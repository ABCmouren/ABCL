// Download page for installing Minecraft versions
import { VersionManifest, VersionInfo } from '../../model/GameVersion';
import { VersionManager } from '../../core/game/VersionManager';
import { VersionBadge, LoadingView, ProgressBar } from '../../components/common/CommonComponents';

@Component
export default struct DownloadPage {
  @State versions: VersionInfo[] = [];
  @State filterType: string = 'all';
  @State isLoading: boolean = true;
  @State searchText: string = '';
  @State installingVersion: string = '';
  @State installProgress: number = 0;

  private versionManager = VersionManager.getInstance();

  aboutToAppear(): void {
    this.loadVersions();
  }

  async loadVersions(): Promise<void> {
    this.isLoading = true;
    try {
      const manifest = await this.versionManager.fetchVersionManifest();
      this.versions = manifest.versions;
    } catch (e) {
      console.error('Failed to load versions', (e as Error).message);
    }
    this.isLoading = false;
  }

  get filteredVersions(): VersionInfo[] {
    let result = this.versions;
    if (this.filterType !== 'all') {
      result = result.filter(v => v.type === this.filterType);
    }
    if (this.searchText) {
      const search = this.searchText.toLowerCase();
      result = result.filter(v => v.id.toLowerCase().includes(search));
    }
    return result;
  }

  async installVersion(version: VersionInfo): Promise<void> {
    this.installingVersion = version.id;
    this.installProgress = 0;
    try {
      await this.versionManager.installVersion(version.id);
      this.installProgress = 1;
    } catch (e) {
      console.error(`Failed to install ${version.id}`, (e as Error).message);
    }
    setTimeout(() => {
      this.installingVersion = '';
      this.installProgress = 0;
    }, 2000);
  }

  build() {
    Column() {
      // Header
      Text('Download Minecraft')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 });

      // Search bar
      Row() {
        TextInput({ placeholder: 'Search versions...', text: this.searchText })
          .layoutWeight(1)
          .height(36)
          .fontSize(14)
          .backgroundColor('#F0F0F0')
          .borderRadius(8)
          .padding({ left: 12 })
          .onChange((value: string) => {
            this.searchText = value;
          });
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 });

      // Filter tabs
      Row({ space: 8 }) {
        this.FilterChip('All', 'all');
        this.FilterChip('Release', 'release');
        this.FilterChip('Snapshot', 'snapshot');
        this.FilterChip('Old', 'old_beta');
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 });

      if (this.isLoading) {
        LoadingView({ message: 'Loading version list...' });
      } else {
        // Version list
        List({ space: 6 }) {
          ForEach(this.filteredVersions, (version: VersionInfo) => {
            ListItem() {
              this.VersionItem(version)
            }
          }, (version: VersionInfo) => version.id);
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 });
      }

      // Install progress overlay
      if (this.installingVersion) {
        Column() {
          Text(`Installing ${this.installingVersion}...`)
            .fontSize(14)
            .fontColor('#1A1A1A')
            .margin({ bottom: 12 });
          ProgressBar({ progress: this.installProgress, showLabel: true });
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(8)
        .shadow({ radius: 4, color: '#33000000', offsetY: 2 })
        .position({ x: 16, y: '50%' });
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5');
  }

  @Builder
  FilterChip(label: string, type: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.filterType === type ? Color.White : '#666666')
      .backgroundColor(this.filterType === type ? '#0078D4' : '#E8E8E8')
      .borderRadius(16)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .onClick(() => {
        this.filterType = type;
      });
  }

  @Builder
  VersionItem(version: VersionInfo) {
    Row() {
      Column() {
        Text(version.id)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A');
        Row() {
          VersionBadge({ type: version.type });
          if (version.releaseTime) {
            Text(new Date(version.releaseTime).toLocaleDateString())
              .fontSize(11)
              .fontColor('#999999')
              .margin({ left: 8 });
          }
        }
        .margin({ top: 4 });
      }
      .layoutWeight(1);

      if (this.installingVersion === version.id) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color('#0078D4');
      } else {
        Button('Install')
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#0078D4')
          .borderRadius(6)
          .height(30)
          .onClick(() => {
            this.installVersion(version);
          });
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8);
  }
}