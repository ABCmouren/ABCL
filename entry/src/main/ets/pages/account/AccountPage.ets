// Account management page
import { Account, AccountType } from '../../model/Account';
import { AuthService } from '../../core/auth/AuthService';
import { AppStore } from '../../core/AppStore';
import { AccountTypeBadge } from '../../components/common/CommonComponents';

@Component
export default struct AccountPage {
  @State accounts: Account[] = [];
  @State showAddModal: boolean = false;
  @State showOfflineInput: boolean = false;
  @State offlineUsername: string = '';
  @State isLoggingIn: boolean = false;

  private authService = new AuthService();
  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.accounts = this.authService.loadAccounts();
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('Accounts')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A');
        Blank();
        Button('+ Add')
          .fontSize(13)
          .fontColor('#0078D4')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showAddModal = true;
          });
      }
      .width('100%')
      .padding(16);

      if (this.accounts.length === 0) {
        // Empty state
        Column() {
          Text('No accounts added')
            .fontSize(16)
            .fontColor('#999999');
          Text('Add an account to play Minecraft')
            .fontSize(14)
            .fontColor('#BFBFBF')
            .margin({ top: 8 });
          Button('Add Account')
            .backgroundColor('#0078D4')
            .fontColor(Color.White)
            .borderRadius(8)
            .margin({ top: 24 })
            .onClick(() => {
              this.showAddModal = true;
            });
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center);
      } else {
        // Account list
        List({ space: 10 }) {
          ForEach(this.accounts, (account: Account) => {
            ListItem() {
              this.AccountCard(account)
            }
          }, (account: Account) => account.uuid);
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 });
      }

      // Add account modal
      if (this.showAddModal) {
        this.AddAccountModal();
      }

      // Offline username input
      if (this.showOfflineInput) {
        this.OfflineInputModal();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5');
  }

  @Builder
  AccountCard(account: Account) {
    Row() {
      // Avatar placeholder
      Circle()
        .width(40)
        .height(40)
        .fill('#E0E0E0')
        .margin({ right: 12 });

      Column() {
        Text(account.username)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1A1A');
        AccountTypeBadge({ accountType: account.type });
      }
      .layoutWeight(1);

      if (account.selected) {
        Text('Selected')
          .fontSize(12)
          .fontColor('#107C10')
          .fontWeight(FontWeight.Medium)
          .margin({ right: 8 });
      }

      Button('Select')
        .fontSize(12)
        .fontColor(account.selected ? '#666666' : '#0078D4')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (!account.selected) {
            this.authService.loadAccounts();
            this.store.setSelectedAccount(account.uuid);
            this.authService.saveAccounts();
            this.accounts = this.authService.getAccounts();
          }
        });
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .shadow({ radius: 2, color: '#1A000000', offsetY: 1 });
  }

  @Builder
  AddAccountModal() {
    Column() {
      Text('Add Account')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .margin({ bottom: 16 });

      // Offline mode
      Button('Offline Mode')
        .width('100%')
        .height(44)
        .backgroundColor('#F0F0F0')
        .fontColor('#1A1A1A')
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.showAddModal = false;
          this.showOfflineInput = true;
        });

      // Microsoft login
      Button('Microsoft Account')
        .width('100%')
        .height(44)
        .backgroundColor('#0078D4')
        .fontColor(Color.White)
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.showAddModal = false;
          this.isLoggingIn = true;
          this.handleMicrosoftLogin();
        });

      // Authlib Injector
      Button('Authlib Injector')
        .width('100%')
        .height(44)
        .backgroundColor('#F0F0F0')
        .fontColor('#1A1A1A')
        .borderRadius(8)
        .onClick(() => {
          this.showAddModal = false;
          // In a real implementation, show a server URL input
        });

      // Cancel
      Button('Cancel')
        .width('100%')
        .height(36)
        .fontColor('#666666')
        .backgroundColor(Color.Transparent)
        .margin({ top: 16 })
        .onClick(() => {
          this.showAddModal = false;
        });
    }
    .width('80%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
    .position({ x: '10%', y: '30%' });
  }

  @Builder
  OfflineInputModal() {
    Column() {
      Text('Offline Mode')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .margin({ bottom: 16 });

      TextInput({ placeholder: 'Enter username', text: this.offlineUsername })
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .padding({ left: 12 })
        .onChange((value: string) => {
          this.offlineUsername = value;
        });

      Button('Login')
        .width('100%')
        .height(40)
        .backgroundColor('#0078D4')
        .fontColor(Color.White)
        .borderRadius(8)
        .margin({ top: 16 })
        .onClick(() => {
          if (this.offlineUsername.trim()) {
            this.authService.loginOffline(this.offlineUsername.trim());
            this.accounts = this.authService.getAccounts();
            this.showOfflineInput = false;
            this.offlineUsername = '';
          }
        });

      Button('Cancel')
        .width('100%')
        .height(36)
        .fontColor('#666666')
        .backgroundColor(Color.Transparent)
        .margin({ top: 8 })
        .onClick(() => {
          this.showOfflineInput = false;
          this.offlineUsername = '';
        });
    }
    .width('80%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
    .position({ x: '10%', y: '30%' });
  }

  async handleMicrosoftLogin(): Promise<void> {
    try {
      this.isLoggingIn = true;
      const result = await this.authService.loginMicrosoft();
      if (result.success) {
        this.accounts = this.authService.getAccounts();
      }
    } catch (e) {
      console.error('Microsoft login failed', (e as Error).message);
    }
    this.isLoggingIn = false;
  }
}