/**
 * BlockListSlashSlot — Slash 命令菜单的**行内入口注册表**（U2.3）。
 *
 * ─── 解决什么问题 ───
 * Slash 菜单的行内常显入口在 `BlockView` 内部（每行一个按钮，见 BlockView 的
 * `SlashEntryButton`），而「哪一行被点」要交给宿主 `BlockList` 去开菜单 ——
 * 宿主才知道菜单该构造在哪一层、以及本列表属于哪个窗格。
 *
 * 但 `BlockView` 不能直接 import `BlockList`：
 *   ① `BlockList` 反过来 import 了 `BlockView`（它渲染每一行）⇒ 模块环；
 *   ② 为了一次方法调用引入环，代价与风险都不成比例。
 *
 * 因此本仓采用已在 `BlockDragLayer` 上验证过的形态：**注册表 + 函数类型回调**，
 * 把这条依赖放进一个双方都能引用的叶子模块（本文件）——
 *   · `BlockList` 在 `aboutToAppear` 登记自己的回调、`aboutToDisappear` 撤回；
 *   · `BlockView` 只调 `requestSlashMenu(listId, blockUuid)`，从不提及 `BlockList`。
 * 与 `BlockView.onRowGrab`（@Prop 传参）是同一手法，差别只在**必须走注册表**：
 * 行会被 `LazyForEach` 复用、且入口按钮在任意深度的行里，传参型 @Prop 会在
 * 「键未变」时收不到新值（见 AGENTS §7 陷阱 15），结构化通道更可靠。
 *
 * ─── 幂等与生命周期 ───
 *   · 同 listId 重复登记 = 覆盖（不叠加）；
 *   · 撤回按「同一函数引用」判等 ⇒ 旧实例卸载不会误删新实例的登记；
 *   · 查不到宿主（未挂载/已卸载/分屏的另一窗格未构造）时**静默忽略**，
 *     与「这一行没有入口」等价，不抛错。
 */

/** 菜单打开请求的接收端（由 BlockList 实例在挂载时登记）。 */
export type SlashMenuRequestHandler = (blockUuid: string) => void;

/** listId → 宿主 BlockList 的打开回调。 */
const slashMenuSlots: Map<string, SlashMenuRequestHandler> = new Map<string, SlashMenuRequestHandler>();

/** 由 BlockList 自身在 aboutToAppear 调用（行内入口不直接调用）。 */
export function bindSlashMenuSlot(listId: string, handler: SlashMenuRequestHandler): void {
  if (listId === '') {
    return;
  }
  slashMenuSlots.set(listId, handler);
}

/** 由 BlockList 自身在 aboutToDisappear 调用（按同一函数引用撤回）。 */
export function unbindSlashMenuSlot(listId: string, handler: SlashMenuRequestHandler): void {
  const current = slashMenuSlots.get(listId);
  if (current === handler) {
    slashMenuSlots.delete(listId);
  }
}

/**
 * 行内入口 → 宿主：打开 Slash 菜单，目标块 = 本行。
 * 查不到宿主时静默忽略（不抛错、不改任何状态）。
 */
export function requestSlashMenu(listId: string, blockUuid: string): void {
  if (listId === '' || blockUuid === '') {
    return;
  }
  const handler = slashMenuSlots.get(listId);
  if (handler !== undefined) {
    handler(blockUuid);
  }
}

/** 当前已登记的宿主数量（诊断用，不参与任何 UI）。 */
export function slashMenuSlotCount(): number {
  return slashMenuSlots.size;
}
