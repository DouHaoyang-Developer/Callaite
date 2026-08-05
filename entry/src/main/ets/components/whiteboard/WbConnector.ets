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
  @Prop isSelected: boolean = false;

  /**
   * 计算贝塞尔/折线路径 SVG commands。
   */
  calculatePath(): string {
    const fp = this.connector.fromPoint;
    const tp = this.connector.toPoint;
    if (this.connector.type === 'straight') {
      return 'M ' + fp.x + ' ' + fp.y + ' L ' + tp.x + ' ' + tp.y;
    } else if (this.connector.type === 'curved') {
      const cx = (fp.x + tp.x) / 2;
      const cy = (fp.y + tp.y) / 2 - 50;
      return 'M ' + fp.x + ' ' + fp.y + ' Q ' + cx + ' ' + cy + ' ' + tp.x + ' ' + tp.y;
    } else {
      const mx = tp.x;
      const my = fp.y;
      return 'M ' + fp.x + ' ' + fp.y + ' L ' + mx + ' ' + my + ' L ' + tp.x + ' ' + tp.y;
    }
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
   * 计算箭头路径 SVG commands。
   */
  calculateArrowPath(): string {
    const angle = this.calculateArrowAngle();
    const arrowLength = 10;
    const arrowSpread = Math.PI / 7;
    const tp = this.connector.toPoint;
    const p1x = tp.x - arrowLength * Math.cos(angle - arrowSpread);
    const p1y = tp.y - arrowLength * Math.sin(angle - arrowSpread);
    const p2x = tp.x - arrowLength * Math.cos(angle + arrowSpread);
    const p2y = tp.y - arrowLength * Math.sin(angle + arrowSpread);
    return 'M ' + p1x + ' ' + p1y + ' L ' + tp.x + ' ' + tp.y + ' L ' + p2x + ' ' + p2y;
  }

  /**
   * 计算包围盒宽度。
   */
  private getBoundsWidth(): number {
    const minX = Math.min(this.connector.fromPoint.x, this.connector.toPoint.x);
    const maxX = Math.max(this.connector.fromPoint.x, this.connector.toPoint.x);
    return maxX - minX + 20;
  }

  /**
   * 计算包围盒高度。
   */
  private getBoundsHeight(): number {
    const minY = Math.min(this.connector.fromPoint.y, this.connector.toPoint.y);
    const maxY = Math.max(this.connector.fromPoint.y, this.connector.toPoint.y);
    return maxY - minY + 20;
  }

  /**
   * 计算偏移 X（使路径相对于 Shape 左上角）。
   */
  private getOffsetX(): number {
    const minX = Math.min(this.connector.fromPoint.x, this.connector.toPoint.x);
    return minX - 10;
  }

  /**
   * 计算偏移 Y。
   */
  private getOffsetY(): number {
    const minY = Math.min(this.connector.fromPoint.y, this.connector.toPoint.y);
    return minY - 10;
  }

  /**
   * 计算起点控制点 X。
   */
  private getFromHandleX(): number {
    return this.connector.fromPoint.x - this.getOffsetX() - 4;
  }

  /**
   * 计算起点控制点 Y。
   */
  private getFromHandleY(): number {
    return this.connector.fromPoint.y - this.getOffsetY() - 4;
  }

  /**
   * 计算终点控制点 X。
   */
  private getToHandleX(): number {
    return this.connector.toPoint.x - this.getOffsetX() - 4;
  }

  /**
   * 计算终点控制点 Y。
   */
  private getToHandleY(): number {
    return this.connector.toPoint.y - this.getOffsetY() - 4;
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
      // 主路径
      Path()
        .commands(this.calculatePath())
        .stroke(this.connector.color)
        .strokeWidth(2)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        .fillOpacity(0)
      // 箭头
      Path()
        .commands(this.calculateArrowPath())
        .stroke(this.connector.color)
        .strokeWidth(2)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        .fillOpacity(0)
      // 选中控制点
      if (this.isSelected) {
        this.ControlPoints()
      }
    }
    .width(this.getBoundsWidth())
    .height(this.getBoundsHeight())
    .position({ x: this.getOffsetX(), y: this.getOffsetY() })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
