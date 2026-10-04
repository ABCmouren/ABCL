/**
 * LogPage — 日志查看器（P0-5）
 *
 * 对应 HMCL 的 LogWindow / SettingsPage 的「查看日志」：
 *   - 列出所有历史日志文件（hmcl_YYYY-MM-DD.log，保留 5 天）
 *   - 显示内存中的实时日志（Logger 的 500 行环形缓冲）
 *   - 可切级别过滤、搜索、自动滚动、复制、清空
 *   - 崩溃报告单独一栏（crash-reports/）
 */
import { Logger, StringUtils } from '../../core/util/Utils';
import { CrashReporter, CrashEntry } from '../../core/util/CrashReporter';
import { GameDirectory } from '../../core/game/GameDirectory';
import { VersionManager } from '../../core/game/VersionManager';
import { FileUtils } from '../../core/util/Utils';
import { HmclTheme } from '../../theme/HmclTheme';
import { EmptyView } from '../../components/common/CommonComponents';

enum LogSource {
  MEMORY = 'memory',
  FILE = 'file'
}

@Component
export default struct LogPage {
  @State files: string[] = [];
  @State selected: string = '';      // 空 = 看内存实时日志
  @State content: string = '';
  /** 显式维护的渲染数组（不能用 content.split() 直接喂 ForEach） */
  @State lines: string[] = [];
  @State search: string = '';
  @State minLevel: string = 'ALL';
  @State autoScroll: boolean = true;
  @State crashFiles: string[] = [];
  @State crashEntries: CrashEntry[] = [];
  @State crashDetail: string = '';
  @State message: string = '';

  private versionManager = VersionManager.getInstance();
  private scroller: Scroller = new Scroller();
  private timer: number = -1;

  aboutToAppear(): void {
    this.reload();
    // 内存日志每 2 秒刷新一次
    this.timer = setInterval(() => {
      if (this.selected.length === 0 && !this.autoScroll) {
        return;
      }
      this.loadContent();
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private reload(): void {
    this.files = Logger.listFiles();
    this.loadCrashes();
    this.loadContent();
  }

  private loadCrashes(): void {
    const all = CrashReporter.collect(this.versionManager.getMinecraftDir());
    this.crashEntries = all;
    this.crashFiles = all.map((e: CrashEntry) => e.title);
  }

  private source(): LogSource {
    return this.selected.length === 0 ? LogSource.MEMORY : LogSource.FILE;
  }

  private loadContent(): void {
    let text: string;
    if (this.source() === LogSource.MEMORY) {
      text = Logger.tail(500);
    } else {
      text = Logger.readFile(this.selected, 512 * 1024);
    }
    this.content = this.applyFilter(text);
    const arr: string[] = this.content.split('\n');
    this.lines = arr.length > 800 ? arr.slice(arr.length - 800) : arr;
  }

  /** 级别过滤 + 关键字搜索 */
  private applyFilter(text: string): string {
    const rows: string[] = text.split('\n');
    const out: string[] = [];
    const kw = this.search.toLowerCase();
    for (const line of rows) {
      if (this.minLevel !== 'ALL') {
        // 行格式：[ts] [LEVEL] [tag] message
        const m = /\]\s*\[(ERROR|WARN|INFO|DEBUG)\]/.exec(line);
        const level = m !== null ? m[1] : 'INFO';
        if (!LogPage.levelPass(this.minLevel, level)) {
          continue;
        }
      }
      if (kw.length > 0 && line.toLowerCase().indexOf(kw) < 0) {
        continue;
      }
      out.push(line);
    }
    return out.join('\n');
  }

  /** 过滤后同步到 @State 数组 */
  private syncLines(text: string): void {
    const filtered: string[] = this.applyFilter(text).split('\n');
    // 超过 800 行只保留尾部，避免一次渲染太多节点
    this.lines = filtered.length > 800 ? filtered.slice(filtered.length - 800) : filtered;
  }

  private static levelPass(min: string, level: string): boolean {
    const order: string[] = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
    const mi = order.indexOf(min);
    const li = order.indexOf(level);
    if (mi < 0) {
      return true;
    }
    if (li < 0) {
      return true;
    }
    return li >= mi;
  }

  private static levelColor(line: string): string {
    if (line.indexOf('[ERROR]') >= 0) {
      return HmclTheme.ERROR;
    }
    if (line.indexOf('[WARN]') >= 0) {
      return '#8A5000';
    }
    if (line.indexOf('[DEBUG]') >= 0) {
      return HmclTheme.OUTLINE;
    }
    return HmclTheme.ON_SURFACE;
  }

  private lineColor(line: string): string {
    return LogPage.levelColor(line);
  }

  private async copyAll(): Promise<void> {
    const text = this.source() === LogSource.MEMORY
      ? Logger.toClipboard('memory')
      : Logger.toClipboard(this.selected);
    // ArkUI 的剪贴板通过 pasteboard，这里用 promptAction 提示用户手动复制
    this.message = `已准备 ${text.length} 字符，请长按下方文本复制`;
  }

  private async shareFile(): Promise<void> {
    if (this.source() === LogSource.MEMORY) {
      this.message = '内存日志无法导出，请先选择一个日志文件';
      return;
    }
    const dir = Logger.dir();
    this.message = `日志文件位于：${dir}/${this.selected}`;
  }

  build() {
    Column() {
      this.HeaderView()
      this.Toolbar()
      this.SourceBar()

      if (this.crashDetail.length > 0) {
        this.CrashOverlay()
      }

      if (this.content.length === 0) {
        EmptyView({ icon: '', message: this.selected.length === 0 ? '暂无日志' : '日志为空', actionText: '刷新' })
      } else {
        Scroll(this.scroller) {
          Column() {
            // ⚠️ 不要直接 ForEach(this.content.split('\n'))：
            // 每次 build 都产生新数组，key 相同的情况下 ArkUI 不会重建节点，
            // 正文就一直是空的。必须显式维护 @State 数组。
            ForEach(this.lines, (line: string, index: number) => {
              Text(line.length > 0 ? line : ' ')
                .fontSize(11)
                .fontFamily('monospace')
                .fontColor(LogPage.levelColor(line))
                .width('100%')
                .padding({ left: 2, right: 2 })
            }, (line: string, index: number) => `${index}-${line.length}-${line.substring(0, 24)}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
        .scrollBar(BarState.Auto)
      }

      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .width('100%')
          .padding({ left: 20, right: 20, top: 6, bottom: 6 });
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
        Text('日志')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Text(` ${this.files.length} 个文件 · 崩溃报告 ${this.crashFiles.length}`)
          .fontSize(12)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT);
        Blank();
        Text('刷新')
          .fontSize(12)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.reload();
          });
      }
      .width('100%');

      Text(Logger.dir())
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 8 })
  }

  @Builder
  Toolbar() {
    Row() {
      TextInput({ placeholder: '搜索日志内容…', text: this.search })
        .layoutWeight(1)
        .height(32)
        .fontSize(13)
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(8)
        .onChange((v: string) => {
          this.search = v;
          this.loadContent();
        });
      Text('清空内存')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .padding({ left: 10, right: 4, top: 8, bottom: 8 })
        .onClick(() => {
          Logger.clearMemory();
          this.loadContent();
        });
      Text('位置')
        .fontSize(11)
        .fontColor(HmclTheme.PRIMARY)
        .padding({ left: 6, right: 4, top: 8, bottom: 8 })
        .onClick(() => {
          this.shareFile();
        });
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 8 })
  }

  @Builder
  SourceBar() {
    Column() {
      Scroll() {
        Row() {
          this.LevelChip('ALL', '全部');
          this.LevelChip('DEBUG', 'DEBUG');
          this.LevelChip('INFO', 'INFO');
          this.LevelChip('WARN', 'WARN');
          this.LevelChip('ERROR', 'ERROR');
          Text('|')
            .fontSize(11)
            .fontColor(HmclTheme.OUTLINE)
            .margin({ left: 8, right: 8 });
          this.FileChip('实时日志', '');
          ForEach(this.files, (f: string) => {
            this.FileChip(f, f)
          }, (f: string) => f);
          if (this.crashFiles.length > 0) {
            Text('|')
              .fontSize(11)
              .fontColor(HmclTheme.OUTLINE)
              .margin({ left: 8, right: 8 });
            this.FileChip(`崩溃报告 ${this.crashFiles.length}`, '__crash__');
          }
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Auto)
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 8 })
  }

  @Builder
  LevelChip(label: string, value: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.minLevel === value ? HmclTheme.ON_SECONDARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
      .backgroundColor(this.minLevel === value ? HmclTheme.SECONDARY_CONTAINER : Color.Transparent)
      .borderRadius(10)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ right: 6 })
      .onClick(() => {
        this.minLevel = value;
        this.loadContent();
      })
  }

  @Builder
  FileChip(label: string, value: string) {
    Text(label)
      .fontSize(11)
      .fontColor(this.selected === value ? HmclTheme.ON_PRIMARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
      .backgroundColor(this.selected === value ? HmclTheme.PRIMARY_CONTAINER : HmclTheme.SURFACE_CONTAINER)
      .borderRadius(10)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .margin({ right: 6 })
      .onClick(() => {
        if (value === '__crash__') {
          this.showCrashList();
          return;
        }
        this.selected = value;
        this.message = '';
        this.loadContent();
      })
  }

  private showCrashList(): void {
    if (this.crashFiles.length === 0) {
      this.message = '没有崩溃报告（游戏目录/crash-reports）';
      return;
    }
    this.crashDetail = this.crashFiles[0];
  }

  @Builder
  CrashOverlay() {
    Column() {
      Row() {
        Text('崩溃报告')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE)
          .layoutWeight(1);
        Text('关闭')
          .fontSize(13)
          .fontColor(HmclTheme.PRIMARY)
          .onClick(() => {
            this.crashDetail = '';
          });
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 8 });

      Scroll() {
        Row() {
          ForEach(this.crashFiles, (f: string) => {
            Text(f)
              .fontSize(11)
              .fontColor(this.crashDetail === f ? HmclTheme.ON_PRIMARY_CONTAINER : HmclTheme.ON_SURFACE_VARIANT)
              .backgroundColor(this.crashDetail === f ? HmclTheme.PRIMARY_CONTAINER : HmclTheme.SURFACE_CONTAINER)
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.crashDetail = f;
              })
          }, (f: string) => f)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .width('100%')
      .padding({ left: 20, right: 20 });

      Scroll() {
        Text(this.crashText())
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(HmclTheme.ON_SURFACE)
          .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .padding(12)
      .margin({ top: 8, left: 20, right: 20 })
      .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
      .borderRadius(8);
    }
    .width('88%')
    .height('80%')
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOW)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  private crashText(): string {
    if (this.crashDetail.length === 0 || this.crashDetail === '__crash__') {
      return '';
    }
    const dir = GameDirectory.subPath(this.versionManager.getMinecraftDir(), 'crash-reports');
    const path = `${dir}/${this.crashDetail}`;
    if (!FileUtils.exists(path)) {
      return '（文件不存在）';
    }
    return FileUtils.readFile(path);
  }
}
