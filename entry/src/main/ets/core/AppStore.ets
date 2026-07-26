// Store for HMCL-HarmonyOS global state
import { Account } from '../model/Account';
import { GameInstallation } from '../model/GameVersion';
import { LauncherConfig, DefaultConfig } from '../model/LauncherConfig';

export class AppStore {
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
    this.accounts.forEach(acc => { acc.selected = acc.uuid === uuid; });
    this.notifyAccountsChanged();
  }

  addAccount(account: Account): void {
    if (this.accounts.length === 0) {
      account.selected = true;
    }
    this.accounts.push(account);
    this.notifyAccountsChanged();
  }

  removeAccount(uuid: string): void {
    this.accounts = this.accounts.filter(acc => acc.uuid !== uuid);
    this.notifyAccountsChanged();
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
}