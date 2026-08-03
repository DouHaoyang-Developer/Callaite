import { BlockData } from '../models/Block';
import { PageData } from '../models/Page';
import { DataStore } from './DataStore';

/**
 * QueryEngine — 简单查询引擎。
 *
 * 对应 Logseq db/query_dsl.cljs (782行)。
 * 支持按 task marker、priority、date range、标签筛选 Block。
 *
 * 后续可扩展为完整 Datalog 引擎。
 */
export interface QueryOptions {
  marker?: string;
  markers?: string[];
  priority?: string;
  priorities?: string[];
  scheduledAfter?: string;   // yyyy-MM-dd
  scheduledBefore?: string;  // yyyy-MM-dd
  deadlineAfter?: string;
  deadlineBefore?: string;
  tags?: string[];
  notMarker?: string;
  notTags?: string[];
  pageName?: string;
  hasProperty?: string;
  contentContains?: string;
  limit?: number;
}

export class QueryEngine {

  /**
   * 在指定范围内的所有页面中查询 Block。
   */
  static query(store: DataStore, options: QueryOptions): BlockData[] {
    const pages = store.getAllPages();
    const result: BlockData[] = [];
    const limit = options.limit ?? 50;

    for (let pi = 0; pi < pages.length && result.length < limit; pi++) {
      const blocks = store.getPageBlocks(pages[pi].uuid);
      for (let bi = 0; bi < blocks.length && result.length < limit; bi++) {
        if (QueryEngine.matches(blocks[bi], pages[pi], options)) {
          result.push(blocks[bi]);
        }
      }
    }

    return result;
  }

  /**
   * 在单页面内查询。
   */
  static queryPage(store: DataStore, pageId: string, options: QueryOptions): BlockData[] {
    const blocks = store.getPageBlocks(pageId);
    const page = store.getIndexStore().getPage(pageId);
    const result: BlockData[] = [];
    const limit = options.limit ?? 50;

    for (let i = 0; i < blocks.length && result.length < limit; i++) {
      if (QueryEngine.matches(blocks[i], page, options)) {
        result.push(blocks[i]);
      }
    }

    return result;
  }

  private static matches(block: BlockData, page: PageData | undefined, options: QueryOptions): boolean {
    // task marker 筛选
    if (options.marker) {
      if (block.marker !== options.marker) {
        return false;
      }
    }
    if (options.markers) {
      let found = false;
      for (let i = 0; i < options.markers.length; i++) {
        if (block.marker === options.markers[i]) {
          found = true;
          break;
        }
      }
      if (!found) {
        return false;
      }
    }

    // 优先级筛选
    if (options.priority) {
      if (block.priority !== options.priority) {
        return false;
      }
    }

    // 日期范围筛选
    if (options.scheduledAfter) {
      if (block.scheduled === '' || block.scheduled < options.scheduledAfter) {
        return false;
      }
    }
    if (options.scheduledBefore) {
      if (block.scheduled === '' || block.scheduled > options.scheduledBefore) {
        return false;
      }
    }
    if (options.deadlineAfter) {
      if (block.deadline === '' || block.deadline < options.deadlineAfter) {
        return false;
      }
    }
    if (options.deadlineBefore) {
      if (block.deadline === '' || block.deadline > options.deadlineBefore) {
        return false;
      }
    }

    // 标签筛选
    if (options.tags) {
      for (let i = 0; i < options.tags.length; i++) {
        let tagFound = false;
        for (let j = 0; j < block.tags.length; j++) {
          if (block.tags[j] === options.tags[i]) {
            tagFound = true;
            break;
          }
        }
        if (!tagFound) {
          return false;
        }
      }
    }

    // 页面名筛选
    if (options.pageName && page) {
      if (page.name !== options.pageName && page.originalName !== options.pageName) {
        return false;
      }
    }

    // NOT marker: 排除指定状态
    if (options.notMarker) {
      if (block.marker === options.notMarker) return false;
    }
    // NOT tags: 排除指定标签
    if (options.notTags) {
      for (let i = 0; i < options.notTags.length; i++) {
        for (let j = 0; j < block.tags.length; j++) {
          if (block.tags[j] === options.notTags[i]) return false;
        }
      }
    }
    // has-property: 属性存在检查
    if (options.hasProperty) {
      if (!block.properties.has(options.hasProperty)) return false;
    }
    // content 包含
    if (options.contentContains) {
      if (block.content.indexOf(options.contentContains) < 0) return false;
    }

    return true;
  }

  /**
   * 获取所有今天的未完成任务（用于日志页顶部）。
   */
  static getTodayTasks(store: DataStore, journalDay: string): BlockData[] {
    const options: QueryOptions = {
      markers: ['TODO', 'DOING', 'LATER', 'NOW'],
      scheduledAfter: journalDay,
      scheduledBefore: journalDay
    };
    return QueryEngine.query(store, options);
  }
}
