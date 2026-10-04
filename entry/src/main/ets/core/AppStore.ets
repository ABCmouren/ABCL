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

  // 监听器列表
  //
  // 原来这里是单槽回调（private onAccountsChange: ((...) => void) | null），
  // 多个页面订阅时会互相覆盖 —— 比如账户页一订阅就把 Index 的顶掉，
  // 于是侧栏的「当前账户」永远不刷新，必须切页顺带重建才更新。
  private configListeners: ((config: LauncherConfig) => void)[] = [];
  private accountListeners: ((accounts: Account[]) => void)[] = [];
  private installationListeners: ((installations: GameInstallation[]) => void)[] = [];

  static getInstance(): AppStore {
    if (!AppStore.instance) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  getSelectedAccount(): Account | null {
    return this.accounts.find(acc => acc.selected) || null;
  }

  /**
   * 由 PreferencesManager 在异步加载完成后调用。
   * 直接写 this.store.accounts 会绕过通知，导致订阅者（侧栏「当前账户」）
   * 在冷启动后一直显示「未登录」，必须切页才刷新。
   */
  setAccounts(accounts: Account[]): void {
    this.accounts = accounts;
    this.notifyAccountsChanged();
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
    for (const cb of this.configListeners) {
      cb(this.config);
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

  /** 订阅配置变化（可多页面同时订阅，返回取消订阅函数） */
  onConfigChanged(callback: (config: LauncherConfig) => void): () => void {
    this.configListeners.push(callback);
    return () => {
      this.configListeners = this.configListeners.filter((cb: (c: LauncherConfig) => void) => cb !== callback);
    };
  }

  private notifyAccountsChanged(): void {
    for (const cb of this.accountListeners) {
      cb(this.accounts);
    }
  }

  /** 订阅账户变化（Index 的侧栏「当前账户」靠它刷新） */
  onAccountsChanged(callback: (accounts: Account[]) => void): () => void {
    this.accountListeners.push(callback);
    return () => {
      this.accountListeners = this.accountListeners.filter((cb: (a: Account[]) => void) => cb !== callback);
    };
  }

  private notifyInstallationsChanged(): void {
    for (const cb of this.installationListeners) {
      cb(this.installations);
    }
  }

  onInstallationsChanged(callback: (installations: GameInstallation[]) => void): () => void {
    this.installationListeners.push(callback);
    return () => {
      this.installationListeners =
        this.installationListeners.filter((cb: (i: GameInstallation[]) => void) => cb !== callback);
    };
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