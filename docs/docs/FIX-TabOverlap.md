# FIX-TabOverlap — 标签页重叠缺陷修复方案

- **状态**：方案已在**云端镜像仓库**实施（2026-09-26）；**本地工作区（F:\DevEcoStudioProjects）已于 2026-09-26 按本方案落地**，见下方核验注记
- **缺陷报告来源**：窦浩扬（模拟器测试发现：打开多个标签页出现重叠）
- **影响面**：仅 `TabBar.ets` 单文件（+119/−122，纯重构，无行为变更之外的副作用）
- **关联**：液态玻璃代码（GlassTheme 等）为同轮独立改动，与本修复解耦，见 §8

---

## 1. 现象

模拟器中打开/切换多个标签页时，页签出现**视觉重叠**：两个页签短暂或持续叠在同一槽位上，拖影残留在标签栏内。真机出现概率较低但不为零（取决于帧率）。

## 2. 复现路径

1. 打开 Callaite，连点「＋」新建 3 个以上标签（或 Ctrl+K 切换已有标签）
2. 观察标签栏：每次激活态切换的瞬间，旧激活页签与新激活页签重叠
3. 模拟器（低帧率、软件渲染）必现且窗口期更长；长标题页签因 140ms 渐变中宽度仍在测量，重叠更明显

## 3. 根因分析

### 3.1 直接原因：ForEach 键含激活态

原实现（修复前 TabBar.ets，标签滚动区）：

```typescript
ForEach(this.tabsList, (tab: TabInfo) => {
  this.TabItem(tab)
}, (tab: TabInfo) => tab.id + '_' + (tab.id === this.activeTabId ? 'a' : 'i'))
//                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//                                键随激活态变化
```

### 3.2 因果链（五步）

1. 每次切换标签，**恰好两个**页签的键同时变化：旧激活 `…_a → …_i`，新激活 `…_i → …_a`
2. ArkUI ForEach 的 diff 规则：键变化 = 「旧条目删除 + 新条目插入」，即使数量与位置都不变
3. 删除与插入发生在**同一渲染槽位**：旧组件进入销毁周期，新组件同帧挂载
4. 旧组件挂有 140ms 的 `stateStyles`/`shadow`/`animation` 过渡——销毁 teardown 并不立即终止已发射的动画帧，拆除窗口内**新旧两个页签组件短暂共存且位置重叠**
5. 模拟器帧率低（约 20–30fps），140ms 动画横跨 3–5 帧，重叠窗口被拉长为肉眼可见的「标签页叠影」

### 3.3 为什么代码会写成这样（历史动因）

`TabItem` 原为父组件的 `@Builder`。ArkUI 的 `@Builder` **不响应状态变化重渲染**——`activeTabId` 改变后 Builder 内的样式三元不会刷新。原作者（或过去某次修复）把激活态编进 ForEach 键，正是借用「键变化 → 强制重建」来强刷样式。**副作用就是重建引发的重叠**。这是典型的「用错误层的机制解决上一层的渲染问题」。

## 4. 修复设计

### 4.1 原则

样式刷新问题归还给状态系统（`@StorageLink`），ForEach 键回归**稳定身份标识**（`tab.id`），让组件树只做「复用 + 更新」，不做「销毁 + 重建」。

### 4.2 方案：TabItem 子组件化

```
TabBar（父）
 ├─ ForEach(tabsList, key = tab.id)      ← 键稳定，条目复用
 │   └─ TabItemView({ tab })             ← @Prop 接收数据
 │        ├─ @StorageLink('callaite_activeTabId')   ← 激活态自刷新
 │        └─ @State hovered / hoveredClose          ← hover 态组件内自持
 └─ （chevron 菜单 / ＋ / split 控件不变）
```

代码骨架（已实施）：

```typescript
@Component
struct TabItemView {
  @Prop tab: TabInfo = { id: '', page: '', pinned: false };
  @StorageLink('callaite_activeTabId') activeTabId: string = '';
  @State hovered: boolean = false;
  @State hoveredClose: boolean = false;

  private isActive(): boolean { return this.tab.id === this.activeTabId; }

  build() {
    Row({ space: 6 }) { /* 图标 + 标题 + 关闭按钮，样式三元全部读 isActive() */ }
    .stateStyles({ normal: { .backgroundColor(this.isActive() ? … : …) }, … })
    .onClick(() => { TabState.activateTab(this.tab.id); })
  }
}

// 父组件 ForEach：
ForEach(this.tabsList, (tab: TabInfo) => {
  TabItemView({ tab: tab })
}, (tab: TabInfo) => tab.id)   // ← 稳定键
```

### 4.3 顺带修复的三处衍生问题

| # | 问题 | 原因 | 修复 |
|---|---|---|---|
| 1 | hover 亮页签在标签切换后残留/丢失 | 原 hover 态存父组件 `hoveredTabId`，重建时 hover 事件丢失 | 下沉到 TabItemView 的 `@State hovered`，组件复用后 hover 稳定 |
| 2 | 长标题收缩路径不稳定（偶发不出现省略号） | `constraintSize({ maxWidth: 156 })` 缺 `minWidth: 0`，Row 收缩时文本节点宽度协商不收敛 | 补 `minWidth: 0`，强制文本参与收缩 |
| 3 | 父组件状态冗余 | `hoveredTabId` / `hoveredCloseId` / `activeTabId` 三个状态服务于子项样式 | 清理为 1 个（`hoveredAction` 属于工具按钮，保留） |

### 4.4 不变式（防止回归）

> **ForEach 键 = 数据身份，不携带任何 UI 态。**
> 任何「想让 ForEach 条目刷新样式」的需求，一律用子组件 + `@StorageLink`/`@Prop`/`@Watch` 实现，禁止改键。

建议后续给 code-linter 或评审 checklist 加这一条（`AllPagesPage` 的多选模式也有类似键设计，需一并检查——其 `toggleSelection` 入口当前不可达，风险低）。

## 5. 已实施改动摘要

| 文件 | 改动 |
|---|---|
| `TabBar.ets` | `TabItem` @Builder（约 130 行）→ `TabItemView` @Component（约 119 行）；ForEach 键去激活态；父组件清理 2 个状态；文本约束补 `minWidth: 0` |

注：同文件还含 3 处液态玻璃三元（`glassTheme ? … : …`），与本修复**逻辑独立**，见 §8 处置说明。

## 6. 验证清单

- [ ] 模拟器：连开 5+ 标签，连续快速切换 20 次——无叠影、无残影
- [ ] 模拟器：新建标签瞬间（键新增路径）无重叠
- [ ] 关闭标签（中间/末位/唯一）后相邻页签位置正确回缩
- [ ] 长标题（中文 20+ 字 / 英文 40+ 字符）省略号出现，页签不超 220vp
- [ ] 短标题（"日记"）页签不窄于 88vp
- [ ] hover 未激活页签出现关闭按钮，移开后消失；hover 态在切换标签后不残留
- [ ] 关闭按钮热区 ≥ 40vp（responseRegion 生效）
- [ ] 标签数超出栏宽时水平滚动正常，新建标签后自动可见（既有行为不回归）
- [ ] 键盘 Ctrl+K → 选择页面：单标签变多标签场景样式正确
- [ ] 真机（高帧率）走一遍上述核心项，确认无视觉异常

## 7. 回滚方案

单文件还原即可，无跨文件依赖：

```bash
git checkout -- entry/src/main/ets/components/layout/TabBar.ets
```

若回滚，缺陷复现路径（§2）即回归——不建议。若仅回退液态玻璃而保留本修复，见 §8。

## 8. 与液态玻璃改动的解耦说明

本轮工作区还包含液态玻璃主题（GlassTheme/AmbientBackground + 12 处接线）。**TabBar 修复不依赖它们**：TabItemView 内的 3 处 `glassTheme` 三元只影响玻璃主题开启时的配色，删掉三元即回到纯 surface 版本，TabItemView 结构与稳定键不受影响。

处置选项（待决策）：
- **A（推荐）**：回退液态玻璃全部代码，保留标签页修复——玻璃方向按新方案文档（SPEC-ImmersiveGlass）重做
- **B**：液态玻璃作为隐藏实验开关保留（默认关闭零回归），正式路线走 SPEC-ImmersiveGlass

---

*评审通过后本文档状态改为 Accepted 并随修复一起提交。*

---

## 9. 核验与落地注记（本地工作区，2026-09-26）

### 9.1 原「已实施」声明的适用性
§5 描述的改动**在本地工作区当时并不存在**（核验依据：`git status` 干净、HEAD 即基线提交；`grep TabItemView` 全仓 0 命中；`git log -S 'TabItemView' --all` 0 个提交；`TabBar.ets:198` 旧键仍在）。经与作者确认，该改动发生在**云端镜像仓库**，本文档未同步说明适用仓库。**已于本地按方案重新落地。**

### 9.2 本地落地内容（与方案的对应关系）
| 方案条目 | 本地实现 |
|---|---|
| TabItem @Builder → TabItemView @Component | ✅ `TabBar.ets` 末尾新增 `struct TabItemView`（含「为什么必须是组件」的完整因果注释） |
| ForEach 键去激活态 | ✅ `TabBar.ets`：`(tab) => tab.id + '_' + (active?'a':'i')` → `(tab) => tab.id` |
| 激活态自刷新 | ✅ TabItemView 内 `@StorageLink('callaite_activeTabId')` + `isActive()` |
| hover 态下沉 | ✅ `@State hovered` / `@State hoveredClose`；父组件 `hoveredTabId`/`hoveredCloseId` 已删除 |
| 文本约束补 `minWidth: 0` | ✅ `constraintSize({ maxWidth: 156, minWidth: 0 })` |
| **方案遗漏的第三处同形反模式** | ✅ **本次一并修复**：`TabOverviewSheet.ets` 的 ForEach 键同样含激活态（标签总览浮层内会闪叠影） |

编译：`BUILD SUCCESSFUL`，最终 `.hap` 已安装到模拟器（平板实例）。

### 9.3 验收状态（**未完成，如实登记**）
- ✅ 已通过：编译、装包、应用启动正常；代码层不变式成立（全仓已无携带 UI 态的 ForEach 键）。
- ❌ **未通过（方法问题，非代码问题）**：§6 清单的核心项「连开 5+ 标签、连续快速切换 20 次无叠影」**未取得证据**。
  - 自动化建标签受阻：点击标签栏右侧 `+`（2840,118）未弹出预期的新建对话框，三次尝试均未定位到选项，最终只存在 1 个标签。
  - 首次重叠检测**方法有缺陷**（假阳性）：用几何筛选取到的 4 个矩形实为**嵌套容器**（标签栏根 620–2880 ⊃ 滚动区 716–2699 ⊃ 页签 716–1123 ⊃ 页签内 Row 720–1119），并非并列页签；「6 处重叠」不成立，已作废。
  - **正确的检测法（下次执行）**：先按「同级 + 同 y 带 + 宽度落在 88–220vp」筛出**兄弟节点**（排除包含关系：若 A 的 x 区间包含 B 的 x 区间且 A 的 h 更大，则 A 是容器），再断言两两 x 区间不相交；同时补 3 张连续截图做叠影目视复核。
  - **可靠的建标签路径（下次执行）**：`chevron-down` 菜单（标签栏最左，约 x=632–712）→ 菜单内的新建项；或 `Ctrl+K` 选择页面（`TabState.newTab` 的实际入口）。
