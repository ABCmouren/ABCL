/**
 * GameDirPage — 游戏目录（让用户知道 .minecraft 在哪、能干什么）
 *
 * 诉求来自实际使用：之前的目录「用到才建」，装完游戏只有
 * versions / libraries / assets，用户想自己丢模组、光影、截图时不知道往哪放；
 * 而且默认路径在 app 沙箱里，外部文件管理器打不开。
 *
 * 这一页做四件事：
 *   1. 明确显示当前 .minecraft 的完整路径 + 位置性质（沙箱内 / 自定义）
 *   2. 列出标准骨架目录、用途、占用大小，并可一键补建缺失目录
 *   3. 允许改游戏目录位置（写到 settings，新实例生效）
 *   4. 说明外部访问方式（沙箱限制 + 导出建议）
 */
import { DirUsage, GameDirectory } from '../../core/game/GameDirectory';
import { VersionManager } from '../../core/game/VersionManager';
import { AppStore } from '../../core/AppStore';
import { HmclTheme } from '../../theme/HmclTheme';
import { FileUtils, Logger } from '../../core/util/Utils';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';

@Component
export default struct GameDirPage {
  @State usages: DirUsage[] = [];
  @State isLoading: boolean = true;
  @State message: string = '';
  @State error: string = '';
  @State editingPath: boolean = false;
  @State pathInput: string = '';

  private versionManager = VersionManager.getInstance();
  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  private mcDir(): string {
    return this.versionManager.getMinecraftDir();
  }

  private isDefault(): boolean {
    const configured = this.store.config.gameDirectory;
    return configured === undefined || configured.length === 0;
  }

  private reload(): void {
    this.isLoading = true;
    this.error = '';
    this.measuring = true;
    // 统计是递归遍历，放后台
    void (async () => {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => {
          resolve();
        }, 0);
      });
      this.usages = GameDirectory.measureAll(this.mcDir());
      this.measuring = false;
      this.isLoading = false;
    })();
  }

  @State measuring: boolean = false;

  private ensureSkeleton(): void {
    const created = GameDirectory.ensureSkeleton(this.mcDir());
    if (created.length > 0) {
      this.message = `已补建 ${created.length} 个目录：${created.join('、')}`;
    } else {
      this.message = '目录骨架已完整';
    }
    this.reload();
  }

  private savePath(): void {
    const p = this.pathInput.trim();
    if (p.length > 0 && !p.startsWith('/')) {
      this.error = '请填写以 / 开头的绝对路径';
      return;
    }
    this.store.updateConfig({ gameDirectory: p });
    this.editingPath = false;
    this.message = p.length > 0 ? `游戏目录已改为 ${p}` : '已恢复默认目录';
    this.error = '';
    this.ensureSkeleton();
  }

  private resetPath(): void {
    this.store.updateConfig({ gameDirectory: '' });
    this.editingPath = false;
    this.message = '已恢复默认目录';
    this.ensureSkeleton();
  }

  build() {
    Stack() {
      Column() {
        this.LocationCard()
        this.UsageList()
        if (this.editingPath) {
          this.EditOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(HmclTheme.SURFACE)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LocationCard() {
    Column() {
      Row() {
        Text('.minecraft 位置')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Blank();
        Text('修改位置')
          .fontSize(12)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.pathInput = this.store.config.gameDirectory;
            this.editingPath = true;
          });
      }
      .width('100%');

      Text(this.mcDir())
        .fontSize(12)
        .fontFamily('monospace')
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%')
        .margin({ top: 8 })
        .padding(10)
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(8)
        .copyOption(CopyOptions.LocalDevice);

      Text(this.isDefault()
        ? '当前在应用私有目录（沙箱内）。鸿蒙沙箱不对外开放，文件管理器和电脑都访问不到这里。' +
          '想在外面管理文件，请点右上角把目录改到应用可访问的位置。'
        : '当前为自定义目录。')
        .fontSize(11)
        .fontColor(this.isDefault() ? HmclTheme.ON_SURFACE_VARIANT : HmclTheme.ON_SECONDARY_CONTAINER)
        .width('100%')
        .margin({ top: 8 });

      Row() {
        Button('补建缺失目录')
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(8)
          .onClick(() => {
            this.ensureSkeleton();
          });
        Text('总占用')
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .margin({ left: 12, right: 6 })
          .align(Alignment.Center);
        Text(this.totalLabel())
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE)
          .align(Alignment.Center);
      }
      .width('100%')
      .margin({ top: 12 });

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .width('100%')
          .margin({ top: 8 });
      }
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(11)
          .fontColor(HmclTheme.ERROR)
          .width('100%')
          .margin({ top: 8 });
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 12 })
  }

  private totalLabel(): string {
    if (this.measuring) {
      return '统计中…';
    }
    const total = GameDirectory.totalBytes(this.usages);
    if (total <= 0) {
      return '0 B';
    }
    return FormatSize(total);
  }

  @Builder
  UsageList() {
    Column() {
      Row() {
        Text('目录结构')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE);
        Blank();
        Text('刷新')
          .fontSize(12)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.reload();
          });
      }
      .width('100%')
      .padding({ bottom: 6 });

      if (this.isLoading) {
        LoadingView({ message: '统计目录占用…' })
      } else if (this.usages.length === 0) {
        EmptyView({ icon: '', message: '目录还不存在，点上面「补建缺失目录」', actionText: '' })
      } else {
        List() {
          ForEach(this.usages, (u: DirUsage) => {
            ListItem() {
              this.UsageRow(u)
            }
          }, (u: DirUsage) => u.name)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  @Builder
  UsageRow(u: DirUsage) {
    Row() {
      Column() {
        Text(`${u.name}/`)
          .fontSize(13)
          .fontFamily('monospace')
          .fontColor(HmclTheme.ON_SURFACE)
          .width('100%');
        Text(GameDirectory.purposeOf(u.name))
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .width('100%')
          .margin({ top: 2 });
      }
      .layoutWeight(1);

      Text(this.measuring ? '…' : GameDirectory.formatUsage(u))
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .margin({ left: 10 });
    }
    .width('100%')
    .height(46)
  }

  @Builder
  EditOverlay() {
    Column() {
      Text('修改游戏目录')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');

      Text('填写应用有读写权限的绝对路径，例如应用沙箱下的另一个目录。' +
        '改完这里只影响「之后」新建或安装的实例；已装好的实例仍在旧目录。')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width('100%')
        .margin({ top: 8 });

      TextInput({ placeholder: '/data/storage/el2/base/haps/entry/files/minecraft', text: this.pathInput })
        .width('100%')
        .height(38)
        .fontSize(12)
        .margin({ top: 14 })
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(8)
        .onChange((v: string) => {
          this.pathInput = v;
        });

      Row() {
        Button('恢复默认')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .backgroundColor(HmclTheme.SURFACE_CONTAINER)
          .borderRadius(10)
          .onClick(() => {
            this.resetPath();
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
            this.savePath();
          });
      }
      .width('100%')
      .margin({ top: 16 });
    }
    .width(460)
    .padding(22)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }
}

function FormatSize(bytes: number): string {
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  }
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
