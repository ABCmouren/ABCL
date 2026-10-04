/**
 * I18n — 国际化（对齐 HMCL 的 I18n / lang/*.properties）
 *
 * HMCL 自带 20+ 语言，先做简体中文 / English 两种，
 * 字典结构与 HMCL 的 i18n key 命名保持一致，方便后续直接搬语言包。
 *
 * 用法：
 *   I18n.t('instances.title')          // 按当前语言取值
 *   I18n.setLocale('en-US')            // 切换语言
 *   I18n.supportedLocales()            // 支持的语言列表
 */
import { AppStore } from '../AppStore';
import { Logger } from '../util/Utils';

export type Locale = 'zh-CN' | 'en-US';

export interface LocaleInfo {
  code: Locale;
  label: string;
}

export class I18n {
  private static current: Locale = 'zh-CN';
  private static listeners: ((locale: Locale) => void)[] = [];

  static readonly SUPPORTED: LocaleInfo[] = [
    { code: 'zh-CN', label: '简体中文' },
    { code: 'en-US', label: 'English' }
  ];

  /** 简体中文字典（缺 key 时回退到这里，再回退到 key 本身） */
  private static readonly ZH: Record<string, string> = {
    'app.name': 'ABCL',
    'app.description': 'Minecraft Java 版启动器',

    'nav.instances': '实例列表',
    'nav.download': '下载',
    'nav.accounts': '账户',
    'nav.mods': '模组',
    'nav.resourcepacks': '资源包',
    'nav.shaders': '光影',
    'nav.worlds': '世界',
    'nav.modpacks': '整合包',
    'nav.gamedir': '游戏目录',
    'nav.java': 'Java',
    'nav.logs': '日志',
    'nav.settings': '设置',

    'instance.empty': '还没有已安装的实例',
    'instance.install_hint': '点下面的「安装新游戏」下载一个 Minecraft 版本',
    'instance.install_game': '安装新游戏',
    'instance.launch': '启动游戏',
    'instance.select_instance': '选择左侧的一个实例',
    'instance.installed': '已安装',
    'instance.menu.install_forge': '安装 Forge',
    'instance.menu.install_fabric': '安装 Fabric',
    'instance.menu.install_neoforge': '安装 NeoForge',
    'instance.menu.rename': '重命名实例',
    'instance.menu.save_name': '保存新名称',
    'instance.menu.duplicate': '复制实例',
    'instance.menu.isolate': '开启版本隔离',
    'instance.menu.unisolate': '关闭版本隔离',
    'instance.menu.export': '导出整合包',
    'instance.menu.delete': '删除实例',
    'instance.menu.cancel': '取消',
    'instance.isolated': '已隔离',

    'download.game': '游戏',
    'download.mod': '模组',
    'download.resourcepack': '资源包',
    'download.shader': '光影',
    'download.modpack': '整合包',
    'download.search': '搜索',
    'download.install': '安装',
    'download.reinstall': '重新安装',
    'download.searching': '正在搜索…',
    'download.results': '共 {0} 个结果',
    'download.page': '第 {0} / {1} 页',
    'download.prev': '上一页',
    'download.next': '下一页',
    'download.filter_version': '版本',
    'download.filter_category': '分类',
    'download.filter_loader': '加载器',
    'download.all': '全部',
    'download.cancel': '取消',
    'download.source': '下载源',

    'account.add': '添加账户',
    'account.offline': '离线账号',
    'account.microsoft': '微软账号',
    'account.authlib': 'Authlib-Injector',
    'account.select': '选择',
    'account.selected': '当前使用',
    'account.remove': '删除',
    'account.no_account': '还没有账户',
    'account.login_failed': '登录失败',

    'mod.title': '模组',
    'mod.empty': '这个实例还没有安装模组',
    'mod.enabled': '已启用',
    'mod.disabled': '已禁用',
    'mod.detail': '详情',
    'mod.delete': '删除',
    'mod.version': '版本',
    'mod.author': '作者',
    'mod.loader': '加载器',

    'world.title': '世界',
    'world.empty': '还没有存档',
    'world.backup': '备份',
    'world.rename': '重命名',
    'world.delete': '删除',
    'world.no_level_dat': '缺少 level.dat',

    'gamedir.title': '.minecraft 位置',
    'gamedir.change': '修改位置',
    'gamedir.open': '打开 .minecraft 文件夹',
    'gamedir.import': '导入 .minecraft 备份',
    'gamedir.pick': '从外部选择',
    'gamedir.ensure': '补建缺失目录',
    'gamedir.total': '总占用',

    'java.title': 'Java 运行时',
    'java.import': '导入 JDK',
    'java.set_default': '设为默认',
    'java.auto': '自动选择',
    'java.jre_only': '仅 JRE，不可启动游戏',

    'log.title': '日志',
    'log.clear': '清空内存',
    'log.location': '位置',
    'log.crash': '崩溃报告',

    'common.ok': '确定',
    'common.cancel': '取消',
    'common.close': '关闭',
    'common.refresh': '刷新',
    'common.save': '保存',
    'common.loading': '加载中…',
    'common.search': '搜索…',
    'common.unknown': '未知'
  };

  private static readonly EN: Record<string, string> = {
    'app.name': 'ABCL',
    'app.description': 'Minecraft Java Edition Launcher',

    'nav.instances': 'Instances',
    'nav.download': 'Download',
    'nav.accounts': 'Accounts',
    'nav.mods': 'Mods',
    'nav.resourcepacks': 'Resource Packs',
    'nav.shaders': 'Shaders',
    'nav.worlds': 'Worlds',
    'nav.modpacks': 'Modpacks',
    'nav.gamedir': 'Game Directory',
    'nav.java': 'Java',
    'nav.logs': 'Logs',
    'nav.settings': 'Settings',

    'instance.empty': 'No instances installed',
    'instance.install_hint': 'Click "Install New Game" below to download a Minecraft version',
    'instance.install_game': 'Install New Game',
    'instance.launch': 'Launch',
    'instance.select_instance': 'Select an instance on the left',
    'instance.installed': 'Installed',
    'instance.menu.install_forge': 'Install Forge',
    'instance.menu.install_fabric': 'Install Fabric',
    'instance.menu.install_neoforge': 'Install NeoForge',
    'instance.menu.rename': 'Rename',
    'instance.menu.save_name': 'Save Name',
    'instance.menu.duplicate': 'Duplicate',
    'instance.menu.isolate': 'Enable Isolation',
    'instance.menu.unisolate': 'Disable Isolation',
    'instance.menu.export': 'Export Modpack',
    'instance.menu.delete': 'Delete Instance',
    'instance.menu.cancel': 'Cancel',
    'instance.isolated': 'Isolated',

    'download.game': 'Game',
    'download.mod': 'Mods',
    'download.resourcepack': 'Resource Packs',
    'download.shader': 'Shaders',
    'download.modpack': 'Modpacks',
    'download.search': 'Search',
    'download.install': 'Install',
    'download.reinstall': 'Reinstall',
    'download.searching': 'Searching…',
    'download.results': '{0} results',
    'download.page': 'Page {0} / {1}',
    'download.prev': 'Previous',
    'download.next': 'Next',
    'download.filter_version': 'Version',
    'download.filter_category': 'Category',
    'download.filter_loader': 'Loader',
    'download.all': 'All',
    'download.cancel': 'Cancel',
    'download.source': 'Download Source',

    'account.add': 'Add Account',
    'account.offline': 'Offline',
    'account.microsoft': 'Microsoft',
    'account.authlib': 'Authlib Injector',
    'account.select': 'Select',
    'account.selected': 'In Use',
    'account.remove': 'Remove',
    'account.no_account': 'No accounts yet',
    'account.login_failed': 'Login failed',

    'mod.title': 'Mods',
    'mod.empty': 'No mods installed in this instance',
    'mod.enabled': 'Enabled',
    'mod.disabled': 'Disabled',
    'mod.detail': 'Details',
    'mod.delete': 'Delete',
    'mod.version': 'Version',
    'mod.author': 'Author',
    'mod.loader': 'Loader',

    'world.title': 'Worlds',
    'world.empty': 'No saves yet',
    'world.backup': 'Backup',
    'world.rename': 'Rename',
    'world.delete': 'Delete',
    'world.no_level_dat': 'Missing level.dat',

    'gamedir.title': '.minecraft Location',
    'gamedir.change': 'Change',
    'gamedir.open': 'Open .minecraft Folder',
    'gamedir.import': 'Import .minecraft Backup',
    'gamedir.pick': 'Pick Externally',
    'gamedir.ensure': 'Create Missing Dirs',
    'gamedir.total': 'Total Size',

    'java.title': 'Java Runtimes',
    'java.import': 'Import JDK',
    'java.set_default': 'Set Default',
    'java.auto': 'Auto',
    'java.jre_only': 'JRE only, cannot launch',

    'log.title': 'Logs',
    'log.clear': 'Clear Memory',
    'log.location': 'Location',
    'log.crash': 'Crash Reports',

    'common.ok': 'OK',
    'common.cancel': 'Cancel',
    'common.close': 'Close',
    'common.refresh': 'Refresh',
    'common.save': 'Save',
    'common.loading': 'Loading…',
    'common.search': 'Search…',
    'common.unknown': 'Unknown'
  };

  static init(): void {
    const cfg = AppStore.getInstance().config.language;
    I18n.setLocale(cfg === 'en-US' ? 'en-US' : 'zh-CN');
  }

  static locale(): Locale {
    return I18n.current;
  }

  static setLocale(locale: Locale): void {
    I18n.current = locale;
    for (const cb of I18n.listeners) {
      cb(locale);
    }
  }

  static onLocaleChanged(cb: (locale: Locale) => void): () => void {
    I18n.listeners.push(cb);
    return () => {
      I18n.listeners = I18n.listeners.filter((c: (l: Locale) => void) => c !== cb);
    };
  }

  /** 取翻译；缺 key 时返回 key 本身，便于发现遗漏 */
  static t(key: string): string {
    const dict: Record<string, string> = I18n.current === 'en-US' ? I18n.EN : I18n.ZH;
    const v = dict[key];
    if (v !== undefined) {
      return v;
    }
    const fallback = I18n.ZH[key];
    return fallback !== undefined ? fallback : key;
  }

  /** 带参数的翻译：把 {0} {1} 依次替换 */
  static f(key: string, args: string[]): string {
    let s = I18n.t(key);
    for (let i = 0; i < args.length; i++) {
      s = s.replace('{' + i + '}', args[i]);
    }
    return s;
  }

  static supported(): LocaleInfo[] {
    return I18n.SUPPORTED;
  }
}
