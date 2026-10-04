/**
 * DownloadEngine — 带并发 / 校验 / 重试 / 镜像回退的批量下载器
 *
 * 参考 AMCL 的 LoaderDownload + NetFile 语义（文件级校验、失败聚合、进度字节加权），
 * 但用 ArkTS 的 http 流式下载实现，不依赖 native 引擎。
 */
import { HttpClient } from '../network/HttpClient';
import { FileUtils, Logger } from '../util/Utils';

export interface DownloadItem {
  /** 主 URL */
  url: string;
  /** 备用镜像（顺序回退） */
  mirrors: string[];
  /** 本地绝对路径 */
  path: string;
  /** 期望 SHA-1（小写十六进制；空串表示不校验） */
  sha1: string;
  /** 期望字节数（0 表示未知） */
  size: number;
  /** 展示名 */
  name: string;
}

export interface DownloadStats {
  phase: string;
  message: string;
  totalFiles: number;
  completedFiles: number;
  failedFiles: number;
  totalBytes: number;
  completedBytes: number;
  speedBps: number;
  currentFile: string;
}

export type StatsCallback = (stats: DownloadStats) => void;

export interface BatchResult {
  ok: boolean;
  failedItems: DownloadItem[];
  errors: string[];
  bytesDownloaded: number;
  elapsedMs: number;
}

/** 取消令牌 */
export class CancelToken {
  cancelled: boolean = false;

  cancel(): void {
    this.cancelled = true;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }
}

export class DownloadEngine {
  private static readonly TAG = 'DownloadEngine';
  private static readonly DEFAULT_CONCURRENCY = 6;

  /**
   * 批量下载。已存在且大小匹配的文件直接跳过（SHA-1 在下载后校验）。
   */
  static async run(
    items: DownloadItem[],
    phase: string,
    onStats?: StatsCallback,
    concurrency: number = DownloadEngine.DEFAULT_CONCURRENCY,
    token?: CancelToken
  ): Promise<BatchResult> {
    const startedAt = Date.now();
    const totalFiles = items.length;
    let completedFiles = 0;
    let failedFiles = 0;
    let completedBytes = 0;
    let inflightBytes = 0;
    let totalBytes = 0;
    for (const item of items) {
      totalBytes += item.size > 0 ? item.size : 0;
    }

    const failedItems: DownloadItem[] = [];
    const errors: string[] = [];
    let lastEmit = 0;
    let windowBytes = 0;
    let windowStart = Date.now();
    let speedBps = 0;
    let currentFile = '';
    const inflight = new Map<string, number>();

    const emit = (message: string, force: boolean): void => {
      const now = Date.now();
      if (!force && now - lastEmit < 200) {
        return;
      }
      lastEmit = now;
      if (onStats) {
        onStats({
          phase: phase,
          message: message,
          totalFiles: totalFiles,
          completedFiles: completedFiles,
          failedFiles: failedFiles,
          totalBytes: totalBytes,
          completedBytes: completedBytes + inflightBytes,
          speedBps: speedBps,
          currentFile: currentFile
        });
      }
    };

    let cursor = 0;
    const workerCount = Math.max(1, Math.min(concurrency, totalFiles > 0 ? totalFiles : 1));

    const consume = async (): Promise<void> => {
      while (true) {
        if (token && token.isCancelled()) {
          return;
        }
        const index = cursor;
        cursor++;
        if (index >= totalFiles) {
          return;
        }
        const item = items[index];
        currentFile = item.name;

        // 1) 已存在且大小匹配 → 跳过
        if (DownloadEngine.isValid(item)) {
          completedFiles++;
          completedBytes += item.size > 0 ? item.size : FileUtils.getFileSize(item.path);
          emit(`校验通过，跳过 ${item.name}`, false);
          continue;
        }

        // 2) 依次尝试主 URL + 镜像
        const candidates: string[] = [];
        candidates.push(item.url);
        for (const mirror of item.mirrors) {
          if (mirror.length > 0 && mirror !== item.url) {
            candidates.push(mirror);
          }
        }

        let ok = false;
        let lastError = '';
        if (item.size > 0) {
          totalBytes = totalBytes;
        }

        for (const url of candidates) {
          if (token && token.isCancelled()) {
            return;
          }
          inflight.set(item.path, 0);
          const outcome = await HttpClient.downloadToFile(url, item.path, item.size, (received: number, total: number) => {
            const prev = inflight.get(item.path) || 0;
            const delta = received - prev;
            if (delta > 0) {
              inflight.set(item.path, received);
              inflightBytes += delta;
              windowBytes += delta;
              const now = Date.now();
              if (now - windowStart >= 1000) {
                speedBps = Math.floor(windowBytes * 1000 / (now - windowStart));
                windowBytes = 0;
                windowStart = now;
              }
              emit(`下载中 ${completedFiles + 1}/${totalFiles}`, false);
            }
          });
          const hold = inflight.get(item.path) || 0;
          inflight.delete(item.path);
          inflightBytes -= hold;

          if (!outcome.success) {
            lastError = `${url} → ${outcome.error}`;
            Logger.warn(DownloadEngine.TAG, `下载失败 ${item.name}: ${lastError}`);
            continue;
          }
          if (item.sha1.length > 0) {
            const actual = await FileUtils.sha1File(item.path);
            if (actual.toLowerCase() !== item.sha1.toLowerCase()) {
              lastError = `${url} → SHA-1 不符（期望 ${item.sha1} 实际 ${actual}）`;
              Logger.warn(DownloadEngine.TAG, `${item.name} ${lastError}`);
              FileUtils.delete(item.path);
              continue;
            }
          }
          ok = true;
          completedBytes += outcome.bytes;
          break;
        }

        if (ok) {
          completedFiles++;
          emit(`已下载 ${completedFiles}/${totalFiles}`, false);
        } else {
          failedFiles++;
          failedItems.push(item);
          errors.push(`${item.name}: ${lastError}`);
          emit(`下载失败 ${item.name}`, true);
        }
      }
    };

    const workers: Promise<void>[] = [];
    for (let i = 0; i < workerCount; i++) {
      workers.push(consume());
    }
    await Promise.all(workers);

    const cancelled = token !== undefined && token.isCancelled();
    emit(cancelled ? '已取消' : (failedFiles === 0 ? '全部完成' : `${failedFiles} 个文件失败`), true);

    return {
      ok: failedFiles === 0 && !cancelled,
      failedItems: failedItems,
      errors: errors,
      bytesDownloaded: completedBytes,
      elapsedMs: Date.now() - startedAt
    };
  }

  /** 文件是否已存在且大小匹配 */
  static isValid(item: DownloadItem): boolean {
    if (!FileUtils.exists(item.path)) {
      return false;
    }
    const size = FileUtils.getFileSize(item.path);
    if (size <= 0) {
      return false;
    }
    if (item.size > 0 && size !== item.size) {
      return false;
    }
    return true;
  }

  /** 带 SHA-1 的完整校验（较慢，用于最终复核） */
  static async isValidDeep(item: DownloadItem): Promise<boolean> {
    if (!DownloadEngine.isValid(item)) {
      return false;
    }
    if (item.sha1.length === 0) {
      return true;
    }
    const actual = await FileUtils.sha1File(item.path);
    return actual.toLowerCase() === item.sha1.toLowerCase();
  }

  /** 下载单个文件（含镜像回退） */
  static async fetchOne(item: DownloadItem): Promise<boolean> {
    const result = await DownloadEngine.run([item], 'single', undefined, 1, undefined);
    return result.ok;
  }
}
