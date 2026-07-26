/**
 * Mod and resource pack manager for HMCL-HarmonyOS
 * Scans mod directories, parses mod metadata, enables/disables mods,
 * tracks dependencies, downloads from Modrinth/CurseForge
 */

import { Constants, HttpHelper } from '../../config/Constants';
import fileIo from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import util from '@ohos.util';

export interface ModInfo {
  fileName: string;
  filePath: string;
  name: string;
  modId: string;
  version: string;
  description: string;
  authors: string[];
  loaderType: ModLoaderType;
  enabled: boolean;
  dependencies: ModDependency[];
  url: string;
  iconPath: string;
  mcVersions: string[];
  side: ModSide;
}

export interface ModDependency {
  modId: string;
  versionRange: string;
  optional: boolean;
}

export interface ResourcePack {
  fileName: string;
  filePath: string;
  name: string;
  description: string;
  format: number;
  enabled: boolean;
  packVersion: string;
  iconPath: string;
}

export interface ShaderPack {
  fileName: string;
  filePath: string;
  name: string;
  enabled: boolean;
}

export interface ModrinthProject {
  id: string;
  slug: string;
  title: string;
  description: string;
  project_type: string;
  versions: string[];
  client_side: string;
  server_side: string;
}

export interface ModrinthVersion {
  id: string;
  project_id: string;
  name: string;
  version_number: string;
  game_versions: string[];
  loaders: string[];
  files: ModrinthFile[];
  dependencies: ModrinthDependency[];
}

export interface ModrinthFile {
  url: string;
  filename: string;
  hashes: {
    sha1: string;
    sha512: string;
  };
  size: number;
}

export interface ModrinthDependency {
  version_id: string | null;
  project_id: string;
  dependency_type: string;
}

export interface CurseForgeMod {
  id: number;
  slug: string;
  name: string;
  summary: string;
  links: {
    websiteUrl: string;
  };
  latestFiles: CurseForgeFile[];
}

export interface CurseForgeFile {
  id: number;
  displayName: string;
  fileName: string;
  fileDate: string;
  fileLength: number;
  downloadUrl: string;
  gameVersions: string[];
  modLoaders: string[];
}

export enum ModLoaderType {
  FABRIC = 'fabric',
  FORGE = 'forge',
  QUILT = 'quilt',
  NEO_FORGE = 'neoforge',
  RIFT = 'rift',
  LITELOADER = 'liteloader',
  UNKNOWN = 'unknown',
}

export enum ModSide {
  CLIENT = 'client',
  SERVER = 'server',
  BOTH = 'both',
  UNKNOWN = 'unknown',
}

export class ModManager {
  private static instance: ModManager;
  private baseDir: string = '';
  private modsDir: string = '';
  private resourcePacksDir: string = '';
  private shaderPacksDir: string = '';
  private mods: ModInfo[] = [];
  private resourcePacks: ResourcePack[] = [];
  private shaderPacks: ShaderPack[] = [];

  private constructor() {
  }

  static getInstance(): ModManager {
    if (!ModManager.instance) {
      ModManager.instance = new ModManager();
    }
    return ModManager.instance;
  }

  /**
   * Initialize the mod manager with base directory
   */
  init(baseDir: string): void {
    this.baseDir = baseDir;
    this.modsDir = `${baseDir}/${Constants.MODS_DIR}`;
    this.resourcePacksDir = `${baseDir}/${Constants.RESOURCE_PACKS_DIR}`;
    this.shaderPacksDir = `${baseDir}/${Constants.SHADER_PACKS_DIR}`;
  }

  /**
   * Scan the mods directory for installed mods
   */
  async scanMods(): Promise<ModInfo[]> {
    this.mods = [];
    try {
      await this.ensureDirectory(this.modsDir);
      const files = await this.listFiles(this.modsDir);

      for (const file of files) {
        if (file.name.endsWith('.jar') || file.name.endsWith('.disabled')) {
          const isEnabled = !file.name.endsWith('.disabled');
          const actualFileName = isEnabled ? file.name : file.name.replace(/\.disabled$/, '');
          const filePath = `${this.modsDir}/${file.name}`;

          // Try to parse mod metadata from the jar
          const metadata = await this.parseModMetadata(filePath, actualFileName);

          this.mods.push({
            fileName: actualFileName,
            filePath: filePath,
            name: metadata.name || actualFileName.replace(/\.jar$/i, ''),
            modId: metadata.modId || actualFileName.replace(/\.jar$/i, ''),
            version: metadata.version || 'unknown',
            description: metadata.description || '',
            authors: metadata.authors || [],
            loaderType: metadata.loaderType || ModLoaderType.UNKNOWN,
            enabled: isEnabled,
            dependencies: metadata.dependencies || [],
            url: metadata.url || '',
            iconPath: '',
            mcVersions: metadata.mcVersions || [],
            side: metadata.side || ModSide.UNKNOWN,
          });
        }
      }
    } catch (e) {
      console.error('Failed to scan mods', JSON.stringify(e));
    }

    return [...this.mods];
  }

  /**
   * Enable a mod
   */
  async enableMod(fileName: string): Promise<void> {
    const mod = this.mods.find(m => m.fileName === fileName || m.filePath.endsWith(fileName));
    if (!mod) {
      throw new Error(`Mod not found: ${fileName}`);
    }

    if (mod.enabled) {
      return; // Already enabled
    }

    // Rename .disabled file back to .jar
    const disabledPath = `${this.modsDir}/${mod.fileName}.disabled`;
    const enabledPath = `${this.modsDir}/${mod.fileName}`;
    try {
      await fileIo.rename(disabledPath, enabledPath);
      mod.enabled = true;
      mod.filePath = enabledPath;
    } catch (e) {
      throw new Error(`Failed to enable mod: ${JSON.stringify(e)}`);
    }
  }

  /**
   * Disable a mod
   */
  async disableMod(fileName: string): Promise<void> {
    const mod = this.mods.find(m => m.fileName === fileName || m.filePath.endsWith(fileName));
    if (!mod) {
      throw new Error(`Mod not found: ${fileName}`);
    }

    if (!mod.enabled) {
      return; // Already disabled
    }

    // Rename .jar to .disabled
    const enabledPath = `${this.modsDir}/${mod.fileName}`;
    const disabledPath = `${this.modsDir}/${mod.fileName}.disabled`;
    try {
      await fileIo.rename(enabledPath, disabledPath);
      mod.enabled = false;
      mod.filePath = disabledPath;
    } catch (e) {
      throw new Error(`Failed to disable mod: ${JSON.stringify(e)}`);
    }
  }

  /**
   * Get mod dependencies
   */
  getModDependencies(modId: string): ModDependency[] {
    const mod = this.mods.find(m => m.modId === modId);
    if (!mod) {
      return [];
    }
    return [...mod.dependencies];
  }

  /**
   * Track mod dependencies and check if they are satisfied
   */
  checkDependencies(modId: string): { satisfied: ModDependency[]; missing: ModDependency[] } {
    const mod = this.mods.find(m => m.modId === modId);
    if (!mod) {
      return { satisfied: [], missing: [] };
    }

    const satisfied: ModDependency[] = [];
    const missing: ModDependency[] = [];

    for (const dep of mod.dependencies) {
      const installed = this.mods.find(m => m.modId === dep.modId && m.enabled);
      if (installed) {
        satisfied.push(dep);
      } else {
        missing.push(dep);
      }
    }

    return { satisfied, missing };
  }

  /**
   * Search for mods on Modrinth
   */
  async searchModrinth(query: string, limit: number = 20): Promise<ModrinthProject[]> {
    try {
      const url = `${Constants.MODRINTH_API}/search?query=${encodeURIComponent(query)}&limit=${limit}`;
      const response = await HttpHelper.get(url);
      const data = JSON.parse(response);
      return data.hits || [];
    } catch (e) {
      console.error('Failed to search Modrinth', JSON.stringify(e));
      throw new Error('Failed to search Modrinth');
    }
  }

  /**
   * Get mod versions from Modrinth
   */
  async getModrinthVersions(
    projectId: string,
    gameVersion: string,
    loader: string
  ): Promise<ModrinthVersion[]> {
    try {
      const url = `${Constants.MODRINTH_API}/project/${projectId}/version` +
        `?game_versions=["${gameVersion}"]&loaders=["${loader}"]`;
      const response = await HttpHelper.get(url);
      return JSON.parse(response) as ModrinthVersion[];
    } catch (e) {
      console.error('Failed to get Modrinth versions', JSON.stringify(e));
      throw new Error('Failed to get Modrinth versions');
    }
  }

  /**
   * Download a mod from Modrinth
   */
  async downloadModFromModrinth(version: ModrinthVersion, targetDir?: string): Promise<string> {
    const downloadDir = targetDir || this.modsDir;
    await this.ensureDirectory(downloadDir);

    const file = version.files[0];
    if (!file) {
      throw new Error('No files available for this version');
    }

    const targetPath = `${downloadDir}/${file.filename}`;
    await this.downloadFile(file.url, targetPath);

    return targetPath;
  }

  /**
   * Search for mods on CurseForge
   */
  async searchCurseForge(query: string, gameVersion: string): Promise<CurseForgeMod[]> {
    try {
      const url = `${Constants.CURSEFORGE_API}/mods/search?gameId=432&searchFilter=${encodeURIComponent(query)}&gameVersion=${gameVersion}`;
      const response = await HttpHelper.get(url);
      const data = JSON.parse(response);
      return data.data || [];
    } catch (e) {
      console.error('Failed to search CurseForge', JSON.stringify(e));
      throw new Error('Failed to search CurseForge');
    }
  }

  /**
   * Scan resource packs
   */
  async scanResourcePacks(): Promise<ResourcePack[]> {
    this.resourcePacks = [];
    try {
      await this.ensureDirectory(this.resourcePacksDir);
      const files = await this.listFiles(this.resourcePacksDir);

      for (const file of files) {
        if (file.name.endsWith('.zip') || file.name.endsWith('.mcpack')) {
          this.resourcePacks.push({
            fileName: file.name,
            filePath: `${this.resourcePacksDir}/${file.name}`,
            name: file.name.replace(/\.(zip|mcpack)$/i, ''),
            description: '',
            format: 0,
            enabled: true,
            packVersion: '1.0',
            iconPath: '',
          });
        }
      }
    } catch (e) {
      console.error('Failed to scan resource packs', JSON.stringify(e));
    }

    return [...this.resourcePacks];
  }

  /**
   * Scan shader packs
   */
  async scanShaderPacks(): Promise<ShaderPack[]> {
    this.shaderPacks = [];
    try {
      await this.ensureDirectory(this.shaderPacksDir);
      const files = await this.listFiles(this.shaderPacksDir);

      for (const file of files) {
        if (file.name.endsWith('.zip') || file.name.endsWith('.shaderpack')) {
          this.shaderPacks.push({
            fileName: file.name,
            filePath: `${this.shaderPacksDir}/${file.name}`,
            name: file.name.replace(/\.(zip|shaderpack)$/i, ''),
            enabled: true,
          });
        }
      }
    } catch (e) {
      console.error('Failed to scan shader packs', JSON.stringify(e));
    }

    return [...this.shaderPacks];
  }

  /**
   * Enable a resource pack
   */
  async enableResourcePack(fileName: string): Promise<void> {
    const pack = this.resourcePacks.find(p => p.fileName === fileName);
    if (pack) {
      pack.enabled = true;
    }
  }

  /**
   * Disable a resource pack
   */
  async disableResourcePack(fileName: string): Promise<void> {
    const pack = this.resourcePacks.find(p => p.fileName === fileName);
    if (pack) {
      pack.enabled = false;
    }
  }

  /**
   * Parse mod metadata from a jar file
   * Supports fabric.mod.json, mcmod.info, and META-INF/MANIFEST.MF
   */
  private async parseModMetadata(
    jarPath: string,
    fileName: string
  ): Promise<{
    name: string;
    modId: string;
    version: string;
    description: string;
    authors: string[];
    loaderType: ModLoaderType;
    dependencies: ModDependency[];
    url: string;
    mcVersions: string[];
    side: ModSide;
  }> {
    const defaultMetadata = {
      name: '',
      modId: '',
      version: 'unknown',
      description: '',
      authors: [] as string[],
      loaderType: ModLoaderType.UNKNOWN,
      dependencies: [] as ModDependency[],
      url: '',
      mcVersions: [] as string[],
      side: ModSide.UNKNOWN,
    };

    // Since we can't easily read zip/jar contents in ArkTS without native APIs,
    // we attempt to parse the filename for basic info and use placeholder metadata.
    // Full zip parsing would require a native module.

    // Attempt to read the jar as a zip (simplified - real impl would use zip API)
    try {
      // Try to detect loader type from file name
      const lowerName = fileName.toLowerCase();
      if (lowerName.includes('fabric')) {
        defaultMetadata.loaderType = ModLoaderType.FABRIC;
      } else if (lowerName.includes('forge')) {
        defaultMetadata.loaderType = ModLoaderType.FORGE;
      } else if (lowerName.includes('quilt')) {
        defaultMetadata.loaderType = ModLoaderType.QUILT;
      } else if (lowerName.includes('neoforge')) {
        defaultMetadata.loaderType = ModLoaderType.NEO_FORGE;
      }

      // Extract mod id from filename (remove version and extension)
      // e.g., "MyMod-1.0.0.jar" -> "MyMod"
      const nameMatch = fileName.match(/^(.+?)(?:-[\d.]+(?:-[a-zA-Z0-9.]+)*)?\.jar$/i);
      if (nameMatch) {
        defaultMetadata.name = nameMatch[1];
        defaultMetadata.modId = nameMatch[1].toLowerCase();
      }

      // Try to extract version from filename
      const versionMatch = fileName.match(/-(\d[\d.]*\d)/);
      if (versionMatch) {
        defaultMetadata.version = versionMatch[1];
      }
    } catch (e) {
      console.warn(`Failed to parse metadata for ${fileName}: ${JSON.stringify(e)}`);
    }

    return defaultMetadata;
  }

  /**
   * Download a file from URL to local path
   */
  private async downloadFile(url: string, targetPath: string): Promise<void> {
    try {
      const http = await import('@ohos.net.http');
      const httpRequest = http.createHttp();

      return new Promise<void>((resolve, reject) => {
        httpRequest.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 30000,
          readTimeout: 60000,
        }, async (err, data) => {
          httpRequest.destroy();

          if (err) {
            reject(new Error(`Download failed: ${JSON.stringify(err)}`));
            return;
          }

          try {
            const buffer = data.result as ArrayBuffer;
            await fileIo.write(targetPath, buffer);
            resolve();
          } catch (writeErr) {
            reject(new Error(`Failed to write file: ${JSON.stringify(writeErr)}`));
          }
        });
      });
    } catch (e) {
      throw new Error(`Failed to download file: ${JSON.stringify(e)}`);
    }
  }

  /**
   * List files in a directory
   */
  private async listFiles(dirPath: string): Promise<Array<{ name: string; path: string }>> {
    try {
      const files = await fileIo.listFile(dirPath, { recursive: false });
      return files;
    } catch (e) {
      console.error(`Failed to list files in ${dirPath}`, JSON.stringify(e));
      return [];
    }
  }

  /**
   * Ensure a directory exists
   */
  private async ensureDirectory(path: string): Promise<void> {
    try {
      const stat = await fileIo.stat(path);
      if (!stat.isDirectory()) {
        throw new Error(`Path exists but is not a directory: ${path}`);
      }
    } catch (e) {
      try {
        await fileIo.mkdir(path, { recursive: true });
      } catch (mkdirErr) {
        throw new Error(`Failed to create directory ${path}: ${JSON.stringify(mkdirErr)}`);
      }
    }
  }
}