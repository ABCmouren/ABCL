/**
 * AssetsManager — Minecraft 资产（资源包）下载管理器
 *
 * 管理 asset index 的下载和 asset objects 的下载缓存。
 * Minecraft 的 asset objects 存放在 assets/objects/{hash前2位}/{hash} 路径下。
 *
 * 流程：
 * 1. 从 VersionManager 获取版本信息，得到 assetIndex URL
 * 2. 下载 asset index JSON（assets/indexes/{id}.json）
 * 3. 遍历 objects 列表，下载缺失的 asset objects
 *
 * [API 26+] 使用 @ohos.net.http 下载 / @ohos.file.fs 写文件
 */

import { HttpClient } from '../network/HttpClient';
import { Constants } from '../../config/Constants';
import { Logger, FileUtils } from '../util/Utils';
import { VersionManager } from './VersionManager';

export interface AssetObject {
  hash: string;
  size: number;
}

export interface AssetIndexData {
  objects: Record<string, AssetObject>;
  virtual?: boolean;
  map_to_resources?: boolean;
}

export interface AssetDownloadProgress {
  totalObjects: number;
  completedObjects: number;
  currentObject: string;
  totalBytes: number;
  completedBytes: number;
}

export type AssetProgressCallback = (progress: AssetDownloadProgress) => void;

export class AssetsManager {
  private static readonly TAG = 'AssetsManager';
  private static instance: AssetsManager;
  private baseDir: string = '';
  private versionManager: VersionManager;

  private constructor() {
    this.versionManager = VersionManager.getInstance();
  }

  static getInstance(): AssetsManager {
    if (!AssetsManager.instance) {
      AssetsManager.instance = new AssetsManager();
    }
    return AssetsManager.instance;
  }

  init(baseDir: string): void {
    this.baseDir = baseDir;
    Logger.info(AssetsManager.TAG, `AssetsManager initialized, baseDir: ${baseDir}`);
  }

  /**
   * 确保某个 Minecraft 版本的 asset 已下载
   * @param versionId 版本 ID
   * @param onProgress 进度回调
   */
  async ensureAssets(
    versionId: string,
    onProgress?: AssetProgressCallback
  ): Promise<void> {
    Logger.info(AssetsManager.TAG, `Ensuring assets for ${versionId}`);

    // 1. 获取版本的 asset index 信息
    const versionJson = await this.versionManager.getResolvedVersionInfo(versionId);
    const assetIndex = versionJson.assetIndex;
    if (!assetIndex || !assetIndex.url) {
      Logger.warn(AssetsManager.TAG, `No asset index for ${versionId}, skipping`);
      return;
    }

    // 2. 下载 asset index JSON
    const indexDir = `${this.baseDir}/${Constants.ASSETS_DIR}/indexes`;
    FileUtils.mkdirs(indexDir);
    const indexId = assetIndex.id || versionId;
    const indexPath = `${indexDir}/${indexId}.json`;

    let indexData: AssetIndexData;
    if (FileUtils.exists(indexPath)) {
      // 已缓存
      try {
        indexData = JSON.parse(FileUtils.readFile(indexPath)) as AssetIndexData;
        Logger.info(AssetsManager.TAG, `Asset index for ${indexId} loaded from cache`);
      } catch (e) {
        Logger.warn(AssetsManager.TAG, `Cached asset index corrupted, re-downloading`);
        indexData = await this.downloadAssetIndex(assetIndex.url, indexPath);
      }
    } else {
      indexData = await this.downloadAssetIndex(assetIndex.url, indexPath);
    }

    // 3. 下载缺失的 asset objects
    await this.downloadMissingObjects(indexData, indexId, onProgress);
  }

  /**
   * 下载 asset index JSON
   */
  private async downloadAssetIndex(url: string, savePath: string): Promise<AssetIndexData> {
    // 尝试镜像源
    let result = await HttpClient.getText(url);
    if (!result.success || !result.data) {
      // 尝试 BMCLAPI 镜像
      const mirrorUrl = url.replace('https://piston-meta.mojang.com', Constants.BMCLAPI_VERSION_BASE);
      Logger.info(AssetsManager.TAG, `Trying BMCLAPI mirror: ${mirrorUrl}`);
      result = await HttpClient.getText(mirrorUrl);
    }
    if (!result.success || !result.data) {
      throw new Error(`Failed to download asset index from all sources`);
    }

    FileUtils.writeFile(savePath, result.data);
    Logger.info(AssetsManager.TAG, `Asset index saved to ${savePath}`);
    return JSON.parse(result.data) as AssetIndexData;
  }

  /**
   * 下载缺失的 asset objects
   */
  private async downloadMissingObjects(
    indexData: AssetIndexData,
    indexId: string,
    onProgress?: AssetProgressCallback
  ): Promise<void> {
    const objectsDir = `${this.baseDir}/${Constants.ASSETS_DIR}/objects`;
    FileUtils.mkdirs(objectsDir);

    const objectEntries = Object.entries(indexData.objects || {});
    const total = objectEntries.length;
    let completed = 0;
    let completedBytes = 0;
    let totalBytes = 0;

    // 计算总大小
    for (const entry of objectEntries) {
      totalBytes += entry[1].size;
    }

    Logger.info(AssetsManager.TAG, `Total objects to check: ${total}, total size: ${totalBytes} bytes`);

    for (const entry of objectEntries) {
      const objectName = entry[0];
      const assetObj = entry[1];
      const hash = assetObj.hash;
      const subDir = hash.substring(0, 2);
      const objectPath = `${objectsDir}/${subDir}/${hash}`;

      // 检查是否已存在（按 hash 路径）
      if (FileUtils.exists(objectPath)) {
        // 验证文件大小（快速校验）
        const existingSize = FileUtils.getFileSize(objectPath);
        if (existingSize === assetObj.size) {
          completed++;
          completedBytes += assetObj.size;
          this.reportProgress(onProgress, total, completed, totalBytes, completedBytes, objectName);
          continue;
        }
      }

      // 确保子目录存在
      FileUtils.mkdirs(`${objectsDir}/${subDir}`);

      // 下载 asset object
      // 标准 URL: https://resources.download.minecraft.net/{hash前2位}/{hash}
      // BMCLAPI 镜像: https://bmclapi2.bangbang93.com/assets/{hash前2位}/{hash}
      const objectUrl = `${Constants.MOJANG_RESOURCES_BASE}/${subDir}/${hash}`;
      const mirrorUrl = `${Constants.BMCLAPI_RESOURCES_BASE}/${subDir}/${hash}`;

      try {
        await HttpClient.downloadFile(objectUrl, objectPath);
        Logger.info(AssetsManager.TAG, `Downloaded asset: ${objectName}`);
      } catch (e) {
        // 尝试镜像
        try {
          Logger.warn(AssetsManager.TAG, `Download failed, trying BMCLAPI mirror: ${objectName}`);
          await HttpClient.downloadFile(mirrorUrl, objectPath);
        } catch (e2) {
          Logger.warn(AssetsManager.TAG, `Failed to download asset: ${objectName} - ${(e2 as Error).message}`);
        }
      }

      completed++;
      completedBytes += assetObj.size;
      this.reportProgress(onProgress, total, completed, totalBytes, completedBytes, objectName);
    }

    Logger.info(AssetsManager.TAG, `Asset download complete: ${completed}/${total} objects`);
  }

  /**
   * 获取单个 asset object 的本地路径
   * 供 asset index 替换使用
   */
  getAssetPath(hash: string): string {
    if (hash.length < 2) return '';
    const subDir = hash.substring(0, 2);
    return `${this.baseDir}/${Constants.ASSETS_DIR}/objects/${subDir}/${hash}`;
  }

  /**
   * 检查某个 hash 的 asset object 是否已下载
   */
  hasAsset(hash: string): boolean {
    if (hash.length < 2) return false;
    const subDir = hash.substring(0, 2);
    return FileUtils.exists(`${this.baseDir}/${Constants.ASSETS_DIR}/objects/${subDir}/${hash}`);
  }

  /**
   * 检查 asset index 是否已下载
   */
  hasAssetIndex(indexId: string): boolean {
    return FileUtils.exists(`${this.baseDir}/${Constants.ASSETS_DIR}/indexes/${indexId}.json`);
  }

  private reportProgress(
    callback: AssetProgressCallback | undefined,
    totalObjects: number,
    completedObjects: number,
    totalBytes: number,
    completedBytes: number,
    currentObject: string
  ): void {
    if (callback) {
      callback({ totalObjects, completedObjects, currentObject, totalBytes, completedBytes });
    }
  }
}