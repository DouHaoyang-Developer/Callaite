import { findIconPath, IconPathData } from './TablerIconPaths';

interface IconSvgParams {
  pathData: IconPathData;
  size: number;
  color: ResourceColor;
}

/**
 * 图标渲染组件 — 将 Tabler SVG path 数据渲染为 ArkTS Shape/Path。
 * 使用 @Component 以支持 aboutToAppear 中的图标查找逻辑。
 */
@Component
struct IconRenderer {
  @Prop name: string;
  @Prop iconSize: number;
  @Prop iconColor: ResourceColor;
  private pathData: IconPathData | undefined;

  aboutToAppear(): void {
    this.pathData = findIconPath(this.name);
  }

  private resolveStrokeWidth(): number {
    // Tabler 图标以 24x24 为设计坐标系、标准线宽 2，按渲染尺寸等比缩放线宽，
    // 避免大图标线条过粗、小图标线条过糊。
    const width = this.iconSize / 12;
    return width < 0.8 ? 0.8 : width;
  }

  build() {
    if (this.pathData) {
      Shape() {
        ForEach(this.pathData.paths, (path: string, index: number) => {
          Path()
            .commands(path)
            .fillOpacity(0)
            .stroke(this.iconColor)
            .strokeWidth(this.resolveStrokeWidth())
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
        }, (path: string, index: number) => `${index}`)
      }
      .width(this.iconSize)
      .height(this.iconSize)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })
    } else {
      // 未找到图标时使用带边框的占位框，避免误认为错位的实心圆
      Rect({ width: this.iconSize, height: this.iconSize, radius: this.iconSize * 0.18 })
        .fillOpacity(0)
        .stroke(this.iconColor)
        .strokeWidth(1)
        .opacity(0.4)
    }
  }
}

/**
 * Tabler 图标 @Builder 入口 — 供组件 build() 方法中直接调用。
 * 用法：TablerIcon('search', 20, $r('app.color.text'))
 */
@Builder
// Logseq 默认图标尺寸: 16px (Logseq 实际使用 16-18px 范围的图标)
export function TablerIcon(name: string, size: number = 16, color: ResourceColor = $r('app.color.muted_text')) {
  IconRenderer({ name: name, iconSize: size, iconColor: color })
}

export function getNodeIcon(nodeType: string): string {
  if (nodeType === 'class') {
    return 'hash';
  }
  if (nodeType === 'property') {
    return 'letter-r';
  }
  if (nodeType === 'page') {
    return 'file';
  }
  if (nodeType === 'pdf') {
    return 'book';
  }
  return 'point-filled';
}
