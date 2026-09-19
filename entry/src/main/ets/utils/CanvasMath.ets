/**
 * CanvasMath —— Canvas 绘制坐标的数值防护。
 *
 * 背景（API 26.0.0 行为变更，官方 changelog app-all-5101）：
 *   CanvasRenderingContext2D / OffscreenCanvasRenderingContext2D 的方法在传入
 *   NaN / Infinity 后，「其它」绘制方法由 **不绘制** 变更为 **正常绘制**。
 *   也就是说，一处坐标异常不再只是那一条线画不出来，而是会污染整幅画面
 *   （白板 / 图谱的缩放与力导向布局都存在除零与未初始化风险）。
 *
 * 因此所有进入绘制调用的坐标必须在源头做有限性校验。
 */
export class CanvasMath {
  /** 有限数则原样返回，否则返回 fallback（默认 0） */
  static safe(v: number, fallback: number = 0): number {
    return Number.isFinite(v) ? v : fallback;
  }

  /** 全部为有限数时返回 true（用于跳过整段绘制） */
  static allFinite(values: number[]): boolean {
    for (let i = 0; i < values.length; i++) {
      if (!Number.isFinite(values[i])) {
        return false;
      }
    }
    return true;
  }

  /** 任一为非有限数时返回 true（等价于 !allFinite，便于正向表达） */
  static anyNotFinite(values: number[]): boolean {
    return !CanvasMath.allFinite(values);
  }

  /** 安全除法：分母为 0 或结果非有限数时返回 fallback */
  static div(a: number, b: number, fallback: number = 0): number {
    if (b === 0 || !Number.isFinite(b)) {
      return fallback;
    }
    const r = a / b;
    return Number.isFinite(r) ? r : fallback;
  }

  // ─── 零分配便捷方法（绘制热路径禁用数组字面量，避免 GC 风暴）───

  static notFinite2(a: number, b: number): boolean {
    return !Number.isFinite(a) || !Number.isFinite(b);
  }

  static notFinite3(a: number, b: number, c: number): boolean {
    return !Number.isFinite(a) || !Number.isFinite(b) || !Number.isFinite(c);
  }

  static notFinite4(a: number, b: number, c: number, d: number): boolean {
    return !Number.isFinite(a) || !Number.isFinite(b)
      || !Number.isFinite(c) || !Number.isFinite(d);
  }
}
