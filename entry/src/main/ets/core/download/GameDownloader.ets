/**
 * Game downloader orchestrator for HMCL-HarmonyOS
 * Downloads Minecraft client jar, libraries, assets, and handles verification
 */

import {
  GameVersionJson, Artifact, Library, DownloadTask,
  DownloadProgress, DownloadSource, VersionManifest, VersionInfo
} from '../../model/GameVersion';
import { Constants, HttpHelper } from '../../config/Constants';
import fileIo from '@ohos.file.fs';
import util from '@ohos.util';
import { BusinessError } from '@ohos.base';

export type ProgressCallback = (progress: DownloadProgress) => void;

export class GameDownloader {
  private static instance: GameDownloader;
  private baseDir: string = '';
  private downloadSource: DownloadSource = DownloadSource.BMCLAPI;
  private activeDownloads: Map<string, boolean> = new Map();
  private isDownloading: boolean = false;

  private constructor() {
  }

  static getInstance(): GameDownloader {
    if (!GameDownloader.instance) {
      GameDownloader.instance = new GameDownloader();
    }
    return GameDownloader.instance;
  }

  /**
   * Initialize the downloader
   */
  init(baseDir: string): void {
    this.baseDir = baseDir;
  }

  /**
   * Set the download source
   */
  setDownloadSource(source: DownloadSource): void {
    this.downloadSource = source;
  }

  /**
   * Get the download source
   */
  getDownloadSource(): DownloadSource {
    return this.downloadSource;
  }

  /**
   * Download version manifest
   */
  async downloadVersionManifest(): Promise<VersionManifest> {
    const url = this.getVersionManifestUrl();
    const response = await HttpHelper.get(url);
    return JSON.parse(response) as VersionManifest;
  }

  /**
   * Download a Minecraft client jar
   */
  async downloadClientJar(
    versionId: string,
    onProgress?: ProgressCallback
  ): Promise<string> {
    const versionJson = await this.getVersionJson(versionId);
    const download = versionJson.downloads?.client;
    if (!download) {
      throw new Error(`No client download found for version ${versionId}`);
    }

    const targetDir = `${this.baseDir}/${Constants.VERSIONS_DIR}/${versionId}`;
    await this.ensureDirectory(targetDir);
    const targetPath = `${targetDir}/${versionId}.jar`;

    // Check if already downloaded and valid
    if (await this.verifyFile(targetPath, download.sha1)) {
      console.info(`Client jar for ${versionId} already exists and is valid`);
      return targetPath;
    }

    await this.downloadWithVerification(
      download.url,
      targetPath,
      download.sha1,
      download.size,
      `client-${versionId}.jar`,
      onProgress
    );

    return targetPath;
  }

  /**
   * Download version JSON
   */
  async downloadVersionJson(
    versionId: string,
    onProgress?: ProgressCallback
  ): Promise<string> {
    const manifest = await this.downloadVersionManifest();
    const versionInfo = manifest.versions.find(v => v.id === versionId);
    if (!versionInfo) {
      throw new Error(`Version ${versionId} not found in manifest`);
    }

    const targetDir = `${this.baseDir}/${Constants.VERSIONS_DIR}/${versionId}`;
    await this.ensureDirectory(targetDir);
    const targetPath = `${targetDir}/${versionId}.json`;

    // Use BMCLAPI mirror for version JSON
    const url = `${this.getVersionBaseUrl()}/mc/game/version_manifest_v2/versions/${versionId}.json`;

    // Download the version JSON
    const response = await HttpHelper.get(url);
    await fileIo.writeText(targetPath, response);

    if (onProgress) {
      onProgress({
        totalFiles: 1,
        completedFiles: 1,
        totalBytes: response.length,
        completedBytes: response.length,
        currentFile: `${versionId}.json`,
        speed: 0,
      });
    }

    return targetPath;
  }

  /**
   * Download all libraries for a version
   */
  async downloadLibraries(
    versionId: string,
    onProgress?: ProgressCallback
  ): Promise<string[]> {
    const versionJson = await this.getVersionJson(versionId);
    const libraries = this.filterLibraries(versionJson.libraries || []);
    const downloadedPaths: string[] = [];

    // Calculate total size
    let totalSize = 0;
    for (const lib of libraries) {
      if (lib.downloads?.artifact) {
        totalSize += lib.downloads.artifact.size || 0;
      }
      // Handle natives
      if (lib.natives && lib.downloads?.classifiers) {
        const nativeKey = this.getNativeKey(lib);
        if (nativeKey && lib.downloads.classifiers[nativeKey]) {
          totalSize += lib.downloads.classifiers[nativeKey].size || 0;
        }
      }
    }

    let completedSize = 0;
    let completedFiles = 0;

    for (const library of libraries) {
      // Download main artifact
      if (library.downloads?.artifact) {
        const artifact = library.downloads.artifact;
        const libPath = this.getLibraryFilePath(library);
        const targetPath = `${this.baseDir}/${Constants.LIBRARIES_DIR}/${libPath}`;

        await this.ensureDirectory(this.getDirName(targetPath));

        if (!(await this.verifyFile(targetPath, artifact.sha1))) {
          const downloadUrl = this.getMirrorLibraryUrl(artifact.url);
          await this.downloadWithVerification(
            downloadUrl,
            targetPath,
            artifact.sha1,
            artifact.size,
            `lib-${library.name}`,
            undefined
          );
        }

        downloadedPaths.push(targetPath);

        completedSize += artifact.size || 0;
        completedFiles++;

        if (onProgress) {
          onProgress({
            totalFiles: libraries.length,
            completedFiles: completedFiles,
            totalBytes: totalSize,
            completedBytes: completedSize,
            currentFile: library.name,
            speed: 0,
          });
        }
      }

      // Download natives
      if (library.natives && library.downloads?.classifiers) {
        const nativeKey = this.getNativeKey(library);
        if (nativeKey && library.downloads.classifiers[nativeKey]) {
          const nativeArtifact = library.downloads.classifiers[nativeKey];
          const nativePath = nativeArtifact.path || this.getLibraryFilePath(library, nativeKey);
          const targetPath = `${this.baseDir}/${Constants.LIBRARIES_DIR}/${nativePath}`;

          await this.ensureDirectory(this.getDirName(targetPath));

          if (!(await this.verifyFile(targetPath, nativeArtifact.sha1))) {
            const downloadUrl = this.getMirrorLibraryUrl(nativeArtifact.url);
            await this.downloadWithVerification(
              downloadUrl,
              targetPath,
              nativeArtifact.sha1,
              nativeArtifact.size,
              `native-${library.name}`,
              undefined
            );
          }

          downloadedPaths.push(targetPath);

          completedSize += nativeArtifact.size || 0;
          completedFiles++;

          if (onProgress) {
            onProgress({
              totalFiles: libraries.length * 2,
              completedFiles: completedFiles,
              totalBytes: totalSize,
              completedBytes: completedSize,
              currentFile: `native-${library.name}`,
              speed: 0,
            });
          }
        }
      }
    }

    return downloadedPaths;
  }

  /**
   * Download assets (indexes and objects)
   */
  async downloadAssets(
    versionId: string,
    onProgress?: ProgressCallback
  ): Promise<string[]> {
    const versionJson = await this.getVersionJson(versionId);
    if (!versionJson.assetIndex) {
      throw new Error(`No asset index for version ${versionId}`);
    }

    // Download asset index
    const assetIndexUrl = versionJson.assetIndex.url;
    const assetIndexDir = `${this.baseDir}/${Constants.ASSETS_DIR}/indexes`;
    await this.ensureDirectory(assetIndexDir);
    const assetIndexPath = `${assetIndexDir}/${versionJson.assets}.json`;

    let assetIndexResponse: string;
    if (!(await this.fileExists(assetIndexPath))) {
      assetIndexResponse = await HttpHelper.get(this.getMirrorAssetUrl(assetIndexUrl));
      await fileIo.writeText(assetIndexPath, assetIndexResponse);
    } else {
      assetIndexResponse = await fileIo.readText(assetIndexPath);
    }

    const assetIndex = JSON.parse(assetIndexResponse);
    const objects = assetIndex.objects || {};
    const objectKeys = Object.keys(objects);

    // Download asset objects
    const downloadedPaths: string[] = [];
    let completedFiles = 0;
    let totalSize = 0;
    let completedSize = 0;

    for (const key of objectKeys) {
      totalSize += objects[key].size || 0;
    }

    for (const key of objectKeys) {
      const asset = objects[key];
      const hash = asset.hash;
      const subDir = hash.substring(0, 2);
      const objectDir = `${this.baseDir}/${Constants.ASSETS_DIR}/objects/${subDir}`;
      const objectPath = `${objectDir}/${hash}`;

      await this.ensureDirectory(objectDir);

      if (!(await this.verifyFile(objectPath, hash))) {
        const assetUrl = `${this.getAssetsBaseUrl()}/${subDir}/${hash}`;
        await this.downloadWithVerification(
          assetUrl,
          objectPath,
          hash,
          asset.size,
          `asset-${key}`,
          undefined
        );
      }

      downloadedPaths.push(objectPath);
      completedFiles++;
      completedSize += asset.size || 0;

      if (onProgress && completedFiles % 100 === 0) {
        onProgress({
          totalFiles: objectKeys.length,
          completedFiles: completedFiles,
          totalBytes: totalSize,
          completedBytes: completedSize,
          currentFile: key,
          speed: 0,
        });
      }
    }

    if (onProgress) {
      onProgress({
        totalFiles: objectKeys.length,
        completedFiles: completedFiles,
        totalBytes: totalSize,
        completedBytes: completedSize,
        currentFile: 'assets-complete',
        speed: 0,
      });
    }

    return downloadedPaths;
  }

  /**
   * Download a complete Minecraft version (client + libraries + assets)
   */
  async downloadCompleteVersion(
    versionId: string,
    onProgress?: ProgressCallback
  ): Promise<void> {
    this.isDownloading = true;

    try {
      // Step 1: Download version JSON
      if (onProgress) {
        onProgress({
          totalFiles: 1,
          completedFiles: 0,
          totalBytes: 0,
          completedBytes: 0,
          currentFile: 'Downloading version manifest...',
          speed: 0,
        });
      }
      await this.downloadVersionJson(versionId, onProgress);

      // Step 2: Download client jar
      if (onProgress) {
        onProgress({
          totalFiles: 1,
          completedFiles: 0,
          totalBytes: 0,
          completedBytes: 0,
          currentFile: 'Downloading client jar...',
          speed: 0,
        });
      }
      await this.downloadClientJar(versionId, onProgress);

      // Step 3: Download libraries
      if (onProgress) {
        onProgress({
          totalFiles: 1,
          completedFiles: 0,
          totalBytes: 0,
          completedBytes: 0,
          currentFile: 'Downloading libraries...',
          speed: 0,
        });
      }
      await this.downloadLibraries(versionId, onProgress);

      // Step 4: Download assets
      if (onProgress) {
        onProgress({
          totalFiles: 1,
          completedFiles: 0,
          totalBytes: 0,
          completedBytes: 0,
          currentFile: 'Downloading assets...',
          speed: 0,
        });
      }
      await this.downloadAssets(versionId, onProgress);

      console.info(`Version ${versionId} download completed`);
    } catch (e) {
      console.error(`Failed to download version ${versionId}`, JSON.stringify(e));
      throw e;
    } finally {
      this.isDownloading = false;
    }
  }

  /**
   * Verify file integrity using SHA-1 hash
   */
  async verifyFile(filePath: string, expectedSha1: string): Promise<boolean> {
    try {
      if (!(await this.fileExists(filePath))) {
        return false;
      }

      const stat = await fileIo.stat(filePath);
      // Quick check: if expectedSha1 is empty, just check file exists
      if (!expectedSha1) {
        return stat.size > 0;
      }

      // Compute SHA-1 hash of the file
      const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const bufSize = 8192;
      const totalSize = stat.size;
      const sha1 = new util.SHA1();

      let offset = 0;
      while (offset < totalSize) {
        const readSize = Math.min(bufSize, totalSize - offset);
        const buffer = new ArrayBuffer(readSize);
        await fileIo.read(file.fd, buffer, { offset: offset, length: readSize });
        sha1.update(new Uint8Array(buffer));
        offset += readSize;
      }

      fileIo.close(file);

      const hash = sha1.digest();
      const hexHash = this.bytesToHex(hash);

      return hexHash.toLowerCase() === expectedSha1.toLowerCase();
    } catch (e) {
      console.warn(`Failed to verify file ${filePath}: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * Cancel all active downloads
   */
  cancelDownloads(): void {
    this.activeDownloads.clear();
    this.isDownloading = false;
  }

  /**
   * Check if the downloader is currently downloading
   */
  getIsDownloading(): boolean {
    return this.isDownloading;
  }

  /**
   * Get the version JSON for a version
   */
  private async getVersionJson(versionId: string): Promise<GameVersionJson> {
    const localJsonPath = `${this.baseDir}/${Constants.VERSIONS_DIR}/${versionId}/${versionId}.json`;

    if (await this.fileExists(localJsonPath)) {
      const content = await fileIo.readText(localJsonPath);
      return JSON.parse(content) as GameVersionJson;
    }

    // Fetch from remote
    const url = `${this.getVersionBaseUrl()}/mc/game/version_manifest_v2/versions/${versionId}.json`;
    const response = await HttpHelper.get(url);
    return JSON.parse(response) as GameVersionJson;
  }

  /**
   * Filter libraries based on OS rules (for HarmonyOS/Linux)
   */
  private filterLibraries(libraries: Library[]): Library[] {
    const osName = 'linux'; // HarmonyOS is Linux-based

    return libraries.filter(lib => {
      if (!lib.rules || lib.rules.length === 0) {
        return true;
      }

      let allowed = false;
      let hasRule = false;

      for (const rule of lib.rules) {
        if (rule.os) {
          if (rule.os.name === osName) {
            hasRule = true;
            allowed = rule.action === 'allow';
          }
          // Skip rules for other OS
        } else {
          // No OS constraint
          hasRule = true;
          allowed = rule.action === 'allow';
        }
      }

      return hasRule ? allowed : true;
    });
  }

  /**
   * Get the native classifier key for the current OS
   */
  private getNativeKey(library: Library): string {
    if (!library.natives) {
      return '';
    }
    return library.natives['linux'] || library.natives['osx'] || '';
  }

  /**
   * Get the library file path from Maven coordinates
   */
  private getLibraryFilePath(library: Library, classifier?: string): string {
    if (library.downloads?.artifact?.path) {
      if (classifier && library.downloads.classifiers?.[classifier]?.path) {
        return library.downloads.classifiers[classifier].path!;
      }
      return library.downloads.artifact.path!;
    }

    const parts = library.name.split(':');
    if (parts.length < 3) {
      return library.name;
    }

    const group = parts[0].replace(/\./g, '/');
    const artifact = parts[1];
    const version = parts[2];
    const ext = classifier ? `-${classifier}.jar` : '';

    return `${group}/${artifact}/${version}/${artifact}-${version}${ext}.jar`;
  }

  /**
   * Get the version manifest URL based on download source
   */
  private getVersionManifestUrl(): string {
    switch (this.downloadSource) {
      case DownloadSource.BMCLAPI:
        return Constants.BMCLAPI_VERSION_MANIFEST;
      case DownloadSource.MOJANG:
      default:
        return Constants.MOJANG_VERSION_MANIFEST;
    }
  }

  /**
   * Get the version base URL based on download source
   */
  private getVersionBaseUrl(): string {
    switch (this.downloadSource) {
      case DownloadSource.BMCLAPI:
        return Constants.BMCLAPI_VERSION_BASE;
      case DownloadSource.MOJANG:
      default:
        return Constants.MOJANG_VERSION_BASE;
    }
  }

  /**
   * Get the assets base URL based on download source
   */
  private getAssetsBaseUrl(): string {
    switch (this.downloadSource) {
      case DownloadSource.BMCLAPI:
        return Constants.BMCLAPI_RESOURCES_BASE;
      case DownloadSource.MOJANG:
      default:
        return Constants.MOJANG_RESOURCES_BASE;
    }
  }

  /**
   * Get the mirror URL for a library artifact
   */
  private getMirrorLibraryUrl(originalUrl: string): string {
    if (this.downloadSource === DownloadSource.BMCLAPI) {
      return originalUrl.replace(
        'https://libraries.minecraft.net',
        Constants.BMCLAPI_LIBRARIES_BASE
      );
    }
    return originalUrl;
  }

  /**
   * Get the mirror URL for an asset
   */
  private getMirrorAssetUrl(originalUrl: string): string {
    if (this.downloadSource === DownloadSource.BMCLAPI) {
      return originalUrl.replace(
        'https://piston-meta.mojang.com',
        Constants.BMCLAPI_VERSION_BASE
      );
    }
    return originalUrl;
  }

  /**
   * Download a file with SHA-1 verification
   */
  private async downloadWithVerification(
    url: string,
    targetPath: string,
    expectedSha1: string,
    expectedSize: number,
    taskName: string,
    onProgress?: ProgressCallback
  ): Promise<void> {
    if (this.activeDownloads.has(taskName)) {
      console.info(`Download already in progress: ${taskName}`);
      return;
    }

    this.activeDownloads.set(taskName, true);

    try {
      // Try download with fallback sources
      const urls = this.getDownloadUrlsWithFallback(url);
      let lastError: Error | null = null;

      for (const downloadUrl of urls) {
        try {
          await this.downloadFile(downloadUrl, targetPath);
          lastError = null;
          break;
        } catch (e) {
          lastError = e as Error;
          console.warn(`Download failed from ${downloadUrl}, trying next source`);
        }
      }

      if (lastError) {
        throw lastError;
      }

      // Verify downloaded file
      if (expectedSha1) {
        const valid = await this.verifyFile(targetPath, expectedSha1);
        if (!valid) {
          // Delete invalid file
          try {
            await fileIo.unlink(targetPath);
          } catch (e) {
            // Ignore delete errors
          }
          throw new Error(`SHA-1 verification failed for ${taskName}`);
        }
      }
    } finally {
      this.activeDownloads.delete(taskName);
    }
  }

  /**
   * Get download URLs with fallback sources
   */
  private getDownloadUrlsWithFallback(originalUrl: string): string[] {
    const urls: string[] = [originalUrl];

    // Add BMCLAPI mirror as fallback if original is Mojang
    if (originalUrl.includes('libraries.minecraft.net')) {
      urls.push(originalUrl.replace(
        'https://libraries.minecraft.net',
        Constants.BMCLAPI_LIBRARIES_BASE
      ));
    } else if (originalUrl.includes('piston-meta.mojang.com')) {
      urls.push(originalUrl.replace(
        'https://piston-meta.mojang.com',
        Constants.BMCLAPI_VERSION_BASE
      ));
    } else if (originalUrl.includes('resources.download.minecraft.net')) {
      urls.push(originalUrl.replace(
        'https://resources.download.minecraft.net',
        Constants.BMCLAPI_RESOURCES_BASE
      ));
    }

    return urls;
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
          readTimeout: 120000,
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
      throw new Error(`Failed to create HTTP request: ${JSON.stringify(e)}`);
    }
  }

  /**
   * Convert bytes to hex string
   */
  private bytesToHex(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      hex += bytes[i].toString(16).padStart(2, '0');
    }
    return hex;
  }

  /**
   * Get the directory name from a path
   */
  private getDirName(filePath: string): string {
    const lastSlash = filePath.lastIndexOf('/');
    if (lastSlash >= 0) {
      return filePath.substring(0, lastSlash);
    }
    return '';
  }

  /**
   * Check if a file exists
   */
  private async fileExists(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return stat.isFile() || stat.isDirectory();
    } catch (e) {
      return false;
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