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

/** /tag/category 返回项（对应 HMCL 的 RemoteAddonRepository.Category） */
export interface ModrinthCategory {
  name: string;
  project_type: string;
  header: string;
  icon?: string;
}

export interface ModrinthGameVersionTag {
  version: string;
  version_type: string;
  major: boolean;
  date?: string;
}

export interface ModrinthLoaderTag {
  name: string;
  supported_project_types: string[];
}

/** 搜索分页结果（对齐 HMCL 的 RemoteAddonRepository.SearchResult） */
export interface ModrinthSearchPage {
  hits: ModrinthSearchHit[];
  offset: number;
  limit: number;
  totalHits: number;
  /** 总页数 = ceil(totalHits / limit)，与 HMCL 一致 */
  pageCount: number;
}

export class ModrinthClient {
  private static readonly TAG = 'Modrinth';
  private static readonly BASE = 'https://api.modrinth.com/v2';
  /** HMCL DownloadListPage 用的就是 50 */
  static readonly PAGE_SIZE = 50;

  /** Modrinth 的排序索引（对应 HMCL 的 SortType） */
  static readonly SORT_RELEVANCE = 'relevance';
  static readonly SORT_DOWNLOADS = 'downloads';
  static readonly SORT_FOLLOWS = 'follows';
  static readonly SORT_NEWEST = 'newest';
  static readonly SORT_UPDATED = 'updated';

  private static headers(): Record<string, string> {
    const h: Record<string, string> = {};
    h['User-Agent'] = 'ABCmouren/ABCL/2.0.0 (HarmonyOS Minecraft Launcher)';
    h['Accept'] = 'application/json';
    return h;
  }

  /**
   * 搜索项目（分页，语义对齐 HMCL 的 RemoteAddonRepository.search）
   *
   * @param pageOffset 页号，从 0 开始；请求里换算式为 pageOffset * pageSize
   * @param projectType mod | resourcepack | shader | modpack | datapack
   * @param sort relevance | downloads | follows | newest | updated
   */
  static async search(
    query: string,
    projectType: string,
    gameVersion: string,
    loader: string,
    pageOffset: number = 0,
    pageSize: number = ModrinthClient.PAGE_SIZE,
    sort: string = ModrinthClient.SORT_RELEVANCE,
    category: string = ''
  ): Promise<ModrinthSearchPage> {
    const empty: ModrinthSearchPage = {
      hits: [], offset: pageOffset, limit: pageSize, totalHits: 0, pageCount: 0
    };
    // facets 允许出现多个同名类别（HMCL 也是 List<List<String>>）
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
    // 分类与加载器同为 categories facet，HMCL 也是分成两组（组内 OR、组间 AND）
    if (category.length > 0) {
      facets.push(`["categories:${category}"]`);
    }
    const parts: string[] = [];
    parts.push(`query=${query.length > 0 ? encodeURIComponent(query) : ''}`);
    if (facets.length > 0) {
      parts.push(`facets=${encodeURIComponent('[' + facets.join(',') + ']')}`);
    }
    parts.push(`index=${sort}`);
    parts.push(`offset=${pageOffset * pageSize}`);
    parts.push(`limit=${pageSize}`);
    const url = `${ModrinthClient.BASE}/search?${parts.join('&')}`;

    const res = await HttpClient.getJson<ModrinthSearchResult>(url, ModrinthClient.headers());
    if (!res.success || !res.data) {
      Logger.warn(ModrinthClient.TAG, `搜索失败: ${res.error}`);
      return empty;
    }
    const total = res.data.total_hits ? res.data.total_hits : 0;
    return {
      hits: res.data.hits ? res.data.hits : [],
      offset: pageOffset,
      limit: pageSize,
      totalHits: total,
      pageCount: pageSize > 0 ? Math.ceil(total / pageSize) : 0
    };
  }

  // ============================================================
  //  标签（对应 HMCL 的 getCategories / 版本列表 / 加载器列表）
  // ============================================================

  /** 分类列表（按 project_type 过滤） */
  static async getCategories(projectType: string): Promise<ModrinthCategory[]> {
    const res = await HttpClient.getJson<ModrinthCategory[]>(`${ModrinthClient.BASE}/tag/category`, ModrinthClient.headers());
    if (!res.success || !res.data) {
      Logger.warn(ModrinthClient.TAG, `分类拉取失败: ${res.error}`);
      return [];
    }
    const out: ModrinthCategory[] = [];
    for (const c of res.data) {
      if (projectType.length === 0 || c.project_type === projectType) {
        out.push(c);
      }
    }
    return out;
  }

  /** 全部游戏版本（含快照），按接口返回顺序（新的在前） */
  static async getGameVersions(): Promise<ModrinthGameVersionTag[]> {
    const res = await HttpClient.getJson<ModrinthGameVersionTag[]>(`${ModrinthClient.BASE}/tag/game_version`, ModrinthClient.headers());
    if (!res.success || !res.data) {
      Logger.warn(ModrinthClient.TAG, `游戏版本标签拉取失败: ${res.error}`);
      return [];
    }
    return res.data;
  }

  /** 加载器列表（按 project_type 过滤） */
  static async getLoaders(projectType: string): Promise<string[]> {
    const res = await HttpClient.getJson<ModrinthLoaderTag[]>(`${ModrinthClient.BASE}/tag/loader`, ModrinthClient.headers());
    if (!res.success || !res.data) {
      Logger.warn(ModrinthClient.TAG, `加载器标签拉取失败: ${res.error}`);
      return [];
    }
    const out: string[] = [];
    for (const l of res.data) {
      const types = l.supported_project_types ? l.supported_project_types : [];
      if (types.indexOf(projectType) >= 0) {
        out.push(l.name);
      }
    }
    return out;
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
