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
    // Tabler 标准线宽 2（24 设计坐标系）→ iconSize/12。
    // 注意：strokeWidth 单位为 vp，不能再乘 densityPixels，
    // 否则线宽被放大 2~3 倍，小尺寸图标糊成一团。
    return this.iconSize / 12;
  }

  /**
   * 数值缩放路径坐标：Tabler 以 24x24 设计坐标系存储。
   * 乘以 factor 后直接生成像素坐标。
   *
   * 命令感知解析：a/A（椭圆弧）的 7 个参数中，第 3 个（x-axis-rotation，
   * 角度）与第 4/5 个（large-arc-flag / sweep-flag，必须是 0 或 1）不可缩放，
   * 否则含圆弧的图标（search/home/calendar/settings 等）会因非法 flag
   * 被渲染器丢弃而畸形。
   */
  private scaledPath(path: string, factor: number): string {
    const f = factor;
    let out = '';
    let i = 0;
    let cmd = '';
    let argIndex = 0;
    while (i < path.length) {
      const ch = path.charAt(i);
      if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) {
        cmd = ch;
        argIndex = 0;
        out += ch;
        i++;
      } else if (ch === '-' || ch === '.' || (ch >= '0' && ch <= '9')) {
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
        // arc 参数序：rx ry rotation large-arc-flag sweep-flag dx dy
        const arcPos = argIndex % 7;
        const keepRaw = (cmd === 'a' || cmd === 'A') && (arcPos === 2 || arcPos === 3 || arcPos === 4);
        out += keepRaw ? numStr : (Math.round(num * f * 100) / 100).toString();
        argIndex++;
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
