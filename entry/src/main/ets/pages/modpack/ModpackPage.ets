/**
 * ModpackPage — 整合包管理（真实读写 modpacks/ 目录）
 *
 * 2026-10 重写：原实现是 generateMockModpacks() 造的假数据。
 * 现在对应 HMCL 的 ModpackPage：
 *   - 扫描 modpacks/ 下所有 .zip
 *   - 解压后识别 CurseForge(manifest.json) 与 Modrinth(modrinth.index.json) 两种清单
 *   - 展示 MC 版本 / 加载器 / 文件数 / 作者
 *   - 支持删除；「安装到实例」把内容铺进目标游戏目录
 */
import { InstalledModpack, ModpackManager } from '../../core/modplatform/ModpackManager';
import { VersionManager } from '../../core/game/VersionManager';
import { HmclTheme } from '../../theme/HmclTheme';
import { FileUtils, Logger, StringUtils } from '../../core/util/Utils';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';

@Component
export default struct ModpackPage {
  @State packs: InstalledModpack[] = [];
  @State isLoading: boolean = true;
  @State searchText: string = '';
  @State detail: InstalledModpack | null = null;
  @State parseNote: string = '';
  @State error: string = '';

  @State applying: boolean = false;
  @State applyNote: string = '';

  private versionManager = VersionManager.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  private mcDir(): string {
    return this.versionManager.getMinecraftDir();
  }

  private reload(): void {
    this.isLoading = true;
    this.error = '';
    // ⚠️ 顺序很重要：seedDemoModpacks 是异步的（要等 zlib 打包完成），
    // 必须 await 之后再 scan，否则 scan 跑在 zip 落盘之前，列表还是空的。
    void (async () => {
      try {
        const seeded: number = await ModpackManager.seedDemoModpacks(this.mcDir());
        this.packs = ModpackManager.scan(this.mcDir());
        this.parseNote = this.packs.length > 0
          ? ''
          : '还没有整合包。可在「下载 → 整合包」Tab 下载，或把 .zip 放进 modpacks/ 目录。';
        this.isLoading = false;
        this.parseAll();
      } catch (e) {
        this.error = '读取整合包目录失败：' + (e as Error).message;
        Logger.error('ModpackPage', this.error);
        this.isLoading = false;
      }
    })();
  }

  /** 逐个解压解析清单（后台进行，大包可能稍慢） */
  private parseAll(): void {
    const pending = this.packs.filter((p: InstalledModpack) => !p.metaLoaded);
    if (pending.length === 0) {
      return;
    }
    const root = `${this.mcDir()}/.modpack-tmp`;
    void (async () => {
      for (const pack of pending) {
        this.parseNote = `解析 ${pack.fileName}…`;
        const info = await ModpackManager.inspect(pack, root);
        pack.info = info;
        pack.metaLoaded = true;
        this.packs = this.packs.slice();
      }
      this.parseNote = '';
      FileUtils.delete(root);
    })();
  }

  private visible(): InstalledModpack[] {
    if (this.searchText.length === 0) {
      return this.packs;
    }
    const q = this.searchText.toLowerCase();
    return this.packs.filter((p: InstalledModpack) => {
      const name = p.info !== null ? p.info.name.toLowerCase() : '';
      return p.fileName.toLowerCase().indexOf(q) >= 0 || name.indexOf(q) >= 0;
    });
  }

  private packTitle(pack: InstalledModpack): string {
    if (pack.info !== null && pack.info.name.length > 0) {
      return pack.info.name;
    }
    return pack.fileName.replace(/\.zip$/i, '');
  }

  private packSubtitle(pack: InstalledModpack): string {
    if (!pack.metaLoaded) {
      return '解析中…';
    }
    if (pack.info === null) {
      return '无法识别的格式';
    }
    const bits: string[] = [];
    if (pack.info.format === 'curseforge') {
      bits.push('CurseForge');
    } else if (pack.info.format === 'modrinth') {
      bits.push('Modrinth');
    }
    if (pack.info.minecraftVersion.length > 0) {
      bits.push('MC ' + pack.info.minecraftVersion);
    }
    if (pack.info.loader.length > 0) {
      bits.push(pack.info.loader + ' ' + pack.info.loaderVersion);
    }
    if (pack.info.fileCount > 0) {
      bits.push(pack.info.fileCount + ' 个文件');
    }
    if (pack.info.author.length > 0) {
      bits.push(pack.info.author);
    }
    return bits.length > 0 ? bits.join(' · ') : pack.info.summary;
  }

  private applyToInstance(): void {
    if (this.detail === null || this.detail.info === null) {
      return;
    }
    this.applying = true;
    this.applyNote = '正在解压并应用整合包…';
    const pack = this.detail;
    const root = `${this.mcDir()}/.modpack-tmp`;
    void (async () => {
      const info = await ModpackManager.inspect(pack, root);
      if (info === null) {
        this.applyNote = '解析失败，无法应用';
        this.applying = false;
        return;
      }
      const extractDir = root + '/mp-' + Math.abs(ModpackManager.hashOf(pack.fileName));
      const n = ModpackManager.applyOverrides(info, extractDir, this.mcDir());
      FileUtils.delete(root);
      this.applyNote = '已应用 ' + n + ' 项到当前游戏目录';
      this.applying = false;
      this.detail = null;
    })();
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()
        this.Toolbar()

        if (this.isLoading) {
          LoadingView({ message: '扫描整合包目录…' })
        } else if (this.packs.length === 0) {
          EmptyView({ icon: '', message: this.parseNote.length > 0 ? this.parseNote : '还没有整合包', actionText: '刷新' })
        } else {
          List() {
            ForEach(this.visible(), (pack: InstalledModpack) => {
              ListItem() {
                this.PackRow(pack)
              }
            }, (pack: InstalledModpack) => `${pack.path}|${pack.metaLoaded ? '1' : '0'}`)
          }
          .layoutWeight(1)
          .width('100%')
          .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
        }

        if (this.applyNote.length > 0) {
          Text(this.applyNote)
            .fontSize(12)
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

      if (this.detail !== null) {
        this.DetailOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderView() {
    Column() {
      Row() {
        Text('整合包')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Text(` ${this.packs.length} 个`)
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

      Text(ModpackManager.modpacksDir(this.mcDir()))
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 });

      if (this.parseNote.length > 0) {
        Text(this.parseNote)
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .width('100%')
          .margin({ top: 4 });
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }

  @Builder
  Toolbar() {
    Row() {
      TextInput({ placeholder: '搜索整合包…', text: this.searchText })
        .layoutWeight(1)
        .height(34)
        .fontSize(13)
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(8)
        .onChange((v: string) => {
          this.searchText = v;
        });
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 8 })
  }

  @Builder
  PackRow(pack: InstalledModpack) {
    Row() {
      Column() {
        Text(this.packTitle(pack))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(HmclTheme.ON_SURFACE)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');

        Row() {
          Text(this.packSubtitle(pack))
            .fontSize(11)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(StringUtils.formatSize(pack.sizeBytes))
            .fontSize(10)
            .fontColor(HmclTheme.OUTLINE)
            .margin({ left: 6 });
        }
        .width('100%')
        .margin({ top: 3 });
      }
      .layoutWeight(1);

      Text('详情')
        .fontSize(12)
        .fontColor(HmclTheme.PRIMARY)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          this.detail = pack;
          this.applyNote = '';
        });

      Text('删除')
        .fontSize(12)
        .fontColor(HmclTheme.ERROR)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          ModpackManager.delete(pack);
          this.packs = ModpackManager.scan(this.mcDir());
        });
    }
    .width('100%')
    .height(64)
    .padding({ left: 20, right: 12 })
  }

  @Builder
  DetailOverlay() {
    Column() {
      Text(this.detail ? this.packTitle(this.detail) : '')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');
      Text(this.detail ? this.detail.fileName : '')
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .margin({ top: 4 });

      Divider().color(HmclTheme.OUTLINE_VARIANT).margin({ top: 12, bottom: 8 });

      this.InfoRow('格式', this.detail && this.detail.info !== null ? this.detail.info.format : '未识别');
      this.InfoRow('MC 版本', this.detail && this.detail.info !== null ? this.detail.info.minecraftVersion : '');
      this.InfoRow('加载器', this.detail && this.detail.info !== null
        ? `${this.detail.info.loader} ${this.detail.info.loaderVersion}` : '');
      this.InfoRow('作者', this.detail && this.detail.info !== null ? this.detail.info.author : '');
      this.InfoRow('版本', this.detail && this.detail.info !== null ? this.detail.info.version : '');
      this.InfoRow('声明文件', this.detail && this.detail.info !== null
        ? this.detail.info.fileCount.toString() : '');
      this.InfoRow('含 overrides', this.detail && this.detail.info !== null
        ? (this.detail.info.hasOverrides ? '是' : '否') : '');
      this.InfoRow('大小', this.detail ? StringUtils.formatSize(this.detail.sizeBytes) : '');
      this.InfoRow('路径', this.detail ? this.detail.path : '');

      if (this.applying) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(HmclTheme.PRIMARY_CONTAINER)
          .margin({ top: 14 });
      } else {
        Button('安装到当前实例')
          .width('100%')
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(10)
          .margin({ top: 16 })
          .onClick(() => {
            this.applyToInstance();
          });
      }

      Button('关闭')
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(10)
        .margin({ top: 10 })
        .onClick(() => {
          this.detail = null;
        });
    }
    .width(470)
    .padding(22)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width(80);
      Text(value.length > 0 ? value : '—')
        .fontSize(12)
        .fontColor(HmclTheme.ON_SURFACE)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
  }
}
