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
  d.add('loading', '加载中...');
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
  d.add('loading', 'Loading...');
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
