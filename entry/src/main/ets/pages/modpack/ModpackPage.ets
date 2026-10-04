/**
 * ModpackPage - Modpack management page
 */

import { EmptyView, SearchBar, Card, SectionHeader, ProgressBar } from '../../components/common/CommonComponents';

interface ModpackInfo {
  name: string;
  version: string;
  author: string;
  description: string;
  mcVersion: string;
  modLoader: string;
  modCount: number;
  icon: string;
  source: string; // CurseForge, Modrinth, MultiMC
  installStatus: InstallStatus;
  installProgress: number;
}

enum InstallStatus {
  NOT_INSTALLED = 'not_installed',
  INSTALLING = 'installing',
  INSTALLED = 'installed',
  UPDATE_AVAILABLE = 'update_available',
  FAILED = 'failed'
}

@Component
export default struct ModpackPage {
  @State private modpacks: ModpackInfo[] = [];
  @State private filteredModpacks: ModpackInfo[] = [];
  @State private isLoading: boolean = true;
  @State private searchText: string = '';
  @State private showDetail: boolean = false;
  @State private selectedIndex: number = -1;
  @State private showImportPicker: boolean = false;

  aboutToAppear(): void {
    this.loadModpacks();
  }

  private loadModpacks(): void {
    this.isLoading = true;
    setTimeout(() => {
      this.modpacks = this.generateMockModpacks();
      this.filteredModpacks = [...this.modpacks];
      this.isLoading = false;
    }, 400);
  }

  private generateMockModpacks(): ModpackInfo[] {
    return [
      {
        name: 'All the Mods 9',
        version: '0.2.0',
        author: 'AllTheMods',
        description: 'Over 400 mods in a massive kitchen-sink pack',
        mcVersion: '1.20.1',
        modLoader: 'Forge',
        modCount: 420,
        icon: '📦',
        source: 'CurseForge',
        installStatus: InstallStatus.INSTALLED,
        installProgress: 1
      },
      {
        name: 'Better MC [Fabric]',
        version: '1.20.4',
        author: 'BetterMC Team',
        description: 'Enhanced vanilla experience with performance and quality of life mods',
        mcVersion: '1.20.4',
        modLoader: 'Fabric',
        modCount: 180,
        icon: '✨',
        source: 'CurseForge',
        installStatus: InstallStatus.UPDATE_AVAILABLE,
        installProgress: 1
      },
      {
        name: 'SkyFactory 5',
        version: '1.0.0',
        author: 'Darkosto',
        description: 'Skyblock-style modpack with tech and magic',
        mcVersion: '1.20.1',
        modLoader: 'NeoForge',
        modCount: 280,
        icon: '☁️',
        source: 'Modrinth',
        installStatus: InstallStatus.NOT_INSTALLED,
        installProgress: 0
      },
      {
        name: 'Prominence II',
        version: '2.3.1',
        author: 'Prominence Team',
        description: 'RPG-themed modpack with custom quests',
        mcVersion: '1.20.1',
        modLoader: 'Forge',
        modCount: 320,
        icon: '⚔️',
        source: 'CurseForge',
        installStatus: InstallStatus.NOT_INSTALLED,
        installProgress: 0
      },
      {
        name: 'Create: Above and Beyond',
        version: '1.0.5',
        author: 'Create Mod Team',
        description: 'Factory automation with Create mod',
        mcVersion: '1.18.2',
        modLoader: 'Forge',
        modCount: 120,
        icon: '⚙️',
        source: 'MultiMC',
        installStatus: InstallStatus.INSTALLED,
        installProgress: 1
      }
    ];
  }

  private installModpack(index: number): void {
    const modpack = this.filteredModpacks[index];
    modpack.installStatus = InstallStatus.INSTALLING;
    modpack.installProgress = 0;
    this.filteredModpacks = [...this.filteredModpacks];

    // Simulate installation progress
    let progress = 0;
    const interval = setInterval(() => {
      progress += Math.random() * 0.12;
      if (progress >= 1) {
        progress = 1;
        clearInterval(interval);
        modpack.installStatus = InstallStatus.INSTALLED;
        modpack.installProgress = 1;
        this.filteredModpacks = [...this.filteredModpacks];
        // Update the main list too
        this.modpacks = this.modpacks.map(m =>
          m.name === modpack.name ? modpack : m
        );
      } else {
        modpack.installProgress = progress;
        this.filteredModpacks = [...this.filteredModpacks];
      }
    }, 400);
  }

  private updateModpack(index: number): void {
    // Same as install but with update logic
    this.installModpack(index);
  }

  private importModpack(): void {
    console.info('Opening file picker for modpack import...');
    this.showImportPicker = false;
    // In real implementation: open file dialog for .zip, .mrpack, .txt files
  }

  private viewDetails(index: number): void {
    this.selectedIndex = index;
    this.showDetail = true;
  }

  private onSearch(text: string): void {
    this.searchText = text;
    if (text.length === 0) {
      this.filteredModpacks = [...this.modpacks];
    } else {
      const query = text.toLowerCase();
      this.filteredModpacks = this.modpacks.filter(mp =>
        mp.name.toLowerCase().includes(query) ||
        mp.author.toLowerCase().includes(query) ||
        mp.description.toLowerCase().includes(query) ||
        mp.source.toLowerCase().includes(query)
      );
    }
  }

  private getStatusLabel(status: InstallStatus): string {
    switch (status) {
      case InstallStatus.NOT_INSTALLED: return 'Install';
      case InstallStatus.INSTALLING: return 'Installing...';
      case InstallStatus.INSTALLED: return 'Installed';
      case InstallStatus.UPDATE_AVAILABLE: return 'Update';
      case InstallStatus.FAILED: return 'Failed';
      default: return 'Unknown';
    }
  }

  private getStatusColor(status: InstallStatus): ResourceColor {
    switch (status) {
      case InstallStatus.NOT_INSTALLED: return '#5C6BC0';
      case InstallStatus.INSTALLING: return '#FF8C00';
      case InstallStatus.INSTALLED: return '#107C10';
      case InstallStatus.UPDATE_AVAILABLE: return '#D83B01';
      case InstallStatus.FAILED: return '#D83B01';
      default: return '#666666';
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('Modpacks')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A');
        Blank();
        Button({ type: ButtonType.Normal }) {
          Text('+ Import')
            .fontSize(13)
            .fontColor('#5C6BC0')
            .fontWeight(FontWeight.Medium);
        }
        .height(32)
        .backgroundColor('#E8F4FD')
        .borderRadius(16)
        .padding({ left: 12, right: 12 })
        .onClick(() => this.importModpack());
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 });

      // Search bar
      SearchBar({ onSearch: (text: string) => this.onSearch(text) })
        .padding({ left: 16, right: 16, bottom: 8 });

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
      } else if (this.filteredModpacks.length === 0) {
        EmptyView({
          message: this.searchText.length > 0 ? 'No modpacks match your search' : 'No modpacks installed',
          actionText: 'Import Modpack'
        });
      } else {
        if (this.showDetail && this.selectedIndex >= 0) {
          this.ModpackDetailView(this.filteredModpacks[this.selectedIndex]);
        } else {
          List() {
            ForEach(this.filteredModpacks, (modpack: ModpackInfo, index: number) => {
              ListItem() {
                this.ModpackItemComponent(modpack, index);
              }
            }, (modpack: ModpackInfo) => modpack.name + modpack.version);
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: '#E8E8E8', startMargin: 16, endMargin: 16 });
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FBF8FF');
  }

  @Builder ModpackItemComponent(modpack: ModpackInfo, index: number) {
    Row() {
      // Modpack icon
      Text(modpack.icon)
        .fontSize(32);

      // Modpack info
      Column() {
        Text(modpack.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A');

        Row() {
          Text(`v${modpack.version}`)
            .fontSize(12)
            .fontColor('#999999');
          Text(` | ${modpack.mcVersion}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 4 });
          Text(` | ${modpack.modLoader}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 4 });
          Text(` | ${modpack.modCount} mods`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 4 });
        }
        .margin({ top: 2 });

        Text(modpack.description)
          .fontSize(12)
          .fontColor('#666666')
          .margin({ top: 2 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      // Status/action button
      if (modpack.installStatus === InstallStatus.INSTALLING) {
        Column() {
          ProgressBar({ progress: modpack.installProgress, showLabel: true });
        }
        .width(80);
      } else {
        Button(this.getStatusLabel(modpack.installStatus))
          .height(30)
          .backgroundColor(this.getStatusColor(modpack.installStatus))
          .fontColor(Color.White)
          .fontSize(12)
          .borderRadius(6)
          .onClick(() => {
            if (modpack.installStatus === InstallStatus.NOT_INSTALLED) {
              this.installModpack(index);
            } else if (modpack.installStatus === InstallStatus.UPDATE_AVAILABLE) {
              this.updateModpack(index);
            }
          });
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick(() => this.viewDetails(index));
  }

  @Builder ModpackDetailView(modpack: ModpackInfo) {
    Column() {
      Scroll() {
        Column() {
          // Back button
          Row() {
            Button({ type: ButtonType.Normal }) {
              Text('← Back')
                .fontSize(14)
                .fontColor('#5C6BC0');
            }
            .backgroundColor(Color.Transparent);
            Blank();
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 });

          // Modpack header
          Column() {
            Card() {
              Column() {
                Row() {
                  Text(modpack.icon)
                    .fontSize(48);

                  Column() {
                    Text(modpack.name)
                      .fontSize(22)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#1A1A1A');

                    Text(`by ${modpack.author}`)
                      .fontSize(14)
                      .fontColor('#666666')
                      .margin({ top: 2 });
                  }
                  .margin({ left: 16 })
                  .alignItems(HorizontalAlign.Start);
                }
                .width('100%');

                Text(modpack.description)
                  .fontSize(14)
                  .fontColor('#666666')
                  .width('100%')
                  .margin({ top: 16 });
              }
              .width('100%');
            }
          }
          .padding(16);

          Column() {
            Card() {
              Column() {
                this.DetailRow('Version', modpack.version);
                this.DetailRow('Minecraft', modpack.mcVersion);
                this.DetailRow('Mod Loader', modpack.modLoader);
                this.DetailRow('Mod Count', `${modpack.modCount} mods`);
                this.DetailRow('Source', modpack.source);
                this.DetailRow('Status', this.getStatusLabel(modpack.installStatus));
              }
              .width('100%');
            }
          }
          .padding(16);

          // Install progress
          if (modpack.installStatus === InstallStatus.INSTALLING) {
            Column() {
              Card() {
                Column() {
                  Text('Installation Progress')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#1A1A1A')
                    .margin({ bottom: 8 });

                  ProgressBar({ progress: modpack.installProgress, showLabel: true });
                }
                .width('100%');
              }
            }
            .padding(16);
          }

          // Action buttons
          Row() {
            if (modpack.installStatus === InstallStatus.NOT_INSTALLED) {
              Button('Install')
                .height(44)
                .backgroundColor('#5C6BC0')
                .fontColor(Color.White)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .borderRadius(8)
                .layoutWeight(1)
                .onClick(() => this.installModpack(this.selectedIndex));
            } else if (modpack.installStatus === InstallStatus.UPDATE_AVAILABLE) {
              Button('Update')
                .height(44)
                .backgroundColor('#D83B01')
                .fontColor(Color.White)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .borderRadius(8)
                .layoutWeight(1)
                .onClick(() => this.updateModpack(this.selectedIndex));
            } else if (modpack.installStatus === InstallStatus.INSTALLED) {
              Button('Update Available')
                .height(44)
                .backgroundColor('#107C10')
                .fontColor(Color.White)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .borderRadius(8)
                .layoutWeight(1)
                .enabled(false);
            }
          }
          .width('100%')
          .padding({ top: 16 });
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 });
      }
      .width('100%')
      .height('100%');
    }
    .width('100%')
    .height('100%');
  }

  @Builder DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666666')
        .width(100);
      Text(value)
        .fontSize(14)
        .fontColor('#1A1A1A');
    }
    .width('100%')
    .height(32);
  }
}