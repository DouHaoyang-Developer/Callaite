import { PropertyBag } from './Property';
import { BlockMarker, BlockPriority, FileFormat } from './Constants';

/**
 * Block 数据模型 — 对应 Logseq deps/db 中的 Block Schema。
 *
 * 字段映射：
 *   :block/uuid       → uuid
 *   :block/content    → content
 *   :block/format     → format
 *   :block/page       → pageId
 *   :block/parent     → parentId
 *   :block/left       → leftId
 *   :block/level      → level
 *   :block/marker     → marker
 *   :block/priority   → priority
 *   :block/properties → properties (PropertyBag)
 *   :block/refs       → refs
 *   :block/block-refs → blockRefs
 *   :block/tags       → tags
 *   :block/scheduled  → scheduled
 *   :block/deadline   → deadline
 *   :block/collapsed? → collapsed
 */
export interface BlockData {
  // ─── 标识 ───
  uuid: string;

  // ─── 内容 ───
  /** Block 文本内容（不含 marker/priority 前缀，不含缩进标识符） */
  content: string;
  /** 文件格式 */
  format: FileFormat;

  // ─── 树结构 ───
  /** 所属页面 UUID */
  pageId: string;
  /** 父 Block UUID（顶层 Block 的 parentId = pageId） */
  parentId: string;
  /** 左侧兄弟 Block UUID（用于排序，空字符串表示第一个子节点） */
  leftId: string;
  /** 缩进层级（0 = 顶层，1 = 一级缩进，依此类推） */
  level: number;

  // ─── 任务与优先级 ───
  /** 任务标记：BlockMarker 枚举值 */
  marker: string;
  /** 优先级：BlockPriority 枚举值 */
  priority: string;
  /** 计划日期 yyyy-MM-dd（空字符串表示未设置） */
  scheduled: string;
  /** 截止日期 yyyy-MM-dd（空字符串表示未设置） */
  deadline: string;

  // ─── 属性 ───
  /** 自定义属性键值对 */
  properties: PropertyBag;
  /** 属性显示顺序 */
  propertiesOrder: string[];

  // ─── 引用 ───
  /** 页面引用列表（从 content 中解析的 [[page]]） */
  refs: string[];
  /** Block 引用列表（从 content 中解析的 ((uuid))） */
  blockRefs: string[];

  // ─── 标签与分类 ───
  /** 标签列表（从 content 中解析的 #tag） */
  tags: string[];
  /** 所属 Class（页级分类） */
  class: string;

  // ─── 元数据 ───
  /** 创建时间戳 (ms) */
  createdAt: number;
  /** 更新时间戳 (ms) */
  updatedAt: number;
  /** 子 Block 是否折叠 */
  collapsed: boolean;
}

/**
 * 创建 BlockData 的工厂函数。
 * 提供合理的默认值，确保必填字段完整。
 */
export function createBlockData(uuid: string, pageId: string, parentId: string, level: number): BlockData {
  const now = Date.now();
  const block: BlockData = {
    uuid: uuid,
    content: '',
    format: FileFormat.MARKDOWN,
    pageId: pageId,
    parentId: parentId,
    leftId: '',
    level: level,
    marker: BlockMarker.NONE,
    priority: BlockPriority.NONE,
    scheduled: '',
    deadline: '',
    properties: new PropertyBag(),
    propertiesOrder: [],
    refs: [],
    blockRefs: [],
    tags: [],
    class: '',
    createdAt: now,
    updatedAt: now,
    collapsed: false
  };
  return block;
}
