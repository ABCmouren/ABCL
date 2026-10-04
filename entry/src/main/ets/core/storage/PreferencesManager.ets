/**
 * PreferencesManager — 设置持久化存储
 *
 * 使用 @ohos.data.preferences 实现 LauncherConfig / Accounts / Installations
 * 的持久化存储、读取、导入导出功能。
 *
 * 参照 AMCL 的 Preferences 持久化模式：
 * - 每次设置变更自动保存
 * - 启动时自动加载
 * - 支持 JSON 导入/导出
 *
 * [API 26+] 使用 @ohos.data.preferences
 */

import dataPreferences from '@ohos.data.preferences';
import { Account, UserType } from '../../model/Account';
import { LauncherConfig, DefaultConfig, ThemeMode } from '../../model/LauncherConfig';
import { GameInstallation, DownloadSource, LoaderType } from '../../model/GameVersion';
import { AppStore } from '../AppStore';
import { Logger, FileUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';
import { BusinessError } from '@ohos.base';
import common from '@ohos.app.ability.common';

export interface ImportResult {
  accounts: number;
  installations: number;
}

export interface ExportData {
  version: number;
  exportedAt: string;
  accounts: Account[];
  installations: GameInstallation[];
  config: LauncherConfig;
}

export class PreferencesManager {
  private static readonly TAG = 'PreferencesManager';
  private static readonly PREFERENCES_NAME = 'hmcl_preferences';
  private static instance: PreferencesManager;
  private preferences: dataPreferences.Preferences | null = null;
  private store: AppStore;
  private baseDir: string = '';
  private context: common.UIAbilityContext | null = null;

  private constructor() {
    this.store = AppStore.getInstance();
  }

  static getInstance(): PreferencesManager {
    if (!PreferencesManager.instance) {
      PreferencesManager.instance = new PreferencesManager();
    }
    return PreferencesManager.instance;
  }

  /**
   * 初始化 PreferencesManager
   * 必须在应用启动时调用（在 EntryAbility.onCreate 中调用）
   */
  async init(baseDir: string): Promise<void> {
    this.baseDir = baseDir;
    Logger.info(PreferencesManager.TAG, `Initializing PreferencesManager, baseDir: ${baseDir}`);

    try {
      if (!this.context) {
        Logger.warn(PreferencesManager.TAG, 'Context not set, cannot initialize preferences');
        return;
      }
      this.preferences = await dataPreferences.getPreferences(this.context, PreferencesManager.PREFERENCES_NAME);
      Logger.info(PreferencesManager.TAG, 'Preferences initialized successfully');

      // 自动加载已保存的数据
      await this.loadAll();
    } catch (e) {
      const err = e as BusinessError;
      Logger.error(PreferencesManager.TAG, `Failed to initialize preferences: ${err.message}`);
    }
  }

  // ============================================================
  // 保存方法
  // ============================================================

  /**
   * 保存所有数据到 Preferences
   */
  async saveAll(): Promise<void> {
    if (!this.preferences) {
      Logger.warn(PreferencesManager.TAG, 'Preferences not initialized, skipping saveAll');
      return;
    }

    try {
      await this.saveConfig();
      await this.saveAccounts();
      await this.saveInstallations();
      Logger.info(PreferencesManager.TAG, 'All data saved to preferences');
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to save all: ${(e as Error).message}`);
    }
  }

  /**
   * 保存 LauncherConfig
   */
  async saveConfig(): Promise<void> {
    if (!this.preferences) return;

    try {
      const config = this.store.config;
      await this.preferences.put('config_theme', config.theme);
      await this.preferences.put('config_language', config.language);
      await this.preferences.put('config_downloadSource', config.downloadSource);
      await this.preferences.put('config_downloadThreads', config.downloadThreads);
      await this.preferences.put('config_javaPath', config.javaPath);
      await this.preferences.put('config_minMemory', config.minMemory);
      await this.preferences.put('config_maxMemory', config.maxMemory);
      await this.preferences.put('config_jvmArgs', config.jvmArgs);
      await this.preferences.put('config_defaultMinMemory', config.defaultMinMemory);
      await this.preferences.put('config_defaultMaxMemory', config.defaultMaxMemory);
      await this.preferences.put('config_javaArgs', config.javaArgs);
      await this.preferences.put('config_gameDirectory', config.gameDirectory);
      await this.preferences.put('config_closeLauncherOnLaunch', config.closeLauncherOnLaunch);
      await this.preferences.put('config_showLog', config.showLog);
      await this.preferences.put('config_showGameLog', config.showGameLog);
      await this.preferences.put('config_fontSize', config.fontSize);
      await this.preferences.put('config_showSidebar', config.showSidebar);
      await this.preferences.flush();
      Logger.info(PreferencesManager.TAG, 'Config saved');
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to save config: ${(e as Error).message}`);
    }
  }

  /**
   * 保存 Accounts 列表（JSON 序列化）
   */
  async saveAccounts(): Promise<void> {
    if (!this.preferences) return;

    try {
      const accountsJson = JSON.stringify(this.store.accounts);
      await this.preferences.put(Constants.PREF_KEY_ACCOUNTS, accountsJson);

      // 保存选中的 account UUID
      const selectedAccount = this.store.getSelectedAccount();
      if (selectedAccount) {
        await this.preferences.put(Constants.PREF_KEY_SELECTED_ACCOUNT, selectedAccount.uuid);
      }

      await this.preferences.flush();
      Logger.info(PreferencesManager.TAG, `Accounts saved: ${this.store.accounts.length}`);
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to save accounts: ${(e as Error).message}`);
    }
  }

  /**
   * 保存 Installations 列表（JSON 序列化）
   */
  async saveInstallations(): Promise<void> {
    if (!this.preferences) return;

    try {
      const installationsJson = JSON.stringify(this.store.installations);
      await this.preferences.put(Constants.PREF_KEY_INSTALLATIONS, installationsJson);
      await this.preferences.flush();
      Logger.info(PreferencesManager.TAG, `Installations saved: ${this.store.installations.length}`);
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to save installations: ${(e as Error).message}`);
    }
  }

  /**
   * 保存单个启动设置项（按需保存，避免全量写入）
   */
  async saveLaunchSettings(settings: Record<string, Object>): Promise<void> {
    if (!this.preferences) return;

    try {
      const existingJson = await this.preferences.get(Constants.PREF_KEY_LAUNCH_SETTINGS, '{}');
      const existing = JSON.parse(existingJson as string) as Record<string, Object>;
      const merged: Record<string, Object> = {};
      const keys = Object.keys(existing);
      for (const key of keys) {
        merged[key] = existing[key];
      }
      const settingsKeys = Object.keys(settings);
      for (const key of settingsKeys) {
        merged[key] = settings[key];
      }
      await this.preferences.put(Constants.PREF_KEY_LAUNCH_SETTINGS, JSON.stringify(merged));
      await this.preferences.flush();
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to save launch settings: ${(e as Error).message}`);
    }
  }

  // ============================================================
  // 加载方法
  // ============================================================

  /**
   * 从 Preferences 加载所有数据
   */
  async loadAll(): Promise<void> {
    if (!this.preferences) {
      Logger.warn(PreferencesManager.TAG, 'Preferences not initialized, skipping loadAll');
      return;
    }

    try {
      await this.loadConfig();
      await this.loadAccounts();
      await this.loadInstallations();
      Logger.info(PreferencesManager.TAG, 'All data loaded from preferences');
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to load all: ${(e as Error).message}`);
    }
  }

  /**
   * 加载 LauncherConfig
   */
  async loadConfig(): Promise<void> {
    if (!this.preferences) return;

    try {
      const theme = await this.preferences.get('config_theme', DefaultConfig.theme);
      const language = await this.preferences.get('config_language', DefaultConfig.language);
      const downloadSource = await this.preferences.get('config_downloadSource', DefaultConfig.downloadSource);
      const downloadThreads = await this.preferences.get('config_downloadThreads', DefaultConfig.downloadThreads);
      const javaPath = await this.preferences.get('config_javaPath', DefaultConfig.javaPath);
      const minMemory = await this.preferences.get('config_minMemory', DefaultConfig.minMemory);
      const maxMemory = await this.preferences.get('config_maxMemory', DefaultConfig.maxMemory);
      const jvmArgs = await this.preferences.get('config_jvmArgs', DefaultConfig.jvmArgs);
      const defaultMinMemory = await this.preferences.get('config_defaultMinMemory', DefaultConfig.defaultMinMemory);
      const defaultMaxMemory = await this.preferences.get('config_defaultMaxMemory', DefaultConfig.defaultMaxMemory);
      const javaArgs = await this.preferences.get('config_javaArgs', DefaultConfig.javaArgs);
      const gameDirectory = await this.preferences.get('config_gameDirectory', DefaultConfig.gameDirectory);
      const closeLauncherOnLaunch = await this.preferences.get('config_closeLauncherOnLaunch', DefaultConfig.closeLauncherOnLaunch);
      const showLog = await this.preferences.get('config_showLog', DefaultConfig.showLog);
      const showGameLog = await this.preferences.get('config_showGameLog', DefaultConfig.showGameLog);
      const fontSize = await this.preferences.get('config_fontSize', DefaultConfig.fontSize);
      const showSidebar = await this.preferences.get('config_showSidebar', DefaultConfig.showSidebar);

      this.store.updateConfig({
        theme: theme as ThemeMode,
        language: language as string,
        downloadSource: downloadSource as DownloadSource,
        downloadThreads: downloadThreads as number,
        javaPath: javaPath as string,
        minMemory: minMemory as number,
        maxMemory: maxMemory as number,
        jvmArgs: jvmArgs as string,
        defaultMinMemory: defaultMinMemory as number,
        defaultMaxMemory: defaultMaxMemory as number,
        javaArgs: javaArgs as string,
        gameDirectory: gameDirectory as string,
        closeLauncherOnLaunch: closeLauncherOnLaunch as boolean,
        showLog: showLog as boolean,
        showGameLog: showGameLog as boolean,
        fontSize: fontSize as number,
        showSidebar: showSidebar as boolean,
      });

      Logger.info(PreferencesManager.TAG, 'Config loaded from preferences');
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to load config: ${(e as Error).message}`);
    }
  }

  /**
   * 加载 Accounts 列表
   */
  async loadAccounts(): Promise<void> {
    if (!this.preferences) return;

    try {
      const accountsJson = await this.preferences.get(Constants.PREF_KEY_ACCOUNTS, '[]');
      const accounts = JSON.parse(accountsJson as string) as Account[];

      // 恢复选中的 account
      const selectedUuid = await this.preferences.get(Constants.PREF_KEY_SELECTED_ACCOUNT, '');
      if (selectedUuid) {
        for (const acc of accounts) {
          acc.selected = acc.uuid === selectedUuid;
        }
      }

      this.store.accounts = accounts;
      Logger.info(PreferencesManager.TAG, `Accounts loaded: ${accounts.length}`);
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to load accounts: ${(e as Error).message}`);
    }
  }

  /**
   * 加载 Installations 列表
   */
  async loadInstallations(): Promise<void> {
    if (!this.preferences) return;

    try {
      const installationsJson = await this.preferences.get(Constants.PREF_KEY_INSTALLATIONS, '[]');
      const installations = JSON.parse(installationsJson as string) as GameInstallation[];

      this.store.installations = installations;
      Logger.info(PreferencesManager.TAG, `Installations loaded: ${installations.length}`);
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to load installations: ${(e as Error).message}`);
    }
  }

  /**
   * 获取下载来源设置
   */
  async getDownloadSource(): Promise<DownloadSource> {
    if (!this.preferences) return DownloadSource.BMCLAPI;
    const val = await this.preferences.get(Constants.PREF_KEY_DOWNLOAD_SOURCE, DownloadSource.BMCLAPI);
    return val as DownloadSource;
  }

  /**
   * 保存下载来源设置
   */
  /** 远端资源源（Modrinth / CurseForge） */
  async getRemoteSource(): Promise<string> {
    if (!this.preferences) {
      return 'modrinth';
    }
    const val = await this.preferences.get(Constants.PREF_KEY_REMOTE_SOURCE, 'modrinth');
    return val as string;
  }

  async setRemoteSource(source: string): Promise<void> {
    if (!this.preferences) {
      return;
    }
    await this.preferences.put(Constants.PREF_KEY_REMOTE_SOURCE, source);
    await this.preferences.flush();
  }

  /** CurseForge API Key（用户自备） */
  async getCurseForgeKey(): Promise<string> {
    if (!this.preferences) {
      return '';
    }
    const val = await this.preferences.get(Constants.PREF_KEY_CURSEFORGE_KEY, '');
    return val as string;
  }

  async setCurseForgeKey(key: string): Promise<void> {
    if (!this.preferences) {
      return;
    }
    await this.preferences.put(Constants.PREF_KEY_CURSEFORGE_KEY, key);
    await this.preferences.flush();
  }

  async setDownloadSource(source: DownloadSource): Promise<void> {
    if (!this.preferences) return;
    await this.preferences.put(Constants.PREF_KEY_DOWNLOAD_SOURCE, source);
    await this.preferences.flush();
  }

  // ============================================================
  // 导入 / 导出
  // ============================================================

  /**
   * 导出所有数据为 JSON 文件
   * 返回导出文件的路径
   */
  async exportToFile(filePath: string): Promise<boolean> {
    try {
      const exportData: ExportData = {
        version: 1,
        exportedAt: new Date().toISOString(),
        accounts: this.store.accounts,
        installations: this.store.installations,
        config: this.store.config,
      };

      FileUtils.writeFile(filePath, JSON.stringify(exportData, null, 2));
      Logger.info(PreferencesManager.TAG, `Data exported to: ${filePath}`);
      return true;
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to export data: ${(e as Error).message}`);
      return false;
    }
  }

  /**
   * 从 JSON 文件导入数据
   * 返回导入的条目数
   */
  async importFromFile(filePath: string): Promise<ImportResult> {
    try {
      if (!FileUtils.exists(filePath)) {
        throw new Error('File not found: ' + filePath);
      }

      const content = FileUtils.readFile(filePath);
      const importData = JSON.parse(content) as ExportData;

      if (!importData.version) {
        throw new Error('Invalid export file format');
      }

      // 导入 accounts
      if (importData.accounts && importData.accounts.length > 0) {
        this.store.accounts = importData.accounts;
        await this.saveAccounts();
      }

      // 导入 installations
      if (importData.installations && importData.installations.length > 0) {
        this.store.installations = importData.installations;
        await this.saveInstallations();
      }

      // 导入 config
      if (importData.config) {
        this.store.updateConfig(importData.config);
        await this.saveConfig();
      }

      const ac = importData.accounts ? importData.accounts.length : 0;
      const ins = importData.installations ? importData.installations.length : 0;
      Logger.info(PreferencesManager.TAG, `Data imported: ${ac} accounts, ${ins} installations`);
      const result: ImportResult = {
        accounts: ac,
        installations: ins,
      };
      return result;
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to import data: ${(e as Error).message}`);
      throw e as Error;
    }
  }

  /**
   * 清除所有数据
   */
  async clearAll(): Promise<void> {
    if (!this.preferences) return;

    try {
      await this.preferences.clear();
      await this.preferences.flush();
      Logger.info(PreferencesManager.TAG, 'All preferences cleared');
    } catch (e) {
      Logger.error(PreferencesManager.TAG, `Failed to clear preferences: ${(e as Error).message}`);
    }
  }

  /**
   * 设置上下文（由 EntryAbility 在 onCreate 时调用）
   */
  setContext(context: common.UIAbilityContext): void {
    this.context = context;
    Logger.info(PreferencesManager.TAG, 'Context set for PreferencesManager');
  }
}