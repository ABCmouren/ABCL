// Store for ABCL global state
import { Account } from '../model/Account';
import { GameInstallation } from '../model/GameVersion';
import { LauncherConfig, DefaultConfig } from '../model/LauncherConfig';
import { PreferencesManager } from './storage/PreferencesManager';
import { Logger } from './util/Utils';

export class AppStore {
  private static readonly TAG = 'AppStore';
  private static instance: AppStore;

  // App state
  accounts: Account[] = [];
  installations: GameInstallation[] = [];
  config: LauncherConfig = DefaultConfig;
  isLoading: boolean = false;
  downloadProgress: number = 0;
  selectedInstallation: GameInstallation | null = null;

  // Callbacks
  private onConfigChange: ((config: LauncherConfig) => void) | null = null;
  private onAccountsChange: ((accounts: Account[]) => void) | null = null;
  private onInstallationsChange: ((installations: GameInstallation[]) => void) | null = null;

  static getInstance(): AppStore {
    if (!AppStore.instance) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  getSelectedAccount(): Account | null {
    return this.accounts.find(acc => acc.selected) || null;
  }

  setSelectedAccount(uuid: string): void {
    // ⚠️ 必须产生新数组：ArkUI 的 @State 靠「引用变化」判断要不要重绘。
    // 原来这里只 forEach 改数组内的对象，数组引用没变 → 界面上的
    // 选中态完全不刷新，表现就是「离线账户没法切换」。
    const next: Account[] = [];
    for (const acc of this.accounts) {
      const copy: Account = {
        id: acc.id,
        uuid: acc.uuid,
        username: acc.username,
        userType: acc.userType,
        type: acc.type,
        accessToken: acc.accessToken,
        refreshToken: acc.refreshToken,
        expiresAt: acc.expiresAt,
        lastLoginTime: acc.lastLoginTime,
        selected: acc.uuid === uuid,
        skinUrl: acc.skinUrl
      };
      next.push(copy);
    }
    this.accounts = next;
    this.notifyAccountsChanged();
    // Auto-persist
    this.persistAccounts();
  }

  addAccount(account: Account): void {
    // push 不会改变数组引用 → @State 不会重绘，同样要复制一份
    const next: Account[] = [];
    for (const acc of this.accounts) {
      next.push(acc);
    }
    const added: Account = {
      id: account.id,
      uuid: account.uuid,
      username: account.username,
      userType: account.userType,
      type: account.type,
      accessToken: account.accessToken,
      refreshToken: account.refreshToken,
      expiresAt: account.expiresAt,
      lastLoginTime: account.lastLoginTime,
      selected: next.length === 0 ? true : account.selected,
      skinUrl: account.skinUrl
    };
    next.push(added);
    this.accounts = next;
    this.notifyAccountsChanged();
    // Auto-persist
    this.persistAccounts();
  }

  removeAccount(uuid: string): void {
    this.accounts = this.accounts.filter(acc => acc.uuid !== uuid);
    this.notifyAccountsChanged();
    // Auto-persist
    this.persistAccounts();
  }

  updateConfig(config: Partial<LauncherConfig>): void {
    this.config = {
      theme: config.theme !== undefined ? config.theme : this.config.theme,
      language: config.language !== undefined ? config.language : this.config.language,
      downloadSource: config.downloadSource !== undefined ? config.downloadSource : this.config.downloadSource,
      downloadThreads: config.downloadThreads !== undefined ? config.downloadThreads : this.config.downloadThreads,
      javaPath: config.javaPath !== undefined ? config.javaPath : this.config.javaPath,
      minMemory: config.minMemory !== undefined ? config.minMemory : this.config.minMemory,
      maxMemory: config.maxMemory !== undefined ? config.maxMemory : this.config.maxMemory,
      jvmArgs: config.jvmArgs !== undefined ? config.jvmArgs : this.config.jvmArgs,
      defaultMinMemory: config.defaultMinMemory !== undefined ? config.defaultMinMemory : this.config.defaultMinMemory,
      defaultMaxMemory: config.defaultMaxMemory !== undefined ? config.defaultMaxMemory : this.config.defaultMaxMemory,
      javaArgs: config.javaArgs !== undefined ? config.javaArgs : this.config.javaArgs,
      gameDirectory: config.gameDirectory !== undefined ? config.gameDirectory : this.config.gameDirectory,
      closeLauncherOnLaunch: config.closeLauncherOnLaunch !== undefined ? config.closeLauncherOnLaunch : this.config.closeLauncherOnLaunch,
      showLog: config.showLog !== undefined ? config.showLog : this.config.showLog,
      showGameLog: config.showGameLog !== undefined ? config.showGameLog : this.config.showGameLog,
      fontSize: config.fontSize !== undefined ? config.fontSize : this.config.fontSize,
      showSidebar: config.showSidebar !== undefined ? config.showSidebar : this.config.showSidebar
    };
    if (this.onConfigChange) {
      this.onConfigChange(this.config);
    }
    // Auto-persist config changes
    this.persistConfig();
  }

  /**
   * Replace the entire installations list.
   * This is used by VersionManager when scanning local versions.
   */
  setInstallations(installations: GameInstallation[]): void {
    this.installations = installations;
    this.notifyInstallationsChanged();
    // Auto-persist
    this.persistInstallations();
  }

  onConfigChanged(callback: (config: LauncherConfig) => void): void {
    this.onConfigChange = callback;
  }

  private notifyAccountsChanged(): void {
    if (this.onAccountsChange) {
      this.onAccountsChange(this.accounts);
    }
  }

  onAccountsChanged(callback: (accounts: Account[]) => void): void {
    this.onAccountsChange = callback;
  }

  private notifyInstallationsChanged(): void {
    if (this.onInstallationsChange) {
      this.onInstallationsChange(this.installations);
    }
  }

  onInstallationsChanged(callback: (installations: GameInstallation[]) => void): void {
    this.onInstallationsChange = callback;
  }

  // ===== 自动持久化（异步，不阻塞调用方） =====

  private async persistConfig(): Promise<void> {
    try {
      const prefs = PreferencesManager.getInstance();
      await prefs.saveConfig();
    } catch (e) {
      Logger.warn(AppStore.TAG, `Auto-persist config failed: ${(e as Error).message}`);
    }
  }

  private async persistAccounts(): Promise<void> {
    try {
      const prefs = PreferencesManager.getInstance();
      await prefs.saveAccounts();
    } catch (e) {
      Logger.warn(AppStore.TAG, `Auto-persist accounts failed: ${(e as Error).message}`);
    }
  }

  private async persistInstallations(): Promise<void> {
    try {
      const prefs = PreferencesManager.getInstance();
      await prefs.saveInstallations();
    } catch (e) {
      Logger.warn(AppStore.TAG, `Auto-persist installations failed: ${(e as Error).message}`);
    }
  }
}