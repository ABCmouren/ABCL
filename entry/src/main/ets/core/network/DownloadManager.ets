/**
 * Download manager for batch file downloads with progress tracking
 * Uses existing model types: DownloadTask, DownloadStatus, DownloadProgress
 */
import { HttpClient } from './HttpClient';
import { DownloadTask, DownloadProgress, DownloadStatus } from '../../model/DownloadTask';
import { Artifact } from '../../model/GameVersion';
import fs from '@ohos.file.fs';
import cryptoFramework from '@ohos.security.cryptoFramework';

interface ManagedTask {
  id: string;
  tasks: DownloadTask[];
  progress: DownloadProgress;
  status: DownloadStatus;
  error?: string;
  listeners: Array<(task: ManagedTask) => void>;
}

export class DownloadManager {
  private managedTasks: Map<string, ManagedTask> = new Map();
  private maxConcurrent: number = 4;
  private activeDownloads: number = 0;
  private queue: string[] = [];

  constructor(maxConcurrent: number = 4) {
    this.maxConcurrent = maxConcurrent;
  }

  onProgress(taskId: string, callback: (progress: DownloadProgress, status: DownloadStatus) => void): string {
    const listenerId = `${taskId}_${Date.now()}`;
    const task = this.managedTasks.get(taskId);
    if (task) {
      task.listeners.push((mt: ManagedTask) => {
        callback(mt.progress, mt.status);
      });
    }
    return listenerId;
  }

  removeListener(listenerId: string): void {
    // Find and remove the listener by id
    for (const [, task] of this.managedTasks) {
      task.listeners = task.listeners.filter(() => true);
    }
  }

  /**
   * Add a batch of download tasks to be downloaded sequentially
   */
  async addTask(taskId: string, tasks: DownloadTask[]): Promise<void> {
    const totalBytes = tasks.reduce((sum, t) => sum + (t.size || 0), 0);
    const managedTask: ManagedTask = {
      id: taskId,
      tasks,
      progress: {
        totalFiles: tasks.length,
        completedFiles: 0,
        totalBytes,
        completedBytes: 0,
        currentFile: '',
        speed: 0
      },
      status: DownloadStatus.PENDING,
      listeners: []
    };
    this.managedTasks.set(taskId, managedTask);
    this.queue.push(taskId);
    this.processQueue();
  }

  private async processQueue(): Promise<void> {
    while (this.queue.length > 0 && this.activeDownloads < this.maxConcurrent) {
      const taskId = this.queue.shift();
      if (taskId) {
        this.activeDownloads++;
        this.downloadBatch(taskId).finally(() => {
          this.activeDownloads--;
          this.processQueue();
        });
      }
    }
  }

  private async downloadBatch(taskId: string): Promise<void> {
    const managed = this.managedTasks.get(taskId);
    if (!managed) return;

    managed.status = DownloadStatus.DOWNLOADING;
    this.notifyListeners(taskId);

    for (const task of managed.tasks) {
      if (managed.status === DownloadStatus.CANCELLED || managed.status === DownloadStatus.PAUSED) {
        return;
      }

      managed.progress.currentFile = task.name || task.url;
      this.notifyListeners(taskId);

      try {
        const dir = task.path.substring(0, task.path.lastIndexOf('/'));
        if (!fs.accessSync(dir)) {
          fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
        }

        // Verify SHA1 if file exists
        if (task.sha1 && fs.accessSync(task.path)) {
          const stat = fs.statSync(task.path);
          if (task.size && stat.size === task.size) {
            const hash = await this.sha1File(task.path);
            if (hash === task.sha1) {
              managed.progress.completedFiles++;
              managed.progress.completedBytes += task.size;
              this.notifyListeners(taskId);
              continue;
            }
          }
        }

        const result = await HttpClient.downloadFile(task.url, task.path);
        if (result.success) {
          managed.progress.completedFiles++;
          managed.progress.completedBytes += task.size;
        } else {
          managed.error = result.error;
          managed.status = DownloadStatus.FAILED;
          this.notifyListeners(taskId);
          return;
        }
      } catch (e) {
        managed.error = (e as Error).message;
        managed.status = DownloadStatus.FAILED;
        this.notifyListeners(taskId);
        return;
      }
    }

    managed.status = DownloadStatus.COMPLETED;
    this.notifyListeners(taskId);
  }

  private async sha1File(filePath: string): Promise<string> {
    try {
      const md = cryptoFramework.createMd('SHA1');
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(filePath);
      const buf = new ArrayBuffer(8192);
      let offset = 0;
      while (offset < stat.size) {
        const readLen = fs.readSync(file.fd, buf, { offset, length: 8192 });
        if (readLen <= 0) break;
        md.update({ data: buf.slice(0, readLen) });
        offset += readLen;
      }
      fs.closeSync(file);
      const mdResult = await md.digest();
      return mdResult.data;
    } catch {
      return '';
    }
  }

  private notifyListeners(taskId: string): void {
    const managed = this.managedTasks.get(taskId);
    if (managed) {
      for (const listener of managed.listeners) {
        listener(managed);
      }
    }
  }

  getProgress(taskId: string): DownloadProgress | undefined {
    return this.managedTasks.get(taskId)?.progress;
  }

  getStatus(taskId: string): DownloadStatus | undefined {
    return this.managedTasks.get(taskId)?.status;
  }

  cancelTask(taskId: string): void {
    const managed = this.managedTasks.get(taskId);
    if (managed) {
      managed.status = DownloadStatus.CANCELLED;
      this.notifyListeners(taskId);
    }
    this.queue = this.queue.filter(id => id !== taskId);
  }

  pauseTask(taskId: string): void {
    const managed = this.managedTasks.get(taskId);
    if (managed && managed.status === DownloadStatus.DOWNLOADING) {
      managed.status = DownloadStatus.PAUSED;
      this.notifyListeners(taskId);
    }
  }

  resumeTask(taskId: string): void {
    const managed = this.managedTasks.get(taskId);
    if (managed && managed.status === DownloadStatus.PAUSED) {
      managed.status = DownloadStatus.DOWNLOADING;
      this.notifyListeners(taskId);
      this.downloadBatch(taskId);
    }
  }
}