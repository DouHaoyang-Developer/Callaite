import { BlockData } from '../../core/models/Block';
import { BlockView } from './BlockView';
import { WorkspaceService } from '../../services/WorkspaceService';

/**
 * BlockChildren — Block 子组件递归渲染器。
 *
 * 从 BlockList.RenderChildren 抽取为独立组件，支持递归渲染子 Block。
 * 监听 blocksVersion 变化自动刷新。
 *
 * 对应 Logseq 中 block tree 的递归渲染逻辑。
 *
 * 用法：
 *   BlockChildren({ parentUuid: 'block-uuid', depth: 1 })
 *
 * 行为：
 *   - 获取 parentUuid 的直接子 Block
 *   - 对每个子 Block 渲染 BlockView
 *   - 若子 Block 未折叠，递归渲染其子 Block
 *   - 无子 Block 时高度为 0（不占空间）
 */
@Component
export struct BlockChildren {
  @Prop parentUuid: string = '';
  @Prop depth: number = 0;
  @State children: BlockData[] = [];
  @StorageLink('callaite_blocksVersion') @Watch('onRefresh') private blocksVersion: number = 0;

  aboutToAppear(): void {
    this.refreshChildren();
  }

  /**
   * blocksVersion 变化时刷新子 Block 列表。
   * 由 Block 编辑/移动/删除/折叠等操作触发。
   */
  onRefresh(): void {
    this.refreshChildren();
  }

  /**
   * 从 WorkspaceService 获取 parentUuid 的直接子 Block。
   */
  refreshChildren(): void {
    const ws = WorkspaceService.getInstance();
    this.children = ws.getChildrenOfBlock(this.parentUuid);
  }

  build() {
    if (this.children.length === 0) {
      // 无子 Block — 不渲染，高度为 0
      Column().width('100%').height(0)
    } else {
      Column() {
        ForEach(this.children, (child: BlockData) => {
          Column() {
            // 渲染当前子 Block
            BlockView({ blockUuid: child.uuid, depth: child.level })

            // 未折叠时递归渲染孙 Block
            if (!child.collapsed) {
              BlockChildren({ parentUuid: child.uuid, depth: child.level })
            }
          }
          .width('100%')
        }, (child: BlockData) => child.uuid)
      }
      .width('100%')
    }
  }
}
