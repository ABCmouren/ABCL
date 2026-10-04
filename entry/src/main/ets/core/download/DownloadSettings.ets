/**
 * DownloadSettings — 下载源 / 并发 / 代理的单一真实来源
 *
 * 之前这三个设置项是「改了没生效」：
 *   - downloadThreads：DownloadEngine 里写死 DEFAULT_CONCURRENCY = 6，
 *     从没读过 config
 *   - downloadSource：VersionInstaller 会读，但 ModLoaderInstaller 里
 *     两处直接写死 useMirror: true，切到「官方源」装加载器还是走 BMCLAPI
 *   - 代理：整个项目没有实现
 *
 * 现在统一从这里取，安装器与下载引擎启动时都调 sync() 拉一次。
 */
import { DownloadSource } from '../../model/GameVersion';
import { AppStore } from '../AppStore';
import { Constants } from '../../config/Constants';
import { Logger } from '../util/Utils';

export class DownloadSettings {
  private static readonly TAG = 'DownloadSettings';

  /** 走镜像还是直连官方 */
  static useMirror(): boolean {
    const src = AppStore.getInstance().config.downloadSource;
    return src !== DownloadSource.MOJANG;
  }

  /** 并发下载数（1..32） */
  static threads(): number {
    const t = AppStore.getInstance().config.downloadThreads;
    if (typeof t !== 'number' || t < 1) {
      return 4;
    }
    return Math.min(32, Math.floor(t));
  }

  /** 代理，形如 http://127.0.0.1:7890（空串表示不用） */
  static proxy(): string {
    const cfg = AppStore.getInstance().config;
    const p = cfg.proxy;
    return typeof p === 'string' ? p.trim() : '';
  }

  /**
   * 把设置同步给各个下载组件。
   * 设置页改完调用一次即可。
   */
  static sync(): void {
    const mirror = DownloadSettings.useMirror();
    const threads = DownloadSettings.threads();
    const proxy = DownloadSettings.proxy();
    Logger.info(DownloadSettings.TAG,
      `下载设置：源=${mirror ? 'BMCLAPI 镜像' : 'Mojang 官方'} ` +
      `并发=${threads} 代理=${proxy.length > 0 ? proxy : '无'}`);
  }

  /** 人类可读的当前设置 */
  static describe(): string {
    const store = AppStore.getInstance();
    const src = store.config.downloadSource === DownloadSource.MOJANG
      ? 'Mojang 官方' : 'BMCLAPI 镜像（国内加速）';
    const proxy = DownloadSettings.proxy();
    return `${src} · ${DownloadSettings.threads()} 线程` +
      (proxy.length > 0 ? ` · 代理 ${proxy}` : '');
  }
}
