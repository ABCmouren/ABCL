/**
 * Minecraft version models for ABCL
 */

export interface VersionManifestLatest {
  release: string;
  snapshot: string;
}

export interface VersionManifest {
  latest: VersionManifestLatest;
  versions: VersionInfo[];
}

export interface VersionInfo {
  id: string;
  type: string;
  url: string;
  time: string;
  releaseTime: string;
}

export interface GameInstallation {
  versionId: string;
  name: string;
  directory: string;
  gameVersion: string;
  loaderType: LoaderType | null;
  loaderVersion: string | null;
  installed: boolean;
  installTime: number;
  lastPlayed: number;
  javaArgs: string;
  minMemory: number;
  maxMemory: number;
  width: number;
  height: number;
  fullscreen: boolean;
  customJvmArgs: string;
  customGameArgs: string;
}

export enum LoaderType {
  VANILLA = 'vanilla',
  FORGE = 'forge',
  FABRIC = 'fabric',
  QUILT = 'quilt',
  NEO_FORGE = 'neoforge',
  NONE = 'none'
}

export interface GameArguments {
  game: (string | GameArgumentRule)[];
  jvm: (string | GameArgumentRule)[];
}

export interface GameArgumentRule {
  rules: Rule[];
  value: string | string[];
}

export interface AssetIndex {
  id: string;
  sha1: string;
  size: number;
  totalSize: number;
  url: string;
}

export interface GameDownloads {
  client: Artifact;
  client_mappings?: Artifact;
  server?: Artifact;
  server_mappings?: Artifact;
}

export interface GameLoggingFile {
  id: string;
  sha1: string;
  size: number;
  url: string;
}

export interface GameLoggingClient {
  argument: string;
  file: GameLoggingFile;
  type: string;
}

export interface GameLogging {
  client: GameLoggingClient;
}

export interface GameVersionJson {
  id: string;
  type: string;
  time: string;
  releaseTime: string;
  minecraftArguments?: string;
  arguments?: GameArguments;
  mainClass: string;
  inheritsFrom?: string;
  jar?: string;
  minimumLauncherVersion: number;
  assets: string;
  assetIndex: AssetIndex;
  downloads: GameDownloads;
  libraries: Library[];
  logging?: GameLogging;
  complianceLevel?: number;
}

export interface Artifact {
  path?: string;
  sha1: string;
  size: number;
  url: string;
}

export interface LibraryDownloads {
  artifact: Artifact;
  classifiers?: Record<string, Artifact>;
}

export interface LibraryExtract {
  exclude: string[];
}

export interface Library {
  name: string;
  downloads: LibraryDownloads;
  rules?: Rule[];
  natives?: Record<string, string>;
  extract?: LibraryExtract;
}

export interface RuleOs {
  name: string;
  version?: string;
  arch?: string;
}

export interface Rule {
  action: string;
  os?: RuleOs;
  features?: Record<string, boolean>;
}

export interface DownloadTask {
  url: string;
  sha1: string;
  size: number;
  path: string;
  name: string;
  source: DownloadSource;
}

export interface DownloadProgress {
  totalFiles: number;
  completedFiles: number;
  totalBytes: number;
  completedBytes: number;
  currentFile: string;
  speed: number; // bytes per second
}

export enum DownloadSource {
  MOJANG = 'mojang',
  BMCLAPI = 'bmclapi',
  MCBBS = 'mcbbs'
}

export interface LaunchResult {
  success: boolean;
  process?: object;
  exitCode?: number;
  error?: string;
  log?: string[];
}