# Callaite HarmonyOS 7（API 26）升级评估与实施方案

**日期**：2026-09-19
**仓库**：`F:\DevEcoStudioProjects\Callaite`
**基线**：`231c284` · Callaite 4.1.4 Beta 测试版本
**结论**：SDK 已升级至 API 26（HarmonyOS 7），但**尚未做任何 API 26 适配**（扫描 2702 条提示，0 条已修复）；沉浸光感改造受一处硬约束影响，需分两阶段落地。

---

## 第一部分 · 现状总结

### 1.1 仓库状态

| 项 | 值 | 判定 |
|---|---|---|
| 分支 / HEAD | `main` / `231c284` | 正常 |
| 与远程关系 | `origin/main` = `main` = `231c284` | **已同步，无分叉** |
| 工作区 | 0 处未提交变更 | 干净 |
| `targetSdkVersion` | `26.0.0` | **已升级至 HarmonyOS 7 / API 26** |
| `compatibleSdkVersion` | `26.0.0` | 最低兼容版本同样提到 26 |
| `oh-package.json5` `modelVersion` | `6.1.1` | ⚠️ 未随 SDK 同步 |

**关于版本对应关系（已核实）**：官方资料确认 **HarmonyOS 7 ↔ API 26**（"适用范围：HarmonyOS 7、API 26 Developer Beta"）。因此 `26.0.0` 即 HarmonyOS 7。

### 1.2 关键架构现状（决定改造可行性）

| 维度 | 现状 | 影响 |
|---|---|---|
| 外壳结构 | **完全未使用 `Navigation` / `NavDestination`**（0 处引用），自研 `Stack + Row + Column` | **决定沉浸光感只能走"降级路径"**（见 §3.2） |
| 玻璃质感 | 自研 `GlassSurface`，仅 **3 个文件**引用（自身 + `MobileHeader` + `MobileBottomBar`） | 改造面小，收敛快 |
| 玻璃实现 | `GlassMode.MATERIAL` → `backgroundBlurStyle(COMPONENT)`；`GlassMode.EFFECT` → `backgroundEffect` + 高光层 + 描边 + 投影 | 可对齐官方语义 |
| HDS / uiMaterial | **均未接入**（`@kit.UIDesignKit`、`@kit.ArkUI` 的 `uiMaterial` 引用数 = 0） | 需新建材质层 |
| 白板 | `Whiteboard.ets` 1363 行 + `WbConnector`/`WbPageRef`/`WbShape`，基于 Canvas | 受 API 26 Canvas 行为变更影响 |
| 多端协同 | `CollaborationService`（DistributedKVStore P2P）+ `ContinuationManager` + `HuaweiAccountService`（`distributedAccount`） | 已有基础，缺 Share Kit |
| 碰一碰 / 超级终端 | **完全未接入**（Share Kit / `knockShare` / `canIUse` 引用数 = 0） | 需从零建设 |

---

### 1.3 API 变更扫描结果分析

**文件**：`20260919111316_apiChange.csv`（921 KB / 2,703 行，为 11:13 重新生成的版本）
**来源**：DevEco Studio「API 变更扫描」——覆盖项目自 `compatibleSdkVersion` 以来所有版本的行为提示

#### 规模与构成

| 维度 | 结果 |
|---|---|
| 总提示条目 | **2,702** |
| 已修复 | **0** |
| 唯一 API 数 | 35 |
| **唯一变更类别数** | **18** |
| 涉及文件 | 68 |
| 语言 | 全部 ArkTS |

> **关键洞察**：2,702 条提示**仅对应 18 类变更**——即同一条变更在 68 个文件、2,702 个代码位置被重复标记。因此实际待处理工作量是 **18 类**，而非 2,702 项。

#### 变更类型分布

| 类型 | 条目 | 占比 | 性质 |
|---|---|---|---|
| 接口定义变更 | 2,136 | 79.1% | 多为**兼容性放宽**提示（如新增 `Resource` 类型支持），非破坏性 |
| UX视觉布局变更 | 489 | 18.1% | 默认样式/尺寸变化，**需目视复核** |
| 接口行为变更 | 45 | 1.7% | **真实行为变更，需改代码** |
| UX交互行为变更 | 32 | 1.2% | **真实行为变更，需改代码** |

#### SDK 版本归因

| 变更版本 | 条目 |
|---|---|
| **7.0.0(26) Beta1** | **2,470**（91.4%） |
| 6.0.0(20) Beta1 | 132 |
| 5.1.0(18) Release | 57 |
| 5.0.1(13) Beta3 / Release | 40 |
| 5.0.2(14) Beta1 / 6.0.0(20) Beta2 | 3 |

> 91.4% 归因于 **7.0.0(26)**，印证"升级到 HarmonyOS 7 触发批量提示"。

#### 18 类变更 × 优先级分层

**P0（真实行为变更 —— 必须改代码，共 9 类 / 65 条 / 涉及 20 个文件）**

| # | 变更 | 条目 | 文件 | 项目命中点 |
|---|---|---|---|---|
| 1 | `setWindowLayoutFullScreen` / `setImmersiveModeEnabledState` **在 PC/2in1 自由多窗模式禁用** | 1 | 1 | ⚠️ **`EntryAbility.ets`（正是一轮前的沉浸式实现）** |
| 2 | 组件**阴影模糊半径规格变更** | 15 | 13 | `FloatingPanel`、`GlassSurface`、`TabBar`、`TabOverviewSheet`、`GraphActions`、`MobileToolbar` |
| 3 | 属性动画 `onFinish` 回调在退后台时**提前触发** | 29 | 10 | `FloatingPanel`、`MainContainer`、`MobileBottomBar`、`MobileHeader`、`MobileMenuSheet`、`Ribbon`、`TabBar` |
| 4 | **双指长按**行为变更 | 9 | 3 | `GraphView`、`BlockDragHandler`、`AllPagesPage` |
| 5 | `CanvasRenderingContext2D` 传 **NaN/Infinity** 后其他绘制方法由"不绘制"变为"正常绘制" | 9 | 2 | ⚠️ **`Whiteboard.ets`、`GraphView.ets`** |
| 6 | **禁止在转场动画中更新消失节点的属性** | 6 | 2 | `FloatingPanel`、`OnboardingPage` |
| 7 | `MenuItem` 在非 PC/2in1 上**超长文本由缩略改为换行** | 3 | 1 | `TabBar` |
| 8 | `postCardAction` router 事件**允许拉起 Ability 类型范围变更** | 1 | 1 | `widget/pages/WidgetCard.ets` |
| 9 | 画布绘制文本时 `globalCompositeOperation`/`fillStyle`/`globalAlpha` **效果变更**；`CanvasRenderer.font` **自定义字体行为变更** | 2 | 2 | `GraphView.ets` |
| 10 | `getOsAccountDistributedInfo` **返回值生成规则变更** | 1 | 1 | ⚠️ **`HuaweiAccountService.ets`（多端流转依赖）** |
| 11 | `Image.borderRadius` 支持动态修改 | 1 | 1 | `BlockView.ets` |

**P1（接口定义变更 —— 需核对签名，多为兼容放宽，共 2 类 / 2,136 条）**

| # | 变更 | 条目 | 文件 | 说明 |
|---|---|---|---|---|
| 12 | **ArkUI 接口新增"仅支持 Stage 模型"约束** | **2,004** | 64 | 项目已是 Stage 模型（`module.json5` 有 `abilities`），属**符合性提示**，无需改代码，仅需确认无 FA 模型残留 |
| 13 | 文本/输入/按钮/滚动/图形组件接口**支持 `Resource` 类型** | 132 | 47 | 能力放宽，**非破坏性**；可择机将硬编码数值改为 `$r()` 资源 |

**P2（UX 视觉/交互样式变更 —— 需目视复核，共 5 类 / 528 条）**

| # | 变更 | 条目 | 文件 | 说明 |
|---|---|---|---|---|
| 14 | **`Dialog`、`Toast`、`AlphabetIndexer`、文本选择菜单默认开启沉浸式系统材质** | 341 | 52 | 与任务 1 同向；系统组件自动获得材质，需复核与应用自绘玻璃的**视觉一致性** |
| 15 | 内置文本的组件**文本样式优化** | 61 | 23 | `AlertDialog`/`DatePickerDialog`/`Button`/`Menu` 文本样式变化 |
| 16 | 表单类组件**触摸热区最小高度变更** | 49 | 20 | ⚠️ 与一轮前的 40vp 热区改造叠加，需复核 `Button`/`Select`/`Toggle` |
| 17 | **按钮默认值变更为新增圆角矩形类型** | 38 | 15 | `Button` 默认 `type` 变化 → 显式指定 `ButtonType` 的调用点不受影响，未指定者外观会变 |
| 18 | 其它 UX 布局微调 | 39 | — | 逐项目视复核 |

---

## 第二部分 · 任务 1：玻璃质感 → 沉浸光感 UI

### 2.1 官方规范（已从华为开发者联盟核实，非推断）

**沉浸光感 = Immersive Light**，HarmonyOS 7 官方设计语言。官方定位：*"将材质视作独立界面物质，统一整合其光学行为、空间属性与交互响应能力，系统化地模拟光线的传播与反射"*。

**六个特性**：通透材质 / 渐变模糊 / 按压弹性反馈 / 按压点光源 / 材质流光 / 智能反色

**五档材质语义（官方设计指南的场景规范）**：

| 位置 | 推荐档位 | 官方说明 |
|---|---|---|
| 顶部悬浮 | **`ULTRA_THIN`** | 结合**渐变模糊**延展顶部内容展示空间 |
| 底部悬浮 | **`THIN`** | 结合**渐变颜色蒙层**延展底部内容展示空间 |
| 任意位置弹出 | **`THICK`** | 确保复杂场景下内容的可读性 |
| 半模态 / 弹出框 | **`ULTRA_THICK`** | 面积大、内容丰富度强 |
| 常规承载 | `REGULAR`（默认） | — |

**API 事实（已核对本地 SDK 声明文件 `@ohos.arkui.uiMaterial.d.ts`，非猜测）**：

```typescript
import { uiMaterial } from '@kit.ArkUI';        // API 26.0.0+，@stagemodelonly

enum ImmersiveStyle { ULTRA_THIN=0, THIN=1, REGULAR=2, THICK=3, ULTRA_THICK=4 }
enum MaterialLevel  { EXQUISITE=0, GENTLE=1, SMOOTH=2 }   // 设备决定，不支持设置

function isImmersiveMaterialSupported(): boolean
function getGlobalMaterialLevel(): MaterialLevel
class Material { static get empty(): Material }
class ImmersiveMaterial extends Material { constructor(options: ImmersiveOptions) }

interface ImmersiveOptions {
  style?: ImmersiveStyle;              // 默认 REGULAR
  materialColor?: ResourceColor;       // 默认 Transparent；**不可完全不透明**，否则滤镜被遮挡
  colorInvert?: boolean;               // 默认 false；需 ≥THIN 薄档才可能生效
  applyShadow?: boolean;               // 默认 true；**true 时材质阴影优先于 shadow() 属性**
  interactive?: boolean;               // 默认 false；按压形变
  lightEffect?: LightEffectOptions | null;  // 默认 undefined；触点光感，color 默认白
}

// 应用入口（通用属性）
.systemMaterial(material: SystemUiMaterial | undefined): T
```

### 2.2 ⚠️ 决定性约束（官方原文）

> **"通过该属性设置组件的系统材质时，仅在 `Navigation` 或 `NavDestination` 的标题栏，或横向 `Tabs` 中 `barPosition` 为 `BarPosition.End` 的底部 `TabBar` 中生效。"**
>
> **"该样式仅限当前组件使用，不会影响或继承至子组件。"**

**对本项目的影响**：项目外壳是自研 `Stack/Row/Column` + `GlassSurface`，**不在生效范围内**。这意味着：

- ❌ 不能简单地把 `GlassSurface` 替换为 `.systemMaterial(...)` —— 系统会**静默忽略**
- ✅ 有两条可行路径（见下）

### 2.3 改造范围与涉及组件

| 组件 | 角色 | 现档位来源 | 目标档位 | 是否在系统材质生效范围 |
|---|---|---|---|---|
| `MobileHeader`（顶栏） | 顶部悬浮 | `shadowRadius 10 / alpha 0.12` | **ULTRA_THIN** | ❌ 自研容器 |
| `MobileBottomBar`（胶囊栏） | 底部悬浮 | `shadowRadius 20 / alpha 0.16` | **THIN** | ❌ 自研容器 |
| `FloatingPanel`（侧边悬浮面板） | 任意位置弹出 | `shadow radius 24` | **THICK** | ❌ 自研容器 |
| `MobileMenuSheet`（更多菜单） | 半模态 | `surface1 + 顶部圆角` | **ULTRA_THICK** | ❌ 自研容器（`bindSheet` 类） |
| 停靠侧栏 / 标签栏 | 常规承载 | 实色 `surface1` | REGULAR | — |

### 2.4 视觉规范（项目材质 Token 表）

**核心原则**：把"视觉强度"收口为**语义 Token**，页面不再散落模糊半径/阴影/透明度数值。参数随档位"厚度"单调变化：

| 档位 | 模糊半径 | 填充不透明度 | 高光强度 | 阴影半径 | 阴影不透明度 | 按压缩放 | 触点光感 |
|---|---|---|---|---|---|---|---|
| ULTRA_THIN（顶部） | 12vp | 0.55 | 0.30 | 10vp | 0.10 | 否 | 否 |
| THIN（底部） | 18vp | 0.66 | 0.24 | 20vp | 0.16 | **是** | **是** |
| REGULAR（内容） | 22vp | 0.78 | 0.18 | 14vp | 0.12 | 否 | 否 |
| THICK（临时浮层） | 28vp | 0.86 | 0.14 | 24vp | 0.24 | 否 | 否 |
| ULTRA_THICK（弹窗） | 36vp | 0.94 | 0.08 | 28vp | 0.28 | 否 | 否 |

**互动反馈**：`interactive` 档位启用按压缩放至 **0.97**，`Curve.Friction` / 160ms；`lightEffect` 档位启用触点白光光晕。

### 2.5 实施步骤与已完成项

**阶段一（已完成，可立即验证）** —— 自研玻璃对齐官方语义：

1. ✅ 新建 `entry/src/main/ets/theme/MaterialTokens.ets`
   - `MaterialRole` 枚举（5 种语义角色，对齐官方位置规范）
   - `MATERIAL_SPECS` Token 表（上表）
   - `ImmersiveMaterialResolver`：`isSystemMaterialSupported()` / `deviceLevelName()` / `buildSystemMaterial()` / `emptyMaterial()`
2. ✅ 改造 `GlassSurface`：新增 `materialRole` 属性，模糊半径/填充/高光/阴影全部由 Token 驱动（原模糊半径是硬编码 36vp），**并补齐官方六特性中缺失的"按压弹性反馈"**（`onTouch` + `scale` + `animation`）
3. ✅ 更新调用点：`MobileHeader` → `TOP_FLOATING`，`MobileBottomBar` → `BOTTOM_FLOATING`
4. ✅ 构建验证：`BUILD SUCCESSFUL`，产物含 `MaterialTokens.protoBin`

**阶段二（建议后续排期）** —— 迁移外壳以启用系统材质：

| 步骤 | 内容 | 风险 |
|---|---|---|
| 2.1 | 将 `MainContainer` 外壳迁移到 `Navigation` + `NavDestination`，顶栏用 titleBar | **高**（涉及导航栈、返回键、深链） |
| 2.2 | 顶栏/底栏改由 `systemMaterial(new uiMaterial.ImmersiveMaterial({...}))` 驱动 | 中 |
| 2.3 | 接入 `isImmersiveMaterialSupported()` 降级：不支持则回退阶段一的 Token 参数 | 低 |
| 2.4 | 处理 `applyShadow` 冲突：材质默认 `applyShadow=true` 会**覆盖** `shadow()` 属性 | 低（已预留） |

### 2.6 验证方式

| 层级 | 方法 | 通过标准 |
|---|---|---|
| 编译 | `build_callaite.sh debug` | `BUILD SUCCESSFUL` |
| 能力探测 | 运行时打印 `isSystemMaterialSupported()` / `deviceLevelName()` | 正确返回，不抛异常 |
| 视觉 | 三设备（phone/tablet/2in1）截图对比改造前后 | 顶部更通透、底部层次更明确、按压有缩放反馈 |
| 一致性 | 与系统组件（API 26 后 `Dialog`/`Toast` 默认带材质）并置比对 | 材质强度观感一致，无明显割裂 |
| 降级 | 低算力设备/模拟器（`SMOOTH`） | 不崩、不白屏，回退到 Token 参数 |
| 性能 | DevEco Profiler 滚动帧率 | 长列表滚动 ≥ 55 FPS，无明显掉帧 |

---

## 第三部分 · 任务 2：API 扫描结果的分优先级处理方案

### 3.1 处理原则

```
P0（行为变更，9 类 / 65 条）  → 逐条改代码 + 逐条验证    【必做】
P1（定义变更，2 类 /2136 条） → 确认符合性，基本无需改码  【核对即可】
P2（视觉布局，5 类 / 528 条） → 目视复核 + 显式化          【复核为主】
```

### 3.2 P0 逐项处理方案

| # | 变更 | 处理方案 | 涉及文件 | 验证方式 |
|---|---|---|---|---|
| P0-1 | `setWindowLayoutFullScreen` 在 **PC/2in1 自由多窗禁用** | 在调用处按设备类型分支：PC/2in1 自由多窗下跳过该调用，改用 `getWindowAvoidArea` 单独取避让区；保留非 PC 设备行为 | `EntryAbility.ets` | 2in1 模拟器自由多窗模式下启动，确认无异常且避让区正确 |
| P0-2 | **阴影模糊半径规格变更** | 逐处核对 `shadow({radius})` 实际视觉半径，按新规格回填；材质场景优先用 Token 的 `shadowRadius` | `FloatingPanel` / `GlassSurface` / `TabBar` / `TabOverviewSheet` / `GraphActions` / `MobileToolbar` | 截图比对阴影扩散范围；确认无过度发虚 |
| P0-3 | 动画 `onFinish` 退后台**提前触发** | 关键路径不依赖 `onFinish` 做状态提交；改为显式状态机 + `onDisAppear` 兜底 | `FloatingPanel` / `MainContainer` / `MobileBottomBar` / `MobileHeader` / `MobileMenuSheet` / `Ribbon` / `TabBar` | 动画中途切后台再回来，确认 UI 状态不残留、不错乱 |
| P0-4 | **双指长按**行为变更 | 核对 `LongPressGesture({fingers: 2})` 的触发条件，必要时显式指定 `fingers`/`repeat`/`duration` | `GraphView` / `BlockDragHandler` / `AllPagesPage` | 手势实测：单指/双指长按行为与预期一致 |
| P0-5 | **Canvas 传 NaN/Infinity 后绘制行为变更** | 在坐标计算出口统一做 **有限性校验**（`Number.isFinite`），非法值跳过绘制；缩放手势、力导向布局的除零路径重点排查 | ⚠️**`Whiteboard.ets`** / `GraphView.ets` | 白板缩放至极值/空画布/单节点图谱时无异常图形 |
| P0-6 | **转场动画中禁止更新消失节点属性** | 转场期间不写将消失节点的 `@State`；把状态更新移出过渡窗口 | `FloatingPanel` / `OnboardingPage` | 快速开关浮层/切步骤，确认无属性不生效或闪烁 |
| P0-7 | `MenuItem` 超长文本改为换行 | 给菜单项文本显式 `maxLines(1)` + `textOverflow(Ellipsis)` | `TabBar` | 构造超长标签页名，确认仍为单行省略 |
| P0-8 | `postCardAction` 拉起 Ability 范围变更 | 核对卡片 router 目标是否在允许范围内 | `WidgetCard.ets` | 添加卡片后点击，确认能正确拉起 |
| P0-9 | Canvas 文本绘制效果 / `font` 自定义字体行为变更 | 核对 `fillText` 前后的 `globalAlpha`/`fillStyle` 设置顺序；自定义字体显式设置 | `GraphView.ets` | 图谱节点标签渲染正确、无颜色错乱 |
| P0-10 | `getOsAccountDistributedInfo` **返回值生成规则变更** | 核对 `detectLoggedIn()` 对返回值的判定逻辑，改为按新规则解析 | ⚠️**`HuaweiAccountService.ets`** | 登录/未登录/未授权三态判断正确；影响多端流转 |
| P0-11 | `Image.borderRadius` 支持动态修改 | 能力放宽，确认原有静态用法即可 | `BlockView.ets` | 图片圆角正常 |

### 3.3 P1 / P2 处理要点

- **P1-12（2,004 条）**：确认全部组件均为 Stage 模型（`module.json5` 含 `abilities` 声明），**属符合性提示，不产生代码改动**。建议在扫描报告中批量标记为"已确认"。
- **P1-13（132 条）**：`fontWeight`/`height` 等接口新增 `Resource` 支持属能力放宽。**机会点**：可将分散的硬编码尺寸/字重改为 `$r()` 资源，利于多端与主题化。
- **P2-14（341 条）**：API 26 起 `Dialog`/`Toast`/文本选择菜单**默认开启沉浸式系统材质**。需复核应用自绘玻璃与系统组件材质的**观感一致性**（这是沉浸光感改造的自然延伸）。
- **P2-16（49 条）**：表单类组件**触摸热区最小高度变更**，与一轮前的 40vp 热区改造**存在叠加**，需重新测量 `Button`/`Select`/`Toggle` 的实际热区。
- **P2-17（38 条）**：`Button` 默认 `type` 变为**圆角矩形**。**排查动作**：找出未显式指定 `ButtonType` 的调用点（本项目多数已显式指定 `Capsule`，风险低）。

### 3.4 建议执行顺序

```
第 1 批（阻断性，先做）：P0-1（PC 多窗）、P0-5（白板 NaN）、P0-10（账号返回值）
                        —— 均直接影响已有功能可用性
第 2 批（表现层）：      P0-2（阴影）、P0-3（动画回调）、P0-6（转场）
第 3 批（交互）：        P0-4（双指长按）、P0-7（菜单换行）、P0-9（Canvas 文本）
第 4 批（核对）：        P1-12/13 批量确认；P2 全类目目视复核
```

---

## 第四部分 · 任务 3：多端流转功能优化

### 4.1 现状评估

| 功能 | 现状 | 差距 |
|---|---|---|
| **白板** | `Whiteboard.ets` 1363 行，Canvas 绘制 + 4 笔刷 + 手势路由，已可用 | 未适配 API 26 Canvas 行为变更（P0-5/9）；无多端协同 |
| **超级终端 / 流转** | `ContinuationManager`（流转）+ `CollaborationService`（DistributedKVStore P2P）+ `HuaweiAccountService`（分布式账号）已有基础 | 未做 API 26 行为核对；未声明流转能力 |
| **碰一碰** | **完全未接入**（Share Kit / `knockShare` 引用数 0） | 需从零建设：Share Kit 集成 + 能力声明 + App Linking |

### 4.2 碰一碰（Share Kit）实施要点（已从官方文档核实）

**能力与约束**：

- 集成包：`@kit.ShareKit` 的 `harmonyShare` / `systemShare`
- 能力检测：`canIUse('SystemCapability.Collaboration.HarmonyShare')`
- 分享数据必须构建 `SharedRecord`：**文件分享必填 `uri` + `utd`；内容分享必填 `content`**
- 注册监听：`on('knockShare')`（发起）；PC/2in1 接收端可注册 `on('dataReceive')`
- 沉浸式大卡片：系统回调 `immersiveCallback`，在其中组装卡片数据
- 跨应用唤起：`App Linking` 承载参数（需在 **AppGallery Connect 创建 AppLinking** 并配置域名）
- **使用约束**：双端需**亮屏且解锁**、已开启华为分享；**手机碰 PC/2in1 需登录同一华为账号**；任一端不支持则轻碰无响应；**宿主应用无法获得分享结果**（由系统通知告知用户）

**实施步骤**：

1. `module.json5` 声明 Share Kit 所需能力与 `skills`（`entities`/`actions`）及 App Linking 域名
2. AGC 创建 AppLinking，配置域名与参数
3. 新建 `services/KnockShareService.ets`：
   - `canIUse` 能力判断 → 不支持则隐藏入口
   - 注册 `on('knockShare')`，在回调中把当前笔记/白板构建为 `SharedRecord`
   - 图标/封面通过 `immersiveCallback` 返回沉浸式大卡片
4. 在编辑器/白板页增加"碰一碰分享"入口，与华为账号登录态联动（未登录给出引导）

**验证方式**：⚠️ **必须真机双设备**（模拟器不支持碰一碰）—— 手机↔手机、手机↔PC/2in1 各测一轮，核对卡片展示、接收落地、异常提示（拒收/未登录/分享服务关闭）。

### 4.3 超级终端 / 自由流转实施要点

1. **核对 API 26 行为变更**：`ContinuationManager` 与 `CollaborationService` 逐接口核对（含 P0-10 账号返回值）
2. **能力声明**：`module.json5` 补齐流转所需 `continuation` 相关配置与权限
3. **白板多端协同**（重点）：当前白板为纯本地 Canvas。建议：
   - 复用现有 `CollaborationService`（DistributedKVStore）承载白板增量操作
   - 参考现有 OT 机制（`insert`/`delete`/`replace`）扩展到白板节点/连线
   - 参考项目已有 `.canvas`（JSON Canvas 1.0）序列化，作为同步载荷
4. **API 26 性能优化**：白板大量绘制路径是 P0-5 的高风险区，需先做 `Number.isFinite` 防护与离屏缓存

**验证方式**：真机双设备流转（接续启动参数正确、状态不丢）；白板协同需双端同时编辑，核对冲突收敛。

### 4.4 关于「使用 DevEco CLI 全面优化」的可行性说明

本轮已实际使用的 DevEco CLI 能力：

| 工具 | 用途 | 本轮使用情况 |
|---|---|---|
| `hvigorw` | 构建 | ✅ 多轮构建验证 |
| `UxTestService`（`ux_detect.py` + 20+ checker） | 官方 UX 检测 | ✅ 已提取全部阈值并用于前轮走查 |
| `dumpParser/dump-parser.exe` | 布局 dump 解析 | ✅ 已了解用途 |
| `hdc` + `uitest` | 设备控制与 UI 自动化 | ✅ 三设备走查 |
| `profiler` | 性能分析 | ⬜ 建议用于白板帧率验收 |
| `ohpm` | 依赖管理 | ⬜ 本项目无三方依赖 |

**需说明的边界**：DevEco CLI **不具备**"自动优化代码"的能力——`UxTestService` 做的是**问题检测**（输出缺陷清单），优化动作仍需人工/编码完成。因此任务 3 的"全面优化"应理解为：**用 CLI 做检测 → 按检测结果编码修复 → 再用 CLI 复测**的闭环。

---

## 第五部分 · 风险与建议

| # | 风险 | 影响 | 建议 |
|---|---|---|---|
| 1 | **沉浸光感受容器约束**，阶段二需重构导航外壳 | 高 | 阶段一的 Token 化可先行交付；阶段二单独立项，做好导航栈回归 |
| 2 | **碰一碰/流转必须真机双设备** | 高 | 模拟器无法验证；需协调两台真机（含一台 PC/2in1）与 AGC 权限 |
| 3 | API 26 扫描提示 **2,702 条易造成心理负担** | 中 | 按本报告 §3 的 18 类 / P0-P2 分层推进，**P1 的 2,004 条可直接批量确认** |
| 4 | P0-2（阴影规格）与 P0-16（热区高度）**与此前 UI 改造叠加** | 中 | 需在改动前先重测当前实际表现，避免"改到一半" |
| 5 | `modelVersion` 仍为 `6.1.1` | 低 | 确认是否需随 SDK 升至 26 对应值（需查官方版本对应表） |

---

## 附 · 本轮已完成的代码改动（4 个文件）

| 文件 | 变更 |
|---|---|
| `entry/src/main/ets/theme/MaterialTokens.ets` | **新增** —— 沉浸光感材质角色枚举、5 档 Token 表、系统材质能力探测与构造 |
| `entry/src/main/ets/components/common/GlassSurface.ets` | 接入 `materialRole`，模糊/高光/阴影由 Token 驱动；补齐按压缩放反馈 |
| `entry/src/main/ets/components/layout/MobileHeader.ets` | 顶栏材质角色 = `TOP_FLOATING`（ULTRA_THIN） |
| `entry/src/main/ets/components/layout/MobileBottomBar.ets` | 底栏材质角色 = `BOTTOM_FLOATING`（THIN） |

**构建验证**：`BUILD SUCCESSFUL`，`MaterialTokens` 已编译进产物。
