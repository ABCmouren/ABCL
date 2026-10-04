/**
 * DownloadPage — 下载中心（2026-10 重写）
 *
 * 原实现的问题：
 *   1. ForEach 直接吃 `get filteredVersions()` 这个访问器 —— ArkUI V1 对访问器返回的
 *      数组不做可靠依赖追踪，首帧 isLoading=true 时根本没读过 this.versions，
 *      于是 fetch 完成后界面不会重绘，列表永远是空的（这就是「下载列表又空了」）；
 *   2. 安装调用的是旧签名的 installVersion，没有进度、没有取消、没有失败提示。
 *
 * 现在：显式维护派生数组（applyFilter()）+ 真实进度/取消 + 已安装标记，
 * 并接上 Modrinth 真实搜索与安装。
 */
import { GameInstallation, LoaderType, VersionInfo } from '../../model/GameVersion';
import { VersionManager } from '../../core/game/VersionManager';
import { VersionInstaller } from '../../core/game/VersionInstaller';
import { CancelToken } from '../../core/download/DownloadEngine';
import { ModManager } from '../../core/game/ModManager';
import { PackKind, ResourcePackManager } from '../../core/game/ResourcePackManager';
import { ModrinthClient, ModrinthSearchHit, ModrinthVersion, ModrinthFile } from '../../core/modplatform/ModrinthClient';
import { AppStore } from '../../core/AppStore';
import { HmclTheme } from '../../theme/HmclTheme';
import { FileUtils, Logger, StringUtils } from '../../core/util/Utils';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';
import { HttpClient } from '../../core/network/HttpClient';

@Component
export default struct DownloadPage {
  @State tab: string = 'game';

  // ---- 游戏 ----
  @State allVersions: VersionInfo[] = [];
  @State visibleVersions: VersionInfo[] = [];
  @State filterType: string = 'release';
  @State searchText: string = '';
  @State loadingGame: boolean = false;
  @State gameError: string = '';
  @State installedIds: string[] = [];

  // ---- 安装进度 ----
  @State installing: boolean = false;
  @State installTitle: string = '';
  @State installDetail: string = '';
  @State installPercent: number = 0;

  // ---- 模组（Modrinth）----
  @State modHits: ModrinthSearchHit[] = [];
  @State modQuery: string = '';
  @State modLoading: boolean = false;
  @State modError: string = '';
  @State modPick: ModrinthSearchHit | null = null;
  @State modVersions: ModrinthVersion[] = [];
  @State modVersionsLoading: boolean = false;
  @State modNote: string = '';

  private versionManager = VersionManager.getInstance();
  private store = AppStore.getInstance();
  private token: CancelToken = new CancelToken();

  aboutToAppear(): void {
    this.loadInstalled();
    this.loadGameVersions();
    this.searchMods('');
  }

  // ============================================================
  //  数据
  // ============================================================
  private loadInstalled(): void {
    const list: string[] = [];
    for (const inst of this.versionManager.getLocalVersions()) {
      list.push(inst.versionId);
    }
    this.installedIds = list;
  }

  private async loadGameVersions(): Promise<void> {
    this.loadingGame = true;
    this.gameError = '';
    try {
      // 复用 VersionInstaller.fetchManifest —— 它与「安装新游戏」走同一条已验证可用的路径
      const manifest = await VersionInstaller.fetchManifest(true);
      this.allVersions = manifest.versions ? manifest.versions : [];
      this.applyFilter();
      Logger.info('DownloadPage', `版本清单加载完成：${this.allVersions.length} 个`);
    } catch (e) {
      this.gameError = `版本清单获取失败：${(e as Error).message}`;
      Logger.error('DownloadPage', this.gameError);
    }
    this.loadingGame = false;
  }

  /** 显式维护派生数组（不要用访问器给 ForEach） */
  private applyFilter(): void {
    let result: VersionInfo[] = [];
    for (const v of this.allVersions) {
      if (this.filterType !== 'all' && v.type !== this.filterType) {
        continue;
      }
      if (this.searchText.length > 0 && v.id.toLowerCase().indexOf(this.searchText.toLowerCase()) < 0) {
        continue;
      }
      result.push(v);
    }
    this.visibleVersions = result;
  }

  private selectedInstance(): GameInstallation | null {
    if (this.store.selectedInstallation !== null) {
      return this.store.selectedInstallation;
    }
    const list = this.versionManager.getLocalVersions();
    return list.length > 0 ? list[0] : null;
  }

  private instanceMcVersion(): string {
    const inst = this.selectedInstance();
    if (!inst) {
      return '';
    }
    return inst.gameVersion && inst.gameVersion.length > 0 ? inst.gameVersion : inst.versionId;
  }

  private instanceLoader(): string {
    const inst = this.selectedInstance();
    if (!inst || !inst.loaderType) {
      return '';
    }
    const t = inst.loaderType;
    if (t === LoaderType.FABRIC) {
      return 'fabric';
    }
    if (t === LoaderType.QUILT) {
      return 'quilt';
    }
    if (t === LoaderType.NEO_FORGE) {
      return 'neoforge';
    }
    if (t === LoaderType.FORGE) {
      return 'forge';
    }
    return '';
  }

  private async searchMods(query: string): Promise<void> {
    this.modLoading = true;
    this.modError = '';
    this.modNote = '';
    try {
      const mc = this.instanceMcVersion();
      let loader = this.instanceLoader();
      if (loader.length === 0) {
        loader = 'fabric';
      }
      // 只有模组需要按加载器过滤；资源包/光影只看游戏版本
      const projectType = this.modProjectType();
      const hits = await ModrinthClient.search(query, projectType, mc, loader, 0, 20);
      this.modHits = hits;
      if (hits.length === 0) {
        this.modError = mc.length > 0
          ? `没有找到适配 ${mc} / ${loader} 的模组`
          : '没有找到模组';
      } else {
        this.modNote = mc.length > 0
          ? `按 ${mc} · ${loader} 过滤，共 ${hits.length} 条`
          : `共 ${hits.length} 条`;
      }
    } catch (e) {
      this.modError = 'Modrinth 搜索失败：' + (e as Error).message;
      Logger.error('DownloadPage', this.modError);
    }
    this.modLoading = false;
  }

  // ============================================================
  //  安装原版
  // ============================================================
  private startInstall(versionId: string): void {
    this.installing = true;
    this.installPercent = 0;
    this.installTitle = `安装 ${versionId}`;
    this.installDetail = '准备中…';
    this.token = new CancelToken();

    this.versionManager.installVersion(versionId, (p) => {
      this.installPercent = Math.round(p.progress * 100);
      this.installDetail = `${p.phase} · ${p.message}`;
    }, this.token).then(() => {
      this.installing = false;
      this.loadInstalled();
    }).catch((e: Error) => {
      this.installing = false;
      this.installDetail = '失败：' + e.message;
      Logger.error('DownloadPage', `安装 ${versionId} 失败: ${e.message}`);
    });
  }

  // ============================================================
  //  安装模组
  // ============================================================
  /** 当前 Tab 对应的 Modrinth project_type */
  private modProjectType(): string {
    if (this.tab === 'resourcepack' || this.tab === 'shader' || this.tab === 'modpack') {
      return this.tab;
    }
    return 'mod';
  }

  private tabTitle(): string {
    if (this.tab === 'mod') {
      return '模组';
    }
    if (this.tab === 'resourcepack') {
      return '资源包';
    }
    if (this.tab === 'shader') {
      return '光影';
    }
    if (this.tab === 'modpack') {
      return '整合包';
    }
    return '游戏';
  }

  private async openModVersions(hit: ModrinthSearchHit): Promise<void> {
    this.modPick = hit;
    this.modVersions = [];
    this.modVersionsLoading = true;
    const versions = await ModrinthClient.getVersions(hit.project_id, this.instanceMcVersion(), this.instanceLoader());
    this.modVersions = versions;
    this.modVersionsLoading = false;
  }

  private async installMod(file: ModrinthFile): Promise<void> {
    const mcDir = this.versionManager.getMinecraftDir();
    const tmp = `${mcDir}/.download-tmp/${file.filename}`;
    this.modNote = `下载 ${file.filename} …`;
    const sha1 = file.hashes && file.hashes.sha1 ? file.hashes.sha1 : '';
    const outcome = await HttpClient.downloadToFile(file.url, tmp, file.size, undefined, true);
    if (!outcome.success) {
      this.modNote = '下载失败：' + outcome.error;
      return;
    }
    if (sha1.length > 0) {
      const actual = await FileUtils.sha1File(tmp);
      if (actual.toLowerCase() !== sha1.toLowerCase()) {
        this.modNote = `SHA-1 校验失败（期望 ${sha1} 实际 ${actual}）`;
        FileUtils.delete(tmp);
        return;
      }
    }
    let target = '';
    if (this.tab === 'resourcepack') {
      target = ResourcePackManager.installFile(mcDir, PackKind.RESOURCE, tmp, file.filename);
    } else if (this.tab === 'shader') {
      target = ResourcePackManager.installFile(mcDir, PackKind.SHADER, tmp, file.filename);
    } else if (this.tab === 'modpack') {
      // 整合包需要解包 + 建实例，属于 P0-4，这里先只落盘到 modpacks 暂存目录
      FileUtils.mkdirs(`${mcDir}/modpacks`);
      target = `${mcDir}/modpacks/${file.filename}`;
      FileUtils.copyFile(tmp, target);
      FileUtils.delete(tmp);
    } else {
      target = ModManager.installJar(mcDir, tmp, file.filename);
    }
    this.modNote = `已安装到 ${target}`;
    this.modPick = null;
    this.modVersions = [];
  }

  // ============================================================
  //  UI
  // ============================================================
  build() {
    Stack() {
      Column() {
        this.TabBar()

        if (this.tab === 'game') {
          this.GameTab()
        } else {
          this.ModTab()
        }

        if (this.installing) {
          this.InstallPanel()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(HmclTheme.SURFACE)

      if (this.modPick !== null) {
        this.ModVersionOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ModVersionOverlay() {
    Column() {
      Row() {
        Text(this.modPick ? this.modPick.title : '')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text('关闭')
          .fontSize(13)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.modPick = null;
            this.modVersions = [];
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 10 });

      Text(this.instanceContextLabel())
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .padding({ left: 20, bottom: 8 });

      if (this.modVersionsLoading) {
        LoadingView({ message: '拉取可用版本…' })
      } else if (this.modVersions.length === 0) {
        Column() {
          Text('没有适配当前实例的版本')
            .fontSize(13)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT);
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.modVersions, (ver: ModrinthVersion) => {
            ListItem() {
              Row() {
                Column() {
                  Text(ver.name ? ver.name : ver.version_number)
                    .fontSize(13)
                    .fontColor(HmclTheme.ON_SURFACE)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%');
                  Text(`${ver.version_number} · ${ver.loaders.join('/')} · ${ver.date_published ? ver.date_published.substring(0, 10) : ''}`)
                    .fontSize(10)
                    .fontColor(HmclTheme.OUTLINE)
                    .width('100%')
                    .margin({ top: 3 });
                }
                .layoutWeight(1);

                Text('安装')
                  .fontSize(12)
                  .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
                  .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
                  .borderRadius(8)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .onClick(() => {
                    const f = ModrinthClient.primaryFile(ver);
                    if (f !== null) {
                      this.installMod(f);
                    } else {
                      this.modNote = '该版本没有可下载文件';
                    }
                  });
              }
              .width('100%')
              .height(56)
              .padding({ left: 20, right: 20 });
            }
          }, (ver: ModrinthVersion) => ver.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
      }
    }
    .width('72%')
    .height('76%')
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  private instanceContextLabel(): string {
    const inst = this.selectedInstance();
    if (!inst) {
      return '当前没有实例，将不做版本过滤';
    }
    return `目标实例：${inst.name}（${this.instanceMcVersion()} · ${this.instanceLoader()}）`;
  }

  @Builder
  TabBar() {
    Row() {
      this.TabChip('游戏', 'game');
      this.TabChip('模组', 'mod');
      this.TabChip('资源包', 'resourcepack');
      this.TabChip('光影', 'shader');
      this.TabChip('整合包', 'modpack');
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }

  @Builder
  TabChip(label: string, key: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.tab === key ? HmclTheme.ON_PRIMARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
      .backgroundColor(this.tab === key ? HmclTheme.PRIMARY_CONTAINER : HmclTheme.SURFACE_CONTAINER)
      .borderRadius(14)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .margin({ right: 8 })
      .onClick(() => {
        this.tab = key;
        if (key === 'mod' || key === 'resourcepack' || key === 'shader' || key === 'modpack') {
          this.searchMods(this.modQuery);
        }
      })
  }

  // ------------------------------------------------------------
  //  游戏
  // ------------------------------------------------------------
  @Builder
  GameTab() {
    Column() {
      Row() {
        TextInput({ placeholder: '搜索版本…', text: this.searchText })
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(HmclTheme.SURFACE_CONTAINER)
          .borderRadius(8)
          .onChange((v: string) => {
            this.searchText = v;
            this.applyFilter();
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })

      Row() {
        this.FilterChip('正式版', 'release');
        this.FilterChip('快照', 'snapshot');
        this.FilterChip('旧版', 'old_beta');
        this.FilterChip('全部', 'all');
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })

      if (this.loadingGame) {
        LoadingView({ message: '拉取版本清单…' })
      } else if (this.gameError.length > 0) {
        Column() {
          Text(this.gameError)
            .fontSize(13)
            .fontColor(HmclTheme.ERROR);
          Text('点击重试')
            .fontSize(13)
            .fontColor(HmclTheme.PRIMARY)
            .margin({ top: 10 })
            .onClick(() => {
              this.loadGameVersions();
            });
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center);
      } else {
        Text(`${this.visibleVersions.length} 个版本`)
          .fontSize(11)
          .fontColor(HmclTheme.OUTLINE)
          .width('100%')
          .padding({ left: 20, bottom: 6 });
        List() {
          ForEach(this.visibleVersions, (v: VersionInfo) => {
            ListItem() {
              this.VersionRow(v)
            }
          }, (v: VersionInfo) => v.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  FilterChip(label: string, key: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.filterType === key ? HmclTheme.ON_SECONDARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
      .backgroundColor(this.filterType === key ? HmclTheme.SECONDARY_CONTAINER : Color.Transparent)
      .borderRadius(12)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .margin({ right: 6 })
      .onClick(() => {
        this.filterType = key;
        this.applyFilter();
      })
  }

  private isInstalled(id: string): boolean {
    return this.installedIds.indexOf(id) >= 0;
  }

  @Builder
  VersionRow(v: VersionInfo) {
    Row() {
      Column() {
        Row() {
          Text(v.id)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(HmclTheme.ON_SURFACE);
          if (this.isInstalled(v.id)) {
            Text('已安装')
              .fontSize(10)
              .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
              .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ left: 8 });
          }
        }
        .width('100%');
        Text(`${v.type} · ${v.releaseTime ? v.releaseTime.substring(0, 10) : ''}`)
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .width('100%')
          .margin({ top: 3 });
      }
      .layoutWeight(1);

      if (this.installing && this.installTitle.indexOf(v.id) >= 0) {
        LoadingProgress().width(18).height(18).color(HmclTheme.PRIMARY_CONTAINER);
      } else {
        Text(this.isInstalled(v.id) ? '重新安装' : '安装')
          .fontSize(12)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(8)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .onClick(() => {
            if (!this.installing) {
              this.startInstall(v.id);
            }
          });
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
  }

  // ------------------------------------------------------------
  //  模组
  // ------------------------------------------------------------
  @Builder
  ModTab() {
    Column() {
      Row() {
        TextInput({ placeholder: `在 Modrinth 搜索${this.tabTitle()}…`, text: this.modQuery })
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(HmclTheme.SURFACE_CONTAINER)
          .borderRadius(8)
          .onChange((v: string) => {
            this.modQuery = v;
          });
        Text('搜索')
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(8)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ left: 8 })
          .onClick(() => {
            this.searchMods(this.modQuery);
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })

      if (this.modNote.length > 0) {
        Text(this.modNote)
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 6 });
      }
      if (this.modError.length > 0) {
        Text(this.modError)
          .fontSize(11)
          .fontColor(HmclTheme.ERROR)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 6 });
      }

      if (this.modLoading) {
        LoadingView({ message: '搜索 Modrinth…' })
      } else if (this.modHits.length === 0) {
        EmptyView({ icon: '', message: '没有结果', actionText: '' })
      } else {
        List() {
          ForEach(this.modHits, (hit: ModrinthSearchHit) => {
            ListItem() {
              this.ModHitRow(hit)
            }
          }, (hit: ModrinthSearchHit) => hit.project_id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  ModHitRow(hit: ModrinthSearchHit) {
    Row() {
      Column() {
        Text(hit.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
        Text(hit.description)
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 3 });
        Text(`${hit.author} · ${StringUtils.formatCount(hit.downloads)} 次下载`)
          .fontSize(10)
          .fontColor(HmclTheme.OUTLINE)
          .width('100%')
          .margin({ top: 3 });
      }
      .layoutWeight(1);

      Text('选择版本')
        .fontSize(12)
        .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
        .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
        .borderRadius(8)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          this.openModVersions(hit);
        });
    }
    .width('100%')
    .height(72)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  InstallPanel() {
    Column() {
      Row() {
        Text(this.installTitle)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE)
          .layoutWeight(1);
        Text('取消')
          .fontSize(12)
          .fontColor(HmclTheme.ERROR)
          .onClick(() => {
            this.token.cancel();
          });
      }
      .width('100%');

      Progress({ value: this.installPercent, total: 100, type: ProgressType.Linear })
        .width('100%')
        .margin({ top: 10 })
        .color(HmclTheme.PRIMARY_CONTAINER);

      Text(`${this.installPercent}%  ${this.installDetail}`)
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 });
    }
    .width('100%')
    .padding(16)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER)
    .border({ width: { top: 1 }, color: HmclTheme.OUTLINE_VARIANT })
  }
}
