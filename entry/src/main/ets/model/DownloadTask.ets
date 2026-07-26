/**
 * Download task model for HMCL-HarmonyOS
 * Re-exports types from GameVersion for convenience
 */
export { DownloadTask, DownloadProgress, DownloadSource } from './GameVersion';

export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export interface DownloadQueue {
  tasks: DownloadTask[];
  totalProgress: number;
  status: DownloadStatus;
}