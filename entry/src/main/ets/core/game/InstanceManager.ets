/**
 * InstanceManager — 实例管理（复制 / 重命名 / 删除 / 导出整合包）
 *
 * 对应 HMCL 实例页右键菜单里的这些项
 * （HMCLGameRepository / HMCLGameInstance / ModpackHelper）：
 *   启动 · 重命名 · 复制 · 删除 · 导出整合包 · 打开目录 · 重新下载资源
 *
 * 隔离实例的内容目录是 instances/<name>/，
 * 复制实例就是整份拷贝这个目录；导出整合包把配置类文件打成 zip。
 */
import { GameInstallation, LoaderType } from '../../model/GameVersion';
import { GameDirectoryResolver } from './GameDirectoryResolver';
import { AppStore } from '../AppStore';
import { FileUtils, Logger, StringUtils } from '../util/Utils';
import { ArchiveUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';

/** 导出整合包时应排除的目录（体积大且可重新下载） */
const EXPORT_EXCLUDE: string[] = ['libraries', 'versions', 'assets', '.modmeta', '.modpack-tmp'];

export class InstanceManager {
  private static readonly TAG = 'InstanceManager';

  /** 实例是否已安装（版本目录里存在 json） */
  static isInstalled(inst: GameInstallation): boolean {
    const dir = `${GameDirectoryResolver.versionsDir()}/${inst.versionId}`;
    return FileUtils.exists(`${dir}/${inst.versionId}.json`);
  }

  /** 重命名实例：改 name，并迁移隔离目录 */
  static rename(inst: GameInstallation, newName: string): boolean {
    const trimmed = newName.trim();
    if (trimmed.length === 0) {
      return false;
    }
    const store = AppStore.getInstance();
    // 重名检查
    for (const other of store.installations) {
      if (other.versionId !== inst.versionId && other.name === trimmed) {
        Logger.warn(InstanceManager.TAG, `实例名已存在：${trimmed}`);
        return false;
      }
    }
    const wasIsolated = GameDirectoryResolver.isIsolated(inst);
    const oldRoot = GameDirectoryResolver.contentRoot(inst);
    inst.name = trimmed;
    if (wasIsolated) {
      const newRoot = GameDirectoryResolver.isolatedRoot(inst);
      if (oldRoot !== newRoot && FileUtils.exists(oldRoot)) {
        try {
          FileUtils.moveFile(oldRoot, newRoot);
          Logger.info(InstanceManager.TAG, `实例目录已迁移：${oldRoot} → ${newRoot}`);
        } catch (e) {
          Logger.error(InstanceManager.TAG, '迁移实例目录失败', e as Error);
          return false;
        }
      }
    }
    Logger.info(InstanceManager.TAG, `重命名实例 ${inst.name}`);
    return true;
  }

  /**
   * 复制实例。
   * - 复制安装记录（新 versionId，带 "-副本"后缀）
   * - 隔离实例额外整份拷贝内容目录
   */
  static async duplicate(inst: GameInstallation): Promise<GameInstallation | null> {
    const store = AppStore.getInstance();
    let name = inst.name + ' 副本';
    let counter = 1;
    while (InstanceManager.nameTaken(store.installations, name)) {
      counter++;
      name = `${inst.name} 副本 ${counter}`;
    }

    const copy: GameInstallation = {
      versionId: inst.versionId,
      name: name,
      directory: inst.directory,
      gameVersion: inst.gameVersion,
      loaderType: inst.loaderType,
      loaderVersion: inst.loaderVersion,
      installed: inst.installed,
      installTime: Date.now(),
      lastPlayed: 0,
      javaArgs: inst.javaArgs,
      minMemory: inst.minMemory,
      maxMemory: inst.maxMemory,
      width: inst.width,
      height: inst.height,
      fullscreen: inst.fullscreen,
      customJvmArgs: inst.customJvmArgs,
      customGameArgs: inst.customGameArgs,
      // 副本一定是隔离的，否则会和原实例共用 mods/saves
      isolated: true
    };

    const srcRoot = GameDirectoryResolver.contentRoot(inst);
    if (FileUtils.exists(srcRoot)) {
      const dstRoot = GameDirectoryResolver.isolatedRoot(copy);
      try {
        FileUtils.mkdirs(dstRoot);
        const n = InstanceManager.copyTree(srcRoot, dstRoot);
        Logger.info(InstanceManager.TAG, `复制实例内容 ${n} 项 → ${dstRoot}`);
      } catch (e) {
        Logger.error(InstanceManager.TAG, '复制实例内容失败', e as Error);
        return null;
      }
    }
    store.addInstallation(copy);
    Logger.info(InstanceManager.TAG, `已复制实例 ${inst.name} → ${name}`);
    return copy;
  }

  private static nameTaken(list: GameInstallation[], name: string): boolean {
    for (const i of list) {
      if (i.name === name) {
        return true;
      }
    }
    return false;
  }

  /** 删除实例：删记录 + 删隔离目录（非隔离的不动共享目录） */
  static async remove(inst: GameInstallation): Promise<boolean> {
    const store = AppStore.getInstance();
    const isolated = GameDirectoryResolver.isIsolated(inst);
    const root = GameDirectoryResolver.contentRoot(inst);
    if (isolated && FileUtils.exists(root)) {
      try {
        FileUtils.delete(root);
        Logger.info(InstanceManager.TAG, `已删除实例目录 ${root}`);
      } catch (e) {
        Logger.error(InstanceManager.TAG, '删除实例目录失败', e as Error);
        return false;
      }
    }
    store.removeInstallation(inst.versionId);
    Logger.info(InstanceManager.TAG, `已移除实例 ${inst.name}`);
    return true;
  }

  /**
   * 导出整合包（zip）。
   * 只打包实例特有内容，排除 libraries/versions/assets 等可重新下载的大目录。
   */
  static async exportModpack(inst: GameInstallation, outDir: string): Promise<string> {
    const src = GameDirectoryResolver.contentRoot(inst);
    if (!FileUtils.exists(src)) {
      Logger.warn(InstanceManager.TAG, `实例目录不存在，无法导出：${src}`);
      return '';
    }
    FileUtils.mkdirs(outDir);
    let target = `${outDir}/${GameDirectoryResolver.safeName(inst.name)}.zip`;
    let counter = 1;
    while (FileUtils.exists(target)) {
      target = `${outDir}/${GameDirectoryResolver.safeName(inst.name)}-${counter}.zip`;
      counter++;
    }

    const stage = `${outDir}/.export-${Date.now()}`;
    try {
      FileUtils.mkdirs(stage);
      InstanceManager.copyTree(src, stage, EXPORT_EXCLUDE);
      // 补一份 manifest.json，便于别人识别（CurseForge 格式的最小子集）
      const manifest = `{"manifestType":"minecraftModpack","manifestVersion":1,` +
        `"name":"${inst.name}","version":"${inst.gameVersion}",` +
        `"author":"ABCL","overrides":"overrides",` +
        `"minecraft":{"version":"${inst.gameVersion}",` +
        `"modLoaders":[{"id":"${InstanceManager.loaderId(inst)}","primary":true}]},` +
        `"files":[]}`;
      FileUtils.writeFile(`${stage}/manifest.json`, manifest);
      // 真正的内容放 overrides/（CurseForge 约定）
      const inner = `${stage}/__content__`;
      FileUtils.mkdirs(inner);
      for (const e of FileUtils.listDir(stage)) {
        if (e === '__content__' || e === 'overrides' || e === 'manifest.json') {
          continue;
        }
        FileUtils.moveFile(`${stage}/${e}`, `${inner}/${e}`);
      }
      FileUtils.moveFile(inner, `${stage}/overrides`);

      const ok = await ArchiveUtils.zipDir(stage, target);
      FileUtils.delete(stage);
      if (!ok) {
        Logger.error(InstanceManager.TAG, '打包失败');
        return '';
      }
      Logger.info(InstanceManager.TAG, `已导出整合包 → ${target}`);
      return target;
    } catch (e) {
      FileUtils.delete(stage);
      Logger.error(InstanceManager.TAG, '导出整合包失败', e as Error);
      return '';
    }
  }

  private static loaderId(inst: GameInstallation): string {
    const lt = inst.loaderType;
    const lv = inst.loaderVersion !== null ? inst.loaderVersion : '';
    if (lt === LoaderType.FORGE) {
      return `forge-${lv}`;
    }
    if (lt === LoaderType.NEO_FORGE) {
      return `neoforge-${lv}`;
    }
    if (lt === LoaderType.FABRIC) {
      return `fabric-${lv}`;
    }
    if (lt === LoaderType.QUILT) {
      return `quilt-${lv}`;
    }
    return `vanilla-${inst.gameVersion}`;
  }

  /** 递归拷贝（可排除顶层目录名） */
  static copyTree(srcDir: string, dstDir: string, excludeTop: string[] = []): number {
    let n = 0;
    for (const entry of FileUtils.listDir(srcDir)) {
      if (excludeTop.indexOf(entry) >= 0) {
        continue;
      }
      const from = `${srcDir}/${entry}`;
      const to = `${dstDir}/${entry}`;
      if (FileUtils.isDirectory(from)) {
        FileUtils.mkdirs(to);
        n += InstanceManager.copyTree(from, to);
      } else {
        FileUtils.mkdirs(FileUtils.getDirName(to));
        FileUtils.copyFile(from, to);
        n++;
      }
    }
    return n;
  }

  /** 实例体积（递归，带上限） */
  static measure(inst: GameInstallation): number {
    const root = GameDirectoryResolver.contentRoot(inst);
    if (!FileUtils.exists(root)) {
      return 0;
    }
    let bytes = 0;
    let files = 0;
    const stack: string[] = [root];
    const LIMIT = 30000;
    while (stack.length > 0 && files < LIMIT) {
      const cur = stack.pop();
      if (cur === undefined) {
        break;
      }
      let entries: string[] = [];
      try {
        entries = FileUtils.listDir(cur);
      } catch (e) {
        continue;
      }
      for (const e of entries) {
        const full = `${cur}/${e}`;
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
        }
      }
    }
    return bytes;
  }

  static sizeLabel(bytes: number): string {
    return StringUtils.formatSize(bytes);
  }
}
