/**
 * WorldPage - World management page
 */

import { EmptyView, SearchBar, Card, SectionHeader } from '../../components/common/CommonComponents';

interface WorldInfo {
  name: string;
  folderName: string;
  lastPlayed: number;
  fileSize: number;
  gameVersion: string;
  gameMode: string;
  difficulty: string;
  players: string[];
  seed: number;
  icon: string;
}

@Component
export default struct WorldPage {
  @State private worlds: WorldInfo[] = [];
  @State private filteredWorlds: WorldInfo[] = [];
  @State private isLoading: boolean = true;
  @State private searchText: string = '';
  @State private showDetail: boolean = false;
  @State private selectedIndex: number = -1;
  @State private showDeleteConfirm: boolean = false;
  @State private deleteTargetIndex: number = -1;

  aboutToAppear(): void {
    this.loadWorlds();
  }

  private loadWorlds(): void {
    this.isLoading = true;
    setTimeout(() => {
      this.worlds = this.generateMockWorlds();
      this.filteredWorlds = [...this.worlds];
      this.isLoading = false;
    }, 400);
  }

  private generateMockWorlds(): WorldInfo[] {
    return [
      {
        name: 'Survival World',
        folderName: 'survival_world',
        lastPlayed: Date.now() - 3600000,
        fileSize: 52428800,
        gameVersion: '1.20.4',
        gameMode: 'Survival',
        difficulty: 'Normal',
        players: ['StevePlayer'],
        seed: 1234567890,
        icon: '🌲'
      },
      {
        name: 'Creative Builds',
        folderName: 'creative_builds',
        lastPlayed: Date.now() - 172800000,
        fileSize: 157286400,
        gameVersion: '1.20.4',
        gameMode: 'Creative',
        difficulty: 'Peaceful',
        players: ['StevePlayer', 'AlexBuilder'],
        seed: -987654321,
        icon: '🏗️'
      },
      {
        name: 'Modded Adventure',
        folderName: 'modded_adventure',
        lastPlayed: Date.now() - 604800000,
        fileSize: 89128960,
        gameVersion: '1.20.1',
        gameMode: 'Survival',
        difficulty: 'Hard',
        players: ['ModdedUser'],
        seed: 567890123,
        icon: '⚔️'
      },
      {
        name: 'Flat World',
        folderName: 'flat_world',
        lastPlayed: Date.now() - 2592000000,
        fileSize: 10485760,
        gameVersion: '1.19.4',
        gameMode: 'Creative',
        difficulty: 'Peaceful',
        players: ['StevePlayer'],
        seed: 0,
        icon: '🏜️'
      },
      {
        name: 'Redstone Lab',
        folderName: 'redstone_lab',
        lastPlayed: Date.now() - 86400000,
        fileSize: 31457280,
        gameVersion: '1.20.4',
        gameMode: 'Creative',
        difficulty: 'Peaceful',
        players: ['StevePlayer'],
        seed: 123456,
        icon: '🔴'
      }
    ];
  }

  private viewDetails(index: number): void {
    this.selectedIndex = index;
    this.showDetail = true;
  }

  private confirmDelete(index: number): void {
    this.deleteTargetIndex = index;
    this.showDeleteConfirm = true;
  }

  private executeDelete(): void {
    if (this.deleteTargetIndex >= 0 && this.deleteTargetIndex < this.filteredWorlds.length) {
      const world = this.filteredWorlds[this.deleteTargetIndex];
      this.worlds = this.worlds.filter(w => w.folderName !== world.folderName);
      this.filteredWorlds = this.filteredWorlds.filter((_, i) => i !== this.deleteTargetIndex);
    }
    this.showDeleteConfirm = false;
    this.deleteTargetIndex = -1;
  }

  private backupWorld(index: number): void {
    const world = this.filteredWorlds[index];
    console.info(`Backing up world: ${world.name}`);
  }

  private openWorldsFolder(): void {
    console.info('Opening worlds folder...');
  }

  private onSearch(text: string): void {
    this.searchText = text;
    if (text.length === 0) {
      this.filteredWorlds = [...this.worlds];
    } else {
      const query = text.toLowerCase();
      this.filteredWorlds = this.worlds.filter(w =>
        w.name.toLowerCase().includes(query) ||
        w.gameVersion.includes(query) ||
        w.gameMode.toLowerCase().includes(query)
      );
    }
  }

  private formatLastPlayed(timestamp: number): string {
    if (timestamp === 0) return 'Never';
    const diff = Date.now() - timestamp;
    if (diff < 3600000) return 'Just now';
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
    if (diff < 604800000) return `${Math.floor(diff / 86400000)}d ago`;
    return new Date(timestamp).toLocaleDateString();
  }

  private formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(2)} GB`;
  }

  private formatSeed(seed: number): string {
    if (seed === 0) return '0 (Default)';
    return seed.toString();
  }

  build() {
    Stack() {
      Column() {
        // Header
        Row() {
          Text('Worlds')
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
          .onClick(() => this.openWorldsFolder());
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
        } else if (this.filteredWorlds.length === 0) {
          EmptyView({
            message: this.searchText.length > 0 ? 'No worlds match your search' : 'No worlds saved',
            actionText: 'Open Worlds Folder'
          });
        } else {
          if (this.showDetail && this.selectedIndex >= 0) {
            this.WorldDetailView(this.filteredWorlds[this.selectedIndex]);
          } else {
            List() {
              ForEach(this.filteredWorlds, (world: WorldInfo, index: number) => {
                ListItem() {
                  this.WorldItemComponent(world, index);
                }
              }, (world: WorldInfo) => world.folderName);
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

      // Delete confirmation dialog
      if (this.showDeleteConfirm) {
        Column() {
          Column() {
            Text('Delete World')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1A1A1A')
              .margin({ bottom: 8 });
            Text('This will permanently delete the world. Create a backup first?')
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
                .onClick(() => { this.showDeleteConfirm = false; });
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
          .shadow({ radius: 8, color: '#33000000', offsetX: 0, offsetY: 4 });
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

  @Builder WorldItemComponent(world: WorldInfo, index: number) {
    Row() {
      Text(world.icon)
        .fontSize(32);
      Column() {
        Text(world.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A');
        Row() {
          Text(this.formatLastPlayed(world.lastPlayed))
            .fontSize(12)
            .fontColor('#999999');
          Text(` | ${this.formatFileSize(world.fileSize)}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 4 });
          Text(` | ${world.gameVersion}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 4 });
        }
        .margin({ top: 2 });
        Row() {
          Text(world.gameMode)
            .fontSize(11)
            .fontColor('#5C6BC0')
            .backgroundColor('#E8F4FD')
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 });
          Text(world.difficulty)
            .fontSize(11)
            .fontColor('#D83B01')
            .backgroundColor('#FFF4E8')
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ left: 4 });
        }
        .margin({ top: 4 });
      }
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Column() {
        Button({ type: ButtonType.Normal }) {
          Text('ⓘ')
            .fontSize(16);
        }
        .width(28)
        .height(28)
        .backgroundColor('#F0F0F0')
        .borderRadius(14)
        .onClick(() => this.viewDetails(index));
      }
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick(() => this.viewDetails(index));
  }

  @Builder WorldDetailView(world: WorldInfo) {
    Column() {
      Scroll() {
        Column() {
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

          Row() {
            Text(world.icon)
              .fontSize(48);
            Column() {
              Text(world.name)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#1A1A1A');
              Text(world.folderName)
                .fontSize(13)
                .fontColor('#999999')
                .fontFamily('monospace');
            }
            .margin({ left: 16 })
            .alignItems(HorizontalAlign.Start);
          }
          .width('100%')
          .padding({ bottom: 20 });

          Column() {
            Card() {
              Column() {
                this.DetailRow('Game Version', world.gameVersion);
                this.DetailRow('Game Mode', world.gameMode);
                this.DetailRow('Difficulty', world.difficulty);
                this.DetailRow('Seed', this.formatSeed(world.seed));
                this.DetailRow('File Size', this.formatFileSize(world.fileSize));
                this.DetailRow('Last Played', this.formatLastPlayed(world.lastPlayed));
                this.DetailRow('Players', world.players.join(', '));
              }
              .width('100%');
            }
          }
          .padding(16);

          Row() {
            Button('Delete')
              .height(40)
              .backgroundColor('#D83B01')
              .fontColor(Color.White)
              .fontSize(14)
              .borderRadius(8)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(() => this.confirmDelete(this.selectedIndex));
            Button('Backup')
              .height(40)
              .backgroundColor('#5C6BC0')
              .fontColor(Color.White)
              .fontSize(14)
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => this.backupWorld(this.selectedIndex));
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