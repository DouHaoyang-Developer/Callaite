import { findIconPath, IconPathData } from './TablerIconPaths';
import { display } from '@kit.ArkUI';

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

  /**
   * 屏幕密度。Shape/Path 的坐标单位是该 SDK 上的物理像素
   * （实测 24 单位方块渲染为 26x25px），因此必须按密度换算：
   * 目标像素尺寸 = iconSize(vp) × densityPixels。
   */
  private densityScale(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.densityPixels > 0 ? d.densityPixels : 1;
    } catch (_e) {
      return 1;
    }
  }

  private resolveStrokeWidthPx(): number {
    // Tabler 标准线宽 2（24 设计坐标系），等比换算到像素
    const px = this.iconSize * this.densityScale();
    return px / 12;
  }

  /**
   * 数值缩放路径坐标：Tabler 以 24x24 设计坐标系存储。
   * 乘以 factor 后直接生成像素坐标。
   */
  private scaledPath(path: string, factor: number): string {
    let out = '';
    let i = 0;
    while (i < path.length) {
      const ch = path.charAt(i);
      if (ch === '-' || ch === '.' || (ch >= '0' && ch <= '9')) {
        let j = i;
        while (j < path.length) {
          const cj = path.charAt(j);
          if (cj === '-' || cj === '.' || (cj >= '0' && cj <= '9')) {
            j++;
          } else {
            break;
          }
        }
        const numStr = path.substring(i, j);
        const num = parseFloat(numStr);
        out += (Math.round(num * factor * 100) / 100).toString();
        i = j;
      } else {
        out += ch;
        i++;
      }
    }
    return out;
  }

  build() {
    if (this.pathData) {
      Shape() {
        ForEach(this.pathData.paths, (path: string, index: number) => {
          Path()
            .width(this.iconSize * this.densityScale())
            .height(this.iconSize * this.densityScale())
            .commands(this.scaledPath(path, this.iconSize * this.densityScale() / 24))
            .fillOpacity(0)
            .stroke(this.iconColor)
            .strokeWidth(this.resolveStrokeWidthPx())
            .strokeLineCap(LineCapStyle.Round)
            .strokeLineJoin(LineJoinStyle.Round)
        }, (path: string, index: number) => `${index}`)
      }
      .width(this.iconSize)
      .height(this.iconSize)
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
