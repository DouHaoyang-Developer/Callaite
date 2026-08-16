import { StatePersistence } from '../state/StatePersistence';

export type SupportedLanguage = 'zh-CN' | 'en-US';

const LANGUAGE_KEY = 'callaite_language';

/**
 * 字典类 — 替代 ArkTS 禁用的 [key: string] 索引签名。
 * 内部使用 Map 存储键值对，对外提供 get/set/has 方法。
 */
class I18nDict {
  private data: Map<string, string> = new Map<string, string>();

  add(key: string, value: string): void {
    this.data.set(key, value);
  }

  getValue(key: string): string {
    return this.data.get(key) ?? '';
  }

  has(key: string): boolean {
    return this.data.has(key);
  }
}

function buildZhCN(): I18nDict {
  const d = new I18nDict();
  d.add('app_name', 'Callaite');
  d.add('journal', '日志');
  d.add('pages', '页面');
  d.add('favorites', '收藏夹');
  d.add('recent', '最近');
  d.add('all_pages', '所有页面');
  d.add('graph', '图谱');
  d.add('whiteboards', '白板');
  d.add('flashcards', '闪卡');
  d.add('settings', '设置');
  d.add('search', '搜索');
  d.add('commands', '命令面板');
  d.add('back', '返回');
  d.add('forward', '前进');
  d.add('close', '关闭');
  d.add('add', '添加');
  d.add('edit', '编辑');
  d.add('delete', '删除');
  d.add('save', '保存');
  d.add('cancel', '取消');
  d.add('confirm', '确认');
  d.add('more', '更多');
  d.add('theme', '主题');
  d.add('theme_light', '浅色');
  d.add('theme_dark', '深色');
  d.add('theme_system', '跟随系统');
  d.add('language', '语言');
  d.add('sidebar_left', '左侧栏');
  d.add('sidebar_right', '右侧栏');
  d.add('backlinks', '反向链接');
  d.add('outline', '大纲');
  d.add('properties', '属性');
  d.add('empty_page', '当前页面为空');
  d.add('placeholder_search', '搜索或创建页面...');
  d.add('placeholder_block', '输入内容，按 / 查看命令');
  d.add('from_page', '来自');
  d.add('about', '关于');
  d.add('rename', '重命名');
  d.add('import', '导入');
  d.add('export', '导出');
  d.add('recycle', '回收站');
  d.add('onboarding_welcome', '欢迎使用 Callaite');
  d.add('onboarding_desc', 'Logseq 风格的鸿蒙知识管理应用');
  d.add('loading', '加载中...');
  // 新增 — Header 与导航
  d.add('nav_journals', '日志');
  d.add('nav_all_pages', '所有页面');
  d.add('nav_graph_view', '图谱视图');
  d.add('nav_flashcards', '闪卡复习');
  d.add('nav_home', '主页');
  d.add('nav_appearance', '外观');
  d.add('nav_recycle', '回收站');
  d.add('nav_export', '导出图谱');
  d.add('nav_import', '导入');
  d.add('nav_about', '关于');
  d.add('header_more', '更多');
  d.add('header_go_back', '后退');
  d.add('header_go_forward', '前进');
  d.add('header_toggle_left_sidebar', '切换左侧栏');
  d.add('header_toggle_right_sidebar', '切换右侧栏');
  d.add('header_search', '搜索');
  d.add('header_home', '主页');
  // 右侧栏
  d.add('sidebar_right_title', '右侧栏');
  d.add('sidebar_contents', '目录');
  d.add('sidebar_page_graph', '页面图谱');
  d.add('sidebar_help', '帮助');
  d.add('sidebar_navigations', '导航');
  d.add('close_all', '全部关闭');
  d.add('collapse_all', '全部折叠');
  d.add('expand_all', '全部展开');
  d.add('open_in_sidebar', '在侧栏中打开');
  d.add('open_as_page', '作为页面打开');
  d.add('no_backlinks', '暂无反向链接');
  d.add('no_outline', '暂无大纲');
  d.add('no_properties', '暂无属性');
  d.add('add_property_hint', 'key:: value 添加属性');
  d.add('empty_sidebar', '右侧栏为空');
  d.add('empty_sidebar_hint', '点击右侧栏图标查看页面信息');
  // 设置页
  d.add('font_size', '字体大小');
  d.add('show_bullets', '显示 Bullet');
  d.add('autosave_interval', '自动保存间隔');
  d.add('tab_width', 'Tab 缩进宽度');
  d.add('editor', '编辑器');
  d.add('shortcuts', '快捷键');
  d.add('sync', '同步');
  d.add('account', '账户');
  d.add('plugins', '插件');
  d.add('data', '数据');
  d.add('cloud_sync', '云同步');
  d.add('collab_edit', '协同编辑');
  return d;
}

function buildEnUS(): I18nDict {
  const d = new I18nDict();
  d.add('app_name', 'Callaite');
  d.add('journal', 'Journal');
  d.add('pages', 'Pages');
  d.add('favorites', 'Favorites');
  d.add('recent', 'Recent');
  d.add('all_pages', 'All Pages');
  d.add('graph', 'Graph');
  d.add('whiteboards', 'Whiteboards');
  d.add('flashcards', 'Flashcards');
  d.add('settings', 'Settings');
  d.add('search', 'Search');
  d.add('commands', 'Command Palette');
  d.add('back', 'Back');
  d.add('forward', 'Forward');
  d.add('close', 'Close');
  d.add('add', 'Add');
  d.add('edit', 'Edit');
  d.add('delete', 'Delete');
  d.add('save', 'Save');
  d.add('cancel', 'Cancel');
  d.add('confirm', 'Confirm');
  d.add('more', 'More');
  d.add('theme', 'Theme');
  d.add('theme_light', 'Light');
  d.add('theme_dark', 'Dark');
  d.add('theme_system', 'System');
  d.add('language', 'Language');
  d.add('sidebar_left', 'Left Sidebar');
  d.add('sidebar_right', 'Right Sidebar');
  d.add('backlinks', 'Backlinks');
  d.add('outline', 'Outline');
  d.add('properties', 'Properties');
  d.add('empty_page', 'This page is empty');
  d.add('placeholder_search', 'Search or create page...');
  d.add('placeholder_block', 'Type something, press / for commands');
  d.add('from_page', 'From');
  d.add('about', 'About');
  d.add('rename', 'Rename');
  d.add('import', 'Import');
  d.add('export', 'Export');
  d.add('recycle', 'Recycle Bin');
  d.add('onboarding_welcome', 'Welcome to Callaite');
  d.add('onboarding_desc', 'Logseq-style knowledge management for HarmonyOS');
  d.add('loading', 'Loading...');
  // Header & navigation
  d.add('nav_journals', 'Journals');
  d.add('nav_all_pages', 'All Pages');
  d.add('nav_graph_view', 'Graph View');
  d.add('nav_flashcards', 'Flashcards');
  d.add('nav_home', 'Home');
  d.add('nav_appearance', 'Appearance');
  d.add('nav_recycle', 'Recycle Bin');
  d.add('nav_export', 'Export Graph');
  d.add('nav_import', 'Import');
  d.add('nav_about', 'About');
  d.add('header_more', 'More');
  d.add('header_go_back', 'Go Back');
  d.add('header_go_forward', 'Go Forward');
  d.add('header_toggle_left_sidebar', 'Toggle Left Sidebar');
  d.add('header_toggle_right_sidebar', 'Toggle Right Sidebar');
  d.add('header_search', 'Search');
  d.add('header_home', 'Home');
  d.add('sidebar_right_title', 'Right Sidebar');
  d.add('sidebar_contents', 'Contents');
  d.add('sidebar_page_graph', 'Page Graph');
  d.add('sidebar_help', 'Help');
  d.add('sidebar_navigations', 'Navigations');
  d.add('close_all', 'Close All');
  d.add('collapse_all', 'Collapse All');
  d.add('expand_all', 'Expand All');
  d.add('open_in_sidebar', 'Open in Sidebar');
  d.add('open_as_page', 'Open as Page');
  d.add('no_backlinks', 'No backlinks');
  d.add('no_outline', 'No outline');
  d.add('no_properties', 'No properties');
  d.add('add_property_hint', 'key:: value to add property');
  d.add('empty_sidebar', 'Sidebar is empty');
  d.add('empty_sidebar_hint', 'Click right sidebar icons to view page info');
  // Settings
  d.add('font_size', 'Font Size');
  d.add('show_bullets', 'Show Bullet');
  d.add('autosave_interval', 'Autosave Interval');
  d.add('tab_width', 'Tab Width');
  d.add('editor', 'Editor');
  d.add('shortcuts', 'Shortcuts');
  d.add('sync', 'Sync');
  d.add('account', 'Account');
  d.add('plugins', 'Plugins');
  d.add('data', 'Data');
  d.add('cloud_sync', 'Cloud Sync');
  d.add('collab_edit', 'Collaborative Editing');
  return d;
}

const zhCNDict = buildZhCN();
const enUSDict = buildEnUS();

function getDict(lang: SupportedLanguage): I18nDict {
  if (lang === 'zh-CN') {
    return zhCNDict;
  }
  return enUSDict;
}

export class I18n {
  static initDefault(): void {
    if (!AppStorage.has(LANGUAGE_KEY)) {
      AppStorage.setOrCreate(LANGUAGE_KEY, 'zh-CN');
    }
  }

  static getLanguage(): SupportedLanguage {
    const stored = AppStorage.get<string>(LANGUAGE_KEY);
    if (stored !== undefined) {
      if (stored === 'zh-CN' || stored === 'en-US') {
        return stored as SupportedLanguage;
      }
    }
    return 'zh-CN';
  }

  static setLanguage(lang: SupportedLanguage): void {
    AppStorage.setOrCreate(LANGUAGE_KEY, lang);
    StatePersistence.save();
  }

  /**
   * 翻译函数。第一个参数为 key，第二个参数为可选的替换映射（Map<string, string>）。
   * 调用示例：t('hello') 或 t('greeting', new Map([['name', 'World']]))
   */
  static t(key: string, replacements?: Map<string, string>): string {
    const lang = I18n.getLanguage();
    let value = getDict(lang).getValue(key);
    if (value === '' && lang !== 'en-US') {
      value = getDict('en-US').getValue(key);
    }
    if (value === '') {
      value = key;
    }
    if (replacements) {
      replacements.forEach((v: string, k: string) => {
        value = value.replace(new RegExp(`\\{${k}\\}`, 'g'), v);
      });
    }
    return value;
  }
}

/**
 * 便捷函数，供组件中直接调用。
 * 使用 Map 传参替代 ArkTS 禁用的 Record<string, string>。
 */
export function t(key: string, replacements?: Map<string, string>): string {
  return I18n.t(key, replacements);
}
