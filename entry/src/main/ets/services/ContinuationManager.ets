import { Want } from '@kit.AbilityKit';
import { AppState } from '../state/AppState';

/**
 * 跨设备流转状态结构 — 序列化到 want.parameters 的数据载体。
 */
interface ContinuationState {
  /** 当前页面名（如 "Journal"、页面标题等） */
  currentPage: string;
  /** 正在编辑的 Block UUID，空字符串表示无编辑 */
  editingBlockUuid: string;
  /** 当前页面滚动偏移量（px） */
  scrollOffset: number;
  /** 左侧栏是否展开 */
  leftSidebarOpen: boolean;
  /** 右侧栏是否展开 */
  rightSidebarOpen: boolean;
}

/**
 * AppStorage 键名定义 — editingBlockUuid / scrollOffset 不在 AppState 中，独立维护。
 */
interface ContinuationStorageKeys {
  editingBlockUuid: string;
  scrollOffset: string;
}

const CONTINUATION_KEYS: ContinuationStorageKeys = {
  editingBlockUuid: 'callaite_editingBlockUuid',
  scrollOffset: 'callaite_scrollOffset'
};

/** want.parameters 中存放序列化状态的键名 */
const CONTINUATION_PARAM_KEY = 'continuationState';

/** 日志标签 */
const LOG_TAG = 'ContinuationManager';

/**
 * 管理跨设备状态迁移（多端流转）。
 *
 * 流转流程：
 * 1. 源端 onContinue → saveToContinue(want) 将状态写入 want.parameters
 * 2. 目标端 onRestoreData(want) → restoreFromContinue(want) 从 want.parameters 恢复
 *
 * 序列化字段：currentPage / editingBlockUuid / scrollOffset /
 *             leftSidebarOpen / rightSidebarOpen
 *
 * 其中 currentPage / leftSidebarOpen / rightSidebarOpen 通过 AppState 读写；
 * editingBlockUuid / scrollOffset 通过 AppStorage 独立键读写（AppState 未暴露相关方法）。
 */
export class ContinuationManager {

  // ─── editingBlockUuid（AppStorage 独立维护） ───

  /**
   * 获取当前正在编辑的 Block UUID。
   * @returns Block UUID，未编辑时返回空字符串
   */
  static getEditingBlockUuid(): string {
    return AppStorage.get<string>(CONTINUATION_KEYS.editingBlockUuid) ?? '';
  }

  /**
   * 设置当前正在编辑的 Block UUID。
   * @param uuid Block UUID，传入空字符串表示退出编辑
   */
  static setEditingBlockUuid(uuid: string): void {
    AppStorage.setOrCreate(CONTINUATION_KEYS.editingBlockUuid, uuid);
  }

  // ─── scrollOffset（AppStorage 独立维护） ───

  /**
   * 获取当前页面的滚动偏移量。
   * @returns 滚动偏移量（px），默认 0
   */
  static getScrollOffset(): number {
    return AppStorage.get<number>(CONTINUATION_KEYS.scrollOffset) ?? 0;
  }

  /**
   * 设置当前页面的滚动偏移量。
   * @param offset 滚动偏移量（px）
   */
  static setScrollOffset(offset: number): void {
    AppStorage.setOrCreate(CONTINUATION_KEYS.scrollOffset, offset);
  }

  // ─── 序列化 / 反序列化 ───

  /**
   * 从 AppState 及 AppStorage 读取当前状态，序列化为 JSON 字符串。
   * @returns JSON 格式的 ContinuationState 字符串
   */
  static serialize(): string {
    const state: ContinuationState = {
      currentPage: AppState.getCurrentPage(),
      editingBlockUuid: ContinuationManager.getEditingBlockUuid(),
      scrollOffset: ContinuationManager.getScrollOffset(),
      leftSidebarOpen: AppState.isLeftSidebarOpen(),
      rightSidebarOpen: AppState.isRightSidebarOpen()
    };
    return JSON.stringify(state);
  }

  /**
   * 解析 JSON 字符串并恢复到 AppState 及 AppStorage。
   * 解析失败时静默忽略，不抛出异常。
   * @param json ContinuationState 的 JSON 字符串
   */
  static deserialize(json: string): void {
    if (json === undefined || json === null || json.length === 0) {
      console.warn(`[${LOG_TAG}] deserialize: empty json input`);
      return;
    }
    let state: ContinuationState;
    try {
      state = JSON.parse(json) as ContinuationState;
    } catch (e) {
      console.error(`[${LOG_TAG}] deserialize: JSON.parse failed`, e);
      return;
    }
    if (state === undefined || state === null) {
      console.warn(`[${LOG_TAG}] deserialize: parsed state is null`);
      return;
    }
    // 逐字段恢复（带类型校验，避免脏数据破坏状态）
    if (typeof state.currentPage === 'string' && state.currentPage.length > 0) {
      AppState.setCurrentPage(state.currentPage);
    }
    if (typeof state.editingBlockUuid === 'string') {
      ContinuationManager.setEditingBlockUuid(state.editingBlockUuid);
    }
    if (typeof state.scrollOffset === 'number' && state.scrollOffset === state.scrollOffset) {
      ContinuationManager.setScrollOffset(state.scrollOffset);
    }
    if (typeof state.leftSidebarOpen === 'boolean') {
      AppState.setLeftSidebarOpen(state.leftSidebarOpen);
    }
    if (typeof state.rightSidebarOpen === 'boolean') {
      AppState.setRightSidebarOpen(state.rightSidebarOpen);
    }
    console.info(`[${LOG_TAG}] deserialize: state restored — ${ContinuationManager.summary()}`);
  }

  // ─── Want 参数读写 ───

  /**
   * 将当前状态序列化后写入 want.parameters。
   * 用于源端 onContinue 回调。
   * @param want 携带 parameters 的 Want 对象
   */
  static saveToContinue(want: Want): void {
    const json = ContinuationManager.serialize();
    if (want.parameters === undefined || want.parameters === null) {
      console.warn(`[${LOG_TAG}] saveToContinue: want.parameters is null, skip`);
      return;
    }
    want.parameters[CONTINUATION_PARAM_KEY] = json;
    console.info(`[${LOG_TAG}] saveToContinue: state saved (${json.length} bytes) — ${ContinuationManager.summary()}`);
  }

  /**
   * 从 want.parameters 读取并恢复状态。
   * 用于目标端 onRestoreData 回调。
   * @param want 携带 parameters 的 Want 对象
   */
  static restoreFromContinue(want: Want): void {
    if (want.parameters === undefined || want.parameters === null) {
      console.warn(`[${LOG_TAG}] restoreFromContinue: want.parameters is null, skip`);
      return;
    }
    const raw = want.parameters[CONTINUATION_PARAM_KEY];
    if (raw === undefined || raw === null) {
      console.warn(`[${LOG_TAG}] restoreFromContinue: no continuation data in want`);
      return;
    }
    if (typeof raw === 'string') {
      ContinuationManager.deserialize(raw);
    } else {
      console.warn(`[${LOG_TAG}] restoreFromContinue: unexpected value type, skip`);
    }
  }

  /**
   * 检查 Want 中是否携带流转状态数据。
   * @param want 待检查的 Want 对象
   * @returns true 表示包含可恢复的流转数据
   */
  static hasContinuationData(want: Want): boolean {
    if (want.parameters === undefined || want.parameters === null) {
      return false;
    }
    const raw = want.parameters[CONTINUATION_PARAM_KEY];
    if (raw === undefined || raw === null) {
      return false;
    }
    return typeof raw === 'string';
  }

  // ─── 便捷方法 ───

  /**
   * 生成当前状态的摘要字符串（用于日志/调试）。
   * @returns 形如 "page=Journal, edit=abc-123, scroll=0, L=true, R=false"
   */
  static summary(): string {
    const currentPage = AppState.getCurrentPage();
    const editingBlockUuid = ContinuationManager.getEditingBlockUuid();
    const scrollOffset = ContinuationManager.getScrollOffset();
    const leftSidebarOpen = AppState.isLeftSidebarOpen();
    const rightSidebarOpen = AppState.isRightSidebarOpen();
    return `page=${currentPage}, edit=${editingBlockUuid}, scroll=${scrollOffset}, L=${leftSidebarOpen}, R=${rightSidebarOpen}`;
  }

  /**
   * 清除编辑状态和滚动位置（不影响页面/侧边栏）。
   * 通常在保存笔记或切换页面后调用。
   */
  static clearEditorState(): void {
    ContinuationManager.setEditingBlockUuid('');
    ContinuationManager.setScrollOffset(0);
  }

  /**
   * 返回默认的 ContinuationState（用于初始化或回退）。
   * @returns 默认状态对象
   */
  static getDefaultState(): ContinuationState {
    return {
      currentPage: 'Journal',
      editingBlockUuid: '',
      scrollOffset: 0,
      leftSidebarOpen: true,
      rightSidebarOpen: false
    };
  }
}
