// Authentication service for HMCL-HarmonyOS
import { Account, AuthResult, UserType } from '../../model/Account';
import { AppStore } from '../AppStore';
import { HttpClient, HttpResult } from '../network/HttpClient';
import { FileUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';
import { Logger } from '../util/Utils';

// Response interfaces for Microsoft OAuth flow
interface DeviceCodeResponse {
  device_code: string;
  user_code: string;
  verification_uri: string;
  expires_in: number;
  interval: number;
}

interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
}

interface XuiClaim {
  uhs: string;
}

interface DisplayClaims {
  xui: XuiClaim[];
}

interface XblResponse {
  Token: string;
  DisplayClaims: DisplayClaims;
}

interface XstsResponse {
  Token: string;
}

interface McAuthResponse {
  access_token: string;
  expires_in: number;
}

interface McSkin {
  url: string;
}

interface McProfileResponse {
  id: string;
  name: string;
  skins: McSkin[];
}

interface AuthlibProfileResponse {
  id: string;
  name: string;
}

interface XblAuthRequest {
  client_id: string;
  scope: string;
}

interface TokenPollRequest {
  client_id: string;
  grant_type: string;
  device_code: string;
}

interface XblAuthProperties {
  AuthMethod: string;
  SiteName: string;
  RpsTicket: string;
}

interface XblAuthBody {
  Properties: XblAuthProperties;
  RelyingParty: string;
  TokenType: string;
}

interface XstsProperties {
  SandboxId: string;
  UserTokens: string[];
}

interface XstsAuthBody {
  Properties: XstsProperties;
  RelyingParty: string;
  TokenType: string;
}

interface McAuthBody {
  identityToken: string;
}

interface McProfileHeader {
  Authorization: string;
}

export class AuthService {
  private static readonly TAG = 'AuthService';
  private static readonly ACCOUNTS_FILE = 'hmcl_accounts.json';

  private store: AppStore;

  constructor() {
    this.store = AppStore.getInstance();
  }

  // Load accounts from storage
  loadAccounts(): Account[] {
    const path = `${Constants.APP_DIR}${AuthService.ACCOUNTS_FILE}`;
    const data = FileUtils.readFile(path);
    if (data) {
      try {
        const accounts = JSON.parse(data) as Account[];
        this.store.accounts = accounts;
        return accounts;
      } catch (e) {
        Logger.error(AuthService.TAG, 'Failed to parse accounts', e as Error);
      }
    }
    return [];
  }

  // Save accounts to storage
  saveAccounts(): void {
    const path = `${Constants.APP_DIR}${AuthService.ACCOUNTS_FILE}`;
    const data = JSON.stringify(this.store.accounts, null, 2);
    FileUtils.writeFile(path, data);
  }

  // Create offline mode account
  loginOffline(username: string): Account {
    const uuid = FileUtils.generateUUIDv3(username);
    const account: Account = {
      id: uuid,
      uuid: uuid,
      username: username,
      userType: UserType.OFFLINE,
      type: UserType.OFFLINE,
      accessToken: 'offline',
      expiresAt: Date.now() + 365 * 24 * 60 * 60 * 1000, // 1 year
      lastLoginTime: Date.now(),
      selected: this.store.accounts.length === 0
    };
    this.store.addAccount(account);
    this.saveAccounts();
    Logger.info(AuthService.TAG, `Offline account created: ${username}`);
    return account;
  }

  // Microsoft OAuth login (device code flow)
  async loginMicrosoft(): Promise<AuthResult> {
    try {
      // Step 1: Get device code
      const deviceCodeBody: XblAuthRequest = {
        client_id: Constants.AZURE_CLIENT_ID,
        scope: 'XboxLive.signin offline_access'
      };
      const formHeader: Record<string, string> = {
        'Content-Type': 'application/x-www-form-urlencoded'
      };
      const deviceCodeResult = await HttpClient.postJson<DeviceCodeResponse>(
        'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode',
        deviceCodeBody,
        formHeader
      );

      if (!deviceCodeResult.success || !deviceCodeResult.data) {
        return { success: false, error: 'Failed to get device code' };
      }

      const deviceCode = deviceCodeResult.data;

      // Step 2: Poll for token
      const tokenPollBody: TokenPollRequest = {
        client_id: Constants.AZURE_CLIENT_ID,
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
        device_code: deviceCode.device_code
      };
      const tokenResult = await HttpClient.postJson<TokenResponse>(
        'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
        tokenPollBody,
        formHeader
      );

      if (!tokenResult.success || !tokenResult.data) {
        return { success: false, error: 'Microsoft login failed or user cancelled' };
      }

      const msToken = tokenResult.data;

      // Step 3: Xbox Live authentication
      const xblBody: XblAuthBody = {
        Properties: {
          AuthMethod: 'RPS',
          SiteName: 'user.auth.xboxlive.com',
          RpsTicket: `d=${msToken.access_token}`
        },
        RelyingParty: 'http://auth.xboxlive.com',
        TokenType: 'JWT'
      };
      const xblResult = await HttpClient.postJson<XblResponse>(
        Constants.XBL_AUTHENTICATE,
        xblBody
      );

      if (!xblResult.success || !xblResult.data) {
        return { success: false, error: 'Xbox Live authentication failed' };
      }

      const xblToken = xblResult.data.Token;
      const uhs = xblResult.data.DisplayClaims.xui[0].uhs;

      // Step 4: XSTS authorization
      const xstsBody: XstsAuthBody = {
        Properties: {
          SandboxId: 'RETAIL',
          UserTokens: [xblToken]
        },
        RelyingParty: 'rp://api.minecraftservices.com/',
        TokenType: 'JWT'
      };
      const xstsResult = await HttpClient.postJson<XstsResponse>(
        Constants.XSTS_AUTHORIZE,
        xstsBody
      );

      if (!xstsResult.success || !xstsResult.data) {
        return { success: false, error: 'XSTS authorization failed' };
      }

      const xstsToken = xstsResult.data.Token;

      // Step 5: Minecraft authentication
      const mcAuthBody: McAuthBody = {
        identityToken: `XBL3.0 x=${uhs};${xstsToken}`
      };
      const mcResult = await HttpClient.postJson<McAuthResponse>(
        Constants.MINECRAFT_AUTH,
        mcAuthBody
      );

      if (!mcResult.success || !mcResult.data) {
        return { success: false, error: 'Minecraft authentication failed' };
      }

      const mcToken = mcResult.data.access_token;

      // Step 6: Get Minecraft profile
      const mcProfileHeader: Record<string, string> = {
        'Authorization': `Bearer ${mcToken}`
      };
      const profileResult = await HttpClient.getJson<McProfileResponse>(
        Constants.MINECRAFT_PROFILE,
        mcProfileHeader
      );

      if (!profileResult.success || !profileResult.data) {
        return { success: false, error: 'Failed to get Minecraft profile' };
      }

      const profile = profileResult.data;

      const account: Account = {
        id: profile.id,
        uuid: profile.id,
        username: profile.name,
        userType: UserType.MICROSOFT,
        type: UserType.MICROSOFT,
        accessToken: mcToken,
        refreshToken: msToken.refresh_token,
        expiresAt: Date.now() + msToken.expires_in * 1000,
        lastLoginTime: Date.now(),
        selected: this.store.accounts.length === 0,
        skinUrl: profile.skins && profile.skins.length > 0 ? profile.skins[0].url : undefined
      };

      this.store.addAccount(account);
      this.saveAccounts();
      Logger.info(AuthService.TAG, `Microsoft account added: ${profile.name}`);
      return { success: true, account };
    } catch (e) {
      Logger.error(AuthService.TAG, 'Microsoft login failed', e as Error);
      return { success: false, error: (e as Error).message };
    }
  }

  // Authlib Injector login
  async loginAuthlibInjector(server: string, token: string): Promise<AuthResult> {
    try {
      const result = await HttpClient.getJson<AuthlibProfileResponse>(
        `${server}/api/user/profile/${token}`
      );

      if (!result.success || !result.data) {
        return { success: false, error: 'Authlib authentication failed' };
      }

      const profile = result.data;
      const account: Account = {
        id: profile.id,
        uuid: profile.id,
        username: profile.name,
        userType: UserType.AUTH_LIB_INJECTOR,
        type: UserType.AUTH_LIB_INJECTOR,
        accessToken: token,
        expiresAt: Date.now() + 86400000, // 24 hours
        lastLoginTime: Date.now(),
        selected: this.store.accounts.length === 0,
        authServer: server
      };

      this.store.addAccount(account);
      this.saveAccounts();
      return { success: true, account };
    } catch (e) {
      return { success: false, error: (e as Error).message };
    }
  }

  // Remove account
  removeAccount(uuid: string): void {
    this.store.removeAccount(uuid);
    this.saveAccounts();
  }

  // Get selected account
  getSelectedAccount(): Account | null {
    return this.store.getSelectedAccount();
  }

  // Get all accounts
  getAccounts(): Account[] {
    return this.store.accounts;
  }
}
