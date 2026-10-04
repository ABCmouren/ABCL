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
