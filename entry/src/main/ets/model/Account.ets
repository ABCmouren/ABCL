/**
 * Minecraft account model for ABCL
 */

export enum UserType {
  OFFLINE = 'offline',
  MICROSOFT = 'microsoft',
  AUTH_LIB_INJECTOR = 'authlib_injector'
}

export interface Account {
  id: string;
  uuid: string;
  username: string;
  userType: UserType;
  type: UserType;
  accessToken: string;
  expiresAt: number;
  selected: boolean;
  lastLoginTime: number;
  // Microsoft-specific fields
  refreshToken?: string;
  microsoftRefreshToken?: string;
  microsoftAccessToken?: string;
  xuid?: string;
  clientId?: string;
  userProperties?: string;
  skinUrl?: string;
  // Authlib-injector specific fields
  authServer?: string;
}

export type AccountType = UserType;

export interface OfflineProfile {
  uuid: string;
  username: string;
}

export interface AuthResult {
  success: boolean;
  account?: Account;
  error?: string;
  errorType?: string;
}

export interface AccountStorage {
  accounts: Account[];
  selectedUuid: string | null;
}