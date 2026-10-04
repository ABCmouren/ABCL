// Game version management for HMCL-HarmonyOS
import { GameInstallation, VersionManifest, GameVersionJson, LoaderType, Library, DownloadSource } from '../../model/GameVersion';
import { AppStore } from '../AppStore';
import { Logger, FileUtils } from '../util/Utils';
import { HttpClient } from '../network/HttpClient';
import { Constants } from '../../config/Constants';
import { VersionInstaller, InstallProgressFn } from './VersionInstaller';
import { CancelToken } from '../download/DownloadEngine';

export class VersionManager {
  private static readonly TAG = 'VersionManager';
  private store: AppStore;
  private static instance: VersionManager;

  constructor() {
    this.store = AppStore.getInstance();
  }

  static getInstance(): VersionManager {
    if (!VersionManager.instance) {
      VersionManager.instance = new VersionManager();
    }
    return VersionManager.instance;
  }

  // Fetch version manifest from API
  async fetchVersionManifest(): Promise<VersionManifest> {
    // Try BMCLAPI first, fallback to Mojang
    let result = await HttpClient.getJson<VersionManifest>(
      Constants.BMCLAPI_VERSION_MANIFEST
    );
    if (!result.success || !result.data) {
      Logger.warn(VersionManager.TAG, 'BMCLAPI failed, trying Mojang');
      result = await HttpClient.getJson<VersionManifest>(
        Constants.MOJANG_VERSION_MANIFEST
      );
    }
    if (!result.success || !result.data) {
      throw new Error('Failed to fetch version manifest from all sources');
    }
    return result.data;
  }

  // Get locally installed versions
  getLocalVersions(): GameInstallation[] {
    const versionsDir = this.getVersionsDir();
    if (!FileUtils.exists(versionsDir)) {
      return [];
    }

    const dirs = FileUtils.listDir(versionsDir);
    const installations: GameInstallation[] = [];

    for (const dir of dirs) {
      const versionJson = `${versionsDir}/${dir}/${dir}.json`;
      if (FileUtils.exists(versionJson)) {
        try {
          const data: GameVersionJson = JSON.parse(FileUtils.readFile(versionJson));
          const installation: GameInstallation = {
            versionId: dir,
            name: dir,
            directory: `${versionsDir}/${dir}`,
            gameVersion: data.id,
            loaderType: this.detectModLoaderType(dir),
            loaderVersion: '',
            installed: true,
            installTime: 0,
            lastPlayed: 0,
            javaArgs: '',
            minMemory: this.store.config.defaultMinMemory,
            maxMemory: this.store.config.defaultMaxMemory,
            width: Constants.DEFAULT_WIDTH,
            height: Constants.DEFAULT_HEIGHT,
            fullscreen: false,
            customJvmArgs: '',
            customGameArgs: ''
          };
          installations.push(installation);
        } catch (e) {
          Logger.error(VersionManager.TAG, `Failed to parse version ${dir}`, e as Error);
        }
      }
    }

    this.store.setInstallations(installations);
    return installations;
  }

  // Detect mod loader type from version directory
  private detectModLoader(versionId: string): string {
    const versionDir = `${this.getVersionsDir()}/${versionId}`;
    const files = FileUtils.listDir(versionDir);
    
    // Check for mod loader markers
    for (const file of files) {
      const lower = file.toLowerCase();
      if (lower.includes('forge')) return 'forge';
      if (lower.includes('fabric')) return 'fabric';
      if (lower.includes('quilt')) return 'quilt';
      if (lower.includes('neoforge')) return 'neoforge';
      if (lower.includes('liteloader')) return 'liteloader';
    }
    return '';
  }

  private detectModLoaderType(versionId: string): LoaderType | null {
    const loader = this.detectModLoader(versionId);
    if (loader === 'forge') return LoaderType.FORGE;
    if (loader === 'fabric') return LoaderType.FABRIC;
    if (loader === 'quilt') return LoaderType.QUILT;
    if (loader === 'neoforge') return LoaderType.NEO_FORGE;
    return null;
  }

  /**
   * 完整安装一个 Minecraft 版本。
   *
   * 2026-10 修复：旧实现只下载 version json + client.jar，既不下载 libraries
   * 也不下载 assets，所以"安装成功"的版本启动必然失败。现在整套流程交给
   * VersionInstaller（版本元数据 → client.jar → libraries → natives → logging → assets）。
   */
  async installVersion(
    versionId: string,
    onProgress?: InstallProgressFn,
    token?: CancelToken
  ): Promise<void> {
    Logger.info(VersionManager.TAG, `安装版本 ${versionId}（下载源：${this.store.config.downloadSource}）`);
    this.initMinecraftDir();

    const useMirror = this.store.config.downloadSource !== DownloadSource.MOJANG;
    await VersionInstaller.install({
      mcDir: this.getMinecraftDir(),
      versionId: versionId,
      useMirror: useMirror,
      osArch: Constants.osArch,
      onProgress: onProgress,
      token: token
    });

    this.getLocalVersions();
    Logger.info(VersionManager.TAG, `版本 ${versionId} 安装完成`);
  }

  // Remove a Minecraft version（含子目录递归删除）
  async removeVersion(versionId: string): Promise<void> {
    const versionDir = `${this.getVersionsDir()}/${versionId}`;
    FileUtils.delete(versionDir);
    this.store.installations = this.store.installations.filter(
      inst => inst.versionId !== versionId
    );
    this.store.setInstallations(this.store.installations);
  }

  // Get versions directory path
  private getVersionsDir(): string {
    return `${this.getMinecraftDir()}/${Constants.VERSIONS_DIR}`;
  }

  // Get Minecraft directory path（沙箱根由 EntryAbility 注入，见 Constants.appDir）
  getMinecraftDir(): string {
    const configured = this.store.config.gameDirectory;
    if (configured && configured.length > 0) {
      return configured;
    }
    return Constants.baseDir();
  }

  // Get main class for a version (follows inheritsFrom chain)
  async getMainClass(versionId: string): Promise<string> {
    const versionJson = await this.getResolvedVersionInfo(versionId);
    return versionJson.mainClass || 'net.minecraft.client.main.Main';
  }

  // Get libraries for a version
  async getLibrariesForVersion(versionId: string): Promise<Library[]> {
    const versionJson = await this.getResolvedVersionInfo(versionId);
    return versionJson.libraries || [];
  }

  // Get version info (parsed version JSON) — raw, no inheritance resolution
  async getVersionInfo(versionId: string): Promise<GameVersionJson> {
    const versionDir = `${this.getVersionsDir()}/${versionId}`;
    const versionJsonPath = `${versionDir}/${versionId}.json`;
    if (!FileUtils.exists(versionJsonPath)) {
      throw new Error(`Version JSON not found for ${versionId}`);
    }
    const data = FileUtils.readFile(versionJsonPath);
    return JSON.parse(data) as GameVersionJson;
  }

  /**
   * Get resolved version info with inheritsFrom chain merged.
   * Forge/Fabric/Quilt version JSONs have `inheritsFrom` pointing to the
   * vanilla version. We need to merge libraries and inherit mainClass from
   * the parent only if the child doesn't override it.
   *
   * Merge rules (same as HMCL / standard launcher):
   *   - mainClass: child takes priority over parent
   *   - libraries: child libs prepended, parent libs appended (child wins on duplicate name)
   *   - arguments/minecraftArguments: child takes priority
   *   - everything else: child takes priority, fall back to parent
   */
  async getResolvedVersionInfo(versionId: string): Promise<GameVersionJson> {
    const child = await this.getVersionInfo(versionId);

    if (!child.inheritsFrom) {
      // Vanilla — no merging needed
      return child;
    }

    Logger.info(VersionManager.TAG, `Version ${versionId} inheritsFrom ${child.inheritsFrom}`);

    let parent: GameVersionJson;
    try {
      // Parent is usually a vanilla version already installed
      parent = await this.getVersionInfo(child.inheritsFrom);
    } catch (e) {
      Logger.warn(VersionManager.TAG,
        `Parent version ${child.inheritsFrom} not found, launching with child only`);
      return child;
    }

    // Merge libraries: child first (so child's Forge/Fabric libs override), then parent
    const childLibNames = new Set<string>();
    const mergedLibs: Library[] = [];

    for (const lib of (child.libraries || [])) {
      childLibNames.add(lib.name);
      mergedLibs.push(lib);
    }
    for (const lib of (parent.libraries || [])) {
      if (!childLibNames.has(lib.name)) {
        mergedLibs.push(lib);
      }
    }

    const resolved: GameVersionJson = {
      // Manually merge fields (ArkTS strict mode forbids spread on objects)
      id: child.id || parent.id,
      type: child.type || parent.type,
      time: child.time || parent.time,
      releaseTime: child.releaseTime || parent.releaseTime,
      minecraftArguments: child.minecraftArguments || parent.minecraftArguments,
      arguments: child.arguments || parent.arguments,
      // mainClass: child takes priority (Forge/Fabric override this)
      mainClass: child.mainClass || parent.mainClass || 'net.minecraft.client.main.Main',
      inheritsFrom: child.inheritsFrom || parent.inheritsFrom,
      jar: child.jar || parent.jar,
      minimumLauncherVersion: child.minimumLauncherVersion || parent.minimumLauncherVersion,
      // assets: child takes priority
      assets: child.assets || parent.assets,
      // assetIndex: child takes priority
      assetIndex: child.assetIndex || parent.assetIndex || { id: '', sha1: '', size: 0, totalSize: 0, url: '' },
      // downloads: child takes priority
      downloads: child.downloads || parent.downloads || { client: { sha1: '', size: 0, url: '' } },
      // libraries: merged
      libraries: mergedLibs,
      logging: child.logging || parent.logging,
      complianceLevel: child.complianceLevel || parent.complianceLevel,
    };

    Logger.info(VersionManager.TAG,
      `Resolved ${versionId}: mainClass=${resolved.mainClass}, ` +
      `libs=${mergedLibs.length} (child=${child.libraries?.length || 0} + parent=${parent.libraries?.length || 0})`);

    return resolved;
  }

  /**
   * Build the full classpath array for launching a version.
   * Resolves `inheritsFrom` chain and converts Maven-style library names
   * to absolute file paths under the libraries directory.
   *
   * Library name format: "group:artifact:version" → Maven path
   * e.g. "cpw.mods:bootstraplauncher:1.1.2" →
   *      libraries/cpw/mods/bootstraplauncher/1.1.2/bootstraplauncher-1.1.2.jar
   *
   * Returns: [version.jar, ...library jars in classpath order]
   */
  async getClasspathForVersion(versionId: string): Promise<string[]> {
    const resolved = await this.getResolvedVersionInfo(versionId);
    const libsDir = `${this.getMinecraftDir()}/${Constants.LIBRARIES_DIR}`;
    const versionsDir = this.getVersionsDir();
    const classpath: string[] = [];

    // Add library JARs (filter by rules: skip platform-specific natives)
    for (const lib of (resolved.libraries || [])) {
      if (!lib.name) continue;

      // Skip libraries with OS rules that exclude HarmonyOS (treated as Linux)
      if (lib.rules) {
        let allowed = false;
        for (const rule of lib.rules) {
          if (rule.action === 'allow') {
            if (!rule.os) {
              allowed = true; // allow all platforms
            } else if (rule.os.name === 'linux' || rule.os.name === 'ohos') {
              allowed = true; // allow Linux/HarmonyOS
            }
          } else if (rule.action === 'disallow') {
            if (rule.os && (rule.os.name === 'linux' || rule.os.name === 'ohos')) {
              allowed = false;
              break;
            }
          }
        }
        if (!allowed) continue;
      }

      // Skip native-only classifier libs (we handle natives separately)
      if (lib.natives) {
        // This lib entry is for natives extraction, skip JAR from classpath
        continue;
      }

      // Prefer downloads.artifact.path (it's the canonical Maven path)
      let jarPath: string | null = null;
      if (lib.downloads?.artifact?.path) {
        jarPath = `${libsDir}/${lib.downloads.artifact.path}`;
      } else {
        jarPath = this.mavenNameToPath(lib.name, libsDir);
      }
      if (jarPath && FileUtils.exists(jarPath)) {
        classpath.push(jarPath);
      } else if (jarPath) {
        Logger.warn(VersionManager.TAG, `Library JAR not found: ${jarPath}`);
      }
    }

    // Add the version JAR (or parent jar for Forge/Fabric which set `jar` field)
    const jarName = resolved.jar || versionId;
    const versionJar = `${versionsDir}/${jarName}/${jarName}.jar`;
    if (FileUtils.exists(versionJar)) {
      classpath.push(versionJar);
    } else {
      Logger.warn(VersionManager.TAG, `Version JAR not found: ${versionJar}`);
    }

    Logger.info(VersionManager.TAG, `Classpath for ${versionId}: ${classpath.length} entries`);
    return classpath;
  }

  /**
   * Convert Maven coordinate "group:artifact:version[:classifier]"
   * to an absolute JAR path under libsDir.
   *
   * e.g. "net.minecraftforge:forge:1.20.4-49.0.19:universal"
   *   → libsDir/net/minecraftforge/forge/1.20.4-49.0.19/forge-1.20.4-49.0.19-universal.jar
   */
  private mavenNameToPath(name: string, libsDir: string): string | null {
    // Use downloads.artifact.path if present (most reliable)
    // We'll resolve from name since we don't have the Library object here

    const parts = name.split(':');
    if (parts.length < 3) return null;

    const group = parts[0].replace(/\./g, '/');
    const artifact = parts[1];
    const version = parts[2];
    const classifier = parts.length >= 4 ? parts[3] : '';

    const jarFile = classifier
      ? `${artifact}-${version}-${classifier}.jar`
      : `${artifact}-${version}.jar`;

    return `${libsDir}/${group}/${artifact}/${version}/${jarFile}`;
  }

  // Initialize Minecraft directory structure
  initMinecraftDir(): void {
    const mcDir = this.getMinecraftDir();
    const subDirs = [
      Constants.VERSIONS_DIR,
      Constants.LIBRARIES_DIR,
      Constants.ASSETS_DIR,
      Constants.ASSETS_DIR + '/indexes',
      Constants.ASSETS_DIR + '/objects',
      Constants.MODS_DIR,
      Constants.RESOURCE_PACKS_DIR,
      Constants.SAVES_DIR,
      Constants.LOGS_DIR,
      Constants.CONFIG_DIR
    ];
    for (const dir of subDirs) {
      FileUtils.mkdirs(`${mcDir}/${dir}`);
    }
  }
}

// Mod manager for HMCL-HarmonyOS
export class ModManager {
  private static readonly TAG = 'ModManager';

  // Get mods directory
  private getModsDir(gameDir: string): string {
    return `${gameDir}/${Constants.MODS_DIR}`;
  }

  // Scan installed mods
  scanMods(gameDir: string): string[] {
    const modsDir = this.getModsDir(gameDir);
    if (!FileUtils.exists(modsDir)) {
      return [];
    }
    return FileUtils.listDir(modsDir).filter(f => f.endsWith('.jar') || f.endsWith('.disabled'));
  }

  // Toggle mod enabled/disabled
  toggleMod(modsDir: string, fileName: string): void {
    const filePath = `${modsDir}/${fileName}`;
    if (fileName.endsWith('.disabled')) {
      // Enable: rename .jar.disabled to .jar
      const newName = fileName.replace('.disabled', '');
      FileUtils.moveFile(filePath, `${modsDir}/${newName}`);
    } else {
      // Disable: rename .jar to .jar.disabled
      FileUtils.moveFile(filePath, `${filePath}.disabled`);
    }
  }

  // Delete mod
  deleteMod(modsDir: string, fileName: string): void {
    FileUtils.delete(`${modsDir}/${fileName}`);
  }
}