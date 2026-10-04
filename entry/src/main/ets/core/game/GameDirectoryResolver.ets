/**
 * GameDirectoryResolver — 按实例解析游戏目录（版本隔离的单一入口）
 *
 * 之前所有页面（模组/世界/资源包/光影/整合包）都直接调
 * VersionManager.getMinecraftDir()，拿到的永远是全局 minecraft/，
 * 所以多实例之间会互相串模组和存档 —— 这是做版本隔离前必须先修的。
 *
 * 隔离规则（对齐 HMCL 的 DefaultIsolationType）：
 *   - 隔离实例：内容目录用 instances/<实例名>/
 *       mods saves config resourcepacks shaderpacks datapacks
 *       screenshots schematics modpacks crash-reports logs natives
 *     而 versions / libraries / assets 仍走全局共享（避免重复占几 GB）
 *   - 非隔离实例：全部走全局 minecraft/
 *
 * 「共享」的部分要读全局、「内容」的部分要读实例目录，
 * 所以下面把两者分开返回，调用方不要自己拼路径。
 */
import { GameInstallation, IsolationType, shouldIsolate } from '../../model/GameVersion';
import { AppStore } from '../AppStore';
import { FileUtils, Logger } from '../util/Utils';
import { Constants } from '../../config/Constants';

export class GameDirectoryResolver {
  private static readonly TAG = 'GameDirectoryResolver';

  /** 共享根目录：设置里自定义的，或默认 <sandbox>/minecraft */
  static sharedRoot(): string {
    const store = AppStore.getInstance();
    const configured = store.config.gameDirectory;
    if (configured !== undefined && configured.length > 0) {
      return configured;
    }
    return Constants.baseDir();
  }

  /** 隔离实例的根目录 */
  static isolatedRoot(inst: GameInstallation): string {
    return `${GameDirectoryResolver.sharedRoot()}/instances/${GameDirectoryResolver.safeName(inst.name)}`;
  }

  /** 该实例实际使用的内容根目录（mods/saves/config 所在的目录） */
  static contentRoot(inst: GameInstallation | null): string {
    if (inst === null) {
      return GameDirectoryResolver.sharedRoot();
    }
    const policy = GameDirectoryResolver.policy();
    if (shouldIsolate(inst, policy)) {
      return GameDirectoryResolver.isolatedRoot(inst);
    }
    return GameDirectoryResolver.sharedRoot();
  }

  /** 全局隔离策略 */
  static policy(): IsolationType {
    const store = AppStore.getInstance();
    const value: string = store.config.isolationType;
    if (value === IsolationType.ALWAYS) {
      return IsolationType.ALWAYS;
    }
    if (value === IsolationType.NEVER) {
      return IsolationType.NEVER;
    }
    return IsolationType.MODDED;
  }

  /** 文件名安全化：实例名可能带空格与中文，目录名要能安全拼接 */
  static safeName(name: string): string {
    let out = '';
    for (let i = 0; i < name.length; i++) {
      const ch = name.charAt(i);
      if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' || ch === '?' ||
        ch === '"' || ch === '<' || ch === '>') {
        out += '_';
      } else {
        out += ch;
      }
    }
    return out.length > 0 ? out : 'unnamed';
  }

  /** 该实例的版本目录（隔离与非隔离都走共享，避免重复下载） */
  static versionsDir(): string {
    return `${GameDirectoryResolver.sharedRoot()}/${Constants.VERSIONS_DIR}`;
  }

  static librariesDir(): string {
    return `${GameDirectoryResolver.sharedRoot()}/${Constants.LIBRARIES_DIR}`;
  }

  static assetsDir(): string {
    return `${GameDirectoryResolver.sharedRoot()}/${Constants.ASSETS_DIR}`;
  }

  /** 该实例的内容目录下的某个子目录，例如 mods */
  static contentSub(inst: GameInstallation | null, relPath: string): string {
    return `${GameDirectoryResolver.contentRoot(inst)}/${relPath}`;
  }

  /** 该实例的 mods 目录 */
  static modsDir(inst: GameInstallation | null): string {
    return GameDirectoryResolver.contentSub(inst, Constants.MODS_DIR);
  }

  /** 该实例的 saves 目录 */
  static savesDir(inst: GameInstallation | null): string {
    return GameDirectoryResolver.contentSub(inst, Constants.SAVES_DIR);
  }

  static resourcePacksDir(inst: GameInstallation | null): string {
    return GameDirectoryResolver.contentSub(inst, Constants.RESOURCE_PACKS_DIR);
  }

  static shaderPacksDir(inst: GameInstallation | null): string {
    return GameDirectoryResolver.contentSub(inst, Constants.SHADER_PACKS_DIR);
  }

  static modpacksDir(inst: GameInstallation | null): string {
    return GameDirectoryResolver.contentSub(inst, Constants.MODPACKS_DIR);
  }

  /** 为实例确保目录结构 */
  static ensureForInstance(inst: GameInstallation | null): string {
    const root = GameDirectoryResolver.contentRoot(inst);
    try {
      FileUtils.mkdirs(root);
      for (const rel of [
        Constants.MODS_DIR, Constants.SAVES_DIR, Constants.RESOURCE_PACKS_DIR,
        Constants.SHADER_PACKS_DIR, Constants.DATAPACKS_DIR, Constants.SCREENSHOTS_DIR,
        Constants.SCHEMATICS_DIR, Constants.MODPACKS_DIR, 'config', 'crash-reports', 'logs'
      ]) {
        const full = `${root}/${rel}`;
        if (!FileUtils.exists(full)) {
          FileUtils.mkdirs(full);
        }
      }
      Logger.info(GameDirectoryResolver.TAG, `实例目录就绪：${root}`);
    } catch (e) {
      Logger.error(GameDirectoryResolver.TAG, `创建实例目录失败: ${(e as Error).message}`);
    }
    return root;
  }

  /** 是否处于隔离状态（用于 UI 提示） */
  static isIsolated(inst: GameInstallation | null): boolean {
    if (inst === null) {
      return false;
    }
    return shouldIsolate(inst, GameDirectoryResolver.policy());
  }

  /** 人类可读的位置说明 */
  static describe(inst: GameInstallation | null): string {
    if (inst === null) {
      return `${GameDirectoryResolver.sharedRoot()}（共享）`;
    }
    if (GameDirectoryResolver.isIsolated(inst)) {
      return `${GameDirectoryResolver.isolatedRoot(inst)}（已隔离，版本与依赖仍共享）`;
    }
    return `${GameDirectoryResolver.sharedRoot()}（与其它原版实例共享）`;
  }
}
