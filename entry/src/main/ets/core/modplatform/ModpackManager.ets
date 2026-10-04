/**
 * ModpackManager — 整合包（Modpack）导入 / 列表 / 安装
 *
 * 对应 HMCL 的 modpack 包：curse/（CurseForge）与 modrinth/ 两种格式，
 * 另外还有 mcbbs/、multimc/、server/。
 * 当前实现 CurseForge 与 Modrinth 两种主流格式。
 *
 * ┌ CurseForge：根目录 manifest.json
 * │   { manifestType:"minecraftModpack", manifestVersion, name, version, author,
 * │     minecraft:{version, modLoaders:[{id:"forge-47.2.0", primary}]},
 * │     files:[{projectID, fileID, required}], overrides:"overrides" }
 * │
 * └ Modrinth：根目录 modrinth.index.json
 *     { game:"minecraft", formatVersion:1, versionId, name, summary,
 *       files:[{path, hashes:{sha1,sha512}, env:{client:"required"}}],
 *       dependencies:{"minecraft":"1.20.1", "fabric-loader":"0.15.7"} }
 *
 * 文件分发位置：overrides/ 目录（CurseForge）与根目录（Modrinth 的 files 路径）。
 */
import zlib from '@ohos.zlib';
import { ArchiveUtils, FileUtils, Logger } from '../util/Utils';
import { Constants } from '../../config/Constants';

export interface ModpackFileRef {
  /** Modrinth 用 path；CurseForge 用 projectID/fileID，这里统一成可读描述 */
  description: string;
  /** 下载直链（Modrinth files 能直接给；CurseForge 只有 ID，要再查 API） */
  url: string;
  /** CurseForge 的项目 / 文件 ID，Modrinth 为空 */
  projectId: string;
  fileId: string;
  sha1: string;
  size: number;
  /** required / optional */
  required: boolean;
}

export interface ModpackManifestInfo {
  format: string;
  name: string;
  version: string;
  author: string;
  summary: string;
  /** Minecraft 版本 */
  minecraftVersion: string;
  /** 加载器名（forge/fabric/neoforge/quilt） */
  loader: string;
  loaderVersion: string;
  /** 相对解压目录的内容根 */
  overridesDir: string;
  fileCount: number;
  hasOverrides: boolean;
}

export interface InstalledModpack {
  /** zip 文件名 */
  fileName: string;
  path: string;
  sizeBytes: number;
  /** 解析出的清单；未解析时 name 回退为文件名 */
  info: ModpackManifestInfo | null;
  metaLoaded: boolean;
}

interface CurseMinecraft {
  version?: string;
  modLoaders?: CurseModLoader[];
}

interface CurseModLoader {
  id?: string;
  primary?: boolean;
}

interface CurseFileRef {
  projectID?: number;
  fileID?: number;
  required?: boolean;
}

interface CurseManifestJson {
  manifestType?: string;
  manifestVersion?: number;
  name?: string;
  version?: string;
  author?: string;
  overrides?: string;
  minecraft?: CurseMinecraft;
  files?: CurseFileRef[];
}

interface ModrinthFileEntry {
  path?: string;
  hashes?: ModrinthHashesEntry;
  env?: ModrinthEnv;
  downloads?: string[];
}

interface ModrinthHashesEntry {
  sha1?: string;
  sha512?: string;
}

interface ModrinthEnv {
  client?: string;
  server?: string;
}

/**
 * Modrinth index 的 dependencies。
 *
 * ArkTS 不支持索引签名（arkts-no-indexed-signatures）也不支持按索引取字段
 * （arkts-no-props-by-index），而 Modrinth 的 loader 键有
 * minecraft / forge / fabric-loader / quilt-loader / neoforge 等多种，
 * 这里把已知类型显式列出来。
 */
type ModpackLoaderKey = 'forge' | 'neoforge' | 'fabric-loader' | 'quilt-loader' | 'legacy-fabric-loader';

interface ModpackDependencies {
  minecraft?: string;
  forge?: string;
  neoforge?: string;
  /** 对应 JSON 里的 "fabric-loader" */
  fabricLoader?: string;
  /** 对应 "quilt-loader" */
  quiltLoader?: string;
  /** 对应 "legacy-fabric-loader" */
  legacyFabricLoader?: string;
}

interface ModrinthIndexJson {
  game?: string;
  formatVersion?: number;
  versionId?: string;
  name?: string;
  summary?: string;
  files?: ModrinthFileEntry[];
  dependencies?: ModpackDependencies;
}

export class ModpackManager {
  private static readonly TAG = 'ModpackManager';

  static modpacksDir(mcDir: string): string {
    return `${mcDir}/${Constants.MODPACKS_DIR}`;
  }

  static tempDir(mcDir: string): string {
    return `${mcDir}/.modpack-tmp`;
  }

  /** 扫描本地整合包 zip */
  static scan(mcDir: string): InstalledModpack[] {
    const dir = ModpackManager.modpacksDir(mcDir);
    const result: InstalledModpack[] = [];
    if (!FileUtils.exists(dir)) {
      return result;
    }
    for (const entry of FileUtils.listDir(dir)) {
      if (!entry.toLowerCase().endsWith('.zip')) {
        continue;
      }
      const full = `${dir}/${entry}`;
      result.push({
        fileName: entry,
        path: full,
        sizeBytes: FileUtils.getFileSize(full),
        info: null,
        metaLoaded: false
      });
    }
    result.sort((a: InstalledModpack, b: InstalledModpack) => b.sizeBytes - a.sizeBytes);
    return result;
  }

  static delete(pack: InstalledModpack): void {
    FileUtils.delete(pack.path);
    Logger.info(ModpackManager.TAG, `删除整合包 ${pack.fileName}`);
  }

  /**
   * 解压 zip 并解析清单。
   * @param installTo 非空表示把 overrides/内容直接铺进该实例目录
   */
  static async inspect(pack: InstalledModpack, extractRoot: string): Promise<ModpackManifestInfo | null> {
    const temp = `${extractRoot}/mp-${Math.abs(ModpackManager.hash(pack.fileName))}`;
    try {
      const ok = await ArchiveUtils.unzip(pack.path, temp);
      if (!ok) {
        Logger.warn(ModpackManager.TAG, `解压失败 ${pack.fileName}`);
        return null;
      }
      const info = ModpackManager.parseDir(temp, pack.fileName);
      if (info !== null) {
        Logger.info(ModpackManager.TAG,
          `解析整合包 ${pack.fileName} → ${info.format} ${info.name} ` +
          `(MC ${info.minecraftVersion} · ${info.loader} ${info.loaderVersion} · ${info.fileCount} 文件)`);
      } else {
        Logger.warn(ModpackManager.TAG, `${pack.fileName} 不是受支持的整合包格式`);
      }
      return info;
    } catch (e) {
      Logger.error(ModpackManager.TAG, `解析 ${pack.fileName} 失败`, e as Error);
      return null;
    }
  }

  /** 在已解压目录里找 manifest 并解析 */
  static parseDir(dir: string, fallbackName: string): ModpackManifestInfo | null {
    const modrinthPath = `${dir}/modrinth.index.json`;
    if (FileUtils.exists(modrinthPath)) {
      return ModpackManager.parseModrinth(FileUtils.readFile(modrinthPath), fallbackName, dir);
    }
    const cursePath = `${dir}/manifest.json`;
    if (FileUtils.exists(cursePath)) {
      return ModpackManager.parseCurse(FileUtils.readFile(cursePath), fallbackName, dir);
    }
    // 有些整合包把 manifest.json 放在 overrides 里
    const nested = `${dir}/overrides/manifest.json`;
    if (FileUtils.exists(nested)) {
      return ModpackManager.parseCurse(FileUtils.readFile(nested), fallbackName, dir);
    }
    return null;
  }

  private static parseCurse(text: string, fallbackName: string, dir: string): ModpackManifestInfo | null {
    try {
      const m = JSON.parse(text) as CurseManifestJson;
      if (m.manifestType !== undefined && m.manifestType !== 'minecraftModpack') {
        return null;
      }
      let mcVersion = '';
      let loader = '';
      let loaderVersion = '';
      if (m.minecraft) {
        mcVersion = m.minecraft.version ? m.minecraft.version : '';
        const loaders = m.minecraft.modLoaders ? m.minecraft.modLoaders : [];
        let chosen: CurseModLoader | null = null;
        for (const l of loaders) {
          if (l.primary) {
            chosen = l;
            break;
          }
        }
        if (chosen === null && loaders.length > 0) {
          chosen = loaders[0];
        }
        if (chosen !== null && chosen.id) {
          // id 形如 "forge-47.2.0" / "fabric-0.15.7"
          const dash = chosen.id.indexOf('-');
          if (dash > 0) {
            loader = chosen.id.substring(0, dash);
            loaderVersion = chosen.id.substring(dash + 1);
          } else {
            loader = chosen.id;
          }
        }
      }
      const files = m.files ? m.files : [];
      const overridesName = m.overrides ? m.overrides : 'overrides';
      const info: ModpackManifestInfo = {
        format: 'curseforge',
        name: m.name ? m.name : fallbackName.replace(/\.zip$/i, ''),
        version: m.version ? m.version : '',
        author: m.author ? m.author : '',
        summary: '',
        minecraftVersion: mcVersion,
        loader: loader,
        loaderVersion: loaderVersion,
        overridesDir: `${dir}/${overridesName}`,
        fileCount: files.length,
        hasOverrides: FileUtils.exists(`${dir}/${overridesName}`)
      };
      return info;
    } catch (e) {
      return null;
    }
  }

  /**
   * 预扫描 dependencies 段，文本归一化出键值。
   *
   * 为什么不用 JSON.parse 的 dependencies：
   * ArkTS 禁止索引签名与按索引取字段（arkts-no-indexed-signatures /
   * arkts-no-props-by-index），而 Modrinth 的 loader 键是
   * "fabric-loader" / "quilt-loader" 这种带连字符的形式，
   * 连字符字段在 ArkTS 里也无法点号访问。
   * 所以这里对 dependencies 那一段做一次轻量文本提取。
   */
  private static scanDeps(text: string): string[] {
    const found: string[] = [];
    const key = '"dependencies"';
    const start = text.indexOf(key);
    if (start < 0) {
      return found;
    }
    const open = text.indexOf('{', start);
    if (open < 0) {
      return found;
    }
    // 找到配对的右花括号
    let depth = 0;
    let end = -1;
    for (let i = open; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) {
      return found;
    }
    const body = text.substring(open + 1, end);
    // 逐条匹配 "key": "value"
    const re = /"([^"]+)"\s*:\s*"([^"]*)"/g;
    let m: RegExpExecArray | null = re.exec(body);
    while (m !== null) {
      found.push(m[1] + '=' + m[2]);
      m = re.exec(body);
    }
    return found;
  }

  private static depValue(deps: string[], name: string): string {
    const prefix = name + '=';
    for (const entry of deps) {
      if (entry.indexOf(prefix) === 0) {
        return entry.substring(prefix.length);
      }
    }
    return '';
  }

  private static parseModrinth(text: string, fallbackName: string, dir: string): ModpackManifestInfo | null {
    try {
      const m = JSON.parse(text) as ModrinthIndexJson;
      if (m.game !== undefined && m.game !== 'minecraft') {
        return null;
      }
      let mcVersion = '';
      let loader = '';
      let loaderVersion = '';
      // 从 dependencies 段文本提取（避免 ArkTS 的索引访问限制）
      const deps: string[] = ModpackManager.scanDeps(text);
      mcVersion = ModpackManager.depValue(deps, 'minecraft');
      // ⚠️ 顺序即优先级：整合包通常只声明一个加载器，但有的会同时留多个
      // （例如从 Forge 迁 Fabric 的包会同时留着两行）。
      // Modrinth 官方索引的惯例是按 forge / neoforge / fabric / quilt 排列，
      // 但真实数据里 fabric 更常见，放前面更符合多数整合包。
      const loaderKeys: ModpackLoaderKey[] = [
        'fabric-loader', 'quilt-loader', 'forge', 'neoforge', 'legacy-fabric-loader'
      ];
      for (const key of loaderKeys) {
        const value: string = ModpackManager.depValue(deps, key);
        if (value.length > 0) {
          loaderVersion = value;
          loader = key.indexOf('-loader') >= 0 ? key.substring(0, key.indexOf('-loader')) : key;
          break;
        }
      }
      const files = m.files ? m.files : [];
      const info: ModpackManifestInfo = {
        format: 'modrinth',
        name: m.name ? m.name : fallbackName.replace(/\.zip$/i, ''),
        version: m.versionId ? m.versionId : '',
        author: '',
        summary: m.summary ? m.summary : '',
        minecraftVersion: mcVersion,
        loader: loader,
        loaderVersion: loaderVersion,
        // Modrinth 的 files.path 是相对包根的
        overridesDir: dir,
        fileCount: files.length,
        hasOverrides: files.length > 0
      };
      return info;
    } catch (e) {
      return null;
    }
  }

  /** Modrinth 清单里的文件下载列表 */
  static async readModrinthFiles(dir: string): Promise<ModpackFileRef[]> {
    const path = `${dir}/modrinth.index.json`;
    if (!FileUtils.exists(path)) {
      return [];
    }
    try {
      const m = JSON.parse(FileUtils.readFile(path)) as ModrinthIndexJson;
      const out: ModpackFileRef[] = [];
      for (const f of (m.files ? m.files : [])) {
        const sha1 = f.hashes && f.hashes.sha1 ? f.hashes.sha1 : '';
        const downloads = f.downloads ? f.downloads : [];
        const ref: ModpackFileRef = {
          description: f.path ? f.path.split('/').pop() || (f.path as string) : 'file',
          url: downloads.length > 0 ? downloads[0] : '',
          projectId: '',
          fileId: '',
          sha1: sha1,
          size: 0,
          required: f.env !== undefined && f.env.client !== undefined ? f.env.client !== 'optional' : true
        };
        out.push(ref);
      }
      return out;
    } catch (e) {
      Logger.warn(ModpackManager.TAG, `读取 modrinth.index.json 失败: ${(e as Error).message}`);
      return [];
    }
  }

  /** 把整合包内容铺进实例目录：复制 overrides/ 与可选的客户端配置目录 */
  static applyOverrides(info: ModpackManifestInfo, extractDir: string, targetMcDir: string): number {
    let copied = 0;
    const src = info.overridesDir;
    if (FileUtils.exists(src)) {
      copied += ModpackManager.copyTree(src, targetMcDir);
    }
    // Modrinth：把 index 里声明的文件从包内 copy 到 target
    if (info.format === 'modrinth') {
      const files = FileUtils.exists(`${extractDir}/modrinth.index.json`)
        ? ModpackManager.modrinthDeclared(extractDir)
        : '';
      if (files.length > 0) {
        for (const rel of files) {
          const from = `${extractDir}/${rel}`;
          if (FileUtils.exists(from)) {
            const to = `${targetMcDir}/${rel}`;
            FileUtils.mkdirs(FileUtils.getDirName(to));
            FileUtils.copyFile(from, to);
            copied++;
          }
        }
      }
    }
    Logger.info(ModpackManager.TAG, `应用整合包内容到 ${targetMcDir}，复制 ${copied} 项`);
    return copied;
  }

  private static modrinthDeclared(extractDir: string): string[] {
    try {
      const m = JSON.parse(FileUtils.readFile(`${extractDir}/modrinth.index.json`)) as ModrinthIndexJson;
      const out: string[] = [];
      for (const f of (m.files ? m.files : [])) {
        if (f.path) {
          out.push(f.path);
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  private static copyTree(srcDir: string, targetDir: string): number {
    let n = 0;
    for (const entry of FileUtils.listDir(srcDir)) {
      const from = `${srcDir}/${entry}`;
      const to = `${targetDir}/${entry}`;
      if (FileUtils.isDirectory(from)) {
        FileUtils.mkdirs(to);
        n += ModpackManager.copyTree(from, to);
      } else {
        FileUtils.mkdirs(FileUtils.getDirName(to));
        FileUtils.copyFile(from, to);
        n++;
      }
    }
    return n;
  }

  /**
   * 生成两个标准格式的测试整合包（CurseForge + Modrinth）。
   *
   * 用途：在没有真实整合包、且 hdc 无权写 app 沙箱的环境里，
   * 用 @ohos.zlib.compressFile 走真实打包路径，
   * 验证「扫描 → 解压 → 解析清单 → 应用 overrides」这条链路。
   * manifest 内容按 CurseForge / Modrinth 的公开格式书写。
   */
  static async seedDemoModpacks(mcDir: string): Promise<number> {
    const dir = ModpackManager.modpacksDir(mcDir);
    if (FileUtils.exists(dir) && FileUtils.listDir(dir).length > 0) {
      return 0;
    }
    FileUtils.mkdirs(dir);
    const stage = `${mcDir}/.modpack-seed`;
    let made = 0;

    // ---- CurseForge ----
    const curseRoot = `${stage}/curse`;
    FileUtils.writeFile(`${curseRoot}/manifest.json`,
      '{"manifestType":"minecraftModpack","manifestVersion":1,' +
      '"name":"Demo All The Mods","version":"1.0.2","author":"Demo Author",' +
      '"overrides":"overrides",' +
      '"minecraft":{"version":"1.20.1","modLoaders":[{"id":"forge-47.3.0","primary":true}]},' +
      '"files":[{"projectID":238222,"fileID":4712198,"required":true},' +
      '{"projectID":57073,"fileID":4712200,"required":false}]}');
    FileUtils.writeFile(`${curseRoot}/overrides/config/demo.json`, '{"demo":true}');
    FileUtils.writeFile(`${curseRoot}/mods/demo-mod.jar`, 'demo-jar-bytes');
    try {
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      };
      await zlib.compressFile(curseRoot, `${dir}/DemoAllTheMods.zip`, options);
      made++;
      Logger.info(ModpackManager.TAG, '已生成 CurseForge 演示整合包');
    } catch (e) {
      Logger.error(ModpackManager.TAG, '生成 CurseForge 演示包失败', e as Error);
    }

    // ---- Modrinth ----
    const mrRoot = `${stage}/modrinth`;
    FileUtils.writeFile(`${mrRoot}/modrinth.index.json`,
      '{"game":"minecraft","formatVersion":1,"versionId":"demo0001",' +
      '"name":"Demo Modrinth Pack","summary":"A demo modpack",' +
      '"files":[{"path":"mods/demo-mod.jar","hashes":{"sha1":"demo","sha512":"demo2"},' +
      '"env":{"client":"required"},"downloads":[]}],' +
      '"dependencies":{"minecraft":"1.21.1","fabric-loader":"0.15.11","forge":"47.4.0"}}');
    FileUtils.writeFile(`${mrRoot}/mods/demo-mod.jar`, 'demo-jar-bytes');
    try {
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      };
      await zlib.compressFile(mrRoot, `${dir}/DemoModrinthPack.zip`, options);
      made++;
      Logger.info(ModpackManager.TAG, '已生成 Modrinth 演示整合包');
    } catch (e) {
      Logger.error(ModpackManager.TAG, '生成 Modrinth 演示包失败', e as Error);
    }

    FileUtils.delete(stage);
    return made;
  }

  /** 空 dependencies（ArkTS 不允许直接写 {} 字面量） */
  private static emptyDeps(): ModpackDependencies {
    const d: ModpackDependencies = {
      minecraft: '',
      forge: '',
      neoforge: '',
      fabricLoader: '',
      quiltLoader: '',
      legacyFabricLoader: ''
    };
    return d;
  }

  /** 显式读取某个 loader 键（不能按字符串索引） */
  private static readDep(deps: ModpackDependencies, key: ModpackLoaderKey): string | undefined {
    if (key === 'forge') {
      return deps.forge;
    }
    if (key === 'neoforge') {
      return deps.neoforge;
    }
    if (key === 'fabric-loader') {
      return deps.fabricLoader;
    }
    if (key === 'quilt-loader') {
      return deps.quiltLoader;
    }
    return deps.legacyFabricLoader;
  }

  /** 供页面计算解压临时目录名，保持与 inspect() 一致 */
  static hashOf(fileName: string): number {
    return Math.abs(ModpackManager.hash(fileName));
  }

  private static hash(input: string): number {
    let h = 0;
    for (let i = 0; i < input.length; i++) {
      h = ((h << 5) - h) + input.charCodeAt(i);
      h = h & h;
    }
    return h;
  }
}
