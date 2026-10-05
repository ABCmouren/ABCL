/**
 * OptiFineInstaller — OptiFine 安装（对齐 HMCL download/optifine/）
 *
 * 对应 HMCL 的两个类：
 *   OptiFineRemoteVersion  拉可用版本列表
 *     BMCLAPI 接口 {bmclRoot}/optifine/{mcVersion}
 *     特殊映射 1.8 → 1.8.0、1.9 → 1.9.0（OptiFine 自己的命名）
 *     返回项 { mcversion, type, patch }，版本号 = type + "_" + patch
 *
 *   OptiFineInstallTask   真正安装
 *     1. 下载 installer jar
 *     2. 用 optifine.Patcher 把原版 client.jar 打进 OptiFine jar
 *        （installer 里没有 optifine/Patcher.class 时直接复制 installer）
 *     3. 从 installer 取出 launchwrapper-2.0.jar 或 launchwrapper-of-*.jar
 *     4. 删掉产物里的 META-INF/mods.toml
 *     5. 注入依赖 optifine:OptiFine:<mcVersion>_<selfVersion>
 *        没有 OF 自带 launchwrapper 就用 net.minecraft:launchwrapper:1.12
 *     6. 打 --tweakClass optifine.OptiFineTweaker，主类换 launchwrapper
 *
 *   本地安装分支：扫描 installer 内 Config.class 常量池，取
 *   MC_VERSION / OF_EDITION / OF_RELEASE 识别版本，
 *   位置可能是 Config.class、net/optifine/Config.class、
 *   notch/net/optifine/Config.class 三处之一。
 *
 * 第 2 步要跑 java 进程，本项目走 native（dlopen libjvm.so），
 * 所以做成回调由调用方注入。
 */
import { GameInstallation } from '../../model/GameVersion';
import { HttpClient } from '../network/HttpClient';
import { Mirrors } from '../network/Mirrors';
import { DownloadSettings } from '../download/DownloadSettings';
import { ArchiveUtils, FileUtils, Logger } from '../util/Utils';
import { GameDirectoryResolver } from './GameDirectoryResolver';

export interface OptiFineRemoteVersion {
  gameVersion: string;
  selfVersion: string;
  urls: string[];
  isPre: boolean;
  displayName: string;
}

interface BmclOptiFine {
  mcversion?: string;
  type?: string;
  patch?: string;
  filename?: string;
}

export class OptiFineInstaller {
  private static readonly TAG = 'OptiFineInstaller';

  private static toLookupVersion(v: string): string {
    if (v === '1.8') { return '1.8.0'; }
    if (v === '1.9') { return '1.9.0'; }
    return v;
  }

  static async fetchVersions(mcVersion: string): Promise<OptiFineRemoteVersion[]> {
    const lookup = OptiFineInstaller.toLookupVersion(mcVersion);
    const out: OptiFineRemoteVersion[] = [];
    const seen: Set<string> = new Set();

    const urls: string[] = [];
    if (DownloadSettings.useMirror()) {
      urls.push(Mirrors.BMCLAPI_ORIGIN + "/optifine/" + lookup);
      urls.push(Mirrors.MODRINTH_ORIGIN + "/optifine/" + lookup);
    }
    urls.push(Mirrors.BMCLAPI_ORIGIN + "/optifine/" + lookup);

    for (const u of urls) {
      try {
        const res = await HttpClient.getJson<BmclOptiFine[]>(u, OptiFineInstaller.headers(), 20000);
        if (!res.success || !res.data || res.data.length === 0) { continue; }
        for (const item of res.data) {
          const type = item.type ? item.type : "";
          const patch = item.patch ? item.patch : "";
          const mc = item.mcversion ? item.mcversion : "";
          if (type.length === 0 || mc.length === 0) { continue; }
          const selfVersion = type + '_' + patch;
          if (seen.has(selfVersion)) { continue; }
          seen.add(selfVersion);
          const isPre = patch.indexOf('pre') === 0 || patch.indexOf('alpha') === 0;
          out.push({
            gameVersion: mc,
            selfVersion: selfVersion,
            displayName: isPre ? (selfVersion + '（预发布）') : selfVersion,
            isPre: isPre,
            urls: OptiFineInstaller.buildUrls(mc, selfVersion,
              item.filename ? item.filename : "")
          });
        }
        if (out.length > 0) { break; }
      } catch (e) {
        Logger.warn(OptiFineInstaller.TAG, '取版本失败 ' + u);
      }
    }

    out.sort((a: OptiFineRemoteVersion, b: OptiFineRemoteVersion) => {
      if (a.isPre !== b.isPre) { return a.isPre ? 1 : -1; }
      return b.selfVersion.localeCompare(a.selfVersion);
    });
    Logger.info(OptiFineInstaller.TAG, 'OptiFine ' + mcVersion + ' 可用 ' + out.length + ' 个');
    return out;
  }

  /**
   * 请求头。
   * optifine.net 有反爬：裸请求 403，带 User-Agent 与 Referer
   *（模拟从 CurseForge 点进来）即可正常下载。
   */
  private static headers(): Record<string, string> {
    const h: Record<string, string> = {};
    h['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) ABCL/2.0';
    h['Referer'] = 'https://www.curseforge.com/';
    return h;
  }

  private static buildUrls(mcVersion: string, selfVersion: string, filename: string): string[] {
    const lookup = OptiFineInstaller.toLookupVersion(mcVersion);
    const file = filename.length > 0 ? filename :
      ('OptiFine_' + lookup + '_' + selfVersion + '.jar');
    const urls: string[] = [];
    if (DownloadSettings.useMirror()) {
      // BMCLAPI 的下载路径是 {bmcl}/optifine/{mc}/{type}/{patch} —— 两级！
      // selfVersion 形如 HD_U_I7，要拆成 HD_U + I7。
      // 拼成一级（…/{mc}/HD_U_I7）实测 404，两级才 302。
      const seg = OptiFineInstaller.splitTypePatch(selfVersion);
      if (seg !== '') {
        urls.push(Mirrors.BMCLAPI_ORIGIN + '/optifine/' + lookup + '/' + seg);
      }
      urls.push(Mirrors.BMCLAPI_ORIGIN + '/maven/com/optifine/' + lookup + '/' + file);
    }
    urls.push('https://optifine.net/download?filename=' + encodeURIComponent(file));
    return urls;
  }

  /** 把 HD_U_I7 拆成 HD_U/I7；已经是两级形式则原样返回 */
  private static splitTypePatch(selfVersion: string): string {
    // 从右往左找最后一段 patch（通常是 I7 / H8 / G5 这种大写字母+数字）
    const idx = selfVersion.lastIndexOf('_');
    if (idx <= 0 || idx === selfVersion.length - 1) {
      return '';
    }
    const patch = selfVersion.substring(idx + 1);
    if (!/^[A-Za-z]+\\d+$/.test(patch)) {
      return '';
    }
    return selfVersion.substring(0, idx) + '/' + patch;
  }

  static async downloadInstaller(remote: OptiFineRemoteVersion, targetDir: string): Promise<string> {
    FileUtils.mkdirs(targetDir);
    const name = 'OptiFine-' + remote.gameVersion + '_' + remote.selfVersion + '-installer.jar';
    const target = targetDir + '/' + name;
    if (OptiFineInstaller.isValidJar(target)) {
      return target;
    }
    // 上次失败可能留下 44 字节的 HTML 残片（'Error. Please contact…'），
    // 不清掉的话下次会被当成已下载直接跳过。
    if (FileUtils.exists(target)) {
      Logger.info(OptiFineInstaller.TAG, '清理上次失败的残留文件 ' + target);
      FileUtils.delete(target);
    }
    for (const u of remote.urls) {
      try {
        const outcome = await HttpClient.downloadToFile(u, target, 0,
          undefined, false, OptiFineInstaller.headers());
        if (outcome.success && OptiFineInstaller.isValidJar(target)) {
          Logger.info(OptiFineInstaller.TAG, 'installer 下载完成：' + target);
          return target;
        }
        Logger.warn(OptiFineInstaller.TAG, '下载失败 ' + u);
        if (FileUtils.exists(target)) {
          FileUtils.delete(target);
        }
      } catch (e) {
        Logger.warn(OptiFineInstaller.TAG, '下载异常 ' + u);
        if (FileUtils.exists(target)) {
          FileUtils.delete(target);
        }
      }
    }
    return '';
  }

  /** jar 有效性：zip 魔数 PK\x03\x04 + 体积合理 + 不是 HTML 残片 */
  private static isValidJar(path: string): boolean {
    if (!FileUtils.exists(path)) {
      return false;
    }
    const size = FileUtils.getFileSize(path);
    if (size < 1024) {
      return false;
    }
    const head = FileUtils.readFileHead(path, 4);
    return head.length >= 2 && head.charCodeAt(0) === 0x50 && head.charCodeAt(1) === 0x4B;
  }

  static async identifyInstaller(installerPath: string): Promise<OptiFineRemoteVersion | null> {
    const tmp = installerPath + '.probe';
    FileUtils.delete(tmp);
    const ok = await ArchiveUtils.unzip(installerPath, tmp);
    if (!ok) { return null; }
    try {
      const candidates: string[] = [
        tmp + '/Config.class',
        tmp + '/net/optifine/Config.class',
        tmp + '/notch/net/optifine/Config.class'
      ];
      for (const c of candidates) {
        if (!FileUtils.exists(c)) { continue; }
        const cs = OptiFineInstaller.scanUtf8Constants(c);
        const mcV = OptiFineInstaller.constantAfter(cs, 'MC_VERSION');
        const ofE = OptiFineInstaller.constantAfter(cs, 'OF_EDITION');
        const ofR = OptiFineInstaller.constantAfter(cs, 'OF_RELEASE');
        if (mcV.length === 0 || ofE.length === 0 || ofR.length === 0) { continue; }
        const selfVersion = ofE + '_' + ofR;
        Logger.info(OptiFineInstaller.TAG, '识别到 OptiFine ' + selfVersion + ' MC ' + mcV);
        return {
          gameVersion: mcV,
          selfVersion: selfVersion,
          displayName: selfVersion,
          isPre: ofR.indexOf('pre') === 0 || ofR.indexOf('alpha') === 0,
          urls: []
        };
      }
      Logger.warn(OptiFineInstaller.TAG, 'installer 里找不到可识别的 Config.class');
      return null;
    } finally {
      FileUtils.delete(tmp);
    }
  }

  /** 扫描 class 常量池的 UTF8 项（HMCL 用 ConstantPoolScanner，这里最小实现） */
  private static scanUtf8Constants(classPath: string): string[] {
    const out: string[] = [];
    try {
      const bytes = FileUtils.readFileBytes(classPath);
      if (bytes === null || bytes.length < 10) { return out; }
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      let p = 8;
      const count = view.getUint16(p);
      p += 2;
      for (let i = 1; i < count; i++) {
        if (p >= bytes.length) { break; }
        const tag = view.getUint8(p);
        if (tag === 1) {
          const len = view.getUint16(p + 1);
          const start = p + 3;
          if (start + len <= bytes.length) {
            let s = "";
            for (let k = 0; k < len; k++) {
              s += String.fromCharCode(bytes[start + k]);
            }
            out.push(s);
          }
          p += 3 + len;
        } else if (tag === 7 || tag === 8 || tag === 16 || tag === 19 || tag === 20) {
          p += 3;
        } else if (tag === 15) {
          p += 4;
        } else if (tag === 3 || tag === 4 || tag === 9 || tag === 10 || tag === 11 ||
          tag === 12 || tag === 17 || tag === 18) {
          p += 5;
        } else if (tag === 5 || tag === 6) {
          p += 9;
          i++;
        } else {
          break;
        }
      }
    } catch (e) {
      Logger.warn(OptiFineInstaller.TAG, '扫描常量池失败');
    }
    return out;
  }

  private static constantAfter(constants: string[], name: string): string {
    const idx = constants.indexOf(name);
    if (idx < 0 || idx + 1 >= constants.length) { return ""; }
    const next = constants[idx + 1];
    if (next.startsWith('(') || next.startsWith('[') ||
      (next.startsWith('L') && next.endsWith(';'))) { return ''; }
    return next;
  }


  /**
   * 执行安装。返回补完的实例，失败抛错。
   * @param nativeRunner 跑 OptiFine Patcher 的回调（要经 native dlopen
   *        libjvm.so，不能在 core 层直接调）
   */
  static async install(
    inst: GameInstallation,
    remote: OptiFineRemoteVersion,
    nativeRunner: (installerJar: string, vanillaJar: string, outputJar: string) => Promise<boolean>,
  ): Promise<GameInstallation> {
    const mcDir = GameDirectoryResolver.contentRoot(inst);
    const vanillaJar = GameDirectoryResolver.versionsDir() + '/' + remote.gameVersion +
      '/' + remote.gameVersion + '.jar';
    if (!FileUtils.exists(vanillaJar)) {
      throw new Error('找不到原版 jar：' + vanillaJar +
        '，请先安装 Minecraft ' + remote.gameVersion);
    }

    const libsRoot = GameDirectoryResolver.librariesDir() + '/optifine';
    const installerJar = await OptiFineInstaller.downloadInstaller(remote, libsRoot);
    if (installerJar.length === 0) {
      throw new Error('OptiFine installer 下载失败');
    }

    const mavenVersion = remote.gameVersion + '_' + remote.selfVersion;
    const installerLibPath = libsRoot + '/OptiFine/' + mavenVersion + '/OptiFine-' +
      mavenVersion + "-installer.jar";
    const optiFineLibPath = libsRoot + '/OptiFine/' + mavenVersion + '/OptiFine-' +
      mavenVersion + ".jar";
    FileUtils.mkdirs(FileUtils.getDirName(installerLibPath));
    FileUtils.copyFile(installerJar, installerLibPath);

    const tmpDir = mcDir + '/.optifine-tmp';
    FileUtils.mkdirs(tmpDir);
    let hasLaunchWrapper = false;
    const extraLibs: string[] = [];

    try {
      const unpacked = tmpDir + '/unpacked';
      FileUtils.delete(unpacked);
      const ok = await ArchiveUtils.unzip(installerJar, unpacked);
      if (!ok) {
        throw new Error('installer 解包失败');
      }

      if (FileUtils.exists(unpacked + '/optifine/Patcher.class')) {
        const patched = await nativeRunner(installerJar, vanillaJar, optiFineLibPath);
        if (!patched) {
          throw new Error('OptiFine Patcher 执行失败');
        }
      } else {
        FileUtils.copyFile(installerJar, optiFineLibPath);
      }
      FileUtils.delete(unpacked);

      await OptiFineInstaller.removeEntry(optiFineLibPath, 'META-INF/mods.toml');
      await OptiFineInstaller.removeEntry(installerLibPath, 'META-INF/mods.toml');

      const lw2 = await ArchiveUtils.readBinaryEntry(installerJar,
        'launchwrapper-2.0.jar', tmpDir + '/lw2.jar');
      if (lw2.length > 0) {
        const p = libsRoot + '/launchwrapper/2.0/launchwrapper-2.0.jar';
        FileUtils.mkdirs(FileUtils.getDirName(p));
        FileUtils.copyFile(lw2, p);
        extraLibs.push('optifine:launchwrapper:2.0');
        hasLaunchWrapper = true;
      } else {
        const ofVersion = await ArchiveUtils.readTextEntry(installerJar,
          'launchwrapper-of.txt', tmpDir + '/lwv.txt');
        if (ofVersion.length > 0) {
          const ver = ofVersion.trim();
          const jar = await ArchiveUtils.readBinaryEntry(installerJar,
            'launchwrapper-of-' + ver + '.jar', tmpDir + '/lw.jar');
          if (jar.length > 0) {
            const p = libsRoot + '/launchwrapper-of/' + ver + '/launchwrapper-of-' + ver + '.jar';
            FileUtils.mkdirs(FileUtils.getDirName(p));
            FileUtils.copyFile(jar, p);
            extraLibs.push('optifine:launchwrapper-of:' + ver);
            hasLaunchWrapper = true;
          }
        }
      }
      if (!hasLaunchWrapper) {
        extraLibs.push('net.minecraft:launchwrapper:1.12');
      }

      const versionId = remote.gameVersion + '-optifine_' + remote.selfVersion;
      const versionDir = GameDirectoryResolver.versionsDir() + '/' + versionId;
      FileUtils.mkdirs(versionDir);
      FileUtils.copyFile(optiFineLibPath, versionDir + '/' + versionId + '.jar');
      FileUtils.copyFile(vanillaJar, versionDir + '/' + remote.gameVersion + '.jar');

      FileUtils.writeFile(versionDir + '/optifine.install.json',
        OptiFineInstaller.buildPatcherJson(mavenVersion, extraLibs));

      const patched: GameInstallation = {
        versionId: versionId,
        name: inst.name,
        directory: inst.directory,
        gameVersion: remote.gameVersion,
        loaderType: inst.loaderType,
        loaderVersion: inst.loaderVersion,
        installed: true,
        installTime: Date.now(),
        lastPlayed: 0,
        javaArgs: inst.javaArgs,
        minMemory: inst.minMemory,
        maxMemory: inst.maxMemory,
        width: inst.width,
        height: inst.height,
        fullscreen: inst.fullscreen,
        customJvmArgs: inst.customJvmArgs + ' -Dfile.encoding=UTF-8',
        customGameArgs: inst.customGameArgs,
      };
      Logger.info(OptiFineInstaller.TAG,
        'OptiFine ' + remote.selfVersion + ' 安装完成 → ' + versionId);
      return patched;
    } finally {
      FileUtils.delete(tmpDir);
    }
  }

  /** 生成 optifine.install.json（HMCL 的 GameInstancePatch 等价物） */
  private static buildPatcherJson(mavenVersion: string, extraLibs: string[]): string {
    const gameArgs: string[] = [
      '--tweakClass', 'optifine.OptiFineTweaker',
      '--versionType', 'optifine',
      '--version', mavenVersion
    ];
    const libs: string[] = ["optifine:OptiFine:" + mavenVersion];
    for (const l of extraLibs) {
      libs.push(l);
    }
    const libParts: string[] = [];
    for (const l of libs) {
      libParts.push(OptiFineInstaller.jsonString("name") + ":" +
        OptiFineInstaller.jsonString(l));
    }
    const argParts: string[] = [];
    for (const a of gameArgs) {
      argParts.push(OptiFineInstaller.jsonString(a));
    }
    return OptiFineInstaller.jsonString("id") + ":" +
      OptiFineInstaller.jsonString("optifine") + "," +
      OptiFineInstaller.jsonString("version") + ":" +
      OptiFineInstaller.jsonString(mavenVersion) + "," +
      OptiFineInstaller.jsonString("fileId") + ":" +
      OptiFineInstaller.jsonString("optifine") + "," +
      OptiFineInstaller.jsonString("mainClass") + ":" +
      OptiFineInstaller.jsonString("net.minecraft.launchwrapper.Launch") + "," +
      OptiFineInstaller.jsonString("arguments") + ":" +
      OptiFineInstaller.jsonString("game") + ":[" + argParts.join(",") + "]," +
      OptiFineInstaller.jsonString("libraries") + ":[" + libParts.join(",") + "]";
  }

  /** 转义成合法 JSON 字符串字面量（含引号） */
  private static jsonString(raw: string): string {
    // 用 charCode 避开 ArkTS 字符串转义限制
    const DQ = 34;
    const BS = 92;
    let s = String.fromCharCode(DQ);
    for (let i = 0; i < raw.length; i++) {
      const code = raw.charCodeAt(i);
      if (code === DQ || code === BS) {
        s += String.fromCharCode(BS);
      }
      s += raw.charAt(i);
    }
    s += String.fromCharCode(DQ);
    return s;
  }

  /** 从 jar 里删掉一个条目（HMCL: deleteIfExists(zipfs.getPath('/META-INF/mods.toml'))） */
  private static async removeEntry(jarPath: string, entry: string): Promise<void> {
    if (!FileUtils.exists(jarPath)) {
      return;
    }
    const tmp = jarPath + '.rm';
    FileUtils.delete(tmp);
    const ok = await ArchiveUtils.unzip(jarPath, tmp);
    if (!ok) {
      return;
    }
    const target = tmp + "/" + entry;
    if (FileUtils.exists(target)) {
      FileUtils.delete(target);
    }
    FileUtils.delete(jarPath);
    FileUtils.moveFile(tmp, jarPath);
    FileUtils.delete(tmp);
  }
}
