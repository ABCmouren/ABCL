// Game list page - main tab showing installed Minecraft versions
import { GameInstallation, LoaderType } from '../../model/GameVersion';
import { AppStore } from '../../core/AppStore';
import { VersionManager } from '../../core/game/VersionManager';
import { LaunchEngine } from '../../core/launch/LaunchEngine';
import { Account } from '../../model/Account';
import { VersionBadge } from '../../components/common/CommonComponents';
import { LoadingView } from '../../components/common/CommonComponents';
import { Logger } from '../../core/util/Utils';
import common from '@ohos.app.ability.common';
import Want from '@ohos.app.ability.Want';
import { BusinessError } from '@ohos.base';

// Explicit interfaces for JSON serialization (ArkTS strict mode requires typed object literals)
interface PendingAccountData {
  username: string;
  uuid: string;
  accessToken: string;
  refreshToken?: string;
  userProperties: string;
}

interface PendingLaunchConfig {
  versionId: string;
  name: string;
  gameVersion: string;
  loaderType: LoaderType | null;
  minMemory: number;
  maxMemory: number;
  directory: string;
  width: number;
  height: number;
  fullscreen: boolean;
  customJvmArgs: string;
  account: PendingAccountData;
}

// Note: ArkTS strict mode forbids indexed signatures in interfaces.
// Want.parameters expects Record<string, Object>, so we build it directly.

@Component
export default struct GameListPage {
  @State installations: GameInstallation[] = [];
  @State selectedIndex: number = -1;
  @State isLoading: boolean = true;
  @State selectedAccount: Account | null = null;

  private versionManager = new VersionManager();
  private launchEngine = LaunchEngine.getInstance();
  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.loadGames();
  }

  loadGames(): void {
    this.isLoading = true;
    try {
      this.installations = this.versionManager.getLocalVersions();
      this.selectedAccount = this.store.getSelectedAccount();
    } catch (e) {
      Logger.error('GameListPage', 'Failed to load games: ' + (e as Error).message);
    }
    this.isLoading = false;
  }

  build() {
    Column() {
      if (this.isLoading) {
        LoadingView({ message: 'Loading games...' });
      } else if (this.installations.length === 0) {
        // Empty state
        Column() {
          Text('No game versions installed')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ top: 40 });
          Text('Go to Download tab to install Minecraft')
            .fontSize(14)
            .fontColor('#BFBFBF')
            .margin({ top: 8 });
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        // Game list with detail panel
        Row() {
          // Left: version list
          List({ space: 8 }) {
            ForEach(this.installations, (inst: GameInstallation, index: number) => {
              ListItem() {
                this.GameCard(inst, index)
              }
            }, (inst: GameInstallation) => inst.versionId)
          }
          .width('40%')
          .height('100%')
          .padding(12)
          .backgroundColor('#F5F5F5')

          // Right: detail panel
          if (this.selectedIndex >= 0 && this.selectedIndex < this.installations.length) {
            this.DetailPanel(this.installations[this.selectedIndex])
          } else {
            Column() {
              Text('Select a version to view details')
                .fontSize(14)
                .fontColor('#999999');
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center);
          }
        }
        .width('100%')
        .height('100%');
      }
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  GameCard(inst: GameInstallation, index: number) {
    Column() {
      Row() {
        Column() {
          Text(inst.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1A1A1A');
          Row() {
            VersionBadge({ type: inst.gameVersion });
            if (inst.loaderType !== null) {
              Text(inst.loaderType.toUpperCase())
                .fontSize(10)
                .fontColor(Color.White)
                .backgroundColor('#881798')
                .borderRadius(4)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ left: 4 });
            }
          }
          .margin({ top: 4 });
        }
        .layoutWeight(1);

        if (index === this.selectedIndex) {
          Text('✓')
            .fontSize(18)
            .fontColor('#0078D4')
            .fontWeight(FontWeight.Bold);
        }
      }
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .backgroundColor(index === this.selectedIndex ? '#E8F4FD' : Color.White)
    .borderRadius(8)
    .onClick(() => {
      this.selectedIndex = index;
    });
  }

  @Builder
  DetailPanel(inst: GameInstallation) {
    Column() {
      Scroll() {
        Column() {
          // Version info
          Text(inst.name)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .width('100%');

          Row() {
            VersionBadge({ type: inst.gameVersion });
            if (inst.loaderType !== null) {
              Text(inst.loaderType.toUpperCase())
                .fontSize(11)
                .fontColor(Color.White)
                .backgroundColor('#881798')
                .borderRadius(4)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .margin({ left: 6 });
            }
          }
          .margin({ top: 8 });

          // Divider
          Divider()
            .height(1)
            .color('#E0E0E0')
            .margin({ top: 16, bottom: 16 });

          // Information rows
          this.InfoRow('Game Version', inst.gameVersion);
          this.InfoRow('Min Memory', `${inst.minMemory} MB`);
          this.InfoRow('Max Memory', `${inst.maxMemory} MB`);

          if (inst.lastPlayed > 0) {
            this.InfoRow('Last Played', new Date(inst.lastPlayed).toLocaleDateString());
          }

          // Launch button
          Button('Launch')
            .width('100%')
            .height(44)
            .backgroundColor('#0078D4')
            .fontColor(Color.White)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(8)
            .margin({ top: 24 })
            .onClick(() => {
              this.handleLaunch(inst);
            });

          // Account info
          if (this.selectedAccount) {
            Text(`Playing as: ${this.selectedAccount.username}`)
              .fontSize(12)
              .fontColor('#666666')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 8 });
          } else {
            Text('No account selected. Go to Accounts tab.')
              .fontSize(12)
              .fontColor('#D83B01')
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 8 });
          }
        }
        .width('100%')
        .padding(20);
      }
      .layoutWeight(1);
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(Color.White);
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666666');
      Blank();
      Text(value)
        .fontSize(14)
        .fontColor('#1A1A1A')
        .fontWeight(FontWeight.Medium);
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 } as Padding);
  }

  async handleLaunch(inst: GameInstallation): Promise<void> {
    const account = this.store.getSelectedAccount();
    if (!account) {
      Logger.error('GameListPage', 'No account selected');
      return;
    }

    try {
      // Store full launch configuration in AppStorage for GameAbility/GameView to read
      // Use explicit interface to satisfy ArkTS strict mode (arkts-no-untyped-obj-literals)
      const accountData: PendingAccountData = {
        username: account.username,
        uuid: account.uuid,
        accessToken: account.accessToken,
        refreshToken: account.refreshToken,
        userProperties: account.userProperties || '{}',
      };
      const launchConfigObj: PendingLaunchConfig = {
        versionId: inst.versionId,
        name: inst.name,
        gameVersion: inst.gameVersion,
        loaderType: inst.loaderType,
        minMemory: inst.minMemory,
        maxMemory: inst.maxMemory,
        directory: inst.directory,
        width: inst.width,
        height: inst.height,
        fullscreen: inst.fullscreen,
        customJvmArgs: inst.customJvmArgs,
        account: accountData,
      };
      const launchConfig: string = JSON.stringify(launchConfigObj);
      AppStorage.setOrCreate('pendingGameLaunch', launchConfig);
      Logger.info('GameListPage', 'Launch config stored in AppStorage, starting GameAbility...');

      // Start GameAbility which provides the XComponent rendering surface
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // ArkTS: Record must be built by assignment, not object literal
      const wantParams: Record<string, string> = {} as Record<string, string>;
      wantParams['versionId'] = inst.versionId;
      const want: Want = {
        bundleName: 'com.hmcl.launcher',
        abilityName: 'GameAbility',
        parameters: wantParams,
      };
      context.startAbility(want, (err: BusinessError) => {
        if (err.code) {
          Logger.error('GameListPage', 'Failed to start GameAbility: ' + JSON.stringify(err));
        } else {
          Logger.info('GameListPage', 'GameAbility started successfully');
        }
      });
    } catch (e) {
      Logger.error('GameListPage', 'Launch error: ' + (e as Error).message);
    }
  }
}