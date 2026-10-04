// Account management page
import { Account, AccountType } from '../../model/Account';
import { AuthService, MicrosoftDeviceCode } from '../../core/auth/AuthService';
import { promptAction } from '@kit.ArkUI';
import { AppStore } from '../../core/AppStore';
import { AccountTypeBadge } from '../../components/common/CommonComponents';

@Component
export default struct AccountPage {
  @State accounts: Account[] = [];
  @State showAddModal: boolean = false;
  @State showOfflineInput: boolean = false;
  @State offlineUsername: string = '';
  @State isLoggingIn: boolean = false;
  /**
   * 之前所有错误都被 console.error 吞掉了，界面上什么都看不到，
   * 表现为「点了没反应」。现在一律显示在这里。
   */
  @State loginError: string = '';

  // 微软设备码流程的中间态
  @State showDeviceCode: boolean = false;
  @State deviceUserCode: string = '';
  @State deviceVerifyUrl: string = '';
  @State msClientId: string = '';
  @State showClientIdInput: boolean = false;

  private authService = new AuthService();
  private store = AppStore.getInstance();

  aboutToAppear(): void {
    this.accounts = this.authService.loadAccounts();
  }

  build() {
    Stack() {
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
          .fontColor('#5C6BC0')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showAddModal = true;
          });
      }
      .width('100%')
      .padding(16);

      // 错误提示条（之前完全没有，导致所有登录失败都是静默的）
      if (this.loginError.length > 0) {
        Row() {
          Text(this.loginError)
            .fontSize(12)
            .fontColor('#8C1D18')
            .layoutWeight(1);
          Text('设置 client_id')
            .fontSize(12)
            .fontColor('#4352A5')
            .padding({ left: 8, right: 4, top: 2, bottom: 2 })
            .onClick(() => {
              this.showClientIdInput = true;
            });
        }
        .width('100%')
        .padding(12)
        .margin({ left: 16, right: 16, bottom: 8 })
        .backgroundColor('#FCEEEE')
        .borderRadius(8);
      }

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
            .backgroundColor('#5C6BC0')
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
      .backgroundColor('#FBF8FF');

      if (this.showDeviceCode) {
        this.DeviceCodeModal();
      }

      if (this.showClientIdInput) {
        this.ClientIdModal();
      }
    }
    .width('100%')
    .height('100%');
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
        .fontColor(account.selected ? '#666666' : '#5C6BC0')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (!account.selected) {
            this.authService.loadAccounts();
            this.store.setSelectedAccount(account.uuid);
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
        .backgroundColor('#5C6BC0')
        .fontColor(Color.White)
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => {
          this.showAddModal = false;
          this.loginError = '';
          this.startMicrosoftFlow();
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
          this.loginError = 'Authlib-Injector 登录需要填写服务器地址与 accessToken，尚未接入界面';
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
  DeviceCodeModal() {
    Column() {
      Text('微软账号登录')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%');

      Text('1. 在浏览器打开下面的地址')
        .fontSize(13)
        .fontColor('#333333')
        .width('100%')
        .margin({ top: 16 });

      Text(this.deviceVerifyUrl)
        .fontSize(13)
        .fontColor('#4352A5')
        .width('100%')
        .margin({ top: 6 })
        .copyOption(CopyOptions.LocalDevice)
        .onClick(() => {
          promptAction.showToast({ message: '已复制验证地址' });
        });

      Text('2. 输入下面的代码并确认授权')
        .fontSize(13)
        .fontColor('#333333')
        .width('100%')
        .margin({ top: 14 });

      Text(this.deviceUserCode)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .letterSpacing(6)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 8 })
        .padding({ top: 14, bottom: 14 })
        .backgroundColor('#F0F0F0')
        .borderRadius(8)
        .copyOption(CopyOptions.LocalDevice)
        .onClick(() => {
          promptAction.showToast({ message: '已复制代码' });
        });

      Row() {
        LoadingProgress()
          .width(18)
          .height(18)
          .color('#5C6BC0')
          .margin({ right: 8 });
        Text('等待授权中…完成授权后会自动登录')
          .fontSize(12)
          .fontColor('#666666');
      }
      .width('100%')
      .margin({ top: 16 });

      Button('取消')
        .width('100%')
        .height(40)
        .fontColor('#666666')
        .backgroundColor(Color.Transparent)
        .margin({ top: 12 })
        .onClick(() => {
          this.showDeviceCode = false;
        });
    }
    .width('80%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
    .position({ x: '10%', y: '25%' });
  }

  @Builder
  ClientIdModal() {
    Column() {
      Text('微软 client_id')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .width('100%');

      Text('在 https://portal.azure.com 注册一个「公共客户端」应用，' +
        '添加 XboxLive.signin 委托权限，把 Application (client) ID 填在这里。' +
        '这个 ID 没有可用的公共替代，只能用自己的。')
        .fontSize(11)
        .fontColor('#666666')
        .width('100%')
        .margin({ top: 10 });

      TextInput({ placeholder: '例如 12345678-1234-1234-1234-123456789012', text: this.msClientId })
        .width('100%')
        .height(40)
        .fontSize(13)
        .margin({ top: 14 })
        .backgroundColor('#F0F0F0')
        .borderRadius(8)
        .onChange((v: string) => {
          this.msClientId = v;
        });

      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .fontColor('#666666')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showClientIdInput = false;
          });
        Button('保存')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#5C6BC0')
          .fontColor(Color.White)
          .borderRadius(8)
          .margin({ left: 10 })
          .onClick(() => {
            this.showClientIdInput = false;
            this.loginError = '';
          });
      }
      .width('100%')
      .margin({ top: 14 });
    }
    .width('80%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 8, color: '#33000000', offsetY: 4 })
    .position({ x: '10%', y: '28%' });
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
        .backgroundColor('#FBF8FF')
        .borderRadius(8)
        .padding({ left: 12 })
        .onChange((value: string) => {
          this.offlineUsername = value;
        });

      Button('Login')
        .width('100%')
        .height(40)
        .backgroundColor('#5C6BC0')
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

  /**
   * 微软设备码登录第一步：拿码并展示给用户。
   * 设备码登录必须让用户看到 user_code 和验证链接，否则无从授权。
   */
  private async startMicrosoftFlow(): Promise<void> {
    const clientId = this.msClientId.trim();
    if (clientId.length === 0) {
      this.loginError = '尚未配置微软 client_id（Application ID）。点击下方「设置 client_id」填入你在 portal.azure.com 注册的应用 ID。';
      return;
    }
    this.isLoggingIn = true;
    const dc = await this.authService.startMicrosoftLogin(clientId);
    this.isLoggingIn = false;
    if (!dc.ok || dc.deviceCode === undefined) {
      this.loginError = dc.error !== undefined ? dc.error : '获取设备码失败';
      return;
    }
    this.deviceUserCode = dc.userCode !== undefined ? dc.userCode : '';
    this.deviceVerifyUrl = dc.verificationUri !== undefined ? dc.verificationUri : '';
    this.showDeviceCode = true;
    // 后台开始轮询，用户去浏览器输码
    this.pollMicrosoft(dc);
  }

  /** 第二步：轮询直到授权成功 */
  private async pollMicrosoft(dc: MicrosoftDeviceCode): Promise<void> {
    this.isLoggingIn = true;
    const result = await this.authService.pollMicrosoftToken(this.msClientId.trim(), dc);
    this.isLoggingIn = false;
    if (result.success) {
      this.accounts = this.authService.getAccounts();
      this.showDeviceCode = false;
      this.loginError = '';
    } else {
      this.loginError = result.error !== undefined ? result.error : '登录失败';
    }
  }
}