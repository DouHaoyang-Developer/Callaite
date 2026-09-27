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
  /**
   * S1-H：行级长按上报回调（透传给每一层 BlockView，并递归传给下一层 BlockChildren）。
   *
   * 为什么必须透传：整页大纲的拖拽层只有 1 个实例，它靠「行上报的 uuid + 坐标」知道
   * 长按落在哪一行。若不透传，子块行虽然能被命中表登记（onAreaChange 不依赖本回调），
   * 却无法成为**拖拽源** —— 表现为「只有顶层块拖得动」。目标端不受影响。
   *
   * 缺省为空实现：feed 内嵌模式的 Column 分支不传该回调 → 行为与接线前完全一致。
   */
  onRowGrab: (uuid: string, globalX: number, globalY: number) => void = () => {};
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
            // 渲染当前子 Block（S1-H：透传行级长按上报，使子块同样可被拖拽）
            BlockView({
              blockUuid: child.uuid,
              depth: child.level,
              onRowGrab: (uuid: string, gx: number, gy: number) => {
                this.onRowGrab(uuid, gx, gy);
              }
            })

            // 未折叠时递归渲染孙 Block（继续透传，覆盖任意深度）
            if (!child.collapsed) {
              BlockChildren({
                parentUuid: child.uuid,
                depth: child.level,
                onRowGrab: (uuid: string, gx: number, gy: number) => {
                  this.onRowGrab(uuid, gx, gy);
                }
              })
            }
          }
          .width('100%')
        }, (child: BlockData) => child.uuid)
      }
      .width('100%')
    }
  }
}
