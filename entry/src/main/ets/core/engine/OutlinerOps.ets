import { BlockData } from '../models/Block';
import { PageData } from '../models/Page';
import { PropertyBag } from '../models/Property';

/**
 * OutlinerOp — 大纲操作类型定义。
 *
 * 对应 Logseq outliner/op.cljs (438行) 中的所有操作变体。
 * 每个操作是不可变的数据描述，由 OutlinerEngine 执行。
 */

// ─── Block 操作 ───

export interface InsertBlockOp {
  type: 'insert-block';
  content: string;
  pageId: string;
  parentId: string;
  leftId: string;
  level: number;
}

export interface InsertBlocksOp {
  type: 'insert-blocks';
  blocks: InsertBlockOp[];
}

export interface DeleteBlockOp {
  type: 'delete-block';
  uuid: string;
}

export interface DeleteBlocksOp {
  type: 'delete-blocks';
  uuids: string[];
}

export interface MoveBlockOp {
  type: 'move-block';
  uuid: string;
  newParentId: string;
  newLeftId: string;
  newLevel: number;
}

export interface MoveBlocksOp {
  type: 'move-blocks';
  uuids: string[];
  newParentId: string;
  newLeftId: string;
  newLevel: number;
}

export interface UpdateBlockOp {
  type: 'update-block';
  uuid: string;
  content: string;
}

export interface IndentOp {
  type: 'indent';
  uuid: string;
}

export interface OutdentOp {
  type: 'outdent';
  uuid: string;
}

// ─── 任务操作 ───

export interface SetMarkerOp {
  type: 'set-marker';
  uuid: string;
  marker: string;
}

export interface SetPriorityOp {
  type: 'set-priority';
  uuid: string;
  priority: string;
}

export interface SetScheduledOp {
  type: 'set-scheduled';
  uuid: string;
  date: string;
}

export interface SetDeadlineOp {
  type: 'set-deadline';
  uuid: string;
  date: string;
}

// ─── 属性操作 ───

export interface AddPropertyOp {
  type: 'add-property';
  blockUuid: string;
  name: string;
  value: string;
}

export interface RemovePropertyOp {
  type: 'remove-property';
  blockUuid: string;
  name: string;
}

// ─── UI 操作 ───

export interface CollapseOp {
  type: 'collapse';
  uuid: string;
  collapsed: boolean;
}

// ─── 页面操作 ───

export interface NewPageOp {
  type: 'new-page';
  name: string;
  originalName: string;
}

export interface RenamePageOp {
  type: 'rename-page';
  pageId: string;
  newName: string;
}

export interface DeletePageOp {
  type: 'delete-page';
  pageId: string;
}

// ─── 联合类型 ───

export type OutlinerOp =
  | InsertBlockOp
  | DeleteBlockOp
  | DeleteBlocksOp
  | MoveBlockOp
  | MoveBlocksOp
  | UpdateBlockOp
  | IndentOp
  | OutdentOp
  | SetMarkerOp
  | SetPriorityOp
  | SetScheduledOp
  | SetDeadlineOp
  | AddPropertyOp
  | RemovePropertyOp
  | CollapseOp
  | NewPageOp
  | RenamePageOp
  | DeletePageOp;

// ─── 辅助类型 ───

/**
 * 操作执行结果。
 */
export interface OpResult {
  success: boolean;
  message: string;
  affectedUuids: string[];
}
