/**
 * NativesManager — 原生 LWJGL .so 库下载/提取管理器
 *
 * AMCL 的 OHOS 兼容 LWJGL 需要以下原生 .so 库：
 * - libglfw.so（GLFW 窗口/输入）
 * - liblwjgl.so（LWJGL 核心）
 * - liblwjgl_opengl.so（OpenGL 渲染）
 * - liblwjgl_stb.so（STB 图像）
 * - liblwjgl_tinyfd.so（文件对话框）
 * - libopenal.so（音频）
 * - libc++_shared.so（C++ 运行时）
 *
 * 这些 .so 文件可以从 mc-ohos-resources 的 GitHub Release 下载。
 * 提取到 {filesDir}/natives/ 目录，通过 -Djava.library.path 传递给 JVM。
 *
 * [API 26+] 使用 @ohos.net.http 下载 / @ohos.file.fs 写文件
 */

import resourceManager from '@ohos.resourceManager';
import fs from '@ohos.file.fs';
import { HttpClient } from '../network/HttpClient';
import { Constants } from '../../config/Constants';
import { Logger, FileUtils } from '../util/Utils';

export interface NativeLibInfo {
  /** 库文件名（如 libglfw.so） */
  name: string;
  /** 下载 URL */
  url: string;
  /** 目标路径 */
  targetPath: string;
  /** 大小（字节，可选） */
  size?: number;
}

export class NativesManager {
  private static readonly TAG = 'NativesManager';
  private static instance: NativesManager;
  private baseDir: string = '';
  private resourceMgr: resourceManager.ResourceManager = ({} as resourceManager.ResourceManager);
  /** 已下载的库列表 */
  private downloadedLibs: string[] = [];

  /** 原生库下载基础 URL（AMCL 的 mc-ohos-resources release） */
  private static readonly NATIVES_BASE_URL =
    'https://github.com/LZZLHY/mc-ohos-resources/releases/download/v1.0.0';

  private constructor() {}

  static getInstance(): NativesManager {
    if (!NativesManager.instance) {
      NativesManager.instance = new NativesManager();
    }
    return NativesManager.instance;
  }

  init(baseDir: string, mgr: resourceManager.ResourceManager): void {
    this.baseDir = baseDir;
    this.resourceMgr = mgr;
    const nativesDir = this.getNativesDir();
    FileUtils.mkdirs(nativesDir);
    Logger.info(NativesManager.TAG, `NativesManager initialized, natives dir: ${nativesDir}`);
  }

  /**
   * 获取原生库目录路径
   */
  getNativesDir(): string {
    return `${this.baseDir}/natives`;
  }

  /**
   * 确保所有原生库就绪
   * 优先从 rawfile 提取，失败则从网络下载
   */
  async ensureNatives(callback?: (progress: number, message: string) => void): Promise<boolean> {
    const nativesDir = this.getNativesDir();
    let allReady = true;

    for (const libName of Constants.NATIVE_LIBS) {
      const targetPath = `${nativesDir}/${libName}`;

      // 检查是否已存在
      if (FileUtils.exists(targetPath)) {
        if (!this.downloadedLibs.includes(libName)) {
          this.downloadedLibs.push(libName);
        }
        continue;
      }

      // 尝试从 rawfile 提取
      if (callback) callback(0, `Extracting ${libName}...`);
      const extracted = await this.extractFromRawfile(libName, targetPath);
      if (extracted) {
        this.downloadedLibs.push(libName);
        if (callback) callback(100, `${libName} ready`);
        continue;
      }

      // 从网络下载
      if (callback) callback(0, `Downloading ${libName}...`);
      try {
        await this.downloadNativeLib(libName, targetPath);
        this.downloadedLibs.push(libName);
        if (callback) callback(100, `${libName} downloaded`);
      } catch (e) {
        Logger.warn(NativesManager.TAG, `Failed to get native lib ${libName}: ${(e as Error).message}`);
        allReady = false;
      }
    }

    Logger.info(NativesManager.TAG, `Natives ready: ${this.downloadedLibs.length}/${Constants.NATIVE_LIBS.length}`);
    return allReady;
  }

  /**
   * 检查原生库是否已全部就绪
   */
  isReady(): boolean {
    const nativesDir = this.getNativesDir();
    for (const libName of Constants.NATIVE_LIBS) {
      if (!FileUtils.exists(`${nativesDir}/${libName}`)) {
        return false;
      }
    }
    return true;
  }

  /**
   * 获取已下载的库文件列表
   */
  getInstalledLibs(): string[] {
    const nativesDir = this.getNativesDir();
    if (!FileUtils.exists(nativesDir)) return [];
    const files = FileUtils.listDir(nativesDir);
    return files.filter(f => f.endsWith('.so'));
  }

  /**
   * 尝试从 rawfile 提取原生库
   * 如果 rawfile 中没有该文件，返回 false
   */
  private async extractFromRawfile(libName: string, targetPath: string): Promise<boolean> {
    // 尝试多个可能的 rawfile 路径
    const rawfilePaths = [
      libName,
      `natives/${libName}`,
      `libs/${libName}`,
    ];

    for (const rawfileName of rawfilePaths) {
      try {
        const data: Uint8Array = await this.resourceMgr.getRawFileContent(rawfileName);
        if (data && data.byteLength > 0) {
          FileUtils.mkdirs(targetPath.substring(0, targetPath.lastIndexOf('/')));
          const file = fs.openSync(targetPath,
            fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
          fs.writeSync(file.fd, data.buffer.slice(0, data.byteLength));
          fs.closeSync(file);
          Logger.info(NativesManager.TAG, `Extracted ${libName} from rawfile: ${rawfileName}`);
          return true;
        }
      } catch (e) {
        // rawfile 中不存在，继续尝试下一个路径
      }
    }
    return false;
  }

  /**
   * 从网络下载原生库
   */
  private async downloadNativeLib(libName: string, targetPath: string): Promise<void> {
    const url = `${NativesManager.NATIVES_BASE_URL}/${libName}`;
    Logger.info(NativesManager.TAG, `Downloading native lib: ${url}`);

    FileUtils.mkdirs(targetPath.substring(0, targetPath.lastIndexOf('/')));
    const outcome = await HttpClient.downloadToFile(url, targetPath, 0);
    if (!outcome.success) {
      throw new Error(`原生库下载失败: ${outcome.error}`);
    }

    Logger.info(NativesManager.TAG, `Downloaded native lib: ${libName}`);
  }
}