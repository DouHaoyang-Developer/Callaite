import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, promptAction } from '@kit.ArkUI';
import { WorkspaceService } from '../services/WorkspaceService';
import { JournalService } from '../services/JournalService';
import { AppState } from '../state/AppState';
import { StatePersistence } from '../state/StatePersistence';
import { FileService } from '../services/FileService';

const DOMAIN = 0x0002;
const LOG_TAG = 'ShareReceive';

/**
 * ShareReceiveAbility — 分享接收 Ability。
 *
 * 接收其他应用分享的文本/URL，自动创建 Block 到今天的日志页。
 * - 普通文本：直接作为 Block content
 * - URL（http/https）：自动转为 [url] 格式作为 Block content
 *
 * 对应 Callaite shareability/ShareReceiveAbility.ets。
 */
export default class ShareReceiveAbility extends UIAbility {
  private pendingSharedText: string = '';
  /** 窗口是否已就绪（`loadContent` 回调已返回）—— 决定 `onNewWant` 走哪条处理时机 */
  private stageReady: boolean = false;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, LOG_TAG, 'Ability onCreate');

    // 初始化文件服务上下文与 Graph（冷启动时确保 WorkspaceService 可用）
    // ⚠️ 只在冷启动做（保持原实现的位置与次数 ✗）：`FileService.initGraph()` 会
    //   `indexStore.clear()` 后**全量重读 Graph**（`DataStore.loadGraph`），
    //   放进「每次分享都跑」的公共路径会变成**每次分享重载整个 vault** ✗。
    FileService.setContext(this.context);
    // ★ W13（修 `W12-A`）：**恢复跨进程状态，且必须在 `loadContent` 之前完成**。
    //
    // 与 `EntryAbility.onCreate`（`EntryAbility.ets:33`）**调用同一个源** —— 即
    // `StatePersistence.load()` 这个既有的、Ability 无关的共用恢复入口 ⇒ **没有第二份恢复代码** ✓。
    //
    // 为什么不能省（`W12-A` 的根因）：`pages/Index.ets:7` 的
    // `@StorageLink('callaite_onboarded') onboarded: boolean = false` 在**键不存在**时
    // 会就地建键并取 `false` ⇒ `Index.ets:11` 走 `OnboardingPage()` 分支 ✗。
    // 而全仓**只有 `EntryAbility.onCreate` 调过 `load()`**（`git grep StatePersistence.load`
    // 仅 1 处 ✓）⇒ `AppState.initialize()` **根本不写这个键**（它只设 config/language/
    // themeMode/侧栏/路由等默认值 ✓）⇒ 分享窗口单独冷启动时该键**从未被建立** ⇒ 渲染 onboarding ✗。
    //
    // 为什么必须放在这里（本 Ability 的最早时机 ✓）：本方法的返回早于
    // `onWindowStageCreate` ⇒ 早于那里的 `windowStage.loadContent('pages/Index')` ✓。
    // 恢复若晚于 `loadContent`，`Index` 已经按 `false` 选过分支了 ✗（这是本条的要害 ✓）。
    // 位置紧跟 `setContext`（`load()` 需要 `FileService.getContext()` ✓），
    // 与 `EntryAbility` 的 `setContext` → `load()` 顺序**逐字同源** ✓。
    //
    // ⚠️ 刻意**不**在这里做 `FileService.initGraph()` 之外的任何初始化 ——
    //   `initGraph` 保持**只在冷启动跑一次**（见上方注释 ✗），
    //   本行也不引入 `TabState.initialize()`（那属另一类语义，见 W13 文档 §7/§8）。
    StatePersistence.load();

    FileService.initGraph();

    // 提取分享内容并暂存（在窗口创建后处理以支持 toast 提示）
    this.acceptShareText(want, 'onCreate');
  }

  /**
   * ★ W12（修 `W11-A`）：**已启动实例再次被拉起时的入口**。
   *
   * 本 Ability 的 `launchType` 是**默认的 `singleton`**（`module.json5` 未配置该字段 ⇒
   * 取默认值；SDK `LaunchType.SINGLETON = 0`，设备 hilog 实测 `launchType:0` 一致 ✓）。
   * `singleton` 的契约是：**首次启动走 `onCreate`，此后每次拉起都走 `onNewWant`** ✗✓
   * ⇒ 不实现本回调 ⇒ 第二次及以后的分享内容**没有任何代码读取那个 `Want`** ⇒ **静默丢弃** ✗。
   *
   * 与「改用 `launchType: multiton`」的分工说明见 W12 文档 §3：本窗口**选 `onNewWant`** ——
   * ① 它就是这套生命周期的**约定入口**，且设备 hilog 已证明系统**本来就在调它**
   *    （`[JUA2177] JsUIAbility call js, name: onNewWant` ✓）；改 `launchType` 是绕过约定，
   *    还会每次分享**新建一个窗口/任务**（实测一次启动即产生新窗口 ✓）；
   * ② 改动面最小：只动 1 个 `.ets`，**不碰 `module.json5`** ✓。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, LOG_TAG, 'Ability onNewWant');
    // 与 `onCreate` **共用同一条处理路径**（`acceptShareText` → `processPendingShare`）✗✓
    // ⚠️ 这里**不**重复 `FileService.initGraph()`：Graph 在冷启动已加载，
    //    且 `initGraph` 是全量重载（见 `onCreate` 注释），每次分享跑一次会重载整个 vault ✗。
    this.acceptShareText(want, 'onNewWant');
    if (this.stageReady) {
      // 窗口已就绪 ⇒ 本次分享立刻就地处理
      this.processPendingShare();
    } else {
      // 窗口还没起来（`loadContent` 回调未返回）⇒ 先暂存在 pendingSharedText，
      // 等 `onWindowStageCreate` 的回调里统一处理 ⇒ **内容不丢** ✓
      hilog.info(DOMAIN, LOG_TAG, 'Window stage not ready, share deferred to onWindowStageCreate');
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 初始化全局状态（确保 AppStorage 键存在，与 EntryAbility 一致）
    AppState.initialize();

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, LOG_TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, LOG_TAG, 'Content loaded');
      this.stageReady = true;
      // 处理暂存内容：① `onCreate` 那次分享 ② 窗口就绪前到达的 `onNewWant` 分享（若有）
      this.processPendingShare();
    });
  }

  /**
   * 公共处理路径（`onCreate` 与 `onNewWant` **共用**）✗✓ —— 避免两份逻辑分叉。
   *
   * 只做「把该 `Want` 的分享内容追加到暂存串」这一件事；
   * 文件服务初始化**不在这里**（`initGraph` 是全量重载，只应在冷启动做，见 `onCreate`）。
   */
  private acceptShareText(want: Want, source: string): void {
    const text = this.extractSharedText(want);
    if (text.length === 0) {
      hilog.warn(DOMAIN, LOG_TAG, 'No shared text found in want (%{public}s)', source);
      return;
    }
    // ⚠️ 这里**只追加、绝不因「与上次相同」而跳过** ✗ —— 见 processPendingShare 的语义说明
    this.pendingSharedText += text;
    hilog.info(DOMAIN, LOG_TAG, 'Accepted share (%{public}s, len=%{public}d)', source, text.length);
  }

  /**
   * 处理暂存的分享内容：根据类型调用对应处理器并显示 toast。
   *
   * ⚠️ **语义决策（W12 拍板 ✗✓）**：**每一次分享都落一个块，不做内容去重** ✗。
   *
   * 本缺陷登记名是 `W11-A`「去重」，但**真正的缺陷是「第二次静默丢弃」** ——
   * 「同一份内容分享两次应该只留一个块」是**应用的猜测**，而「用户点了两次」是**用户的动作** ✗✓。
   * 判据：用户连点两次分享，期望的是「两次都被记下来」；
   * 而**静默丢弃是应用替用户做了决定** ✗ —— 这与本会话「数据丢失 > 一切」的口径一致
   * （同 W2 静默丢块 / W7 OOM 崩溃 ✓）。
   * 另：本仓其余插入路径（`insert-block` / 导入 / 插件 `insertTodayBlock`）**都不按内容去重**
   * ⇒ 分享路径单独去重会造成**同一操作在不同入口下语义不一致** ✗。
   * ⇒ 若将来真的需要去重，应做成**用户可见且可撤销**的能力（例：toast 提示「重复内容，已跳过」），
   *   而不是在这里静默比对字符串 ✗。
   */
  private processPendingShare(): void {
    if (this.pendingSharedText.length === 0) {
      return;
    }
    const text = this.pendingSharedText;
    this.pendingSharedText = '';

    let success = false;
    try {
      if (this.isUrl(text)) {
        this.handleSharedUrl(text);
      } else {
        this.handleSharedText(text);
      }
      success = true;
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to handle share: %{public}s', JSON.stringify(e));
    }

    // 显示 toast 提示（成功/失败）
    const message = success ? '已添加到今日日志' : '分享接收失败';
    this.showToast(message);
  }

  /**
   * 处理分享的文本内容：在今日日志页创建 Block。
   * @param text 分享的文本
   */
  private handleSharedText(text: string): void {
    const ws = WorkspaceService.getInstance();
    const today = JournalService.ensureTodayJournal();
    const page = ws.getPageByName(today);
    if (!page) {
      hilog.warn(DOMAIN, LOG_TAG, 'Today journal page not found: %{public}s', today);
      return;
    }
    const r = ws.executeOp({
      type: 'insert-block',
      content: text,
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: '',
      level: 0
    });
    ws.savePage(page.uuid);
    // ★ W11（修 `W8-A`）：新增块是结构性变更 ⇒ 必须通知视图重算可见行序列（陷阱 22 / 15）。
    //   补在**本 Ability 内**的理由：这条路径**没有 UI 调用方** —— 触发者是系统分享框架
    //   （`onCreate(want)` → `onWindowStageCreate` → `processPendingShare`），
    //   本 Ability 自己就是调用链顶 ⇒ 按陷阱 22 的判据（「这条路径上究竟有没有一个地方
    //   bump」），只能由它自己补，`WorkspaceService`/`OutlinerEngine` **刻意不 bump** ✓。
    //   同进程时 AppStorage 的 `callaite_blocksVersion` 与主窗口共享；若被系统放进
    //   另一进程，本行只在该进程内建键，无副作用（**不可自证项**，见 W11 文档 §11）。
    if (r.success) {
      AppState.bumpBlocksVersion();
    }
    // 跳转到今日日志页
    AppState.setCurrentPage(today);
    hilog.info(DOMAIN, LOG_TAG, 'Shared text added to journal');
  }

  /**
   * 处理分享的 URL：转为 [url] 格式在今日日志页创建 Block。
   * @param url 分享的 URL
   */
  private handleSharedUrl(url: string): void {
    const ws = WorkspaceService.getInstance();
    const today = JournalService.ensureTodayJournal();
    const page = ws.getPageByName(today);
    if (!page) {
      hilog.warn(DOMAIN, LOG_TAG, 'Today journal page not found: %{public}s', today);
      return;
    }
    const r = ws.executeOp({
      type: 'insert-block',
      content: '[' + url + ']',
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: '',
      level: 0
    });
    ws.savePage(page.uuid);
    // ★ W11（修 `W8-A`）：同 `handleSharedText`（理由见那里的注释）
    if (r.success) {
      AppState.bumpBlocksVersion();
    }
    AppState.setCurrentPage(today);
    hilog.info(DOMAIN, LOG_TAG, 'Shared URL added to journal');
  }

  /**
   * 从 Want 中提取分享的文本内容。
   * 兼容多种分享键名（系统标准键 + 通用键）。
   */
  private extractSharedText(want: Want): string {
    if (want.parameters === undefined || want.parameters === null) {
      return '';
    }

    // 尝试 ohos.extra.param.key.content（HarmonyOS 系统分享标准键名）
    const content = want.parameters['ohos.extra.param.key.content'];
    if (content !== undefined && content !== null && typeof content === 'string' && content.length > 0) {
      return content;
    }

    // 尝试 shareText
    const shareText = want.parameters['shareText'];
    if (shareText !== undefined && shareText !== null && typeof shareText === 'string' && shareText.length > 0) {
      return shareText;
    }

    // 尝试 sharedText
    const sharedText = want.parameters['sharedText'];
    if (sharedText !== undefined && sharedText !== null && typeof sharedText === 'string' && sharedText.length > 0) {
      return sharedText;
    }

    // 尝试 content（通用键名）
    const plainText = want.parameters['content'];
    if (plainText !== undefined && plainText !== null && typeof plainText === 'string' && plainText.length > 0) {
      return plainText;
    }

    return '';
  }

  /**
   * 判断字符串是否为 URL（http/https 协议）。
   */
  private isUrl(text: string): boolean {
    if (text.length < 8) {
      return false;
    }
    const lower = text.toLowerCase();
    if (lower.startsWith('https://')) {
      return true;
    }
    if (lower.startsWith('http://')) {
      return true;
    }
    return false;
  }

  /**
   * 显示 toast 提示（showToast 已弃用，改用 openToast）。
   */
  private showToast(message: string): void {
    promptAction.openToast({
      message: message
    }).catch(() => {
      hilog.warn(DOMAIN, LOG_TAG, 'showToast failed');
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, LOG_TAG, 'Ability onDestroy');
  }
}
