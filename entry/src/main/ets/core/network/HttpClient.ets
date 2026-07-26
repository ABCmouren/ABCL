/**
 * HTTP client for HMCL-HarmonyOS
 * Wraps @ohos.net.http with typed JSON responses and file download support
 */
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';

export interface HttpResult<T> {
  success: boolean;
  data?: T;
  error?: string;
  statusCode?: number;
}

export class HttpClient {
  static readonly DEFAULT_TIMEOUT = 30000;
  static readonly USER_AGENT = 'HMCL-Harmony/1.0';

  static async getJson<T>(url: string, headers?: Record<string, string>): Promise<HttpResult<T>> {
    const httpRequest = http.createHttp();
    try {
      const headerObj: Record<string, string> = {
        'User-Agent': HttpClient.USER_AGENT,
        'Content-Type': 'application/json'
      };
      if (headers) {
        const keys = Object.keys(headers);
        for (const key of keys) {
          headerObj[key] = headers[key];
        }
      }
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headerObj,
        connectTimeout: HttpClient.DEFAULT_TIMEOUT,
        readTimeout: HttpClient.DEFAULT_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode === 200) {
        const data = JSON.parse(result.result as string) as T;
        return { success: true, data, statusCode: result.responseCode };
      }
      return { success: false, error: `HTTP ${result.responseCode}`, statusCode: result.responseCode };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: err.message || 'Network error' };
    } finally {
      httpRequest.destroy();
    }
  }

  static async postJson<T>(url: string, body: object, headers?: Record<string, string>): Promise<HttpResult<T>> {
    const httpRequest = http.createHttp();
    try {
      const headerObj: Record<string, string> = {
        'User-Agent': HttpClient.USER_AGENT,
        'Content-Type': 'application/json'
      };
      if (headers) {
        const keys = Object.keys(headers);
        for (const key of keys) {
          headerObj[key] = headers[key];
        }
      }
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headerObj,
        extraData: JSON.stringify(body),
        connectTimeout: HttpClient.DEFAULT_TIMEOUT,
        readTimeout: HttpClient.DEFAULT_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode === 200) {
        const data = JSON.parse(result.result as string) as T;
        return { success: true, data, statusCode: result.responseCode };
      }
      return { success: false, error: `HTTP ${result.responseCode}`, statusCode: result.responseCode };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: err.message };
    } finally {
      httpRequest.destroy();
    }
  }

  static async downloadFile(url: string, savePath: string, onProgress?: (downloaded: number, total: number) => void): Promise<HttpResult<string>> {
    const httpRequest = http.createHttp();
    try {
      // Ensure directory exists
      const dir = savePath.substring(0, savePath.lastIndexOf('/'));
      try {
        fs.accessSync(dir);
      } catch {
        fs.mkdirSync(dir, true);
      }

      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': HttpClient.USER_AGENT },
        connectTimeout: 60000,
        readTimeout: 600000, // 10 min for large downloads
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });

      if (result.responseCode === 200) {
        const rawData = result.result as ArrayBuffer;
        // Write the response to file
        const file = fs.openSync(savePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        if (rawData) {
          fs.writeSync(file.fd, rawData);
        }
        fs.closeSync(file);
        return { success: true, data: savePath, statusCode: result.responseCode };
      }
      return { success: false, error: `Download failed: HTTP ${result.responseCode}`, statusCode: result.responseCode };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: err.message || 'Download failed' };
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * Fetch a URL and return the raw text content (XML, plain text, etc.)
   * Used by ModLoaderInstaller to fetch Maven metadata XML and install profiles.
   */
  static async getText(url: string, headers?: Record<string, string>): Promise<HttpResult<string>> {
    const httpRequest = http.createHttp();
    try {
      const headerObj: Record<string, string> = {
        'User-Agent': HttpClient.USER_AGENT,
      };
      if (headers) {
        const keys = Object.keys(headers);
        for (const key of keys) {
          headerObj[key] = headers[key];
        }
      }
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headerObj,
        connectTimeout: HttpClient.DEFAULT_TIMEOUT,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode === 200) {
        return { success: true, data: result.result as string, statusCode: result.responseCode };
      }
      return { success: false, error: `HTTP ${result.responseCode}`, statusCode: result.responseCode };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: err.message || 'Network error' };
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 发送 application/x-www-form-urlencoded POST 请求
   * @param url 请求 URL
   * @param body 已编码的 form body 字符串（如 "key1=val1&key2=val2"）
   */
  static async postForm(url: string, body: string): Promise<HttpResult<string>> {
    const httpRequest = http.createHttp();
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'User-Agent': HttpClient.USER_AGENT,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        extraData: body,
        connectTimeout: HttpClient.DEFAULT_TIMEOUT,
        readTimeout: HttpClient.DEFAULT_TIMEOUT,
        expectDataType: http.HttpDataType.STRING
      });
      if (result.responseCode === 200) {
        return { success: true, data: result.result as string, statusCode: result.responseCode };
      }
      return { success: false, error: `HTTP ${result.responseCode}`, statusCode: result.responseCode };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: err.message || 'Network error' };
    } finally {
      httpRequest.destroy();
    }
  }

  static async checkUrl(url: string): Promise<HttpResult<number>> {
    const httpRequest = http.createHttp();
    try {
      const result = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': HttpClient.USER_AGENT },
        connectTimeout: 10000,
        readTimeout: 10000
      });
      return { success: true, data: result.responseCode, statusCode: result.responseCode };
    } catch (e) {
      const err = e as BusinessError;
      return { success: false, error: err.message };
    } finally {
      httpRequest.destroy();
    }
  }
}