/**
 * ModLoaderInstaller — Forge / Fabric / Quilt / NeoForge 自动安装器
 *
 * 参照 AMCL 的安装模式，在 HarmonyOS 上实现模组加载器的安装。
 * 
 * 核心逻辑：
 * 1. 从 Maven 获取安装器元数据（install_profile.json）
 * 2. 解析元数据，提取 version.json 和 library 列表
 * 3. 生成正确的 version.json（含 inheritsFrom 指向原版）
 * 4. 下载所有需要的 libraries
 * 5. 完成安装
 *
 * [API 26+] 使用 @ohos.net.http 下载 / @ohos.file.fs 写文件
 */

import { GameInstallation, GameVersionJson, Library, LoaderType, Artifact } from '../../model/GameVersion';
import { HttpClient } from '../network/HttpClient';
import { Constants } from '../../config/Constants';
import { Logger, FileUtils } from '../util/Utils';
import { VersionManager } from './VersionManager';

export enum ModLoader {
  FORGE = 'forge',
  FABRIC = 'fabric',
  QUILT = 'quilt',
  NEO_FORGE = 'neoforge',
}

export interface LoaderVersion {
  /** 模组加载器类型 */
  loader: ModLoader;
  /** 加载器版本号（如 49.0.19） */
  version: string;
  /** 对应的 Minecraft 版本（如 1.20.4） */
  mcVersion: string;
  /** 完整版本 ID（如 1.20.4-forge-49.0.19） */
  fullVersionId: string;
}

export interface InstallProgress {
  phase: string;
  progress: number; // 0-100
  message: string;
}

export type ProgressCallback = (progress: InstallProgress) => void;

/**
 * Forge 安装器的 install_profile.json 结构
 */
interface ForgeInstallProfile {
  spec: number;
  profile: string;
  version: string;
  icon?: string;
  json: string;
  path?: string;
  minecraft: string;
  data?: Record<string, ForgeInstallData>;
  processors?: ForgeProcessor[];
  libraries: Library[];
  iconOverride?: string;
}

interface ForgeInstallData {
  client: string;
  server: string;
}

interface ForgeProcessor {
  sides: string[];
  jar: string;
  classpath: string[];
  args: string[];
  outputs?: Record<string, string>;
}

interface FabricLoaderInfo {
  separator: string;
  build: number;
  maven: string;
  version: string;
  stable: boolean;
}

interface FabricLauncherLibraries {
  client: Library[];
  common: Library[];
  server: Library[];
}

interface FabricLauncherMainClass {
  client: string;
  server: string;
}

interface FabricLauncherMeta {
  libraries: FabricLauncherLibraries;
  mainClass: FabricLauncherMainClass;
  version: number;
}

/**
 * Fabric/Quilt 安装器元数据
 */
interface FabricLoaderMeta {
  loader: FabricLoaderInfo;
  intermediary: FabricLoaderInfo;
  launcherMeta: FabricLauncherMeta;
}

/**
 * Fabric/Quilt Maven 版本列表
 */
interface MavenVersionList {
  versions: string[];
  latest?: string;
}

export class ModLoaderInstaller {
  private static readonly TAG = 'ModLoaderInstaller';
  private static instance: ModLoaderInstaller;
  private baseDir: string = '';
  private versionManager: VersionManager;

  private constructor() {
    this.versionManager = VersionManager.getInstance();
  }

  static getInstance(): ModLoaderInstaller {
    if (!ModLoaderInstaller.instance) {
      ModLoaderInstaller.instance = new ModLoaderInstaller();
    }
    return ModLoaderInstaller.instance;
  }

  init(baseDir: string): void {
    this.baseDir = baseDir;
    Logger.info(ModLoaderInstaller.TAG, `ModLoaderInstaller initialized, baseDir: ${baseDir}`);
  }

  // ============================================================
  // 公开 API
  // ============================================================

  /**
   * 获取某个模组加载器的可用版本列表
   */
  async getAvailableVersions(loader: ModLoader, mcVersion: string): Promise<LoaderVersion[]> {
    switch (loader) {
      case ModLoader.FORGE:
        return this.getForgeVersions(mcVersion);
      case ModLoader.NEO_FORGE:
        return this.getNeoForgeVersions(mcVersion);
      case ModLoader.FABRIC:
        return this.getFabricVersions(mcVersion);
      case ModLoader.QUILT:
        return this.getQuiltVersions(mcVersion);
      default:
        return [];
    }
  }

  /**
   * 安装模组加载器到指定 Minecraft 版本
   */
  async installLoader(
    loader: ModLoader,
    mcVersion: string,
    loaderVersion: string,
    onProgress?: ProgressCallback
  ): Promise<GameInstallation> {
    const fullVersionId = `${mcVersion}-${loader}-${loaderVersion}`;
    Logger.info(ModLoaderInstaller.TAG, `Installing ${fullVersionId}`);

    this.reportProgress(onProgress, 'Preparing', 5, `Preparing to install ${loader} ${loaderVersion} for MC ${mcVersion}`);

    switch (loader) {
      case ModLoader.FORGE:
        return this.installForge(mcVersion, loaderVersion, fullVersionId, onProgress);
      case ModLoader.NEO_FORGE:
        return this.installNeoForge(mcVersion, loaderVersion, fullVersionId, onProgress);
      case ModLoader.FABRIC:
        return this.installFabric(loader, mcVersion, loaderVersion, fullVersionId, onProgress);
      case ModLoader.QUILT:
        return this.installFabric(loader, mcVersion, loaderVersion, fullVersionId, onProgress);
      default:
        throw new Error(`Unknown loader: ${loader}`);
    }
  }

  /**
   * 检测某个版本是否已安装模组加载器
   */
  async detectLoader(versionId: string): Promise<LoaderType | null> {
    try {
      const versionJson = await this.versionManager.getVersionInfo(versionId);
      if (!versionJson) return null;

      const id = versionJson.id.toLowerCase();
      if (id.includes('forge')) return LoaderType.FORGE;
      if (id.includes('neoforge')) return LoaderType.NEO_FORGE;
      if (id.includes('fabric')) return LoaderType.FABRIC;
      if (id.includes('quilt')) return LoaderType.QUILT;
      if (versionJson.inheritsFrom) {
        return LoaderType.VANILLA; // inheritsFrom 但没识别出具体 loader
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // Forge 安装
  // ============================================================

  /**
   * 获取 Forge 版本列表
   * Forge Maven: net.minecraftforge:forge:{mc_version}-{loader_version}
   * 元数据 URL: https://maven.minecraftforge.net/net/minecraftforge/forge/{mc_version}-{loader_version}/forge-{mc_version}-{loader_version}-installer.json
   */
  private async getForgeVersions(mcVersion: string): Promise<LoaderVersion[]> {
    // Forge 的版本列表通过 maven-metadata.xml 获取
    const metadataUrl = `${Constants.FORGE_MAVEN}/net/minecraftforge/forge/maven-metadata.xml`;
    Logger.info(ModLoaderInstaller.TAG, `Fetching Forge versions from: ${metadataUrl}`);

    try {
      const result = await HttpClient.getText(metadataUrl);
      if (!result.success || !result.data) return [];

      const xml = result.data;
      const versions: string[] = [];
      // 解析 XML 提取版本号
      const versionRegex = /<version>([^<]+)<\/version>/g;
      let match: RegExpExecArray | null;
      while ((match = versionRegex.exec(xml)) !== null) {
        const version = match[1] as string;
        // 只取匹配当前 MC 版本的
        if (version.startsWith(mcVersion + '-')) {
          versions.push(version);
        }
      }

      // 去重、排序（最新的在前）
      const uniqueMap: Record<string, boolean> = {};
      const uniqueVersions: string[] = [];
      for (const v of versions) {
        if (!uniqueMap[v]) {
          uniqueMap[v] = true;
          uniqueVersions.push(v);
        }
      }
      uniqueVersions.sort().reverse();

      const forgeVersions: LoaderVersion[] = [];
      for (const v of uniqueVersions) {
        const loaderVer = v.substring(mcVersion.length + 1); // 去掉 "1.20.4-"
        const lv: LoaderVersion = {
          loader: ModLoader.FORGE,
          version: loaderVer,
          mcVersion: mcVersion,
          fullVersionId: v,
        };
        forgeVersions.push(lv);
      }
      return forgeVersions;
    } catch (e) {
      Logger.error(ModLoaderInstaller.TAG, `Failed to fetch Forge versions: ${(e as Error).message}`);
      return [];
    }
  }

  /**
   * 安装 Forge
   * 
   * 流程（参照 AMCL）：
   * 1. 下载 install_profile.json（含 version.json + libraries）
   * 2. 解析出 version.json（含 inheritsFrom 指向原版）
   * 3. 保存 version.json 到 versions/{versionId}/
   * 4. 下载所有 libraries
   * 5. Forge 的 processor 步骤不需要在 HarmonyOS 上执行（AMCL 已跳过）
   */
  private async installForge(
    mcVersion: string,
    loaderVersion: string,
    fullVersionId: string,
    onProgress?: ProgressCallback
  ): Promise<GameInstallation> {
    // 步骤 1: 下载 install_profile.json
    const forgeVersion = `${mcVersion}-${loaderVersion}`;
    const profileUrl = `${Constants.FORGE_MAVEN}/net/minecraftforge/forge/${forgeVersion}/forge-${forgeVersion}-installer.json`;
    const profileMirrorUrl = `${Constants.BMCLAPI_FORGE_MAVEN}/net/minecraftforge/forge/${forgeVersion}/forge-${forgeVersion}-installer.json`;

    this.reportProgress(onProgress, 'Downloading metadata', 10, `Downloading Forge install profile...`);

    let profileData: string | null = null;
    try {
      const result = await HttpClient.getText(profileUrl);
      if (result.success && result.data) {
        profileData = result.data;
      }
    } catch (e) {
      Logger.warn(ModLoaderInstaller.TAG, `Forge profile fetch failed from maven, trying BMCLAPI mirror`);
    }

    // Fallback to BMCLAPI mirror
    if (!profileData) {
      try {
        const result = await HttpClient.getText(profileMirrorUrl);
        if (result.success && result.data) {
          profileData = result.data;
        }
      } catch (e) {
        throw new Error(`Failed to fetch Forge install profile from all sources`);
      }
    }

    if (!profileData) {
      throw new Error(`Failed to fetch Forge install profile for ${forgeVersion}`);
    }

    const profile: ForgeInstallProfile = JSON.parse(profileData);
    Logger.info(ModLoaderInstaller.TAG, `Forge install profile parsed: minecraft=${profile.minecraft}, version=${profile.version}`);

    // 步骤 2: 解析 version.json（install_profile 的 json 字段是 version.json 的字符串）
    this.reportProgress(onProgress, 'Processing', 20, 'Processing version JSON...');
    let versionJson: GameVersionJson;
    try {
      versionJson = JSON.parse(profile.json) as GameVersionJson;
    } catch (e) {
      throw new Error(`Failed to parse Forge version JSON: ${(e as Error).message}`);
    }

    // 确保 version.json 有正确的 inheritsFrom
    versionJson.id = fullVersionId;
    if (!versionJson.inheritsFrom) {
      versionJson.inheritsFrom = mcVersion;
    }

    // 添加 Forge 的 libraries（来自 install_profile 的 libraries 字段）
    const forgeLibs = profile.libraries || [];
    versionJson.libraries = versionJson.libraries || [];
    for (const lib of forgeLibs) {
      const exists = versionJson.libraries.some((l) => l.name === lib.name);
      if (!exists) {
        versionJson.libraries.push(lib);
      }
    }

    // 步骤 3: 保存 version.json
    this.reportProgress(onProgress, 'Saving', 30, 'Saving version JSON...');
    const versionDir = `${this.baseDir}/${Constants.VERSIONS_DIR}/${fullVersionId}`;
    FileUtils.mkdirs(versionDir);
    FileUtils.writeFile(`${versionDir}/${fullVersionId}.json`, JSON.stringify(versionJson, null, 2));

    // 步骤 4: 下载所有 libraries
    this.reportProgress(onProgress, 'Downloading libraries', 40, 'Downloading libraries...');
    await this.downloadLibraries(versionJson.libraries || [], profile.libraries || [], onProgress);

    // 步骤 5: 确保原版版本已安装（满足 inheritsFrom）
    this.reportProgress(onProgress, 'Verifying parent', 90, 'Verifying parent version...');
    try {
      await this.versionManager.getVersionInfo(mcVersion);
    } catch (e) {
      // 原版还没安装，需要先安装
      Logger.info(ModLoaderInstaller.TAG, `Parent version ${mcVersion} not installed, installing first`);
      await this.versionManager.installVersion(mcVersion);
    }

    this.reportProgress(onProgress, 'Complete', 100, 'Forge installation complete!');

    return this.buildInstallation(fullVersionId, mcVersion, LoaderType.FORGE, loaderVersion);
  }

  // ============================================================
  // NeoForge 安装
  // ============================================================

  /**
   * NeoForge 和 Forge 的安装流程基本相同，只是 Maven 仓库不同
   */
  private async getNeoForgeVersions(mcVersion: string): Promise<LoaderVersion[]> {
    const metadataUrl = `${Constants.NEO_FORGE_MAVEN}/net/neoforged/neoforge/maven-metadata.xml`;
    Logger.info(ModLoaderInstaller.TAG, `Fetching NeoForge versions from: ${metadataUrl}`);

    try {
      const result = await HttpClient.getText(metadataUrl);
      if (!result.success || !result.data) return [];

      const xml = result.data;
      const versions: string[] = [];
      const versionRegex = /<version>([^<]+)<\/version>/g;
      let match: RegExpExecArray | null;
      while ((match = versionRegex.exec(xml)) !== null) {
        const version = match[1] as string;
        if (version.startsWith(mcVersion + '-')) {
          versions.push(version);
        }
      }

      const uniqueMap: Record<string, boolean> = {};
      const uniqueVersions: string[] = [];
      for (const v of versions) {
        if (!uniqueMap[v]) {
          uniqueMap[v] = true;
          uniqueVersions.push(v);
        }
      }
      uniqueVersions.sort().reverse();
      const neoVersions: LoaderVersion[] = [];
      for (const v of uniqueVersions) {
        const loaderVer = v.substring(mcVersion.length + 1);
        const lv: LoaderVersion = {
          loader: ModLoader.NEO_FORGE,
          version: loaderVer,
          mcVersion: mcVersion,
          fullVersionId: v,
        };
        neoVersions.push(lv);
      }
      return neoVersions;
    } catch (e) {
      Logger.error(ModLoaderInstaller.TAG, `Failed to fetch NeoForge versions: ${(e as Error).message}`);
      return [];
    }
  }

  private async installNeoForge(
    mcVersion: string,
    loaderVersion: string,
    fullVersionId: string,
    onProgress?: ProgressCallback
  ): Promise<GameInstallation> {
    const neoVersion = `${mcVersion}-${loaderVersion}`;
    const profileUrl = `${Constants.NEO_FORGE_MAVEN}/net/neoforged/neoforge/${neoVersion}/neoforge-${neoVersion}-installer.json`;

    this.reportProgress(onProgress, 'Downloading metadata', 10, 'Downloading NeoForge install profile...');

    const result = await HttpClient.getText(profileUrl);
    if (!result.success || !result.data) {
      throw new Error(`Failed to fetch NeoForge install profile for ${neoVersion}`);
    }

    const profile: ForgeInstallProfile = JSON.parse(result.data);
    Logger.info(ModLoaderInstaller.TAG, `NeoForge install profile parsed: minecraft=${profile.minecraft}`);

    // 解析 version.json
    this.reportProgress(onProgress, 'Processing', 20, 'Processing version JSON...');
    const versionJson: GameVersionJson = JSON.parse(profile.json) as GameVersionJson;
    versionJson.id = fullVersionId;
    if (!versionJson.inheritsFrom) {
      versionJson.inheritsFrom = mcVersion;
    }

    // 合并 libraries
    const neoLibs = profile.libraries || [];
    versionJson.libraries = versionJson.libraries || [];
    for (const lib of neoLibs) {
      const exists = versionJson.libraries.some((l) => l.name === lib.name);
      if (!exists) {
        versionJson.libraries.push(lib);
      }
    }

    // 保存 version.json
    this.reportProgress(onProgress, 'Saving', 30, 'Saving version JSON...');
    const versionDir = `${this.baseDir}/${Constants.VERSIONS_DIR}/${fullVersionId}`;
    FileUtils.mkdirs(versionDir);
    FileUtils.writeFile(`${versionDir}/${fullVersionId}.json`, JSON.stringify(versionJson, null, 2));

    // 下载 libraries
    this.reportProgress(onProgress, 'Downloading libraries', 40, 'Downloading libraries...');
    await this.downloadLibraries(versionJson.libraries || [], neoLibs, onProgress);

    // 确保原版已安装
    this.reportProgress(onProgress, 'Verifying parent', 90, 'Verifying parent version...');
    try {
      await this.versionManager.getVersionInfo(mcVersion);
    } catch (e) {
      await this.versionManager.installVersion(mcVersion);
    }

    this.reportProgress(onProgress, 'Complete', 100, 'NeoForge installation complete!');
    return this.buildInstallation(fullVersionId, mcVersion, LoaderType.NEO_FORGE, loaderVersion);
  }

  // ============================================================
  // Fabric / Quilt 安装
  // ============================================================

  /**
   * Fabric 安装流程（参照 AMCL）：
   * 1. 获取 Fabric Loader 版本列表
   * 2. 获取 Fabric Installer 元数据（launcherMeta）
   * 3. 生成 version.json：
   *    - mainClass: launcherMeta.mainClass.client
   *    - inheritsFrom: mcVersion
   *    - libraries: launcherMeta.libraries.client + launcherMeta.libraries.common
   */
  private async getFabricVersions(mcVersion: string): Promise<LoaderVersion[]> {
    const mavenBase = Constants.FABRIC_MAVEN;
    const metadataUrl = `${mavenBase}/net/fabricmc/fabric-loader/maven-metadata.xml`;

    try {
      const result = await HttpClient.getText(metadataUrl);
      if (!result.success || !result.data) return [];

      const xml = result.data;
      const versions: string[] = [];
      const versionRegex = /<version>([^<]+)<\/version>/g;
      let match: RegExpExecArray | null;
      while ((match = versionRegex.exec(xml)) !== null) {
        versions.push(match[1] as string);
      }

      // Fabric loader 版本不包含 MC 版本号，所以全都返回
      const uniqueMap: Record<string, boolean> = {};
      const uniqueVersions: string[] = [];
      for (const v of versions) {
        if (!uniqueMap[v]) {
          uniqueMap[v] = true;
          uniqueVersions.push(v);
        }
      }
      uniqueVersions.sort().reverse();
      const resultVersions: LoaderVersion[] = [];
      for (const v of uniqueVersions) {
        const lv: LoaderVersion = {
          loader: ModLoader.FABRIC,
          version: v,
          mcVersion: mcVersion,
          fullVersionId: `${mcVersion}-fabric-${v}`,
        };
        resultVersions.push(lv);
      }
      return resultVersions;
    } catch (e) {
      Logger.error(ModLoaderInstaller.TAG, `Failed to fetch Fabric versions: ${(e as Error).message}`);
      return [];
    }
  }

  /**
   * 获取 Quilt 版本列表
   */
  private async getQuiltVersions(mcVersion: string): Promise<LoaderVersion[]> {
    const metadataUrl = `${Constants.QUILT_MAVEN}/org/quiltmc/quilt-loader/maven-metadata.xml`;

    try {
      const result = await HttpClient.getText(metadataUrl);
      if (!result.success || !result.data) return [];

      const xml = result.data;
      const versions: string[] = [];
      const versionRegex = /<version>([^<]+)<\/version>/g;
      let match: RegExpExecArray | null;
      while ((match = versionRegex.exec(xml)) !== null) {
        versions.push(match[1] as string);
      }

      const uniqueMap2: Record<string, boolean> = {};
      const uniqueVersions2: string[] = [];
      for (const v of versions) {
        if (!uniqueMap2[v]) {
          uniqueMap2[v] = true;
          uniqueVersions2.push(v);
        }
      }
      uniqueVersions2.sort().reverse();
      const quiltVersions: LoaderVersion[] = [];
      for (const v of uniqueVersions2) {
        const lv: LoaderVersion = {
          loader: ModLoader.QUILT,
          version: v,
          mcVersion: mcVersion,
          fullVersionId: `${mcVersion}-quilt-${v}`,
        };
        quiltVersions.push(lv);
      }
      return quiltVersions;
    } catch (e) {
      Logger.error(ModLoaderInstaller.TAG, `Failed to fetch Quilt versions: ${(e as Error).message}`);
      return [];
    }
  }

  /**
   * 安装 Fabric 或 Quilt
   * 
   * 流程：
   * 1. 获取 Fabric Loader 的 launcherMeta（从 Maven 下载 fabric-loader-{version}.json）
   * 2. 生成 version.json
   * 3. 下载 libraries
   * 4. 确保原版已安装
   */
  private async installFabric(
    loader: ModLoader,
    mcVersion: string,
    loaderVersion: string,
    fullVersionId: string,
    onProgress?: ProgressCallback
  ): Promise<GameInstallation> {
    const mavenBase = loader === ModLoader.QUILT ? Constants.QUILT_MAVEN : Constants.FABRIC_MAVEN;
    const mavenPath = loader === ModLoader.QUILT
      ? 'org/quiltmc/quilt-loader'
      : 'net/fabricmc/fabric-loader';

    // 步骤 1: 获取 Fabric Loader 的元数据
    // Fabric Loader 的 JSON 元数据在 Maven 中：fabric-loader-{version}.json
    // 包含 launcherMeta 字段，定义了 mainClass 和 libraries
    const loaderMetaUrl = `${mavenBase}/${mavenPath}/${loaderVersion}/${mavenPath.substring(mavenPath.lastIndexOf('/') + 1)}-${loaderVersion}.json`;
    const loaderMetaMirrorUrl = loader === ModLoader.QUILT
      ? `${Constants.BMCLAPI_FABRIC_MAVEN}/${mavenPath}/${loaderVersion}/${mavenPath.substring(mavenPath.lastIndexOf('/') + 1)}-${loaderVersion}.json`
      : `${Constants.BMCLAPI_FABRIC_MAVEN}/${mavenPath}/${loaderVersion}/${mavenPath.substring(mavenPath.lastIndexOf('/') + 1)}-${loaderVersion}.json`;

    this.reportProgress(onProgress, 'Downloading metadata', 10, `Downloading ${loader} loader metadata...`);

    let metaData: string | null = null;
    try {
      const result = await HttpClient.getText(loaderMetaUrl);
      if (result.success && result.data) {
        metaData = result.data;
      }
    } catch (e) {
      Logger.warn(ModLoaderInstaller.TAG, `${loader} meta fetch failed, trying BMCLAPI mirror`);
    }

    if (!metaData) {
      try {
        const result = await HttpClient.getText(loaderMetaMirrorUrl);
        if (result.success && result.data) {
          metaData = result.data;
        }
      } catch (e) {
        throw new Error(`Failed to fetch ${loader} loader metadata from all sources`);
      }
    }

    if (!metaData) {
      throw new Error(`Failed to fetch ${loader} loader metadata for ${loaderVersion}`);
    }

    const loaderMeta: FabricLoaderMeta = JSON.parse(metaData);
    Logger.info(ModLoaderInstaller.TAG, `${loader} loader meta parsed: mainClass=${loaderMeta.launcherMeta.mainClass.client}`);

    // 步骤 2: 生成 version.json
    this.reportProgress(onProgress, 'Generating version JSON', 20, `Generating ${loader} version JSON...`);

    const clientLibraries = loaderMeta.launcherMeta.libraries.client || [];
    const commonLibraries = loaderMeta.launcherMeta.libraries.common || [];
    const allLibraries: Library[] = [];

    // 合并 client + common libraries（去重）
    const libNames = new Set<string>();
    for (const lib of [...clientLibraries, ...commonLibraries]) {
      if (!libNames.has(lib.name)) {
        libNames.add(lib.name);
        allLibraries.push(lib);
      }
    }

    const versionJson: GameVersionJson = {
      id: fullVersionId,
      type: 'release',
      time: new Date().toISOString(),
      releaseTime: new Date().toISOString(),
      mainClass: loaderMeta.launcherMeta.mainClass.client,
      inheritsFrom: mcVersion,
      minimumLauncherVersion: 0,
      assets: '1.21', // 会被 inheritsFrom 覆盖
      assetIndex: { id: mcVersion, sha1: '', size: 0, totalSize: 0, url: '' },
      downloads: { client: { sha1: '', size: 0, url: '' } },
      libraries: allLibraries,
    };

    // 步骤 3: 保存 version.json
    this.reportProgress(onProgress, 'Saving', 30, 'Saving version JSON...');
    const versionDir = `${this.baseDir}/${Constants.VERSIONS_DIR}/${fullVersionId}`;
    FileUtils.mkdirs(versionDir);
    FileUtils.writeFile(`${versionDir}/${fullVersionId}.json`, JSON.stringify(versionJson, null, 2));

    // 步骤 4: 下载 libraries
    this.reportProgress(onProgress, 'Downloading libraries', 40, 'Downloading libraries...');
    await this.downloadLibraries(allLibraries, [], onProgress);

    // 步骤 5: 确保原版已安装
    this.reportProgress(onProgress, 'Verifying parent', 90, 'Verifying parent version...');
    try {
      await this.versionManager.getVersionInfo(mcVersion);
    } catch (e) {
      await this.versionManager.installVersion(mcVersion);
    }

    this.reportProgress(onProgress, 'Complete', 100, `${loader === ModLoader.QUILT ? 'Quilt' : 'Fabric'} installation complete!`);
    const loaderType = loader === ModLoader.QUILT ? LoaderType.QUILT : LoaderType.FABRIC;
    return this.buildInstallation(fullVersionId, mcVersion, loaderType, loaderVersion);
  }

  // ============================================================
  // 通用工具方法
  // ============================================================

  /**
   * 下载所有 libraries
   */
  private async downloadLibraries(
    libraries: Library[],
    extraLibs: Library[],
    onProgress?: ProgressCallback
  ): Promise<void> {
    const allLibs = [...libraries, ...extraLibs];
    const total = allLibs.length;
    let completed = 0;

    for (const lib of allLibs) {
      if (!lib.name || !lib.downloads?.artifact?.url) {
        completed++;
        continue;
      }

      const artifact = lib.downloads.artifact;
      const libPath = artifact.path || this.mavenNameToPath(lib);
      const targetPath = `${this.baseDir}/${Constants.LIBRARIES_DIR}/${libPath}`;

      // 检查是否已存在
      if (FileUtils.exists(targetPath)) {
        completed++;
        continue;
      }

      // 确保父目录存在
      const parentDir = targetPath.substring(0, targetPath.lastIndexOf('/'));
      FileUtils.mkdirs(parentDir);

      try {
        // 用 BMCLAPI 镜像加速
        const downloadUrl = this.getMirrorUrl(artifact.url);
        await HttpClient.downloadFile(downloadUrl, targetPath);
        Logger.info(ModLoaderInstaller.TAG, `Downloaded library: ${lib.name}`);
      } catch (e) {
        Logger.warn(ModLoaderInstaller.TAG, `Failed to download library ${lib.name}: ${(e as Error).message}, trying original URL`);
        // 重试原始 URL
        try {
          await HttpClient.downloadFile(artifact.url, targetPath);
        } catch (e2) {
          Logger.warn(ModLoaderInstaller.TAG, `Failed to download library ${lib.name} from original URL: ${(e2 as Error).message}`);
        }
      }

      completed++;
      const pct = 40 + Math.floor((completed / total) * 45);
      this.reportProgress(onProgress, 'Downloading libraries', pct, `Downloaded ${completed}/${total} libraries...`);
    }
  }

  /**
   * 将 Maven 坐标转为文件路径
   */
  private mavenNameToPath(lib: Library): string {
    const parts = lib.name.split(':');
    if (parts.length < 3) return lib.name;

    const group = parts[0].replace(/\./g, '/');
    const artifact = parts[1];
    const version = parts[2];
    const classifier = parts.length >= 4 ? `-${parts[3]}` : '';

    return `${group}/${artifact}/${version}/${artifact}-${version}${classifier}.jar`;
  }

  /**
   * 获取镜像 URL
   */
  private getMirrorUrl(originalUrl: string): string {
    if (originalUrl.includes('libraries.minecraft.net')) {
      return originalUrl.replace(
        'https://libraries.minecraft.net',
        Constants.BMCLAPI_LIBRARIES_BASE
      );
    }
    if (originalUrl.includes('maven.minecraftforge.net')) {
      return originalUrl.replace(
        'https://maven.minecraftforge.net',
        Constants.BMCLAPI_FORGE_MAVEN
      );
    }
    if (originalUrl.includes('maven.fabricmc.net')) {
      return originalUrl.replace(
        'https://maven.fabricmc.net',
        Constants.BMCLAPI_FABRIC_MAVEN
      );
    }
    return originalUrl;
  }

  /**
   * 构建 GameInstallation 对象
   */
  private buildInstallation(
    versionId: string,
    gameVersion: string,
    loaderType: LoaderType,
    loaderVersion: string
  ): GameInstallation {
    return {
      versionId: versionId,
      name: versionId,
      directory: `${this.baseDir}/${Constants.VERSIONS_DIR}/${versionId}`,
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
      customGameArgs: '',
    };
  }

  /**
   * 报告进度
   */
  private reportProgress(
    callback: ProgressCallback | undefined,
    phase: string,
    progress: number,
    message: string
  ): void {
    if (callback) {
      callback({ phase, progress, message });
    }
    Logger.info(ModLoaderInstaller.TAG, `[${phase}] ${progress}%: ${message}`);
  }
}