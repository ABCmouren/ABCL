/**
 * Index — HMCL 风格外壳（Decorator）
 *
 * 对齐 HMCL 的 org.jackhuang.hmcl.ui.decorator.Decorator：
 *   顶栏（标题 + 快捷操作） / 左侧导航（gray-background = surface-container） /
 *   内容区 / 底部状态条。
 * 视觉全部取 HMCL assets/css/blue.css 的 -monet-* 色板，见 theme/HmclTheme.ets。
 */
import GameListPage from './main/GameListPage';
import DownloadPage from './download/DownloadPage';
import AccountPage from './account/AccountPage';
import SettingsPage from './settings/SettingsPage';
import ModPage from './mod/ModPage';
import PackPage from './pack/PackPage';
import WorldPage from './world/WorldPage';
import ModpackPage from './modpack/ModpackPage';
import GameDirPage from './gamedir/GameDirPage';
import JavaPage from './java/JavaPage';
import LogPage from './log/LogPage';
import { HMCL_NAV, HmclTheme, NavEntry } from '../theme/HmclTheme';
import { AppStore } from '../core/AppStore';
import { Account } from '../model/Account';
import { GameInstallation } from '../model/GameVersion';

@Entry
@Component
struct Index {
  @State currentNav: string = 'instances';

  /**
   * 侧栏「当前账户」必须用 @State 存，
   * 不能在 build() 里调 this.accountLabel() —— ArkUI V1 不追踪方法返回值，
   * 结果就是切账号后侧栏不动，得切一次页面（触发重建）才显示。
   */
  @State accountLabelText: string = '未登录';
  @State statusText: string = '';

  private store = AppStore.getInstance();
  private unsubscribeAccounts: (() => void) | null = null;
  private unsubscribeInstallations: (() => void) | null = null;

  aboutToAppear(): void {
    this.refreshAccountLabel();
    this.refreshStatus();
    // 订阅全局状态：账户/实例一变，侧栏与状态条立即刷新
    this.unsubscribeAccounts = this.store.onAccountsChanged((accounts: Account[]) => {
      this.accountLabelText = this.store.getSelectedAccount() !== null
        ? this.store.getSelectedAccount()!.username
        : '未登录';
    });
    this.unsubscribeInstallations = this.store.onInstallationsChanged((list: GameInstallation[]) => {
      this.refreshStatus();
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeAccounts !== null) {
      this.unsubscribeAccounts();
      this.unsubscribeAccounts = null;
    }
    if (this.unsubscribeInstallations !== null) {
      this.unsubscribeInstallations();
      this.unsubscribeInstallations = null;
    }
  }

  private refreshAccountLabel(): void {
    const account = this.store.getSelectedAccount();
    this.accountLabelText = account !== null ? account.username : '未登录';
  }

  private refreshStatus(): void {
    this.statusText = `${this.store.installations.length} 个实例 · ${this.store.accounts.length} 个账户`;
  }

  build() {
    Column() {
      this.TitleBar()

      Row() {
        this.NavRail()
        Column() {
          this.Content()
        }
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(HmclTheme.SURFACE)
      }
      .layoutWeight(1)
      .width('100%')

      this.StatusBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HmclTheme.SURFACE)
  }

  @Builder
  TitleBar() {
    Row() {
      Stack() {
        Text('H')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER);
      }
      .width(26)
      .height(26)
      .borderRadius(6)
      .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
      .margin({ right: 10 });

      Text('ABCL')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE);
      Text(' — A Minecraft Java Edition Launcher')
        .fontSize(12)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .margin({ left: 6 });

      Blank();

      this.TitleAction('下载', 'download');
      this.TitleAction('账户', 'accounts');
      this.TitleAction('设置', 'settings');
    }
    .width('100%')
    .height(HmclTheme.TITLE_BAR_HEIGHT)
    .padding({ left: 14, right: 14 })
    .backgroundColor(HmclTheme.SURFACE_CONTAINER)
    .border({ width: { bottom: 1 }, color: HmclTheme.OUTLINE_VARIANT })
  }

  @Builder
  TitleAction(label: string, key: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.currentNav === key ? HmclTheme.PRIMARY : HmclTheme.ON_SURFACE_VARIANT)
      .fontWeight(this.currentNav === key ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(8)
      .margin({ left: 4 })
      .onClick(() => {
        this.currentNav = key;
      })
  }

  @Builder
  NavRail() {
    Column() {
      ForEach(HMCL_NAV, (item: NavEntry) => {
        Row() {
          Text(item.glyph)
            .fontSize(15)
            .width(24)
            .textAlign(TextAlign.Center)
            .fontColor(this.currentNav === item.key
              ? HmclTheme.ON_PRIMARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT);
          Text(item.label)
            .fontSize(14)
            .margin({ left: 8 })
            .fontColor(this.currentNav === item.key
              ? HmclTheme.ON_PRIMARY_CONTAINER : HmclTheme.ON_SURFACE);
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .borderRadius(10)
        .margin({ bottom: 4 })
        .backgroundColor(this.currentNav === item.key ? HmclTheme.PRIMARY_CONTAINER : Color.Transparent)
        .onClick(() => {
          this.currentNav = item.key;
        })
      }, (item: NavEntry) => item.key)

      Blank();

      Column() {
        Text('当前账户')
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .width('100%');
        Text(this.accountLabelText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 });
      }
      .width('100%')
      .padding(10)
      .borderRadius(10)
      .backgroundColor(HmclTheme.SURFACE_CONTAINER)
      .onClick(() => {
        this.currentNav = 'accounts';
      });
    }
    .width(HmclTheme.NAV_WIDTH)
    .height('100%')
    .padding({ left: 10, right: 10, top: 12, bottom: 12 })
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOW)
    .border({ width: { right: 1 }, color: HmclTheme.OUTLINE_VARIANT })
  }

  @Builder
  Content() {
    if (this.currentNav === 'instances') {
      GameListPage()
    } else if (this.currentNav === 'download') {
      DownloadPage()
    } else if (this.currentNav === 'accounts') {
      AccountPage()
    } else if (this.currentNav === 'mods') {
      ModPage()
    } else if (this.currentNav === 'resourcepacks') {
      PackPage({ kind: 'resourcepack' })
    } else if (this.currentNav === 'shaders') {
      PackPage({ kind: 'shader' })
    } else if (this.currentNav === 'worlds') {
      WorldPage()
    } else if (this.currentNav === 'modpacks') {
      ModpackPage()
    } else if (this.currentNav === 'gamedir') {
      GameDirPage()
    } else if (this.currentNav === 'java') {
      JavaPage()
    } else if (this.currentNav === 'logs') {
      LogPage()
    } else {
      SettingsPage()
    }
  }

  @Builder
  StatusBar() {
    Row() {
      Text('ABCL 2.0.0')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
      Blank();
      Text(this.statusText.length > 0
        ? this.statusText
        : `${this.store.installations.length} 个实例 · ${this.store.accounts.length} 个账户`)
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
    }
    .width('100%')
    .height(26)
    .padding({ left: 14, right: 14 })
    .backgroundColor(HmclTheme.SURFACE_CONTAINER)
    .border({ width: { top: 1 }, color: HmclTheme.OUTLINE_VARIANT })
  }

}
