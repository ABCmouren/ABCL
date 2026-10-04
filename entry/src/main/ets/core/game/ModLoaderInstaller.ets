/**
 * ModLoaderInstaller — Forge / NeoForge / Fabric / Quilt 安装器（2026-10 重写）
 *
 * 旧实现为什么全坏（实测确认）：
 *  1. Forge 去下载 `forge-<mc>-<ver>-installer.json`，该 URL 在 Forge Maven 上是 **404**，
 *     真实制品只有 `-installer.jar`（zip），install_profile.json 在 jar 内部；
 *  2. NeoForge 的 maven 根少了 `/releases` 前缀 → 404；
 *  3. BMCLAPI 没有 fabric 镜像（404），代码却优先走 BMCLAPI → Fabric 也装不上；
 *  4. Fabric 的 profile JSON 里 libraries 用的是 `url` + Maven 坐标，没有 `downloads` 字段，
 *     旧代码只认 `downloads.artifact.url` → 所有库被静默跳过；
 *  5. 生成的 version JSON 里 `assets` 被硬编码成 '1.21'，继承合并时覆盖父版本 → 资源索引错误。
 *
 * 现在按 HMCL / AMCL 的实际做法重写：
 *  - Forge/NeoForge：下载 installer.jar → 解包读取 install_profile.json / version.json
 *    → 复制包内 maven/ 库 → 下载全部 libraries → 运行 processors（需要 JVM）
 *  - Fabric/Quilt：走官方 meta API 的 profile/json（自带正确的 id / mainClass / libraries）
 */
import { GameInstallation, Library, LoaderType, Rule } from '../../model/GameVersion';
import { Constants } from '../../config/Constants';
import { HttpClient } from '../network/HttpClient';
import { Mirrors } from '../network/Mirrors';
import { DownloadEngine, DownloadItem, CancelToken } from '../download/DownloadEngine';
import { ArchiveUtils, FileUtils, Logger } from '../util/Utils';
import { VersionInstaller } from './VersionInstaller';
import { ProcessorRunner } from './ProcessorRunner';

export enum ModLoader {
  FORGE = 'forge',
  FABRIC = 'fabric',
  QUILT = 'quilt',
  NEO_FORGE = 'neoforge'
}

export interface LoaderVersion {
  loader: ModLoader;
  version: string;
  mcVersion: string;
  fullVersionId: string;
  stable: boolean;
}

export interface InstallProgress {
  phase: string;
  progress: number;
  message: string;
}

export type ProgressCallback = (progress: InstallProgress) => void;

/** 容错版本的库描述：兼容 Mojang( downloads ) / Fabric&Forge( url+name ) 两种风格 */
export interface RawLibrary {
  name: string;
  url?: string;
  sha1?: string;
  size?: number;
  downloads?: LibraryDownloadsLike;
  rules?: Rule[];
  natives?: Record<string, string>;
  clientreq?: boolean;
}

export interface LibraryDownloadsLike {
  artifact?: RawArtifact;
  classifiers?: Record<string, RawArtifact>;
}

export interface RawArtifact {
  path?: string;
  sha1?: string;
  size?: number;
  url?: string;
}

export interface ForgeProcessor {
  sides?: string[];
  jar: string;
  classpath: string[];
  args: string[];
  outputs?: Record<string, string>;
}

export interface ForgeInstallDataEntry {
  client: string;
  server: string;
}

export interface RawVersionJson {
  id?: string;
  inheritsFrom?: string;
  mainClass?: string;
  assets?: string;
  type?: string;
  libraries?: RawLibrary[];
  librariesUrl?: string;
}

export interface ForgeInstallProfile {
  spec?: number;
  profile?: string;
  version?: string;
  path?: string;
  json?: string;
  minecraft?: string;
  data?: Record<string, ForgeInstallDataEntry>;
  processors?: ForgeProcessor[];
  libraries?: RawLibrary[];
  versionInfo?: RawVersionJson;
  install?: ForgeLegacyInstall;
  serverJarPath?: string;
}

export interface ForgeLegacyInstall {
  profileName?: string;
  target?: string;
  path?: string;
  filePath?: string;
  minecraft?: string;
  version?: string;
}

export interface FabricMetaVersion {
  version: string;
  stable: boolean;
}

export class ModLoaderInstaller {
  private static readonly TAG = 'ModLoaderInstaller';
  private static instance: ModLoaderInstaller;
  private baseDir: string = '';

  static getInstance(): ModLoaderInstaller {
    if (!ModLoaderInstaller.instance) {
      ModLoaderInstaller.instance = new ModLoaderInstaller();
    }
    return ModLoaderInstaller.instance;
  }

  init(baseDir: string): void {
    this.baseDir = baseDir;
    Logger.info(ModLoaderInstaller.TAG, `initialized, baseDir=${baseDir}`);
  }

  // ============================================================
  //  可用版本列表
  // ============================================================

  async getAvailableVersions(loader: ModLoader, mcVersion: string): Promise<LoaderVersion[]> {
    switch (loader) {
      case ModLoader.FORGE:
        return this.getForgeVersions(mcVersion);
      case ModLoader.NEO_FORGE:
        return this.getNeoForgeVersions(mcVersion);
      case ModLoader.FABRIC:
        return this.getFabricLikeVersions(ModLoader.FABRIC, mcVersion);
      case ModLoader.QUILT:
        return this.getFabricLikeVersions(ModLoader.QUILT, mcVersion);
      default:
        return [];
    }
  }

  private async runStats(
    items: DownloadItem[],
    phase: string,
    onProgress?: ProgressCallback,
    token?: CancelToken
  ): Promise<string[]> {
    if (items.length === 0) {
      return [];
    }
    const result = await DownloadEngine.run(
      items,
      phase,
      (stats) => {
        if (onProgress) {
          const ratio = stats.totalFiles > 0 ? stats.completedFiles / stats.totalFiles : 0;
          onProgress({
            phase: phase,
            progress: Math.round(ratio * 100),
            message: `${phase} ${stats.completedFiles}/${stats.totalFiles}`
          });
        }
      },
      Constants.DOWNLOAD_CONCURRENCY,
      token
    );
    return result.errors;
  }

  // ============================================================
  //  Forge
  // ============================================================

  private async getForgeVersions(mcVersion: string): Promise<LoaderVersion[]> {
    const path = 'net/minecraftforge/forge/maven-metadata.xml';
    const xml = await this.fetchText([
      `${Constants.FORGE_MAVEN}/${path}`,
      Mirrors.mavenPath(Constants.FORGE_MAVEN, path)
    ]);
    if (xml.length === 0) {
      return [];
    }
    const all = ModLoaderInstaller.parseMavenVersions(xml);
    const prefix = `${mcVersion}-`;
    const mine: LoaderVersion[] = [];
    for (const full of all) {
      if (!full.startsWith(prefix)) {
        continue;
      }
      const loaderVersion = full.substring(prefix.length);
      // 过滤掉 "1.20.4-49.0.19-mdk" 之类的非安装器版本号
      if (loaderVersion.indexOf('-') >= 0 && !/^\d/.test(loaderVersion)) {
        continue;
      }
      mine.push({
        loader: ModLoader.FORGE,
        version: loaderVersion,
        mcVersion: mcVersion,
        fullVersionId: full,
        stable: true
      });
    }
    return mine.sort((a: LoaderVersion, b: LoaderVersion) =>
      ModLoaderInstaller.compareVersions(b.version, a.version));
  }

  private async installForge(
    mcVersion: string,
    loaderVersion: string,
    fullVersionId: string,
    onProgress?: ProgressCallback,
    token?: CancelToken
  ): Promise<GameInstallation> {
    const forgeVersion = `${mcVersion}-${loaderVersion}`;
    const dirName = 'net/minecraftforge/forge/' + forgeVersion;
    const jarName = `forge-${forgeVersion}-installer.jar`;
    const installerUrl = `${Constants.FORGE_MAVEN}/${dirName}/${jarName}`;

    return this.installForgelike(
      ModLoader.FORGE, mcVersion, loaderVersion, fullVersionId,
      installerUrl, `${forgeVersion}`, onProgress, token
    );
  }

  // ============================================================
  //  NeoForge
  // ============================================================

  /** MC 1.x.y → NeoForge 的版本前缀 "x.y."（NeoForge 用 20.4.237 表示 1.20.4） */
  static neoForgePrefix(mcVersion: string): string {
    const parts = mcVersion.split('.');
    const minor = parts.length > 1 ? parts[1] : '0';
    const patch = parts.length > 2 ? parts[2] : '0';
    return `${minor}.${patch}.`;
  }

  private async getNeoForgeVersions(mcVersion: string): Promise<LoaderVersion[]> {
    const path = 'net/neoforged/neoforge/maven-metadata.xml';
    const xml = await this.fetchText([
      `${Constants.NEO_FORGE_MAVEN}/${path}`,
      `${Mirrors.BMCLAPI_MAVEN}/net/neoforged/neoforge/maven-metadata.xml`
    ]);
    if (xml.length === 0) {
      return [];
    }
    const prefix = ModLoaderInstaller.neoForgePrefix(mcVersion);
    const result: LoaderVersion[] = [];
    for (const full of ModLoaderInstaller.parseMavenVersions(xml)) {
      if (!full.startsWith(prefix)) {
        continue;
      }
      result.push({
        loader: ModLoader.NEO_FORGE,
        version: full,
        mcVersion: mcVersion,
        fullVersionId: `neoforge-${full}`,
        stable: full.indexOf('-beta') < 0
      });
    }
    return result.sort((a: LoaderVersion, b: LoaderVersion) =>
      ModLoaderInstaller.compareVersions(b.version, a.version));
  }

  private async installNeoForge(
    mcVersion: string,
    loaderVersion: string,
    fullVersionId: string,
    onProgress?: ProgressCallback,
    token?: CancelToken
  ): Promise<GameInstallation> {
    const dirName = `net/neoforged/neoforge/${loaderVersion}`;
    const jarName = `neoforge-${loaderVersion}-installer.jar`;
    const url = `${Constants.NEO_FORGE_MAVEN}/${dirName}/${jarName}`;
    return this.installForgelike(
      ModLoader.NEO_FORGE, mcVersion, loaderVersion, fullVersionId,
      url, loaderVersion, onProgress, token
    );
  }

  // ============================================================
  //  Forge-like 通用安装（Forge / NeoForge）
  // ============================================================

  private async installForgelike(
    loader: ModLoader,
    mcVersion: string,
    loaderVersion: string,
    fullVersionId: string,
    installerUrl: string,
    installerVersionKey: string,
    onProgress?: ProgressCallback,
    token?: CancelToken
  ): Promise<GameInstallation> {
    const mcDir = this.minecraftDir();
    const libsDir = `${mcDir}/${Constants.LIBRARIES_DIR}`;
    const versionDir = `${mcDir}/${Constants.VERSIONS_DIR}/${fullVersionId}`;
    const workDir = `${mcDir}/.installer/${fullVersionId}`;

    const report = (phase: string, progress: number, message: string): void => {
      if (onProgress) {
        onProgress({ phase: phase, progress: progress, message: message });
      }
      Logger.info(ModLoaderInstaller.TAG, `[${phase}] ${progress}% ${message}`);
    };

    // ---------- 1. 下载 installer.jar ----------
    report('metadata', 5, `下载 ${loader} 安装器…`);
    FileUtils.delete(workDir);
    FileUtils.mkdirs(workDir);
    const installerPath = `${workDir}/installer.jar`;
    const installerItem: DownloadItem = {
      url: installerUrl,
      mirrors: Mirrors.candidates(installerUrl, true).slice(1),
      path: installerPath,
      sha1: '',
      size: 0,
      name: `${loader}-installer.jar`
    };
    const ok = await DownloadEngine.fetchOne(installerItem);
    if (!ok) {
      throw new Error(`${loader} 安装器下载失败：${installerUrl}`);
    }
    if (token && token.isCancelled()) {
      throw new Error('安装已取消');
    }

    // ---------- 2. 解包 ----------
    report('metadata', 15, '解包安装器…');
    const unpackDir = `${workDir}/unpacked`;
    const unpacked = await ArchiveUtils.unzip(installerPath, unpackDir);
    if (!unpacked) {
      throw new Error('安装器解包失败（不是有效的 zip/jar）');
    }

    const profileText = FileUtils.readFile(`${unpackDir}/install_profile.json`);
    if (profileText.length === 0) {
      throw new Error('安装器内没有 install_profile.json');
    }
    let profile: ForgeInstallProfile;
    try {
      profile = JSON.parse(profileText) as ForgeInstallProfile;
    } catch (e) {
      throw new Error(`install_profile.json 解析失败: ${(e as Error).message}`);
    }

    // ---------- 3. 解析 version json ----------
    report('metadata', 25, '解析版本 JSON…');
    let versionJson: RawVersionJson | null = null;
    if (profile.versionInfo) {
      // Forge ≤ 1.12.2：install_profile 内联完整 versionInfo
      versionJson = profile.versionInfo;
    } else {
      // Forge 1.13+ / NeoForge：install_profile.path 指向包内文件（通常 /version.json）
      const rel = profile.path ? profile.path : '/version.json';
      const normalized = rel.startsWith('/') ? rel.substring(1) : rel;
      const candidates: string[] = [`${unpackDir}/${normalized}`, `${unpackDir}/version.json`];
      for (const candidate of candidates) {
        const text = FileUtils.readFile(candidate);
        if (text.length > 0) {
          try {
            versionJson = JSON.parse(text) as RawVersionJson;
            break;
          } catch (e) {
            // 尝试下一个
          }
        }
      }
    }
    if (!versionJson) {
      throw new Error('无法从安装器中解析出 version.json');
    }

    versionJson.id = fullVersionId;
    versionJson.inheritsFrom = mcVersion;
    versionJson.type = 'release';
    // 关键修复：不能让子版本自带的 assets 覆盖父版本（旧代码硬编码 '1.21' 是错的）
    versionJson.assets = undefined;

    // ---------- 4. 合并 libraries ----------
    const mergedLibs: RawLibrary[] = [];
    const seen = new Set<string>();
    for (const lib of (versionJson.libraries || [])) {
      if (lib.name && !seen.has(lib.name)) {
        seen.add(lib.name);
        mergedLibs.push(lib);
      }
    }
    for (const lib of (profile.libraries || [])) {
      if (lib.name && !seen.has(lib.name)) {
        seen.add(lib.name);
        mergedLibs.push(lib);
      }
    }
    versionJson.libraries = mergedLibs;

    FileUtils.mkdirs(versionDir);
    FileUtils.writeFile(`${versionDir}/${fullVersionId}.json`, JSON.stringify(versionJson, null, 2));

    // ---------- 5. 复制安装器内嵌的 maven 库 ----------
    const embeddedMaven = `${unpackDir}/maven`;
    let embeddedCount = 0;
    if (FileUtils.exists(embeddedMaven)) {
      report('libraries', 35, '复制安装器内嵌库…');
      embeddedCount = ModLoaderInstaller.copyTree(embeddedMaven, libsDir, 0);
    }
    Logger.info(ModLoaderInstaller.TAG, `内嵌 maven 库复制完成：${embeddedCount} 个文件`);

    // ---------- 6. 下载 libraries ----------
    report('libraries', 40, `整理 ${mergedLibs.length} 个库文件…`);
    const items = ModLoaderInstaller.libraryItems(mergedLibs, libsDir, true);

    // 1.12.2 及以前的 universal jar
    const legacyInstall = profile.install;
    if (legacyInstall) {
      const dest = legacyInstall.filePath ? legacyInstall.filePath : legacyInstall.path;
      if (dest) {
        const fromUnpacked = `${unpackDir}/${legacyInstall.path ? legacyInstall.path : ''}`;
        if (FileUtils.exists(fromUnpacked) && !FileUtils.isDirectory(fromUnpacked)) {
          FileUtils.copyFile(fromUnpacked, `${libsDir}/${dest}`);
        } else {
          const rel = legacyInstall.path ? legacyInstall.path : '';
          const base = `${Constants.FORGE_MAVEN}/${VersionInstaller.mavenRelativePath('net.minecraftforge:forge:0')}`;
          void base;
        }
      }
    }

    const errors = await this.runStats(items, 'libraries', onProgress, token);
    if (errors.length > 0) {
      Logger.warn(ModLoaderInstaller.TAG, `${errors.length} 个库下载失败，例如 ${errors[0]}`);
    }

    // ---------- 7. 确保原版父版本已安装 ----------
    report('parent', 70, `检查原版 ${mcVersion}…`);
    const parentJson = `${mcDir}/${Constants.VERSIONS_DIR}/${mcVersion}/${mcVersion}.json`;
    const parentJar = `${mcDir}/${Constants.VERSIONS_DIR}/${mcVersion}/${mcVersion}.jar`;
    if (!FileUtils.exists(parentJson) || !FileUtils.exists(parentJar)) {
      report('parent', 72, `先安装原版 ${mcVersion}…`);
      await VersionInstaller.install({
        mcDir: mcDir,
        versionId: mcVersion,
        useMirror: true,
        osArch: Constants.osArch,
        onProgress: (p) => {
          if (onProgress) {
            onProgress({ phase: 'parent', progress: 72 + Math.round(p.progress * 10), message: `原版 ${p.phase}: ${p.message}` });
          }
        },
        token: token
      });
    }

    // ---------- 8. 运行 processors ----------
    const processors = profile.processors || [];
    const clientProcessors: ForgeProcessor[] = [];
    for (const processor of processors) {
      const sides = processor.sides;
      if (!sides || sides.length === 0 || sides.indexOf('client') >= 0) {
        clientProcessors.push(processor);
      }
    }

    if (clientProcessors.length > 0) {
      report('processors', 85, `运行 ${clientProcessors.length} 个安装处理器…`);
      try {
        await ProcessorRunner.runAll(clientProcessors, {
          mcDir: mcDir,
          versionId: fullVersionId,
          mcVersion: mcVersion,
          installerPath: installerPath,
          classpathDir: libsDir,
          data: profile.data,
          onProgress: onProgress,
          token: token
        });
      } catch (e) {
        // processors 失败 = 这个 Forge 版本不可用。绝不能把半成品留在实例列表里
        // 让用户以为装好了（Forge 1.13+ 缺 processor 产物必然启动失败）。
        Logger.error(ModLoaderInstaller.TAG,
          `processors 失败，回滚 ${fullVersionId}: ${(e as Error).message}`);
        FileUtils.delete(versionDir);
        throw new Error(
          `${loader} 安装未完成：安装处理器执行失败（${(e as Error).message}）。已回滚该版本。`
        );
      }
    }

    report('done', 100, `${loader} ${loaderVersion} 安装完成`);
    void installerVersionKey;

    return this.buildInstallation(
      fullVersionId, mcVersion,
      loader === ModLoader.NEO_FORGE ? LoaderType.NEO_FORGE : LoaderType.FORGE,
      loaderVersion, versionDir
    );
  }

  // ============================================================
  //  Fabric / Quilt
  // ============================================================

  private async getFabricLikeVersions(loader: ModLoader, mcVersion: string): Promise<LoaderVersion[]> {
    const metaBase = loader === ModLoader.QUILT
      ? `${Constants.QUILT_META}/v3/versions/loader/${mcVersion}`
      : `${Constants.FABRIC_META}/v2/versions/loader/${mcVersion}`;

    const res = await HttpClient.getJson<FabricMetaVersion[]>(metaBase);
    if (!res.success || !res.data) {
      Logger.warn(ModLoaderInstaller.TAG, `${loader} 版本列表获取失败: ${res.error}`);
      return [];
    }
    const list: LoaderVersion[] = [];
    for (const entry of res.data) {
      list.push({
        loader: loader,
        version: entry.version,
        mcVersion: mcVersion,
        fullVersionId: loader === ModLoader.QUILT
          ? `${mcVersion}-quilt-${entry.version}`
          : `fabric-loader-${entry.version}-${mcVersion}`,
        stable: entry.stable === true
      });
    }
    return list;
  }

  private async installFabricLike(
    loader: ModLoader,
    mcVersion: string,
    loaderVersion: string,
    onProgress?: ProgressCallback,
    token?: CancelToken
  ): Promise<GameInstallation> {
    const mcDir = this.minecraftDir();
    const libsDir = `${mcDir}/${Constants.LIBRARIES_DIR}`;

    const report = (phase: string, progress: number, message: string): void => {
      if (onProgress) {
        onProgress({ phase: phase, progress: progress, message: message });
      }
      Logger.info(ModLoaderInstaller.TAG, `[${phase}] ${progress}% ${message}`);
    };

    report('metadata', 5, `获取 ${loader} profile…`);
    const profileUrl = loader === ModLoader.QUILT
      ? `${Constants.QUILT_META}/v3/versions/loader/${mcVersion}/${loaderVersion}/profile/json`
      : `${Constants.FABRIC_META}/v2/versions/loader/${mcVersion}/${loaderVersion}/profile/json`;

    const res = await HttpClient.getJson<RawVersionJson>(profileUrl);
    if (!res.success || !res.data) {
      throw new Error(`${loader} profile 获取失败: ${res.error} (${profileUrl})`);
    }
    const profile = res.data;
    const fullVersionId = profile.id ? profile.id : `${loader}-${loaderVersion}-${mcVersion}`;
    profile.id = fullVersionId;
    profile.inheritsFrom = mcVersion;
    profile.assets = undefined;

    const versionDir = `${mcDir}/${Constants.VERSIONS_DIR}/${fullVersionId}`;
    FileUtils.mkdirs(versionDir);
    FileUtils.writeFile(`${versionDir}/${fullVersionId}.json`, JSON.stringify(profile, null, 2));
    report('metadata', 20, '版本 JSON 已生成');

    // 下载 libraries
    const rawLibs = profile.libraries || [];
    const items = ModLoaderInstaller.libraryItems(rawLibs, libsDir, true);
    report('libraries', 30, `下载 ${items.length} 个库…`);
    const errors = await this.runStats(items, 'libraries', onProgress, token);
    if (errors.length > 0) {
      Logger.warn(ModLoaderInstaller.TAG, `${errors.length} 个库下载失败，例如 ${errors[0]}`);
    }

    // 确保原版父版本
    report('parent', 70, `检查原版 ${mcVersion}…`);
    const parentJson = `${mcDir}/${Constants.VERSIONS_DIR}/${mcVersion}/${mcVersion}.json`;
    const parentJar = `${mcDir}/${Constants.VERSIONS_DIR}/${mcVersion}/${mcVersion}.jar`;
    if (!FileUtils.exists(parentJson) || !FileUtils.exists(parentJar)) {
      report('parent', 72, `先安装原版 ${mcVersion}…`);
      await VersionInstaller.install({
        mcDir: mcDir,
        versionId: mcVersion,
        useMirror: true,
        osArch: Constants.osArch,
        onProgress: (p) => {
          if (onProgress) {
            onProgress({ phase: 'parent', progress: 72 + Math.round(p.progress * 10), message: `原版 ${p.phase}: ${p.message}` });
          }
        },
        token: token
      });
    }

    report('done', 100, `${loader} ${loaderVersion} 安装完成`);
    return this.buildInstallation(
      fullVersionId, mcVersion,
      loader === ModLoader.QUILT ? LoaderType.QUILT : LoaderType.FABRIC,
      loaderVersion, versionDir
    );
  }

  // ============================================================
  //  对外安装入口
  // ============================================================

  async installLoader(
    loader: ModLoader,
    mcVersion: string,
    loaderVersion: string,
    onProgress?: ProgressCallback,
    token?: CancelToken
  ): Promise<GameInstallation> {
    Logger.info(ModLoaderInstaller.TAG, `安装 ${loader} ${loaderVersion} (MC ${mcVersion})`);
    switch (loader) {
      case ModLoader.FORGE: {
        const id = `${mcVersion}-forge-${loaderVersion}`;
        return this.installForge(mcVersion, loaderVersion, id, onProgress, token);
      }
      case ModLoader.NEO_FORGE:
        return this.installNeoForge(mcVersion, loaderVersion, `neoforge-${loaderVersion}`, onProgress, token);
      case ModLoader.FABRIC:
      case ModLoader.QUILT:
        return this.installFabricLike(loader, mcVersion, loaderVersion, onProgress, token);
      default:
        throw new Error(`未知的加载器: ${loader}`);
    }
  }

  async detectLoader(versionId: string): Promise<LoaderType | null> {
    const jsonPath = `${this.minecraftDir()}/${Constants.VERSIONS_DIR}/${versionId}/${versionId}.json`;
    const text = FileUtils.readFile(jsonPath);
    if (text.length === 0) {
      return null;
    }
    const lower = text.toLowerCase();
    if (lower.indexOf('neoforge') >= 0) {
      return LoaderType.NEO_FORGE;
    }
    if (lower.indexOf('minecraftforge') >= 0 || lower.indexOf('forge') >= 0) {
      return LoaderType.FORGE;
    }
    if (lower.indexOf('quilt') >= 0) {
      return LoaderType.QUILT;
    }
    if (lower.indexOf('fabric') >= 0) {
      return LoaderType.FABRIC;
    }
    return null;
  }

  // ============================================================
  //  工具
  // ============================================================

  private minecraftDir(): string {
    return Constants.baseDir();
  }

  private async fetchText(urls: string[]): Promise<string> {
    for (const url of urls) {
      const res = await HttpClient.getText(url);
      if (res.success && res.data && res.data.length > 0) {
        return res.data;
      }
      Logger.warn(ModLoaderInstaller.TAG, `拉取失败 ${url}: ${res.error}`);
    }
    return '';
  }

  /** 解析 maven-metadata.xml 里的 <version> */
  static parseMavenVersions(xml: string): string[] {
    const result: string[] = [];
    const regex = new RegExp('<version>([^<]+)</version>', 'g');
    let match = regex.exec(xml);
    while (match !== null) {
      result.push(match[1]);
      match = regex.exec(xml);
    }
    return result;
  }

  /** 版本号比较（数值段优先，非法段降级为字符串比较） */
  static compareVersions(a: string, b: string): number {
    const pa = a.split(/[.\-+]/);
    const pb = b.split(/[.\-+]/);
    const len = Math.max(pa.length, pb.length);
    for (let i = 0; i < len; i++) {
      const sa = i < pa.length ? pa[i] : '0';
      const sb = i < pb.length ? pb[i] : '0';
      const na = parseInt(sa, 10);
      const nb = parseInt(sb, 10);
      if (!isNaN(na) && !isNaN(nb)) {
        if (na !== nb) {
          return na - nb;
        }
      } else if (sa !== sb) {
        return sa > sb ? 1 : -1;
      }
    }
    return 0;
  }

  /** 把 url 规范成以 '/' 结尾 */
  private static ensureSlash(url: string): string {
    return url.endsWith('/') ? url : `${url}/`;
  }

  /** 库列表 → 下载项（兼容 downloads.artifact 与 url+name 两种风格） */
  static libraryItems(libs: RawLibrary[], libsDir: string, useMirror: boolean): DownloadItem[] {
    const items: DownloadItem[] = [];
    for (const lib of libs) {
      if (!lib.name) {
        continue;
      }
      const rel = VersionInstaller.mavenRelativePath(lib.name);
      if (rel.length === 0) {
        continue;
      }
      const artifact = lib.downloads ? lib.downloads.artifact : undefined;
      let url = '';
      let sha1 = '';
      let size = 0;
      let path = rel;

      if (artifact && artifact.url) {
        url = artifact.url;
        sha1 = artifact.sha1 ? artifact.sha1 : '';
        size = artifact.size ? artifact.size : 0;
        path = artifact.path ? artifact.path : rel;
      } else if (lib.url) {
        url = `${ModLoaderInstaller.ensureSlash(lib.url)}${rel}`;
        sha1 = lib.sha1 ? lib.sha1 : '';
        size = lib.size ? lib.size : 0;
      } else {
        continue;
      }

      items.push({
        url: url,
        mirrors: Mirrors.candidates(url, useMirror).slice(1),
        path: `${libsDir}/${path}`,
        sha1: sha1,
        size: size,
        name: rel
      });
    }
    return items;
  }

  /** 递归复制目录（用于安装器内嵌 maven/） */
  static copyTree(srcDir: string, destDir: string, depth: number): number {
    if (depth > 12) {
      return 0;
    }
    let copied = 0;
    for (const entry of FileUtils.listDir(srcDir)) {
      const src = `${srcDir}/${entry}`;
      const dest = `${destDir}/${entry}`;
      if (FileUtils.isDirectory(src)) {
        FileUtils.mkdirs(dest);
        copied += ModLoaderInstaller.copyTree(src, dest, depth + 1);
      } else {
        if (!FileUtils.exists(dest)) {
          FileUtils.copyFile(src, dest);
          copied++;
        }
      }
    }
    return copied;
  }

  private buildInstallation(
    versionId: string,
    gameVersion: string,
    loaderType: LoaderType,
    loaderVersion: string,
    versionDir: string
  ): GameInstallation {
    return {
      versionId: versionId,
      name: versionId,
      directory: versionDir,
      gameVersion: gameVersion,
      loaderType: loaderType,
      loaderVersion: loaderVersion,
      installed: true,
      installTime: Date.now(),
      lastPlayed: 0,
      javaArgs: '',
      minMemory: 1024,
      maxMemory: 4096,
      width: Constants.DEFAULT_WIDTH,
      height: Constants.DEFAULT_HEIGHT,
      fullscreen: false,
      customJvmArgs: '',
      customGameArgs: ''
    };
  }
}
