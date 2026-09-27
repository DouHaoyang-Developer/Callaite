import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { FileService } from '../services/FileService';
import { PreferencesStore } from '../utils/PreferencesStore';

const DOMAIN = 0x0001;
const TAG = 'StatePersistence';

/** 旧版自研 JSON 持久化文件（仅用于一次性迁移，迁移后删除） */
const LEGACY_STATE_FILE = 'app_state.json';
/** 本持久化线专用的 preferences 实例名（含模块名，稳定性要求：改名即丢数据） */
const STORE_NAME = 'callaite_app_state';

/**
 * 需要跨进程存活的 AppStorage 键。
 * 注：PersistentStorage.persistProp 在部分 SDK 上冷启动恢复不可靠（写入正常、恢复丢失），
 * 因此仍由本类自管，只是把存储介质从「自研 JSON 文件」换成系统 preferences。
 */
const STATE_KEYS: string[] = [
  'callaite_onboarded',
  'callaite_themeMode',
  'callaite_language',
  'callaite_config',
  // 'callaite_currentPage', —— 启动页固定为 Home，不再恢复上次页面（见 AppState.initialize）
  'callaite_leftSidebarOpen',
  'callaite_rightSidebarOpen',
  'callaite_favorites',
  'callaite_recentPages',
  'callaite_rightSidebarBlocks'
];

/**
 * 旧 app_state.json 的字段形状（扁平 JSON 对象，值为各 AppStorage 键的 JSON 值）。
 *
 * 这里逐字段显式声明而不是用 Record/索引签名（ArkTS 禁用），
 * key → 字段的映射由 pickLegacyValue 完成，两者必须与 STATE_KEYS 保持同步。
 */
interface LegacyStateFile {
  callaite_onboarded?: Object;
  callaite_themeMode?: Object;
  callaite_language?: Object;
  callaite_config?: Object;
  callaite_leftSidebarOpen?: Object;
  callaite_rightSidebarOpen?: Object;
  callaite_favorites?: Object;
  callaite_recentPages?: Object;
  callaite_rightSidebarBlocks?: Object;
}

/**
 * StatePersistence — AppStorage 跨进程状态的持久化（存储介质：系统 preferences）。
 *
 * 存储布局：preferences 实例 `callaite_app_state`，**一个 AppStorage 键一个 preferences 键**，
 * 键名沿用原 AppStorage 键名（callaite_*），值统一以 JSON 文本存储。
 *
 * 值为什么用 JSON 文本：`preferences.getSync(key, defValue)` 在「已存值类型 ≠ defValue 类型」时
 * 会返回 defValue，而本线的 9 个键混有 boolean（onboarded / 两侧栏开合）与 string
 * （themeMode / language，以及本身就是 JSON 文本的 config / favorites / recentPages /
 * rightSidebarBlocks）。逐一按类型分支读取既脆弱、又会在未来新增键时静默读到默认值；
 * 统一 JSON 文本可保证「迁移后读到的值与迁移前逐字段一致」，并与旧实现的语义完全对齐。
 */
export class StatePersistence {
  /**
   * 从 preferences 恢复 AppStorage（必须在任何 UI 读取这些键之前调用）。
   *
   * 首次运行（preferences 中还没有本线任一键）且旧的 app_state.json 仍存在时，
   * 一次性把旧文件内容迁入 preferences 并删除旧文件。
   *
   * @returns true 表示恢复流程正常结束；false 表示 context 缺失或读写失败（已 hilog.error）。
   */
  static load(): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'load: context 未就绪，AppStorage 状态未恢复');
      return false;
    }
    let store: preferences.Preferences;
    try {
      store = PreferencesStore.open(ctx, STORE_NAME);
    } catch (e) {
      PreferencesStore.logError(STORE_NAME, 'getPreferencesSync', e as Object);
      return false;
    }
    try {
      // ─── 一次性迁移 ───
      // 触发条件：本线任一键都不存在（= 从未用 preferences 写过）+ 旧 JSON 文件存在。
      // hasSync 可能抛 BusinessError，因此放在本 try 内：查询失败即中止本次恢复（不写不删，保留旧文件）。
      let alreadyMigrated = false;
      for (let i = 0; i < STATE_KEYS.length; i++) {
        if (store.hasSync(STATE_KEYS[i])) {
          alreadyMigrated = true;
          break;
        }
      }
      if (!alreadyMigrated) {
        StatePersistence.migrateLegacyFile(store, ctx);
      }
      for (let i = 0; i < STATE_KEYS.length; i++) {
        const k = STATE_KEYS[i];
        if (!store.hasSync(k)) {
          continue;
        }
        const raw: string = store.getSync(k, '') as string;
        if (raw === '') {
          // 值不是 string（正常路径不会出现）：跳过并告警，不把默认值当成读到的值
          PreferencesStore.logWarn(STORE_NAME, 'key ' + k + ' 的存储值不是 JSON 文本，已跳过');
          continue;
        }
        const value: Object = JSON.parse(raw) as Object;
        if (value !== undefined && value !== null) {
          AppStorage.setOrCreate(k, value);
        }
      }
      return true;
    } catch (e) {
      PreferencesStore.logError(STORE_NAME, 'load', e as Object);
      return false;
    }
  }

  /**
   * 将当前 AppStorage 状态写入 preferences 并落盘。
   *
   * @returns true 表示已 flush 落盘；false 表示失败（已 hilog.error）。
   *          调用点（onBackground / 主题切换 / 引导完成等）可据此感知，不再静默丢弃。
   */
  static save(): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'save: context 未就绪，AppStorage 状态未持久化');
      return false;
    }
    try {
      const store: preferences.Preferences = PreferencesStore.open(ctx, STORE_NAME);
      for (let i = 0; i < STATE_KEYS.length; i++) {
        const k = STATE_KEYS[i];
        const v: Object | undefined = AppStorage.get<Object>(k);
        if (v === undefined) {
          continue;
        }
        store.putSync(k, JSON.stringify(v));
      }
      // XML 存储（默认）必须 flush 才真正落盘；onBackground 之后进程随时可能被回收，不能用异步 flush
      store.flushSync();
      return true;
    } catch (e) {
      PreferencesStore.logError(STORE_NAME, 'save', e as Object);
      return false;
    }
  }

  /**
   * 一次性迁移：读旧 app_state.json → 逐键写入 preferences → 删除旧文件。
   *
   * 旧文件的值本身就是 `JSON.stringify(AppStorage 值)`，因此原样搬入即可保证一致；
   * 只有读取/解析全部成功才删除旧文件，失败时保留以便下次启动重试（避免丢数据）。
   */
  private static migrateLegacyFile(store: preferences.Preferences, ctx: Context): void {
    const path = ctx.filesDir + '/' + LEGACY_STATE_FILE;
    let exists = false;
    try {
      exists = fs.accessSync(path);
    } catch (e) {
      PreferencesStore.logError(STORE_NAME, 'accessSync(legacy)', e as Object);
      return;
    }
    if (!exists) {
      return;
    }
    try {
      const raw = fs.readTextSync(path).trim();
      if (raw !== '') {
        const legacy = JSON.parse(raw) as LegacyStateFile;
        for (let i = 0; i < STATE_KEYS.length; i++) {
          const k = STATE_KEYS[i];
          const v: Object | undefined = StatePersistence.pickLegacyValue(legacy, k);
          if (v !== undefined && v !== null) {
            store.putSync(k, JSON.stringify(v));
          }
        }
        store.flushSync();
      }
      // 迁移完成：旧文件不再是真相来源，删除它
      fs.unlinkSync(path);
      PreferencesStore.logInfo(STORE_NAME, 'migrated legacy state, removed ' + path);
    } catch (e) {
      PreferencesStore.logError(STORE_NAME, 'migrate legacy state', e as Object);
    }
  }

  /** key → 旧文件字段 的显式映射（替代 ArkTS 不允许的索引签名访问）。 */
  private static pickLegacyValue(legacy: LegacyStateFile, key: string): Object | undefined {
    switch (key) {
      case 'callaite_onboarded': return legacy.callaite_onboarded;
      case 'callaite_themeMode': return legacy.callaite_themeMode;
      case 'callaite_language': return legacy.callaite_language;
      case 'callaite_config': return legacy.callaite_config;
      case 'callaite_leftSidebarOpen': return legacy.callaite_leftSidebarOpen;
      case 'callaite_rightSidebarOpen': return legacy.callaite_rightSidebarOpen;
      case 'callaite_favorites': return legacy.callaite_favorites;
      case 'callaite_recentPages': return legacy.callaite_recentPages;
      case 'callaite_rightSidebarBlocks': return legacy.callaite_rightSidebarBlocks;
      default: return undefined;
    }
  }
}
