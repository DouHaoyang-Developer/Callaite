import { TablerIcon } from '../common/Icons';

/**
 * WbPageRefData — 白板页面引用数据模型。
 * 对应 Logseq Whiteboards 的 page-ref 节点。
 */
export interface WbPageRefData {
  id: string;
  pageName: string;
  x: number;
  y: number;
  width: number;
  height: number;
  blockCount: number;
}

/**
 * 预览块占位条目。
 */
interface PreviewBlock {
  index: number;
  label: string;
}

/**
 * WbPageRef — 白板页面引用组件。
 *
 * 职责：
 *  - 渲染圆角矩形卡片：页面图标 + 页面名 + Block 数量
 *  - 单击：选中并展开预览（前 5 条 Block 占位）
 *  - 双击：跳转到页面（通过 onNavigate 回调）
 *  - 选中状态：蓝色边框
 */
@Component
export struct WbPageRef {
  @Prop pageRef: WbPageRefData;
  // 命名 zoomScale，避免与组件 scale() 属性方法冲突
  @Prop zoomScale: number = 1;
  @Prop isSelected: boolean = false;
  @State showPreview: boolean = false;

  onNavigate: (pageName: string) => void = (pageName: string) => {};
  onSelect: (id: string) => void = (id: string) => {};

  /**
   * 生成预览 Block 占位列表（最多 5 条）。
   */
  private getPreviewBlocks(): PreviewBlock[] {
    const blocks: PreviewBlock[] = [];
    const count = Math.min(this.pageRef.blockCount, 5);
    for (let i = 0; i < count; i++) {
      blocks.push({ index: i, label: 'Block ' + (i + 1) });
    }
    return blocks;
  }

  build() {
    Column({ space: 6 }) {
      // 页面标题行
      Row({ space: 8 }) {
        TablerIcon('file', 16, $r('app.color.primary'))
        Text(this.pageRef.pageName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      // Block 数量
      Row() {
        Text(this.pageRef.blockCount + ' blocks')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
      }
      .width('100%')

      // 预览列表
      if (this.showPreview) {
        Divider()
          .color($r('app.color.border'))
          .strokeWidth(1)
        ForEach(this.getPreviewBlocks(), (pb: PreviewBlock) => {
          Row({ space: 6 }) {
            Circle({ width: 4, height: 4 })
              .fill($r('app.color.muted_text'))
            Text(pb.label)
              .fontSize(11)
              .fontColor($r('app.color.muted_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }, (pb: PreviewBlock) => `${pb.index}`)
      }
    }
    .width(this.pageRef.width * this.zoomScale)
    .padding(10)
    .backgroundColor($r('app.color.surface2'))
    .borderRadius(8)
    .border({
      width: this.isSelected ? 2 : 1,
      color: this.isSelected ? $r('app.color.primary') : $r('app.color.border')
    })
    .onClick(() => {
      this.showPreview = !this.showPreview;
      this.onSelect(this.pageRef.id);
    })
    .gesture(
      TapGesture({ count: 2 })
        .onAction(() => {
          this.onNavigate(this.pageRef.pageName);
        })
    )
  }
}
