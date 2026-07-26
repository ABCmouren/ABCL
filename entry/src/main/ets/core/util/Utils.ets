// Utility functions for HMCL-HarmonyOS
import fs from '@ohos.file.fs';

export class FileUtils {
  // Check if a file or directory exists
  static exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch {
      return false;
    }
  }

  // Create directory recursively
  static mkdirs(dir: string): void {
    try {
      if (!FileUtils.exists(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      console.error(`Failed to create dir: ${dir}`, (e as Error).message);
    }
  }

  // Read file as string
  static readFile(path: string): string {
    try {
      if (!FileUtils.exists(path)) return '';
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf, { offset: 0, length: stat.size });
      fs.closeSync(file);
      return String.fromCharCode(...new Uint8Array(buf));
    } catch (e) {
      console.error(`Failed to read file: ${path}`, (e as Error).message);
      return '';
    }
  }

  // Write string to file
  static writeFile(path: string, content: string): void {
    try {
      const dir = path.substring(0, path.lastIndexOf('/'));
      FileUtils.mkdirs(dir);
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
    } catch (e) {
      console.error(`Failed to write file: ${path}`, (e as Error).message);
    }
  }

  // Delete file or directory
  static delete(path: string): void {
    try {
      if (FileUtils.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      console.error(`Failed to delete: ${path}`, (e as Error).message);
    }
  }

  // List directory contents
  static listDir(dir: string): string[] {
    try {
      if (!FileUtils.exists(dir)) return [];
      const files = fs.listFileSync(dir, { recursion: false });
      const result: string[] = [];
      // listFileSync might return relative paths
      for (const f of files) {
        result.push(f);
      }
      return result;
    } catch (e) {
      console.error(`Failed to list dir: ${dir}`, (e as Error).message);
      return [];
    }
  }

  // Get file size
  static getFileSize(path: string): number {
    try {
      if (!FileUtils.exists(path)) return 0;
      const stat = fs.statSync(path);
      return stat.size;
    } catch {
      return 0;
    }
  }

  // Copy file
  static copyFile(src: string, dest: string): void {
    try {
      const dir = dest.substring(0, dest.lastIndexOf('/'));
      FileUtils.mkdirs(dir);
      fs.copyFileSync(src, dest);
    } catch (e) {
      console.error(`Failed to copy: ${src} -> ${dest}`, (e as Error).message);
    }
  }

  // Move file
  static moveFile(src: string, dest: string): void {
    try {
      FileUtils.copyFile(src, dest);
      FileUtils.delete(src);
    } catch (e) {
      console.error(`Failed to move: ${src} -> ${dest}`, (e as Error).message);
    }
  }

  // Get file extension
  static getExtension(path: string): string {
    const idx = path.lastIndexOf('.');
    return idx >= 0 ? path.substring(idx).toLowerCase() : '';
  }

  // Generate UUID v4
  static generateUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  // Generate UUID v3 from string (offline mode)
  static generateUUIDv3(input: string): string {
    // Simple hash-based UUID for offline mode (consistent per username)
    let hash = 0;
    for (let i = 0; i < input.length; i++) {
      const char = input.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    const hashStr = Math.abs(hash).toString(16).padStart(8, '0');
    return `${hashStr}-0000-4000-8000-${hashStr.padStart(12, '0').substring(0, 12)}`;
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
        .filter(f => f.startsWith('hmcl_') && f.endsWith('.log'))
        .sort()
        .reverse();
      while (files.length > Logger.maxLogFiles) {
        const old = files.pop();
        if (old) {
          FileUtils.delete(`${Logger.logDir}/${old}`);
        }
      }
    } catch {
      // Silently handle rotation errors
    }
  }

  private static log(level: LogLevel, tag: string, message: string): void {
    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] [${level}] [${tag}] ${message}`;
    
    // Console output
    console.info(logLine);

    // File output
    if (Logger.logDir) {
      const logFile = Logger.getLogFileName();
      try {
        const file = fs.openSync(logFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND);
        fs.writeSync(file.fd, logLine + '\n');
        fs.closeSync(file);
      } catch {
        // Silently handle file write errors
      }
    }
  }

  static debug(tag: string, message: string): void { Logger.log(LogLevel.DEBUG, tag, message); }
  static info(tag: string, message: string): void { Logger.log(LogLevel.INFO, tag, message); }
  static warn(tag: string, message: string): void { Logger.log(LogLevel.WARN, tag, message); }
  static error(tag: string, message: string, error?: Error): void {
    Logger.log(LogLevel.ERROR, tag, `${message} ${error ? error.stack || error.message : ''}`);
  }
}

// String utilities
export class StringUtils {
  static isBlank(str: string | null | undefined): boolean {
    return str === null || str === undefined || str.trim().length === 0;
  }

  static isNotBlank(str: string | null | undefined): boolean {
    return !StringUtils.isBlank(str);
  }

  static formatSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const k = 1024;
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    const size = parseFloat((bytes / Math.pow(k, i)).toFixed(2));
    return `${size} ${units[i]}`;
  }

  static formatSpeed(bytesPerSec: number): string {
    return `${StringUtils.formatSize(bytesPerSec)}/s`;
  }

  static formatTime(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    if (hours > 0) return `${hours}h ${minutes % 60}m`;
    if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
    return `${seconds}s`;
  }

  static truncate(str: string, maxLen: number): string {
    return str.length > maxLen ? str.substring(0, maxLen - 3) + '...' : str;
  }
}

// JSON utilities
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