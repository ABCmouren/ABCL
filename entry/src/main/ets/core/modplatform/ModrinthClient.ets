/**
 * ModrinthClient — Modrinth v2 API 客户端
 *
 * HMCL 的模组/资源包/光影/整合包下载走 Modrinth 与 CurseForge。
 * 本文件先实现 Modrinth（免费、无需 API Key）；CurseForge 需要 key，后续再补。
 *
 * 注意：Modrinth 要求带 User-Agent，否则会被限流。
 */
import { HttpClient } from '../network/HttpClient';
import { Logger } from '../util/Utils';

export interface ModrinthSearchHit {
  project_id: string;
  slug: string;
  title: string;
  description: string;
  author: string;
  downloads: number;
  follows: number;
  icon_url: string;
  categories: string[];
  display_categories?: string[];
  versions: string[];
  project_type: string;
}

export interface ModrinthSearchResult {
  hits: ModrinthSearchHit[];
  offset: number;
  limit: number;
  total_hits: number;
}

export interface ModrinthHashes {
  sha1?: string;
  sha512?: string;
}

export interface ModrinthFile {
  hashes: ModrinthHashes;
  url: string;
  filename: string;
  size: number;
  primary: boolean;
}

export interface ModrinthDependency {
  version_id?: string;
  project_id?: string;
  dependency_type: string;
}

export interface ModrinthVersion {
  id: string;
  project_id: string;
  name: string;
  version_number: string;
  game_versions: string[];
  loaders: string[];
  files: ModrinthFile[];
  date_published: string;
  dependencies: ModrinthDependency[];
  version_type: string;
}

export class ModrinthClient {
  private static readonly TAG = 'Modrinth';
  private static readonly BASE = 'https://api.modrinth.com/v2';

  private static headers(): Record<string, string> {
    const h: Record<string, string> = {};
    h['User-Agent'] = 'ABCmouren/ABCL/2.0.0 (HarmonyOS Minecraft Launcher)';
    h['Accept'] = 'application/json';
    return h;
  }

  /**
   * 搜索项目
   * @param projectType mod | resourcepack | shader | modpack | datapack
   */
  static async search(
    query: string,
    projectType: string,
    gameVersion: string,
    loader: string,
    offset: number = 0,
    limit: number = 20
  ): Promise<ModrinthSearchHit[]> {
    const facets: string[] = [];
    if (projectType.length > 0) {
      facets.push(`["project_type:${projectType}"]`);
    }
    if (gameVersion.length > 0) {
      facets.push(`["versions:${gameVersion}"]`);
    }
    if (loader.length > 0 && projectType === 'mod') {
      facets.push(`["categories:${loader}"]`);
    }
    const facetParam = facets.length > 0 ? `&facets=${encodeURIComponent('[' + facets.join(',') + ']')}` : '';
    const q = query.length > 0 ? encodeURIComponent(query) : '';
    const url = `${ModrinthClient.BASE}/search?query=${q}${facetParam}&index=relevance&offset=${offset}&limit=${limit}`;

    const res = await HttpClient.getJson<ModrinthSearchResult>(url, ModrinthClient.headers());
    if (!res.success || !res.data) {
      Logger.warn(ModrinthClient.TAG, `搜索失败: ${res.error}`);
      return [];
    }
    return res.data.hits ? res.data.hits : [];
  }

  /** 取某个项目在指定 MC 版本 / 加载器下的可用版本（按发布时间倒序） */
  static async getVersions(projectId: string, gameVersion: string, loader: string): Promise<ModrinthVersion[]> {
    let url = `${ModrinthClient.BASE}/project/${projectId}/version`;
    const params: string[] = [];
    if (gameVersion.length > 0) {
      params.push(`game_versions=${encodeURIComponent('["' + gameVersion + '"]')}`);
    }
    if (loader.length > 0) {
      params.push(`loaders=${encodeURIComponent('["' + loader + '"]')}`);
    }
    if (params.length > 0) {
      url += '?' + params.join('&');
    }
    const res = await HttpClient.getJson<ModrinthVersion[]>(url, ModrinthClient.headers());
    if (!res.success || !res.data) {
      Logger.warn(ModrinthClient.TAG, `取版本失败: ${res.error}`);
      return [];
    }
    return res.data;
  }

  /** 取主文件（primary 优先，否则第一个） */
  static primaryFile(version: ModrinthVersion): ModrinthFile | null {
    if (!version.files || version.files.length === 0) {
      return null;
    }
    for (const f of version.files) {
      if (f.primary) {
        return f;
      }
    }
    return version.files[0];
  }
}
