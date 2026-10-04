/**
 * ResourcePackManager — 资源包 / 光影包管理（真实读写目录）
 *
 * HMCL 的行为：
 *   - 资源包放在 <gameDir>/resourcepacks/，光影包放在 <gameDir>/shaderpacks/
 *   - 既支持单个 .zip 文件，也支持解包后的文件夹
 *   - 禁用 = 在名字后面加 .disabled（重命名实现，不移动文件）
 *   - 元数据从 pack.mcmeta 读取（光影包没有统一元数据，退化为文件名）
 */
import { ArchiveUtils, FileUtils, Logger } from '../util/Utils';
import { Constants } from '../../config/Constants';

export enum PackKind {
  RESOURCE = 'resourcepack',
  SHADER = 'shader'
}

export interface InstalledPack {
  /** 磁盘上的名字（含 .disabled 与 .zip） */
  fileName: string;
  path: string;
  /** 去掉 .disabled 与扩展名的展示名 */
  baseName: string;
  enabled: boolean;
  /** 是否是文件夹形态 */
  isDirectory: boolean;
  size: number;
  /** pack.mcmeta 里的描述，未解析时为空 */
  description: string;
  packFormat: number;
  metaLoaded: boolean;
}

export class ResourcePackManager {
  private static readonly TAG = 'ResourcePackManager';
  private static readonly DESC_LIMIT = 300;
  private static readonly metaCache: Map<string, string> = new Map();

  static dirName(kind: PackKind): string {
    return kind === PackKind.SHADER ? Constants.SHADER_PACKS_DIR : Constants.RESOURCE_PACKS_DIR;
  }

  static packDir(mcDir: string, kind: PackKind): string {
    return `${mcDir}/${ResourcePackManager.dirName(kind)}`;
  }

  /** 扫描目录（同步，快） */
  static scan(mcDir: string, kind: PackKind): InstalledPack[] {
    const dir = ResourcePackManager.packDir(mcDir, kind);
    const result: InstalledPack[] = [];
    if (!FileUtils.exists(dir)) {
      return result;
    }
    for (const entry of FileUtils.listDir(dir)) {
      const lower = entry.toLowerCase();
      const isZip = lower.endsWith('.zip') || lower.endsWith('.zip.disabled');
      const isDir = FileUtils.isDirectory(`${dir}/${entry}`);
      if (!isZip && !isDir) {
        continue;
      }
      const enabled = !lower.endsWith('.disabled');
      let baseName = entry;
      if (!enabled) {
        baseName = baseName.substring(0, baseName.length - '.disabled'.length);
      }
      if (baseName.toLowerCase().endsWith('.zip')) {
        baseName = baseName.substring(0, baseName.length - 4);
      }
      const full = `${dir}/${entry}`;
      const pack: InstalledPack = {
        fileName: entry,
        path: full,
        baseName: baseName,
        enabled: enabled,
        isDirectory: isDir,
        size: isDir ? 0 : FileUtils.getFileSize(full),
        description: '',
        packFormat: 0,
        metaLoaded: false
      };
      const cached = ResourcePackManager.metaCache.get(ResourcePackManager.cacheKey(full, isDir));
      if (cached !== undefined) {
        pack.description = cached;
        pack.metaLoaded = true;
      }
      result.push(pack);
    }
    result.sort((a: InstalledPack, b: InstalledPack) => {
      if (a.enabled !== b.enabled) {
        return a.enabled ? -1 : 1;
      }
      return a.baseName.localeCompare(b.baseName);
    });
    return result;
  }

  static setEnabled(pack: InstalledPack, enabled: boolean): string {
    if (pack.enabled === enabled) {
      return pack.fileName;
    }
    const dir = FileUtils.getDirName(pack.path);
    const stripped = pack.fileName.toLowerCase().endsWith('.disabled')
      ? pack.fileName.substring(0, pack.fileName.length - '.disabled'.length)
      : pack.fileName;
    const targetName = enabled ? stripped : `${stripped}.disabled`;
    const target = `${dir}/${targetName}`;
    try {
      FileUtils.moveFile(pack.path, target);
      Logger.info(ResourcePackManager.TAG, `${enabled ? '启用' : '禁用'} ${pack.fileName}`);
      return targetName;
    } catch (e) {
      Logger.error(ResourcePackManager.TAG, `切换 ${pack.fileName} 失败`, e as Error);
      return pack.fileName;
    }
  }

  static delete(pack: InstalledPack): void {
    FileUtils.delete(pack.path);
    ResourcePackManager.metaCache.delete(ResourcePackManager.cacheKey(pack.path, pack.isDirectory));
    Logger.info(ResourcePackManager.TAG, `删除 ${pack.fileName}`);
  }

  /** 把下载好的文件装进对应目录（重名自动加序号） */
  static installFile(mcDir: string, kind: PackKind, sourcePath: string, fileName: string): string {
    const dir = ResourcePackManager.packDir(mcDir, kind);
    FileUtils.mkdirs(dir);
    let targetName = fileName;
    let counter = 1;
    while (FileUtils.exists(`${dir}/${targetName}`)) {
      const dot = fileName.lastIndexOf('.');
      const base = dot > 0 ? fileName.substring(0, dot) : fileName;
      const ext = dot > 0 ? fileName.substring(dot) : '';
      targetName = `${base}-(${counter})${ext}`;
      counter++;
    }
    const target = `${dir}/${targetName}`;
    FileUtils.copyFile(sourcePath, target);
    FileUtils.delete(sourcePath);
    Logger.info(ResourcePackManager.TAG, `安装 → ${target}`);
    return target;
  }

  // ============================================================
  //  元数据（pack.mcmeta）
  // ============================================================

  static async readDescription(pack: InstalledPack, tempRoot: string): Promise<string> {
    const key = ResourcePackManager.cacheKey(pack.path, pack.isDirectory);
    const cached = ResourcePackManager.metaCache.get(key);
    if (cached !== undefined) {
      return cached;
    }
    let text = '';
    let tempDir = '';
    try {
      if (pack.isDirectory) {
        text = FileUtils.readFile(`${pack.path}/pack.mcmeta`);
        if (text.length === 0) {
          // 光影包常见结构：shaders/ 子目录
          text = FileUtils.exists(`${pack.path}/shaders`) ? '__shader__' : '';
        }
      } else {
        tempDir = `${tempRoot}/packmeta-${Math.abs(ResourcePackManager.hash(pack.fileName))}`;
        const ok = await ArchiveUtils.unzip(pack.path, tempDir);
        if (ok) {
          text = FileUtils.readFile(`${tempDir}/pack.mcmeta`);
          if (text.length === 0 && FileUtils.exists(`${tempDir}/shaders`)) {
            text = '__shader__';
          }
        }
      }
      const desc = ResourcePackManager.extractDescription(text);
      ResourcePackManager.metaCache.set(key, desc);
      Logger.info(ResourcePackManager.TAG, `解析 ${pack.fileName} → ${desc}`);
      return desc;
    } catch (e) {
      Logger.warn(ResourcePackManager.TAG, `解析 ${pack.fileName} 失败: ${(e as Error).message}`);
      return '';
    } finally {
      if (tempDir.length > 0) {
        FileUtils.delete(tempDir);
      }
    }
  }

  /**
   * 去掉 Minecraft 的格式化码（§ 后跟一个字符），HMCL 在列表里也是这么做的。
   * 否则描述会显示成 "§4■ 1.10.5 BETA§8"。
   */
  private static stripFormatting(input: string): string {
    let out = '';
    let i = 0;
    while (i < input.length) {
      const ch = input.charAt(i);
      if (ch === '\u00A7' && i + 1 < input.length) {
        i += 2;
        continue;
      }
      out += ch;
      i++;
    }
    return out.trim();
  }

  /** pack.mcmeta 的 description 可能是纯字符串，也可能是 {"text": "..."} */
  private static extractDescription(text: string): string {
    if (text.length === 0) {
      return '';
    }
    if (text === '__shader__') {
      return '光影包（包含 shaders/ 目录）';
    }
    try {
      const root = JSON.parse(text) as Record<string, Object>;
      const pack = root['pack'];
      if (pack === undefined) {
        return '';
      }
      const desc = (pack as Record<string, Object>)['description'];
      if (desc === undefined) {
        return '';
      }
      let value = '';
      if (typeof desc === 'string') {
        value = desc as string;
      } else {
        const obj = desc as Record<string, Object>;
        const t = obj['text'];
        if (t !== undefined && typeof t === 'string') {
          value = t as string;
        }
      }
      value = ResourcePackManager.stripFormatting(value);
      if (value.length > ResourcePackManager.DESC_LIMIT) {
        value = value.substring(0, ResourcePackManager.DESC_LIMIT);
      }
      return value;
    } catch (e) {
      return '';
    }
  }

  private static cacheKey(path: string, isDir: boolean): string {
    return isDir ? `${path}|dir` : `${path}|${FileUtils.getFileSize(path)}`;
  }

  private static hash(input: string): number {
    let h = 0;
    for (let i = 0; i < input.length; i++) {
      h = ((h << 5) - h) + input.charCodeAt(i);
      h = h & h;
    }
    return h;
  }
}
