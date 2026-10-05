# Callaite 深度研究与分优先级执行报告

**日期**：2026-09-19
**基线**：`main` @ `231c284`（4.1.4），SDK 26.0.0（HarmonyOS 7 / API 26）
**本轮结果**：完成 Obsidian 参考截图精确测量、Pen Kit 官方 API 全量核实、HarmonyOS 7 特性盘点；落地 **Pen Kit 手写白板**（构建通过、零告警）与沉浸光感材质层。

---

## 第一部分 · 研究结论（先行确认，不做猜测）

### 1.1 Obsidian 参考截图 —— 程序化测量结果

> 方法：对 2560×1392（PC）与 1170×2532×7（Phone）原图做**逐像素扫描定位面板边界**，而非目视估计。

**PC 端（`Obsidian_Laptop.png`）实测**

| 区域 | 实测值 | 说明 |
|---|---|---|
| Ribbon 竖条宽 | **43 px** | 与左栏同底色 `#F6F6F6`，靠 1px `#E4E4E4` 分隔线区分 |
| 左 sidebar 宽 | **300 px** | 恰为 Obsidian 默认宽度 |
| 标签栏高 | **58 px** | 底部 1px 分隔线在 y=58 |
| 内容区底色 | `#FFFFFF` | 与侧栏 `#F6F6F6` 形成层次 |

**PC 端结构（自上而下 / 自左而右）**

```
┌────┬──────────────────┬──────────────────────────────────────────┐
│    │ [文件][搜索][书签] │  ⌄  [新建标签页 ×][未命名画布 ×]      +  │
│ R  ├──────────────────┼──────────────────────────────────────────┤
│ i  │ ✎ 📁 ↕ ▤ ⌃⌄      │  ‹ ›                                     │
│ b  │                  │                                          │
│ b  │   （文件树）      │   创建新文件 (Ctrl + N)                   │
│ o  │                  │   打开文件 (Ctrl + O)                     │
│ n  │                  │   关闭标签页                              │
│    │                  │                                          │
│ ✓  │ Callaite测试库 ⊙ │  ⧉                                       │
└────┴──────────────────┴──────────────────────────────────────────┘
```

关键结构点：
1. **Ribbon 与左栏同底色**，仅靠分隔线区分（非差异底色）—— 当前项目用的是不同 surface，需核对
2. 左栏有**两行头部**：视图切换行（文件/搜索/书签，含激活态灰底）+ 文件树工具行（新建/新建文件夹/排序/面板/折叠）
3. 标签栏最左侧有 **`⌄` 标签列表下拉**，最右是 `+`
4. 内容区空状态是**居中竖排 3 个链接**（`创建新文件 (Ctrl+N)` / `打开文件 (Ctrl+O)` / `关闭标签页`），紫色文字
5. 左下角状态区：**库名 + 同步/勾选图标**，右端 2 个图标
6. 内容区支持**左右分屏**（左"新建标签页" | 右"未命名画布"）

**Phone 端（7 张）实测**

| # | 状态 | 结构要点 |
|---|---|---|
| 1 | 主视图（空态） | 悬浮玻璃顶栏 `[侧栏][标题][⋯]`；居中「创建新文件 / 关闭标签页」；底部玻璃胶囊 |
| 2 | 更多菜单 | 上滑面板：打开快速切换/查看关系图谱/新建白板/打开今天的日记/导入笔记/打开命令面板/新建数据库 |
| 3 | 标签总览 | 背景压暗；居中单张标签卡（圆角白卡 + 右上 × + 页面图标）；底部 `+` / 「1 个标签页」/「完成」 |
| 4 | 搜索态 | 居中「未找到最近文件，输入以搜索…」+ 2 图标 |
| 5/6 | 编辑器 + 键盘 | 标题「欢迎使用 LightNote」；**键盘上方 Markdown 工具行**（撤销/重做/缩进/反缩进/链接/图片/标签/H1/B…） |
| 7 | — | （同上变体） |

**底部操作栏（实测放大确认）**：**单个玻璃胶囊内含 6 个等距单元**

```
‹   ›   🔍   ＋   [1]   ☰
返回 前进 搜索 新建  标签数 菜单
```
- 胶囊宽度 ≈ **屏宽 80%**（左右各留 10%）
- 未加载历史时 `‹ ›` 为**浅灰禁用态**
- ✅ **当前项目 `MobileBottomBar` 结构已与之一致**（6 单元 + 单胶囊 + 禁用态），无需重构

---

### 1.2 Pen Kit —— 官方 API 全量核实

> 来源：本地 SDK 声明文件 `@hms.stylus.HandwriteComponent.d.ets` + 华为开发者联盟《接入手写套件》
> SysCap：`SystemCapability.Stylus.Handwrite`（起始 **5.0.0(12)**），Stage 模型专有

**导入**（注意 kit 名大小写为 `Penkit`）：
```typescript
import { HandwriteComponent, HandwriteController, PenType, PenHspInfo,
         HiddenToolType, HiddenConfig } from '@kit.Penkit';
```

**`HandwriteComponent` 全部属性（已逐条核实）**

| 属性 | 类型 | 起始版本 | 说明 |
|---|---|---|---|
| `handwriteController` | `HandwriteController` | 5.0.0(12) | **必填** |
| `onInit` | `InitCallback` | 5.0.0(12) | 初始化完成回调 |
| `onScale` | `ScaleCallback` | 5.0.0(12) | 画布缩放回调 |
| `onDidScroll` | `DidScrollCallback` | 6.1.0(23) | 长画布滚动回调 |
| `defaultPenType` | `PenType` | 5.1.0(18) | 默认笔型 |
| `defaultPenInfo` | `PenHspInfo[]` | 5.1.0(18) | 各笔刷默认宽度 |
| `widthRatio` / `heightRatio` | `number` | 6.0.0(20) | 画布宽/高占比，[0,1]，默认 1 |
| `maxCanvasHeight` | `number` | 6.1.0(23) | 长画布最大高度（vp） |
| `scaleDisabled` | `boolean` | 6.1.0(23) | 禁用缩放，默认 false |
| **`hiddenTools`** | `HiddenConfig` | **26.0.0** | **HarmonyOS 7 新增**：隐藏指定工具 |

**`HandwriteController` 全部方法**

| 方法 | 签名 | 起始版本 | 异常 |
|---|---|---|---|
| `save` | `(path: string): Promise<void>` | 5.0.0(12) | `1010400002 save failed` |
| `load` | `(path: string): void` | 5.0.0(12) | `1010400001 load failed` |
| `onLoad` | `(cb: AsyncCallback<string>): void` | 5.0.0(12) | `1010400001` |
| `getContentRange` | `(): Rect` | 6.0.0(20) | — |
| `getThumbnail` | `(rect: Rect): Promise<PixelMap>` | 6.0.0(20) | — |
| `scrollTo` | `(yOffset: number): void` | 6.1.0(23) | — |

**枚举实测取值**

```
PenType       : PEN=1 BALLPOINT_PEN=2 PENCIL=3 MARKER=4 HIGHLIGHTER_BRUSH=5
                MOSAIC=7 RUBBER=8 LASSO=9 LASER=10
HiddenToolType: PEN=1 PENCIL=3 MARKER=4 HIGHLIGHTER_BRUSH=5 MOSAIC=7
                LASSO=1048576 LASER=3145728 GRAPHICS_TOOLS=4194304
PenHspInfo    : { penType: PenType; penWidth: number }
HiddenConfig  : { hiddenOptionalTools?: HiddenToolType[]; hiddenArcBox?: boolean }
```

**套件另附能力**（同 kit 导出）：`InstantShapeGenerator`（一笔成形）、`PointPredictor` / `StylusFrameBoost`（报点预测 / 帧率提升）、`imageFeaturePicker`（全局取色）、`stylusInteraction`。

**重要约束（官方）**：
- Pen Kit 手写套件**仅支持上下滑动，不支持左右滑动**
- **接入手写套件后自动开启一笔成形与报点预测**，无需单独接入
- 需在 `EntryAbility` 中把 `UIAbilityContext` 暴露到全局容器（官方接入步骤 1）

---

### 1.3 HarmonyOS 7 系统特性盘点（与本项目相关）

| 特性 | API | 项目可用性 |
|---|---|---|
| 沉浸光感（Immersive Light） | `uiMaterial` / `systemMaterial` | ⚠️ 受 Navigation 容器约束（见 §2.1） |
| 手写套件波轮菜单 / 预置图形 / 矩形套索 / 自定义工具 | `HandwriteComponent.hiddenTools` 等 | ✅ **已接入** |
| 系统组件默认沉浸材质 | Dialog / Toast / AlphabetIndexer | 自动生效，需复核观感一致性 |
| 智感握姿 / 闪控球 / 可变字体 | 系统级 | 后续评估 |
| 碰一碰 / 隔空投送 | Share Kit | 未接入（需真机） |

---

## 第二部分 · 逐项任务的改动点、实施步骤与验证方式

### 2.1 任务 1：UI 层面最大程度复刻 Obsidian 布局

**差距分析（当前 vs 参考）**

| # | 项 | 参考（Obsidian） | 当前项目 | 优先级 |
|---|---|---|---|---|
| U1 | Phone 底部胶囊 6 单元 | ‹ › 🔍 ＋ [N] ☰ | 同 | ✅ 已达标 |
| U2 | Phone 顶栏 | [侧栏][标题][⋯] 悬浮玻璃 | 同 | ✅ 已达标 |
| U3 | 胶囊宽度 | 屏宽 80% | 92%（上限 336vp） | P2 微调 |
| U4 | **Ribbon 与左栏同底色** | 均为 `#F6F6F6`，靠分隔线区分 | Ribbon `surface0` / 侧栏 `surface1` 异色 | **P1** |
| U5 | **左栏两行头部** | 视图切换行（含激活灰底）+ 文件树工具行（5 图标） | 有视图切换行，**缺文件树工具行** | **P1** |
| U6 | 标签栏 `⌄` 标签列表下拉（最左） | 有 | 最右有 `⌄` 菜单 | P2 位置对齐 |
| U7 | 左下角状态区 | 库名 + 同步图标 + 右端 2 图标 | 有「仓库 · 设置」 | P2 |
| U8 | **内容区左右分屏** | 支持（左/右双面板） | 未实现 | **P1** |
| U9 | **键盘上方 Markdown 工具行** | 撤销/重做/缩进/链接/图片/标签/H1/B | 需核对 `Toolbar.ets` | **P1** |
| U10 | 标签总览底部 `+` / 「N 个标签页」/「完成」 | 有 | 需核对 `TabOverviewSheet` | P2 |
| U11 | Phone 更多菜单项文案 | 打开快速切换/查看关系图谱/新建白板/打开今天的日记/导入笔记/打开命令面板/新建数据库 | 三组分类（内容/视图/数据） | P2 文案对齐 |

**实施步骤（按优先级）**

1. **U4/U5**（左栏结构对齐）：统一 Ribbon 与左栏底色为同色系，补文件树工具行（新建文件/新建文件夹/排序/折叠切换/展开全部）
2. **U8**（分屏）：`MainContainer` 在桌面壳下支持水平双面板 + 拖拽分隔条；这是 Obsidian 的核心交互，改动面中等
3. **U9**：核对并补齐键盘上方 Markdown 工具行
4. **U3/U6/U7/U10/U11**：参数与文案微调

**验证方式**：三设备（phone / tablet / 2in1）截图与参考图**逐区域并置比对**；辅以布局 dump 的几何校验（面板宽度、间距、对齐 tolerance 1.2）。

---

### 2.2 任务 2：白板优先接入 Pen Kit，再做 Canvas 适配 ✅ 本轮已落地

**实施步骤**

1. 新建 `utils/GlobalContext.ets` —— 按官方接入步骤 1 暴露 `UIAbilityContext`
2. `EntryAbility.onWindowStageCreate` 注入 `GlobalContext.setContext(this.context)`
3. 新建 `components/whiteboard/PenCanvasPage.ets` —— 完整覆盖 §1.2 全部 API：
   - 画布：`widthRatio` / `heightRatio` / `maxCanvasHeight`（8000vp 长画布）/ `scaleDisabled`
   - 笔刷：`defaultPenType = PEN`，`defaultPenInfo` 配置 5 种笔刷宽度（钢笔/铅笔/马克笔/荧光笔/橡皮）
   - 工具裁剪：`hiddenTools`（**API 26 新能力**，隐藏镭射笔与图形工具）
   - 回调：`onInit` / `onScale`（实时显示缩放百分比）/ `onDidScroll`
   - 生命周期：`onLoad` 注册加载回调、`aboutToDisappear` 自动保存、异常按 `BusinessError` 码分类提示
   - 缩略图：`getContentRange()` + `getThumbnail()` 生成并展示
4. `PageView.ets` 接入**引擎路由**：`canIUse('SystemCapability.Stylus.Handwrite')` 为真时默认使用 Pen Kit，否则回退自研 Canvas；两者均可用时提供「手写引擎」切换条

**验证方式**

| 层级 | 方法 | 结果 |
|---|---|---|
| 编译 | `build_callaite.sh debug` | ✅ `BUILD SUCCESSFUL`，`PenCanvasPage` 已进产物，**零告警** |
| 能力探测 | 运行时 `isPenKitSupported()` | 支持则渲染 Pen Kit，否则 Canvas |
| 功能 | 真机（平板/2in1 + 手写笔）：书写、笔刷切换、缩放、长画布滚动、保存/重载、缩略图 | ⬜ 需真机手写笔 |
| 降级 | 无手写能力设备 | ⬜ 待验 |

**⚠️ 过程中发现的两个真实问题（已修复，值得记录）**

1. **`@State scale` 与 `CustomComponent` 基类成员 `scale()` 冲突** → 编译报 `not assignable to the same property in base type`
   修复：重命名为 `zoomScale`。**这与项目此前 `GlassSurface` 记录的 `blur` 同名冲突是同一类陷阱**——在 struct 中命名 `@State` 时须避开基类已声明的方法名（`scale`/`blur`/`opacity`/`width` 等）。
2. **`controller.load()` 会抛 `BusinessError 1010400001`** → 补齐 try/catch 与错误码提示。

**另注**：未引用 `PenCanvasPage` 时它**不会进入编译产物**（被 tree-shake），因此初次构建"通过"并不代表 Pen Kit 可用。接入路由后重新编译才真正暴露上述错误 —— 这是本轮一条重要的验证经验。

---

### 2.3 任务 3：最大限度发挥 HarmonyOS 7 系统特性

| 特性 | 现状 | 建议 |
|---|---|---|
| 沉浸光感 | 阶段一已落地（Token 化玻璃 + 按压反馈） | 阶段二迁移 Navigation 以启用系统材质 |
| 手写套件 API 26 新能力 | ✅ 已用 `hiddenTools` | 后续可加波轮菜单、预置图形、矩形套索 |
| 系统组件沉浸材质 | 自动生效 | 复核 Dialog/Toast 与应用自绘材质的观感一致性 |
| 碰一碰 / 流转 | 未接入 | 需真机 + AGC AppLink |
| 智感握姿 / 闪控球 | 未评估 | 建议后续专项评估 |

---

### 2.4 任务 4：官方文档研究（已执行）

本轮**所有 API 均先核实后编码**，来源为：

| API | 核实来源 |
|---|---|
| `uiMaterial` / `ImmersiveStyle` / `ImmersiveMaterial` | 本地 SDK `@ohos.arkui.uiMaterial.d.ts`（530 行，逐字段读取） |
| `systemMaterial` 生效范围与冲突规则 | 华为开发者联盟《图像效果-通用属性》官方参考原文 |
| 沉浸光感设计规范（五档落位） | 华为开发者联盟《沉浸光感》设计指南 |
| `HandwriteComponent` / `HandwriteController` | 本地 SDK `@hms.stylus.HandwriteComponent.d.ets` |
| Pen Kit 接入步骤与版本演进 | 华为开发者联盟《接入手写套件》 |
| 碰一碰 / Share Kit | 华为开发者联盟 Share Kit 简介与碰一碰分享文档 |

**交叉验证亮点**：编译器独立报出 `EntryAbility.ets:194` 的「This API is unavailable to 2in1」警告，**与 CSV 扫描的 P0-1（`setWindowLayoutFullScreen` 在 PC/2in1 禁用）完全吻合** —— 两条独立证据链相互印证。

---

## 第三部分 · 本轮代码改动（7 个文件）

| 文件 | 变更 | 验证 |
|---|---|---|
| `ets/utils/GlobalContext.ets` | **新增** —— Pen Kit 要求的全局 Context 容器 | 编译通过 |
| `ets/components/whiteboard/PenCanvasPage.ets` | **新增** —— Pen Kit 手写白板（覆盖全部已核实 API） | 编译通过、零告警、已进产物 |
| `ets/entryability/EntryAbility.ets` | 注入 `GlobalContext` | 编译通过 |
| `ets/components/page/PageView.ets` | 白板引擎路由（Pen Kit 优先 / Canvas 兜底 / 可切换） | 编译通过 |
| `ets/theme/MaterialTokens.ets` | **新增** —— 沉浸光感 5 档材质 Token | 编译通过 |
| `ets/components/common/GlassSurface.ets` | 接入 `materialRole` + 按压弹性反馈 | 编译通过 |
| `layout/MobileHeader.ets`、`MobileBottomBar.ets` | 材质角色绑定（ULTRA_THIN / THIN） | 编译通过 |

---

## 第四部分 · 待办与建议（按优先级）

| 优先级 | 事项 | 依赖 |
|---|---|---|
| **P1** | UI：Ribbon/左栏同底色重构（U4）、文件树工具行（U5）、内容区左右分屏（U8）、Markdown 工具行（U9） | 无（可在模拟器验证） |
| **P1** | API 26 P0 第一批修复：PC 多窗 `setWindowLayoutFullScreen`、白板/图谱 Canvas 的 NaN 防护、账号返回值规则 | 无 |
| **P2** | 胶囊宽度 80%、标签栏 `⌄` 位置、标签总览底部栏、菜单文案对齐 | 无 |
| **P2** | 沉浸光感阶段二：外壳迁移 Navigation + NavDestination | 高风险，建议单独立项 |
| **P3** | 碰一碰 / 超级终端多端流转 | **需真机双设备 + AGC AppLink 配置** |
| **P3** | Pen Kit 真机验证（笔迹质量、延迟、压感） | **需手写笔真机** |

**两点必须说明的限制**：
1. Pen Kit 与多端流转**无法在模拟器验证** —— 模拟器无手写笔输入、不支持碰一碰。当前仅完成到"编译通过 + 类型正确 + 能力探测 + 降级路径"。
2. UI 复刻的 P1 项（分屏、文件树工具行）本轮**未实施**，因需协调 `MainContainer` 分屏状态管理与侧栏结构，改动面较大且需逐设备回归。已给出明确差距清单（§2.1）可直接排期。
