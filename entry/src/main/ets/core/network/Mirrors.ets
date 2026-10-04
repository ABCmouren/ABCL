/**
 * Mirrors — Mojang 官方源 ↔ BMCLAPI 镜像 的 URL 映射。
 *
 * 2026-10 修正（实测结果）：
 *  - BMCLAPI 的 version_manifest_v2.json **不会**把 URL 改写成镜像地址，必须自己替换；
 *  - maven 制品统一走 https://bmclapi2.bangbang93.com/maven/<maven-path>（302 → 可用）；
 *  - fabric-loader 的元数据 BMCLAPI 没有镜像（404），必须走官方 maven.fabricmc.net；
 *  - NeoForge 的 maven 根路径是 https://maven.neoforged.net/releases（旧代码漏了 /releases）。
 */
import { Constants } from '../../config/Constants';

export class Mirrors {
  static readonly BMCLAPI_ORIGIN = 'https://bmclapi2.bangbang93.com';
  static readonly BMCLAPI_MAVEN = 'https://bmclapi2.bangbang93.com/maven';

  /** 通用：把任何 Mojang 域名换成 BMCLAPI 同路径 */
  static toBmclapi(url: string): string {
    if (!url.startsWith('http')) {
      return url;
    }
    return url
      .replace('https://piston-meta.mojang.com', Mirrors.BMCLAPI_ORIGIN)
      .replace('https://piston-data.mojang.com', Mirrors.BMCLAPI_ORIGIN)
      .replace('https://launcher.mojang.com', Mirrors.BMCLAPI_ORIGIN)
      .replace('https://libraries.minecraft.net', `${Mirrors.BMCLAPI_MAVEN}`)
      .replace('https://resources.download.minecraft.net', `${Mirrors.BMCLAPI_ORIGIN}/assets`);
  }

  /** 库文件镜像 */
  static library(url: string): string {
    if (url.includes('libraries.minecraft.net')) {
      return url.replace('https://libraries.minecraft.net', Mirrors.BMCLAPI_MAVEN);
    }
    if (url.includes('maven.minecraftforge.net')) {
      return url.replace('https://maven.minecraftforge.net', `${Mirrors.BMCLAPI_MAVEN}`);
    }
    return url;
  }

  /** Maven 路径 → BMCLAPI 镜像 URL */
  static mavenPath(mavenRepo: string, path: string): string {
    const trimmed = path.startsWith('/') ? path.substring(1) : path;
    return `${Mirrors.BMCLAPI_MAVEN}/${trimmed}`;
  }

  /** 资产对象路径（hash 前两位/hash） */
  static assetObject(hash: string): string {
    if (hash.length < 2) {
      return '';
    }
    const sub = hash.substring(0, 2);
    return `${Mirrors.BMCLAPI_ORIGIN}/assets/${sub}/${hash}`;
  }

  static officialAssetObject(hash: string): string {
    if (hash.length < 2) {
      return '';
    }
    const sub = hash.substring(0, 2);
    return `${Constants.MOJANG_RESOURCES_BASE}/${sub}/${hash}`;
  }

  /** 给定主 URL，返回可用的镜像候选列表（去重、去空） */
  // ============================================================
  //  模组平台镜像（照搬 HMCL 的 MirrorRule）
  //
  //  HMCL 的 CurseForge / Modrinth 之所以「不需要 API Key」，
  //  是因为它把请求改写到 mcimirror 上；官方 api.curseforge.com
  //  是必须有 key 的（HMCL 的 key 构建时打进 jar，源码里看不到）。
  //
  //  https://github.com/mcmod-info-mirror/mcim-rust-api
  // ============================================================
  static readonly MCIMIRROR_ORIGIN = 'https://mod.mcimirror.top';
  static readonly MODRINTH_OFFICIAL = 'https://api.modrinth.com/v2';
  static readonly MODRINTH_MIRROR = 'https://mod.mcimirror.top/modrinth/v2';
  static readonly CURSEFORGE_OFFICIAL = 'https://api.curseforge.com/v1';
  static readonly CURSEFORGE_MIRROR = 'https://mod.mcimirror.top/curseforge/v1';

  /** Modrinth API 根地址（enableMirror 时走 mcimirror，国内更快且无需 UA 规避） */
  static modrinthBase(enableMirror: boolean): string {
    return enableMirror ? Mirrors.MODRINTH_MIRROR : Mirrors.MODRINTH_OFFICIAL;
  }

  /**
   * CurseForge API 根地址。
   * 镜像源不需要 API Key；官方源必须有 key（由用户自备）。
   */
  static curseforgeBase(enableMirror: boolean): string {
    return enableMirror ? Mirrors.CURSEFORGE_MIRROR : Mirrors.CURSEFORGE_OFFICIAL;
  }

  /**
   * 把下载直链改写到镜像。
   * 对应 HMCL 的：
   *   cdn.modrinth.com  → mod.mcimirror.top
   *   edge.forgecdn.net → mod.mcimirror.top
   */
  static rewriteDownloadUrl(url: string, enableMirror: boolean): string {
    if (!enableMirror || url.length === 0) {
      return url;
    }
    if (url.startsWith('https://cdn.modrinth.com')) {
      return url.replace('https://cdn.modrinth.com', Mirrors.MCIMIRROR_ORIGIN);
    }
    if (url.startsWith('https://edge.forgecdn.net')) {
      return url.replace('https://edge.forgecdn.net', Mirrors.MCIMIRROR_ORIGIN);
    }
    if (url.startsWith('https://mediafilez.forgecdn.net')) {
      return url.replace('https://mediafilez.forgecdn.net', Mirrors.MCIMIRROR_ORIGIN);
    }
    return url;
  }

  static candidates(primary: string, enableMirror: boolean): string[] {
    const list: string[] = [];
    if (primary && primary.length > 0) {
      list.push(primary);
    }
    if (enableMirror) {
      const mirrored = Mirrors.toBmclapi(primary);
      if (mirrored !== primary) {
        list.push(mirrored);
      }
    }
    return list;
  }
}
