# Callaite 多设备 UI 全量走查与修复报告

**日期**：2026-09-18
**范围**：phone / tablet / 2in1 三类设备，以 UI 为主的全量走查、修复与复测
**构建**：`bash F:/DevEcoStudioProjects/build_callaite.sh debug`（五轮迭代全部 `BUILD SUCCESSFUL`）
**改动**：25 个源文件（含 1 个新增）
**结论**：**发现并修复 10 类 UI 问题，其中 1 个 P0 级全局配色缺陷；三设备最终审计全部通过，功能无回归**

---

## 一、概要

本轮走查共发现 **10 类问题**，按严重度分布：

| 级别 | 数量 | 代表问题 |
|---|---|---|
| P0 | 1 | 颜色令牌 ARGB 误写 → 全应用「强调色」渲染为亮绿色 |
| P1 | 4 | 侧栏内容垂直居中留大片空白；内部路由名泄漏为英文标题；宽屏通栏拉伸；2in1 窗口缩放断点失效 |
| P2 | 5 | 交互三态与动效几乎缺失；固定宽度溢出风险；命中区不一致；菜单结构冗余；Toggle 配色不统一 |

**三设备最终审计结果（越界 / 零尺寸 / 重叠 / 内容溢出 / 文字截断 / 小命中区）**：

| 设备 | 分辨率 | 布局节点 | 越界 | 零尺寸 | 重叠 | 溢出父容器 | 截断 | 小命中区 |
|---|---|---|---|---|---|---|---|---|
| phone (Pura 90 Pro) | 1256×2760 | 75–135 | 0 | 0 | 0 | 0 | 0 | 0 |
| tablet (MatePad Pro 13) | 2880×1920 | 100–269 | 0 | 0 | 0 | 0 | 0 | 0 |
| 2in1 (MateBook Pro) | 3120×2080 | 90–390 | 0 | 0 | 0 | 0 | 0 | 0 |

---

## 二、走查方法

1. **构建 + 三设备并行部署**：`deploy_all.sh` 就地升级（保留应用数据），避免重复引导
2. **逐屏采集**：`uitest dumpLayout` 取结构化布局树 + `uitest screenCap` 取像素截图
3. **自动审计**：自建 `ui_audit.py` 做 8 项检测（越界 / 零尺寸 / 同层重叠 / 文本左边界分布 / 命中区尺寸 / 同级间距分布 / 文本截断 / 可点击元素清单）
4. **视觉复核**：Pillow 对截图做区域裁切 + 2–6 倍 LANCZOS 放大，逐图标、逐文本核对清晰度与对齐
5. **交互实测**：`uitest uiInput click/drag` 驱动，逐项操作并核对 PID 存活与 hilog

> 工具脚本位于 `F:/DevEcoStudioProjects/uiwalk/`：`ui_audit.py`、`deploy_all.sh`、`walk.sh`、`sweep.sh`

---

## 三、逐设备发现的问题、修复方案与改动文件

### 3.1 phone（Pura 90 Pro · 1256×2760 · density 3.5 · 移动壳）

| # | 问题现象 | 根因 | 修复方案 | 改动文件 |
|---|---|---|---|---|
| P-1 | 顶部标题显示英文 **"Settings"**，而页面正文标题是「设置」，同一屏两种语言 | `MobileHeader` 直接渲染 `currentPage` 内部路由名 | 新增 `pageTitle()` 统一把内部路由映射为本地化标题 | `utils/PageTitle.ets`（新增）、`components/layout/MobileHeader.ets`、`utils/i18n.ets` |
| P-2 | 引导页副标题「兼具 Obsidian 与 Logseq 亮点的鸿蒙知识库」在居中容器内左对齐换行，断行位置尴尬（"鸿蒙知 / 识库"） | `Text` 未设 `textAlign`，多行按起始边对齐 | 副标题与各步骤说明统一 `.textAlign(TextAlign.Center)` + `maxLines` | `components/onboarding/OnboardingPage.ets` |
| P-3 | 引导页「选择目录」按钮点击后仅切换一行提示文案，无实际功能，属误导性交互 | 目录选择尚未实现 | 移除此按钮，改为直接陈述「当前使用应用默认目录，可在设置中切换」 | `components/onboarding/OnboardingPage.ets` |
| P-4 | 底部玻璃胶囊栏固定宽 336vp，在 ≤360vp 窄屏（折叠屏外屏）有溢出风险 | 硬编码 `width(336)` | 改 `width('92%')` + `constraintSize({ maxWidth: 336 })` | `components/layout/MobileBottomBar.ets` |
| P-5 | 顶栏标题固定 `maxWidth 200`，宽屏浪费空间、窄屏易触发省略号 | 硬编码约束 | 改 `layoutWeight(1)` + `textAlign(Center)` + 左右 padding，自适应剩余宽度 | `components/layout/MobileHeader.ets` |
| P-6 | 侧栏「收藏夹 / 最近」空态文案**居中**显示，与列表项左对齐不一致 | `Column` 默认 `alignItems` 为 `Center`，`EmptyHint` 的 Text 未占满宽度 | `EmptyHint` 加 `.width('100%').textAlign(TextAlign.Start)` | `components/sidebar/LeftSidebar.ets` |
| P-7 | 侧栏打开后，图标行与「日志」之间出现**约 157vp 的大片空白** | ArkUI `Scroll` 默认 `align = Center`，内容不足一屏时被垂直居中 | `Scroll` 加 `.align(Alignment.TopStart)`；内部 Column 显式 `alignItems(Start)` | `components/sidebar/LeftSidebar.ets` |
| P-8 | 侧栏激活项「日志」呈**亮绿色**，与紫色主题冲突 | 见 §4.1（ARGB） | 修正色值令牌 | `resources/base/element/color.json`、`resources/dark/element/color.json` |
| P-9 | 「更多」菜单 9 项平铺 + 8 条分割线，视觉噪声大、难以扫读 | 结构未分组 | 重构为「内容 / 视图 / 数据与系统」三组，仅组间分割线 | `components/layout/MobileMenuSheet.ets`、`utils/i18n.ets` |
| P-10 | 侧栏页码项 `PageLink` 的 `onClick` 仅挂在文字上，点击行内空白无效；导航项 `NavRow` 却整行可点，命中不一致 | 事件挂载层级不一致 | `onClick` 上移至整行 | `components/sidebar/LeftSidebar.ets` |
| P-11 | 设置页 Toggle「显示 Bullet」使用系统默认**蓝色**，与紫色主题不统一 | 未设 `selectedColor` | `Toggle` 加 `.selectedColor($r('app.color.primary'))` | `components/settings/SettingsPage.ets` |
| P-12 | 设置页内容在内容不足一屏时同样被垂直居中 | 同 P-7 | `Scroll` 加 `.align(Alignment.TopStart)` | `components/settings/SettingsPage.ets` |

### 3.2 tablet（MatePad Pro 13 · 2880×1920 · density 2.0 · 桌面壳）

| # | 问题现象 | 根因 | 修复方案 | 改动文件 |
|---|---|---|---|---|
| T-1 | 引导页**通栏拉伸**：特性卡片横跨整个 1440vp，内部内容挤在左侧、右侧大片空白；「下一步」按钮几乎占满全屏宽（实测 **1440vp**） | 内容列无最大宽度约束 | 内容列与按钮行加 `constraintSize({ maxWidth: 520 })` 并居中；padding 32→24 | `components/onboarding/OnboardingPage.ets` |
| T-2 | 侧栏「日志」激活项呈**亮绿色** | ARGB | 同 P-8 | 同上 |
| T-3 | 侧栏图标行与导航列表间**大片空白**（同 P-7） | `Scroll` 默认居中 | 同 P-7 | `components/sidebar/LeftSidebar.ets` |
| T-4 | 侧栏空态文案居中，与列表左对齐不一致 | 同 P-6 | 同 P-6 | `components/sidebar/LeftSidebar.ets` |
| T-5 | 右侧栏 / 所有页面 / 标签总览 / 页面视图 / 快捷键页 均有同类居中风险 | 全局 `Scroll` 默认行为 | 统一补 `.align(Alignment.TopStart)`（共 6 处） | `RightSidebar.ets`、`AllPagesPage.ets`、`TabOverviewSheet.ets`、`PageView.ets`、`ShortcutSettings.ets` |
| T-6 | 顶部标签页标题可能显示英文内部路由名 | 同 P-1 | `TabState.tabTitle()` 改为调用 `pageTitle()` | `state/TabState.ets` |
| T-7 | 底部状态栏面包屑显示英文内部路由名 | 同 P-1（且**该值同时被用于数据查询**，不能直接替换） | 拆分为 `resolvePageKey()`（查询用，保留原始页面名）与 `resolveDisplayName()`（显示用，走 `pageTitle()`） | `components/layout/StatusBar.ets` |

**T-1 修复量化验证**（最终 dump 实测）：
```
Button (1440,1756) 1040x88 '下一步'   →  1040px / density2 = 520vp  ✓ 与 CONTENT_MAX_WIDTH 一致
```
修复前该按钮宽度为 1440vp（满屏宽），修复后为 520vp 居中，宽屏观感显著改善。

### 3.3 2in1（MateBook Pro · 3120×2080 · density 2.0 · PC 窗口模式）

| # | 问题现象 | 根因 | 修复方案 | 改动文件 |
|---|---|---|---|---|
| W-1 | **窗口缩放后断点失效**：把窗口从 1045vp 拖窄到 304vp，仍停留在桌面形态（Ribbon + 260vp 侧栏挤爆窄窗，内容区被压成一条缝） | `MainContainer` 用 `display.getDefaultDisplaySync().width` 推断点——这是**整块屏幕**宽度，与窗口尺寸无关，窗口缩放时永不变化 | 根 `Stack` 加 `.onAreaChange()`，以组件**真实 vp 宽度**作为断点依据（窗口缩放 / 分屏 / 折叠 / 旋转均触发） | `components/layout/MainContainer.ets` |
| W-2 | **冷启动窄窗仍用桌面形态**：窗口已被拖窄到 304vp 后冷启动，首屏仍是 Ribbon + 侧栏挤爆 | `onAreaChange` 仅在尺寸**变化**时回调，不保证首帧布局后上报一次，导致 `windowWidth` 停在 display 推导值 | 新增 `initViewportFromWindow()`：启动时主动查 `window.getLastWindow(ctx).getWindowProperties().windowRect`，除以 `densityPixels` 得到真实窗口 vp 宽 | `components/layout/MainContainer.ets` |
| W-3 | **桌面→紧凑切换时左侧抽屉无故自动弹出** | 同一个 `leftSidebarOpen` 状态位在桌面语义是「常驻侧栏」、在移动语义是「抽屉是否展开」；从桌面切换到紧凑时该位仍为 `true`，抽屉随即弹出 | `applyViewportWidth()` 检测 desktop→compact 跃迁时复位左右侧栏 | `components/layout/MainContainer.ets` |
| W-4 | Ribbon 图标按钮、标签栏 +/⌄ 按钮无悬停与按压反馈（PC 有鼠标，缺失尤其明显） | 未实现交互态 | 统一补 `stateStyles`（normal/pressed）+ `onHover` + `animation` | `Ribbon.ets`、`TabBar.ets` |

**W-1 / W-3 实测验证**（2in1 拖拽窗口右边缘）：

| 阶段 | 窗口像素宽 | 换算 vp | 布局形态 | 抽屉是否自动弹出 |
|---|---|---|---|---|
| 初始 | 2090px | 1045vp | 桌面壳（Ribbon + 侧栏 + 标签栏 + 状态栏） | — |
| 拖窄后 | 608px | 304vp | **移动壳**（悬浮玻璃头 + 底部胶囊栏）✓ | **否** ✓（修复前为「是」） |

---

## 四、问题归类与修复汇总

### 4.1 P0 — 颜色令牌 ARGB 误写（影响全应用配色）

**这是本轮最有价值的发现。** HarmonyOS `color.json` 的 8 位十六进制色值按 **`#AARRGGBB`**（alpha 在前）解析，而项目按 `#RRGGBBAA`（alpha 在后）书写：

```
意图：accent_soft = 紫色 #7C4DEF 的 8% 透明度  →  写成 "#7C4DEF14"
实际：alpha = 0x7C (49%)，RGB = (4D, EF, 14) = 亮绿色
```

**实证依据**：截图显示侧栏/Ribbon 激活项为亮绿色，而该处代码明确引用 `app.color.accent_soft`；只有按 ARGB 解析才会得到绿色。放大 5–6 倍复核后确认无误。

**受影响范围**（共 18 处）：

| 文件 | 修正项 |
|---|---|
| `resources/base/element/color.json` | `accent_soft`、`marker_done_bg`、`marker_doing_bg`、`marker_todo_bg`、`marker_later_bg`、`marker_cancelled_bg` |
| `resources/dark/element/color.json` | 同上 6 项 |
| `components/mobile/MobileToolbar.ets` | `#00000020`（原为 **alpha=0，完全透明**） |
| `components/outliner/AutoComplete.ets` | 同上 |
| `components/outliner/SlashMenu.ets` | 同上（2 处） |
| `components/outliner/Toolbar.ets` | `#00000010` |
| `components/search/TaskDashboard.ets` | `#10B98120`、`#0078D420`（后者 alpha=0，完全透明） |

> 注：`glass_border`/`glass_sheen`/`glass_fill` 等本就按 ARGB 正确书写，未改动。

### 4.2 P1 — 布局与自适应

| 类别 | 修复要点 | 文件数 |
|---|---|---|
| 侧栏/列表垂直居中 | 统一为 `Scroll` 补 `.align(Alignment.TopStart)` | 7 |
| 空态文案对齐 | `EmptyHint` 占满宽度 + 起始对齐 | 1 |
| 宽屏通栏拉伸 | 引导页内容与按钮限宽 520vp 居中 | 1 |
| 断点依据 | 改为窗口真实宽度（`onAreaChange` + 窗口矩形初始化 + 形态跃迁复位） | 1 |
| i18n 标题泄漏 | 新增 `pageTitle()` 统一映射，3 处接入 | 4 |

### 4.3 P2 — 交互细节（对应需求第 3 条）

**走查前的覆盖度实测**：

| 能力 | 走查前 | 走查后 |
|---|---|---|
| `stateStyles`（按压/禁用态） | **0 处** | Ribbon、侧栏 3 类行、标签页、顶栏 2 按钮、底栏 7 单元、菜单 9 项、引导 3 按钮 |
| `onHover`（悬停态） | 3 个文件 | 8 个文件 |
| `transition`/`animation`（过渡） | 2 处 | 步骤切换过渡 + 各处 140–220ms 状态过渡 |

**补充的交互能力**：
- **悬停态**：鼠标设备上高亮背景（`surface2`）
- **按压态**：`stateStyles.pressed` 使用新增 `surface3` 令牌
- **禁用态**：底栏后退/前进按 `canGoBack/canGoForward` 降透明度至 0.35 且不响应点击（原有，已核对）
- **过渡动画**：引导步骤切换（新步骤自右淡入 / 旧步骤向左淡出）、指示器宽度变化、激活态背景切换
- **操作反馈**：关闭按钮 hover 变红；标签页 hover 显示关闭按钮（保留）
- **命中区**：标签关闭按钮 18→22vp；`PageLink` 整行可点；顶栏圆形按钮 44vp、底栏单元 44vp（符合 44vp 触控规范）

**超长文本与边界数据**：核对各标题/标签/列表项的 `maxLines` + `TextOverflow.Ellipsis`，并在本轮为顶栏标题、菜单项、引导说明补全约束；新增令牌 `surface3` 作为按压态专用底色，避免与既有 `surface0/1/2` 语义混用。

---

## 五、复测确认

### 5.1 功能无回归

| 检查项 | phone | tablet | 2in1 |
|---|---|---|---|
| 安装 / 冷启动 | ✅ | ✅ | ✅ |
| 进程存活（多轮操作后） | ✅ | ✅ | ✅ |
| 崩溃（APP_CRASH / JS_CRASH） | 0 | 0 | 0 |
| 应用级 E/F 业务错误 | 0（仅系统噪声） | 0 | 0 |
| 引导流程 4 步走通 | ✅ | ✅ | ✅ |
| 侧栏 / 菜单 / 设置 / 图谱 / 白板 / 编辑器 导航 | ✅ | ✅ | ✅ |

### 5.2 修复项逐条复测

| 修复项 | 复测方式 | 结果 |
|---|---|---|
| ARGB 配色 | 截图放大复核侧栏 + Ribbon 激活态 | ✅ 亮绿 → 主题紫 |
| 侧栏顶对齐 | 截图复核 | ✅ 大片空白消失，列表紧贴图标行 |
| 空态文案对齐 | 截图复核 | ✅ 三个分组空态均左对齐 |
| 标题本地化 | 截图复核（设置页） | ✅ 顶栏 "Settings" → 「设置」 |
| 引导限宽 | dump 实测按钮宽度 | ✅ 1440vp → 520vp |
| 窗口断点 | 2in1 拖拽缩放 | ✅ 1045vp→304vp 正确切壳 |
| 抽屉不自动弹出 | 2in1 拖拽缩放 | ✅ 不再弹出 |
| 菜单分组 | 截图复核 | ✅ 三组带标题、仅组间分割线 |
| Toggle 配色 | 截图复核 | ✅ 蓝 → 紫 |
| 交互态 | 代码覆盖度统计 + 设备操作 | ✅ 已补齐 |

### 5.3 一次疑似「卡死」的归因（已排除）

phone 端曾出现 1 次 `LIFECYCLE_HALF_TIMEOUT` / `LIFECYCLE_TIMEOUT`（`EntryAbility foreground timeout`）。归因过程：

1. **改动前基线**：上一轮会话三设备 hilog 中该类事件均为 **0** 次
2. **横向对比**：本次同一构建的 tablet 与 2in1 均为 **0** 次，仅 phone 出现 1 次
3. **隔离复测**：清空日志缓冲后单机冷启动，**0 次**，且启动链路实测极快
   ```
   22:52:03.801 Lifecycle: name EntryAbility
   22:52:03.812 Ability onCreate
   22:52:03.855 onWindowStageCreate  (17ms)
   22:52:03.888 onForeground        → 全程约 87ms
   ```

**结论：为三台模拟器并发运行 + 同时执行构建/部署导致的 CPU 争用**，非应用缺陷。已排除。

---

## 六、未覆盖项与风险提示

| # | 项 | 说明 | 建议 |
|---|---|---|---|
| 1 | **横竖屏旋转适配** | 模拟器不提供旋转能力（`settings`/`wm` 命令均 `inaccessible`，无 `persist.sys.orientation`），无法实测。已确认应用正确注册方向监听，但旋转后实际布局未端到端验证 | 真机补测；重点验证竖→横时是否触发桌面壳、`onAreaChange` 是否驱动重建 |
| 2 | **2in1 冷启动窄窗场景** | 修复方案（W-2）已实现，但模拟器在应用启动时会把窗口还原为常规尺寸，导致「窗口处于窄态时冷启动」难以稳定复现 | 真机上手动把窗口调窄后重启应用验证 |
| 3 | 侧栏行高 32vp | 为保持 Obsidian/Logseq 侧栏的紧凑密度未上调；虽已整行可点，仍略低于 44vp 触控建议值 | 若面向触控优先场景，可提升至 36–40vp |
| 4 | 未签名包 | 工程未配置 `signingConfigs`，产出 `entry-default-unsigned.hap`；模拟器可正常安装，真机分发前须补签名 | 补充签名配置 |

---

## 七、改动文件清单（25 个）

**资源（2）**
- `entry/src/main/resources/base/element/color.json` — 6 个 ARGB 色值修正 + 新增 `surface3`
- `entry/src/main/resources/dark/element/color.json` — 同上

**新增（1）**
- `entry/src/main/ets/utils/PageTitle.ets` — 内部路由 → 本地化标题统一映射

**布局壳（7）**
- `components/layout/MainContainer.ets` — 断点改为窗口真实宽度（onAreaChange + 窗口矩形初始化 + 形态跃迁复位）
- `components/layout/MobileHeader.ets` — 标题本地化 + 自适应宽度 + 圆形按钮三态
- `components/layout/MobileBottomBar.ets` — 宽度自适应 + 7 单元三态
- `components/layout/MobileMenuSheet.ets` — 三组分类重构 + 三态
- `components/layout/Ribbon.ets` — 图标按钮三态
- `components/layout/TabBar.ets` — 标签与操作按钮三态 + 关闭按钮命中区
- `components/layout/TabOverviewSheet.ets` — 顶对齐

**侧栏（2）**
- `components/sidebar/LeftSidebar.ets` — 顶对齐 + 空态对齐 + 三态 + 整行命中 + 死代码清理
- `components/sidebar/RightSidebar.ets` — 顶对齐

**页面（3）**
- `components/onboarding/OnboardingPage.ets` — 限宽居中 + 步骤过渡 + 按钮三态 + 文本对齐 + 移除非功能按钮
- `components/page/AllPagesPage.ets` — 顶对齐
- `components/page/PageView.ets` — 顶对齐（2 处）

**设置（2）**
- `components/settings/SettingsPage.ets` — 顶对齐 + Toggle 主题色
- `components/settings/ShortcutSettings.ets` — 顶对齐

**状态/工具（3）**
- `state/TabState.ets` — `tabTitle()` 接入 `pageTitle()`
- `utils/i18n.ets` — 新增 7 个 key × 2 语言（4 个标题 + 3 个菜单分组）
- `components/layout/StatusBar.ets` — 查询键与显示名拆分

**颜色杂项修正（5）**
- `components/mobile/MobileToolbar.ets`、`components/outliner/AutoComplete.ets`、`components/outliner/SlashMenu.ets`、`components/outliner/Toolbar.ets`、`components/search/TaskDashboard.ets`

---

## 八、结论

本轮以 UI 为主的全量走查，**最关键的收获是定位并修复了一个 P0 级全局配色缺陷**——18 处 8 位色值被按错误的字节序解释，导致全应用的「强调色」渲染为亮绿色、多处阴影/覆盖层变为完全透明。该问题此前被当作「设计如此」而未察觉，本轮通过「截图观测到绿色 → 反查色值定义 → 对照 ARGB 解析规则 → 放大截图证实」的链路确证。

其次修复了 3 个相互关联的自适应缺陷（显示宽度 vs 窗口宽度、首帧断点未初始化、形态跃迁状态位未复位），使 2in1 的窗口缩放首次真正生效；以及侧栏垂直居中、宽屏通栏拉伸、内部路由名泄漏等直接影响观感与一致性的问题。

交互细节方面，将 `stateStyles` 覆盖度从 **0 处**补齐到全部主要可交互组件，并补入悬停态、过渡动画与命中区修正，对应满足了「按钮多态 + 必要过渡动画与操作反馈」的要求。

**三设备最终审计全部通过（越界 / 零尺寸 / 重叠 / 溢出 / 截断 / 小命中区 均为 0），功能无回归。** 遗留 2 项验证缺口（横竖屏旋转、2in1 冷启动窄窗）均因模拟器能力或行为限制无法稳定复现，已在第六节明确列出并给出真机补测建议。
