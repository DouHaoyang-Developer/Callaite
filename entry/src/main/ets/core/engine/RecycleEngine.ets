import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData, createBlockData } from '../models/Block';
import { PageData, createPageData } from '../models/Page';
import { PropertyBag } from '../models/Property';
import { FileFormat } from '../models/Constants';

/**
 * RecycleItem — 回收站项。
 *
 * 序列化的 Block 或 Page 数据，存储在回收站中等待恢复或永久删除。
 */
export interface RecycleItem {
  /** 项目 UUID（对应 Block 或 Page 的 UUID） */
  uuid: string;
  /** 项目类型：'block' 或 'page' */
  type: string;
  /** 序列化的 JSON 数据 */
  data: string;
  /** 原始父 ID（Block 的 parentId，Page 为空字符串） */
  originalParentId: string;
  /** 删除时间戳 (ms) */
  deletedAt: number;
}

/**
 * Block 序列化形式（可 JSON 序列化的纯数据结构）。
 * PropertyBag 通过 toJSON() 转换为字符串。
 */
interface BlockSerialForm {
  uuid: string;
  content: string;
  format: string;
  pageId: string;
  parentId: string;
  leftId: string;
  level: number;
  marker: string;
  priority: string;
  scheduled: string;
  deadline: string;
  propertiesJson: string;
  propertiesOrder: string[];
  refs: string[];
  blockRefs: string[];
  tags: string[];
  class: string;
  createdAt: number;
  updatedAt: number;
  collapsed: boolean;
}

/**
 * Page 序列化形式（可 JSON 序列化的纯数据结构）。
 */
interface PageSerialForm {
  uuid: string;
  name: string;
  originalName: string;
  namespace: string;
  propertiesJson: string;
  journalDay: string;
  format: string;
  filePath: string;
  aliases: string[];
  tags: string[];
  class: string;
  createdAt: number;
  updatedAt: number;
}

/**
 * RecycleEngine — 回收站引擎单例。
 *
 * 对应 Logseq mobile/recycle_bin.cljs。
 *
 * 职责：
 *  - 将 Block / Page 移入回收站（序列化为 JSON 存储）
 *  - 从回收站恢复（反序列化并重新写入 DataStore）
 *  - 永久删除回收站项
 *  - 清理过期项目（默认 7 天）
 *  - 清空回收站
 *
 * 数据存储在内存 Map 中；应用重启后回收站会清空。
 * 若需持久化，可在后续扩展中序列化 recycledItems 到文件。
 */
export class RecycleEngine {
  private static instance: RecycleEngine | undefined;

  /** 回收站存储：itemUuid → RecycleItem */
  private recycledItems: Map<string, RecycleItem> = new Map<string, RecycleItem>();

  static getInstance(): RecycleEngine {
    if (!RecycleEngine.instance) {
      RecycleEngine.instance = new RecycleEngine();
    }
    return RecycleEngine.instance;
  }

  // ─── 移入回收站 ───

  /**
   * 将 Block 移入回收站。
   *
   * 1. 获取 BlockData
   * 2. 序列化为 JSON
   * 3. 存入 recycledItems
   * 4. 从 DataStore 中删除（通过 OutlinerEngine delete-block 操作）
   *
   * @param blockUuid Block UUID
   */
  recycleBlock(blockUuid: string): void {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(blockUuid);
    if (!block) {
      return;
    }

    // 序列化
    const serialForm: BlockSerialForm = this.blockToSerialForm(block);
    const json: string = this.serialize(serialForm);

    const item: RecycleItem = {
      uuid: blockUuid,
      type: 'block',
      data: json,
      originalParentId: block.parentId,
      deletedAt: Date.now()
    };
    this.recycledItems.set(blockUuid, item);

    // 从 DataStore 删除
    ws.executeOp({ type: 'delete-block', uuid: blockUuid });
  }

  /**
   * 将 Page 移入回收站。
   *
   * 1. 获取 PageData
   * 2. 序列化为 JSON
   * 3. 存入 recycledItems
   * 4. 从 DataStore 中删除页面（DataStore.deletePage）
   *
   * @param pageUuid Page UUID
   */
  recyclePage(pageUuid: string): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getDataStore().getPage(pageUuid);
    if (!page) {
      return;
    }

    // 序列化
    const serialForm: PageSerialForm = this.pageToSerialForm(page);
    const json: string = this.serialize(serialForm);

    const item: RecycleItem = {
      uuid: pageUuid,
      type: 'page',
      data: json,
      originalParentId: '',
      deletedAt: Date.now()
    };
    this.recycledItems.set(pageUuid, item);

    // 从 DataStore 删除
    ws.getDataStore().deletePage(pageUuid);
  }

  // ─── 恢复 ───

  /**
   * 从回收站恢复项目。
   *
   * 1. 获取 RecycleItem
   * 2. 反序列化
   * 3. 根据 type 重建 BlockData 或 PageData
   * 4. 写回 DataStore
   * 5. 从回收站移除
   *
   * @param uuid 项目 UUID
   * @returns 恢复成功返回 true；项目不存在或恢复失败返回 false
   */
  restore(uuid: string): boolean {
    const item = this.recycledItems.get(uuid);
    if (!item) {
      return false;
    }

    try {
      if (item.type === 'page') {
        this.restorePage(item);
      } else if (item.type === 'block') {
        this.restoreBlock(item);
      } else {
        return false;
      }
      this.recycledItems.delete(uuid);
      return true;
    } catch (e) {
      return false;
    }
  }

  /**
   * 恢复 Page。
   */
  private restorePage(item: RecycleItem): void {
    const ws = WorkspaceService.getInstance();
    const dataStore = ws.getDataStore();
    const indexStore = dataStore.getIndexStore();

    const obj: Object = this.deserialize(item.data);
    const serialForm = obj as PageSerialForm;

    // 重建 PageData
    const page: PageData = createPageData(serialForm.uuid, serialForm.name, serialForm.originalName);
    page.namespace = serialForm.namespace;
    page.properties = PropertyBag.fromJSON(serialForm.propertiesJson);
    page.journalDay = serialForm.journalDay;
    page.format = serialForm.format === 'org' ? FileFormat.ORG : FileFormat.MARKDOWN;
    page.filePath = serialForm.filePath;
    page.aliases = serialForm.aliases;
    page.tags = serialForm.tags;
    page.class = serialForm.class;
    page.createdAt = serialForm.createdAt;
    page.updatedAt = Date.now();

    // 注册到索引
    indexStore.addPage(page);

    // 持久化
    dataStore.savePage(page.uuid);
  }

  /**
   * 恢复 Block。
   *
   * 将 Block 重新加载到 BlockTree 中。
   * 若所属页面不存在，则恢复失败。
   */
  private restoreBlock(item: RecycleItem): void {
    const ws = WorkspaceService.getInstance();
    const dataStore = ws.getDataStore();

    const obj: Object = this.deserialize(item.data);
    const serialForm = obj as BlockSerialForm;

    // 重建 BlockData
    const block: BlockData = createBlockData(
      serialForm.uuid, serialForm.pageId, serialForm.parentId, serialForm.level
    );
    block.content = serialForm.content;
    block.format = serialForm.format === 'org' ? FileFormat.ORG : FileFormat.MARKDOWN;
    block.leftId = serialForm.leftId;
    block.marker = serialForm.marker;
    block.priority = serialForm.priority;
    block.scheduled = serialForm.scheduled;
    block.deadline = serialForm.deadline;
    block.properties = PropertyBag.fromJSON(serialForm.propertiesJson);
    block.propertiesOrder = serialForm.propertiesOrder;
    block.refs = serialForm.refs;
    block.blockRefs = serialForm.blockRefs;
    block.tags = serialForm.tags;
    block.class = serialForm.class;
    block.createdAt = serialForm.createdAt;
    block.updatedAt = Date.now();
    block.collapsed = serialForm.collapsed;

    // 获取页面现有 Block，追加恢复的 Block，重新加载
    const existingBlocks: BlockData[] = dataStore.getPageBlocks(block.pageId);
    existingBlocks.push(block);
    dataStore.getBlockTree().loadPageBlocks(block.pageId, existingBlocks);

    // 重建引用索引
    const indexStore = dataStore.getIndexStore();
    indexStore.indexBlock(block.uuid, block.pageId);
    for (let i = 0; i < block.refs.length; i++) {
      indexStore.addReference(block.uuid, block.refs[i], false);
    }
    for (let i = 0; i < block.blockRefs.length; i++) {
      indexStore.addReference(block.uuid, block.blockRefs[i], true);
    }

    // 持久化页面
    dataStore.savePage(block.pageId);
  }

  // ─── 删除 ───

  /**
   * 永久删除回收站中的项目。
   *
   * 仅从回收站移除，不写入 DataStore（数据已从 DataStore 删除）。
   *
   * @param uuid 项目 UUID
   */
  permanentDelete(uuid: string): void {
    this.recycledItems.delete(uuid);
  }

  /**
   * 清理过期项目。
   *
   * @param maxAgeDays 最大保留天数（默认 7 天）
   * @returns 清理的项目数量
   */
  clearExpired(maxAgeDays: number = 7): number {
    const now: number = Date.now();
    const maxAgeMs: number = maxAgeDays * 24 * 60 * 60 * 1000;
    const toRemove: string[] = [];

    this.recycledItems.forEach((item: RecycleItem) => {
      if (now - item.deletedAt > maxAgeMs) {
        toRemove.push(item.uuid);
      }
    });

    for (let i = 0; i < toRemove.length; i++) {
      this.recycledItems.delete(toRemove[i]);
    }
    return toRemove.length;
  }

  /**
   * 清空回收站。
   */
  empty(): void {
    this.recycledItems.clear();
  }

  // ─── 查询 ───

  /**
   * 获取所有回收站项目。
   *
   * @returns RecycleItem 数组（按删除时间降序）
   */
  getRecycledItems(): RecycleItem[] {
    const result: RecycleItem[] = [];
    this.recycledItems.forEach((item: RecycleItem) => {
      result.push(item);
    });
    // 按删除时间降序排序（最近删除的在前）
    result.sort((a: RecycleItem, b: RecycleItem): number => {
      return b.deletedAt - a.deletedAt;
    });
    return result;
  }

  // ─── 序列化辅助 ───

  /**
   * 将 BlockData 转换为可序列化的纯数据结构。
   */
  private blockToSerialForm(block: BlockData): BlockSerialForm {
    const form: BlockSerialForm = {
      uuid: block.uuid,
      content: block.content,
      format: block.format.toString(),
      pageId: block.pageId,
      parentId: block.parentId,
      leftId: block.leftId,
      level: block.level,
      marker: block.marker,
      priority: block.priority,
      scheduled: block.scheduled,
      deadline: block.deadline,
      propertiesJson: block.properties.toJSON(),
      propertiesOrder: block.propertiesOrder,
      refs: block.refs,
      blockRefs: block.blockRefs,
      tags: block.tags,
      class: block.class,
      createdAt: block.createdAt,
      updatedAt: block.updatedAt,
      collapsed: block.collapsed
    };
    return form;
  }

  /**
   * 将 PageData 转换为可序列化的纯数据结构。
   */
  private pageToSerialForm(page: PageData): PageSerialForm {
    const form: PageSerialForm = {
      uuid: page.uuid,
      name: page.name,
      originalName: page.originalName,
      namespace: page.namespace,
      propertiesJson: page.properties.toJSON(),
      journalDay: page.journalDay,
      format: page.format.toString(),
      filePath: page.filePath,
      aliases: page.aliases,
      tags: page.tags,
      class: page.class,
      createdAt: page.createdAt,
      updatedAt: page.updatedAt
    };
    return form;
  }

  /**
   * JSON 序列化。
   *
   * @param data 待序列化的对象
   * @returns JSON 字符串
   */
  private serialize(data: Object): string {
    try {
      return JSON.stringify(data);
    } catch (e) {
      return '{}';
    }
  }

  /**
   * JSON 反序列化。
   *
   * @param json JSON 字符串
   * @returns 反序列化后的对象
   */
  private deserialize(json: string): Object {
    try {
      return JSON.parse(json) as Object;
    } catch (e) {
      return {};
    }
  }
}
