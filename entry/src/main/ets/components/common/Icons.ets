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

  build() {
    if (this.pathData) {
      Shape() {
        ForEach(this.pathData.paths, (path: string, index: number) => {
          Path()
            .commands(path)
            .fillOpacity(0)
            .stroke(this.iconColor)
            .strokeWidth(2)
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
        }, (path: string, index: number) => `${index}`)
      }
      .width(this.iconSize)
      .height(this.iconSize)
    } else {
      Circle({ width: this.iconSize, height: this.iconSize })
        .fill(this.iconColor)
        .opacity(0.3)
    }
  }
}

/**
 * Tabler 图标 @Builder 入口 — 供组件 build() 方法中直接调用。
 * 用法：TablerIcon('search', 20, $r('app.color.text'))
 */
@Builder
export function TablerIcon(name: string, size: number = 18, color: ResourceColor = $r('app.color.muted_text')) {
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
