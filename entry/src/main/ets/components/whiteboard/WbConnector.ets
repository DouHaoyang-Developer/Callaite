import { display } from '@kit.ArkUI';

/**
 * ConnectorPoint — 连线端点坐标。
 */
export interface ConnectorPoint {
  x: number;
  y: number;
}

/**
 * WbConnectorData — 白板连线数据模型。
 * type: 'straight' | 'curved' | 'elbow'
 */
export interface WbConnectorData {
  id: string;
  fromShapeId: string;
  toShapeId: string;
  fromPoint: ConnectorPoint;
  toPoint: ConnectorPoint;
  type: string;
  color: string;
}

/**
 * WbConnector — 白板连线渲染组件。
 *
 * 职责：
 *  - 根据连线类型渲染直线/曲线/折线
 *  - 在终点绘制箭头
 *  - 使用 Shape + Path 组件绘制贝塞尔曲线
 *  - 选中时显示控制点
 */
@Component
export struct WbConnector {
  @Prop connector: WbConnectorData;
  // 命名 zoomScale，避免与组件 scale() 属性方法冲突
  @Prop zoomScale: number = 1;
  @Prop panX: number = 0;
  @Prop panY: number = 0;
  @Prop isSelected: boolean = false;

  /**
   * 屏幕密度。Shape/Path 坐标单位是该 SDK 上的物理像素，
   * 与 Icons 渲染的结论一致，必须按密度换算。
   */
  private densityScale(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.densityPixels > 0 ? d.densityPixels : 1;
    } catch (_e) {
      return 1;
    }
  }

  /**
   * 计算贝塞尔/折线路径（局部坐标，相对 Shape 左上角）。
   * 渲染时再按 zoomScale × density 数值缩放。
   */
  localPath(): string {
    const fp = this.connector.fromPoint;
    const tp = this.connector.toPoint;
    const ox = this.getOffsetX();
    const oy = this.getOffsetY();
    if (this.connector.type === 'straight') {
      return 'M ' + (fp.x - ox) + ' ' + (fp.y - oy) + ' L ' + (tp.x - ox) + ' ' + (tp.y - oy);
    } else if (this.connector.type === 'curved') {
      const cx = (fp.x + tp.x) / 2 - ox;
      const cy = Math.min(fp.y, tp.y) - 20 - oy;
      return 'M ' + (fp.x - ox) + ' ' + (fp.y - oy) + ' Q ' + cx + ' ' + cy + ' ' + (tp.x - ox) + ' ' + (tp.y - oy);
    } else {
      const mx = tp.x - ox;
      const my = fp.y - oy;
      return 'M ' + (fp.x - ox) + ' ' + (fp.y - oy) + ' L ' + mx + ' ' + my + ' L ' + (tp.x - ox) + ' ' + (tp.y - oy);
    }
  }

  /**
   * 数值缩放路径坐标（命令感知：arc 的 rotation/flag 参数不可缩放——
   * 此处连线路径无 arc，保留通用实现以防未来扩展）。
   */
  private scalePath(path: string, factor: number): string {
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

  /**
   * 计算箭头角度（弧度）。
   */
  calculateArrowAngle(): number {
    const dx = this.connector.toPoint.x - this.connector.fromPoint.x;
    const dy = this.connector.toPoint.y - this.connector.fromPoint.y;
    return Math.atan2(dy, dx);
  }

  /**
   * 计算箭头路径（局部坐标）。
   */
  localArrowPath(): string {
    const angle = this.calculateArrowAngle();
    const arrowLength = 10;
    const arrowSpread = Math.PI / 7;
    const tp = this.connector.toPoint;
    const ox = this.getOffsetX();
    const oy = this.getOffsetY();
    const p1x = tp.x - arrowLength * Math.cos(angle - arrowSpread) - ox;
    const p1y = tp.y - arrowLength * Math.sin(angle - arrowSpread) - oy;
    const p2x = tp.x - arrowLength * Math.cos(angle + arrowSpread) - ox;
    const p2y = tp.y - arrowLength * Math.sin(angle + arrowSpread) - oy;
    return 'M ' + p1x + ' ' + p1y + ' L ' + (tp.x - ox) + ' ' + (tp.y - oy) + ' L ' + p2x + ' ' + p2y;
  }

  /**
   * 计算包围盒宽度（25 单位边距容纳曲线外拱与箭头）。
   */
  private getBoundsWidth(): number {
    const minX = Math.min(this.connector.fromPoint.x, this.connector.toPoint.x);
    const maxX = Math.max(this.connector.fromPoint.x, this.connector.toPoint.x);
    return maxX - minX + 50;
  }

  /**
   * 计算包围盒高度。
   */
  private getBoundsHeight(): number {
    const minY = Math.min(this.connector.fromPoint.y, this.connector.toPoint.y);
    const maxY = Math.max(this.connector.fromPoint.y, this.connector.toPoint.y);
    return maxY - minY + 50;
  }

  /**
   * 计算偏移 X（使路径相对于 Shape 左上角）。
   */
  private getOffsetX(): number {
    const minX = Math.min(this.connector.fromPoint.x, this.connector.toPoint.x);
    return minX - 25;
  }

  /**
   * 计算偏移 Y。
   */
  private getOffsetY(): number {
    const minY = Math.min(this.connector.fromPoint.y, this.connector.toPoint.y);
    return minY - 25;
  }

  /**
   * 计算起点控制点 X（局部坐标，随缩放）。
   */
  private getFromHandleX(): number {
    return (this.connector.fromPoint.x - this.getOffsetX()) * this.zoomScale - 4;
  }

  /**
   * 计算起点控制点 Y。
   */
  private getFromHandleY(): number {
    return (this.connector.fromPoint.y - this.getOffsetY()) * this.zoomScale - 4;
  }

  /**
   * 计算终点控制点 X。
   */
  private getToHandleX(): number {
    return (this.connector.toPoint.x - this.getOffsetX()) * this.zoomScale - 4;
  }

  /**
   * 计算终点控制点 Y。
   */
  private getToHandleY(): number {
    return (this.connector.toPoint.y - this.getOffsetY()) * this.zoomScale - 4;
  }

  @Builder ControlPoints() {
    Circle({ width: 8, height: 8 })
      .fill(Color.White)
      .stroke($r('app.color.primary'))
      .strokeWidth(1.5)
      .position({ x: this.getFromHandleX(), y: this.getFromHandleY() })
    Circle({ width: 8, height: 8 })
      .fill(Color.White)
      .stroke($r('app.color.primary'))
      .strokeWidth(1.5)
      .position({ x: this.getToHandleX(), y: this.getToHandleY() })
  }

  build() {
    Shape() {
      // 主路径（zoomScale × 密度 数值缩放，跟随平移）
      Path()
        .width(this.getBoundsWidth() * this.zoomScale * this.densityScale())
        .height(this.getBoundsHeight() * this.zoomScale * this.densityScale())
        .commands(this.scalePath(this.localPath(), this.zoomScale * this.densityScale()))
        .stroke(this.connector.color)
        .strokeWidth(2 * this.zoomScale)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        .fillOpacity(0)
      // 箭头
      Path()
        .width(this.getBoundsWidth() * this.zoomScale * this.densityScale())
        .height(this.getBoundsHeight() * this.zoomScale * this.densityScale())
        .commands(this.scalePath(this.localArrowPath(), this.zoomScale * this.densityScale()))
        .stroke(this.connector.color)
        .strokeWidth(2 * this.zoomScale)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        .fillOpacity(0)
      // 选中控制点
      if (this.isSelected) {
        this.ControlPoints()
      }
    }
    .width(this.getBoundsWidth() * this.zoomScale)
    .height(this.getBoundsHeight() * this.zoomScale)
    .position({
      x: this.getOffsetX() * this.zoomScale + this.panX,
      y: this.getOffsetY() * this.zoomScale + this.panY
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
