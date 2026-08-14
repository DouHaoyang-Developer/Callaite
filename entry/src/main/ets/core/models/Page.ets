import { PropertyBag } from './Property';
import { FileFormat } from './Constants';

/**
 * Page 数据模型 — 对应 Logseq deps/db 中的 Page Schema。
 *
 * 字段映射：
 *   :page/name          → name
 *   :page/original-name → originalName
 *   :page/namespace     → namespace
 *   :page/properties    → properties (PropertyBag)
 *   :page/journal-day   → journalDay
 *   :page/format        → format
 *   :page/file          → filePath
 *   :page/tags          → tags
 *   :page/alias         → aliases
 *   :page/class         → class
 */
export interface PageData {
  // ─── 标识 ───
  uuid: string;

  // ─── 名称 ───
  /** 规范化名称（小写，用作文件名和引用匹配） */
  name: string;
  /** 原始显示名称（保留大小写） */
  originalName: string;
  /** 命名空间前缀（例 "project" in "project/sub-page"），空字符串为普通页面 */
  namespace: string;

  // ─── 属性 ───
  /** 页面属性键值对 */
  properties: PropertyBag;

  // ─── 日志页 ───
  /** 日志页日期 yyyy-MM-dd（普通页面为空字符串） */
  journalDay: string;

  // ─── 格式与文件 ───
  /** 文件格式 */
  format: FileFormat;
  /** .md 文件相对于 Graph 根目录的路径 */
  filePath: string;

  // ─── 引用与元数据 ───
  /** 别名列表 */
  aliases: string[];
  /** 标签列表（聚合自页面属性 + 顶层 Block 属性） */
  tags: string[];
  /** 所属 Class（页面分类） */
  class: string;

  // ─── 元数据 ───
  /** 创建时间戳 (ms) */
  createdAt: number;
  /** 更新时间戳 (ms) */
  updatedAt: number;
}

/**
 * 创建 PageData 的工厂函数。
 */
export function createPageData(uuid: string, name: string, originalName: string): PageData {
  const now = Date.now();
  const ns = extractNamespace(name);
  const filePathStr = pageNameToFileName(name);
  const page: PageData = {
    uuid: uuid,
    name: name,
    originalName: originalName,
    namespace: ns,
    properties: new PropertyBag(),
    journalDay: '',
    format: FileFormat.MARKDOWN,
    filePath: filePathStr,
    aliases: [],
    tags: [],
    class: '',
    createdAt: now,
    updatedAt: now
  };
  return page;
}

/**
 * 将页面名安全地转换为 .md 文件名，防止路径穿越。
 * 规则：
 *  - 统一将 / 与 \ 替换为 _（与命名空间扁平化存储保持一致）
 *  - 移除或替换 ..、空段、控制字符等危险片段
 *  - 确保结果不为空、不以 . 开头（避免隐藏文件）
 */
export function pageNameToFileName(name: string): string {
  let sanitized = '';
  for (let i = 0; i < name.length; i++) {
    const code = name.charCodeAt(i);
    const ch = name.charAt(i);
    if (ch === '/' || ch === '\\' || ch === ':' || ch === '*' ||
        ch === '?' || ch === '"' || ch === '<' || ch === '>' || ch === '|') {
      sanitized += '_';
    } else if (code < 32) {
      // 控制字符直接丢弃
    } else {
      sanitized += ch;
    }
  }

  // 处理路径穿越片段 ..（可能被替换为 _ 后残留，如 a..b 保留，但纯 .. 段替换）
  // 由于 / 已替换为 _，此处再防御性处理连续点号段
  const segments = sanitized.split('_');
  const cleaned: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    if (seg === '' || seg === '.' || seg === '..') {
      cleaned.push('_');
    } else {
      cleaned.push(seg);
    }
  }
  let result = cleaned.join('_');

  // 去除开头点号，避免生成隐藏文件
  while (result.startsWith('.')) {
    result = result.substring(1);
  }
  if (result === '') {
    result = 'Untitled';
  }
  return result + '.md';
}

/**
 * 从页面名中提取命名空间。
 * 例: "project/sub-page" → namespace = "project"
 */
export function extractNamespace(name: string): string {
  const slashIdx = name.indexOf('/');
  if (slashIdx > 0 && slashIdx < name.length - 1) {
    return name.substring(0, slashIdx);
  }
  return '';
}

/**
 * 获取命名空间的显示名（无前缀的短名）。
 */
export function getShortPageName(name: string): string {
  const slashIdx = name.lastIndexOf('/');
  if (slashIdx > 0 && slashIdx < name.length - 1) {
    return name.substring(slashIdx + 1);
  }
  return name;
}

/**
 * 判断页面是否为日志页（journalDay 非空）。
 */
export function isJournalPage(page: PageData): boolean {
  return page.journalDay !== '';
}

/**
 * 获取页面的所有显示名称（含别名）。
 */
export function getPageAllNames(page: PageData): string[] {
  const names: string[] = [];
  names.push(page.originalName);
  names.push(page.name);
  for (let i = 0; i < page.aliases.length; i++) {
    names.push(page.aliases[i]);
  }
  return names;
}
