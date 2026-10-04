/**
 * PackPage — 资源包 / 光影包管理（同一套 UI，按 kind 复用）
 *
 * 对应 HMCL 的 ResourcePackListPage / ShaderPackListPage：
 * 列表来自 <gameDir>/resourcepacks 或 <gameDir>/shaderpacks，
 * 支持启用/禁用（.disabled 重命名）、删除、查看 pack.mcmeta 描述。
 */
import { InstalledPack, PackKind, ResourcePackManager } from '../../core/game/ResourcePackManager';
import { VersionManager } from '../../core/game/VersionManager';
import { HmclTheme } from '../../theme/HmclTheme';
import { FileUtils, Logger, StringUtils } from '../../core/util/Utils';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';

@Component
export default struct PackPage {
  /** 'resourcepack' | 'shader' */
  @Prop kind: string = 'resourcepack';

  @State packs: InstalledPack[] = [];
  @State isLoading: boolean = true;
  @State searchText: string = '';
  @State detail: InstalledPack | null = null;
  @State metaProgress: string = '';
  @State message: string = '';

  private versionManager = VersionManager.getInstance();

  aboutToAppear(): void {
    this.reload();
  }

  private packKind(): PackKind {
    return this.kind === 'shader' ? PackKind.SHADER : PackKind.RESOURCE;
  }

  private title(): string {
    return this.kind === 'shader' ? '光影包' : '资源包';
  }

  private mcDir(): string {
    return this.versionManager.getMinecraftDir();
  }

  private reload(): void {
    this.isLoading = true;
    try {
      this.packs = ResourcePackManager.scan(this.mcDir(), this.packKind());
      this.message = '';
    } catch (e) {
      this.message = '读取目录失败：' + (e as Error).message;
      Logger.error('PackPage', this.message);
    }
    this.isLoading = false;
    this.enrich();
  }

  private enrich(): void {
    const pending: InstalledPack[] = this.packs.filter((p: InstalledPack) => !p.metaLoaded);
    if (pending.length === 0) {
      this.metaProgress = '';
      return;
    }
    const tempRoot = `${this.mcDir()}/.packmeta`;
    void (async () => {
      let done = 0;
      for (const pack of pending) {
        this.metaProgress = `解析描述 ${done + 1}/${pending.length}：${pack.baseName}`;
        const desc = await ResourcePackManager.readDescription(pack, tempRoot);
        pack.description = desc;
        pack.metaLoaded = true;
        done++;
        this.packs = this.packs.slice();
      }
      this.metaProgress = '';
      FileUtils.delete(tempRoot);
    })();
  }

  private visible(): InstalledPack[] {
    if (this.searchText.length === 0) {
      return this.packs;
    }
    const q = this.searchText.toLowerCase();
    return this.packs.filter((p: InstalledPack) =>
      p.baseName.toLowerCase().indexOf(q) >= 0 || p.description.toLowerCase().indexOf(q) >= 0);
  }

  build() {
    Stack() {
      Column() {
        this.Header()
        this.Toolbar()

        if (this.isLoading) {
          LoadingView({ message: `扫描${this.title()}目录…` });
        } else if (this.packs.length === 0) {
          EmptyView({
            icon: '',
            message: `还没有${this.title()}`,
            actionText: '刷新'
          });
        } else {
          List() {
            ForEach(this.visible(), (pack: InstalledPack) => {
              ListItem() {
                this.PackRow(pack)
              }
            }, (pack: InstalledPack) => `${pack.path}|${pack.enabled ? '1' : '0'}|${pack.metaLoaded ? pack.description : ''}`)
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
        Text(this.title())
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

      Text(ResourcePackManager.packDir(this.mcDir(), this.packKind()))
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

  @Builder
  Toolbar() {
    Row() {
      TextInput({ placeholder: `搜索${this.title()}…`, text: this.searchText })
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
  PackRow(pack: InstalledPack) {
    Row() {
      Stack() {
        Text(pack.enabled ? '✓' : '')
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER);
      }
      .width(22)
      .height(22)
      .borderRadius(6)
      .backgroundColor(pack.enabled ? HmclTheme.PRIMARY_CONTAINER : Color.Transparent)
      .border({ width: 1, color: pack.enabled ? HmclTheme.PRIMARY_CONTAINER : HmclTheme.OUTLINE })
      .margin({ right: 14 })
      .onClick(() => {
        const newName = ResourcePackManager.setEnabled(pack, !pack.enabled);
        pack.enabled = !pack.enabled;
        pack.fileName = newName;
        pack.path = ResourcePackManager.packDir(this.mcDir(), this.packKind()) + '/' + newName;
        this.packs = this.packs.slice();
      });

      Column() {
        Row() {
          Text(pack.baseName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(pack.enabled ? HmclTheme.ON_SURFACE : HmclTheme.OUTLINE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(pack.isDirectory ? '文件夹' : 'zip')
            .fontSize(10)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT)
            .margin({ left: 6 });
        }
        .width('100%');

        Row() {
          if (!pack.enabled) {
            Text('已禁用')
              .fontSize(10)
              .fontColor(HmclTheme.ON_ERROR_CONTAINER)
              .backgroundColor(HmclTheme.ERROR_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ right: 6 });
          }
          Text(pack.description.length > 0 ? pack.description : '—')
            .fontSize(10)
            .fontColor(HmclTheme.OUTLINE)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text(pack.size > 0 ? StringUtils.formatSize(pack.size) : '')
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
        });

      Text('删除')
        .fontSize(12)
        .fontColor(HmclTheme.ERROR)
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          ResourcePackManager.delete(pack);
          this.packs = ResourcePackManager.scan(this.mcDir(), this.packKind());
        });
    }
    .width('100%')
    .height(62)
    .padding({ left: 20, right: 12 })
  }

  @Builder
  DetailOverlay() {
    Column() {
      Text(this.detail ? this.detail.baseName : '')
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

      this.DetailRow('类型', this.title());
      this.DetailRow('形态', this.detail ? (this.detail.isDirectory ? '文件夹' : 'zip') : '');
      this.DetailRow('大小', this.detail ? StringUtils.formatSize(this.detail.size) : '');
      this.DetailRow('状态', this.detail ? (this.detail.enabled ? '已启用' : '已禁用') : '');
      this.DetailRow('描述', this.detail ? this.detail.description : '');
      this.DetailRow('路径', this.detail ? this.detail.path : '');

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
    .width(460)
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
        .width(60);
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
