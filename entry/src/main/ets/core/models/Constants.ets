/**
 * 全局常量定义 — 对应 Logseq schema.cljs 中的枚举值与配置常量。
 */

// ─── Block 任务标记 ───
export enum BlockMarker {
  NONE = '',
  TODO = 'TODO',
  DOING = 'DOING',
  DONE = 'DONE',
  LATER = 'LATER',
  NOW = 'NOW',
  CANCELLED = 'CANCELLED'
}

// ─── 优先级 ───
export enum BlockPriority {
  NONE = '',
  A = 'A',
  B = 'B',
  C = 'C'
}

// ─── 文件格式 ───
export enum FileFormat {
  MARKDOWN = 'markdown',
  ORG = 'org'
}

// ─── 属性值类型 — 对应 db/frontend/property.cljs ───
export enum PropertyType {
  TEXT = 'text',
  NUMBER = 'number',
  CHECKBOX = 'checkbox',
  DATE = 'date',
  TAGS = 'tags',
  URL = 'url',
  PAGE = 'page',
  BLOCK = 'block',
  CLASS = 'class'
}

// ─── 内置属性名 ───
export const BUILTIN_PROPERTY_NAMES: string[] = [
  'tags',
  'alias',
  'created-at',
  'updated-at',
  'title',
  'template',
  'template-including-parent',
  'public',
  'categories'
];

// ─── 页面引用正则（摘取自 common/util/page_ref.cljs） ───
export const PAGE_REF_REGEX = /\[\[([^\]]+)\]\]/g;

// ─── Block 引用正则 ───
export const BLOCK_REF_REGEX = /\(\(([a-f0-9\-]{36})\)\)/g;

// ─── 标签正则 ───
export const TAG_REGEX = /#([\w一-鿿\-]+)/g;

// ─── 属性正则 key:: value ───
export const PROPERTY_REGEX = /^(\S[\w\-]*?)\s*::\s*(.+)$/;

// ─── 任务标记正则 TODO/DOING/DONE/LATER/NOW/CANCELLED ───
export const MARKER_REGEX = /^(TODO|DOING|DONE|LATER|NOW|CANCELLED)\s+/;

// ─── 优先级正则 ───
export const PRIORITY_REGEX = /^\[#(A|B|C)\]\s+/;

// ─── 日期属性正则 SCHEDULED: <yyyy-MM-dd> / DEADLINE: <yyyy-MM-dd> ───
export const SCHEDULED_REGEX = /SCHEDULED:\s*<(\d{4}-\d{2}-\d{2})>/;
export const DEADLINE_REGEX = /DEADLINE:\s*<(\d{4}-\d{2}-\d{2})>/;

// ─── 日志页日期格式 ───
export const JOURNAL_DATE_FORMAT = 'yyyy-MM-dd';

// ─── Markdown 缩进标识 ───
export const BLOCK_PREFIX = '- ';
export const INDENT_PREFIX = '  ';
