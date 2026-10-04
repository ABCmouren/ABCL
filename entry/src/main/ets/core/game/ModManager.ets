/**
 * ModManager — 真实的模组管理（读文件系统，不是假数据）
 *
 * HMCL 的模组列表来自实例游戏目录下的 mods/ 文件夹：
 *   - 启用中的模组：<name>.jar
 *   - 已禁用的模组：<name>.jar.disabled
 * 元数据从 jar 内的 fabric.mod.json / META-INF/mods.toml / mcmod.info 读取。
 *
 * 注意：@ohos.zlib 只能整包解压，不能按条目读取，所以元数据解析是
 * 「解压到临时目录 → 读那几个文件 → 删临时目录」，只对列表异步补全，
 * 并且对超大 jar 做上限保护，避免一次解析几十个几百 MB 的包。
 */
import { ArchiveUtils, FileUtils, Logger } from '../util/Utils';
import { Constants } from '../../config/Constants';

export interface InstalledMod {
  /** 磁盘文件名（含 .disabled 后缀） */
  fileName: string;
  /** 绝对路径 */
  path: string;
  /** 不含 .disabled 的 jar 名 */
  jarName: string;
  enabled: boolean;
  size: number;
  /** 元数据展示名，未解析时回退为 jarName */
  name: string;
  version: string;
  authors: string;
  /** fabric / forge / neoforge / quilt / unknown */
  loader: string;
  description: string;
  /** 元数据是否已解析 */
  metaLoaded: boolean;
}

export interface ModMetadata {
  name: string;
  version: string;
  authors: string;
  loader: string;
  description: string;
}

interface FabricModJson {
  id?: string;
  name?: string;
  version?: string;
  description?: string;
  authors?: (string | FabricPerson)[];
}

interface FabricPerson {
  name?: string;
}

interface LegacyModInfo {
  name?: string;
  version?: string;
  authorList?: string[];
  description?: string;
}

export class ModManager {
  private static readonly TAG = 'ModManager';
  /** 超过这个大小的 jar 不解析元数据（解压整包代价太高） */
  private static readonly META_SIZE_LIMIT = 40 * 1024 * 1024;
  private static readonly metaCache: Map<string, ModMetadata> = new Map();

  /** 模组目录（HMCL 默认所有实例共用同一个 .minecraft） */
  static modsDir(mcDir: string): string {
    return `${mcDir}/${Constants.MODS_DIR}`;
  }

  /** 扫描已安装模组（同步、只读文件名与大小，快） */
  static scan(mcDir: string): InstalledMod[] {
    const dir = ModManager.modsDir(mcDir);
    const result: InstalledMod[] = [];
    if (!FileUtils.exists(dir)) {
      return result;
    }
    for (const entry of FileUtils.listDir(dir)) {
      const lower = entry.toLowerCase();
      if (!lower.endsWith('.jar') && !lower.endsWith('.jar.disabled')) {
        continue;
      }
      const enabled = lower.endsWith('.jar');
      const jarName = enabled ? entry : entry.substring(0, entry.length - '.disabled'.length);
      const full = `${dir}/${entry}`;
      const mod: InstalledMod = {
        fileName: entry,
        path: full,
        jarName: jarName,
        enabled: enabled,
        size: FileUtils.getFileSize(full),
        name: jarName.replace(/\.jar$/i, ''),
        version: '',
        authors: '',
        loader: '',
        description: '',
        metaLoaded: false
      };
      const cached = ModManager.metaCache.get(ModManager.cacheKey(full));
      if (cached) {
        ModManager.applyMeta(mod, cached);
      }
      result.push(mod);
    }
    // 启用优先、再按名字排序（与 HMCL 观感一致）
    result.sort((a: InstalledMod, b: InstalledMod) => {
      if (a.enabled !== b.enabled) {
        return a.enabled ? -1 : 1;
      }
      return a.jarName.localeCompare(b.jarName);
    });
    return result;
  }

  /** 启用 / 禁用（重命名 .jar ↔ .jar.disabled），返回新的文件名 */
  static setEnabled(mod: InstalledMod, enabled: boolean): string {
    if (mod.enabled === enabled) {
      return mod.fileName;
    }
    const dir = FileUtils.getDirName(mod.path);
    const target = enabled ? `${dir}/${mod.jarName}` : `${dir}/${mod.jarName}.disabled`;
    try {
      FileUtils.moveFile(mod.path, target);
      Logger.info(ModManager.TAG, `${enabled ? '启用' : '禁用'} 模组 ${mod.jarName}`);
      return target.substring(target.lastIndexOf('/') + 1);
    } catch (e) {
      Logger.error(ModManager.TAG, `切换模组状态失败 ${mod.jarName}`, e as Error);
      return mod.fileName;
    }
  }

  static delete(mod: InstalledMod): void {
    FileUtils.delete(mod.path);
    ModManager.metaCache.delete(ModManager.cacheKey(mod.path));
    Logger.info(ModManager.TAG, `删除模组 ${mod.fileName}`);
  }

  /** 从已下载的 jar 安装到 mods/（带重名处理） */
  static installJar(mcDir: string, sourcePath: string, fileName: string): string {
    const dir = ModManager.modsDir(mcDir);
    FileUtils.mkdirs(dir);
    let target = `${dir}/${fileName}`;
    let counter = 1;
    while (FileUtils.exists(target)) {
      const dot = fileName.toLowerCase().lastIndexOf('.jar');
      const base = dot > 0 ? fileName.substring(0, dot) : fileName;
      target = `${dir}/${base}-(${counter}).jar`;
      counter++;
    }
    FileUtils.copyFile(sourcePath, target);
    FileUtils.delete(sourcePath);
    Logger.info(ModManager.TAG, `安装模组 → ${target}`);
    return target;
  }

  // ============================================================
  //  元数据
  // ============================================================

  /**
   * 解析 jar 元数据（会解压整包到临时目录）。
   * 调用方应放在后台、逐个进行，并把结果回填到列表。
   */
  static async readMetadata(mod: InstalledMod, tempRoot: string): Promise<ModMetadata | null> {
    const key = ModManager.cacheKey(mod.path);
    const cached = ModManager.metaCache.get(key);
    if (cached) {
      return cached;
    }
    if (mod.size > ModManager.META_SIZE_LIMIT) {
      Logger.info(ModManager.TAG, `${mod.jarName} 超过元数据解析上限，跳过`);
      return null;
    }

    const tempDir = `${tempRoot}/modmeta-${Math.abs(ModManager.hash(mod.jarName))}`;
    try {
      const ok = await ArchiveUtils.unzip(mod.path, tempDir);
      if (!ok) {
        return null;
      }
      const meta = ModManager.parseFromDir(tempDir, mod.jarName);
      if (meta) {
        ModManager.metaCache.set(key, meta);
        Logger.info(ModManager.TAG,
          `元数据 ${mod.jarName} → name=${meta.name} ver=${meta.version} loader=${meta.loader}`);
      } else {
        Logger.info(ModManager.TAG, `${mod.jarName} 未找到可识别的元数据文件`);
      }
      return meta;
    } catch (e) {
      Logger.warn(ModManager.TAG, `解析 ${mod.jarName} 元数据失败: ${(e as Error).message}`);
      return null;
    } finally {
      FileUtils.delete(tempDir);
    }
  }

  static applyMeta(mod: InstalledMod, meta: ModMetadata): void {
    mod.name = meta.name.length > 0 ? meta.name : mod.name;
    mod.version = meta.version;
    mod.authors = meta.authors;
    mod.loader = meta.loader;
    mod.description = meta.description;
    mod.metaLoaded = true;
  }

  /** 从解压目录里挑一个已知的元数据文件来解析 */
  private static parseFromDir(dir: string, fallbackName: string): ModMetadata | null {
    const fabric = `${dir}/fabric.mod.json`;
    if (FileUtils.exists(fabric)) {
      return ModManager.parseFabric(FileUtils.readFile(fabric), fallbackName);
    }
    const quilt = `${dir}/quilt.mod.json`;
    if (FileUtils.exists(quilt)) {
      return ModManager.parseFabric(FileUtils.readFile(quilt), fallbackName);
    }
    const forge = `${dir}/META-INF/mods.toml`;
    if (FileUtils.exists(forge)) {
      return ModManager.parseToml(FileUtils.readFile(forge), 'forge', fallbackName);
    }
    const neo = `${dir}/META-INF/neoforge.mods.toml`;
    if (FileUtils.exists(neo)) {
      return ModManager.parseToml(FileUtils.readFile(neo), 'neoforge', fallbackName);
    }
    const legacy = `${dir}/mcmod.info`;
    if (FileUtils.exists(legacy)) {
      return ModManager.parseLegacy(FileUtils.readFile(legacy), fallbackName);
    }
    // 包名为空壳（只有 classes）时也算识别失败
    return null;
  }

  private static parseFabric(text: string, fallbackName: string): ModMetadata | null {
    try {
      const json = JSON.parse(text) as FabricModJson;
      let authors = '';
      if (json.authors) {
        const names: string[] = [];
        for (const a of json.authors) {
          if (typeof a === 'string') {
            names.push(a as string);
          } else {
            const person = a as FabricPerson;
            if (person.name) {
              names.push(person.name);
            }
          }
        }
        authors = names.join(', ');
      }
      return {
        name: json.name ? json.name : (json.id ? json.id : fallbackName),
        version: json.version ? json.version : '',
        authors: authors,
        loader: 'fabric',
        description: json.description ? json.description : ''
      };
    } catch (e) {
      return null;
    }
  }

  /** 极简 TOML 读取：只取第一个 [[mods]] 段里的 displayName / version / authors / description */
  private static parseToml(text: string, loader: string, fallbackName: string): ModMetadata | null {
    const name = ModManager.tomlValue(text, 'displayName');
    const version = ModManager.tomlValue(text, 'version');
    const authors = ModManager.tomlValue(text, 'authors');
    const description = ModManager.tomlValue(text, 'description');
    if (!name && !version) {
      return null;
    }
    return {
      name: name ? name : fallbackName,
      version: version ? version : '',
      authors: authors ? authors : '',
      loader: loader,
      description: description ? description : ''
    };
  }

  private static tomlValue(text: string, key: string): string {
    const regex = new RegExp(`^\\s*${key}\\s*=\\s*(.+)$`, 'm');
    const m = regex.exec(text);
    if (!m) {
      return '';
    }
    let value = m[1].trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1).replace(/"/g, '').trim();
    }
    return value;
  }

  private static parseLegacy(text: string, fallbackName: string): ModMetadata | null {
    try {
      const parsed = JSON.parse(text) as LegacyModInfo[];
      if (!parsed || parsed.length === 0) {
        return null;
      }
      const first = parsed[0];
      return {
        name: first.name ? first.name : fallbackName,
        version: first.version ? first.version : '',
        authors: first.authorList ? first.authorList.join(', ') : '',
        loader: 'forge',
        description: first.description ? first.description : ''
      };
    } catch (e) {
      return null;
    }
  }

  private static cacheKey(path: string): string {
    return `${path}|${FileUtils.getFileSize(path)}`;
  }

  private static hash(input: string): number {
    let h = 0;
    for (let i = 0; i < input.length; i++) {
      h = ((h << 5) - h) + input.charCodeAt(i);
      h = h & h;
    }
    return h;
  }
}
