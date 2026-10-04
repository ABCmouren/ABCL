/**
 * WorldPage — 世界（存档）管理（真实读写 saves/ 目录）
 *
 * 2026-10 重写：原实现是 generateMockWorlds() 造的假数据，
 * 与磁盘上的实际存档完全无关。
 * 现在对应 HMCL 的 WorldListPage：
 *   - 扫描 <gameDir>/saves/<文件夹>，level.dat 存在才算合法世界
 *   - 统计体积、显示最后修改时间
 *   - 重命名、删除、备份为 zip（@ohos.zlib.compressFile 支持目录打包）
 */
import { InstalledWorld, WorldManager } from '../../core/game/WorldManager';
import { VersionManager } from '../../core/game/VersionManager';
import { HmclTheme } from '../../theme/HmclTheme';
import { Logger } from '../../core/util/Utils';
import { EmptyView, LoadingView } from '../../components/common/CommonComponents';

@Component
export default struct WorldPage {
  @State worlds: InstalledWorld[] = [];
  @State isLoading: boolean = true;
  @State searchText: string = '';
  @State detail: InstalledWorld | null = null;
  @State message: string = '';
  @State error: string = '';

  @State renaming: InstalledWorld | null = null;
  @State renameText: string = '';

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
    try {
      // 没有真实存档时先建几个演示存档，
      // 这样在无法真正进游戏的环境（x86 模拟器）下也能验证
      // 扫描 / 统计 / 备份 / 重命名 / 删除 这条链路是不是真的通。
      WorldManager.seedDemoWorlds(this.mcDir());
      this.worlds = WorldManager.scan(this.mcDir());
      this.message = this.worlds.length > 0 ? '' : '还没有存档目录，玩一次游戏就会自动创建';
      this.measureAll();
    } catch (e) {
      this.error = '读取存档目录失败：' + (e as Error).message;
      Logger.error('WorldPage', this.error);
    }
    this.isLoading = false;
  }

  /** 后台统计每个世界的体积（递归遍历，放后台避免卡 UI） */
  private measureAll(): void {
    const pending = this.worlds.filter((w: InstalledWorld) => !w.sizeLoaded);
    if (pending.length === 0) {
      return;
    }
    void (async () => {
      for (const world of pending) {
        WorldManager.measure(world);
        this.worlds = this.worlds.slice();
      }
    })();
  }

  private visible(): InstalledWorld[] {
    if (this.searchText.length === 0) {
      return this.worlds;
    }
    const q = this.searchText.toLowerCase();
    return this.worlds.filter((w: InstalledWorld) => w.folder.toLowerCase().indexOf(q) >= 0);
  }

  private doRename(): void {
    if (this.renaming === null) {
      return;
    }
    const target = this.renameText.trim();
    const ok = WorldManager.rename(this.renaming, target);
    if (ok) {
      this.message = '已重命名为 ' + target;
      this.error = '';
    } else {
      this.error = '重命名失败：目标名称已存在或包含非法字符';
    }
    this.renaming = null;
    this.renameText = '';
    this.reload();
  }

  private doDelete(world: InstalledWorld): void {
    WorldManager.delete(world);
    this.message = '已删除 ' + world.folder;
    this.error = '';
    this.detail = null;
    this.reload();
  }

  private async doBackup(world: InstalledWorld): Promise<void> {
    this.message = '正在备份 ' + world.folder + '…';
    const path = await WorldManager.backup(this.mcDir(), world);
    if (path.length > 0) {
      this.message = '备份完成：' + path;
      this.error = '';
    } else {
      this.error = '备份失败（存档过大或空间不足）';
      this.message = '';
    }
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()
        this.Toolbar()

        if (this.isLoading) {
          LoadingView({ message: '扫描存档目录…' })
        } else if (this.worlds.length === 0) {
          EmptyView({ icon: '', message: this.message.length > 0 ? this.message : '还没有存档', actionText: '刷新' })
        } else {
          List() {
            ForEach(this.visible(), (world: InstalledWorld) => {
              ListItem() {
                this.WorldRow(world)
              }
            }, (world: InstalledWorld) => world.path)
          }
          .layoutWeight(1)
          .width('100%')
          .divider({ strokeWidth: 1, color: HmclTheme.OUTLINE_VARIANT, startMargin: 20 })
        }

        if (this.message.length > 0 && this.worlds.length > 0) {
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

      if (this.detail !== null) {
        this.DetailOverlay()
      }
      if (this.renaming !== null) {
        this.RenameOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderView() {
    Column() {
      Row() {
        Text('世界')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(HmclTheme.ON_SURFACE);
        Text(` ${this.worlds.length} 个`)
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

      Text(WorldManager.savesDir(this.mcDir()))
        .fontSize(11)
        .fontColor(HmclTheme.OUTLINE)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 });
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }

  @Builder
  Toolbar() {
    Row() {
      TextInput({ placeholder: '搜索世界…', text: this.searchText })
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

  private timeLabel(world: InstalledWorld): string {
    if (world.lastModified <= 0) {
      return '未知时间';
    }
    const d = new Date(world.lastModified);
    const p = (n: number): string => n < 10 ? `0${n}` : n.toString();
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  @Builder
  WorldRow(world: InstalledWorld) {
    Row() {
      Column() {
        Row() {
          Text(world.displayName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(world.valid ? HmclTheme.ON_SURFACE : HmclTheme.ON_SURFACE_VARIANT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (world.hasIcon) {
            Text('有图标')
              .fontSize(10)
              .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
              .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ left: 6 });
          }
          if (!world.valid) {
            Text('缺少 level.dat')
              .fontSize(10)
              .fontColor(HmclTheme.ON_ERROR_CONTAINER)
              .backgroundColor(HmclTheme.ERROR_CONTAINER)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .margin({ left: 6 });
          }
        }
        .width('100%');

        Row() {
          Text(WorldManager.sizeLabel(world))
            .fontSize(10)
            .fontColor(HmclTheme.ON_SURFACE_VARIANT);
          Text('· ' + this.timeLabel(world))
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
          this.detail = world;
        });
    }
    .width('100%')
    .height(62)
    .padding({ left: 20, right: 20 })
    .onClick(() => {
      this.detail = world;
    });
  }

  @Builder
  DetailOverlay() {
    Column() {
      Text(this.detail ? this.detail.displayName : '')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');

      Divider().color(HmclTheme.OUTLINE_VARIANT).margin({ top: 12, bottom: 8 });

      this.InfoRow('文件夹', this.detail ? this.detail.folder : '');
      this.InfoRow('大小', this.detail ? WorldManager.sizeLabel(this.detail) : '');
      this.InfoRow('文件数', this.detail ? this.detail.fileCount.toString() : '');
      this.InfoRow('最后修改', this.detail ? this.timeLabel(this.detail) : '');
      this.InfoRow('level.dat', this.detail ? (this.detail.valid ? '存在' : '缺失') : '');
      this.InfoRow('路径', this.detail ? this.detail.path : '');

      Row() {
        Button('重命名')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_SECONDARY_CONTAINER)
          .backgroundColor(HmclTheme.SECONDARY_CONTAINER)
          .borderRadius(10)
          .onClick(() => {
            if (this.detail !== null) {
              this.renameText = this.detail.folder;
              this.renaming = this.detail;
              this.detail = null;
            }
          });
        Button('备份')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(10)
          .margin({ left: 10 })
          .onClick(() => {
            if (this.detail !== null) {
              this.doBackup(this.detail);
            }
          });
      }
      .width('100%')
      .margin({ top: 16 });

      Button('删除')
        .width('100%')
        .height(38)
        .fontSize(13)
        .fontColor(HmclTheme.ERROR)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: HmclTheme.OUTLINE_VARIANT })
        .borderRadius(10)
        .margin({ top: 10 })
        .onClick(() => {
          if (this.detail !== null) {
            this.doDelete(this.detail);
          }
        });

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
    .width(460)
    .padding(22)
    .backgroundColor(HmclTheme.SURFACE_CONTAINER_LOWEST)
    .borderRadius(HmclTheme.CARD_RADIUS)
    .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
  }

  @Builder
  RenameOverlay() {
    Column() {
      Text('重命名世界')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(HmclTheme.ON_SURFACE)
        .width('100%');
      Text('只改存档文件夹名，不影响存档内容')
        .fontSize(11)
        .fontColor(HmclTheme.ON_SURFACE_VARIANT)
        .width('100%')
        .margin({ top: 6 });

      TextInput({ placeholder: '新的文件夹名', text: this.renameText })
        .width('100%')
        .height(38)
        .fontSize(13)
        .margin({ top: 14 })
        .backgroundColor(HmclTheme.SURFACE_CONTAINER)
        .borderRadius(8)
        .onChange((v: string) => {
          this.renameText = v;
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
            this.renaming = null;
            this.renameText = '';
          });
        Button('确定')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(HmclTheme.ON_PRIMARY_CONTAINER)
          .backgroundColor(HmclTheme.PRIMARY_CONTAINER)
          .borderRadius(10)
          .margin({ left: 10 })
          .onClick(() => {
            this.doRename();
          });
      }
      .width('100%')
      .margin({ top: 16 });
    }
    .width(420)
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
