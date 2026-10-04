/**
 * CurseForgeClient — CurseForge 官方 API v1 客户端
 *
 * 对应 HMCL 的 CurseForgeRemoteAddonRepository。
 * CurseForge 强制要求 x-api-key，而且 key 不能共享/内置（每个应用要自己申请），
 * 所以这里由用户在设置里填自己的 key；没填时所有调用直接返回空并给出明确提示。
 *
 * classId:  mods=6, resourcepacks=12, shaders=6552, modpacks=4471
 * modLoaderType: forge=1, fabric=4, quilt=5, neoforge=6
 * sortField: featured=1, popularity=2, lastUpdated=3, name=4, totalDownloads=6
 */
import { HttpClient } from '../network/HttpClient';
import { Mirrors } from '../network/Mirrors';
import { Logger } from '../util/Utils';
import {
  ModrinthSearchHit, ModrinthVersion, ModrinthFile, ModrinthSearchPage,
  ModrinthHashes, ModrinthDependency
} from './ModrinthClient';

export interface CfAuthor {
  name: string;
}

export interface CfLogo {
  url: string;
}

export interface CfHashes {
  value: string;
  algo: number;
}

export interface CfDependency {
  modId: number;
  relationType: number;
}

export interface CfFile {
  id: number;
  displayName: string;
  fileName: string;
  releaseType: number;
  fileDate: string;
  fileLength: number;
  downloadCount: number;
  downloadUrl: string;
  gameVersions: string[];
  hashes: CfHashes[];
  dependencies: CfDependency[];
}

export interface CfMod {
  id: number;
  name: string;
  slug: string;
  summary: string;
  downloadCount: number;
  authors: CfAuthor[];
  logo: CfLogo;
  classId: number;
  dateModified: string;
  latestFiles: CfFile[];
}

export interface CfPagination {
  index: number;
  pageSize: number;
  resultCount: number;
  totalCount: number;
}

export interface CfModListResponse {
  data: CfMod[];
  pagination: CfPagination;
}

export interface CfFileListResponse {
  data: CfFile[];
  pagination?: CfPagination;
}

export interface CfCategory {
  id: number;
  name: string;
  classId: number;
}

export interface CfCategoryResponse {
  data: CfCategory[];
}

export class CurseForgeClient {
  private static readonly TAG = 'CurseForge';
  private static readonly GAME_ID = 432;
  /**
   * CurseForge 每条 mod 都带完整 HTML 描述，响应特别大：
   * 实测镜像源 pageSize=50 要 1.3MB / 42s，所以降到 25，
   * 并把读超时拉到 120s（默认 30s 会直接 timeout）。
   */
  static readonly PAGE_SIZE = 25;
  static readonly READ_TIMEOUT_MS = 120000;

  private static apiKey: string = '';
  /**
   * 走 mcimirror 镜像（默认开）。
   * 镜像不需要 API Key —— 这正是 HMCL 的 CurseForge「开箱可用」的原因：
   *   new MirrorRule("https://api.curseforge.com", "https://mod.mcimirror.top/curseforge", true)
   * 官方 api.curseforge.com 仍然要求每个应用自备 key。
   */
  private static useMirror: boolean = true;

  static setApiKey(key: string): void {
    CurseForgeClient.apiKey = key;
  }

  static setUseMirror(on: boolean): void {
    CurseForgeClient.useMirror = on;
  }

  static hasApiKey(): boolean {
    return CurseForgeClient.apiKey.length > 0;
  }

  /** 镜像永远可用；官方源必须有 key */
  static isAvailable(): boolean {
    return CurseForgeClient.useMirror || CurseForgeClient.hasApiKey();
  }

  static isMirror(): boolean {
    return CurseForgeClient.useMirror || !CurseForgeClient.hasApiKey();
  }

  private static base(): string {
    // 没有 key 时强制走镜像，避免 403
    return Mirrors.curseforgeBase(CurseForgeClient.isMirror());
  }

  private static headers(): Record<string, string> {
    const h: Record<string, string> = {};
    if (CurseForgeClient.apiKey.length > 0) {
      h['x-api-key'] = CurseForgeClient.apiKey;
    }
    h['Accept'] = 'application/json';
    return h;
  }

  /** 项目类型 → classId */
  static classId(projectType: string): number {
    if (projectType === 'resourcepack') {
      return 12;
    }
    if (projectType === 'shader') {
      return 6552;
    }
    if (projectType === 'modpack') {
      return 4471;
    }
    if (projectType === 'datapack') {
      return 6945;
    }
    return 6;
  }

  /** 加载器名 → modLoaderType */
  static loaderId(loader: string): number {
    if (loader === 'forge') {
      return 1;
    }
    if (loader === 'fabric') {
      return 4;
    }
    if (loader === 'quilt') {
      return 5;
    }
    if (loader === 'neoforge') {
      return 6;
    }
    return 0;
  }

  /** 排序 → sortField */
  static sortField(sort: string): number {
    if (sort === 'downloads') {
      return 6;
    }
    if (sort === 'follows') {
      return 2;
    }
    if (sort === 'newest') {
      return 11;
    }
    if (sort === 'updated') {
      return 3;
    }
    return 1;
  }

  /**
   * 搜索（分页语义与 Modrinth 客户端保持一致：pageOffset 从 0 开始）
   */
  static async search(
    query: string,
    projectType: string,
    gameVersion: string,
    loader: string,
    pageOffset: number,
    pageSize: number,
    sort: string,
    categoryId: number
  ): Promise<ModrinthSearchPage> {
    const empty: ModrinthSearchPage = {
      hits: [], offset: pageOffset, limit: pageSize, totalHits: 0, pageCount: 0
    };
    if (!CurseForgeClient.isAvailable()) {
      Logger.warn(CurseForgeClient.TAG, 'CurseForge 不可用（官方源需要 API Key）');
      return empty;
    }
    const parts: string[] = [];
    parts.push(`gameId=${CurseForgeClient.GAME_ID}`);
    parts.push(`classId=${CurseForgeClient.classId(projectType)}`);
    parts.push(`searchFilter=${query.length > 0 ? encodeURIComponent(query) : ''}`);
    if (gameVersion.length > 0) {
      parts.push(`gameVersion=${encodeURIComponent(gameVersion)}`);
    }
    const loaderId = CurseForgeClient.loaderId(loader);
    if (loaderId > 0 && projectType === 'mod') {
      parts.push(`modLoaderType=${loaderId}`);
    }
    if (categoryId > 0) {
      parts.push(`categoryId=${categoryId}`);
    }
    parts.push(`sortField=${CurseForgeClient.sortField(sort)}`);
    parts.push('sortOrder=desc');
    parts.push(`index=${pageOffset * pageSize}`);
    parts.push(`pageSize=${pageSize}`);

    const url = `${CurseForgeClient.base()}/mods/search?${parts.join('&')}`;
    const res = await HttpClient.getJson<CfModListResponse>(url, CurseForgeClient.headers(), CurseForgeClient.READ_TIMEOUT_MS);
    if (!res.success || !res.data) {
      Logger.warn(CurseForgeClient.TAG, `搜索失败: ${res.error}`);
      return empty;
    }
    const hits: ModrinthSearchHit[] = [];
    const list = res.data.data ? res.data.data : [];
    for (const m of list) {
      hits.push(CurseForgeClient.toHit(m, projectType));
    }
    const total = res.data.pagination ? res.data.pagination.totalCount : hits.length;
    return {
      hits: hits,
      offset: pageOffset,
      limit: pageSize,
      totalHits: total,
      pageCount: pageSize > 0 ? Math.ceil(total / pageSize) : 0
    };
  }

  private static toHit(m: CfMod, projectType: string): ModrinthSearchHit {
    let author = '';
    if (m.authors && m.authors.length > 0) {
      author = m.authors[0].name;
    }
    const hit: ModrinthSearchHit = {
      project_id: m.id.toString(),
      slug: m.slug,
      title: m.name,
      description: m.summary,
      author: author,
      downloads: m.downloadCount,
      follows: 0,
      icon_url: m.logo ? m.logo.url : '',
      categories: [],
      versions: [],
      project_type: projectType
    };
    return hit;
  }

  /** 分类列表（按 classId 过滤） */
  static async getCategories(projectType: string): Promise<CfCategory[]> {
    if (!CurseForgeClient.isAvailable()) {
      return [];
    }
    const url = `${CurseForgeClient.base()}/categories?gameId=${CurseForgeClient.GAME_ID}`;
    const res = await HttpClient.getJson<CfCategoryResponse>(url, CurseForgeClient.headers(), CurseForgeClient.READ_TIMEOUT_MS);
    if (!res.success || !res.data || !res.data.data) {
      Logger.warn(CurseForgeClient.TAG, `分类拉取失败: ${res.error}`);
      return [];
    }
    const want = CurseForgeClient.classId(projectType);
    const out: CfCategory[] = [];
    for (const c of res.data.data) {
      if (c.classId === want) {
        out.push(c);
      }
    }
    return out;
  }

  /** 取项目的文件列表，并映射成 UI 用的 ModrinthVersion 形状 */
  static async getFiles(modId: string, gameVersion: string, loader: string, projectType: string): Promise<ModrinthVersion[]> {
    if (!CurseForgeClient.isAvailable()) {
      return [];
    }
    const parts: string[] = [];
    if (gameVersion.length > 0) {
      parts.push(`gameVersion=${encodeURIComponent(gameVersion)}`);
    }
    const loaderId = CurseForgeClient.loaderId(loader);
    if (loaderId > 0 && projectType === 'mod') {
      parts.push(`modLoaderType=${loaderId}`);
    }
    parts.push('index=0');
    parts.push('pageSize=50');
    const url = `${CurseForgeClient.base()}/mods/${modId}/files?${parts.join('&')}`;
    const res = await HttpClient.getJson<CfFileListResponse>(url, CurseForgeClient.headers(), CurseForgeClient.READ_TIMEOUT_MS);
    if (!res.success || !res.data || !res.data.data) {
      Logger.warn(CurseForgeClient.TAG, `文件列表失败: ${res.error}`);
      return [];
    }
    const out: ModrinthVersion[] = [];
    for (const f of res.data.data) {
      out.push(CurseForgeClient.toVersion(f, modId));
    }
    return out;
  }

  private static toVersion(f: CfFile, modId: string): ModrinthVersion {
    const files: ModrinthFile[] = [];
    const hash: ModrinthHashes = { sha1: '', sha512: '' };
    if (f.hashes) {
      for (const h of f.hashes) {
        // algo: 1 = sha1, 2 = md5
        if (h.algo === 1) {
          hash.sha1 = h.value;
        }
      }
    }
    const rawUrl = f.downloadUrl ? f.downloadUrl : '';
    const file: ModrinthFile = {
      hashes: hash,
      url: Mirrors.rewriteDownloadUrl(rawUrl, CurseForgeClient.isMirror()),
      filename: f.fileName,
      size: f.fileLength,
      primary: true
    };
    files.push(file);
    const deps: ModrinthDependency[] = [];
    if (f.dependencies) {
      for (const d of f.dependencies) {
        deps.push({ project_id: d.modId.toString(), dependency_type: d.relationType === 3 ? 'required' : 'optional' });
      }
    }
    let releaseName = '正式版';
    if (f.releaseType === 2) {
      releaseName = 'Beta';
    } else if (f.releaseType === 3) {
      releaseName = 'Alpha';
    }
    const version: ModrinthVersion = {
      id: f.id.toString(),
      project_id: modId,
      name: f.displayName ? f.displayName : f.fileName,
      version_number: f.displayName ? f.displayName : f.fileName,
      game_versions: f.gameVersions ? f.gameVersions : [],
      loaders: [],
      files: files,
      date_published: f.fileDate,
      dependencies: deps,
      version_type: releaseName
    };
    return version;
  }
}


