import { DataStore, BacklinkInfo } from '../core/db/DataStore';

/**
 * BacklinkWarning — 删除前反链计数预警（非阻断）。
 *
 * 设计动机（Obsidian 核心功能拆解 §12.1 第 3 项）：
 *   把「数据完整性约束」前移到破坏性操作的 UX —— 删除一个被别处引用的页面时，
 *   先告诉用户会牵连多少处链接，把不可见的图关系在决策点显性化。
 *
 * 三条硬约束：
 *   1. **非阻断**：这里的文案只做「知情提示」，不改变删除本身的可行性。
 *      调用方负责提供「继续删除」的出口，不得把它变成阻止性校验。
 *   2. **惰性计算**：反链是遍历整个 backlinkIndex 得来的，
 *      只能在「用户点了删除」那一刻算一次；禁止放进 build()/列表渲染/hover 回调。
 *   3. **N=0 返回空串**：无引用时不产出任何文案，由调用方原样拼接，
 *      这样绝大多数（无被引用）页面的删除路径**一个字符都不会变**。
 *
 * 计数口径与 `DataStore.getBacklinks()` / 右侧栏反链面板完全一致：
 * IndexStore.addReference 已按 (sourceBlockId, isBlockRef) 去重，
 * 因此 N = 「引用了该页面的块数」，与用户在反链面板里数到的条数相同 —— 弹窗数字与面板对得上。
 * 同一块里写两次 [[目标]] 只算 1 处（块内去重由 MarkdownParser.extractPageRefs 完成）。
 */

/**
 * 计算指向某页面的反链条数（引用了该页面的块数）。
 *
 * @param dataStore 数据仓库
 * @param pageName 页面名（非文件名，不含 .md）
 * @returns 反链条数；页面名缺失或查询异常时返回 0
 */
export function countBacklinks(dataStore: DataStore, pageName: string): number {
  if (pageName === '') {
    return 0;
  }
  let list: BacklinkInfo[] = [];
  try {
    list = dataStore.getBacklinks(pageName);
  } catch (e) {
    // 索引异常不应阻断删除流程：退化为「无引用」，即不显示预警
    return 0;
  }
  return list.length;
}
