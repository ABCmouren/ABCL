/**
 * VersionInstaller — 原版 Minecraft 完整安装（2026-10 重写）
 *
 * 旧版本 VersionManager.installVersion() 只下载了 version json + client.jar，
 * **既不下载 libraries 也不下载 assets**，所以"安装完成"的版本根本起不来。
 *
 * 现在按 HMCL / AMCL 的完整流程执行：
 *   prepare   拉取 version_manifest_v2 → 版本元数据 JSON → 落盘
 *   client    下载 client.jar
 *   libraries 下载所有库文件（含 rules 过滤 + linux natives 分类器）
 *   natives   解压 natives jar 到 versions/<id>/natives
 *   logging   下载官方 log4j 配置到 assets/log_configs/
 *   assets    下载 asset index + 全部 asset objects 到 assets/objects/<xx>/<hash>
 */
import {
  GameVersionJson, Library, VersionManifest, VersionInfo, AssetIndex
} from '../../model/GameVersion';
import { Constants } from '../../config/Constants';
import { HttpClient } from '../network/HttpClient';
import { Mirrors } from '../network/Mirrors';
import { DownloadEngine, DownloadItem, CancelToken } from '../download/DownloadEngine';
import { DownloadSettings } from '../download/DownloadSettings';
import { ArchiveUtils, FileUtils, Logger, StringUtils } from '../util/Utils';

export interface InstallProgress {
  phase: string;
  message: string;
  progress: number;
  filesDone: number;
  filesTotal: number;
  bytesDone: number;
  bytesTotal: number;
  speedBps: number;
}

export type InstallProgressFn = (p: InstallProgress) => void;

export interface InstallOptions {
  mcDir: string;
  versionId: string;
  useMirror: boolean;
  /** 'aarch64'（真机）或 'x86_64'（模拟器） */
  osArch: string;
  onProgress?: InstallProgressFn;
  token?: CancelToken;
}

export interface AssetIndexData {
  objects: Record<string, AssetObjectEntry>;
}

export interface AssetObjectEntry {
  hash: string;
  size: number;
}

export class VersionInstaller {
  private static readonly TAG = 'VersionInstaller';

  // ============================================================
  //  版本元数据
  // ============================================================

  /** 拉取版本清单（BMCLAPI 优先，失败回退 Mojang 官方） */
  static async fetchManifest(useMirror: boolean): Promise<VersionManifest> {
    const urls: string[] = [];
    if (useMirror) {
      urls.push(Constants.BMCLAPI_VERSION_MANIFEST);
    }
    urls.push(Constants.MOJANG_VERSION_MANIFEST);

    let lastError = '';
    for (const url of urls) {
      const res = await HttpClient.getJson<VersionManifest>(url);
      if (res.success && res.data && res.data.versions && res.data.versions.length > 0) {
        Logger.info(VersionInstaller.TAG, `版本清单来源: ${url} (${res.data.versions.length} 个版本)`);
        return res.data;
      }
      lastError = res.error || 'unknown';
      Logger.warn(VersionInstaller.TAG, `版本清单拉取失败 ${url}: ${lastError}`);
    }
    throw new Error(`无法获取版本清单: ${lastError}`);
  }

  /** 拉取某个版本的元数据 JSON（自动镜像回退） */
  static async fetchVersionJson(info: VersionInfo, useMirror: boolean): Promise<GameVersionJson> {
    const candidates = Mirrors.candidates(info.url, useMirror);
    if (useMirror) {
      candidates.push(`${Mirrors.BMCLAPI_ORIGIN}/version/${info.id}/json`);
    }
    let lastError = '';
    for (const url of candidates) {
      const res = await HttpClient.getJson<GameVersionJson>(url);
      if (res.success && res.data && res.data.id) {
        Logger.info(VersionInstaller.TAG, `版本 JSON 来源: ${url}`);
        return res.data;
      }
      lastError = res.error || 'unknown';
    }
    throw new Error(`无法获取版本 ${info.id} 的元数据: ${lastError}`);
  }

  // ============================================================
  //  主流程
  // ============================================================

  static async install(opts: InstallOptions): Promise<void> {
    const mcDir = opts.mcDir;
    const versionId = opts.versionId;
    const useMirror = opts.useMirror;
    const osArch = opts.osArch || 'aarch64';

    const emit = (phase: string, message: string, progress: number): void => {
      if (opts.onProgress) {
        opts.onProgress({
          phase: phase,
          message: message,
          progress: progress,
          filesDone: 0,
          filesTotal: 0,
          bytesDone: 0,
          bytesTotal: 0,
          speedBps: 0
        });
      }
      Logger.info(VersionInstaller.TAG, `[${phase}] ${message}`);
    };

    // ---------- 1. prepare ----------
    emit('prepare', '获取版本清单…', 0.01);
    const manifest = await VersionInstaller.fetchManifest(useMirror);
    const info = manifest.versions.find((v: VersionInfo) => v.id === versionId);
    if (!info) {
      throw new Error(`版本清单中没有 ${versionId}`);
    }

    emit('prepare', `获取 ${versionId} 元数据…`, 0.03);
    const versionJson = await VersionInstaller.fetchVersionJson(info, useMirror);

    const versionDir = `${mcDir}/${Constants.VERSIONS_DIR}/${versionId}`;
    FileUtils.mkdirs(versionDir);
    FileUtils.writeFile(`${versionDir}/${versionId}.json`, JSON.stringify(versionJson, null, 2));
    emit('prepare', '版本元数据已保存', 0.05);

    if (opts.token && opts.token.isCancelled()) {
      throw new Error('安装已取消');
    }

    // ---------- 2. 构建下载清单 ----------
    const items: DownloadItem[] = [];

    // client.jar
    const clientArtifact = versionJson.downloads ? versionJson.downloads.client : undefined;
    if (!clientArtifact || !clientArtifact.url) {
      throw new Error(`版本 ${versionId} 缺少 client 下载信息`);
    }
    items.push({
      url: clientArtifact.url,
      mirrors: Mirrors.candidates(clientArtifact.url, useMirror).slice(1),
      path: `${versionDir}/${versionId}.jar`,
      sha1: clientArtifact.sha1 || '',
      size: clientArtifact.size || 0,
      name: `${versionId}.jar`
    });

    // libraries + natives
    const libsDir = `${mcDir}/${Constants.LIBRARIES_DIR}`;
    const nativesDir = `${versionDir}/natives`;
    const nativeJars: string[] = [];
    const libraries: Library[] = versionJson.libraries || [];
    for (const lib of libraries) {
      if (!VersionInstaller.isLibraryAllowed(lib, osArch)) {
        continue;
      }
      const artifact = lib.downloads ? lib.downloads.artifact : undefined;
      if (artifact && artifact.url && artifact.path) {
        items.push({
          url: artifact.url,
          mirrors: Mirrors.candidates(artifact.url, useMirror).slice(1),
          path: `${libsDir}/${artifact.path}`,
          sha1: artifact.sha1 || '',
          size: artifact.size || 0,
          name: artifact.path
        });
      } else if (lib.name) {
        // 没有 downloads 字段（Forge install_profile 的库）→ 按 Maven 坐标推导
        const rel = VersionInstaller.mavenRelativePath(lib.name);
        if (rel.length > 0) {
          const base = VersionInstaller.mavenBaseFor(lib.name, useMirror);
          items.push({
            url: `${base}/${rel}`,
            mirrors: [],
            path: `${libsDir}/${rel}`,
            sha1: '',
            size: 0,
            name: rel
          });
        }
      }

      // natives（HarmonyOS 走 linux 分类器）
      const nativeKey = VersionInstaller.nativeClassifier(lib);
      if (nativeKey.length > 0 && lib.downloads && lib.downloads.classifiers) {
        const nativeArtifact = lib.downloads.classifiers[nativeKey];
        if (nativeArtifact && nativeArtifact.url) {
          const rel = nativeArtifact.path ? nativeArtifact.path : VersionInstaller.mavenRelativePath(`${lib.name}:${nativeKey}`);
          const target = `${libsDir}/${rel}`;
          items.push({
            url: nativeArtifact.url,
            mirrors: Mirrors.candidates(nativeArtifact.url, useMirror).slice(1),
            path: target,
            sha1: nativeArtifact.sha1 || '',
            size: nativeArtifact.size || 0,
            name: rel
          });
          nativeJars.push(target);
        }
      }
    }

    // logging config
    const loggingClient = versionJson.logging ? versionJson.logging.client : undefined;
    if (loggingClient && loggingClient.file && loggingClient.file.url) {
      items.push({
        url: loggingClient.file.url,
        mirrors: Mirrors.candidates(loggingClient.file.url, useMirror).slice(1),
        path: `${mcDir}/${Constants.ASSETS_DIR}/log_configs/${loggingClient.file.id}`,
        sha1: loggingClient.file.sha1 || '',
        size: loggingClient.file.size || 0,
        name: `log_configs/${loggingClient.file.id}`
      });
    }

    // asset index
    const assetIndex: AssetIndex | undefined = versionJson.assetIndex;
    const assetId = versionJson.assets || (assetIndex ? assetIndex.id : '');
    let assetIndexPath = '';
    if (assetIndex && assetIndex.url && assetId) {
      assetIndexPath = `${mcDir}/${Constants.ASSETS_DIR}/indexes/${assetId}.json`;
      items.push({
        url: assetIndex.url,
        mirrors: Mirrors.candidates(assetIndex.url, useMirror).slice(1),
        path: assetIndexPath,
        sha1: assetIndex.sha1 || '',
        size: assetIndex.size || 0,
        name: `${assetId}.json`
      });
    }

    // ---------- 3. 下载 ----------
    emit('client', `开始下载 ${items.length} 个文件…`, 0.08);
    const phaseBase = 0.08;
    const phaseSpan = 0.62;
    const batch = await DownloadEngine.run(
      items,
      'files',
      (stats) => {
        if (!opts.onProgress) {
          return;
        }
        const ratio = stats.totalFiles > 0 ? stats.completedFiles / stats.totalFiles : 0;
        opts.onProgress({
          phase: stats.phase,
          message: stats.message,
          progress: phaseBase + ratio * phaseSpan,
          filesDone: stats.completedFiles,
          filesTotal: stats.totalFiles,
          bytesDone: stats.completedBytes,
          bytesTotal: stats.totalBytes,
          speedBps: stats.speedBps
        });
      },
      DownloadSettings.threads(),
      opts.token
    );

    if (batch.failedItems.length > 0) {
      const preview = batch.errors.slice(0, 3).join('; ');
      Logger.warn(VersionInstaller.TAG, `${batch.failedItems.length} 个文件下载失败: ${preview}`);
    }

    // client.jar 必须成功，否则版本不可用
    const clientPath = `${versionDir}/${versionId}.jar`;
    if (!FileUtils.exists(clientPath) || FileUtils.getFileSize(clientPath) <= 0) {
      throw new Error(`client.jar 下载失败：${batch.errors.length > 0 ? batch.errors[0] : '未知原因'}`);
    }

    // ---------- 4. 解压 natives ----------
    if (nativeJars.length > 0) {
      emit('natives', `解压 ${nativeJars.length} 个 natives 包…`, 0.72);
      await VersionInstaller.extractNatives(nativeJars, nativesDir, osArch);
    }

    // ---------- 5. assets ----------
    if (assetIndexPath.length > 0 && FileUtils.exists(assetIndexPath)) {
      emit('assets', '解析资源索引…', 0.75);
      await VersionInstaller.downloadAssets(mcDir, assetIndexPath, useMirror, opts);
    } else {
      Logger.warn(VersionInstaller.TAG, '未找到 asset index，跳过资源下载');
    }

    emit('done', `${versionId} 安装完成`, 1.0);
  }

  // ============================================================
  //  资源（assets）
  // ============================================================

  static async downloadAssets(
    mcDir: string,
    assetIndexPath: string,
    useMirror: boolean,
    opts: InstallOptions
  ): Promise<void> {
    const raw = FileUtils.readFile(assetIndexPath);
    let index: AssetIndexData;
    try {
      index = JSON.parse(raw) as AssetIndexData;
    } catch (e) {
      throw new Error(`asset index 解析失败: ${(e as Error).message}`);
    }
    const objects = index.objects || {};
    const keys = Object.keys(objects);

    const items: DownloadItem[] = [];
    for (const key of keys) {
      const entry = objects[key];
      const hash = entry.hash;
      if (!hash || hash.length < 2) {
        continue;
      }
      const sub = hash.substring(0, 2);
      const official = Mirrors.officialAssetObject(hash);
      const mirror = Mirrors.assetObject(hash);
      items.push({
        url: useMirror ? mirror : official,
        mirrors: useMirror ? [official] : [mirror],
        path: `${mcDir}/${Constants.ASSETS_DIR}/objects/${sub}/${hash}`,
        sha1: hash,
        size: entry.size || 0,
        name: key
      });
    }

    if (items.length === 0) {
      return;
    }
    Logger.info(VersionInstaller.TAG, `资源对象共 ${items.length} 个`);

    const batch = await DownloadEngine.run(
      items,
      'assets',
      (stats) => {
        if (!opts.onProgress) {
          return;
        }
        const ratio = stats.totalFiles > 0 ? stats.completedFiles / stats.totalFiles : 0;
        opts.onProgress({
          phase: 'assets',
          message: `资源 ${stats.completedFiles}/${stats.totalFiles}`,
          progress: 0.75 + ratio * 0.24,
          filesDone: stats.completedFiles,
          filesTotal: stats.totalFiles,
          bytesDone: stats.completedBytes,
          bytesTotal: stats.totalBytes,
          speedBps: stats.speedBps
        });
      },
      // 资源文件多且小，用设置里的并发（上限 12，避免请求过密被限流）
      Math.min(DownloadSettings.threads(), 12),
      opts.token
    );

    if (batch.failedItems.length > 0) {
      throw new Error(`${batch.failedItems.length}/${items.length} 个资源文件下载失败（例如 ${batch.failedItems[0].name}）`);
    }
  }

  // ============================================================
  //  libraries 规则 / 路径
  // ============================================================

  /** HarmonyOS 视为 linux；按 rules 判断库是否适用 */
  static isLibraryAllowed(lib: Library, osArch: string): boolean {
    const rules = lib.rules;
    if (!rules || rules.length === 0) {
      return true;
    }
    let allowed = false;
    for (const rule of rules) {
      let matched = true;
      if (rule.os) {
        const name = rule.os.name ? rule.os.name : '';
        matched = (name === 'linux' || name === 'ohos');
        if (matched && rule.os.arch) {
          matched = VersionInstaller.archMatches(rule.os.arch, osArch);
        }
      }
      if (rule.features) {
        // demo / custom_resolution 一律按 false
        matched = false;
      }
      if (matched) {
        allowed = rule.action === 'allow';
      }
    }
    return allowed;
  }

  private static archMatches(ruleArch: string, osArch: string): boolean {
    if (ruleArch === osArch) {
      return true;
    }
    if (ruleArch === 'x86' && (osArch === 'x86_64' || osArch === 'x86')) {
      return true;
    }
    if (ruleArch === 'arm64' && (osArch === 'aarch64' || osArch === 'arm64')) {
      return true;
    }
    return false;
  }

  /** natives 分类器 key（HarmonyOS 用 linux） */
  static nativeClassifier(lib: Library): string {
    if (!lib.natives) {
      return '';
    }
    const table = lib.natives;
    const key = table['ohos'] ? table['ohos'] : (table['linux'] ? table['linux'] : '');
    if (!key) {
      return '';
    }
    return key.replace(`${'$'}{arch}`, '64');
  }

  /** Maven 坐标 → 相对路径 */
  static mavenRelativePath(coordinates: string): string {
    const parts = coordinates.split(':');
    if (parts.length < 3) {
      return '';
    }
    const group = parts[0].replace(/\./g, '/');
    const artifact = parts[1];
    const version = parts[2];
    const classifier = parts.length >= 4 && parts[3].length > 0 ? `-${parts[3]}` : '';
    return `${group}/${artifact}/${version}/${artifact}-${version}${classifier}.jar`;
  }

  /** 库的 Maven 根（用于没有 downloads 字段的情况） */
  static mavenBaseFor(coordinates: string, useMirror: boolean): string {
    if (coordinates.startsWith('net.minecraftforge') || coordinates.startsWith('cpw.mods')
      || coordinates.startsWith('net.minecraft')) {
      return useMirror ? Mirrors.BMCLAPI_MAVEN : Constants.FORGE_MAVEN;
    }
    if (coordinates.startsWith('net.fabricmc') || coordinates.startsWith('org.quiltmc')) {
      return Constants.FABRIC_MAVEN;
    }
    if (coordinates.startsWith('net.neoforged')) {
      return `${Constants.NEO_FORGE_MAVEN}/releases`;
    }
    return useMirror ? Mirrors.BMCLAPI_MAVEN : Constants.MOJANG_LIBRARIES_BASE;
  }

  // ============================================================
  //  natives 解压
  // ============================================================

  static async extractNatives(nativeJars: string[], nativesDir: string, osArch: string): Promise<void> {
    FileUtils.mkdirs(nativesDir);
    const rawRoot = `${nativesDir}-raw`;
    let index = 0;
    let copied = 0;
    for (const jar of nativeJars) {
      if (!FileUtils.exists(jar)) {
        continue;
      }
      index++;
      const rawDir = `${rawRoot}/${index}`;
      const ok = await ArchiveUtils.unzip(jar, rawDir);
      if (!ok) {
        continue;
      }
      copied += VersionInstaller.collectNativeFiles(rawDir, nativesDir, 0);
    }
    FileUtils.delete(rawRoot);
    Logger.info(VersionInstaller.TAG,
      `natives 解压完成：${index} 个包 → ${copied} 个库文件（arch=${osArch}）`);
  }

  private static collectNativeFiles(dir: string, nativesDir: string, depth: number): number {
    if (depth > 6) {
      return 0;
    }
    let copied = 0;
    const entries = FileUtils.listDir(dir);
    for (const entry of entries) {
      const full = `${dir}/${entry}`;
      if (FileUtils.isDirectory(full)) {
        copied += VersionInstaller.collectNativeFiles(full, nativesDir, depth + 1);
        continue;
      }
      const lower = entry.toLowerCase();
      if (lower.startsWith('meta-inf') || lower.endsWith('.class') || lower.endsWith('.java')) {
        continue;
      }
      if (lower.endsWith('.so') || lower.endsWith('.dylib') || lower.endsWith('.dll')) {
        FileUtils.copyFile(full, `${nativesDir}/${entry}`);
        copied++;
      }
    }
    return copied;
  }
}
