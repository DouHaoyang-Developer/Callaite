/**
 * PenKitService — 手写笔服务（单例）。
 *
 * 功能：
 *  - 手写笔压感映射（4 种笔刷：钢笔/铅笔/马克笔/橡皮擦）
 *  - 手掌误触过滤（压感阈值检测）
 *  - 笔触平滑（移动平均，窗口 3）
 *  - 模拟器降级（PenKit 不可用时基于触摸模拟压感）
 *  - 当前笔刷状态管理（setBrush/getBrush）
 *
 * 设计说明：
 *  - @kit.PenKit 在部分 SDK 不可用，本服务采用运行时检测策略
 *  - 优先使用 @kit.MultimodalAwarenessKit 的 inputDevice API 检测手写笔
 *  - 由于 ArkTS 不支持 try-import，若 SDK 缺少该 kit 会导致编译失败
 *  - 因此本服务通过 TouchEvent 的压感字段进行运行时检测
 *  - 检测到非零且变化的压感时判定手写笔可用
 *  - 否则降级为普通触摸模式（pressure 固定 1.0）
 *
 * 压感映射规则：
 *  - PEN:    线宽 = baseSize * (0.3 + 0.7 * pressure)
 *  - PENCIL:  线宽 = baseSize * (0.5 + 0.5 * pressure)，透明度随压感变化
 *  - MARKER:  线宽 = baseSize * (0.8 + 0.2 * pressure)，透明度固定 0.6
 *  - ERASER:  线宽 = baseSize * 1.5，无视压感
 */

// ═══════════════════════════════════════════
//  类型定义
// ═══════════════════════════════════════════

/**
 * PenBrushType — 笔刷类型枚举。
 */
export enum PenBrushType {
  PEN = 'pen',
  PENCIL = 'pencil',
  MARKER = 'marker',
  ERASER = 'eraser'
}

/**
 * BrushConfig — 笔刷配置。
 */
export interface BrushConfig {
  type: PenBrushType;
  color: number;
  size: number;
  opacity: number;
  pressureSensitive: boolean;
}

/**
 * StrokePoint — 笔触点数据。
 */
export interface StrokePoint {
  x: number;
  y: number;
  pressure: number;
  timestamp: number;
}

/**
 * StrokeData — 完整笔触数据（用于渲染和持久化）。
 */
export interface StrokeData {
  id: string;
  brushType: PenBrushType;
  color: number;
  baseSize: number;
  opacity: number;
  points: StrokePoint[];
}

/**
 * BrushPresetItem — 笔刷预设按钮数据。
 */
export interface BrushPresetItem {
  type: PenBrushType;
  label: string;
  symbol: string;
}

// ═══════════════════════════════════════════
//  常量
// ═══════════════════════════════════════════

/** 手掌误触压感阈值（低于此值判定为手掌） */
const PALM_PRESSURE_THRESHOLD = 0.1;

/** 默认压感（模拟器/手指触摸模式） */
const DEFAULT_PRESSURE = 1.0;

/** 笔刷预设列表 */
const BRUSH_PRESETS: BrushPresetItem[] = [
  { type: PenBrushType.PEN, label: '钢笔', symbol: '✎' },
  { type: PenBrushType.PENCIL, label: '铅笔', symbol: '✏' },
  { type: PenBrushType.MARKER, label: '马克笔', symbol: '▮' },
  { type: PenBrushType.ERASER, label: '橡皮擦', symbol: '⌫' }
];

/** 预设颜色列表（ARGB 格式） */
const PRESET_COLORS: number[] = [
  0xFF000000, // 黑
  0xFF0458A6, // 蓝
  0xFFE74C3C, // 红
  0xFF2ECC71, // 绿
  0xFFF39C12, // 橙
  0xFF9B59B6  // 紫
];

/** 默认笔刷配置 */
const DEFAULT_BRUSH: BrushConfig = {
  type: PenBrushType.PEN,
  color: 0xFF0458A6,
  size: 4,
  opacity: 1.0,
  pressureSensitive: true
};

// ═══════════════════════════════════════════
//  PenKitService 单例
// ═══════════════════════════════════════════

/**
 * PenKitService — 手写笔核心服务。
 *
 * 单例模式，通过 PenKitService.getInstance() 获取。
 * 管理当前笔刷状态，提供压感映射、手掌过滤、笔触平滑等能力。
 */
export class PenKitService {
  private static instance: PenKitService | undefined;

  // 当前笔刷配置
  private currentBrush: BrushConfig;

  // 手写笔可用性标志
  private penAvailable: boolean = false;
  private penDetectAttempted: boolean = false;

  // 压感变化记录（用于运行时检测手写笔）
  private lastSeenPressure: number = 0;

  // 笔触计数器（生成唯一 ID）
  private strokeCounter: number = 0;

  /** 私有构造函数 */
  private constructor() {
    this.currentBrush = this.deepCopyBrush(DEFAULT_BRUSH);
    this.detectPenAvailability();
  }

  /** 获取单例实例 */
  static getInstance(): PenKitService {
    if (!PenKitService.instance) {
      PenKitService.instance = new PenKitService();
    }
    return PenKitService.instance;
  }

  // ─── 手写笔检测 ────────────────────────────

  /**
   * 异步检测手写笔设备可用性。
   *
   * 策略：
   *  1. 默认降级为触摸模式（penAvailable = false）
   *  2. 通过 notifyTouchPressure() 在运行时检测压感变化
   *  3. 若需使用 @kit.MultimodalAwarenessKit 的 inputDevice API，
   *     可在 SDK 支持时添加动态导入：
   *       const mod = await import('@kit.MultimodalAwarenessKit');
   *     并调用 mod.inputDevice.getDeviceList() 检测手写笔设备
   */
  async detectPenAvailability(): Promise<void> {
    if (this.penDetectAttempted) {
      return;
    }
    this.penDetectAttempted = true;
    // 默认降级为触摸模式，等待运行时压感检测
    this.penAvailable = false;
    console.info('[PenKitService] 初始化为触摸模式，等待运行时压感检测');
  }

  /**
   * 手动设置手写笔可用性（用于测试或显式配置）。
   */
  setPenAvailable(available: boolean): void {
    this.penAvailable = available;
    this.penDetectAttempted = true;
  }

  /**
   * 检测手写笔是否可用。
   * 模拟器环境下返回 false，pressure 将固定为 1.0。
   */
  isPenAvailable(): boolean {
    return this.penAvailable;
  }

  /**
   * 通知触摸压感值（运行时检测手写笔）。
   * 若收到非零且非 1.0 的压感值，判定手写笔可用。
   *
   * @param pressure 触摸事件上报的压感值
   */
  notifyTouchPressure(pressure: number): void {
    if (!this.penAvailable && pressure > 0) {
      // 压感值在 (0, 1) 区间内变化，说明是手写笔
      if (pressure < 1.0 || this.lastSeenPressure !== pressure) {
        this.penAvailable = true;
        console.info('[PenKitService] 通过触摸压感检测到手写笔: ' + pressure);
      }
    }
    this.lastSeenPressure = pressure;
  }

  // ─── 笔刷状态管理 ──────────────────────────

  /**
   * 设置当前笔刷配置。
   */
  setBrush(brush: BrushConfig): void {
    this.currentBrush = this.deepCopyBrush(brush);
  }

  /**
   * 获取当前笔刷配置（返回副本）。
   */
  getBrush(): BrushConfig {
    return this.deepCopyBrush(this.currentBrush);
  }

  /**
   * 设置笔刷类型。
   * 马克笔自动设透明度 0.6，橡皮擦自动设不透明。
   */
  setBrushType(type: PenBrushType): void {
    this.currentBrush.type = type;
    if (type === PenBrushType.MARKER) {
      this.currentBrush.opacity = 0.6;
    } else if (type === PenBrushType.ERASER) {
      this.currentBrush.opacity = 1.0;
    }
  }

  /**
   * 设置笔刷颜色（ARGB 数值）。
   */
  setBrushColor(color: number): void {
    this.currentBrush.color = color;
  }

  /**
   * 设置笔刷粗细（1-50 像素）。
   */
  setBrushSize(size: number): void {
    let s = size;
    if (s < 1) {
      s = 1;
    }
    if (s > 50) {
      s = 50;
    }
    this.currentBrush.size = s;
  }

  // ─── 压感映射 ──────────────────────────────

  /**
   * 根据笔刷类型映射压感到线宽。
   * 使用当前笔刷的 size 作为 baseSize。
   *
   * 映射规则：
   *  - PEN:    baseSize * (0.3 + 0.7 * pressure)
   *  - PENCIL: baseSize * (0.5 + 0.5 * pressure)
   *  - MARKER: baseSize * (0.8 + 0.2 * pressure)
   *  - ERASER: baseSize * 1.5（无视压感）
   *
   * @param pressure 压感值 [0, 1]
   * @param brushType 笔刷类型
   * @returns 映射后的线宽（像素）
   */
  mapPressure(pressure: number, brushType: PenBrushType): number {
    return this.mapPressureWithBase(pressure, brushType, this.currentBrush.size);
  }

  /**
   * 根据笔刷类型和指定 baseSize 映射压感到线宽。
   * 用于渲染已存储的笔触（使用笔触创建时的 baseSize，而非当前笔刷设置）。
   *
   * @param pressure 压感值 [0, 1]
   * @param brushType 笔刷类型
   * @param baseSize 基础线宽
   * @returns 映射后的线宽（像素）
   */
  mapPressureWithBase(pressure: number, brushType: PenBrushType, baseSize: number): number {
    let p = pressure;
    if (p < 0) {
      p = 0;
    }
    if (p > 1) {
      p = 1;
    }
    // 模拟器降级：手写笔不可用时固定 1.0
    if (!this.penAvailable) {
      p = DEFAULT_PRESSURE;
    }

    if (brushType === PenBrushType.PEN) {
      return baseSize * (0.3 + 0.7 * p);
    } else if (brushType === PenBrushType.PENCIL) {
      return baseSize * (0.5 + 0.5 * p);
    } else if (brushType === PenBrushType.MARKER) {
      return baseSize * (0.8 + 0.2 * p);
    } else {
      // ERASER: 无视压感
      return baseSize * 1.5;
    }
  }

  /**
   * 根据笔刷类型和压感映射透明度。
   * 铅笔透明度随压感变化，马克笔固定 0.6。
   *
   * @param pressure 压感值 [0, 1]
   * @param brushType 笔刷类型
   * @returns 映射后的透明度 [0, 1]
   */
  mapOpacity(pressure: number, brushType: PenBrushType): number {
    let p = pressure;
    if (p < 0) {
      p = 0;
    }
    if (p > 1) {
      p = 1;
    }
    if (!this.penAvailable) {
      p = DEFAULT_PRESSURE;
    }

    if (brushType === PenBrushType.PENCIL) {
      // 铅笔透明度随压感变化
      return 0.3 + 0.5 * p;
    } else if (brushType === PenBrushType.MARKER) {
      // 马克笔固定透明度
      return 0.6;
    } else if (brushType === PenBrushType.ERASER) {
      return 1.0;
    } else {
      // PEN: 不透明
      return 1.0;
    }
  }

  /**
   * 获取有效压感。
   * 手写笔可用时返回原始压感，否则返回默认值 1.0。
   */
  getEffectivePressure(pressure: number): number {
    if (!this.penAvailable) {
      return DEFAULT_PRESSURE;
    }
    if (pressure < 0) {
      return 0;
    }
    if (pressure > 1) {
      return 1;
    }
    return pressure;
  }

  // ─── 手掌误触过滤 ──────────────────────────

  /**
   * 手掌误触检测。
   * 通过压感阈值判断：压感 < 0.1 且非手写笔判定为手掌。
   *
   * @param touchType 触摸来源类型（0=未知, 1=手指, 2=手写笔, 3=手掌）
   * @param pressure 压感值 [0, 1]
   * @returns true 表示是手掌误触（应过滤）
   */
  isPalmTouch(touchType: number, pressure: number): boolean {
    // touchType === 3 明确标识手掌
    if (touchType === 3) {
      return true;
    }
    // 压感低于阈值且非手写笔来源 → 手掌误触
    if (pressure < PALM_PRESSURE_THRESHOLD && touchType !== 2) {
      return true;
    }
    return false;
  }

  // ─── 笔触平滑 ──────────────────────────────

  /**
   * 笔触平滑：简单移动平均（窗口 3）。
   * 对每个中间点取前后相邻三点的平均值，减少抖动。
   * 首尾点保留原值以保持笔触起止精度。
   *
   * @param points 原始笔触点序列
   * @returns 平滑后的笔触点序列
   */
  smoothPoints(points: StrokePoint[]): StrokePoint[] {
    if (points.length < 3) {
      return this.copyPoints(points);
    }
    const result: StrokePoint[] = [];
    // 首点保留
    result.push(this.copyPoint(points[0]));
    // 中间点取移动平均
    for (let i = 1; i < points.length - 1; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const next = points[i + 1];
      const smoothed: StrokePoint = {
        x: (prev.x + curr.x + next.x) / 3,
        y: (prev.y + curr.y + next.y) / 3,
        pressure: (prev.pressure + curr.pressure + next.pressure) / 3,
        timestamp: curr.timestamp
      };
      result.push(smoothed);
    }
    // 末点保留
    result.push(this.copyPoint(points[points.length - 1]));
    return result;
  }

  // ─── 压感模拟 ──────────────────────────────

  /**
   * 基于触摸面积模拟压感。
   * 模拟器或无手写笔设备时，用触摸面积估算压感。
   * 面积越大压感越大（对数映射，缓和变化）。
   *
   * @param touchArea 触摸面积（平方像素）
   * @returns 模拟压感值 [0.2, 1.0]
   */
  simulatePressure(touchArea: number): number {
    if (touchArea <= 0) {
      return DEFAULT_PRESSURE;
    }
    // 对数映射：面积越大压感越大
    let simulated = Math.log(touchArea + 1) / Math.log(100);
    if (simulated < 0.2) {
      simulated = 0.2;
    }
    if (simulated > 1.0) {
      simulated = 1.0;
    }
    return simulated;
  }

  // ─── 笔触创建 ──────────────────────────────

  /**
   * 从点序列创建笔触数据。
   * 自动应用平滑处理，使用当前笔刷配置。
   *
   * @param points 原始笔触点序列
   * @returns 包含平滑后点的 StrokeData
   */
  createStroke(points: StrokePoint[]): StrokeData {
    this.strokeCounter++;
    const id = 'stroke_' + Date.now() + '_' + this.strokeCounter;
    const smoothed = this.smoothPoints(points);
    const stroke: StrokeData = {
      id: id,
      brushType: this.currentBrush.type,
      color: this.currentBrush.color,
      baseSize: this.currentBrush.size,
      opacity: this.currentBrush.opacity,
      points: smoothed
    };
    return stroke;
  }

  // ─── 预设获取 ──────────────────────────────

  /**
   * 获取笔刷预设列表（4 种笔刷）。
   */
  getBrushPresets(): BrushPresetItem[] {
    const result: BrushPresetItem[] = [];
    for (let i = 0; i < BRUSH_PRESETS.length; i++) {
      result.push({
        type: BRUSH_PRESETS[i].type,
        label: BRUSH_PRESETS[i].label,
        symbol: BRUSH_PRESETS[i].symbol
      });
    }
    return result;
  }

  /**
   * 获取预设颜色列表（6 种颜色）。
   */
  getPresetColors(): number[] {
    const result: number[] = [];
    for (let i = 0; i < PRESET_COLORS.length; i++) {
      result.push(PRESET_COLORS[i]);
    }
    return result;
  }

  // ─── 工具方法 ──────────────────────────────

  /**
   * 深拷贝笔刷配置（替代 spread 操作符）。
   */
  private deepCopyBrush(brush: BrushConfig): BrushConfig {
    return {
      type: brush.type,
      color: brush.color,
      size: brush.size,
      opacity: brush.opacity,
      pressureSensitive: brush.pressureSensitive
    };
  }

  /**
   * 深拷贝单个笔触点。
   */
  private copyPoint(p: StrokePoint): StrokePoint {
    return {
      x: p.x,
      y: p.y,
      pressure: p.pressure,
      timestamp: p.timestamp
    };
  }

  /**
   * 深拷贝笔触点数组。
   */
  private copyPoints(points: StrokePoint[]): StrokePoint[] {
    const result: StrokePoint[] = [];
    for (let i = 0; i < points.length; i++) {
      result.push(this.copyPoint(points[i]));
    }
    return result;
  }

  /**
   * 将 ARGB 颜色值转换为 CSS hex 字符串。
   * 用于 Canvas 2D 绘图（strokeStyle / fillStyle）。
   *
   * @param color ARGB 颜色值（如 0xFF0458A6）
   * @returns CSS hex 字符串（如 "#0458A6"）
   */
  static colorToHex(color: number): string {
    const r = (color >> 16) & 0xFF;
    const g = (color >> 8) & 0xFF;
    const b = color & 0xFF;
    const rs = r.toString(16);
    const gs = g.toString(16);
    const bs = b.toString(16);
    const rh = rs.length < 2 ? '0' + rs : rs;
    const gh = gs.length < 2 ? '0' + gs : gs;
    const bh = bs.length < 2 ? '0' + bs : bs;
    return '#' + rh + gh + bh;
  }

  /**
   * 将 ARGB 颜色值转换为带透明度的 CSS rgba 字符串。
   *
   * @param color ARGB 颜色值
   * @param opacity 透明度 [0, 1]
   * @returns CSS rgba 字符串（如 "rgba(4,88,166,0.6)"）
   */
  static colorToRgba(color: number, opacity: number): string {
    const r = (color >> 16) & 0xFF;
    const g = (color >> 8) & 0xFF;
    const b = color & 0xFF;
    let o = opacity;
    if (o < 0) {
      o = 0;
    }
    if (o > 1) {
      o = 1;
    }
    return 'rgba(' + r + ',' + g + ',' + b + ',' + o + ')';
  }
}
