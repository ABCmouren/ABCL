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
import WorldPage from './world/WorldPage';
import ModpackPage from './modpack/ModpackPage';
import { HMCL_NAV, HmclTheme, NavEntry } from '../theme/HmclTheme';
import { AppStore } from '../core/AppStore';

@Entry
@Component
struct Index {
  @State currentNav: string = 'instances';

  private store = AppStore.getInstance();

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

      Text('HMCL')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE);
      Text(' — Hello Minecraft! Launcher')
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
        Text(this.accountLabel())
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

  private accountLabel(): string {
    const account = this.store.getSelectedAccount();
    if (!account) {
      return '未登录';
    }
    return account.username;
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
    } else if (this.currentNav === 'worlds') {
      WorldPage()
    } else if (this.currentNav === 'modpacks') {
      ModpackPage()
    } else {
      SettingsPage()
    }
  }

  @Builder
  StatusBar() {
    Row() {
      Text('HMCL-HarmonyOS 2.0.0')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
      Blank();
      Text(this.summaryLabel())
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT);
    }
    .width('100%')
    .height(26)
    .padding({ left: 14, right: 14 })
    .backgroundColor(HmclTheme.SURFACE_CONTAINER)
    .border({ width: { top: 1 }, color: HmclTheme.OUTLINE_VARIANT })
  }

  private summaryLabel(): string {
    return this.store.installations.length.toString() + ' 个实例 · '
      + this.store.accounts.length.toString() + ' 个账户';
  }
}
