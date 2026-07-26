/**
 * JdkExtractor - Extract bundled JDK runtimes from HAP rawfile
 * Priority: rawfile > network download (fallback)
 */

import resourceManager from '@ohos.resourceManager';
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';
import { BusinessError } from '@ohos.base';
import { Logger, FileUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';

export class JdkExtractor {
  private static readonly TAG = 'JdkExtractor';

  /**
   * Extract a JDK ZIP from rawfile to the target directory.
   * Returns true if extraction was successful.
   */
  static async extractFromRawfile(
    mgr: resourceManager.ResourceManager,
    rawfileName: string,
    targetDir: string,
  ): Promise<boolean> {
    Logger.info(JdkExtractor.TAG, `Extracting ${rawfileName} from rawfile to ${targetDir}`);

    try {
      // Step 1: Read rawfile content as bytes
      const data: Uint8Array = await mgr.getRawFileContent(rawfileName);
      Logger.info(JdkExtractor.TAG, `Read ${rawfileName} from rawfile (${data.byteLength} bytes)`);

      // Step 2: Write temp ZIP to sandbox
      const tempZip = `${targetDir}.temp.zip`;
      FileUtils.mkdirs(targetDir);
      const zipFile = fs.openSync(tempZip, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(zipFile.fd, data.buffer.slice(0, data.byteLength));
      fs.closeSync(zipFile);
      Logger.info(JdkExtractor.TAG, `Temp ZIP written: ${tempZip}`);

      // Step 3: Decompress ZIP to target directory
      const options: zlib.Options = {
        level: 0,
        memLevel: 8,
        strategy: 0,
      };
      await zlib.decompressFile(tempZip, targetDir, options);
      Logger.info(JdkExtractor.TAG, `Decompressed to ${targetDir}`);

      // Step 4: Clean up temp ZIP
      try {
        FileUtils.delete(tempZip);
        Logger.info(JdkExtractor.TAG, 'Temp ZIP cleaned up');
      } catch (e) {
        // Non-critical
      }

      // Step 5: Flatten if needed - sometimes ZIPs extract into a subdirectory
      await JdkExtractor.flattenIfNeeded(targetDir);

      return true;
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(JdkExtractor.TAG, `Failed to extract ${rawfileName}: ${err.message}`);
      return false;
    }
  }

  /**
   * If the extracted JDK has a single subdirectory (e.g. jdk-17.0.13/),
   * flatten it so libjvm.so is at targetDir/lib/server/libjvm.so
   */
  private static async flattenIfNeeded(targetDir: string): Promise<void> {
    try {
      const entries = fs.listFileSync(targetDir, { recursion: false });
      // If there's exactly one subdirectory, move everything up
      if (entries.length === 1) {
        const subPath = `${targetDir}/${entries[0]}`;
        const stat = fs.statSync(subPath);
        if (stat.isDirectory()) {
          Logger.info(JdkExtractor.TAG, `Flattening ${entries[0]} → ${targetDir}`);
          const subFiles = fs.listFileSync(subPath, { recursion: false });
          for (const f of subFiles) {
            try {
              const src = `${subPath}/${f}`;
              const dst = `${targetDir}/${f}`;
              // Remove dest if exists
              if (FileUtils.exists(dst)) {
                FileUtils.delete(dst);
              }
              fs.renameSync(src, dst);
            } catch (e) {
              // Fall back to copy + delete
              FileUtils.moveFile(`${subPath}/${f}`, `${targetDir}/${f}`);
            }
          }
          // Remove now-empty subdirectory
          try {
            FileUtils.delete(subPath);
          } catch (e) {}
        }
      }
    } catch (e) {
      Logger.warn(JdkExtractor.TAG, `Flatten skipped: ${(e as Error).message}`);
    }
  }

  /**
   * Determine which rawfile (if any) corresponds to a JDK URL.
   */
  static getRawfileNameForJdk(jdkUrl: string): string {
    return Constants.getJdkRawfileName(jdkUrl);
  }

  /**
   * Check if a rawfile with the given name exists in the app's resource manager.
   */
  static async rawfileExists(mgr: resourceManager.ResourceManager, rawfileName: string): Promise<boolean> {
    try {
      const data: Uint8Array = await mgr.getRawFileContent(rawfileName);
      return data !== null && data.byteLength > 0;
    } catch (ex) {
      return false;
    }
  }

  /**
   * Extract a single file (not ZIP) from rawfile to the target path.
   * Used for amcl-launcher.jar, cacert.pem, etc.
   */
  static async extractRawFile(
    mgr: resourceManager.ResourceManager,
    rawfileName: string,
    targetPath: string,
  ): Promise<boolean> {
    Logger.info(JdkExtractor.TAG, `Extracting rawfile ${rawfileName} → ${targetPath}`);
    try {
      const data: Uint8Array = await mgr.getRawFileContent(rawfileName);
      Logger.info(JdkExtractor.TAG, `Read ${rawfileName} from rawfile (${data.byteLength} bytes)`);

      // Ensure parent directory exists
      const parentDir: string = targetPath.substring(0, targetPath.lastIndexOf('/'));
      FileUtils.mkdirs(parentDir);

      const outFile = fs.openSync(targetPath,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(outFile.fd, data.buffer.slice(0, data.byteLength));
      fs.closeSync(outFile);
      Logger.info(JdkExtractor.TAG, `Extracted ${rawfileName} (${data.byteLength} bytes)`);
      return true;
    } catch (ex) {
      const err: Error = ex as Error;
      Logger.error(JdkExtractor.TAG, `Failed to extract rawfile ${rawfileName}: ${err.message}`);
      return false;
    }
  }
}
