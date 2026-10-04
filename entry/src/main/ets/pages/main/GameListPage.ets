/**
 * GameListPage — HMCL 主页面（实例列表 + 详情 + 启动栏）
 *
 * 对齐 HMCL：
 *  - ui/instances/GameListCell.java  列表行：32px 图标 + 两行文本 + 右侧启动/管理按钮
 *  - ui/main/MainPage.java           右下角 launch-pane（大号"启动游戏" + 菜单按钮）
 *  - assets/css/root.css             .md-list-cell / .card / .launch-pane 的尺寸与配色
 */
import { GameInstallation, LoaderType, VersionInfo, VersionManifest } from '../../model/GameVersion';
import { AppStore } from '../../core/AppStore';
import { VersionManager } from '../../core/game/VersionManager';
import { VersionInstaller } from '../../core/game/VersionInstaller';
import { ModLoaderInstaller, ModLoader, LoaderVersion } from '../../core/game/ModLoaderInstaller';
import { LaunchEngine } from '../../core/launch/LaunchEngine';
import { Account } from '../../model/Account';
import { Logger, StringUtils } from '../../core/util/Utils';
import { HmclTheme } from '../../theme/HmclTheme';
import { LoadingView } from '../../components/common/CommonComponents';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import { BusinessError } from '@ohos.base';

interface PendingAccountData {
  username: string;
  uuid: string;
  accessToken: string;
  refreshToken?: string;
  userProperties: string;
}

interface PendingLaunchConfig {
  versionId: string;
  name: string;
  gameVersion: string;
  loaderType: LoaderType | null;
  minMemory: number;
  maxMemory: number;
  directory: string;
  width: number;
  height: number;
  fullscreen: boolean;
  customJvmArgs: string;
  account: PendingAccountData;
}

@Component
export default struct GameListPage {
  @State installations: GameInstallation[] = [];
  @State selectedIndex: number = -1;
  @State isLoading: boolean = true;
  @State selectedAccount: Account | null = null;
  @State message: string = '';

  // 安装面板
  @State showInstall: boolean = false;
  @State manifestVersions: VersionInfo[] = [];
  @State manifestLoading: boolean = false;
  @State installing: boolean = false;
  @State installTitle: string = '';
  @State installProgress: number = 0;
  @State installDetail: string = '';

  // 实例操作菜单
  @State menuVisible: boolean = false;
  @State menuInstance: GameInstallation | null = null;

  // 加载器安装面板
  @State pickMode: string = 'mc';
  @State loaderVersions: LoaderVersion[] = [];
  @State loaderLoading: boolean = false;
  @State loaderTarget: GameInstallation | null = null;

  private loaderInstaller = ModLoaderInstaller.getInstance();

  private versionManager = new VersionManager();
  private launchEngine = LaunchEngine.getInstance();
  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.loadGames();
  }

  loadGames(): void {
    this.isLoading = true;
    try {
      this.installations = this.versionManager.getLocalVersions();
      this.selectedAccount = this.store.getSelectedAccount();
      if (this.selectedIndex < 0 && this.installations.length > 0) {
        this.selectedIndex = 0;
      }
    } catch (e) {
      Logger.error('GameListPage', '读取本地版本失败: ' + (e as Error).message);
    }
    this.isLoading = false;
  }

  // ============================================================
  //  布局
  // ============================================================
  build() {
    Stack() {
      Row() {
        this.InstanceList()
        this.DetailPane()
      }
      .width('100%')
      .height('100%')

      if (this.showInstall) {
        this.InstallOverlay()
      }

      if (this.menuVisible) {
        this.RowMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HmclTheme.SURFACE)
  }

  @Builder
  InstanceList() {
    Column() {
      Row() {
        Text('实例列表')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Blank();
        Text('刷新')
          .fontSize(12)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.loadGames();
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 });

      if (this.isLoading) {
        LoadingView({ message: '读取实例…' });
      } else if (this.installations.length === 0) {
        Column() {
          Text('还没有已安装的实例')
            .fontSize(14)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT);
          Text('点下面的「安装新游戏」下载一个 Minecraft 版本')
            .fontSize(12)
            .fontColor(HmclTheme.OUTLINE)
            .margin({ top: 8 })
            .textAlign(TextAlign.Center);
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(20);
      } else {
        List() {
          ForEach(this.installations, (inst: GameInstallation, index: number) => {
            ListItem() {
              this.InstanceCell(inst, index)
            }
          }, (inst: GameInstallation) => inst.versionId)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 56, endMargin: 0 })
        .scrollBar(BarState.Auto);
      }

      Button('安装新游戏')
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
        .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
        .borderRadius(HmclTheme.CARD_RADIUS)
        .margin({ top: 10, left: 12, right: 12, bottom: 12 })
        .onClick(() => {
          this.openInstallPanel();
        });
    }
    .width(360)
    .height('100%')
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOW)
    .border({ width: { right: 1 }, color: HmclTheme.OUTLINE_VARIANT });
  }

  /** 对应 HMCL GameListCell：md-list-cell，选中态 secondary-container */
  @Builder
  InstanceCell(inst: GameInstallation, index: number) {
    Row() {
      // 图标（HMCL 用 32px grass 方块）
      Stack() {
        Text(inst.loaderType ? 'M' : 'M')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER);
      }
      .width(HmclTheme.LIST_ICON_SIZE)
      .height(HmclTheme.LIST_ICON_SIZE)
      .borderRadius(8)
      .backgroundColor(this.iconColor(inst));

      Column() {
        Text(inst.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
        Text(this.subtitleOf(inst))
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 });
      }
      .layoutWeight(1)
      .margin({ left: 10 });

      Text('▷')
        .fontSize(15)
        .fontColor(HmclTheme.PRIMARY)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .borderRadius(17)
        .onClick(() => {
          this.selectedIndex = index;
          this.handleLaunch(inst);
        });

      Text('⋯')
        .fontSize(15)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .borderRadius(17)
        .onClick(() => {
          this.selectedIndex = index;
          this.showRowMenu(inst);
        });
    }
    .width('100%')
    .height(HmclTheme.LIST_CELL_HEIGHT)
    .padding({ left: 12, right: 8 })
    .backgroundColor(index === this.selectedIndex ? HmclTheme.SECONDARY_CONTAINER : Color.Transparent)
    .onClick(() => {
      this.selectedIndex = index;
    })
  }

  private iconColor(inst: GameInstallation): ResourceColor {
    if (inst.loaderType === LoaderType.FORGE || inst.loaderType === LoaderType.NEO_FORGE) {
      return '#5C6BC0';
    }
    if (inst.loaderType === LoaderType.FABRIC || inst.loaderType === LoaderType.QUILT) {
      return '#775200';
    }
    return '#4352A5';
  }

  private subtitleOf(inst: GameInstallation): string {
    const parts: string[] = [];
    parts.push(inst.gameVersion && inst.gameVersion.length > 0 ? inst.gameVersion : inst.versionId);
    if (inst.loaderType) {
      const name = inst.loaderType === LoaderType.NEO_FORGE ? 'NeoForge' : inst.loaderType;
      parts.push(name + (inst.loaderVersion ? ' ' + inst.loaderVersion : ''));
    } else {
      parts.push('原版');
    }
    return parts.join(' · ');
  }

  // ============================================================
  //  右侧详情 + 启动栏
  // ============================================================
  @Builder
  DetailPane() {
    Column() {
      if (this.selectedIndex >= 0 && this.selectedIndex < this.installations.length) {
        this.DetailBody(this.installations[this.selectedIndex])
      } else {
        Column() {
          Text('选择左侧的一个实例')
            .fontSize(14)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT);
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center);
      }

      // launch-pane：HMCL 右下角的启动按钮组
      this.LaunchPane()
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(HmclTheme.SURFACE)
  }

  @Builder
  DetailBody(inst: GameInstallation) {
    Scroll() {
      Column() {
        Text(inst.name)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE)
          .width('100%');

        Row() {
          Text(inst.gameVersion && inst.gameVersion.length > 0 ? inst.gameVersion : inst.versionId)
            .fontSize(11)
            .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
            .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 });
          if (inst.loaderType) {
            Text(inst.loaderType === LoaderType.NEO_FORGE ? 'NeoForge' : inst.loaderType)
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor(HmclTheme.TERTIARY)
              .borderRadius(6)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .margin({ left: 6 });
          }
        }
        .width('100%')
        .margin({ top: 10 });

        Divider()
          .color(HmclTheme.OUTLINE_VARIANT)
          .margin({ top: 16, bottom: 8 });

        this.InfoRow('游戏版本', inst.gameVersion && inst.gameVersion.length > 0 ? inst.gameVersion : '-');
        this.InfoRow('加载器', inst.loaderType ? (inst.loaderType + ' ' + (inst.loaderVersion ? inst.loaderVersion : '')) : '原版');
        this.InfoRow('最小内存', inst.minMemory.toString() + ' MB');
        this.InfoRow('最大内存', inst.maxMemory.toString() + ' MB');
        this.InfoRow('上次启动', inst.lastPlayed > 0 ? new Date(inst.lastPlayed).toLocaleString() : '从未启动');
        this.InfoRow('实例目录', inst.directory);

        if (this.message.length > 0) {
          Text(this.message)
            .fontSize(12)
            .fontColor(HmclTheme.ERROR)
            .width('100%')
            .margin({ top: 12 });
        }
      }
      .width('100%')
      .padding({ left: 28, right: 28, top: 24 });
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.TopStart);
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width(90);
      Text(value)
        .fontSize(13)
        .fontColor(HmclTheme.ON_SURFACE)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 });
  }

  /** HMCL .launch-pane：右下角，大号圆角启动按钮 + 方形菜单按钮 */
  @Builder
  LaunchPane() {
    Row() {
      Blank();

      Row() {
        Button(this.launchLabel())
          .height(HmclTheme.LAUNCH_BUTTON_HEIGHT)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(HmclTheme.LAUNCH_BUTTON_RADIUS)
          .padding({ left: 28, right: 28 })
          .enabled(this.selectedIndex >= 0)
          .onClick(() => {
            if (this.selectedIndex >= 0 && this.selectedIndex < this.installations.length) {
              this.handleLaunch(this.installations[this.selectedIndex]);
            }
          });

        Button('⋯')
          .width(HmclTheme.LAUNCH_BUTTON_HEIGHT)
          .height(HmclTheme.LAUNCH_BUTTON_HEIGHT)
          .fontSize(18)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .backgroundColor(HmclTheme.SURFACE_CONTAINER_HIGH)
          .borderRadius(HmclTheme.LAUNCH_BUTTON_RADIUS)
          .margin({ left: 10 })
          .onClick(() => {
            if (this.selectedIndex >= 0 && this.selectedIndex < this.installations.length) {
              this.showRowMenu(this.installations[this.selectedIndex]);
            }
          });
      }
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .backgroundColor(HmclTheme.SURFACE_CONTAINER)
      .borderRadius(HmclTheme.LAUNCH_BUTTON_RADIUS + 10);
    }
    .width('100%')
    .padding({ right: 24, bottom: 22, top: 10 });
  }

  private launchLabel(): string {
    if (this.selectedIndex < 0) {
      return '启动游戏';
    }
    if (!this.store.getSelectedAccount()) {
      return '需要先登录账户';
    }
    return '启动游戏';
  }

  // ============================================================
  //  实例操作菜单
  // ============================================================
  private showRowMenu(inst: GameInstallation): void {
    this.menuInstance = inst;
    this.menuVisible = true;
  }

  @Builder
  RowMenu() {
    Column() {
      Text(this.menuInstance ? this.menuInstance.name : '')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');
      Text(this.menuInstance ? this.menuInstance.directory : '')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4, bottom: 10 });

      this.MenuItem('启动游戏', HmclTheme.PRIMARY, () => {
        this.menuVisible = false;
        if (this.menuInstance) {
          this.handleLaunch(this.menuInstance);
        }
      });
      this.MenuItem('安装 Forge', HmclTheme.ON_SURFACE, () => {
        this.menuVisible = false;
        if (this.menuInstance) {
          this.openLoaderPanel(this.menuInstance, ModLoader.FORGE);
        }
      });
      this.MenuItem('安装 Fabric', HmclTheme.ON_SURFACE, () => {
        this.menuVisible = false;
        if (this.menuInstance) {
          this.openLoaderPanel(this.menuInstance, ModLoader.FABRIC);
        }
      });
      this.MenuItem('安装 NeoForge', HmclTheme.ON_SURFACE, () => {
        this.menuVisible = false;
        if (this.menuInstance) {
          this.openLoaderPanel(this.menuInstance, ModLoader.NEO_FORGE);
        }
      });
      this.MenuItem('删除实例', HmclTheme.ERROR, () => {
        this.menuVisible = false;
        if (this.menuInstance) {
          void this.versionManager.removeVersion(this.menuInstance.versionId);
          this.selectedIndex = -1;
          this.loadGames();
        }
      });
      this.MenuItem('取消', HmclTheme.ON_SURFACE_VARIANT, () => {
        this.menuVisible = false;
      });
    }
    .width(320)
    .padding(18)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 });
  }

  @Builder
  MenuItem(label: string, color: ResourceColor, action: () => void) {
    Text(label)
      .fontSize(14)
      .fontColor(color)
      .width('100%')
      .height(40)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(HmclTheme.SURFACE_CONTAINER)
      .margin({ bottom: 8 })
      .onClick(action);
  }

  // ============================================================
  //  安装面板（版本清单 → 安装）
  // ============================================================
  /** 打开加载器版本选择面板 */
  private openLoaderPanel(inst: GameInstallation, loader: ModLoader): void {
    this.pickMode = loader;
    this.loaderTarget = inst;
    this.loaderVersions = [];
    this.showInstall = true;
    this.installing = false;
    this.loaderLoading = true;
    const mcVersion: string = inst.gameVersion && inst.gameVersion.length > 0 ? inst.gameVersion : inst.versionId;
    this.loaderInstaller.getAvailableVersions(loader, mcVersion).then((list: LoaderVersion[]) => {
      this.loaderVersions = list;
      this.loaderLoading = false;
      if (list.length === 0) {
        this.message = `没有找到适配 ${mcVersion} 的 ${loader} 版本`;
      }
    }).catch((e: Error) => {
      this.loaderLoading = false;
      this.message = `${loader} 版本列表获取失败：${e.message}`;
      Logger.error('GameListPage', this.message);
    });
  }

  private startLoaderInstall(loader: ModLoader, loaderVersion: string): void {
    const inst = this.loaderTarget;
    if (!inst) {
      return;
    }
    const mcVersion: string = inst.gameVersion && inst.gameVersion.length > 0 ? inst.gameVersion : inst.versionId;
    this.installing = true;
    this.installProgress = 0;
    this.installTitle = `安装 ${loader} ${loaderVersion} (MC ${mcVersion})`;
    this.installDetail = '准备中…';

    this.loaderInstaller.installLoader(loader, mcVersion, loaderVersion, (p) => {
      this.installProgress = p.progress;
      this.installDetail = p.phase + ' · ' + p.message;
    }).then(() => {
      this.installing = false;
      this.showInstall = false;
      this.loadGames();
    }).catch((e: Error) => {
      this.installing = false;
      this.installDetail = '失败：' + e.message;
      this.message = `${loader} 安装失败：${e.message}`;
      Logger.error('GameListPage', this.message);
    });
  }

  private openInstallPanel(): void {
    this.pickMode = 'mc';
    this.loaderTarget = null;
    this.showInstall = true;
    if (this.manifestVersions.length > 0) {
      return;
    }
    this.manifestLoading = true;
    VersionInstaller.fetchManifest(true).then((manifest: VersionManifest) => {
      this.manifestVersions = manifest.versions.filter((v: VersionInfo) => v.type === 'release');
      this.manifestLoading = false;
    }).catch((e: Error) => {
      this.manifestLoading = false;
      this.message = '版本清单获取失败：' + e.message;
      Logger.error('GameListPage', this.message);
    });
  }

  @Builder
  InstallOverlay() {
    Column() {
      Row() {
        Text(this.installing ? '正在安装' : this.overlayTitle())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Blank();
        if (!this.installing) {
          Text('关闭')
            .fontSize(13)
            .fontColor(HmclTheme.PRIMARY)
            .onClick(() => {
              this.showInstall = false;
            });
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 });

      if (this.installing) {
        Column() {
          Text(this.installTitle)
            .fontSize(15)
            .fontColor(HmclTheme.ON_SURFACE)
            .width('100%');
          Progress({ value: this.installProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .margin({ top: 12 })
            .color(HmclTheme.PRIMARY_CONTAINER);
          Text(Math.round(this.installProgress).toString() + '%  ' + this.installDetail)
            .fontSize(12)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT)
            .width('100%')
            .margin({ top: 8 });
        }
        .width('100%')
        .padding(20);
      } else if (this.pickMode === 'mc' && this.manifestLoading) {
        LoadingView({ message: '拉取版本清单…' });
      } else if (this.pickMode !== 'mc' && this.loaderLoading) {
        LoadingView({ message: '拉取加载器版本…' });
      } else if (this.pickMode === 'mc') {
        List() {
          ForEach(this.manifestVersions, (v: VersionInfo) => {
            ListItem() {
              this.PickRow(v.id, v.type === 'release' ? '正式版' : v.type, () => {
                this.startInstall(v.id);
              })
            }
          }, (v: VersionInfo) => v.id)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT });
      } else {
        List() {
          ForEach(this.loaderVersions, (v: LoaderVersion) => {
            ListItem() {
              this.PickRow(v.version, v.stable ? '稳定版' : '测试版', () => {
                this.startLoaderInstall(v.loader, v.version);
              })
            }
          }, (v: LoaderVersion) => v.fullVersionId)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT });
      }
    }
    .width('72%')
    .height('78%')
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  private overlayTitle(): string {
    if (this.pickMode === 'mc') {
      return '选择要安装的 Minecraft 版本';
    }
    return '选择 ' + this.pickMode + ' 版本';
  }

  @Builder
  PickRow(label: string, tag: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(HmclTheme.ON_SURFACE)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      Text(tag)
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
      Text('安装')
        .fontSize(12)
        .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
        .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
        .borderRadius(8)
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .margin({ left: 12 })
        .onClick(action);
    }
    .width('100%')
    .height(48)
    .padding({ left: 20, right: 20 });
  }

  private startInstall(versionId: string): void {
    this.installing = true;
    this.installProgress = 0;
    this.installTitle = '安装 ' + versionId;
    this.installDetail = '准备中…';

    this.versionManager.installVersion(versionId, (p) => {
      this.installProgress = Math.round(p.progress * 100);
      this.installDetail = p.phase + ' · ' + p.message;
    }).then(() => {
      this.installing = false;
      this.showInstall = false;
      this.installDetail = '';
      this.loadGames();
    }).catch((e: Error) => {
      this.installing = false;
      this.message = '安装失败：' + e.message;
      this.installDetail = '失败：' + e.message;
      Logger.error('GameListPage', this.message);
    });
  }

  // ============================================================
  //  启动
  // ============================================================
  async handleLaunch(inst: GameInstallation): Promise<void> {
    const account = this.store.getSelectedAccount();
    if (!account) {
      this.message = '还没有账户，请先到「账户」页添加一个离线账户。';
      return;
    }
    this.message = '';

    try {
      const accountData: PendingAccountData = {
        username: account.username,
        uuid: account.uuid,
        accessToken: account.accessToken,
        refreshToken: account.refreshToken,
        userProperties: account.userProperties || '{}',
      };
      const launchConfigObj: PendingLaunchConfig = {
        versionId: inst.versionId,
        name: inst.name,
        gameVersion: inst.gameVersion,
        loaderType: inst.loaderType,
        minMemory: inst.minMemory,
        maxMemory: inst.maxMemory,
        directory: inst.directory,
        width: inst.width,
        height: inst.height,
        fullscreen: inst.fullscreen,
        customJvmArgs: inst.customJvmArgs,
        account: accountData,
      };
      AppStorage.setOrCreate('pendingGameLaunch', JSON.stringify(launchConfigObj));

      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // 旧代码把 bundleName 硬编码成 'com.hmcl.launcher'（AppScope 里早已改成
      // com.abcmouren.HMCL_HarmonyOS），startAbility 必然失败。
      const wantParams: Record<string, string> = {} as Record<string, string>;
      wantParams['versionId'] = inst.versionId;
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'GameAbility',
        parameters: wantParams,
      };
      context.startAbility(want).then(() => {
        Logger.info('GameListPage', 'GameAbility 已启动');
      }).catch((err: BusinessError) => {
        this.message = '启动失败：' + err.message;
        Logger.error('GameListPage', this.message);
      });
    } catch (e) {
      this.message = '启动异常：' + (e as Error).message;
      Logger.error('GameListPage', this.message);
    }
  }
}
