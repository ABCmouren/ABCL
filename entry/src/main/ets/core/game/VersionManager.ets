// Game version management for HMCL-HarmonyOS
import { GameInstallation, VersionManifest, GameVersionJson, LoaderType, Library } from '../../model/GameVersion';
import { AppStore } from '../AppStore';
import { Logger, FileUtils } from '../util/Utils';
import { HttpClient } from '../network/HttpClient';
import { Constants } from '../../config/Constants';

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

  // Install a Minecraft version
  async installVersion(versionId: string): Promise<void> {
    Logger.info(VersionManager.TAG, `Installing version: ${versionId}`);
    
    // Get manifest to find version URL
    const manifest = await this.fetchVersionManifest();
    const version = manifest.versions.find(v => v.id === versionId);
    if (!version) {
      throw new Error(`Version ${versionId} not found in manifest`);
    }

    // Fetch version JSON
    const versionJson = await HttpClient.getJson<GameVersionJson>(version.url);
    if (!versionJson.success || !versionJson.data) {
      throw new Error(`Failed to fetch version JSON for ${versionId}`);
    }

    const vData = versionJson.data;

    // Create version directory
    const versionDir = `${this.getVersionsDir()}/${versionId}`;
    FileUtils.mkdirs(versionDir);

    // Save version JSON
    FileUtils.writeFile(
      `${versionDir}/${versionId}.json`,
      JSON.stringify(vData, null, 2)
    );

    // Download client jar
    if (vData.downloads?.client?.url) {
      const clientPath = `${versionDir}/${versionId}.jar`;
      Logger.info(VersionManager.TAG, `Downloading client jar: ${vData.downloads.client.url}`);
      await HttpClient.downloadFile(vData.downloads.client.url, clientPath);
    }

    Logger.info(VersionManager.TAG, `Version ${versionId} installed successfully`);
  }

  // Remove a Minecraft version
  async removeVersion(versionId: string): Promise<void> {
    const versionDir = `${this.getVersionsDir()}/${versionId}`;
    if (FileUtils.exists(versionDir)) {
      const files = FileUtils.listDir(versionDir);
      for (const file of files) {
        FileUtils.delete(`${versionDir}/${file}`);
      }
      FileUtils.delete(versionDir);
    }
    this.store.installations = this.store.installations.filter(
      inst => inst.versionId !== versionId
    );
  }

  // Get versions directory path
  private getVersionsDir(): string {
    const gameDir = this.store.config.gameDirectory || `${Constants.APP_DIR}${Constants.MINECRAFT_DIR}`;
    return `${gameDir}/${Constants.VERSIONS_DIR}`;
  }

  // Get Minecraft directory path
  getMinecraftDir(): string {
    return this.store.config.gameDirectory || `${Constants.APP_DIR}${Constants.MINECRAFT_DIR}`;
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