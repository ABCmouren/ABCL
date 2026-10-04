/**
 * HttpClient — HMCL-HarmonyOS 网络层（2026-10 重写）
 *
 * 旧实现的两个致命问题：
 *  1. downloadFile 用 expectDataType=ARRAY_BUFFER 把整个文件读进内存再落盘，
 *     下载 100MB+ 的 JDK / client.jar 必然 OOM；
 *  2. readTimeout 固定 120s，大文件必然超时失败。
 *
 * 新实现用 http.requestInStream + on('dataReceive') 边收边写，
 * 支持 HTTP Range 断点续传、镜像回退，并落盘到 .part 后原子改名。
 */
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import { FileUtils } from '../util/Utils';

export interface HttpResult<T> {
  success: boolean;
  data?: T;
  error?: string;
  statusCode?: number;
}

export interface DownloadOutcome {
  success: boolean;
  path: string;
  bytes: number;
  statusCode: number;
  error: string;
}

export type DownloadProgressFn = (received: number, total: number) => void;

export class HttpClient {
  static readonly USER_AGENT = 'HMCL-HarmonyOS/2.0.0 (HarmonyOS; +https://github.com/ABCmouren/HMCL-HarmonyOS)';
  static readonly CONNECT_TIMEOUT = 20000;
  static readonly READ_TIMEOUT = 30000;
  /** 大文件下载：单次请求的读超时（收不到任何字节才算超时） */
  static readonly BIG_READ_TIMEOUT = 300000;

  private static buildHeaders(extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['User-Agent'] = HttpClient.USER_AGENT;
    headers['Accept-Encoding'] = 'identity';
    if (extra) {
      const keys = Object.keys(extra);
      for (const key of keys) {
        headers[key] = extra[key];
      }
    }
    return headers;
  }

  /** GET → JSON */
  static async getJson<T>(url: string, headers?: Record<string, string>): Promise<HttpResult<T>> {
    const res = await HttpClient.getText(url, headers);
    if (!res.success || res.data === undefined) {
      return { success: false, error: res.error, statusCode: res.statusCode };
    }
    try {
      const parsed = JSON.parse(res.data) as T;
      return { success: true, data: parsed, statusCode: res.statusCode };
    } catch (e) {
      return { success: false, error: `JSON 解析失败: ${(e as BusinessError).message}`, statusCode: res.statusCode };
    }
  }

  /** GET → 文本 */
  static async getText(url: string, headers?: Record<string, string>): Promise<HttpResult<string>> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: HttpClient.buildHeaders(headers),
        connectTimeout: HttpClient.CONNECT_TIMEOUT,
        readTimeout: HttpClient.READ_TIMEOUT,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      const result = await request.request(url, options);
      const code = result.responseCode;
      if (code >= 200 && code < 300) {
        const body = typeof result.result === 'string' ? result.result as string : JSON.stringify(result.result);
        return { success: true, data: body, statusCode: code };
      }
      return { success: false, error: `HTTP ${code}`, statusCode: code };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: `${err.code}: ${err.message}` };
    } finally {
      request.destroy();
    }
  }

  /** POST JSON → JSON（body 可以是对象，也可以是已序列化的字符串） */
  static async postJson<T>(url: string, body: object | string, headers?: Record<string, string>): Promise<HttpResult<T>> {
    const extra: Record<string, string> = { 'Content-Type': 'application/json' };
    if (headers) {
      const keys = Object.keys(headers);
      for (const key of keys) {
        extra[key] = headers[key];
      }
    }
    const payload: string = typeof body === 'string' ? body : JSON.stringify(body);
    const res = await HttpClient.postRaw(url, payload, extra);
    if (!res.success || res.data === undefined) {
      return { success: false, error: res.error, statusCode: res.statusCode };
    }
    try {
      const parsed = JSON.parse(res.data) as T;
      return { success: true, data: parsed, statusCode: res.statusCode };
    } catch (e) {
      return { success: false, error: `JSON 解析失败: ${(e as BusinessError).message}`, statusCode: res.statusCode };
    }
  }

  /** POST application/x-www-form-urlencoded → 文本（Microsoft OAuth 需要） */
  static async postForm(url: string, body: string): Promise<HttpResult<string>> {
    const extra: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
    return HttpClient.postRaw(url, body, extra);
  }

  private static async postRaw(url: string, body: string, headers: Record<string, string>): Promise<HttpResult<string>> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: HttpClient.buildHeaders(headers),
        extraData: body,
        connectTimeout: HttpClient.CONNECT_TIMEOUT,
        readTimeout: HttpClient.READ_TIMEOUT,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false
      };
      const result = await request.request(url, options);
      const code = result.responseCode;
      const text = typeof result.result === 'string' ? result.result as string : '';
      if (code >= 200 && code < 300) {
        return { success: true, data: text, statusCode: code };
      }
      return { success: false, error: `HTTP ${code}: ${text.substring(0, 200)}`, statusCode: code };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: `${err.code}: ${err.message}` };
    } finally {
      request.destroy();
    }
  }

  /**
   * 流式下载到文件。
   * - 先写 `<path>.part`，成功后再 rename 成正式文件（避免半成品被当成有效缓存）
   * - 若已存在 .part 且服务器支持 Range，则断点续传
   * - expectedSize > 0 时用于进度百分比
   */
  static async downloadToFile(
    url: string,
    savePath: string,
    expectedSize: number,
    onProgress?: DownloadProgressFn,
    resume: boolean = true
  ): Promise<DownloadOutcome> {
    const failure = (error: string, statusCode: number): DownloadOutcome => {
      return { success: false, path: savePath, bytes: 0, statusCode: statusCode, error: error };
    };

    try {
      const dir = FileUtils.getDirName(savePath);
      if (dir.length > 0) {
        FileUtils.mkdirs(dir);
      }

      const partPath = `${savePath}.part`;
      let startOffset = 0;
      if (resume && FileUtils.exists(partPath)) {
        startOffset = FileUtils.getFileSize(partPath);
      }

      const extraHeaders: Record<string, string> = {};
      if (startOffset > 0) {
        extraHeaders['Range'] = `bytes=${startOffset}-`;
      }

      const request = http.createHttp();
      let file: fs.File | null = null;
      let written = startOffset;
      let streamError: string = '';

      try {
        const openMode = startOffset > 0
          ? (fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND)
          : (fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        file = fs.openSync(partPath, openMode);
        const fd = file.fd;

        request.on('dataReceive', (chunk: ArrayBuffer) => {
          if (!chunk || chunk.byteLength === 0) {
            return;
          }
          try {
            // writeSync 可能短写：必须按返回值推进，否则文件内容会不一致
            let sent = 0;
            while (sent < chunk.byteLength) {
              const view = sent === 0 ? chunk : chunk.slice(sent);
              const n = fs.writeSync(fd, view);
              if (n <= 0) {
                throw new Error('writeSync 返回 0');
              }
              sent += n;
            }
            written += chunk.byteLength;
            if (onProgress) {
              onProgress(written, expectedSize > 0 ? expectedSize : written);
            }
          } catch (e) {
            streamError = `写盘失败: ${(e as BusinessError).message}`;
          }
        });

        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: HttpClient.buildHeaders(extraHeaders),
          connectTimeout: HttpClient.CONNECT_TIMEOUT,
          readTimeout: HttpClient.BIG_READ_TIMEOUT,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          usingCache: false
        };

        const code = await request.requestInStream(url, options);

        if (code === 200 && startOffset > 0) {
          // 服务器忽略了 Range，旧内容已被追加污染 → 清空重下
          fs.closeSync(file);
          file = null;
          FileUtils.delete(partPath);
          return HttpClient.downloadToFile(url, savePath, expectedSize, onProgress, false);
        }
        if (code !== 200 && code !== 206) {
          return failure(`HTTP ${code}`, code);
        }
        if (streamError.length > 0) {
          return failure(streamError, code);
        }
        fs.fsyncSync(file.fd);
        fs.closeSync(file);
        file = null;

        // 以磁盘真实大小为准（短写/丢包都会在这里暴露）
        const onDisk = FileUtils.getFileSize(partPath);
        if (expectedSize > 0 && onDisk !== expectedSize) {
          return failure(`大小不符: 期望 ${expectedSize} 实际 ${onDisk}`, code);
        }
        if (written !== onDisk) {
          return failure(`写入字节数与落盘大小不一致: 写入 ${written} 落盘 ${onDisk}`, code);
        }

        if (FileUtils.exists(savePath)) {
          FileUtils.delete(savePath);
        }
        fs.renameSync(partPath, savePath);
        return { success: true, path: savePath, bytes: written, statusCode: code, error: '' };
      } catch (e) {
        const err = e as BusinessError;
        return failure(`${err.code}: ${err.message}`, 0);
      } finally {
        request.off('dataReceive');
        request.destroy();
        if (file !== null) {
          try {
            fs.closeSync(file);
          } catch {
          }
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      return failure(`${err.code}: ${err.message}`, 0);
    }
  }

  /** 探测 URL 是否可用（返回状态码，0 表示不可达） */
  static async checkUrl(url: string): Promise<number> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.HEAD,
        header: HttpClient.buildHeaders(),
        connectTimeout: 8000,
        readTimeout: 8000,
        usingCache: false
      };
      const result = await request.request(url, options);
      return result.responseCode;
    } catch (e) {
      return 0;
    } finally {
      request.destroy();
    }
  }
}
