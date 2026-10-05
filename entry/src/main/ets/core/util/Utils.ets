// Utility functions for ABCL
// 2026-10 重写：修复 UTF-8 解码、大文件读取栈溢出、递归删除、解压、SHA-1 校验
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import zlib from '@ohos.zlib';
import cryptoFramework from '@ohos.security.cryptoFramework';
import { BusinessError } from '@ohos.base';

export class FileUtils {
  private static readonly READ_CHUNK = 65536;

  // Check if a file or directory exists
  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch {
      return false;
    }
  }

  static isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch {
      return false;
    }
  }

  // Create directory recursively
  static mkdirs(dir: string): void {
    if (!dir || dir.length === 0) {
      return;
    }
    try {
      if (!FileUtils.exists(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      console.error(`Failed to create dir: ${dir}, ${(e as BusinessError).message}`);
    }
  }

  /**
   * 读取文本文件（UTF-8，分块解码）。
   * 旧实现用 String.fromCharCode(...bytes) —— 对 >100KB 的文件会栈溢出，
   * 而且按 Latin-1 解码会把中文/UTF-8 内容全部读成乱码，导致版本 JSON 解析失败。
   */
  static readFile(path: string): string {
    let file: fs.File | null = null;
    try {
      if (!FileUtils.exists(path)) {
        return '';
      }
      const size = fs.statSync(path).size;
      if (size <= 0) {
        return '';
      }
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
      let result = '';
      let offset = 0;
      while (offset < size) {
        const want = Math.min(FileUtils.READ_CHUNK, size - offset);
        const buffer = new ArrayBuffer(want);
        const read = fs.readSync(file.fd, buffer, { offset: offset, length: want });
        if (read <= 0) {
          break;
        }
        offset += read;
        const chunk = new Uint8Array(buffer.slice(0, read));
        result += decoder.decodeWithStream(chunk, { stream: offset < size });
      }
      return result;
    } catch (e) {
      console.error(`Failed to read file: ${path}, ${(e as BusinessError).message}`);
      return '';
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch {
        }
      }
    }
  }

  /**
   * 写入指定大小的二进制文件（用循环写满，因为 fs.writeSync 对大 buffer 会短写）。
   * 用途：造测试数据（如存档 region 文件）、校验磁盘写入完整性。
   */
  static writeBytes(path: string, size: number, fill: number = 0): void {
    try {
      const idx = path.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(path.substring(0, idx));
      }
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        const chunk = new ArrayBuffer(8192);
        new Uint8Array(chunk).fill(fill & 0xff);
        let written = 0;
        while (written < size) {
          const n = Math.min(chunk.byteLength, size - written);
          const buf: ArrayBuffer = n === chunk.byteLength ? chunk : chunk.slice(0, n);
          fs.writeSync(file.fd, buf);
          written += n;
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      Logger.error('FileUtils', 'writeBytes 失败: ' + path, e as Error);
    }
  }

  /** 读整个文件为字节（导出到用户可见位置用） */
  /** 读文件开头若干字符（判断 zip 魔数 PK 等） */
  static readFileHead(path: string, bytes: number): string {
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(bytes);
        const read = fs.readSync(file.fd, buf, { offset: 0, length: bytes });
        const u8 = new Uint8Array(buf);
        let s = '';
        for (let i = 0; i < read; i++) {
          s += String.fromCharCode(u8[i]);
        }
        return s;
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      return '';
    }
  }

  static readFileBytes(path: string): Uint8Array | null {
    try {
      if (!FileUtils.exists(path)) {
        return null;
      }
      const size = fs.statSync(path).size;
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(size);
        fs.readSync(file.fd, buf, { offset: 0, length: size });
        return new Uint8Array(buf);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      Logger.error('FileUtils', 'readFileBytes 失败: ' + path);
      return null;
    }
  }

  /** 把字节写到用户通过 picker 选出的 uri */
  static writeBytesToUri(uri: string, data: Uint8Array): boolean {
    try {
      const file = fs.openSync(uri, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        let written = 0;
        const chunk = 65536;
        while (written < data.length) {
          const n = Math.min(chunk, data.length - written);
          const slice: Uint8Array = data.subarray(written, written + n);
          fs.writeSync(file.fd, slice.buffer);
          written += n;
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (e) {
      Logger.error('FileUtils', 'writeBytesToUri 失败: ' + uri);
      return false;
    }
  }

  /** 从 picker 给出的 uri 复制到沙箱内路径 */
  static copyFromUri(uri: string, destPath: string): boolean {
    try {
      const idx = destPath.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(destPath.substring(0, idx));
      }
      fs.copyFileSync(uri, destPath);
      return true;
    } catch (e) {
      Logger.error('FileUtils', 'copyFromUri 失败: ' + uri);
      return false;
    }
  }

  /** 写入文本文件（覆盖） */
  static writeFile(path: string, content: string): void {
    try {
      const idx = path.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(path.substring(0, idx));
      }
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, content);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      console.error(`Failed to write file: ${path}, ${(e as BusinessError).message}`);
    }
  }

  /** 写入二进制（用于 jar / zip 落盘） */
  static writeBuffer(path: string, data: ArrayBuffer): void {
    try {
      const idx = path.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(path.substring(0, idx));
      }
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, data);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      console.error(`Failed to write buffer: ${path}, ${(e as BusinessError).message}`);
    }
  }

  /** 删除文件或目录（目录递归删除；旧实现只 unlinkSync，对目录必失败） */
  static delete(path: string): void {
    try {
      if (!FileUtils.exists(path)) {
        return;
      }
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const entries = fs.listFileSync(path);
        for (const entry of entries) {
          FileUtils.delete(`${path}/${entry}`);
        }
        fs.rmdirSync(path);
      } else {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.error(`Failed to delete: ${path}, ${(e as BusinessError).message}`);
    }
  }

  // List directory contents (names only, no recursion)
  static listDir(dir: string): string[] {
    try {
      if (!FileUtils.exists(dir)) {
        return [];
      }
      return fs.listFileSync(dir);
    } catch (e) {
      console.error(`Failed to list dir: ${dir}, ${(e as BusinessError).message}`);
      return [];
    }
  }

  /** 最后修改时间（毫秒），失败返回 0 */
  static statMtime(path: string): number {
    try {
      return fs.statSync(path).mtime * 1000;
    } catch {
      return 0;
    }
  }

  static getFileSize(path: string): number {
    try {
      if (!FileUtils.exists(path)) {
        return 0;
      }
      return fs.statSync(path).size;
    } catch {
      return 0;
    }
  }

  static copyFile(src: string, dest: string): void {
    try {
      const idx = dest.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(dest.substring(0, idx));
      }
      fs.copyFileSync(src, dest);
    } catch (e) {
      console.error(`Failed to copy: ${src} -> ${dest}, ${(e as BusinessError).message}`);
    }
  }

  static moveFile(src: string, dest: string): void {
    try {
      const idx = dest.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(dest.substring(0, idx));
      }
      fs.renameSync(src, dest);
    } catch (e) {
      // rename 跨设备会失败，退化为 copy + delete
      FileUtils.copyFile(src, dest);
      FileUtils.delete(src);
    }
  }

  static getExtension(path: string): string {
    const idx = path.lastIndexOf('.');
    return idx >= 0 ? path.substring(idx).toLowerCase() : '';
  }

  static getDirName(path: string): string {
    const idx = path.lastIndexOf('/');
    return idx > 0 ? path.substring(0, idx) : '';
  }

  /**
   * 计算文件 SHA-1（分块，不整文件读入内存）。
   * 返回小写十六进制；失败返回空串。
   */
  static async sha1File(path: string): Promise<string> {
    let file: fs.File | null = null;
    try {
      if (!FileUtils.exists(path)) {
        return '';
      }
      const size = fs.statSync(path).size;
      const md = cryptoFramework.createMd('SHA1');
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let offset = 0;
      while (offset < size) {
        const want = Math.min(FileUtils.READ_CHUNK, size - offset);
        const buffer = new ArrayBuffer(want);
        const read = fs.readSync(file.fd, buffer, { offset: offset, length: want });
        if (read <= 0) {
          break;
        }
        offset += read;
        const blob: cryptoFramework.DataBlob = { data: new Uint8Array(buffer.slice(0, read)) };
        // 注意：cryptoFramework 的 Md.update(DataBlob) 单参重载是【异步】的（返回 Promise），
        // 必须 await。不 await 会让分块只被随机地算进摘要，得到每次都不同的错误哈希。
        await md.update(blob);
      }
      const digest = await md.digest();
      return FileUtils.bytesToHex(new Uint8Array(digest.data));
    } catch (e) {
      console.error(`sha1 failed: ${path}, ${(e as BusinessError).message}`);
      return '';
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch {
        }
      }
    }
  }

  static bytesToHex(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      const v = bytes[i].toString(16);
      hex += v.length === 1 ? `0${v}` : v;
    }
    return hex;
  }

  /** 生成离线模式 UUID（与用户名一一对应，HMCL 兼容格式） */
  static generateUUIDv3(input: string): string {
    let hash = 0;
    for (let i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash) + input.charCodeAt(i);
      hash = hash & hash;
    }
    const hashStr = Math.abs(hash).toString(16).padStart(8, '0');
    const tail = (hashStr + hashStr + hashStr).substring(0, 12);
    return `${hashStr}-0000-3000-8000-${tail}`;
  }
}

/** 压缩包工具：解压 zip/jar、读取包内单个文本条目 */
export class ArchiveUtils {
  /** 把目录打包成 zip（导出整合包、备份世界都走这里） */
  static async zipDir(srcDir: string, zipPath: string): Promise<boolean> {
    try {
      if (!FileUtils.exists(srcDir)) {
        return false;
      }
      const idx = zipPath.lastIndexOf('/');
      if (idx > 0) {
        FileUtils.mkdirs(zipPath.substring(0, idx));
      }
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      };
      await zlib.compressFile(srcDir, zipPath, options);
      return true;
    } catch (e) {
      console.error(`zipDir failed: ${zipPath}, ${(e as BusinessError).message}`);
      return false;
    }
  }

  /** 解压 zip/jar 到目录 */
  static async unzip(zipPath: string, destDir: string): Promise<boolean> {
    try {
      FileUtils.mkdirs(destDir);
      await zlib.decompressFile(zipPath, destDir);
      return true;
    } catch (e) {
      console.error(`unzip failed: ${zipPath}, ${(e as BusinessError).message}`);
      return false;
    }
  }

  /**
   * 读取包内二进制条目并落地为文件（OptiFine 取 launchwrapper 用）。
   * 返回落地路径，不存在则返回空串。
   */
  static async readBinaryEntry(zipPath: string, entryName: string, destPath: string): Promise<string> {
    const tmp = destPath + '.x';
    FileUtils.delete(tmp);
    const ok = await ArchiveUtils.unzip(zipPath, tmp);
    if (!ok) {
      return '';
    }
    const src = `${tmp}/${entryName}`;
    if (!FileUtils.exists(src)) {
      FileUtils.delete(tmp);
      return '';
    }
    FileUtils.mkdirs(FileUtils.getDirName(destPath));
    FileUtils.copyFile(src, destPath);
    FileUtils.delete(tmp);
    return destPath;
  }

  /**
   * 读取包内单个文本条目（做法：整体解压到临时目录再读）。
   * @param zipPath 压缩包路径
   * @param entryName 包内路径，允许带或不带前导 '/'
   * @param tempDir 临时解压目录
   */
  static async readTextEntry(zipPath: string, entryName: string, tempDir: string): Promise<string> {
    FileUtils.delete(tempDir);
    const ok = await ArchiveUtils.unzip(zipPath, tempDir);
    if (!ok) {
      return '';
    }
    const normalized = entryName.startsWith('/') ? entryName.substring(1) : entryName;
    const direct = `${tempDir}/${normalized}`;
    if (FileUtils.exists(direct)) {
      return FileUtils.readFile(direct);
    }
    // 兜底：在解压结果里按文件名查找
    const base = normalized.substring(normalized.lastIndexOf('/') + 1);
    const found = ArchiveUtils.findFile(tempDir, base, 0);
    return found ? FileUtils.readFile(found) : '';
  }

  private static findFile(dir: string, name: string, depth: number): string {
    if (depth > 6) {
      return '';
    }
    const entries = FileUtils.listDir(dir);
    for (const entry of entries) {
      const full = `${dir}/${entry}`;
      if (FileUtils.isDirectory(full)) {
        const hit = ArchiveUtils.findFile(full, name, depth + 1);
        if (hit.length > 0) {
          return hit;
        }
      } else if (entry === name) {
        return full;
      }
    }
    return '';
  }
}

// Logger utility
export enum LogLevel {
  DEBUG = 'DEBUG',
  INFO = 'INFO',
  WARN = 'WARN',
  ERROR = 'ERROR'
}

export class Logger {
  private static logDir: string = '';
  private static maxLogFiles: number = 5;
  private static memBuffer: string[] = [];

  static init(logDir: string): void {
    Logger.logDir = logDir;
    FileUtils.mkdirs(logDir);
    Logger.rotateLogs();
  }

  private static getLogFileName(): string {
    const now = new Date();
    const dateStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
    return `${Logger.logDir}/hmcl_${dateStr}.log`;
  }

  private static rotateLogs(): void {
    try {
      const files = FileUtils.listDir(Logger.logDir)
        .filter((f: string) => f.startsWith('hmcl_') && f.endsWith('.log'))
        .sort()
        .reverse();
      while (files.length > Logger.maxLogFiles) {
        const old = files.pop();
        if (old) {
          FileUtils.delete(`${Logger.logDir}/${old}`);
        }
      }
    } catch {
    }
  }

  private static log(level: LogLevel, tag: string, message: string): void {
    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] [${level}] [${tag}] ${message}`;
    console.info(logLine);
    Logger.memBuffer.push(logLine);
    if (Logger.memBuffer.length > 500) {
      Logger.memBuffer.shift();
    }
    if (Logger.logDir) {
      const logFile = Logger.getLogFileName();
      try {
        const file = fs.openSync(logFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND);
        try {
          fs.writeSync(file.fd, logLine + '\n');
        } finally {
          fs.closeSync(file);
        }
      } catch {
      }
    }
  }

  static debug(tag: string, message: string): void {
    Logger.log(LogLevel.DEBUG, tag, message);
  }

  static info(tag: string, message: string): void {
    Logger.log(LogLevel.INFO, tag, message);
  }

  static warn(tag: string, message: string): void {
    Logger.log(LogLevel.WARN, tag, message);
  }

  static error(tag: string, message: string, error?: Error): void {
    Logger.log(LogLevel.ERROR, tag, `${message} ${error ? (error.stack || error.message) : ''}`);
  }

  /** 内存中的最近日志（UI「日志」页用） */
  static tail(count: number): string {
    const start = Math.max(0, Logger.memBuffer.length - count);
    return Logger.memBuffer.slice(start).join('\n');
  }

  /** 内存日志条数 */
  static memoryCount(): number {
    return Logger.memBuffer.length;
  }

  /** 清空内存缓冲（UI「清空」用） */
  static clearMemory(): void {
    Logger.memBuffer = [];
    Logger.info('Logger', '--- 内存日志已清空 ---');
  }

  /** 日志文件所在目录 */
  static dir(): string {
    return Logger.logDir;
  }

  /** 列出历史日志文件（新 → 旧） */
  static listFiles(): string[] {
    if (!Logger.logDir || !FileUtils.exists(Logger.logDir)) {
      return [];
    }
    const files = FileUtils.listDir(Logger.logDir)
      .filter((f: string) => f.startsWith('hmcl_') && f.endsWith('.log'))
      .sort()
      .reverse();
    return files;
  }

  /**
   * 读某个日志文件的内容。
   * 单文件可能很大，超过 maxBytes 时只取尾部（与 tail -f 语义一致）。
   */
  static readFile(name: string, maxBytes: number = 512 * 1024): string {
    const path = `${Logger.logDir}/${name}`;
    if (!FileUtils.exists(path)) {
      return '';
    }
    const size = FileUtils.getFileSize(path);
    if (size <= maxBytes) {
      return FileUtils.readFile(path);
    }
    // 大文件：跳过前 (size - maxBytes) 字节，取尾部
    const skip = size - maxBytes;
    try {
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buf = new ArrayBuffer(maxBytes);
        fs.readSync(file.fd, buf, { offset: skip, length: maxBytes });
        const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
        return `...(已跳过前 ${skip} 字节)\n` + decoder.decodeToString(new Uint8Array(buf));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      Logger.error('Logger', `读取日志 ${name} 失败`, e as Error);
      return '';
    }
  }

  /** 复制到剪贴板用的纯文本（去掉时间戳前缀里的控制字符） */
  static toClipboard(name: string): string {
    return Logger.readFile(name, 256 * 1024);
  }
}

export class StringUtils {
  static isBlank(str: string | null | undefined): boolean {
    return str === null || str === undefined || str.trim().length === 0;
  }

  static isNotBlank(str: string | null | undefined): boolean {
    return !StringUtils.isBlank(str);
  }

  static formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '0 B';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    const k = 1024;
    const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(k)));
    const size = parseFloat((bytes / Math.pow(k, i)).toFixed(2));
    return `${size} ${units[i]}`;
  }

  static formatSpeed(bytesPerSec: number): string {
    return `${StringUtils.formatSize(bytesPerSec)}/s`;
  }

  /** 计数（下载量/订阅数）格式化：1.2万 / 254.8万 / 3.12亿 */
  static formatCount(value: number): string {
    if (value < 10000) {
      return value.toString();
    }
    if (value < 100000000) {
      return `${(value / 10000).toFixed(1)}万`;
    }
    return `${(value / 100000000).toFixed(2)}亿`;
  }

  static formatTime(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    if (hours > 0) {
      return `${hours}h ${minutes % 60}m`;
    }
    if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`;
    }
    return `${seconds}s`;
  }

  static truncate(str: string, maxLen: number): string {
    return str.length > maxLen ? str.substring(0, maxLen - 3) + '...' : str;
  }
}

export class JsonUtils {
  static parse<T>(json: string): T | null {
    try {
      return JSON.parse(json) as T;
    } catch {
      return null;
    }
  }

  static stringify(obj: object, pretty: boolean = false): string {
    try {
      return JSON.stringify(obj, null, pretty ? 2 : undefined);
    } catch {
      return '';
    }
  }
}
