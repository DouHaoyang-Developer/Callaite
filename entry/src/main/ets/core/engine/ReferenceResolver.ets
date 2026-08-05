import { WorkspaceService } from '../../services/WorkspaceService';
import { DataStore, BacklinkInfo } from '../db/DataStore';
import { BlockData } from '../models/Block';
import { PageData } from '../models/Page';

/**
 * ReferenceResolver — 引用解析器。
 *
 * 对应 Logseq db/common/reference.cljs (312行) + common/util/page_ref.cljs。
 *
 * 职责：
 *  - 解析页面引用 [[name]] 和 Block 引用 ((uuid))
 *  - 页面重命名时传导更新所有引用
 *  - Block 内容更新时刷新引用索引
 *  - 构建引用图（入边 / 出边）
 *  - 从内容中提取页面引用、Block 引用、标签
 */
export class ReferenceResolver {
  private static instance: ReferenceResolver | undefined;

  static getInstance(): ReferenceResolver {
    if (!ReferenceResolver.instance) {
      ReferenceResolver.instance = new ReferenceResolver();
    }
    return ReferenceResolver.instance;
  }

  // ─── 引用解析 ───

  /**
   * 解析页面引用 [[name]] → PageData。
   * 按名称查找页面（不区分大小写）。
   */
  resolvePageRef(name: string): PageData | undefined {
    return WorkspaceService.getInstance().getPageByName(name);
  }

  /**
   * 解析 Block 引用 ((uuid)) → BlockData。
   * 按 UUID 查找 Block。
   */
  resolveBlockRef(uuid: string): BlockData | undefined {
    return WorkspaceService.getInstance().getBlock(uuid);
  }

  // ─── 引用传导 ───

  /**
   * 页面重命名时传导更新所有 [[oldName]] → [[newName]]。
   *
   * 遍历所有页面的所有 Block，将内容中的 [[oldName]] 替换为 [[newName]]，
   * 并刷新引用索引。
   */
  propagateRename(oldName: string, newName: string): void {
    const dataStore = WorkspaceService.getInstance().getDataStore();
    const allPages = dataStore.getAllPages();

    const pattern = '\\[\\[' + this.escapeRegexStr(oldName) + '\\]\\]';
    const regex = new RegExp(pattern, 'g');

    for (let pi = 0; pi < allPages.length; pi++) {
      const blocks = dataStore.getPageBlocks(allPages[pi].uuid);
      let pageModified = false;

      for (let bi = 0; bi < blocks.length; bi++) {
        const block = blocks[bi];
        if (block.content.indexOf('[[' + oldName + ']]') >= 0) {
          // 替换内容中的引用
          block.content = block.content.replace(regex, '[[' + newName + ']]');
          block.updatedAt = Date.now();
          pageModified = true;

          // 刷新引用索引（会重新提取 refs/blockRefs/tags 并保存页面）
          this.propagateBlockUpdate(block.uuid);
        }
      }

      // propagateBlockUpdate 已保存页面，无需重复保存
      if (pageModified) {
        // 已在 propagateBlockUpdate 中保存
      }
    }
  }

  /**
   * Block 内容更新时刷新引用索引。
   *
   * 1. 从 IndexStore 中移除该 Block 的所有旧引用
   * 2. 从内容中重新提取页面引用、Block 引用、标签
   * 3. 更新 Block 的 refs/blockRefs/tags 字段
   * 4. 将新引用注册到 IndexStore
   * 5. 保存所属页面
   */
  propagateBlockUpdate(blockUuid: string): void {
    const workspace = WorkspaceService.getInstance();
    const block = workspace.getBlock(blockUuid);
    if (!block) {
      return;
    }

    const dataStore = workspace.getDataStore();
    const indexStore = dataStore.getIndexStore();

    // 移除旧引用
    indexStore.removeBlockReferences(blockUuid);

    // 重新提取引用
    const pageRefs = this.extractPageRefs(block.content);
    const blockRefs = this.extractBlockRefs(block.content);
    const tags = this.extractTags(block.content);

    // 更新 Block 字段
    block.refs = pageRefs;
    block.blockRefs = blockRefs;
    block.tags = tags;

    // 注册新引用到索引
    for (let i = 0; i < pageRefs.length; i++) {
      indexStore.addReference(blockUuid, pageRefs[i], false);
    }
    for (let i = 0; i < blockRefs.length; i++) {
      indexStore.addReference(blockUuid, blockRefs[i], true);
    }

    // 保存页面
    const pageUuid = dataStore.getPageUuidForBlock(blockUuid);
    if (pageUuid) {
      dataStore.savePage(pageUuid);
    }
  }

  // ─── 引用图 ───

  /**
   * 获取某 Block 的引用图（入边 + 出边）。
   *
   * - incoming: 引用此 Block 的 Block UUID 列表（通过 ((uuid)) 引用）
   * - outgoing: 此 Block 引用的 Block UUID 列表（此 Block 的 blockRefs）
   *
   * @param uuid 目标 Block 的 UUID
   */
  getReferenceGraph(uuid: string): ReferenceGraph {
    const graph: ReferenceGraph = {
      uuid: uuid,
      incoming: [],
      outgoing: []
    };

    const block = WorkspaceService.getInstance().getBlock(uuid);
    if (!block) {
      return graph;
    }

    // 出边：此 Block 引用的其他 Block（blockRefs）
    for (let i = 0; i < block.blockRefs.length; i++) {
      graph.outgoing.push(block.blockRefs[i]);
    }

    // 入边：遍历所有 Block，查找引用了此 Block 的 Block
    const dataStore = WorkspaceService.getInstance().getDataStore();
    const allPages = dataStore.getAllPages();

    for (let pi = 0; pi < allPages.length; pi++) {
      const blocks = dataStore.getPageBlocks(allPages[pi].uuid);
      for (let bi = 0; bi < blocks.length; bi++) {
        const b = blocks[bi];
        // 跳过自身
        if (b.uuid === uuid) {
          continue;
        }
        // 检查是否引用了目标 Block
        for (let ri = 0; ri < b.blockRefs.length; ri++) {
          if (b.blockRefs[ri] === uuid) {
            graph.incoming.push(b.uuid);
            break;
          }
        }
      }
    }

    return graph;
  }

  /**
   * 获取页面所有出边引用（页面引用 [[name]]）。
   *
   * 遍历页面中所有 Block，收集其 refs 中的页面名（去重）。
   *
   * @param pageId 页面 UUID
   * @returns 引用的页面名列表
   */
  getPageOutgoingRefs(pageId: string): string[] {
    const result: string[] = [];
    const blocks = WorkspaceService.getInstance().getDataStore().getPageBlocks(pageId);

    for (let i = 0; i < blocks.length; i++) {
      const refs = blocks[i].refs;
      for (let j = 0; j < refs.length; j++) {
        // 去重
        let found = false;
        for (let k = 0; k < result.length; k++) {
          if (result[k] === refs[j]) {
            found = true;
            break;
          }
        }
        if (!found) {
          result.push(refs[j]);
        }
      }
    }

    return result;
  }

  /**
   * 获取页面所有入边引用（反链）。
   *
   * 通过 IndexStore 的反链索引查找所有引用此页面名的 Block。
   *
   * @param pageName 被引用的页面名
   * @returns 引用此页面的 Block UUID 列表
   */
  getPageIncomingRefs(pageName: string): string[] {
    const result: string[] = [];
    const backlinks: BacklinkInfo[] = WorkspaceService.getInstance().getDataStore().getBacklinks(pageName);

    for (let i = 0; i < backlinks.length; i++) {
      result.push(backlinks[i].sourceBlockId);
    }

    return result;
  }

  // ─── 内容提取 ───

  /**
   * 提取内容中所有 [[page]] 页面引用。
   *
   * 匹配 [[xxx]] 格式，返回 xxx 部分（不含方括号）。
   *
   * @param content Block 文本内容
   * @returns 页面名列表
   */
  extractPageRefs(content: string): string[] {
    const refs: string[] = [];
    const regex = new RegExp('\\[\\[[^\\]]+\\]\\]', 'g');
    const matches = content.match(regex);

    if (matches !== null) {
      for (let i = 0; i < matches.length; i++) {
        // 去掉 [[ 和 ]]
        const ref = matches[i].substring(2, matches[i].length - 2);
        refs.push(ref);
      }
    }

    return refs;
  }

  /**
   * 提取内容中所有 ((uuid)) Block 引用。
   *
   * 匹配 ((36位UUID)) 格式，返回 UUID 部分（不含括号）。
   *
   * @param content Block 文本内容
   * @returns Block UUID 列表
   */
  extractBlockRefs(content: string): string[] {
    const refs: string[] = [];
    const regex = new RegExp('\\(\\([a-fA-F0-9\\-]{36}\\)\\)', 'g');
    const matches = content.match(regex);

    if (matches !== null) {
      for (let i = 0; i < matches.length; i++) {
        // 去掉 (( 和 ))
        const ref = matches[i].substring(2, matches[i].length - 2);
        refs.push(ref);
      }
    }

    return refs;
  }

  /**
   * 提取内容中所有 #tag 标签。
   *
   * 匹配 #xxx 格式（支持中文、字母、数字、连字符），返回 xxx 部分（不含 #）。
   *
   * @param content Block 文本内容
   * @returns 标签名列表
   */
  extractTags(content: string): string[] {
    const tags: string[] = [];
    const regex = new RegExp('#[\\w一-鿿\\-]+', 'g');
    const matches = content.match(regex);

    if (matches !== null) {
      for (let i = 0; i < matches.length; i++) {
        // 去掉前导 #
        const tag = matches[i].substring(1);
        tags.push(tag);
      }
    }

    return tags;
  }

  // ─── 辅助 ───

  /**
   * 转义正则表达式特殊字符。
   * 用于将任意字符串安全地嵌入正则表达式模式中。
   */
  private escapeRegexStr(str: string): string {
    let result = '';
    for (let i = 0; i < str.length; i++) {
      const ch = str.charAt(i);
      if (ch === '(' || ch === ')' || ch === '[' || ch === ']' ||
          ch === '{' || ch === '}' || ch === '.' || ch === '*' ||
          ch === '+' || ch === '?' || ch === '|' || ch === '^' ||
          ch === '$' || ch === '\\') {
        result = result + '\\' + ch;
      } else {
        result = result + ch;
      }
    }
    return result;
  }
}

// ─── 类型定义 ───

/**
 * Block 引用图。
 * 描述一个 Block 的入边（谁引用了它）和出边（它引用了谁）。
 */
export interface ReferenceGraph {
  /** 目标 Block UUID */
  uuid: string;
  /** 引用此 Block 的 UUID 列表（入边） */
  incoming: string[];
  /** 此 Block 引用的 UUID 列表（出边） */
  outgoing: string[];
}
