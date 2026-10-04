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
import {
  ModrinthClient, ModrinthSearchHit, ModrinthVersion, ModrinthFile, ModrinthCategory
} from '../../core/modplatform/ModrinthClient';
import { AppStore } from '../../core/AppStore';
import { HmclTheme } from '../../theme/HmclTheme';
import { FileUtils, Logger, StringUtils } from '../../core/util/Utils';
import { CurseForgeClient, CfCategory } from '../../core/modplatform/CurseForgeClient';
import { PreferencesManager } from '../../core/storage/PreferencesManager';
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
  /** 分页（对齐 HMCL：pageOffset 从 0 开始，pageSize=50） */
  @State modPage: number = 0;
  @State modPageCount: number = -1;
  @State modTotal: number = 0;
  @State modSort: string = ModrinthClient.SORT_RELEVANCE;

  /** 筛选条件（对应 HMCL 的 gameVersionField / categoryComboBox / 加载器） */
  @State filterVersion: string = '';
  @State filterCategory: string = '';
  @State filterLoader: string = '';
  @State tagLoading: boolean = false;

  /** 通用选择器弹层 */
  @State pickerVisible: boolean = false;
  @State pickerTitle: string = '';
  @State pickerKind: string = '';
  @State pickerValues: string[] = [];
  @State pickerLabels: string[] = [];
  @State categoryTags: ModrinthCategory[] = [];
  @State versionTags: string[] = [];
  @State loaderTags: string[] = [];
  /** CurseForge 用数字分类 id，与 pickerValues 对齐 */
  @State pickerCatIds: number[] = [];
  @State filterCategoryId: number = 0;
  @State cfCategories: CfCategory[] = [];

  /** 远端源：modrinth | curseforge */
  @State remoteSource: string = 'modrinth';
  @State cfKeyConfigured: boolean = false;
  @State keyInputVisible: boolean = false;
  @State keyInput: string = '';

  private prefs: PreferencesManager = PreferencesManager.getInstance();

  private versionManager = VersionManager.getInstance();
  private store = AppStore.getInstance();
  private token: CancelToken = new CancelToken();

  aboutToAppear(): void {
    this.loadInstalled();
    this.loadGameVersions();
    // 默认跟随当前实例的 MC 版本与加载器（HMCL 也是把已选实例的版本带进来）
    this.filterVersion = this.instanceMcVersion();
    this.filterLoader = this.instanceLoader();
    this.restoreRemoteSource();
  }

  /** 恢复上次选择的远端源与 CurseForge Key */
  private async restoreRemoteSource(): Promise<void> {
    try {
      const src = await this.prefs.getRemoteSource();
      this.remoteSource = src.length > 0 ? src : 'modrinth';
      const key = await this.prefs.getCurseForgeKey();
      if (key.length > 0) {
        CurseForgeClient.setApiKey(key);
        this.cfKeyConfigured = true;
      }
    } catch (e) {
      Logger.warn('DownloadPage', `恢复远端源失败: ${(e as Error).message}`);
    }
    Logger.info('DownloadPage', `远端源=${this.remoteSource} curseforgeKey=${this.cfKeyConfigured}`);
    this.searchMods('', 0);
    this.loadFilterTags();
  }

  private switchSource(src: string): void {
    if (this.remoteSource === src) {
      return;
    }
    this.remoteSource = src;
    this.filterCategory = '';
    this.filterCategoryId = 0;
    this.categoryTags = [];
    this.pickerCatIds = [];
    void this.prefs.setRemoteSource(src);
    this.searchMods(this.modQuery, 0);
    this.loadFilterTags();
  }

  private async saveCfKey(): Promise<void> {
    const key = this.keyInput.trim();
    await this.prefs.setCurseForgeKey(key);
    CurseForgeClient.setApiKey(key);
    this.cfKeyConfigured = key.length > 0;
    this.keyInputVisible = false;
    this.loadFilterTags();
    this.searchMods(this.modQuery, 0);
  }

  /** 拉取分类 / 游戏版本 / 加载器标签，供筛选下拉使用 */
  private async loadFilterTags(): Promise<void> {
    this.tagLoading = true;
    try {
      const categories = await ModrinthClient.getCategories(this.modProjectType());
      this.categoryTags = categories;
      const loaders = await ModrinthClient.getLoaders(this.modProjectType());
      this.loaderTags = loaders;
      if (this.versionTags.length === 0) {
        const versions = await ModrinthClient.getGameVersions();
        const list: string[] = [];
        for (const v of versions) {
          if (v.version_type === 'release') {
            list.push(v.version);
          }
        }
        this.versionTags = list;
      }
      Logger.info('DownloadPage',
        `筛选标签就绪：分类 ${categories.length} · 版本 ${this.versionTags.length} · 加载器 ${loaders.length}`);
    } catch (e) {
      Logger.warn('DownloadPage', `筛选标签拉取失败: ${(e as Error).message}`);
    }
    this.tagLoading = false;
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

  /**
   * 搜索远端资源（分页版）
   * @param page 页号，从 0 开始；只有「搜索/换排序/换 Tab」时才传 0
   */
  private async searchMods(query: string, page: number): Promise<void> {
    this.modLoading = true;
    this.modError = '';
    try {
      const mc = this.instanceMcVersion();
      let loader = this.instanceLoader();
      if (loader.length === 0) {
        loader = 'fabric';
      }
      // 只有模组需要按加载器过滤；资源包/光影只看游戏版本
      const projectType = this.modProjectType();
      // 筛选优先用工具栏里选的值；未选时回退到当前实例的 MC 版本 / 加载器
      const version = this.filterVersion.length > 0 ? this.filterVersion : mc;
      const loaderEff = this.filterLoader.length > 0 ? this.filterLoader : loader;

      const result = this.remoteSource === 'curseforge'
        ? await CurseForgeClient.search(query, projectType, version, loaderEff, page,
            CurseForgeClient.PAGE_SIZE, this.modSort, this.filterCategoryId)
        : await ModrinthClient.search(query, projectType, version, loaderEff, page,
            ModrinthClient.PAGE_SIZE, this.modSort, this.filterCategory);
      this.modHits = result.hits;
      this.modPage = result.offset;
      this.modPageCount = result.pageCount;
      this.modTotal = result.totalHits;
      const bits: string[] = [];
      if (version.length > 0) {
        bits.push(version);
      }
      if (projectType === 'mod' && loaderEff.length > 0) {
        bits.push(loaderEff);
      }
      if (this.filterCategory.length > 0) {
        bits.push('#' + this.filterCategory);
      }
      const filter = bits.length > 0 ? `（${bits.join(' · ')}）` : '';
      if (this.modHits.length === 0) {
        this.modError = `没有找到${this.tabTitle()}${filter}`;
      } else {
        this.modNote = `共 ${result.totalHits} 个结果${filter} · 第 ${result.offset + 1}/${result.pageCount} 页`;
      }
      Logger.info('DownloadPage',
        `${this.remoteSource === 'curseforge' ? 'CurseForge' : 'Modrinth'} 搜索 ${projectType} ` +
        `page=${result.offset} 命中 ${this.modHits.length}/${result.totalHits}`);
    } catch (e) {
      this.modError = '搜索失败：' + (e as Error).message;
      Logger.error('DownloadPage', this.modError);
    }
    this.modLoading = false;
  }

  private gotoPage(page: number): void {
    if (page < 0) {
      return;
    }
    if (this.modPageCount >= 0 && page >= this.modPageCount) {
      return;
    }
    this.searchMods(this.modQuery, page);
  }

  private changeSort(sort: string): void {
    this.modSort = sort;
    this.searchMods(this.modQuery, 0);
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
    const mc = this.filterVersion.length > 0 ? this.filterVersion : this.instanceMcVersion();
    const loaderEff = this.filterLoader.length > 0 ? this.filterLoader : this.instanceLoader();
    const versions = this.remoteSource === 'curseforge'
      ? await CurseForgeClient.getFiles(hit.project_id, mc, loaderEff, this.modProjectType())
      : await ModrinthClient.getVersions(hit.project_id, mc, loaderEff);
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

      if (this.pickerVisible) {
        this.PickerOverlay()
      }

      if (this.keyInputVisible) {
        this.KeyOverlay()
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

      Blank();

      // 下载源（对应 HMCL 的 downloadSourceComboBox）
      if (this.tab !== 'game') {
        this.SourceChip('Modrinth', 'modrinth');
        this.SourceChip('CurseForge', 'curseforge');
        if (this.remoteSource === 'curseforge') {
          // 镜像源（默认）不需要 key；这里只是可选的「改用官方源」入口
          Text(this.cfKeyConfigured ? '官方源' : '镜像源 · 免 Key')
            .fontSize(11)
            .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
            .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ left: 6 })
            .onClick(() => {
              this.keyInput = '';
              this.keyInputVisible = true;
            });
        }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }

  @Builder
  SourceChip(label: string, src: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.remoteSource === src ? HmclTheme.ON_PRIMARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
      .backgroundColor(this.remoteSource === src ? HmclTheme.PRIMARY_CONTAINER : HmclTheme.SURFACE_CONTAINER)
      .borderRadius(10)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ left: 6 })
      .onClick(() => {
        this.switchSource(src);
      })
  }

  @Builder
  KeyOverlay() {
    Column() {
      Text(this.cfKeyConfigured ? '改用官方 CurseForge 源' : '改用官方 CurseForge 源（可选）')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');
      Text('默认走 mcimirror 镜像，不需要任何 Key。' +
        '只有想直连官方 api.curseforge.com 时才需要填：官方强制每个应用自备 key' +
        '（去 console.curseforge.com 免费申请）。留空即回到镜像源。')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width('100%')
        .margin({ top: 8, bottom: 14 });

      TextInput({ placeholder: '粘贴 $2a$10$... 形式的 key', text: this.keyInput })
        .width('100%')
        .height(38)
        .fontSize(12)
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(8)
        .onChange((v: string) => {
          this.keyInput = v;
        });

      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .backgroundColor(HmclTheme.SURFACE_CONTAINER)
          .borderRadius(10)
          .onClick(() => {
            this.keyInputVisible = false;
          });
        Button('保存')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(10)
          .margin({ left: 10 })
          .onClick(() => {
            this.saveCfKey();
          });
      }
      .width('100%')
      .margin({ top: 16 });
    }
    .width(480)
    .padding(24)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
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
          this.searchMods(this.modQuery, 0);
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
        TextInput({
          placeholder: `在 ${this.remoteSource === 'curseforge' ? 'CurseForge' : 'Modrinth'} 搜索${this.tabTitle()}…`,
          text: this.modQuery
        })
          .onSubmit(() => {
            this.searchMods(this.modQuery, 0);
          })
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .backgroundColor(HmclTheme.SURFACE_CONTAINER)
          .borderRadius(8)
          .onChange((v: string) => {
            this.modQuery = v;
          });
        if (this.modQuery.length > 0) {
          Text('清空')
            .fontSize(12)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .onClick(() => {
              this.modQuery = '';
              this.searchMods('', 0);
            });
        }
        Text('搜索')
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(8)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .margin({ left: 8 })
          .onClick(() => {
            this.searchMods(this.modQuery, 0);
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })

      // 筛选栏（对应 HMCL 的 gameVersionField / categoryComboBox）
      Row() {
        this.FilterButton('版本', this.filterVersion.length > 0 ? this.filterVersion : '全部', 'version');
        this.FilterButton('分类', this.filterCategory.length > 0 ? this.filterCategory : '全部', 'category');
        if (this.modProjectType() === 'mod') {
          this.FilterButton('加载器', this.filterLoader.length > 0 ? this.filterLoader : '全部', 'loader');
        }
        Blank();
        if (this.tagLoading) {
          Text('加载筛选项…')
            .fontSize(11)
            .fontColor(HmclTheme.OUTLINE);
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 8 })

      // 排序（对应 HMCL 的 SortType）
      Row() {
        this.SortChip('相关性', ModrinthClient.SORT_RELEVANCE);
        this.SortChip('下载量', ModrinthClient.SORT_DOWNLOADS);
        this.SortChip('关注数', ModrinthClient.SORT_FOLLOWS);
        this.SortChip('最新发布', ModrinthClient.SORT_NEWEST);
        this.SortChip('最近更新', ModrinthClient.SORT_UPDATED);
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
        LoadingView({
          message: this.remoteSource === 'curseforge'
            ? '搜索 CurseForge 镜像（响应较大，首次可能要十几秒）…'
            : '搜索 Modrinth…'
        })
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

        // 分页（对应 HMCL DownloadListPage 的 上一页 / 第 N 页共 M 页 / 下一页）
        Row() {
          Text('上一页')
            .fontSize(13)
            .fontColor(this.modPage > 0 ? HmclTheme.PRIMARY : HmclTheme.OUTLINE)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.gotoPage(this.modPage - 1);
            });
          Blank();
          Text(this.pageLabel())
            .fontSize(12)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT);
          Blank();
          Text('下一页')
            .fontSize(13)
            .fontColor(this.canNext() ? HmclTheme.PRIMARY : HmclTheme.OUTLINE)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.gotoPage(this.modPage + 1);
            });
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 8 })
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  private canNext(): boolean {
    if (this.modPageCount <= 0) {
      return false;
    }
    return this.modPage < this.modPageCount - 1;
  }

  private pageLabel(): string {
    const total = this.modPageCount < 0 ? '-' : this.modPageCount.toString();
    return `第 ${this.modPage + 1} / ${total} 页 · 共 ${this.modTotal} 个`;
  }

  @Builder
  FilterButton(label: string, value: string, kind: string) {
    Row() {
      Text(`${label}：`)
        .fontSize(12)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
      Text(value)
        .fontSize(12)
        .fontColor(HmclTheme.PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(' ▾')
        .fontSize(10)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
    }
    .height(30)
    .constraintSize({ maxWidth: 260 })
    .padding({ left: 10, right: 10 })
    .margin({ right: 8 })
    .borderRadius(8)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER)
    .onClick(() => {
      this.openPicker(kind);
    })
  }

  /** 打开通用筛选选择器 */
  private openPicker(kind: string): void {
    const values: string[] = [];
    const labels: string[] = [];
    values.push('');
    labels.push('全部');
    const catIds: number[] = [0];
    if (kind === 'version') {
      this.pickerTitle = '选择游戏版本';
      for (const v of this.versionTags) {
        values.push(v);
        labels.push(v);
      }
    } else if (kind === 'category') {
      this.pickerTitle = '选择分类';
      if (this.remoteSource === 'curseforge') {
        for (const c of this.cfCategories) {
          values.push(c.name);
          labels.push(c.name);
          catIds.push(c.id);
        }
      } else {
        for (const c of this.categoryTags) {
          values.push(c.name);
          labels.push(`${c.name}（${c.header}）`);
          catIds.push(0);
        }
      }
    } else {
      this.pickerTitle = '选择加载器';
      for (const l of this.loaderTags) {
        values.push(l);
        labels.push(l);
      }
    }
    this.pickerKind = kind;
    this.pickerValues = values;
    this.pickerLabels = labels;
    this.pickerCatIds = catIds;
    this.pickerVisible = true;
  }

  private applyPick(value: string): void {
    if (this.pickerKind === 'version') {
      this.filterVersion = value;
    } else if (this.pickerKind === 'category') {
      this.filterCategory = value;
      const idx = this.pickerValues.indexOf(value);
      this.filterCategoryId = idx >= 0 && idx < this.pickerCatIds.length ? this.pickerCatIds[idx] : 0;
    } else {
      this.filterLoader = value;
    }
    this.pickerVisible = false;
    this.searchMods(this.modQuery, 0);
  }

  @Builder
  PickerOverlay() {
    Column() {
      Row() {
        Text(this.pickerTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE)
          .layoutWeight(1);
        Text('关闭')
          .fontSize(13)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.pickerVisible = false;
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 10 });

      List() {
        ForEach(this.pickerValues, (value: string, index: number) => {
          ListItem() {
            Row() {
              Text(this.pickerLabels[index])
                .fontSize(13)
                .fontColor(HmclTheme.ON_SURFACE)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1);
              if (this.currentPick() === value) {
                Text('✓')
                  .fontSize(13)
                  .fontColor(HmclTheme.PRIMARY);
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              this.applyPick(value);
            });
          }
        }, (value: string) => `${this.pickerKind}-${value}`)
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
    }
    .width('62%')
    .height('74%')
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  private currentPick(): string {
    if (this.pickerKind === 'version') {
      return this.filterVersion;
    }
    if (this.pickerKind === 'category') {
      return this.filterCategory;
    }
    return this.filterLoader;
  }

  @Builder
  SortChip(label: string, sort: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.modSort === sort ? HmclTheme.ON_SECONDARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
      .backgroundColor(this.modSort === sort ? HmclTheme.SECONDARY_CONTAINER : Color.Transparent)
      .borderRadius(12)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .margin({ right: 6 })
      .onClick(() => {
        this.changeSort(sort);
      })
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
