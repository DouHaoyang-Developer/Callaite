import { BlockData } from '../core/models/Block';

/**
 * FenceOpenCache —— 块级编辑器（B 形态）的**块派生属性**：本块内容的第一行是否处在
 * 一个未闭合的 fenced code 围栏内。
 *
 * ─── 为什么必须有这一层 ───
 * 迁移前的 `LivePreviewHelper.buildSpansInternal` 是**文档级顺序扫描**：`offset` 从 0
 * 单调扫完整个 serde 段数组，并在此过程中维护一组**跨行存活**的状态
 * （`IntegralEditor.ets` 旧实现 `inCodeBlock` 在换行时**不复位** —— 与
 * `currentLineContext` / `headingLevel` / `inBold` / `inInlineCode` / `inHighlight`
 * 全部「换行即复位」形成对照）。
 *
 * 块级化之后，每个块各自持有独立的一段文本，**看不到前序块** ⇒ 若不补这一层，
 * 「一个块里开着围栏、代码继续写在后面几个块里」这种合法写法会立刻失效：
 * 后续块会被当成普通正文着色，行为与迁移前**不一致**。
 *
 * ─── 为什么是缓存的、且缓存键不含文本 ───
 * 设计文档（`S3-前置A与接入形态设计.md` §2.6）要求「按页面缓存 + 缓存键挂结构性版本号」，
 * 理由是文本输入不该引起重算（与 W10「每次按键不重算可见行」的性能前提一致）。
 * 本实现把「结构性版本号」取成**更精确且自校验的签名**：
 *
 *     signature = pageUuid + ':' + 可见行数 + ':' + 各可见行 uuid 的滚动 hash
 *
 * 于是：
 *   · 缩进 / 反缩进 / 删除 / 移动 / 折叠 —— 可见行序列变 ⇒ 签名变 ⇒ 自动失效 ✓
 *   · 文本输入 —— uuid 序列不变 ⇒ 签名不变 ⇒ **零重算** ✓（不必依赖调用方记得 bump）
 *   · 换页 / 换窗格 —— pageUuid 进签名 ⇒ 不会串页 ✓
 * 这里刻意**不比 `callaite_blocksVersion`**：版本号是「发生了一次结构性操作」的粗信号，
 * 而签名是「可见行序列长什么样」的精确描述 —— 后者不需要调用方配合，也不会因无关页面的
 * bump 而失效。
 *
 * ─── 已知边界（如实登记，不掩盖）───
 * 1. 签名只覆盖**可见行**。折叠起来的行不参与扫描，这是刻意的：被折叠的子孙既不可见、
 *    也不可能有块级编辑器实例。若用户折叠着一个「围栏开着」的子树、又在折叠点之后的
 *    顶层块里编辑，那个块的 `fenceOpen` 会按「折叠后可见序列」算 —— 与迁移前
 *    「按顶层块序列扫」也不完全等价。属**已知差异**，需要时再对齐。
 * 2. 只识别行首（允许前置空格）的 ``` / ~~~ 围栏，不识别 4 空格缩进式代码块 ——
 *    与 `MarkdownSegmenter` / `LivePreviewHelper` 的识别面保持一致（它们同样只认 ```）。
 */
export class FenceOpenCache {
  private static instance: FenceOpenCache | undefined;

  /** 上一次计算所用的签名 */
  private signature: string = '';
  /** 缓存结果：blockUuid → 本块第一行是否处在未闭合围栏内 */
  private openAt: Map<string, boolean> = new Map<string, boolean>();

  static getInstance(): FenceOpenCache {
    if (!FenceOpenCache.instance) {
      FenceOpenCache.instance = new FenceOpenCache();
    }
    return FenceOpenCache.instance;
  }

  /**
   * 返回「本块内容的第一行是否处在未闭合围栏内」。
   *
   * @param pageUuid 当前页面 uuid（进签名，防串页）
   * @param blocks   **可见行序列**（`WorkspaceService.getVisibleBlocks`，与 BlockList 同一实现）
   * @param blockUuid 目标块
   */
  isFenceOpenAt(pageUuid: string, blocks: BlockData[], blockUuid: string): boolean {
    const sig = FenceOpenCache.signatureOf(pageUuid, blocks);
    if (sig !== this.signature) {
      this.recompute(sig, blocks);
    }
    const v = this.openAt.get(blockUuid);
    return v === true;
  }

  /** 供诊断/探针读取：上一次计算的签名与条目数（不影响行为） */
  debugSignature(): string {
    return this.signature;
  }

  debugEntryCount(): number {
    return this.openAt.size;
  }

  /**
   * 顺序扫一遍可见行，为每个块记下「进入它之前的围栏状态」。
   *
   * 语义：一个块**自身**的 ``` 行只影响**它之后**的块，不影响它自己 ——
   * 因为块内重建时会从 `fenceOpenAt` 播种，再自己走一遍自己的围栏翻转
   * （见 `LivePreviewHelper.buildBlockSpans`），若这里把「自己开围栏」也算进去
   * 就会在块内造成一次多余的翻转。
   */
  private recompute(sig: string, blocks: BlockData[]): void {
    this.signature = sig;
    this.openAt.clear();
    let open = false;
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i];
      this.openAt.set(b.uuid, open);
      open = FenceOpenCache.foldFences(open, b.content);
    }
  }

  /**
   * 把一段文本里的围栏行折进「进入时状态」，返回「离开这段文本时的状态」。
   * 判据与 `LivePreviewHelper.buildSpansInternal` 的 `inCodeBlock` 翻转逐条对齐：
   * 只认行首（允许前置空格）的 ``` 或 ~~~。
   */
  private static foldFences(open: boolean, content: string): boolean {
    if (content === '') {
      return open;
    }
    const lines: string[] = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t.startsWith('```') || t.startsWith('~~~')) {
        open = !open;
      }
    }
    return open;
  }

  /** 可见行序列的内容签名（见类头「为什么是缓存的」） */
  private static signatureOf(pageUuid: string, blocks: BlockData[]): string {
    let h = 2166136261;
    for (let i = 0; i < blocks.length; i++) {
      const u = blocks[i].uuid;
      for (let j = 0; j < u.length; j++) {
        h = h ^ u.charCodeAt(j);
        // FNV-1a 的 32 位乘法（用移位相加规避 ArkTS 的位运算/大整数书写差异）
        h = (h + ((h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24))) >>> 0;
      }
      h = h ^ 0x2f;
      h = h >>> 0;
    }
    return pageUuid + ':' + blocks.length.toString() + ':' + h.toString();
  }
}
