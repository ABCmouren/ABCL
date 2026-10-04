/**
 * ModPage - Mod management page
 */

import { EmptyView, SearchBar, Card, SectionHeader } from '../../components/common/CommonComponents';

interface ModInfo {
  name: string;
  fileName: string;
  description: string;
  version: string;
  mcVersion: string;
  author: string;
  enabled: boolean;
  icon: string;
  size: number;
}

@Component
export default struct ModPage {
  @State private mods: ModInfo[] = [];
  @State private filteredMods: ModInfo[] = [];
  @State private isLoading: boolean = true;
  @State private searchText: string = '';
  @State private showDeleteConfirm: boolean = false;
  @State private deleteTargetIndex: number = -1;
  @State private showDetailIndex: number = -1;

  aboutToAppear(): void {
    this.loadMods();
  }

  private loadMods(): void {
    this.isLoading = true;
    setTimeout(() => {
      this.mods = this.generateMockMods();
      this.filteredMods = [...this.mods];
      this.isLoading = false;
    }, 400);
  }

  private generateMockMods(): ModInfo[] {
    return [
      {
        name: 'Sodium',
        fileName: 'sodium-fabric-0.5.8.jar',
        description: 'Modern rendering engine for Minecraft',
        version: '0.5.8',
        mcVersion: '1.20.4',
        author: 'CaffeineMC',
        enabled: true,
        icon: '🟢',
        size: 2457600
      },
      {
        name: 'Iris Shaders',
        fileName: 'iris-1.7.0.jar',
        description: 'Shader support for Minecraft',
        version: '1.7.0',
        mcVersion: '1.20.4',
        author: 'IrisShaders',
        enabled: true,
        icon: '🌈',
        size: 4194304
      },
      {
        name: 'Lithium',
        fileName: 'lithium-0.12.1.jar',
        description: 'Optimization mod for Minecraft server',
        version: '0.12.1',
        mcVersion: '1.20.4',
        author: 'CaffeineMC',
        enabled: true,
        icon: '🔋',
        size: 1048576
      },
      {
        name: 'JEI',
        fileName: 'jei-1.20.4-15.3.0.2.jar',
        description: 'Item and recipe viewer',
        version: '15.3.0.2',
        mcVersion: '1.20.4',
        author: 'mezz',
        enabled: false,
        icon: '📖',
        size: 7340032
      },
      {
        name: 'Mod Menu',
        fileName: 'modmenu-9.0.0.jar',
        description: 'Adds a mod menu to the game',
        version: '9.0.0',
        mcVersion: '1.20.4',
        author: 'TerraformersMC',
        enabled: true,
        icon: '📋',
        size: 524288
      },
      {
        name: 'AppleSkin',
        fileName: 'appleskin-2.5.1.jar',
        description: 'Shows food saturation/hunger values',
        version: '2.5.1',
        mcVersion: '1.20.4',
        author: 'squeek502',
        enabled: false,
        icon: '🍎',
        size: 262144
      }
    ];
  }

  private toggleMod(index: number): void {
    const mod = this.filteredMods[index];
    mod.enabled = !mod.enabled;
    // In real implementation: rename .jar to .jar.disabled or move to disabled folder
    this.filteredMods = [...this.filteredMods];
    this.mods = this.mods.map(m => m.fileName === mod.fileName ? mod : m);
  }

  private confirmDelete(index: number): void {
    this.deleteTargetIndex = index;
    this.showDeleteConfirm = true;
  }

  private executeDelete(): void {
    if (this.deleteTargetIndex >= 0 && this.deleteTargetIndex < this.filteredMods.length) {
      const mod = this.filteredMods[this.deleteTargetIndex];
      this.mods = this.mods.filter(m => m.fileName !== mod.fileName);
      this.filteredMods = this.filteredMods.filter((_, i) => i !== this.deleteTargetIndex);
    }
    this.showDeleteConfirm = false;
    this.deleteTargetIndex = -1;
  }

  private openModsFolder(): void {
    console.info('Opening mods folder...');
  }

  private onSearch(text: string): void {
    this.searchText = text;
    if (text.length === 0) {
      this.filteredMods = [...this.mods];
    } else {
      const query = text.toLowerCase();
      this.filteredMods = this.mods.filter(mod =>
        mod.name.toLowerCase().includes(query) ||
        mod.description.toLowerCase().includes(query) ||
        mod.author.toLowerCase().includes(query)
      );
    }
  }

  private formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1048576).toFixed(1)} MB`;
  }

  build() {
    Stack() {
      Column() {
        // Header
        Row() {
          Text('Mods')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A');
          Blank();
          Button({ type: ButtonType.Normal }) {
            Text('📂')
              .fontSize(18);
          }
          .width(36)
          .height(36)
          .backgroundColor('#F0F0F0')
          .borderRadius(18)
          .margin({ right: 8 })
          .onClick(() => this.openModsFolder());
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 });

        // Search bar
        SearchBar({ onSearch: (text: string) => this.onSearch(text) })
          .padding({ left: 16, right: 16, bottom: 8 });

        // Stats bar
        Row() {
          Text(`${this.filteredMods.length} mods`)
            .fontSize(13)
            .fontColor('#999999');
          Text(` (${this.mods.filter(m => m.enabled).length} enabled)`)
            .fontSize(13)
            .fontColor('#107C10');
          Blank();
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 });

        // Mod list
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
              .color('#5C6BC0');
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center);
        } else if (this.filteredMods.length === 0) {
          EmptyView({
            message: this.searchText.length > 0 ? 'No mods match your search' : 'No mods installed',
            actionText: 'Open Mods Folder'
          });
        } else {
          List() {
            ForEach(this.filteredMods, (mod: ModInfo, index: number) => {
              ListItem() {
                this.ModItemComponent(mod, index);
              }
            }, (mod: ModInfo) => mod.fileName);
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: '#E8E8E8', startMargin: 16, endMargin: 16 });
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FBF8FF');

      // Delete confirmation dialog
      if (this.showDeleteConfirm) {
        Column() {
          Column() {
            Text('Delete Mod')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A1A')
              .margin({ bottom: 8 });

            Text('Are you sure you want to delete this mod?')
              .fontSize(14)
              .fontColor('#666666')
              .margin({ bottom: 20 });

            Row() {
              Button('Cancel')
                .height(36)
                .backgroundColor('#F0F0F0')
                .fontColor('#666666')
                .fontSize(14)
                .borderRadius(6)
                .layoutWeight(1)
                .margin({ right: 8 })
                .onClick(() => {
                  this.showDeleteConfirm = false;
                });

              Button('Delete')
                .height(36)
                .backgroundColor('#D83B01')
                .fontColor(Color.White)
                .fontSize(14)
                .borderRadius(6)
                .layoutWeight(1)
                .onClick(() => this.executeDelete());
            }
            .width('100%');
          }
          .width('80%')
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .shadow({
            radius: 8,
            color: '#33000000',
            offsetX: 0,
            offsetY: 4
          });
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder ModItemComponent(mod: ModInfo, index: number) {
    Row() {
      // Mod icon
      Text(mod.icon)
        .fontSize(28);

      // Mod info
      Column() {
        Row() {
          Text(mod.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A');
          Text(` v${mod.version}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 4 });
        }
        .alignItems(VerticalAlign.Center);

        Text(mod.description)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 1 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Row() {
          Text(mod.author)
            .fontSize(11)
            .fontColor('#999999');
          Text(` | ${this.formatFileSize(mod.size)}`)
            .fontSize(11)
            .fontColor('#999999')
            .margin({ left: 8 });
          Text(` | ${mod.mcVersion}`)
            .fontSize(11)
            .fontColor('#999999')
            .margin({ left: 8 });
        }
        .margin({ top: 2 });
      }
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      // Enable/disable toggle
      Toggle({ type: ToggleType.Switch, isOn: mod.enabled })
        .width(36)
        .height(20)
        .onChange(() => this.toggleMod(index));
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White);
  }
}