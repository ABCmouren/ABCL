/**
 * ModPage — 模组管理（真实读写 mods/ 目录）
 *
 * 2026-10 重写：原实现是 generateMockMods() 硬编码的 6 个假模组，
 * 完全不读文件系统，所以永远是那 6 个。
 * 现在：
 *   - 扫描 <mcDir>/mods/ 下所有 *.jar 与 *.jar.disabled
 *   - 启用 = .jar，禁用 = .jar.disabled（与 HMCL 一致，重命名实现）
 *   - 后台逐个解析 fabric.mod.json / META-INF/mods.toml / mcmod.info 补全名称与版本
 *   - 支持删除、详情查看、刷新、打开目录提示
 */
import { InstalledMod, ModManager, ModMetadata } from '../../core/game/ModManager';
import { VersionManager } from '../../core/game/VersionManager';
import { HmclTheme } from '../../theme/HmclTheme';
import { Logger, StringUtils } from '../../core/util/Utils';
import { AppStore } from '../../core/AppStore';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';

@Component
export default struct ModPage {
  @State mods: InstalledMod[] = [];
  @State isLoading: boolean = true;
  @State searchText: string = '';
  @State detail: InstalledMod | null = null;
  @State metaProgress: string = '';
  @State message: string = '';

  private versionManager = VersionManager.getInstance();
  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  private mcDir(): string {
    return this.versionManager.getMinecraftDir();
  }

  private reload(): void {
    this.isLoading = true;
    try {
      this.mods = ModManager.scan(this.mcDir());
      this.message = '';
    } catch (e) {
      this.message = '读取模组目录失败：' + (e as Error).message;
      Logger.error('ModPage', this.message);
    }
    this.isLoading = false;
    this.enrichMetadata();
  }

  /** 后台逐个补全元数据（只对未解析过的模组） */
  private enrichMetadata(): void {
    const pending: InstalledMod[] = this.mods.filter((m: InstalledMod) => !m.metaLoaded);
    if (pending.length === 0) {
      this.metaProgress = '';
      return;
    }
    const tempRoot = `${this.mcDir()}/.modmeta`;
    void (async () => {
      let done = 0;
      for (const mod of pending) {
        this.metaProgress = `解析元数据 ${done + 1}/${pending.length}：${mod.jarName}`;
        const meta: ModMetadata | null = await ModManager.readMetadata(mod, tempRoot);
        if (meta) {
          ModManager.applyMeta(mod, meta);
        } else {
          mod.metaLoaded = true;
        }
        done++;
        // 触发列表刷新
        this.mods = this.mods.slice();
      }
      this.metaProgress = '';
    })();
  }

  private visibleMods(): InstalledMod[] {
    if (this.searchText.length === 0) {
      return this.mods;
    }
    const q = this.searchText.toLowerCase();
    return this.mods.filter((m: InstalledMod) =>
      m.name.toLowerCase().indexOf(q) >= 0 || m.jarName.toLowerCase().indexOf(q) >= 0);
  }

  build() {
    Stack() {
      Column() {
        this.Header()
        this.Toolbar()

        if (this.isLoading) {
          LoadingView({ message: '扫描模组目录…' })
        } else if (this.mods.length === 0) {
          EmptyView({
            icon: '',
            message: '这个实例还没有安装模组',
            actionText: '刷新'
          })
        } else {
          List() {
            ForEach(this.visibleMods(), (mod: InstalledMod) => {
              ListItem() {
                this.ModRow(mod)
              }
            }, (mod: InstalledMod) => `${mod.path}|${mod.enabled ? '1' : '0'}|${mod.metaLoaded ? mod.name : ''}`)
          }
          .layoutWeight(1)
          .width('100%')
          .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 68 })
        }

        if (this.message.length > 0) {
          Text(this.message)
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
  Header() {
    Column() {
      Row() {
        Text('模组')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Text(` ${this.mods.length} 个`)
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

      Text(this.modsDirLabel())
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 });

      if (this.metaProgress.length > 0) {
        Text(this.metaProgress)
          .fontSize(11)
          .fontColor(HmclTheme.PRIMARY)
          .width('100%')
          .margin({ top: 4 });
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }

  private modsDirLabel(): string {
    return ModManager.modsDir(this.mcDir());
  }

  @Builder
  Toolbar() {
    Row() {
      TextInput({ placeholder: '搜索模组…', text: this.searchText })
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
  ModRow(mod: InstalledMod) {
    Row() {
      // 开关：点一下切换启用状态
      Stack() {
        Text(mod.enabled ? '✓' : '')
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER);
      }
      .width(22)
      .height(22)
      .borderRadius(6)
      .backgroundColor(mod.enabled ? HmclTheme.PRIMARY_CONTAINER : Color.Transparent)
      .border({ width: 1, color: mod.enabled ? HmclTheme.PRIMARY_CONTAINER : HmclTheme.OUTLINE })
      .margin({ right: 14 })
      .onClick(() => {
        const newName = ModManager.setEnabled(mod, !mod.enabled);
        mod.enabled = !mod.enabled;
        mod.fileName = newName;
        mod.path = ModManager.modsDir(this.mcDir()) + '/' + newName;
        this.mods = this.mods.slice();
      });

      Column() {
        Row() {
          Text(mod.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(mod.enabled ? HmclTheme.ON_SURFACE : HmclTheme.OUTLINE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (mod.version.length > 0) {
            Text(mod.version)
              .fontSize(11)
              .fontColor(HmclTheme.ON_SURFACE_VARIANT)
              .margin({ left: 6 });
          }
        }
        .width('100%');

        Row() {
          if (mod.loader.length > 0) {
            Text(mod.loader)
              .fontSize(10)
              .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
              .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ right: 6 });
          }
          if (!mod.enabled) {
            Text('已禁用')
              .fontSize(10)
              .fontColor(HmclTheme.ON_ERROR_CONTAINER)
              .backgroundColor(HmclTheme.ERROR_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ right: 6 });
          }
          Text(StringUtils.formatSize(mod.size))
            .fontSize(10)
            .fontColor(HmclTheme.OUTLINE);
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
          this.detail = mod;
        });

      Text('删除')
        .fontSize(12)
        .fontColor(HmclTheme.ERROR)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          ModManager.delete(mod);
          this.mods = ModManager.scan(this.mcDir());
        });
    }
    .width('100%')
    .height(60)
    .padding({ left: 20, right: 12 })
  }

  @Builder
  DetailOverlay() {
    Column() {
      Text(this.detail ? this.detail.name : '')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');
      Text(this.detail ? this.detail.jarName : '')
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .margin({ top: 4 });

      Divider().color(HmclTheme.OUTLINE_VARIANT).margin({ top: 12, bottom: 8 });

      this.DetailRow('版本', this.detail ? this.detail.version : '');
      this.DetailRow('作者', this.detail ? this.detail.authors : '');
      this.DetailRow('加载器', this.detail ? this.detail.loader : '');
      this.DetailRow('大小', this.detail ? StringUtils.formatSize(this.detail.size) : '');
      this.DetailRow('状态', this.detail ? (this.detail.enabled ? '已启用' : '已禁用') : '');
      this.DetailRow('元数据', this.detail ? (this.detail.metaLoaded ? '已解析' : '未解析') : '');

      if (this.detail && this.detail.description.length > 0) {
        Text(this.detail.description)
          .fontSize(12)
          .fontColor(HmclTheme.ON_SURFACE_VARIANT)
          .width('100%')
          .margin({ top: 10 });
      }

      Button('关闭')
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
        .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
        .borderRadius(10)
        .margin({ top: 18 })
        .onClick(() => {
          this.detail = null;
        });
    }
    .width(420)
    .padding(22)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width(70);
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
