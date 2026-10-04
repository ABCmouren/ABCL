/**
 * WorldManager — 存档（世界）管理（真实读写 saves/ 目录）
 *
 * 对应 HMCL 的 WorldListPage / WorldManagePage：
 *   - 世界就是 <gameDir>/saves/<文件夹>（含 level.dat）
 *   - 支持删除、重命名、备份为 zip、查看大小与最后修改时间
 *
 * level.dat 是 gzip 压缩的 NBT，解析它需要独立的 NBT 读取器；
 * 当前用文件夹名 + level.dat 的存在性与修改时间，这些都是磁盘上的真实信息。
 */
import zlib from '@ohos.zlib';
import { BusinessError } from '@ohos.base';
import { FileUtils, Logger, StringUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';

export interface InstalledWorld {
  /** saves/ 下的文件夹名 */
  folder: string;
  path: string;
  displayName: string;
  /** level.dat 存在才算是合法世界 */
  valid: boolean;
  hasIcon: boolean;
  /** level.dat 的最后修改时间（毫秒） */
  lastModified: number;
  /** 递归统计的字节数（异步填充，未统计时为 0） */
  sizeBytes: number;
  fileCount: number;
  sizeLoaded: boolean;
}

export class WorldManager {
  private static readonly TAG = 'WorldManager';
  /** 统计大小时最多遍历多少个文件，避免超大存档卡住 UI */
  private static readonly MAX_WALK_FILES = 20000;

  static savesDir(mcDir: string): string {
    return `${mcDir}/${Constants.SAVES_DIR}`;
  }

  static backupsDir(mcDir: string): string {
    return `${mcDir}/${Constants.BACKUPS_DIR}`;
  }

  static scan(mcDir: string): InstalledWorld[] {
    const dir = WorldManager.savesDir(mcDir);
    const result: InstalledWorld[] = [];
    if (!FileUtils.exists(dir)) {
      return result;
    }
    for (const entry of FileUtils.listDir(dir)) {
      const full = `${dir}/${entry}`;
      if (!FileUtils.isDirectory(full)) {
        continue;
      }
      const levelDat = `${full}/level.dat`;
      const valid = FileUtils.exists(levelDat);
      let modified = 0;
      try {
        modified = valid ? FileUtils.statMtime(levelDat) : FileUtils.statMtime(full);
      } catch (e) {
        modified = 0;
      }
      result.push({
        folder: entry,
        path: full,
        displayName: entry,
        valid: valid,
        hasIcon: FileUtils.exists(`${full}/icon.png`),
        lastModified: modified,
        sizeBytes: 0,
        fileCount: 0,
        sizeLoaded: false
      });
    }
    result.sort((a: InstalledWorld, b: InstalledWorld) => b.lastModified - a.lastModified);
    return result;
  }

  /** 统计单个世界的体积（递归，带上限），结果写回对象 */
  static measure(world: InstalledWorld): void {
    let bytes = 0;
    let files = 0;
    const stack: string[] = [world.path];
    while (stack.length > 0 && files < WorldManager.MAX_WALK_FILES) {
      const current = stack.pop();
      if (current === undefined) {
        break;
      }
      for (const entry of FileUtils.listDir(current)) {
        const full = `${current}/${entry}`;
        if (FileUtils.isDirectory(full)) {
          stack.push(full);
        } else {
          bytes += FileUtils.getFileSize(full);
          files++;
          if (files >= WorldManager.MAX_WALK_FILES) {
            break;
          }
        }
      }
    }
    world.sizeBytes = bytes;
    world.fileCount = files;
    world.sizeLoaded = true;
  }

  static delete(world: InstalledWorld): void {
    FileUtils.delete(world.path);
    Logger.info(WorldManager.TAG, `删除世界 ${world.folder}`);
  }

  /** 重命名（只改文件夹名，与 HMCL 的「重命名世界」一致） */
  static rename(world: InstalledWorld, newFolder: string): boolean {
    if (newFolder.length === 0 || newFolder.indexOf('/') >= 0) {
      return false;
    }
    const parent = FileUtils.getDirName(world.path);
    const target = `${parent}/${newFolder}`;
    if (FileUtils.exists(target)) {
      Logger.warn(WorldManager.TAG, `目标已存在: ${newFolder}`);
      return false;
    }
    try {
      FileUtils.moveFile(world.path, target);
      Logger.info(WorldManager.TAG, `重命名 ${world.folder} → ${newFolder}`);
      return true;
    } catch (e) {
      Logger.error(WorldManager.TAG, '重命名失败', e as Error);
      return false;
    }
  }

  /** 备份为 zip（@ohos.zlib.compressFile 支持目录打包） */
  static async backup(mcDir: string, world: InstalledWorld): Promise<string> {
    const dir = WorldManager.backupsDir(mcDir);
    FileUtils.mkdirs(dir);
    const stamp = WorldManager.timestamp();
    let target = `${dir}/${world.folder}-${stamp}.zip`;
    let counter = 1;
    while (FileUtils.exists(target)) {
      target = `${dir}/${world.folder}-${stamp}-(${counter}).zip`;
      counter++;
    }
    try {
      const options: zlib.Options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
      };
      await zlib.compressFile(world.path, target, options);
      Logger.info(WorldManager.TAG, `备份世界 ${world.folder} → ${target}`);
      return target;
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(WorldManager.TAG, `备份失败: ${err.message}`);
      return '';
    }
  }

  /**
   * 创建演示存档 —— 用来在没有 arm64 真机、无法真正进游戏的情况下
   * 验证世界管理链路（扫描 / 统计 / 备份 / 重命名 / 删除）是否真的可用。
   *
   * 只在没有任何存档时写入，且带明显前缀，方便识别与清理。
   */
  static seedDemoWorlds(mcDir: string): number {
    const dir = WorldManager.savesDir(mcDir);
    if (FileUtils.exists(dir) && FileUtils.listDir(dir).length > 0) {
      return 0;
    }
    let created = 0;
    const samples: string[] = ['Demo_Survival', 'Demo_Adventure', 'Demo_NoLevelDat'];
    for (const name of samples) {
      const worldDir = `${dir}/${name}`;
      try {
        FileUtils.mkdirs(`${worldDir}/region`);
        if (name !== 'Demo_NoLevelDat') {
          FileUtils.writeFile(`${worldDir}/level.dat`, 'demo-level-data');
          if (name === 'Demo_Survival') {
            FileUtils.writeFile(`${worldDir}/icon.png`, 'demo-icon');
          }
        }
        FileUtils.writeBytes(`${worldDir}/region/r.0.0.mca`, 64 * 1024, 7);
        if (name === 'Demo_Adventure') {
          FileUtils.writeBytes(`${worldDir}/region/r.0.1.mca`, 512 * 1024, 3);
        }
        created++;
      } catch (e) {
        Logger.warn(WorldManager.TAG, `创建演示存档 ${name} 失败: ${(e as Error).message}`);
      }
    }
    Logger.info(WorldManager.TAG, `已创建 ${created} 个演示存档用于自检`);
    return created;
  }

  private static timestamp(): string {
    const d = new Date();
    const p = (n: number): string => n < 10 ? `0${n}` : n.toString();
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  }

  static sizeLabel(world: InstalledWorld): string {
    if (!world.sizeLoaded) {
      return '统计中…';
    }
    return `${StringUtils.formatSize(world.sizeBytes)} · ${world.fileCount} 个文件`;
  }
}
