import { WorkspaceService } from './WorkspaceService';
import { CloudSyncService } from './CloudSyncService';

/**
 * Block 元数据（用于跨设备快速索引/搜索）。
 */
interface BlockMeta {
  uuid: string;
  pageId: string;
  content: string;
  marker: string;
  priority: string;
  tags: string[];
  scheduled: string;
  deadline: string;
  updatedAt: number;
}

/**
 * BlockMetadataSyncService — Block 元数据端云同步。
 *
 * 将全量 Block 元数据摘要序列化为 JSON，经 CloudSyncService 加密后写入云目录，
 * 与 .md 文件同步共用端云协同通道。用于跨设备快速检索，不替代完整 .md 内容同步。
 */
export class BlockMetadataSyncService {
  static buildMetadata(): BlockMeta[] {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    const result: BlockMeta[] = [];
    for (let i = 0; i < pages.length; i++) {
      const blocks = ws.getPageBlocks(pages[i].uuid);
      for (let j = 0; j < blocks.length; j++) {
        const b = blocks[j];
        const tags: string[] = [];
        for (let k = 0; k < b.tags.length; k++) {
          tags.push(b.tags[k]);
        }
        const meta: BlockMeta = {
          uuid: b.uuid,
          pageId: b.pageId,
          content: b.content.substring(0, 200),
          marker: b.marker,
          priority: b.priority,
          tags: tags,
          scheduled: b.scheduled,
          deadline: b.deadline,
          updatedAt: b.updatedAt
        };
        result.push(meta);
      }
    }
    return result;
  }

  static async syncToCloud(): Promise<boolean> {
    const meta = BlockMetadataSyncService.buildMetadata();
    return CloudSyncService.syncMetadataToCloud(JSON.stringify(meta));
  }
}
