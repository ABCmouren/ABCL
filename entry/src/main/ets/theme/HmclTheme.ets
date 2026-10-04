/**
 * HmclTheme — HMCL 官方主题色板（取自 HMCL 源码 assets/css/blue.css）
 *
 * HMCL 的界面用 JavaFX CSS 的 -monet-* 变量，这里是同一个 Material 3 色板的
 * ArkTS 常量版本，保证移植后的视觉与 HMCL 原生一致。
 */
export class HmclTheme {
  // primary
  static readonly PRIMARY = '#4352A5';
  static readonly ON_PRIMARY = '#FFFFFF';
  /** HMCL 的标志性蓝色（启动按钮 / 侧边栏） */
  static readonly PRIMARY_CONTAINER = '#5C6BC0';
  static readonly ON_PRIMARY_CONTAINER = '#F8F6FF';
  static readonly PRIMARY_FIXED_DIM = '#BAC3FF';

  // secondary
  static readonly SECONDARY = '#575C7F';
  static readonly ON_SECONDARY = '#FFFFFF';
  /** 列表选中态 */
  static readonly SECONDARY_CONTAINER = '#D0D5FD';
  static readonly SECONDARY_CONTAINER_TRANSPARENT_50 = '#D0D5FD80';
  static readonly ON_SECONDARY_CONTAINER = '#565B7D';

  // tertiary / error
  static readonly TERTIARY = '#775200';
  static readonly ERROR = '#BA1A1A';
  static readonly ERROR_CONTAINER = '#FFDAD6';
  static readonly ON_ERROR_CONTAINER = '#93000A';

  // surface
  static readonly SURFACE = '#FBF8FF';
  static readonly ON_SURFACE = '#1B1B21';
  static readonly SURFACE_CONTAINER_LOWEST = '#FFFFFF';
  static readonly SURFACE_CONTAINER_LOW = '#F5F2FA';
  static readonly SURFACE_CONTAINER = '#EFEDF5';
  static readonly SURFACE_CONTAINER_HIGH = '#E9E7EF';
  static readonly SURFACE_CONTAINER_HIGHEST = '#E3E1E9';
  static readonly SURFACE_VARIANT = '#E2E1EF';
  static readonly ON_SURFACE_VARIANT = '#454651';
  static readonly INVERSE_SURFACE = '#303036';
  static readonly INVERSE_ON_SURFACE = '#F2EFF7';

  // outline
  static readonly OUTLINE = '#767683';
  static readonly OUTLINE_VARIANT = '#C6C5D3';

  // card 背景（.card 用 surface-container-low-transparent-80）
  static readonly CARD = '#F5F2FACC';
  static readonly CARD_SOLID = '#F5F2FA';

  // 尺寸（对齐 HMCL 的 .md-list-cell / .launch-pane）
  static readonly TITLE_BAR_HEIGHT = 44;
  static readonly NAV_WIDTH = 200;
  static readonly LIST_CELL_HEIGHT = 56;
  static readonly LIST_ICON_SIZE = 32;
  static readonly LAUNCH_BUTTON_HEIGHT = 48;
  static readonly LAUNCH_BUTTON_RADIUS = 24;
  static readonly CARD_RADIUS = 12;
}

/** 页面导航项（HMCL 侧边栏） */
export interface NavEntry {
  key: string;
  label: string;
  glyph: string;
}

/**
 * 侧栏导航。
 * label 是 i18n key（nav.xxx），实际显示时用 I18n.t() 取值。
 */
export const HMCL_NAV: NavEntry[] = [
  { key: 'instances', label: 'nav.instances', glyph: '▤' },
  { key: 'download', label: 'nav.download', glyph: '⤓' },
  { key: 'accounts', label: 'nav.accounts', glyph: '☺' },
  { key: 'mods', label: 'nav.mods', glyph: '❖' },
  { key: 'resourcepacks', label: 'nav.resourcepacks', glyph: '◫' },
  { key: 'shaders', label: 'nav.shaders', glyph: '✦' },
  { key: 'worlds', label: 'nav.worlds', glyph: '◍' },
  { key: 'modpacks', label: 'nav.modpacks', glyph: '⛁' },
  { key: 'gamedir', label: 'nav.gamedir', glyph: '🗀' },
  { key: 'java', label: 'nav.java', glyph: '☕' },
  { key: 'logs', label: 'nav.logs', glyph: '☰' },
  { key: 'settings', label: 'nav.settings', glyph: '⚙' },
];
