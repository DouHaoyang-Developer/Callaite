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
  const filePathStr = name.replace('/', '_') + '.md';
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
