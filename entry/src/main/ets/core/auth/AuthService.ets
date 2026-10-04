// Authentication service for ABCL
import { Account, AuthResult, UserType } from '../../model/Account';
import { AppStore } from '../AppStore';
import { HttpClient, HttpResult } from '../network/HttpClient';
import { FileUtils } from '../util/Utils';
import { Constants } from '../../config/Constants';
import { Logger } from '../util/Utils';
import { PreferencesManager } from '../storage/PreferencesManager';

// Response interfaces for Microsoft OAuth flow
interface DeviceCodeResponse {
  device_code: string;
  user_code: string;
  verification_uri: string;
  expires_in: number;
  interval: number;
}

/** 设备码流程第一步的返回值 */
export interface MicrosoftDeviceCode {
  ok: boolean;
  error?: string;
  deviceCode?: string;
  userCode?: string;
  verificationUri?: string;
  /** 秒 */
  expiresIn?: number;
  /** 秒 */
  interval?: number;
}

/** 轮询 token 时的响应：成功有 access_token，失败有 error */
interface MicrosoftTokenResponse {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  error?: string;
  error_description?: string;
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

  private store: AppStore;

  constructor() {
    this.store = AppStore.getInstance();
  }

  // Load accounts from storage (via PreferencesManager)
  loadAccounts(): Account[] {
    // PreferencesManager handles auto-loading during init,
    // so accounts are already in this.store.accounts
    return this.store.accounts;
  }

  // Save accounts to storage (via PreferencesManager, async)
  private async persistAccounts(): Promise<void> {
    try {
      const prefs = PreferencesManager.getInstance();
      await prefs.saveAccounts();
    } catch (e) {
      Logger.warn(AuthService.TAG, `Failed to persist accounts: ${(e as Error).message}`);
    }
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
    this.persistAccounts();
    Logger.info(AuthService.TAG, `Offline account created: ${username}`);
    return account;
  }

  /**
   * 第一步：向微软申请设备码。
   *
   * 之前这个流程是错的：拿到 device_code 之后立刻就换 token，
   * 而设备码流程的本质是「用户去浏览器输码、这边轮询等待」，
   * 所以永远拿不到 token（微软返回 authorization_pending）。
   * 而且 user_code / verification_uri 根本没返回给 UI，用户无从输码。
   *
   * 现在拆成两步：startMicrosoftLogin() 拿码，pollMicrosoftToken() 轮询。
   */
  async startMicrosoftLogin(clientId: string): Promise<MicrosoftDeviceCode> {
    if (clientId.trim().length === 0) {
      const msg = '未配置微软 client_id：请到「设置 → 账户」填入你在 portal.azure.com 注册的 Application (client) ID';
      Logger.error(AuthService.TAG, msg);
      return { ok: false, error: msg };
    }
    const scope = Constants.MICROSOFT_SCOPES;
    const res = await HttpClient.postForm(
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode',
      'client_id=' + encodeURIComponent(clientId.trim()) + '&scope=' + encodeURIComponent(scope)
    );
    if (!res.success || res.data === undefined) {
      const msg = '获取设备码失败：' + (res.error ? res.error : '网络错误');
      Logger.error(AuthService.TAG, msg);
      return { ok: false, error: msg };
    }
    try {
      const dc = JSON.parse(res.data) as DeviceCodeResponse;
      Logger.info(AuthService.TAG, '设备码已获取，验证地址 ' + dc.verification_uri);
      return {
        ok: true,
        deviceCode: dc.device_code,
        userCode: dc.user_code,
        verificationUri: dc.verification_uri,
        // 微软给的 expires_in 通常是 900 秒，HMCL 也额外封顶到 900
        expiresIn: Math.min(dc.expires_in, 900),
        interval: dc.interval > 0 ? dc.interval : 5
      };
    } catch (e) {
      const msg = '设备码响应解析失败：' + (e as Error).message;
      Logger.error(AuthService.TAG, msg);
      return { ok: false, error: msg };
    }
  }

  /**
   * 第二步：轮询 token，直到授权成功 / 超时 / 被拒绝。
   *
   * 语义照搬 HMCL 的 OAuth.authenticateDevice()：
   *   authorization_pending → 继续等
   *   slow_down            → interval += 5 秒
   *   expired_token        → 失败（用户超时）
   *   其他 error            → 失败，并把微软的 error_description 透出去
   */
  async pollMicrosoftToken(clientId: string, dc: MicrosoftDeviceCode): Promise<AuthResult> {
    const startedAt = Date.now();
    const pollInterval: number = dc.interval !== undefined ? dc.interval : 5;
    const ttlSeconds: number = dc.expiresIn !== undefined ? dc.expiresIn : 900;
    const deviceCode: string = dc.deviceCode !== undefined ? dc.deviceCode : '';
    let interval: number = pollInterval;
    while (true) {
      // 先按 interval 等，再发一次请求（HMCL 也是这个顺序）
      await AuthService.sleep(interval * 1000);

      if (Date.now() - startedAt >= ttlSeconds * 1000) {
        const msg = '设备码已过期，请重新登录';
        Logger.warn(AuthService.TAG, msg);
        return { success: false, error: msg, errorType: 'expired' };
      }

      const res = await HttpClient.postForm(
        'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
        'client_id=' + encodeURIComponent(clientId.trim()) +
          '&grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:device_code') +
          '&device_code=' + encodeURIComponent(deviceCode)
      );

      // postRaw 对非 2xx 返回 success=false，但设备码未授权时微软本来就回 400，
      // 所以这里必须看 body，而不是看 success。
      const body = res.data ? res.data : '{}';
      let err = '';
      let desc = '';
      let accessToken = '';
      let refreshToken = '';
      let expiresIn = 0;
      try {
        const parsed = JSON.parse(body) as MicrosoftTokenResponse;
        err = parsed.error ? parsed.error : '';
        desc = parsed.error_description ? parsed.error_description : '';
        accessToken = parsed.access_token ? parsed.access_token : '';
        refreshToken = parsed.refresh_token ? parsed.refresh_token : '';
        expiresIn = parsed.expires_in ? parsed.expires_in : 0;
      } catch (e) {
        const msg = '轮询 token 失败：' + (res.error ? res.error : '响应无法解析');
        Logger.error(AuthService.TAG, msg);
        return { success: false, error: msg };
      }

      if (err === 'authorization_pending') {
        continue;
      }
      if (err === 'slow_down') {
        interval += 5;
        continue;
      }
      if (err === 'expired_token') {
        const msg = '设备码已过期，请重新登录';
        Logger.warn(AuthService.TAG, msg);
        return { success: false, error: msg, errorType: 'expired' };
      }
      if (err.length > 0) {
        const msg = '微软拒绝授权：' + desc;
        Logger.error(AuthService.TAG, msg);
        return { success: false, error: msg, errorType: err };
      }
      if (accessToken.length === 0) {
        return { success: false, error: '微软未返回访问令牌' };
      }
      return this.finishMicrosoftLogin(accessToken, refreshToken, expiresIn);
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 第 3~6 步：XBL → XSTS → login_with_xbox → profile */
  private async finishMicrosoftLogin(msAccessToken: string, msRefreshToken: string, msExpiresIn: number): Promise<AuthResult> {
    try {
      const msToken: TokenResponse = {
        access_token: msAccessToken,
        refresh_token: msRefreshToken,
        expires_in: msExpiresIn,
        token_type: 'Bearer'
      };

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
      this.persistAccounts();
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
      this.persistAccounts();
      return { success: true, account };
    } catch (e) {
      return { success: false, error: (e as Error).message };
    }
  }

  // Remove account
  removeAccount(uuid: string): void {
    this.store.removeAccount(uuid);
    this.persistAccounts();
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
