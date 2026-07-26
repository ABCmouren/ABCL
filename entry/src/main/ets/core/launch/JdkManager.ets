/**
 * JDK Runtime Manager for HMCL-HarmonyOS
 * Handles downloading and verifying JDK runtimes from mc-ohos-resources
 * Extraction priority: rawfile (bundled in HAP) → network download (fallback)
 */

import resourceManager from '@ohos.resourceManager';
import { Constants } from '../../config/Constants';
import { HttpClient } from '../network/HttpClient';
import { Logger, FileUtils } from '../util/Utils';
import { JdkExtractor } from './JdkExtractor';
import zlib from '@ohos.zlib';
import { BusinessError } from '@ohos.base';

export class JdkManager {
  private static readonly TAG = 'JdkManager';
  private static instance: JdkManager;
  private baseDir: string = '';
  private resourceMgr: resourceManager.ResourceManager = ({} as resourceManager.ResourceManager);

  private constructor() {}

  static getInstance(): JdkManager {
    if (!JdkManager.instance) {
      JdkManager.instance = new JdkManager();
    }
    return JdkManager.instance;
  }

  init(baseDir: string, mgr: resourceManager.ResourceManager): void {
    this.baseDir = baseDir;
    this.resourceMgr = mgr;
    FileUtils.mkdirs(`${baseDir}/${Constants.JDK_DIR}`);
    Logger.info(JdkManager.TAG, `JDK directory: ${baseDir}/${Constants.JDK_DIR}`);
  }

  /**
   * Get the path to a JDK runtime, extracting from rawfile or downloading if necessary.
   * Priority: already installed → rawfile (bundled in HAP) → network download
   */
  async ensureJdk(mcVersion: string): Promise<string> {
    const jdkUrl = Constants.getJdkForMcVersion(mcVersion);
    const jdkDirName = Constants.getJdkDirName(jdkUrl);
    const jdkPath = `${this.baseDir}/${Constants.JDK_DIR}/${jdkDirName}`;

    // Check if JDK is already installed
    if (this.isJdkInstalled(jdkPath)) {
      Logger.info(JdkManager.TAG, `JDK ${jdkDirName} already installed at: ${jdkPath}`);
      return jdkPath;
    }

    // Try extracting from rawfile first (bundled in HAP)
    const rawfileName: string = JdkExtractor.getRawfileNameForJdk(jdkUrl);
    if (rawfileName.length > 0) {
      Logger.info(JdkManager.TAG, `Trying to extract ${rawfileName} from rawfile...`);
      const success: boolean = await JdkExtractor.extractFromRawfile(
        this.resourceMgr, rawfileName, jdkPath);
      if (success) {
        Logger.info(JdkManager.TAG, `JDK ${jdkDirName} extracted from rawfile successfully`);
        return jdkPath;
      }
      Logger.warn(JdkManager.TAG, `Rawfile extraction failed, falling back to network download`);
    }

    // Fallback: download from network
    Logger.info(JdkManager.TAG, `Downloading JDK ${jdkDirName} from: ${jdkUrl}`);
    Logger.info(JdkManager.TAG, `To: ${jdkPath}`);

    // Download JDK zip
    const zipPath: string = `${this.baseDir}/${Constants.JDK_DIR}/${jdkDirName}.zip`;
    await this.downloadJdk(jdkUrl, zipPath);

    // Extract
    await this.extractJdk(zipPath, jdkPath);

    // Verify installation
    if (this.isJdkInstalled(jdkPath)) {
      Logger.info(JdkManager.TAG, `JDK ${jdkDirName} installed successfully`);
      return jdkPath;
    }

    throw new Error(`Failed to install JDK ${jdkDirName}`);
  }

  /**
   * Check if JDK is already installed by looking for libjvm.so
   */
  private isJdkInstalled(jdkPath: string): boolean {
    const libjvmPaths: string[] = [
      `${jdkPath}/lib/server/libjvm.so`,
      `${jdkPath}/lib/libjvm.so`,
    ];
    for (const path of libjvmPaths) {
      if (FileUtils.exists(path)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Download JDK zip file
   */
  private async downloadJdk(url: string, targetPath: string): Promise<void> {
    Logger.info(JdkManager.TAG, `Downloading JDK from ${url}`);

    // Ensure parent dir exists
    const parentDir: string = targetPath.substring(0, targetPath.lastIndexOf('/'));
    FileUtils.mkdirs(parentDir);

    // Use HttpClient to download
    await HttpClient.downloadFile(url, targetPath);
    Logger.info(JdkManager.TAG, `JDK downloaded to: ${targetPath}`);
  }

  /**
   * Extract JDK zip
   */
  private async extractJdk(zipPath: string, targetDir: string): Promise<void> {
    Logger.info(JdkManager.TAG, `Extracting JDK to: ${targetDir}`);

    FileUtils.mkdirs(targetDir);

    try {
      // Use system unzip capability with numeric constants
      const options: zlib.Options = {
        level: 0,
        memLevel: 8,
        strategy: 0,
      };

      await zlib.decompressFile(zipPath, targetDir, options);
      Logger.info(JdkManager.TAG, 'JDK extracted successfully');
    } catch (ex) {
      const err: BusinessError = ex as BusinessError;
      Logger.error(JdkManager.TAG, `Failed to extract JDK: ${err.message}`);
      throw new Error(`JDK extraction failed: ${err.message}`);
    } finally {
      // Clean up zip
      try {
        FileUtils.delete(zipPath);
      } catch (ex) {
        // Non-critical cleanup
      }
    }
  }

  /**
   * List installed JDK runtimes
   */
  listInstalledJdks(): string[] {
    const jdkDir: string = `${this.baseDir}/${Constants.JDK_DIR}`;
    if (!FileUtils.exists(jdkDir)) {
      return [];
    }

    try {
      const dirs: string[] = FileUtils.listDir(jdkDir);
      const installed: string[] = [];
      for (const dir of dirs) {
        const fullPath: string = `${jdkDir}/${dir}`;
        if (this.isJdkInstalled(fullPath)) {
          installed.push(dir);
        }
      }
      return installed;
    } catch (ex) {
      return [];
    }
  }

  /**
   * Get the full path to a specific JDK
   */
  getJdkPath(jdkName: string): string {
    return `${this.baseDir}/${Constants.JDK_DIR}/${jdkName}`;
  }

  /**
   * Delete a JDK runtime
   */
  async removeJdk(jdkName: string): Promise<boolean> {
    const jdkPath: string = `${this.baseDir}/${Constants.JDK_DIR}/${jdkName}`;
    if (!FileUtils.exists(jdkPath)) {
      return true;
    }
    try {
      FileUtils.delete(jdkPath);
      return true;
    } catch (ex) {
      Logger.error(JdkManager.TAG, `Failed to remove JDK ${jdkName}`);
      return false;
    }
  }
}
