/**
 * GameDirectory — 游戏目录骨架与可见性
 *
 * 两个问题要解决：
 *
 * 1) 骨架不完整。之前目录是「用到才建」，
 *    装完游戏只有 versions/libraries/assets 三个，logs、shaderpacks、
 *    screenshots、datapacks、schematics 这些 HMCL 启动时就会铺好的目录都没有，
 *    用户往里丢文件时找不到地方。
 *    现在启动时铺一套标准 .minecraft 骨架（与 HMCL/Minecraft 一致）。
 *
 * 2) 用户不知道目录在哪。默认在 app 沙箱里
 *    （/data/app/el2/100/base/<bundle>/haps/entry/files/minecraft），
 *    外部工具无法访问、也不能用文件管理器打开。
 *    所以这里提供：路径展示、占用统计、改位置、导出（复制到用户可访问的位置）。
 */
import { FileUtils, Logger, StringUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';

export interface DirEntry {
  /** 目录名，如 versions / mods */
  name: string;
  /** 用途说明，直接显示给用户 */
  purpose: string;
  /** 相对游戏目录的路径 */
  relPath: string;
}

export interface DirUsage {
  name: string;
  bytes: number;
  fileCount: number;
}

export class GameDirectory {
  private static readonly TAG = 'GameDirectory';

  /** 标准 .minecraft 骨架（HMCL 启动实例时也会建这些） */
  static readonly SKELETON: DirEntry[] = [
    { name: Constants.VERSIONS_DIR, purpose: '各 Minecraft 版本与加载器的 json / jar', relPath: Constants.VERSIONS_DIR },
    { name: Constants.LIBRARIES_DIR, purpose: '依赖库（Fabric / Forge / LWJGL 等）', relPath: Constants.LIBRARIES_DIR },
    { name: Constants.ASSETS_DIR, purpose: '材质、声音、语言等游戏资源', relPath: Constants.ASSETS_DIR },
    { name: Constants.MODS_DIR, purpose: '模组 jar', relPath: Constants.MODS_DIR },
    { name: Constants.SAVES_DIR, purpose: '世界存档', relPath: Constants.SAVES_DIR },
    { name: Constants.RESOURCE_PACKS_DIR, purpose: '资源包', relPath: Constants.RESOURCE_PACKS_DIR },
    { name: Constants.SHADER_PACKS_DIR, purpose: '光影包', relPath: Constants.SHADER_PACKS_DIR },
    { name: Constants.DATAPACKS_DIR, purpose: '数据包', relPath: Constants.DATAPACKS_DIR },
    { name: Constants.SCREENSHOTS_DIR, purpose: '游戏截图', relPath: Constants.SCREENSHOTS_DIR },
    { name: Constants.SCHEMATICS_DIR, purpose: '建筑蓝图', relPath: Constants.SCHEMATICS_DIR },
    { name: Constants.MODPACKS_DIR, purpose: '整合包 zip', relPath: Constants.MODPACKS_DIR },
    { name: Constants.BACKUPS_DIR, purpose: '世界备份 zip', relPath: Constants.BACKUPS_DIR },
    { name: 'config', purpose: '游戏与模组配置', relPath: 'config' },
    { name: 'crash-reports', purpose: '崩溃报告', relPath: 'crash-reports' },
    { name: 'logs', purpose: '游戏日志 latest.log', relPath: 'logs' },
    { name: 'natives', purpose: '本地动态库（LWJGL 等）', relPath: 'natives' }
  ];

  /**
   * 铺好完整骨架。幂等：已存在则跳过。
   * @param mcDir 游戏目录
   * @param isolatedVersions true 时版本也放进实例目录（版本隔离）
   */
  static ensureSkeleton(mcDir: string, isolatedVersions: boolean = false): string[] {
    const created: string[] = [];
    if (mcDir.length === 0) {
      Logger.warn(GameDirectory.TAG, '游戏目录为空，跳过骨架创建');
      return created;
    }
    try {
      FileUtils.mkdirs(mcDir);
      for (const entry of GameDirectory.SKELETON) {
        // 版本隔离时跳过共享的 versions / libraries / assets
        if (isolatedVersions &&
          (entry.relPath === Constants.VERSIONS_DIR ||
            entry.relPath === Constants.LIBRARIES_DIR ||
            entry.relPath === Constants.ASSETS_DIR)) {
          continue;
        }
        const full = `${mcDir}/${entry.relPath}`;
        if (!FileUtils.exists(full)) {
          FileUtils.mkdirs(full);
          created.push(entry.relPath);
        }
      }
      Logger.info(GameDirectory.TAG,
        `游戏目录骨架就绪：${mcDir}` + (created.length > 0 ? `（新建 ${created.length} 个：${created.join(', ')}）` : '（已完整）'));
    } catch (e) {
      Logger.error(GameDirectory.TAG, `创建游戏目录骨架失败: ${(e as Error).message}`);
    }
    return created;
  }

  /** 各子目录占用（递归，带上限） */
  static measureAll(mcDir: string): DirUsage[] {
    const out: DirUsage[] = [];
    for (const entry of GameDirectory.SKELETON) {
      const full = `${mcDir}/${entry.relPath}`;
      if (!FileUtils.exists(full)) {
        out.push({ name: entry.relPath, bytes: 0, fileCount: 0 });
        continue;
      }
      out.push(GameDirectory.measure(full, entry.relPath));
    }
    // 根目录下的散文件
    const rootBytes = FileUtils.getFileSize(mcDir);
    if (rootBytes > 0) {
      out.push({ name: '（散文件）', bytes: rootBytes, fileCount: 1 });
    }
    return out;
  }

  private static measure(dir: string, name: string): DirUsage {
    let bytes = 0;
    let files = 0;
    const stack: string[] = [dir];
    // 限制：单个目录最多统计 5 万文件，避免 assets/ 这种超大目录卡住
    const LIMIT = 50000;
    while (stack.length > 0 && files < LIMIT) {
      const current = stack.pop();
      if (current === undefined) {
        break;
      }
      let entries: string[] = [];
      try {
        entries = FileUtils.listDir(current);
      } catch (e) {
        continue;
      }
      for (const e of entries) {
        const full = `${current}/${e}`;
        try {
          if (FileUtils.isDirectory(full)) {
            stack.push(full);
          } else {
            bytes += FileUtils.getFileSize(full);
            files++;
            if (files >= LIMIT) {
              break;
            }
          }
        } catch (err) {
          // 单个文件读不到就跳过
        }
      }
    }
    return { name: name, bytes: bytes, fileCount: files };
  }

  static totalBytes(usages: DirUsage[]): number {
    let n = 0;
    for (const u of usages) {
      n += u.bytes;
    }
    return n;
  }

  /**
   * 人类可读的位置说明。
   * 沙箱内路径对用户没意义，要说清楚「在哪、怎么访问」。
   */
  static describeLocation(mcDir: string, isDefault: boolean): string {
    if (!isDefault) {
      return `自定义位置：${mcDir}`;
    }
    return `应用私有目录（沙箱内，外部文件管理器无法直接浏览）
${mcDir}`;
    }

  /** 把某个子目录的路径拼出来（给「打开目录」类操作用） */
  static subPath(mcDir: string, relPath: string): string {
    return `${mcDir}/${relPath}`;
  }

  /** 用途说明 */
  static purposeOf(relPath: string): string {
    for (const entry of GameDirectory.SKELETON) {
      if (entry.relPath === relPath) {
        return entry.purpose;
      }
    }
    return '';
  }

  static formatUsage(u: DirUsage): string {
    return `${StringUtils.formatSize(u.bytes)} · ${u.fileCount} 个文件`;
  }
}
