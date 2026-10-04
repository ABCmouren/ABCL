/**
 * Launcher configuration model for ABCL
 */

import { DownloadSource } from './GameVersion';

export enum ThemeMode {
  LIGHT = 'light',
  DARK = 'dark',
  SYSTEM = 'system'
}

export interface LauncherConfig {
  // Launcher settings
  theme: ThemeMode;
  language: string;
  downloadSource: DownloadSource;
  downloadThreads: number;

  // Java settings
  javaPath: string;
  minMemory: number;
  maxMemory: number;
  jvmArgs: string;
  defaultMinMemory: number;
  defaultMaxMemory: number;
  javaArgs: string;

  // Game settings
  gameDirectory: string;
  closeLauncherOnLaunch: boolean;
  showLog: boolean;
  showGameLog: boolean;
  /** 版本隔离策略，对齐 HMCL 的 DefaultIsolationType（默认 modded） */
  isolationType: string;

  // UI settings
  fontSize: number;
  showSidebar: boolean;
}

export const DefaultConfig: LauncherConfig = {
  theme: ThemeMode.SYSTEM,
  language: 'zh-CN',
  downloadSource: DownloadSource.BMCLAPI,
  downloadThreads: 4,
  javaPath: '',
  minMemory: 1024,
  maxMemory: 4096,
  jvmArgs: '',
  defaultMinMemory: 1024,
  defaultMaxMemory: 4096,
  javaArgs: '',
  gameDirectory: '',
  closeLauncherOnLaunch: false,
  showLog: false,
  showGameLog: false,
  isolationType: 'modded',
  fontSize: 14,
  showSidebar: true
};