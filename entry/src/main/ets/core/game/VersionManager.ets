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

    this.store.installations = installations;
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

  // Get main class for a version
  async getMainClass(versionId: string): Promise<string> {
    const versionJson = await this.getVersionInfo(versionId);
    return versionJson.mainClass || 'net.minecraft.client.main.Main';
  }

  // Get libraries for a version
  async getLibrariesForVersion(versionId: string): Promise<Library[]> {
    const versionJson = await this.getVersionInfo(versionId);
    return versionJson.libraries || [];
  }

  // Get version info (parsed version JSON)
  async getVersionInfo(versionId: string): Promise<GameVersionJson> {
    const versionDir = `${this.getVersionsDir()}/${versionId}`;
    const versionJsonPath = `${versionDir}/${versionId}.json`;
    if (!FileUtils.exists(versionJsonPath)) {
      throw new Error(`Version JSON not found for ${versionId}`);
    }
    const data = FileUtils.readFile(versionJsonPath);
    return JSON.parse(data) as GameVersionJson;
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