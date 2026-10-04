/**
 * JavaPage — Java 运行时管理（对应 HMCL 的 JavaManagementPage）
 *
 *   - 列出已安装的 JDK（内置 3 个 + 用户导入）
 *   - 显示每个 JDK 适配哪些 MC 版本
 *   - 导入外部 JDK（用户从设备上选一个目录）
 *   - 删除非内置的 JDK
 *   - 设置默认 Java（写入 settings，实例未单独指定时用它）
 */
import { JavaManager, JdkInfo } from '../../core/launch/JavaManager.ets';
import { FileExchange } from '../../core/util/FileExchange';
import { AppStore } from '../../core/AppStore';
import { Constants } from '../../config/Constants';
import { FileUtils, Logger } from '../../core/util/Utils';
import { HmclTheme } from '../../theme/HmclTheme';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';

@Component
export default struct JavaPage {
  @State jdks: JdkInfo[] = [];
  @State isLoading: boolean = true;
  @State message: string = '';
  @State error: string = '';
  @State importing: boolean = false;

  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  private root(): string {
    return JavaManager.root(Constants.appDir);
  }

  private reload(): void {
    this.isLoading = true;
    this.jdks = JavaManager.scan(this.root());
    this.isLoading = false;
  }

  /** 该 JDK 能跑的 MC 版本范围（人话） */
  private compatibleLabel(jdk: JdkInfo): string {
    const m = jdk.majorVersion;
    if (m >= 21) {
      return 'MC 1.20.5 及以上';
    }
    if (m === 17) {
      return 'MC 1.17 ~ 1.20.4';
    }
    if (m === 8) {
      return 'MC 1.16.5 及以下';
    }
    return m > 0 ? `Java ${m}` : '版本未知';
  }

  private isDefault(jdk: JdkInfo): boolean {
    const p = this.store.config.javaPath;
    return p.length > 0 && p.indexOf('/' + jdk.name) >= 0;
  }

  private setDefault(jdk: JdkInfo): void {
    this.store.updateConfig({ javaPath: jdk.path });
    this.message = '默认 Java 已设为 ' + jdk.name;
    this.reload();
  }

  private clearDefault(): void {
    this.store.updateConfig({ javaPath: '' });
    this.message = '已恢复自动选择（按 MC 版本挑合适的 JDK）';
    this.reload();
  }

  private async importJdk(): Promise<void> {
    this.importing = true;
    this.message = '请选择 JDK 目录…';
    this.error = '';
    const picked = await FileExchange.chooseGameDir();
    this.importing = false;
    if (picked.length === 0) {
      this.message = '已取消';
      return;
    }
    // 校验是否像 JDK
    if (!FileUtils.exists(picked + '/bin')) {
      this.error = '所选目录里没有 bin/，看起来不是 JDK';
      this.message = '';
      return;
    }
    const name = picked.substring(picked.lastIndexOf('/') + 1);
    const target = this.root() + '/' + (name.length > 0 ? name : 'imported-jdk');
    try {
      FileUtils.mkdirs(this.root());
      if (FileUtils.exists(target)) {
        FileUtils.delete(target);
      }
      InstanceCopy.copyTree(picked, target);
      const major = JavaManager.probeMajor(target);
      this.message = `已导入 ${name}（Java ${major > 0 ? major : '版本未知'}）`;
      this.reload();
    } catch (e) {
      this.error = '导入失败：' + (e as Error).message;
      this.message = '';
    }
  }

  private remove(jdk: JdkInfo): void {
    try {
      FileUtils.delete(jdk.path);
      if (this.isDefault(jdk)) {
        this.clearDefault();
      }
      this.message = '已删除 ' + jdk.name;
      this.reload();
    } catch (e) {
      this.error = '删除失败：' + (e as Error).message;
    }
  }

  build() {
    Column() {
      this.HeaderView()
      if (this.isLoading) {
        LoadingView({ message: '扫描 Java 运行时…' })
      } else if (this.jdks.length === 0) {
        EmptyView({ icon: '', message: '没有找到 JDK，点「导入 JDK」从设备上选一个', actionText: '' })
      } else {
        List() {
          ForEach(this.jdks, (jdk: JdkInfo) => {
            ListItem() {
              this.JdkRow(jdk)
            }
          }, (jdk: JdkInfo) => jdk.path)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
      }

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 6 });
      }
      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(12)
          .fontColor(HmclTheme.ERROR)
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 8 });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(HmclTheme.SURFACE)
  }

  @Builder
  HeaderView() {
    Column() {
      Row() {
        Text('Java 运行时')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Text(` ${this.jdks.length} 个`)
          .fontSize(12)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT);
        Blank();
        Text(this.importing ? '选择中…' : '导入 JDK')
          .fontSize(12)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            void this.importJdk();
          });
      }
      .width('100%');

      Text(this.root())
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 });

      Text('Minecraft 对 Java 版本有硬性要求：1.20.5+ 要 Java 21，' +
        '1.17~1.20.4 要 Java 17，1.16.5 及以下要 Java 8。' +
        '不指定默认 Java 时，启动器会按实例的 MC 版本自动挑。')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width('100%')
        .margin({ top: 8 });

      Row() {
        Text('当前默认')
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .margin({ right: 6 });
        Text(this.store.config.javaPath.length > 0 ? this.store.config.javaPath : '自动选择')
          .fontSize(11)
          .fontColor(HmclTheme.ON_SURFACE)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text('恢复自动')
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .padding({ left: 8 })
          .onClick(() => {
            this.clearDefault();
          });
      }
      .width('100%')
      .margin({ top: 10 })
      .padding(10)
      .backgroundColor(HmclTheme.SURFACE_CONTAINER)
      .borderRadius(8);
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }

  @Builder
  JdkRow(jdk: JdkInfo) {
    Row() {
      Column() {
        Row() {
          Text(`${jdk.name}`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(HmclTheme.ON_SURFACE);
          if (jdk.bundled) {
            Text('内置')
              .fontSize(10)
              .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
              .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ left: 8 });
          }
          if (!jdk.fullJdk) {
            Text('仅 JRE，不可启动游戏')
              .fontSize(10)
              .fontColor(HmclTheme.ON_ERROR_CONTAINER)
              .backgroundColor(HmclTheme.ERROR_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ left: 6 });
          }
          if (this.isDefault(jdk)) {
            Text('默认')
              .fontSize(10)
              .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
              .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ left: 6 });
          }
        }
        .width('100%');

        Text(`Java ${jdk.majorVersion > 0 ? jdk.majorVersion : '?'} · ${this.compatibleLabel(jdk)}` +
          (jdk.fullJdk ? '' : ' · 缺少 bin/java'))
          .fontSize(11)
          .fontColor(jdk.fullJdk ? HmclTheme.ON_SURFACE_VARIANT : HmclTheme.ERROR)
          .width('100%')
          .margin({ top: 3 });

        Text(jdk.path)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(HmclTheme.OUTLINE)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 });
      }
      .layoutWeight(1);

      if (!this.isDefault(jdk) && jdk.fullJdk) {
        Text('设为默认')
          .fontSize(12)
          .fontColor(HmclTheme.PRIMARY)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.setDefault(jdk);
          });
      }
      if (jdk.removable) {
        Text('删除')
          .fontSize(12)
          .fontColor(HmclTheme.ERROR)
          .padding({ left: 8, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            this.remove(jdk);
          });
      }
    }
    .width('100%')
    .height(76)
    .padding({ left: 20, right: 16 })
  }
}

/** 目录拷贝（JavaPage 里内联一个精简版，避免额外依赖） */
class InstanceCopy {
  static copyTree(src: string, dst: string): number {
    let n = 0;
    for (const e of FileUtils.listDir(src)) {
      const from = src + '/' + e;
      const to = dst + '/' + e;
      if (FileUtils.isDirectory(from)) {
        FileUtils.mkdirs(to);
        n += InstanceCopy.copyTree(from, to);
      } else {
        FileUtils.mkdirs(FileUtils.getDirName(to));
        FileUtils.copyFile(from, to);
        n++;
      }
    }
    return n;
  }
}
