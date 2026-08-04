import { BlockData } from '../../core/models/Block';
import { BlockView } from './BlockView';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { SlashMenu } from './SlashMenu';
import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';

/**
 * BlockList — Block 列表组件。
 *
 * 管理页面的 Block 列表显示、焦点、键盘快捷键、Slash 菜单。
 * 对应 Logseq components/block.cljs 的列表层。
 */
@Component
export struct BlockList {
  @Prop pageId: string = '';
  @Prop pageName: string = '';
  @State blocks: BlockData[] = [];
  @State slashMenuVisible: boolean = false;
  @State slashMenuBlockUuid: string = '';

  aboutToAppear(): void {
    this.refreshBlocks();
  }

  refreshBlocks(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (page) {
      this.blocks = ws.getPageBlocks(page.uuid);
    } else {
      this.blocks = [];
    }
  }

  build() {
    Column({ space: 0 }) {
      if (this.blocks.length === 0) {
        // 空页面 — 显示创建提示
        Column({ space: 12 }) {
          TablerIcon('edit', 40, $r('app.color.muted_text'))
          Text(t('empty_page'))
            .fontSize(16)
            .fontColor($r('app.color.muted_text'))
            .onClick(() => {
              this.addTopLevelBlock();
            })
        }
        .width('100%')
        .padding({ top: 60 })
        .alignItems(HorizontalAlign.Center)
      } else {
        // Block 树
        ForEach(this.blocks, (block: BlockData) => {
          Column() {
            BlockView({ blockUuid: block.uuid, depth: block.level })

            // 递归渲染子 Block（未折叠时）
            if (!block.collapsed) {
              this.RenderChildren(block.uuid);
            }
          }
          .width('100%')
        }, (block: BlockData) => block.uuid)
      }

      // 底部添加按钮
      Row() {
        Row({ space: 8 }) {
          TablerIcon('plus', 18, $r('app.color.muted_text'))
          Text('添加 Block')
            .fontSize(15)
            .fontColor($r('app.color.muted_text'))
        }
        .width('100%')
        .height(40)
        .padding({ left: 8, right: 8 })
        .borderRadius(6)
        .onClick(() => {
          this.addTopLevelBlock();
        })
      }
      .width('100%')
      .padding({ top: 8 })

      // Slash 命令菜单
      if (this.slashMenuVisible) {
        SlashMenu({ blockUuid: this.slashMenuBlockUuid })
      }
    }
    .width('100%')
  }

  @Builder
  RenderChildren(parentUuid: string) {
    Column() {
      ForEach(this.getChildrenForParent(parentUuid), (child: BlockData) => {
        Column() {
          BlockView({ blockUuid: child.uuid, depth: child.level })

          if (!child.collapsed) {
            this.RenderChildren(child.uuid);
          }
        }
        .width('100%')
      }, (child: BlockData) => child.uuid)
    }
    .width('100%')
  }

  getChildrenForParent(parentUuid: string): BlockData[] {
    const ws = WorkspaceService.getInstance();
    return ws.getChildrenOfBlock(parentUuid);
  }

  // ─── 操作 ───

  addTopLevelBlock(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (!page) {
      return;
    }

    const result = ws.executeOp({
      type: 'insert-block',
      content: '',
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: this.blocks.length > 0 ? this.blocks[this.blocks.length - 1].uuid : '',
      level: 0
    });

    this.refreshBlocks();
  }

  openSlashMenu(blockUuid: string): void {
    this.slashMenuBlockUuid = blockUuid;
    this.slashMenuVisible = true;
  }
}
