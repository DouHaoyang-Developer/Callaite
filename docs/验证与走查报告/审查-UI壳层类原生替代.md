# 审查：UI 壳层与交互域 —— 自研实现 → HarmonyOS 原生组件替代可行性

> 审查范围：导航壳、容器与滚动、分屏、浮层类、标签栏、白板、图谱、通用交互件。
> 审查方法：项目侧 grep 定位当前实现（`文件:行号`）→ SDK 侧 grep 组件/API 声明（d.ts 路径 + 行号 + `@since` + `@syscap`）→ 逐条给出可行性判定、迁移成本、真机验证项。
> 铁律：**SDK 类型面 ⊃ 设备运行时能力面**。类型能编译 ≠ 真机能用，故每条路线均附真机验证项。

---

## 0. 审查基线

### 0.1 路径图例（下文表格中一律使用简写前缀）

| 前缀 | 实际路径 |
|---|---|
| `[P]` | `F:\DevEcoStudioProjects\Callaite\entry\src\main\ets\` |
| `[C]` | `D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\build-tools\ets-loader\declarations\` |
| `[A]` | `D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\api\` |
| `[K]` | `D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\kits\` |
| `[H]` | `D:\Program Files\Huawei\DevEco Studio\sdk\default\hms\ets\` |

### 0.2 版本与设备基线（已核验）

| 项 | 值 | 证据 |
|---|---|---|
| SDK 版本 | apiVersion **26** / HarmonyOS **26.0.0.105** / Release | `sdk-pkg.json` |
| 项目 targetSdkVersion | `26.0.0` | `F:\DevEcoStudioProjects\Callaite\build-profile.json5:7`（即 `[P]..\..\..\..\build-profile.json5`） |
| 项目 compatibleSdkVersion | `26.0.0` | 同上 `:8` |
| 支持设备类型 | `phone` / `tablet` / `2in1` | `[P]..\..\module.json5:8-12` |
| 已申请权限 | 仅 `ohos.permission.DISTRIBUTED_DATASYNC` | `[P]..\..\module.json5` 的 `requestPermissions` |
| ArkUI 组件声明目录 | `[C]`（约 130 个 `*.d.ts`） | 实测存在 |
| Kit 总入口 | `[K]@kit.*.d.ts` / `[H]kits\@kit.*.d.ts` | 实测存在 |

**结论性前提**：`compatibleSdkVersion = 26.0.0` 意味着应用只安装在 API ≥ 26 的设备上，因此**`@since` 版本号在本项目内不构成任何迁移阻碍**（`@since 26.0.0` 的新 API 全部可用）。真正的阻碍只有两个：**syscap 缺失** 与 **容器作用域限制**（运行时行为）。

### 0.3 一个全局发现：`systemMaterial` 的正确入口不是 CommonMethod

项目在 `[P]components\common\GlassSurface.ets:143-147` 与 `[P]theme\MaterialTokens.ets:107-114` 记录：

> 「官方 API 参考明确其"仅在 Navigation/NavDestination 的标题栏，或横向 Tabs 的底部 TabBar 中生效"；本组件位于自研 Stack/Row 容器内，实测（API 26 模拟器）在生效范围外调用会导致首次启动 THREAD_BLOCK_6S 冻结与启动不稳定。」

本次审查在 d.ts 中定位到了**该现象的机制性解释**：

1. `[C]common.d.ts:22642` — `systemMaterial(material: SystemUiMaterial | undefined): T` 是 **CommonMethod**（任意组件可调），其文档注释**完全没有声明容器限制**。这是"陷阱入口"。
2. `[C]common.d.ts:16964` — `declare type SystemUiMaterial = import('../../../api/@ohos.arkui.uiMaterial').default.Material;`
3. **合法入口之一（标题栏）**：`[C]navigation.d.ts:1891` —
   ```
   systemMaterial?: Material;   // NavigationTitleOptions 的字段
   ```
   注释：*"Set system-styled materials for the TitleBar. Different materials have different effects, which can influence the backgroundColor, border, shadow, and other visual attributes of the titleBar."* `@since 26.0.0`，`@stagemodelonly`，`@atomicservice`，`@syscap SystemCapability.ArkUI.ArkUI.Full`。
   它只能通过 `[C]navigation.d.ts:2324` `title(value, options?: NavigationTitleOptions)` 传入；`[C]nav_destination.d.ts:622` 的 `NavDestination.title(..., options?: NavigationTitleOptions)` 同样接受它 → **NavDestination 标题栏也适用**。这与项目的表述方向一致。
4. **合法入口之二（底部浮动标签栏）**：`[C]tabs.d.ts:895` —
   ```
   systemMaterial?: UIMaterial.ImmersiveMaterial;   // FloatingTabBarStyle 的字段
   ```
   所在接口 `FloatingTabBarStyle`（`[C]tabs.d.ts:824`，`@since 26.0.0`）经 `[C]tabs.d.ts:1683` `barFloatingStyle(style: Optional<FloatingTabBarStyle>)` 施加于 `Tabs`。旁证：`[A]@ohos.arkui.uiMaterial.d.ts:365-366` 提及材质的适配能力"…of the `tabBar` of the **TabContent** component when the `BottomTabBarStyle` style is used" → 材质确实与**特定容器槽位**绑定。

**判定：项目"仅 Navigation 标题栏 / Tabs 底部栏生效"的说法方向正确，但 d.ts 层面并不完整覆盖**（例如 `BarGridColumnOptions` 等其它 `Tabs` 样式、以及 `[C]tabs.d.ts:1589 barBackgroundEffect` 等未涉及材质的属性不在其列）。且"普通组件调用触发 THREAD_BLOCK_6S"这一**运行时行为在 d.ts 中无任何文字记载**，属于项目自有实证，本次审查无法从类型面复现或证伪 → 记为**存疑**，但**采纳项目实证**作为迁移风险评估依据。

**由此推出一条低成本机会**：若目标只是"让 `systemMaterial` 合法生效"，**不需要把整个外壳迁移到 Navigation** —— 手机紧凑壳的悬浮底部胶囊栏（`[P]components\layout\MobileBottomBar.ets`，容器在 `[P]components\layout\MainContainer.ets:322-329`）正对应 `Tabs(barPosition: End)` + `barFloatingStyle({...})` 这一合法槽位。详见路线 A6 / E3。

---

## 1. 路线清单表

> 判定只用三档：**强烈推荐** / **可选** / **不建议**（括号内为理由）。

### 1.1 导航壳（`MainContainer` 自研 `Stack + Row + Column`）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| A1 | 自研外壳 `[P]components\layout\MainContainer.ets:236`(Stack 根) / `:252`(Row) / `:273`(中列 Column)；`:268-272` 已记录 Navigation 包裹失败 | `Navigation` + `NavDestination`；`[C]navigation.d.ts:122`(`NavigationMode`) / `:615`(`NavPathStack`) / `:2234`(`mode()`) / `:2324`(`title()`) / `:2594`(`navDestination()`)；syscap `SystemCapability.ArkUI.ArkUI.Full`；核心 `@since 9`，`NavPathStack` `@since 10` | **不建议**（Navigation 的槽位语义是"导航页(navBar) + 内容区(NavDestination)"的**列表-详情**模型；本项目的三栏桌面壳是"Ribbon + 左栏 + 中列(TabBar/内容/状态栏) + 右栏"平铺模型，且中列还要承载**双文档分屏**。强行套用会推翻 ContentPanes 的 `layoutWeight` 分屏模型，回归面覆盖全壳） | 极高（需重做外壳布局模型 + 全部 11 条路由 + TabBar/StatusBar 归属 + 分屏 + 沉浸式安全区避让；`[P]components\page\PageView.ets:126-153` 的 if/else 路由链需改为 `navDestination` builder） | ① 桌面 ≥600vp 下 Navigation 是否按自身模型重排子节点（项目已实测"标题栏与内容区并排"）；② 中列内嵌双 `ContentArea` 时 navBar 宽度协商结果；③ 2in1 自由多窗口缩放时 `onNavigationModeChange` 触发时机 |
| A2 | 自研历史栈 `[P]state\AppState.ets:226-231`（`callaite_historyStack` JSON + `historyBack`/`historyForward` 触发器）+ `[P]pages\..` 路由 if/else 链 | `NavPathStack`：`[C]navigation.d.ts:638` `pushPath` / `:651` `pushPath(info, options?)` / `:723` `pushPathByName` / `:1002` `popToName(name, animated?)` / `:1019` `popToName(name, result, animated?)`；`@since 10/11/12` | **可选**（仅取"返回栈"能力也要先有 Navigation 实例，即依赖 A1；但 `NavPathStack` 可独立引入用于**深链与回退**的语义统一，收益是省掉自研栈的边界 bug，代价是双栈并存期的状态同步） | 中（若 A1 不迁移，则只能在 Spike 分支验证 `NavPathStack` 行为，无法真正落地） | ① `pushPathByName` 的 `onPop` 回调在页面销毁时的触发完整性；② 返回栈与应用自研历史栈双写时的顺序一致性 |
| A3 | 无深链/无外部路由入口（`EntryAbility.ets:107` 仅 `loadContent('pages/Index')`） | `NavPathStack` + 命名路由；`[C]navigation.d.ts:723` `pushPathByName(name, param, animated?)`；上下文查询 `[C]common.d.ts:24764` `queryNavigationInfo()` / `:24738` `queryNavDestinationInfo()`；类型 `[C]common.d.ts:24330`(`NavDestinationInfo`) / `:24341`(`NavigationInfo`) | **可选**（深链是本项目当前**完全缺失**的能力，不是"替代"而是"新增"；若产品要支持"从系统分享/通知直达某页面"，`pushPathByName` 是最短路径） | 中 | ① `ShareReceiveAbility`（`[P]shareability\ShareReceiveAbility.ets`）冷启动拉起的路由是否落在 Navigation 已构建之后；② `queryNavigationInfo()` 在非 Navigation 容器下的返回（文档注明"has effect only when the component is contained within…"） |
| A4 | 无系统返回键/侧滑返回处理（`MainContainer` 全局 `onKeyPreIme` 仅在 `[P]components\page\ContentArea.ets:159-169` 处理修饰键） | `NavDestination` 的返回语义 + `[C]navigation.d.ts:2716` `recoverable()`；`[C]tabs.d.ts:1573` 顺带发现 `List.backPressBehavior`（`[C]list.d.ts:1573`） | **不建议**（当前手机壳用自绘顶栏 + 胶囊栏，"系统返回"语义尚未定义；在 A1 未迁移的前提下引入是"半套机制"，反而制造两套返回逻辑） | 低（但语义不闭合） | ① 手机壳下侧滑返回与 `FloatingPanel` 遮罩点击关闭的优先级；② 分屏副窗格是否应参与返回栈 |
| A5 | 断点自适应 `[P]components\layout\MainContainer.ets:97-109`(`applyViewportWidth`) + `:78-87`(`syncViewportWidth`) + `:119-134`(`initViewportFromWindow`)；复用 `[P]state\Breakpoints.ets` | `NavigationMode`：`[C]navigation.d.ts:131` `Stack`(`@since 9`) / `:159` `Split`(`@since 9`) / `:172` `Auto`(`@since 9`，宽 ≥600vp 走 Split) / `:184` `AUTO_WITH_ASPECT_RATIO`(`@since 24`)；`[C]navigation.d.ts:2163` `navBarWidth()` / `:2204` `navBarWidthRange()` / `:2222` `minContentWidth()` / `:2577` `onNavigationModeChange()` / `:2729` `enableDragBar()` | **不建议**（`Split` 的分割对象是**导航页 vs 内容区**，而项目分屏的分割对象是**两个同级文档窗格**；`[C]navigation.d.ts:159` 的注释明确 `Split` 的分隔条"drag 2 vp each side"、且"single page in content area 时不显示返回键"——语义完全不同，无法表达"左文档 / 右文档"。且项目已在 `:90-96` 注释说明断点必须取自**组件实际宽度**（`onAreaChange`）而非 display，Navigation 的 `Auto` 取窗口宽度，二者会在 2in1 自由窗口下产生分歧） | 高（若迁移等于放弃现有分屏语义） | ① 2in1 窗口拖窄到 599vp 时 `Auto` 的切换是否与 `Breakpoints.SM_MAX` 一致；② `navBarWidthRange` 与项目 `SIDEBAR_MIN=180 / SIDEBAR_MAX=480`（`MainContainer.ets:25-26`）是否冲突 |
| A6 | 系统材质被刻意禁用：`[P]components\common\GlassSurface.ets:143-147`、`[P]theme\MaterialTokens.ets:107-114`；兜底走 `backgroundBlurStyle` + `backgroundEffect`（`GlassSurface.ets:150-161`） | 两个合法入口：① `[C]navigation.d.ts:1891` `NavigationTitleOptions.systemMaterial`（经 `:2324` `title(value, options?)`）；② `[C]tabs.d.ts:895` `FloatingTabBarStyle.systemMaterial`（经 `:1683` `barFloatingStyle()`）；材质对象 `[A]@ohos.arkui.uiMaterial.d.ts:503` `class ImmersiveMaterial extends Material` / `:465` `class Material` / `:43` `enum MaterialType`；均 `@since 26.0.0`，syscap `SystemCapability.ArkUI.ArkUI.Full` | **强烈推荐（限定形态）**（**不要**为材质迁全壳；只在**手机紧凑壳的底部胶囊栏**改用 `Tabs(barPosition: End)` + `barFloatingStyle({systemMaterial})`。这是 d.ts 层面唯一可低成本命中的材质槽位，且项目已有该形态的自研版本可比对视觉）；**通用节点上的 CommonMethod `.systemMaterial()` 严禁启用**（`[C]common.d.ts:22642` 类型允许但项目实测 THREAD_BLOCK_6S） | 中（限手机紧凑壳：`MobileBottomBar` 由"导航工具条"改造为 `Tabs` 底栏，见 E3） | ① 真机（非模拟器）`barFloatingStyle` + `systemMaterial` 是否无冻结；② `ImmersiveMaterial` 在低算力设备是否降级（`[A]@ohos.arkui.uiMaterial.d.ts` 多处注明"takes effect only for…devices with high- and mid-level computing power"）；③ 与项目 `GlassSurface` 兜底视觉是否可接受地接近 |

### 1.2 容器与滚动（`ContentArea` 的 `Scroll` + `BlockList` 的 `Stack→Column→LazyForEach`）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| B1 | **`LazyForEach` 位于普通 `Column` 内** → 虚拟化不生效：`[P]components\outliner\BlockList.ets:101`(`Stack`) / `:102`(`Column`) / `:113`(`LazyForEach`)；数据源 `:16-51`；刷新入口 `:85-87`(`onBlocksVersionChanged`) / `:89-98`(`refreshBlocks`，每次 `onDataReloaded()` 全量重载) | `List` + `ListItem` + `LazyForEach`：`[C]list.d.ts:915`(`ListAttribute`) / `:1195`(`cachedCount`)，syscap `SystemCapability.ArkUI.ArkUI.Full`，`List` `@since 7`；**虚拟化的硬前提见 `[C]lazy_for_each.d.ts:878` `LazyForEachInterface`，`:881-883` 明文**：*"When **LazyForEach** is used in a scrolling container, the framework creates components as required within the visible area of the scrolling container. When a component is out of the visible area, the framework destroys and reclaims the component"* → **非滚动容器内不回收** | **强烈推荐**（本项目 UI 域收益最大的一条：当前 1000 块页面会**一次性构建并常驻全部节点**，`LazyForEach` 的收益被容器选择完全抵消。换成 `List` 后同一份 `IDataSource` 立即获得回收 + `cachedCount` 预取。同时消掉 `Scroll`(ContentArea) 与 `Column`(BlockList) 的嵌套滚动歧义） | 中（`LazyForEach` 的直接子节点必须是 `ListItem`，需在 `BlockList.ets:113-123` 外包一层 `ListItem`；`Scroll`(`ContentArea.ets:71-86`) 需让位给 `List` 自身的滚动，`ContentArea` 的 `focusControl.requestFocus('contentAreaScroll')`(`:46`) 与 `.defaultFocus(true)`(`:79`) 要改挂到 `List`） | ① 迁移后 `[P]components\outliner\BlockDragHandler.ets` 的 `Stack.position` 手工拖拽在 `List` 内是否仍跟随手指（`List` 会裁剪子节点）；② `blocksVersion` 自增触发的 `onDataReloaded()` 是否导致 `List` 滚动位置跳回顶部；③ 分屏双 `List` 时两个 `Scroller` 的 `id` 隔离 |
| B2 | `ContentArea` 外层 `Scroll`：`[P]components\page\ContentArea.ets:71-86`（`:76` `scrollBar(BarState.Auto)` / `:77` `align(Alignment.TopStart)` / `:80` `.id(scrollId())`） | `Scroll` + `Scroller`：`[C]scroll.d.ts:351`(`Scroller`) / `:379`(`scrollTo`) / `:533`(`scrollToIndex(value, smooth?, align?, options?)`) / `:467`(`currentOffset`) / `:930`(`scrollable`) / `:1034`(`onWillScroll`) / `:1053`(`onDidScroll`) / `:1305`(`nestedScroll`) / `:1350`(`scrollSnap`)；`@since 7-12`，syscap `SystemCapability.ArkUI.ArkUI.Full` | **可选**（`Scroll` 本身用法正确；**若采纳 B1 则应删除此 `Scroll`**，改为把 `Scroller` 直接交给 `List`。保留 `Scroll` 会形成 `Scroll > PageView > BlockList-List` 的双层滚动，`nestedScroll` 需显式配置） | 低（B1 的附带动作） | ① 双层滚动嵌套下的惯性传递；② `onKeyEvent`(`ContentArea.ets:81-86`) 挂在 `Scroll` 上，迁移后需重新绑定到 `List` 并验证快捷键不失效 |
| B3 | 大纲缩进为**递归组件**而非容器能力：`[P]components\outliner\BlockChildren.ets:55`(`ForEach`) / `:62`(自递归)，子块列表来自 `:46` `ws.getChildrenOfBlock()` | `List` + `ListItemGroup`（原生分组/缩进/吸顶）：`[C]list.d.ts:1328` `sticky(value: StickyStyle)`（`@since 9`，注释：作用于 `ListItemGroup` 的 header/footer；`StickyStyle.BOTH` 自 API 20 起）；`[C]list.d.ts:178` `declare enum StickyStyle`（`:201 Header=1`、`:212 Footer=2`）；`[C]list.d.ts:560` `scrollToItemInGroup(index, indexInGroup, smooth?, align?)`；`[C]list.d.ts:1423` `childrenMainSize()` | **可选**（`ListItemGroup` 能表达"一层分组"，但本项目大纲是**任意深度递归**，扁平化成"分组套分组"需要把树预展开为一维序列 + 深度标注，收益是吸顶与 `scrollToItemInGroup` 定位。**若产品不需要"父块吸顶"，则收益不足以抵消重构**） | 高（需把 `BlockChildren` 的递归模型改为"预展开扁平序列 + `ListItemGroup` 嵌套或单层分组"，触及 `[P]core\engine\BlockTree.ets` 的读取路径） | ① `StickyStyle` 与折叠态（`collapsed`）联动时吸顶项是否残留在错误层级；② `scrollToItemInGroup` 在深度 >5 时的定位精度 |
| B4 | 页内搜索条浮在列表顶部：`[P]components\outliner\BlockList.ets:103-106`(`FindInPage`)，位于 `Column` 内、随内容滚动 | `List.sticky(StickyStyle.Header)`（同 B3）+ `ListItemGroup` header | **可选**（当前用"浮动在顶部"的 `Stack` 定位规避；改 `List` 后可用原生吸顶，但需先将列表分组） | 低（依赖 B3 决定） | ① 吸顶 header 与 `FindInPage` 的命中区重叠 |
| B5 | 标签栏横向滚动自研：`[P]components\layout\TabBar.ets:124-140`（`Scroll` + `Row` + `.scrollable(ScrollDirection.Horizontal)` + `ForEach`(`:131`)） | `Scroll.scrollable(ScrollDirection.Horizontal)`（当前已用）或 `List`（横向）+ `Tabs` 见 E1 | **可选**（当前实现无虚拟化，但标签数通常 <20，无实际损失；真正缺失的是"激活标签自动滚入视口"） | 低 | ① 新增标签后激活项是否在视口外（当前无 `scrollTo` 调用，见 `[P]components\layout\TabBar.ets` 全文无 `Scroller`） |
| B6 | 无下拉刷新；`Refresh` 未使用 | `Refresh`：`[C]refresh.d.ts:281`(`RefreshAttribute`) / `:293`(`onStateChange`) / `:305`(`onRefreshing`) / `:320`&`:337`(`refreshOffset`) / `:352`(`pullToRefresh`) / `:383`(`onOffsetChange`) / `:400`(`pullDownRatio`)；syscap `SystemCapability.ArkUI.ArkUI.Full` | **可选**（属于**能力新增**而非替代；`[P]services\CloudSyncService.ets` 已存在同步入口，`Refresh` 是自然的手势载体） | 低-中 | ① `Refresh` 与 B1 的 `List` 嵌套时的手势冲突（`pullToRefresh`/`pullDownRatio` 调参） |
| B7 | 卡片网格用 `Scroll + Flex(wrap)`：`[P]components\layout\TabOverviewSheet.ets:47-49` | `Grid` + `GridItem`：`[C]grid.d.ts:561`(`onScrollIndex`)；**`Grid` 无 `sticky`**（实测 `grid.d.ts` 中 `sticky` 命中数 = 0） | **不建议**（`Flex(wrap)` 已是 `Scroll` 内的等价网格，`Grid` 需引入固定列数/`GridItem` 包装，收益仅"虚拟化"，而标签卡片数量级小） | 低 | —— |
| B8 | 分栏/瀑布流均未使用 | `WaterFlow`：`[C]water_flow.d.ts:679`&`:705`(`cachedCount`) / `:817`(`onScrollIndex`) / `:428`(`setOnScrollIndex`)；`Grid.lanes` `[C]list.d.ts:948`&`:972`（实为 `List.lanes` 重载） | **不建议**（"块列表 + 大纲缩进"是**单列纵向**结构，`WaterFlow`/多列 `lanes` 与大纲语义冲突，纯属误配） | —— | —— |

### 1.3 分屏（自研 `SplitDivider` + 副窗格）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| C1 | 内容区双窗格自研：`[P]components\layout\MainContainer.ets:210-233`(`ContentPanes` @Builder，`Row` + 两个 `ContentArea` + `layoutWeight`)；权重换算 `:198-205` | `NavigationMode.Split`：`[C]navigation.d.ts:159`（`@since 9`）；`[C]navigation.d.ts:2163` `navBarWidth()` / `:2204` `navBarWidthRange()` / `:2222` `minContentWidth()` / `:2729` `enableDragBar()` / `:2769` `splitPlaceholder()` | **不建议**（语义错配已在 A5 说明：`Split` 分的是"导航页 / 内容区"，不是"两个同级文档"。项目需要的是"两个可各自独立导航的编辑器窗格"，`Navigation` 无法表达第二个窗格的**路由独立性**——副窗格靠 `pageOverride`（`[P]components\page\ContentArea.ets:28` `@Prop pageOverride`）注入独立路由，该机制在 Navigation 模型下无对应物） | 极高 | ① 若强迁，副窗格能否拥有独立 `NavPathStack`（d.ts 未提供多栈 API，`MultiNavPathStack` 出现在 `[K]@kit.ArkUI.d.ts` 导出列表中，语义未验证 → 存疑） |
| C2 | 自研 `SplitDivider`：`[P]components\layout\SplitDivider.ets:41-82`（`:52` 热区 10vp / `:60-77` `PanGesture({direction: Horizontal, distance:1})` + `:57 onHover` + `:78-81 onClick` 复位 50%）；比例快照防二次累加见 `:20-26` 注释 | `SideBarContainer` 的 `divider(DividerStyle)`：`[C]sidebar.d.ts:381`(`SideBarContainerAttribute`) / `:396`(`showSideBar`) / `:407`(`controlButton(ButtonStyle)`) / `:419`(`showControlButton`) / `:436`(`onChange`) / `:453`&`:506`(`sideBarWidth`) / `:471`&`:525`(`minSideBarWidth`) / `:488`&`:544`(`maxSideBarWidth`) / `:562`(`autoHide`) / `:573`(`sideBarPosition`) / `:587`(`divider`) / `:623`(`minContentWidth`)；`[C]sidebar.d.ts:27` `SideBarContainerType`；主 API `@since 8`，`Length` 重载 `@since 9`，`divider`/`minContentWidth` `@since 10`，另有 `@since 26.0.0` 新增（`sidebar.d.ts:80`、`:636`）；syscap `SystemCapability.ArkUI.ArkUI.Full` | **可选（分场景）**：<br>· 用于**左右侧栏**（`LeftSidebar`/`RightSidebar` 的拖拽调宽）→ **可选**，`SideBarContainer` 原生提供拖拽分隔条 + `minSideBarWidth/maxSideBarWidth` 夹取 + `autoHide`，可省掉 `MainContainer.ets:423-472` 的 `Resizer` @Builder；<br>· 用于**内容区双文档分屏** → **不建议**（`SideBarContainer` 的语义是"侧栏 + 主内容"非对称两栏，两个窗格无法各自独立换路由） | 中（侧栏场景）；无（分屏场景） | ① `showControlButton` 默认值需显式关闭（否则出现系统默认折叠按钮与自研 Ribbon 冲突）；② `autoHide` 在紧凑壳下与 `MainContainer.ets:104-107` 的"桌面→紧凑复位语义"是否打架；③ 原生 `divider` 的分隔条宽度与项目 10vp 热区（`:52`）的视觉差异 |
| C3 | 分屏副窗格页面选择器：`[P]components\layout\TabBar.ets:170-182`(`Select` + `pageOptions`/`pageRoutes` 双数组映射)；可选路由白名单 `:19-20` | 无原生替代（`Select` 已是原生控件） | **不建议**（该处已是原生 `Select`，问题在数据建模而非组件选型） | —— | —— |

### 1.4 浮层类（命令面板 / 新建 / 导出导入 / 仓库切换 / 侧栏 / 更多菜单 / 标签总览）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| D1 | 命令面板：`[P]components\commandpalette\CommandPalette.ets:38-95`（`Scroll` + `Column` + `ForEach(this.results.slice(0,15))`），遮罩与卡片定位在 `[P]components\page\ContentArea.ets:94-125`（`:99` `rgba(0,0,0,0.35)` 遮罩 + `:112` `shadow` + `:113` `border`） | `bindContentCover(isShow, builder, options?: ContentCoverOptions)`：`[C]common.d.ts:21628`；`[C]common.d.ts:11379` `ContentCoverOptions extends BindOptions` / `:11412` `onWillDismiss`；`ModalTransition` `[C]common.d.ts:6911`（`:6922 DEFAULT` / `:6932 NONE` / `:6942 ALPHA`，`@since 10`） | **不建议**（本项目命令面板是**顶部居中的无边距卡片**（`ContentArea.ets:107-113`：宽 92%/上限 560vp/高 420vp），而 `bindContentCover` 是**全屏模态**语义，视觉目标不符；且 `CommandPalette` 真正的缺陷是**键盘导航缺失**——`[P]components\commandpalette\CommandPalette.ets:108-135` 的 `KeyHintFooter` 声明了"↑↓ 选择 / ↵ 打开"，但全文件**无 `onKeyEvent`、无 selectedIndex、无 `defaultFocus`**，改浮层宿主不会修复该缺陷） | —— | ① `ContentArea.ets:79` 的 `.defaultFocus(true)` 与命令面板 `TextInput`（`CommandPalette.ets:22`，无 `defaultFocus`）的焦点竞争——打开面板后输入框是否真的持焦 |
| D2 | 新建三选项对话框（自绘模态）：`[P]components\common\NewFileDialog.ets:131-196`（`:133` Stack 居中 / `:135-141` 遮罩 / `:190-191` `86%`+`maxWidth 380`） | `promptAction.openCustomDialog` / `UIContext.presentCustomDialog`：`[A]@ohos.promptAction.d.ts:1990` `openCustomDialog(options): Promise<number>`（`@since 11`）/ `:1274` `CustomDialogOptions extends BaseDialogOptions`；`[A]@ohos.arkui.UIContext.d.ts:973` `openCustomDialog` / `:997` `presentCustomDialog(builder, controller?, options?)`（`@since 18`）/ `:1013` `closeCustomDialog(dialogId)`；或 `bindContentCover`（同 D1） | **可选**（`presentCustomDialog(builder, ...)` @since 18 可直接吃 `CustomBuilder`，且自带遮罩/居中/进出场，能删掉 `:135-141` 的手写遮罩与 `:26-28` 的手写 open 状态机；代价是失去对"卡片精确尺寸"的完全控制，需改用 dialog options） | 低-中（`AppStorage('callaite_newFileDialogOpen')` 开关需改为 dialogId 生命周期；`[P]state\AppState.ets:217-224` 的相关键需梳理） | ① `openCustomDialog` 返回的 `dialogId` 在页面重建后是否失效；② 遮罩点击关闭（现 `:139-141`）与 `options` 的 `autoCancel` 语义是否等价 |
| D3 | 仓库切换器（自绘深色大模态）：`[P]components\common\VaultSwitcherDialog.ets:29-...`（`:31` Stack 居中 / `:32-38` `rgba(0,0,0,0.55)` 遮罩 / `:41` 左右双栏 Row） | 同 D2（`presentCustomDialog` / `bindContentCover`）；若走 `bindSheet` 则见 D6 | **可选**（同 D2；本项目此模态是"左右双栏大卡片"，更适合 `bindContentCover` + `ModalTransition.ALPHA` 而非底部 sheet） | 低-中 | ① 深色固定配色（`:23-27`）在模态内是否被系统主题覆盖 |
| D4 | 导出/导入对话框：`[P]components\page\ContentArea.ets:127-153`（两个自绘遮罩 + 居中 Dialog 组件），组件本体 `[P]components\common\ExportDialog.ets` / `[P]components\common\ImportDialog.ets` | 同 D2；文件选择侧可另用 `@kit.CoreFileKit` 的 picker（本次未展开核验） | **可选** | 低-中 | ① 导入流程中的文件选择器返回与对话框关闭的时序 |
| D5 | 左右侧边悬浮面板（**已明确否决 `bindSheet`**）：`[P]components\common\FloatingPanel.ets:39-98`（`:42-51` 遮罩 / `:54-74` `Row` + 四边留白 / `:80-98` `Panel` @Builder，`84%` + `maxWidth` + `borderRadius(20)` + `TransitionEffect.asymmetric`）；调用点 `[P]components\layout\MainContainer.ets:336-360`，否决理由见 `:337` 与 `FloatingPanel.ets:4-17` | **`bindSheet` + `SheetType.SIDE`**：`[C]common.d.ts:21649` `bindSheet(isShow, builder, options?: SheetOptions)`；`SheetType` `[C]common.d.ts:11477` → **`:11517 SIDE = 3`（`@since 20`）**，其余 `BOTTOM=11487`/`CENTER=11497`/`POPUP=11507`（`@since 11`）；`SheetOptions` `[C]common.d.ts:11753` → `:11833 preferType?: SheetType` / `:11785 maskColor` / `:11810 blurStyle` / `:11821 showClose` / `:11884 enableOutsideInteractive` / `:11944 onHeightDidChange` / `:11976 onDetentsDidChange` / `:11795 detents` / `:11853 shouldDismiss`；`SheetSize` `[C]common.d.ts:7947`（`MEDIUM`/`LARGE`/`FIT_CONTENT`）；亦可用 `UIContext.openBindSheet(content, options?, targetId)`（`[A]@ohos.arkui.UIContext.d.ts:5323`，`@since 12`） | **可选 / 需重新评估**（项目的否决理由（"铺满整屏、贴底、仅顶部圆角"）**只在 `SheetType.BOTTOM` 下成立**。`SheetType.SIDE`（`@since 20`，本项目 compatibleSdkVersion=26 → 可用）正是"侧边 sheet"语义，与 `FloatingPanel` 目标一致。迁移收益：原生遮罩、拖拽/detents、`onWillDismiss`、系统返回键联动、无障碍，可删掉 `FloatingPanel.ets:42-51` 手写遮罩与 `:92-97` 手写 transition） | 中（需重新验证 SIDE 的宽度约束是否满足官方 PopupSizeChecker 的"宽度占屏 ≤0.95、四边留白、距底 ≥10vp"，见 `FloatingPanel.ets:11-16` 自述约束；`[A]@ohos.arkui.UIContext.d.ts:5300-5302` 提示 `openBindSheet` 下 `preferType` 不能为 `POPUP`、`mode=EMBEDDED` 需 `targetId`） | ① `SheetType.SIDE` 真机（phone/tablet/2in1）宽度与圆角是否可控；② `bindSheet` 初始绑定竞态是否复现 `[P]state\AppState.ets:195` 记录的"抽屉打开后立即关闭"（该注释即为历史踩坑）；③ 与 `safeTop/safeBottom`（`FloatingPanel.ets:32-33`）的避让是否仍由应用负责 |
| D6 | "更多"底部菜单（**拖动指示条是装饰性的**）：`[P]components\layout\MobileMenuSheet.ets:120-150`；`:122-128` 画了 36×4 的拖动指示条但**全文件无任何拖拽手势**；呈现方式为 `MainContainer.ets:391-410` 的手写遮罩 + `TransitionEffect.asymmetric` translate | `bindSheet(isShow, builder, options)`（同 D5），`SheetType.BOTTOM`（默认）+ `detents` + `SheetSize.FIT_CONTENT`：`[C]common.d.ts:7947`(`SheetSize`) / `:11795`(`detents`) / `:11976`(`onDetentsDidChange`) / `:11944`(`onHeightDidChange`) / `:11853`(`shouldDismiss`) / `:11821`(`showClose`) | **强烈推荐**（这是本项目**语义最贴合**的一处：自研组件已经画出了 sheet 的外观（顶部圆角 24、拖动指示条、分组行高 52），却**没有真实的拖拽/detents/高度回调**——指示条是"假"的。`bindSheet` 一次补齐拖拽、吸附档位、下滑关闭、遮罩与系统返回键，且可删掉 `MainContainer.ets:391-410` 的手写遮罩 + transition） | 低-中（`MobileMenuSheet.ets:55-57` 的 `close()` 改为 `isShow` 绑定；`AppStorage('callaite_mobileMenuOpen')` 语义保留为 `isShow`） | ① `detents` 三档的实际吸附点与行数（3 组 9 行 ≈ 高度）是否匹配；② `bindSheet` 在紧凑壳（`MainContainer.ets:306-334` 的浮层层级）中是否被 `MobileHeader`/`MobileBottomBar` 遮挡（z 序）；③ `SheetType.BOTTOM` 的"宽度铺满整屏"是否可接受（本组件设为全宽，故无异议） |
| D7 | 标签总览卡片面板（自绘底部滑入）：`[P]components\layout\TabOverviewSheet.ets:44-...`（`:47` Scroll + `:48` Flex wrap），呈现于 `MainContainer.ets:369-388`（含手写遮罩 + `TransitionEffect.translate({y:320})`） | `bindSheet`（同 D6，宜 `SheetSize.LARGE` 或 `detents`）；卡片网格本体见 B7 | **可选**（面板本体视觉是"卡片墙 + 底部操作条"，`bindSheet` 可承接容器语义；但本组件内部布局不动） | 低-中 | ① `SheetSize.LARGE` 与卡片墙滚动（`:47` 的 `Scroll`）形成 sheet 内滚动，`nestedScroll` 行为 |
| D8 | 命令面板 / 菜单的**右键与长按**绑定：仅探针页有代码 —— `[P]pages\SpikeHarness.ets:145-154`（`:153` `bindContextMenu(..., ResponseType.RightClick)` 与 `:154` `bindContextMenu(..., ResponseType.LongPress)` **同一节点链式双绑**）；正式代码中 `bindContextMenu` **零使用** | `bindContextMenu` 家族：`[C]common.d.ts:21495` `bindContextMenu(content: CustomBuilder, responseType: ResponseType, options?)`（`@since 8`；文档注：*"Only custom menu items are supported"*）；**`:21526` `bindContextMenuWithResponse(content: CustomBuilderT<ResponseType> \| undefined, options?)`（`@since 23`）**；**`:21541` 同签名 + `Array<MenuElement>` 重载（`@since 26.0.0`）**；**`:21511` `bindContextMenuByResponseType(content, responseType, options?)`（`@since 26.0.0`）**；`[C]common.d.ts:22841` `declare type CustomBuilderT<T> = (t: T) => void;`；`ResponseType` `[C]enums.d.ts:2979`（`RightClick=2989`、`LongPress=2999`，均 `@since 8`）；`ContextMenuOptions` `[C]common.d.ts:14963` | **强烈推荐（但先取证据）**（`:21526` `bindContextMenuWithResponse` 的 `CustomBuilderT<ResponseType>` **正是为"同一节点按触发方式分流"设计的官方形态**：一次绑定，builder 收到 `ResponseType` 后自行分支，从根本上绕开"链式双绑是否互相覆盖"的不确定性。项目已在 `SpikeHarness.ets:12` 把双绑列为待验证项 ③；建议**先用 `SpikeHarness` 采到结论，再决定**：若双绑可用 → 保守不动；若互相覆盖 → 直接改用 `bindContextMenuWithResponse`） | 低（`PageContextMenu` 已是独立组件，改绑定方式不动内部） | ① `SpikeHarness.ets:153-154` 链式双绑的实际行为（目视菜单文案 `MENU:RightClick` / `MENU:LongPress`，`SpikeHarness.ets:28` `menuHit` 预留了状态位但 `:129` 的展示与 `:118-122` 的 builder **未回写** `menuHit`，需补一行赋值才能自动化采集）；② `bindContextMenuWithResponse` 的 `CustomBuilderT` 在 ArkTS 严格模式下能否直接传 `@Builder`（`@Builder` 无返回值，与 `(t: T) => void` 的兼容性）；③ 文档注"Long pressing with a mouse device is not supported"（`[C]common.d.ts:21486-21487`）在 2in1 触控屏设备上的实际表现 |
| D9 | 上下文菜单本体（自绘浮动定位）：`[P]components\sidebar\PageContextMenu.ets:24-...`（`:212` `ForEach(getMenuItems())`，`:42-87` 6 项，`:120` 起为动作分发） | 作为 `bindContextMenu` 的 `CustomBuilder` 内容（保留本体）；或 `Menu`/`MenuItem`/`MenuItemGroup` + `bindMenu`（现仅 `[P]components\layout\TabBar.ets:121` 一处使用，`:229-250` 的 `TabsMenu` @Builder） | **可选**（`PageContextMenu` 的定位/关闭逻辑（点击外部关闭、`:28-29` `positionX/positionY`）正是 `bindContextMenu` 内建能力；迁移可删掉手写定位与"点击外部关闭"） | 低 | ① 菜单位置自动避让屏幕边缘（当前手算 `positionX/positionY`）是否被原生 placement 正确接管 |
| D10 | 侧栏切换手势/悬浮提示缺失：全项目 `bindPopup`/`bindTips` **零使用**（`grep` 实测） | `bindPopup` `[C]common.d.ts:21452`（`PopupOptions` `:13177`，`@since 7`；`placement` `@since 10`，`placementOnTop` `@since 7`/`@deprecated since 10`）；`bindTips` `[C]common.d.ts:21434`（`TipsOptions` `[C]common.d.ts:13009`） | **可选**（属于**能力新增**：桌面端 Ribbon/工具栏按钮目前无文字提示，`bindTips`/`bindPopup` 是零成本补齐） | 低 | ① `bindTips` 的 `@since` 与 syscap（本次未逐行核验，见存疑项 4.4）；② 鼠标 hover 触发时机（`bindTips` 的触发条件是 hover 还是长按需核实） |

### 1.5 标签栏（`TabBar.ets` 自研）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| E1 | 桌面标签栏自研：`[P]components\layout\TabBar.ets:99-222`；`:131` 顶层 `ForEach`；`:271-352` `TabItemView`（已做子组件化修复，**不变式见 `:254-270` 注释**：`ForEach` 键只含数据身份 `tab.id`，不携带 UI 态）；标签内容区为 `if/else` 路由（`[P]components\page\PageView.ets:126-153`）而非 `Tabs` | `Tabs` + `TabContent`：`[C]tabs.d.ts:1025`(`TabsAttribute`) / `:1054`(`barPosition`) / `:1066`(`scrollable`) / `:1079`&`:1095`&`:1108`(`barMode`) / `:1313`(`onChange`) / `:1355`(`onTabBarClick`) / `:1452`(`divider`) / `:1467`(`barOverlap`) / `:1479`(`barBackgroundColor`) / `:1548`&`:1576`(`barBackgroundBlurStyle`) / `:1589`(`barBackgroundEffect`) / `:1605`(`cachedMaxCount`) / `:1636`(`onContentWillChange`)；`[C]tabs.d.ts:147` `BarPosition`（`:157 Start` / `:167 End`，`@since 7`）；`[C]tab_content.d.ts:905`(`TabContentAttribute`) / `:926`&`:952`&`:976`(`tabBar` 三重载，支持 `CustomBuilder` → 可直接复用 `TabItemView` 视觉) / `:993`(`onWillShow`) / `:1010`(`onWillHide`)；`@since 7-12`，syscap `SystemCapability.ArkUI.ArkUI.Full` | **可选（收益低于直觉，代价高于直觉）**：<br>**关键反驳"TabContent 切换即销毁"的顾虑**：`[C]tabs.d.ts:1591-1592` 明确 *"If this attribute is not set, **all child components are cached by default and are not released after being cached**"* —— 默认行为是**全缓存不释放**，不会丢编辑器状态。<br>**收益**：① 横向滑动切页手势；② `barMode.Scrollable`(`:1095`) 原生标签滚动 + 激活项自动入视口（当前 `TabBar.ets:124-140` 无 `Scroller`，缺此能力）；③ `onContentWillChange`(`:1636`) 可在切页前拦截（未保存内容提示）。<br>**代价**：① 每个 `TabContent` 承载一个编辑器（含 `Canvas`/ArkWeb/`TextInput`），默认"全缓存不释放"意味着**N 个标签 = N 份常驻树**，内存随标签数线性增长——比当前 `if/else` 只构建一个页面**更差**；② 需显式 `cachedMaxCount(n, mode)`（`:1605`，`@since 19`）把默认行为改掉，而 `TabsCacheMode`（`[C]tabs.d.ts:229`，`:240 CACHE_BOTH_SIDE`=2n+1 / `:251 CACHE_LATEST_SWITCHED`=n+1）一旦生效就会**销毁**非缓存页 → 又回到"编辑器状态丢失"问题，需要用 `onWillHide`/`onWillShow` + 外部状态持久化兜底 | 高（标签内容区从 `if/else` 改为 `TabContent`，触及全部 11 条路由；且必须重做"编辑器状态外置"才能安全启用缓存上限） | ① `cachedMaxCount` 生效后 `TextInput` 光标/选区/输入法状态是否丢失；② `Canvas`/`Web` 组件在 `TabContent` 销毁重建后的 `onReady` 重入；③ `onWillShow`/`onWillHide` 与 `[P]components\page\ContentArea.ets:42-48` 的焦点抢占（`focusControl.requestFocus('contentAreaScroll')`）时序冲突 |
| E2 | 标签栏高度/热区硬编码：`[P]components\layout\TabBar.ets:218` `.height(40)`（`:215-217` 注释说明"此处是唯一高度定义处"）、`:327` 页签 `.height(40)`、`:329` `.constraintSize({minWidth:88, maxWidth:220})`、`:299` 文本 `maxWidth:156`、`:312` `responseRegion` 扩到 40vp | `barHeight`：`[C]tabs.d.ts:1174` `barHeight(value: Length)`、`:1201` `barHeight(height, noMinHeightLimit: boolean)`；`barMode` `:1079`/`:1095`(`ScrollableBarModeOptions`)；`barWidth` `:1137` | **可选**（若不做 E1，则与此项无关；若做 E1，`barHeight`/`barWidth` 可替代硬编码并消除 `:215-217` 的"唯一高度定义处"脆弱不变式） | 低（依附 E1） | ① `barHeight` 的最小高度限制与 40vp 的兼容（`noMinHeightLimit` 参数的存在即暗示默认有下限） |
| E3 | 手机紧凑壳底部悬浮胶囊栏：`[P]components\layout\MobileBottomBar.ets`（`:31-56` `PillIcon` @Builder，44×44 热区；`:8-14` 自述"悬浮玻璃胶囊栏、距底 34vp、占视口 92% 上限 336vp"）；容器 `[P]components\layout\MainContainer.ets:322-329` | `Tabs(barPosition: BarPosition.End)` + **`barFloatingStyle(FloatingTabBarStyle)`**：`[C]tabs.d.ts:1683` `barFloatingStyle(style: Optional<FloatingTabBarStyle>)`；`FloatingTabBarStyle` `[C]tabs.d.ts:824`（`@since 26.0.0`，`@stagemodelonly`/`@crossplatform`/`@atomicservice`，syscap `SystemCapability.ArkUI.ArkUI.Full`）→ `:834 barWidth?: FloatingTabBarWidth` / `:844 barSideMargin?: Length` / `:854 barBottomMargin?: Length` / `:864 maskColor?` / `:874 maskHeight?` / `:885 adaptToHandedness?` / **`:895 systemMaterial?: UIMaterial.ImmersiveMaterial`** | **强烈推荐（形态改造）**（这是 d.ts 层面**唯一**能让 `systemMaterial` 合法生效且与项目现有视觉（悬浮胶囊 + 圆角 + 遮罩 + 侧边距 + 距底距离）**逐字段对应**的槽位；`FloatingTabBarStyle` 的 `barSideMargin`/`barBottomMargin`/`barWidth` 正对应 `MobileBottomBar` 自述的"占视口 92%、上限 336vp、距底 34vp"） | 中（前提：手机紧凑壳的内容区也改用 `Tabs`+`TabContent`（见 E1 的代价评估）；若手机壳的"内容区"不切 `Tabs`，则 `barFloatingStyle` 无处安放 → 此时本项退化为"仅视觉参考"） | ① 真机 `barFloatingStyle` + `ImmersiveMaterial` 是否无 THREAD_BLOCK_6S（对照 `GlassSurface.ets:143-147` 的实测记录）；② `MobileBottomBar` 的 6 个按钮是**动作**（后退/前进/快切/新标签/总览/菜单）而非**标签选择器**，与 `TabContent` 的语义不匹配 → 需确认底部栏只保留"标签切换"语义、其余动作迁至 `MobileMenuSheet`；③ 低算力设备材质降级表现 |

### 1.6 白板（`components/whiteboard/*`）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| F1 | **Pen Kit 原生手写页已存在但未接线**：`[P]components\whiteboard\PenCanvasPage.ets`（`:1` `import { HandwriteComponent, HandwriteController, ... } from '@kit.Penkit'`；`:193-212` `HandwriteComponent` 含 `defaultPenType`/`defaultPenInfo`/`widthRatio`/`maxCanvasHeight`/`scaleDisabled`/`hiddenTools`；`:28` `HandwriteController`；`:226-228` `isPenKitSupported()` = `canIUse('SystemCapability.Stylus.Handwrite')`）。但路由仍指向自研 Canvas 白板：`[P]components\page\PageView.ets:134-135` → `Whiteboard()`；`Whiteboard.ets:75` 只把 `canIUse('SystemCapability.Stylus.Handwrite')` 存进 `handwriteCapable` 字段（`:69-75` 注释说明"经 PenCanvasPage 按需模块接入"），**全项目无任何文件 import `PenCanvasPage`**（`grep` 实测 0 处引用） | `HandwriteComponent` + `HandwriteController`：`[H]api\@hms.stylus.HandwriteComponent.d.ets`（`:13` `@syscap SystemCapability.Stylus.Handwrite`；`HandwriteController` `:161`；`hiddenTools` `:151` `@since 26.0.0`；`maxCanvasHeight` `:131` `@since 6.1.0(23)`；`onDidScroll` `:82` `@since 6.1.0(23)`；`defaultPenType` `:98` `@since 5.1.0(18)`；`widthRatio` `:114` `@since 6.0.0(20)`；`save`/`load`/`getContentRange`/`getThumbnail`/`scrollTo` 均 `SystemCapability.Stylus.Handwrite`）；Kit 入口 `[H]kits\@kit.Penkit.d.ts`（`@kit Penkit`，`@since 5.0.0(12)`，导出 `InstantShapeGenerator`/`PointPredictor`/`StylusFrameBoost`） | **强烈推荐**（代码已写好、含 `canIUse` 判定与 `load` 异常捕获（`PenCanvasPage.ets:80-87`），且系统提供原生笔迹渲染管线（报点预测、一笔成形），**未接线纯属遗漏**。正确形态：`PageView.ets:134-135` 按 `isPenKitSupported()` 分流——支持则 `PenCanvasPage()`，否则回退 `Whiteboard()`） | 低（改 `PageView.ets:134-135` 一处分支 + 决定 `.canvas` 与 `.hw` 两种持久化格式如何共存：`PenCanvasPage.ets:67` 用固定的 `callaite_whiteboard.hw`，而 `Whiteboard.ets:144` 用 `filesDir/whiteboards/default.canvas`） | ① 真机 `canIUse('SystemCapability.Stylus.Handwrite')` 结果（模拟器必为 false）；② `HandwriteController.load` 抛 `BusinessError 1010400001` 的路径（`PenCanvasPage.ets:80-87` 已捕获）；③ 手写笔设备上 `hiddenTools`(API 26) 是否生效；④ 2in1 无手写笔设备上 `HandwriteComponent` 是否优雅降级（若否，则 `canIUse` 判定必须严格） |
| F2 | 自研笔迹渲染的核心性能缺陷：**每段一次 `beginPath/moveTo/lineTo/stroke`** —— `[P]components\whiteboard\Whiteboard.ets:728-765`（`:741` 按点遍历，`:760-763` 每段独立 `beginPath` + `stroke()`）；且 `drawGrid()`（`:666-697`）每次调用先 `clearRect`（`:675`）再**重绘全部已完成笔触**（`:696` → `:703-722` → 逐段 `drawSingleStroke`）。`drawGrid` 的调用点密集：`:437`/`:463`/`:509`/`:528`/`:540`/`:797`/`:904`/`:912`/`:1075`/`:1082`/`:1112` | ① **同宿主内批处理**（最小改动）：`CanvasRenderingContext2D` 的 `Path2D`（`[C]canvas.d.ts:645` 起多个 `constructor`，含 `:674` `constructor(path: Path2D)`、`:708` `constructor(d: string)`）；<br>② **换绘制后端但保留 ArkUI `Canvas` 组件**（推荐）：`DrawingRenderingContext` — `[C]canvas.d.ts:3360`（`@since 12`，`@stagemodelonly`/`@crossplatform`/`@atomicservice`，syscap `SystemCapability.ArkUI.ArkUI.Full`），`:3371 get size()`、**`:3382 get canvas(): DrawingCanvas`**、`:3392 invalidate()`；桥接类型 `[C]canvas.d.ts:29` `declare type DrawingCanvas = import('../../../api/@ohos.graphics.drawing').default.Canvas;`；宿主重载 **`[C]canvas.d.ts:3472` `(context?: CanvasRenderingContext2D \| DrawingRenderingContext): CanvasAttribute`**；配套 `[C]canvas.d.ts:3586` `onReady(event: Callback<DrawingRenderingContext \| undefined> \| undefined)`；<br>③ `@ohos.graphics.drawing` 图元与批处理：`[A]@ohos.graphics.drawing.d.ts:41`(`namespace`) / `:1666`(`class Canvas`) / `:2018`(`drawPath(path: Path)`) / `:2033`(`drawLine`) / `:1794`(`drawCircle`) / `:1689`&`:1708`(`drawRect`) / `:2084`(`drawTextBlob`) / `:2174`(`attachPen`) / `:2191`(`attachBrush`) / `:2218`(`save`) / `:2264`(`restore`) / `:2335`(`scale`) / `:2380`(`translate`) / `:2478`(`setMatrix`) / `:2247`(`clear`)；`class Path` `:734`、`Pen` `:4528`、`Brush` `:4909`、`PathEffect` `:3821`、`SamplingOptions` `:1594` | **强烈推荐（仅做①+②，不动③的全量重写）**：<br>· ① 是**纯算法修复**：把 `:741-764` 的 N-1 次 `stroke()` 合并为**一次路径**（保持同一 `CanvasRenderingContext2D` 宿主即可），收益与宿主选型无关；<br>· ② 是本域最有价值的结构性发现——**要拿到原生 `drawing.Canvas` 并不需要迁移到 `XComponent`**：把 `Whiteboard.ets:88-89` 的 `new CanvasRenderingContext2D(settings)` 换成 `new DrawingRenderingContext()`，`Canvas(this.ctx)`（`:898`）保持不变，即可在 `onReady`(`:3586` 重载) 中拿到 `drawing.Canvas`，直接 `drawPath` + `attachPen` 批量绘制、用 `invalidate()` 精确失效。**宿主组件零改动**；<br>· ③ 全量迁 `@ohos.graphics.drawing` 纹理/着色器/文本（`TextBlob`/`Font`/`Typeface`）属于**长期优化**，现阶段不建议 | ① 低（约 20 行）；② 中（改上下文类型 + 重写 `drawStrokes`/`drawGrid` 的绘制调用，保留 `StrokeData` 模型与 `PenKitService` 压感映射不变）；③ 高 | ① `DrawingRenderingContext` 在 `Canvas` 组件尺寸变化（`Whiteboard.ets:906-914` `onAreaChange`）后 `size` 与 `invalidate()` 的有效性；② 与 `[P]utils\CanvasMath.ets` 的 NaN/Infinity 防护（`Whiteboard.ets:668-670` 注释记录 API 26 行为变更）在 `drawing` 下是否仍必要（`drawing` 对非法坐标的行为未核验）；③ `drawing.Canvas` 的字号单位（`GraphView.ets:502-505` 记录过 px/vp 单位踩坑，`drawing` 用物理 px，需重新换算） |
| F3 | 离屏 Canvas 未使用（`grep` 实测 `OffscreenCanvas` 仅出现在 `[P]utils\CanvasMath.ets:5` 的**注释**里） | `OffscreenCanvas` + `OffscreenCanvasRenderingContext2D`：`[C]canvas.d.ts:3205`(`OffscreenCanvas`) / `:3285`&`:3307`(`constructor(width, height[, unit])`) / `:3270`(`getContext("2d", options?)`) / `:3244`(`transferToImageBitmap(): ImageBitmap`)；`:3098`(`OffscreenCanvasRenderingContext2D`) / `:3133`(`transferToImageBitmap`)；合成 `[C]canvas.d.ts:1426`&`:1454`&`:1502`(`drawImage` 三重载，接受 `ImageBitmap \| PixelMap`)；`ImageBitmap` `[C]canvas.d.ts:960`（`:1063` `constructor(data: PixelMap)`） | **可选（分层重绘）**：把"已完成笔迹层"烘焙进一张 `OffscreenCanvas`，绘制中的笔触只画在临时层，滚动/缩放时用 `drawImage` 合成 → 消除 `drawGrid()` 的全量重绘。属"②之上的增量优化" | 中 | ① `transferToImageBitmap` 在频繁调用下的内存回收；② 缩放（`Whiteboard.ets` 的 `scaleValue`）时的位图重采样质量与 `SamplingOptions` 对应关系 |
| F4 | 白板宿主为 ArkUI `Canvas`：`[P]components\whiteboard\Whiteboard.ets:898-914`（`:902` `hitTestBehavior(HitTestMode.None)`，触摸由外层 `Stack` 的 `:1005-1018` `onTouch` 与 `:1019+` `gesture` 处理） | `XComponent`（`XComponentType.SURFACE`/`TEXTURE`/`NODE`）：`[C]xcomponent.d.ts:151`(`XComponentController`) / `:171`(`getXComponentSurfaceId`) / `:183`(`getXComponentContext`) / `:196`(`setXComponentSurfaceSize`) / `:212`&`:225`(SurfaceRect) / `:263`&`:277`&`:289`(`onSurfaceCreated`/`onSurfaceChanged`/`onSurfaceDestroyed`) / `:381`(`XComponentOptions`) / `:585`(`onLoad`) / `:597`(`onDestroy`) / `:619`(`enableAnalyzer`)；`[C]xcomponent.d.ts:316` `startImageAnalyzer` | **不建议**（现阶段无收益：`XComponent` 提供独立 surface，优势在"绕过 ArkUI 的重录指令 + 直连原生渲染线程"；但本项目白板热路径的瓶颈是 **F2 的逐段 `stroke()`**（`Whiteboard.ets:741-764`，N 点 → N-1 次绘制调用）与 `drawGrid` 的全量重绘，**不是 ArkUI 渲染管线开销**。先做 F2 ①②，再评估是否需要 `XComponent`；此外改 `XComponent` 会丢失 F1 的 `HandwriteComponent` 集成路径（后者才是本域的正确方向） | 高（需自建 surface 生命周期、触摸坐标换算、与 `Stack` 内声明式浮层（`:917-1000` 的 `ForEach` 形状/连线/缩放控件）的 z 序协调——`XComponent` 是独立 surface，**声明式浮层无法简单地叠在其上**） | ① 若坚持验证：`XComponent`(SURFACE) 与 `Stack` 内声明式子节点的层级/裁剪关系；② 2in1 自由窗口缩放时 `onSurfaceChanged` 的触发与尺寸一致性 |

### 1.7 图谱（`GraphView.ets` 自研 Canvas 力导向）

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| G1 | 力导向迭代**同步跑在主线程**：`[P]components\graph\GraphView.ets:104`(`rebuildLayout()`) → `:155-157`(`layout.build(...)` + **`layout.simulate(100)`** + `detectClusters()`)；算法本体 `[P]components\graph\GraphLayout.ets:172-235`(`step()`)：斥力为**双重循环 O(N²)**（`:181-194`），引力为 **O(E·N)**（`:197-212` 每条边两次 `findNode` 线性查找）；`build()` 的边去重为 **O(E²)**（`:129-135`）；`onAreaChange` 内还会**再跑一次完整布局**（`GraphView.ets:299-305`） | 移出主线程：`@ohos.taskpool`（`[A]@ohos.taskpool.d.ts:49` `namespace`；`:134` `class Task`；`:821`&`:841`&`:863`&`:883`&`:900` `execute(...)`；`:923`&`:944` `executeDelayed`；`:1269` `execute(task, configs)`）/ `@ohos.worker`（`[A]@ohos.worker.d.ts:816` `namespace`；`:826` `class ThreadWorker`；`:1101` `class Worker`）。帧驱动：`@ohos.graphics.displaySync`（`[A]@ohos.graphics.displaySync.d.ts:26` `namespace`；`:72` `setExpectedFrameRateRange`；`:81` `on('frame', cb)`；`:91` `off`；`:98` `start`；`:105` `stop`） | **强烈推荐（但替代的是"计算位置"，不是"渲染宿主"）**：<br>· 图谱卡顿的**主因是算法复杂度与线程**，不是 Canvas：`simulate(100)` 在 `aboutToAppear` 同步执行 100×(N²/2 + E·N) 次浮点运算，N=200、E=400 时约 100×(20000+80000)=1×10⁷ 次迭代**全部落在主线程**；<br>· 最有效的一步是 **把边/节点查找改为 Map 索引**（消掉 `findNode` 线性查找）+ **把迭代搬进 taskpool/worker**，Canvas 宿主可不动 | 中（`GraphLayout` 需改为可序列化的纯数据迭代，`GraphNode`/`GraphEdge` 需可在 worker 间传递；`GraphView.ets:299-305` 的"尺寸变化即重建布局"需防抖） | ① `taskpool.execute` 的入参/返回值序列化开销（节点数组较大时可能抵消收益）；② `displaySync` 的 `frame` 回调在后台/息屏时的节流行为；③ worker 内无法访问 `[P]services\WorkspaceService`（边数据必须在主线程先取好再传入） |
| G2 | 逐图元独立绘制调用：`[P]components\graph\GraphView.ets:449-514`(`drawGraph`)——每条边一次 `beginPath/moveTo/lineTo/stroke`（`:474-477`），每个节点一次 `beginPath/arc/fill/stroke`（`:492-498`）+ `fillText`（`:511`）；`:456` 每次全量 `clearRect` | 同 F2：`DrawingRenderingContext`（`[C]canvas.d.ts:3360`/`:3382`/`:3472`/`:3586`）→ `drawing.Canvas.drawPath`（`[A]@ohos.graphics.drawing.d.ts:2018`）+ `attachPen`/`attachBrush`（`:2174`/`:2191`）；离屏烘焙见 F3（`[C]canvas.d.ts:3205`/`:3244`/`:1426`）；文本用 `drawTextBlob`（`:2084`）+ `TextBlob`（`:2641`）/`Font`（`:2959`）替代每帧 `ctx.font` 字符串拼接（`GraphView.ets:505`） | **可选**（收益明确但优先级低于 G1：图元批处理把每帧 2E+2N 次绘制调用降为 2 次（边一次 path、节点一次 path / 或两个 `ImageBitmap` 合成）。若 G1 后仍卡，再上此项） | 中-高（`drawing` 的文本 API 是 `TextBlob`/`Font` 对象模型，需重写字号与对齐逻辑；`GraphView.ets:502-505` 已有一处单位踩坑注释，迁移时需重新推导 px/vp） | ① `drawing` 文本 API 在中文字形与 `textAlign: center` 语义（`GraphView.ets:507`）下的等价性；② 抗锯齿默认值差异（现 `RenderingContextSettings(true)` 见 `GraphView.ets:64`） |
| G3 | `Canvas` 宿主与手势：`[P]components\graph\GraphView.ets:287-342`（`:287` `Canvas(this.ctx)`；`:307-318` `PinchGesture` 缩放；`:319-325` `parallelGesture` + `LongPressGesture` 长按节点；`:326-339` `PanGesture` 平移/拖节点；`:340-342` `onClick` 命中）；`RenderingContextSettings(true)` 见 `:64`，上下文构造见 `:73`（`:65-72` 记录了"未实例化 ctx 导致画布不渲染"的历史缺陷） | `RenderingContextSettings`：`[C]canvas.d.ts:1213`（`:1250` `constructor(antialias?: boolean)`）；手势族见 H4 | **不建议**改手势模型（当前 `gesture` + `parallelGesture` 组合正确；`PinchGesture` 与 `PanGesture` 分离、长按走 `parallelGesture` 是标准写法） | —— | ① 与 H4 的右键双绑问题同源（图谱节点若要加右键菜单） |

### 1.8 通用交互件

| # | 当前实现（文件:行号） | 原生替代（组件/api + d.ts 路径 + @since + syscap） | 可行性判定 | 迁移成本 | 真机验证项 |
|---|---|---|---|---|---|
| H1 | hover 态**已用原生**：`onHover` 全项目约 **25 处**（`[P]components\layout\TabBar.ets:118`/`:163`/`:206`/`:316`/`:348`、`[P]components\layout\Ribbon.ets:119`/`:146`/`:166`、`[P]components\sidebar\LeftSidebar.ets:310`/`:337`/`:366`/`:519`/`:589`、`[P]components\layout\SplitDivider.ets:57`、`[P]components\outliner\BlockView.ets:173`、`[P]components\mobile\MarkdownToolbar.ets:94`、`[P]components\whiteboard\WhiteboardToolbar.ets:62`/`:108`、`[P]components\layout\MobileHeader.ets:55`、`[P]components\layout\MobileBottomBar.ets:48`/`:78`、`[P]components\layout\MobileMenuSheet.ets:112`、`[P]components\common\NewFileDialog.ets:123`、`[P]components\page\HomePage.ets:43`、`[P]components\sidebar\PageTree.ets:162`），模式统一为 `@State hoveredKey` + `stateStyles` + `.animation({duration:140, curve:Curve.EaseOut})` | 补齐 `hoverEffect`：`[C]common.d.ts:18607` `hoverEffect(value: HoverEffect)`；`HoverEffect` `[C]enums.d.ts:3009`（`:3018 Auto` / `:3027 Scale` / `:3036 Highlight` / `:3045 None`，均 `@since 8`）；`onHoverMove` `[C]common.d.ts:18569`；`onMouse` `[C]common.d.ts:18618`；`onAccessibilityHover` `[C]common.d.ts:18581` | **可选**（`hoverEffect` 可替代部分"悬停高亮"手写逻辑，但项目现有方案能表达 `hoverEffect` 无法表达的**分组互斥 hover**（`hoveredKey` 单值 → 同时只有一个按钮高亮），保留现状合理；**建议只在"点击型图标按钮"上补 `hoverEffect(HoverEffect.Highlight)` 以获得系统级涟漪反馈**） | 低 | ① `hoverEffect` 与项目 `stateStyles` 的视觉叠加是否冲突 |
| H2 | 拖拽为**完全自研**（`LongPressGesture` + `PanGesture` + `Stack.position`）：`[P]components\outliner\BlockDragHandler.ets`（`:107` 自定义回调 `onDragStart` —— **注意：这是 struct 的普通属性，与 ArkUI 的 `onDragStart` 属性同名但无关**；`:267-272` `startDrag`；`:278-292` `updateDrag`；`:298-307` `endDrag`；`:320-327` `cleanupDrag`；预览 `:220-245` `DragPreview` @Builder 用 `position({x: previewOffsetX, y: previewOffsetY})`；指示线 `:249-260`；落点计算 `:331-...` 用"每个 block 约 36px"估算）。全项目 `onDragStart`/`onDrop`/`dragPreview`/`draggable`/`allowDrop`/`dragController` **零使用**（`grep` 实测） | 统一拖拽：`[C]common.d.ts:20636` `onDragStart(event: (event: DragEvent, extraParams?) => CustomBuilder \| DragItemInfo)` / `:20650` `onDragEnter` / `:20664` `onDragMove` / `:20678` `onDragLeave` / `:20694`&`:20713` `onDrop` / `:20727` `onDragEnd` / `:20757` `allowDrop` / `:20770` `draggable` / `:20811`&`:20844` `dragPreview` / `:22612` `onDragSpringLoading`（`@since 20`）；`DragController` `[A]@ohos.arkui.UIContext.d.ts:2987` / `:3016`&`:3038` `executeDrag` / `:3066` `createDragAction`，取用 `:4903 getDragController()`；`List` 原生 item 拖拽：`[C]list.d.ts:1151` `editMode` / `:1744` `onItemDragStart` / `:1756` `onItemDragEnter` / `:1768` `onItemDragMove` / `:1780` `onItemDragLeave` / `:1800` `onItemDrop` / `:1713` `onItemMove` / `:1701` `onItemDelete` / `:1507` `editModeOptions` / `:1523` `enableEditMode` / `:1536` `onEditModeChange` | **可选（但需先补 B1）**：<br>· 统一拖拽的价值：跨组件/跨窗口拖拽、系统级拖拽预览、`allowDrop` 类型协商、与 `onDragSpringLoading` 的悬停展开。当前自研方案仅能"页内同层重排"；<br>· `List.onItemDragStart` 系列**只有在 B1 落地（改用 `List`）后才可用**，且它是"列表内重排"语义（`insertIndex` 由框架算），**无法表达项目需要的 third 落点 `child`（成为子节点）** —— `BlockDragHandler.ets:13` 的 `type DropPosition = 'above' \| 'below' \| 'child'` 是三态，而 `onItemDrop` 只给 `itemIndex`/`insertIndex`（`[C]list.d.ts:1800`），因此**不建议**改用 `onItemDragStart`；<br>· 若只需"拖到侧栏/外部"这类跨容器场景，再单独引入统一拖拽 | 中-高（`BlockDragHandler` 的 `computeDropTarget` 依赖像素估算 `:331-...`，迁到统一拖拽需重新处理坐标系：`DragEvent` 提供的是**窗口坐标**，而当前用的是**相对起点的 offsetX/offsetY**） | ① `onDragStart` 的 `CustomBuilder` 预览在 `List`（B1 后）裁剪下的表现；② `onDrop` 的 `DragEvent` 坐标与 `BlockDragHandler.ets:339` 的 Y 偏移估算能否对齐；③ 2in1 上鼠标拖拽与触控拖拽的 `extraParams` 差异 |
| H3 | 长按菜单/上下文菜单：`bindContextMenu` 正式代码零使用（仅 `[P]pages\SpikeHarness.ets:153-154` 探针）；长按走 `LongPressGesture`：`[P]components\graph\GraphView.ets:321-324`、`[P]components\outliner\BlockDragHandler.ets`（长按 500ms 激活拖拽，见 `:61`） | 见 D8/D9（`bindContextMenu` 家族 + `bindContextMenuWithResponse` `@since 23`） | **可选**（同 D8） | 低-中 | 同 D8 |
| H4 | 手势：`gesture` / `parallelGesture` **已用原生且用法正确** —— `[P]components\layout\SplitDivider.ets:60-77`（`PanGesture({direction: PanDirection.Horizontal, distance: 1})`）、`[P]components\graph\GraphView.ets:307-339`（`gesture` ×2 + `parallelGesture` ×1）、`[P]components\outliner\BlockDragHandler.ets`（`LongPressGesture` + `PanGesture` 序列）、`[P]components\whiteboard\Whiteboard.ets:1019+`；全项目 `gestureRecognizerJudgeBegin`/`onGestureJudgeBegin`/`shouldBuiltInRecognizerParallelWith` **零使用** | `[C]common.d.ts:19002` `gesture(gesture, mask?: GestureMask)` / `:19023` `priorityGesture` / `:19041` `parallelGesture`；完整手势族 `[C]gesture.d.ts`（`GestureMask`/`GestureMode`/`GesturePriority`/`PanGestureOptions`/`GestureGroupMode` 等）；`responseRegion` `[C]common.d.ts:17311`（项目已在 `[P]components\layout\TabBar.ets:312` 正确用于把 22vp 关闭按钮扩到 40vp 热区） | **不建议**改动（当前手势模型是标准用法；`onGestureJudgeBegin` 等"手势仲裁"API 只在多手势真冲突时才需要。项目唯一的多手势冲突点是 `ContentArea` 的 `Scroll` 与子组件拖拽，尚未出现误触报告） | —— | ① 若 B1（`List`）落地，`List` 内建滚动手势与 `BlockDragHandler` 的长按拖拽是否冲突（需实测是否要引入 `onGestureJudgeBegin`） |
| H5 | 动画：`animateTo` **零使用**；仅用声明式 `.animation({duration, curve})`（约 20 处，如 `[P]components\layout\TabBar.ets:117`/`:161`/`:205`/`:315`/`:341`）与 `TransitionEffect`（`[P]components\common\FloatingPanel.ets:92-97`、`[P]components\layout\MainContainer.ets:379-384`/`:401-406`）；`keyframeAnimateTo`/`TransitionEffect`/`sharedTransition`/`geometryTransition`/`animateToImmediately` **零使用** | `[A]@ohos.arkui.UIContext.d.ts:4703` `animateTo(value: AnimateParam, event)` / `:4926` `keyframeAnimateTo(param, keyframes)` / `:4953` `animateToImmediately(param, processor)`；`curves` 经 `[K]@kit.ArkUI.d.ts` 导出；`[A]@ohos.curve*`/`@ohos.animator` 未展开核验 | **可选**（声明式 `.animation()` 已覆盖当前所有需求；`animateTo` 的价值在"多属性协同的一次性隐式动画"与"动画结束回调"，项目暂不需要。**`geometryTransition`/`sharedTransition` 可用于"标签总览卡片 → 编辑器"的一镜到底，属体验升级而非替代**） | 低（新增能力） | ① `keyframeAnimateTo`/`animateToImmediately` 的 `@since` 与 syscap（`animateToImmediately` 在 `[A]@ohos.arkui.UIContext.d.ts:4953`，本次未逐行取 `@since`） |
| H6 | 触感反馈**调用点与 SDK 签名/权限不符（已定性）**：`[P]components\outliner\BlockDragHandler.ets:499-505` `triggerVibration()` → `vibrator.startVibration({ type: 'time', duration: 50 })`（**单参数**）；导入 `:5` `import { vibrator } from '@kit.SensorServiceKit'`；调用点 `:271`（拖拽开始）与 `:305`（拖拽结束） | `[A]@ohos.vibrator.d.ts:30` `namespace vibrator`；**全 SDK 仅两处 `startVibration` 声明**（已对 `openharmony\ets` 全目录 `*.d.ts`/`*.d.ets` 递归检索确认）：`:126` `startVibration(effect: VibrateEffect, attribute: VibrateAttribute, callback: AsyncCallback<void>)` 与 `:159` `startVibration(effect: VibrateEffect, attribute: VibrateAttribute): Promise<void>` —— **两者均要求 2 个必填参数，不存在单参重载**；`[K]@kit.SensorServiceKit.d.ts:20-21` 为 `import vibrator from '@ohos.vibrator'; export { sensor, vibrator };` → **无二次包装/宽松签名**；`@permission ohos.permission.VIBRATE`；`@syscap SystemCapability.Sensors.MiscDevice`；`@since 9`；类型 `:560` `type VibrateEffect = VibrateTime \| VibratePreset \| VibrateFromFile \| VibrateFromPattern` / `:569` `interface VibrateTime`（`:578` `type: 'time'`）/ `:511` `interface VibrateAttribute`（`:520 id?: number` / `:532 deviceId?: number` / **`:542 usage: Usage` 为必填**）；效果探测 `:261`/`:276`/`:291` `isSupportEffect` | **必修为先决条件（不计入"替代"）**：<br>① **签名缺参（已定性）**：`:501` 缺第二个参数 `VibrateAttribute`。`VibrateAttribute` 中仅 `usage` 必填（`:542`），`id`(`:520`)/`deviceId`(`:532`) 可选 → 修法为 `vibrator.startVibration({ type: 'time', duration: 50 }, { usage: vibrator.Usage.UNKNOWN })`；<br>② **权限未声明（已定性）**：`[P]..\..\module.json5` 的 `requestPermissions` **仅含 `ohos.permission.DISTRIBUTED_DATASYNC`**，缺 `ohos.permission.VIBRATE` → 真机（若 ① 修好）将抛 `BusinessError 201 Permission denied`（`[A]@ohos.vibrator.d.ts:116`/`:149`/`:169` 等均标注 `@throws 201`）；<br>③ 现有 `try/catch`（`:500-504`）会**静默吞掉** ①②的错误，导致触感反馈"永不生效且无日志" | 极低（改 1 行调用 + 加 1 条权限声明） | ① **编译验证**：项目是否有本地 shim（已检索：`Callaite` 全仓（含 `oh_modules`）除 `BlockDragHandler.ets:66`（注释）与 `:501`（调用）外**无任何 `startVibration` 声明或引用**，亦无自建 `*.d.ts`/`*.d.ets`）→ 因此预期该调用**应无法通过 ArkTS 编译**；需跑一次 `Sync Project` 确认（本环境无 `errorlog.txt`，见存疑项 4.5 已收窄）；② 真机 `startVibration` 在 `usage` 取值下的振动强度差异；③ `isSupportEffect` 用于更精细的预设振动（`:261`） |
| H7 | 快捷键：`onKeyEvent` + `onKeyPreIme` **已用原生**：`[P]components\page\ContentArea.ets:81-86`（`onKeyEvent` 路由到 `ShortcutService`）+ `:159-169`（`onKeyPreIme` 在 IME 前拦截修饰键）；`[P]services\ShortcutService.ets:162` `handleKeyEvent`（`:356-470` 实现 Ctrl+Z/Shift+Z/M/P/K/F/S/B/I）；焦点：`[P]components\page\ContentArea.ets:46` `focusControl.requestFocus('contentAreaScroll')` + `:79` `.defaultFocus(true)` | `[C]common.d.ts:18643`&`:18656` `onKeyEvent` / `:18687` `onKeyPreIme`；`FocusController` `[A]@ohos.arkui.UIContext.d.ts:3239` / `:3264` `requestFocus(key)` / `:3279` `activate(isActive, autoInactive?)`，取用 `:4937 getFocusController()`；键盘避免 `[A]@ohos.arkui.UIContext.d.ts:4834` `setKeyboardAvoidMode()` / `:4845` `getKeyboardAvoidMode()` | **可选（两处小改进）**：<br>① `focusControl` 是全局函数，迁移到 `uiContext.getFocusController().requestFocus()` 更符合当前 SDK 推荐（`focusControl` 未 deprecated，故非必须）；<br>② **命令面板缺少键盘导航**（见 D1）：应在 `CommandPalette` 内加 `onKeyEvent` + `selectedIndex`，并用 `FocusController.requestFocus` 把焦点交给输入框 | 低 | ① `[P]components\page\ContentArea.ets:46` 与 `:79` 的"显式 requestFocus + defaultFocus"在分屏双窗格下的稳定性（`:43-44` 注释说明已规避"两窗格争抢焦点"）；② `setKeyboardAvoidMode` 对移动端键盘遮挡的改善（`[A]@ohos.arkui.UIContext.d.ts:4820` 注明**对 Popup/Menu/BindSheet/BindContentCover/Toast 不生效**） |
| H8 | 系统材质：见 A6（`[P]components\common\GlassSurface.ets:143-147` 刻意禁用） | 见 A6 | 见 A6 | 见 A6 | 见 A6 |

---

## 2. 强烈推荐的前 3 项（收益最大）

> 全表共 8 条「强烈推荐」（A6、B1、D6、D8、E3、F1、F2、G1）。以下前 3 项按 **「收益 ÷ 迁移成本」** 排序选出。
> 未入选的 5 条与理由：
> - **A6 + E3 合并为一条材质路线**（A6 定入口、E3 定形态），因**依赖手机紧凑壳内容区改用 `Tabs`+`TabContent`**（即 E1，而 E1 自身代价高），故未进前 3，列为**第 4 顺位**；
> - **D8**（`bindContextMenuWithResponse`）收益取决于 4.1 的探针结论——**若链式双绑本来就能用，则本项收益归零**，故列为**第 5 顺位（条件触发）**；
> - **G1**（力导向移出主线程）需要把 `GraphLayout` 改造为可序列化的纯数据迭代，改动面比前 3 项大一个量级，列为**第 6 顺位**。

### 🥇 第 1 项：`BlockList` 的 `LazyForEach` 迁入 `List`（B1）—— 当前虚拟化**完全没生效**

**收益量级最大，且是"已有代码在空转"的典型。**

证据链：

1. `[P]components\outliner\BlockList.ets:101-124`：`Stack` → `Column` → `LazyForEach`。`LazyForEach` 的直接父容器是**普通 `Column`**，不是滚动容器。
2. `[C]lazy_for_each.d.ts:881-883` 明文：*"When **LazyForEach** is used in a scrolling container, the framework creates components as required within the visible area of the scrolling container. When a component is out of the visible area, the framework destroys and reclaims the component to reduce memory usage."* → **回收/懒创建的前提是"scrolling container"**；在 `Column` 内，全部数据项都会被构建并常驻。
3. 项目为此写了完整的数据源（`BlockList.ets:16-51` 实现 `IDataSource`）与刷新链路（`:73` `@StorageLink('callaite_blocksVersion')` → `:85-87` → `:89-98`），**这部分投入目前没有换来任何虚拟化收益**。
4. 递归子块（`[P]components\outliner\BlockChildren.ets:55`/`:62`）同样是 `ForEach` + 递归，深树页面的节点数会成倍放大。

**正确做法**：
- `BlockList.build()` 的 `Column` → `List`，`LazyForEach` 的 itemGenerator 用 `ListItem` 包裹（这是 `List` 的硬性结构要求）；
- 把 `[P]components\page\ContentArea.ets:71-86` 外层 `Scroll` 移除，`Scroller` 直接交给 `List`，避免双层滚动；`.id(this.scrollId())`(`:80`)、`.focusable(true)`/`.defaultFocus(true)`(`:78-79`)、`onKeyEvent`(`:81-86`) 全部改挂到 `List` 上；
- 配置 `[C]list.d.ts:1195 cachedCount(value)`（默认文档见 `[C]list.d.ts:761`：*"By default, child components equivalent to one screen…"*）。

**真机验证项**（3 条，按风险排序）：
1. `blocksVersion` 自增 → `onDataReloaded()`（`BlockList.ets:44`）是否导致 `List` 滚动位置跳回顶部（这是本项**最可能回归**的点，`List` 有 `maintainVisibleContentPosition`（`[C]list.d.ts:1439`）可作为兜底）；
2. `[P]components\outliner\BlockDragHandler.ets:220-245` 的 `Stack.position` 拖拽预览在 `List` 的子节点裁剪下是否仍跟随手指；
3. 分屏（`[P]components\layout\MainContainer.ets:210-233`）双 `List` 时 `scrollId()` 隔离（`ContentArea.ets:38-40`）是否仍成立。

---

### 🥈 第 2 项：接线 Pen Kit 白板（F1）+ 修掉逐段 `stroke()`（F2①）

**收益：一次性获得系统原生笔迹管线，同时消除一个 O(N) 次的绘制调用热点。**

证据链：

1. **原生实现已经写好但从未被引用**：`[P]components\whiteboard\PenCanvasPage.ets`（228 行，含 `HandwriteComponent`(`:193-212`)、`HandwriteController`(`:28`)、`load` 异常捕获(`:80-87`)、`canIUse('SystemCapability.Stylus.Handwrite')` 封装(`:226-228`)），但 `[P]components\page\PageView.ets:134-135` 仍是无条件 `Whiteboard()`，全项目 `grep` 显示**零处 import `PenCanvasPage`**。
2. `Whiteboard.ets:69-75` 的注释已经写明了设计意图：「true → 设备具备 `SystemCapability.Stylus.Handwrite`（真机手写笔），可启用 Pen Kit 原生笔迹管线（HandwriteComponent，经 PenCanvasPage 按需模块接入）」「两种引擎共享同一 StrokeData 模型…引擎切换不改变数据格式」——**设计已闭环，只差路由分流这一行**。
3. `[H]api\@hms.stylus.HandwriteComponent.d.ets:13` `@syscap SystemCapability.Stylus.Handwrite`，Kit 入口 `[H]kits\@kit.Penkit.d.ts`（`@since 5.0.0(12)`）→ **属 HMS 能力，必须 `canIUse` 判定**，项目已有该判定。
4. **回退路径的性能热点**（无手写笔设备仍走 `Whiteboard()`）：`Whiteboard.ets:741-764` 对一条 N 点笔触执行 **N-1 次** `beginPath/moveTo/lineTo/stroke`；`drawGrid()`(`:666-697`) 每次先 `clearRect`(`:675`) 再重绘**全部**已完成笔触(`:696`)，而 `drawGrid` 有 **11 个调用点**（`:437`/`:463`/`:509`/`:528`/`:540`/`:797`/`:904`/`:912`/`:1075`/`:1082`/`:1112`）。二者相乘 → 画 500 点后每次交互触发约 (500·笔数) 次绘制调用。
5. 最小改法（F2①）只需把 `:741-764` 的循环合并为**单条路径**（保持同一 `CanvasRenderingContext2D`，只把 `lineWidth` 逐段设置的诉求改为"按宽度分桶后批量描边"）。

**正确做法**：
- `PageView.ets:134-135` 改为 `if (isPenKitSupported()) { PenCanvasPage() } else { Whiteboard() }`（`isPenKitSupported` 已从 `PenCanvasPage.ets:226` export）；
- 明确两种持久化格式的边界：`PenCanvasPage.ets:67` 固定用 `filesDir/callaite_whiteboard.hw`，`Whiteboard.ets:144` 用 `filesDir/whiteboards/default.canvas`，`[P]components\common\NewFileDialog.ets:57-77` 的"新建白板"归档逻辑目前只处理 `.canvas`，需同步；
- 独立提交 F2① 的批处理修复（与 F1 的引擎分流无关，对 `PenCanvasPage` 与 `Whiteboard` 两条路径都有收益）。

**真机验证项**：
1. `canIUse('SystemCapability.Stylus.Handwrite')` 在**有笔/无笔真机**上的返回值（模拟器必为 false，无法验证 HandwriteComponent 分支）；
2. `HandwriteController.load` 对**已存在的 `.hw`** 与**新建空文件**的行为（`PenCanvasPage.ets:96-105` 用 `fs.openSync` 预创建，注释说明"load 需要文件已存在或可创建"）；
3. 笔迹数据在 `PenCanvasPage` 与 `Whiteboard` 之间是否真如注释所述"格式无关"（若用户在有笔设备上画了 `.hw`、又在无笔设备打开 → 数据是否可见，这是**产品层面的数据可用性风险**）。

---

### 🥉 第 3 项：`MobileMenuSheet` 改用 `bindSheet`（D6）—— 自研组件已经在"假装"是 sheet

**收益/成本比最高，且能顺手删掉两处手写浮层脚手架。**

证据链：

1. `[P]components\layout\MobileMenuSheet.ets:120-150`：组件已经具备 sheet 的全部**外观**——顶部圆角 24(`:148`)、拖动指示条 36×4(`:122-128`)、分组行高 52(`:103`)、`padding bottom 24`(`:146`)。
2. **但拖动指示条是假的**：全文件**没有任何手势代码**（`grep` 证实），sheet 无法拖拽、无吸附档位、无高度回调、下滑不关闭。
3. 呈现脚手架全在调用方手写：`[P]components\layout\MainContainer.ets:391-410`（遮罩 `:393-399` + `TransitionEffect.asymmetric` translate 360 `:401-406`）。
4. `bindSheet` 一次补齐：`[C]common.d.ts:21649` `bindSheet(isShow, builder, options?)`；`SheetOptions` `[C]common.d.ts:11753` → `detents`(`:11795`)、`onDetentsDidChange`(`:11976`)、`onHeightDidChange`(`:11944`)、`shouldDismiss`(`:11853`)、`showClose`(`:11821`)、`maskColor`(`:11785`)、`blurStyle`(`:11810`)、`enableOutsideInteractive`(`:11884`)、`onWillDismiss`(`:11863`)；`SheetSize` `[C]common.d.ts:7947`（`FIT_CONTENT=7977` 正是本场景）。
5. **收益不止性能**：`onWillDismiss` 是当前完全缺失的"下滑关闭前拦截"能力；`detents` + `onDetentsDidChange` 是当前完全缺失的"多档位吸附"；系统返回键关闭、无障碍语义也一并获得。
6. 同一模式可复用到 `[P]components\layout\TabOverviewSheet.ets`（D7，`MainContainer.ets:369-388` 也是手写遮罩 + transition）。

**正确做法**：
- `MobileMenuSheet` 本体布局**不动**（`:120-150`），只把开关从"`if (this.mobileMenuOpen) { 手写遮罩 + 面板 }`"改为 `bindSheet(isShow, this.MobileMenuSheetBuilder, { detents: [...], preferType: SheetType.BOTTOM, showClose: false, ... })`；
- 删掉 `MobileMenuSheet.ets:122-128` 的假指示条（`bindSheet` 自带）；
- `[P]state\AppState.ets:223` 的 `callaite_mobileMenuOpen` 语义由"是否挂载"变为"是否显示"，保持键名不变以减少改动面。

**真机验证项**：
1. `[P]state\AppState.ets:195` 已记录过 `bindSheet` 的**初始绑定竞态**（"否则与 bindSheet 初始绑定产生框架竞态导致抽屉打开后立即关闭"）→ 必须验证"冷启动时若 `mobileMenuOpen` 初值为 true"的竞态是否复现（当前默认 false，但需确认）；
2. 紧凑壳的浮层层级：`MainContainer.ets:306-334` 的 `MobileHeader`/`MobileBottomBar` 与 sheet 的 z 序（sheet 在独立层，需确认不会被 `MobileBottomBar` 的 `.margin({bottom: safeBottom+12})`(`:327`) 遮挡）；
3. `detents` 三档与 3 组 9 行的实际高度是否匹配（`SheetSize.FIT_CONTENT` 可能已足够，需实测决定是否要 `detents`）。

---

## 3. 不建议替代的项

### 3.1 ⛔ `Navigation`/`NavDestination` 全壳迁移（A1）—— 语义模型不匹配，回归面覆盖全壳

**不建议的核心理由不是"材质"，而是"槽位语义"**：

1. **槽位语义**：`Navigation` 的子节点构成**导航页（navBar）**，内容区用于承载 `NavDestination`（`[C]navigation.d.ts:2594 navDestination(builder)`）。这是**列表-详情**（master-detail）模型；而本项目的三栏壳（`[P]components\layout\MainContainer.ets:252-295`：Ribbon + LeftSidebar + 中列 + RightSidebar）是**平铺**模型，中列自身还要承载 `ContentPanes`(`:210-233`) 的**双文档分屏**。
2. **分屏语义不可表达**：`NavigationMode.Split`(`[C]navigation.d.ts:159`) 分割的是"导航页 / 内容区"，且其注释明确列出分隔条热区 2vp/侧、内容区单页时不显示返回键等**以"导航页"为前提**的行为。项目需要的是"两个**同级、可各自独立换路由**的文档窗格"（副窗格靠 `[P]components\page\ContentArea.ets:28 @Prop pageOverride` 注入自己的路由）。把副窗格塞进 `Split` 的任一侧都会得到错误语义。
3. **断点来源冲突**：项目在 `[P]components\layout\MainContainer.ets:89-96` 明确论证了"必须以**组件实际宽度**（`onAreaChange`）而非 display 宽度作为断点来源"，理由是 2in1 自由多窗口缩放。`NavigationMode.Auto`(`[C]navigation.d.ts:172`) 的判定基准是"window width ≥600vp"（注释明文），二者在自由窗口下**必然分歧**（组件宽度 ≠ 窗口宽度，例如分屏/悬浮窗）。
4. **项目已实测过失败**：`MainContainer.ets:268-272` 记录"实测 Navigation 会按自己的布局模型重排子节点（标题栏与内容区并排），导致桌面壳布局回归"。本次审查在 d.ts 中找到了该现象的机制依据（见 3.1 第 1 点），**即该失败不是配置问题而是模型问题**，重试不会自愈。
5. **迁移成本覆盖全壳**：涉及外壳布局模型、`PageView.ets:126-153` 的 11 条 `if/else` 路由、`TabBar`/`StatusBar` 的归属、双窗格分屏、沉浸式安全区避让（`EntryAbility.ets:134-210` 的 `safeTop`/`safeBottom` 发布链路）。

**若将来确有必要迁移，正确做法**（本审查的建议形态，但**不建议现在做**）：
- 用 `Navigation` 承载 **navBar = 侧栏的页面列表**（LeftSidebar/PageTree），`NavDestination` 承载**编辑器内容**，把"文件树 → 打开页面"这一条**真正的 master-detail 路径**作为试点，而非包裹整个外壳；
- 桌面三栏、Ribbon、StatusBar、内容区分屏**全部留在 Navigation 之外**（作为 Navigation 的兄弟节点放在最外层 `Row`/`Stack` 里）；
- 材质只挂在该 Navigation 的 `.title(value, { systemMaterial })`（`[C]navigation.d.ts:1891` + `:2324`）上，以验证材质行为；
- 必须保留 `onAreaChange` 作为断点唯一来源（不依赖 `NavigationMode.Auto`）。

### 3.2 ⛔ `BlockList` → `WaterFlow` / 多列 `Grid`（B8）

"块列表 + 大纲缩进"是**严格单列纵向**结构；`WaterFlow`（`[C]water_flow.d.ts`，且实测**无 `sticky`**）与 `List.lanes`(`[C]list.d.ts:948`/`:972`) 的多列布局会破坏大纲的缩进语义与阅读顺序。`Grid` 亦**无 `sticky`**（`grid.d.ts` 中 `sticky` 命中数 = 0）。**属误配**。

### 3.3 ⛔ `List.onItemDragStart` 系列替代自研 Block 拖拽（H2）

`[C]list.d.ts:1744` `onItemDragStart` / `:1800` `onItemDrop(event, itemIndex, insertIndex, isSuccess)` 提供的是**列表内重排**语义（框架只给 `itemIndex`/`insertIndex`）。而项目需要**三态落点** —— `[P]components\outliner\BlockDragHandler.ets:13` `type DropPosition = 'above' | 'below' | 'child'`。`onItemDrop` 无法表达"成为目标的子节点"。**改用它反而会丢失能力**。

（统一拖拽 `onDragStart`/`onDrop`(`[C]common.d.ts:20636`/`:20694`) 仍可**可选**引入，但用途应是"拖到侧栏/拖出应用"等跨容器场景，不是替换页内重排。）

### 3.4 ⛔ 白板 `Canvas` → `XComponent` 全量重写（F4）

现阶段无收益：瓶颈在应用层算法（F2 的逐段 `stroke()` + `drawGrid` 全量重绘），不在 ArkUI 渲染管线。且 `XComponent` 是**独立 surface**，会导致 `[P]components\whiteboard\Whiteboard.ets:917-1000` 的声明式浮层（`ForEach` 形状/连线/页面引用/缩放控件）**无法简单叠加**，等于重做整个白板的图层模型。**更优路径是 F2②（`DrawingRenderingContext` 拿到原生 `drawing.Canvas` 而不换宿主组件）**。

### 3.5 ⛔ 为 `systemMaterial` 而迁移外壳（A6 的反面）

`systemMaterial` 作为 CommonMethod 在任意节点可调（`[C]common.d.ts:22642` 类型面完全允许），但项目实测会触发 THREAD_BLOCK_6S（`[P]components\common\GlassSurface.ets:143-147`）。**严禁**在自研 `Stack`/`Row` 容器内启用它。若目标只是材质视觉：
- **不要**迁全壳（见 3.1）；
- **要**用 `Tabs(barPosition: End)` + `barFloatingStyle({ systemMaterial })`（`[C]tabs.d.ts:1683` + `:895`）命中唯一低成本的合法槽位（见 E3），或维持现有 `backgroundBlurStyle` + `backgroundEffect` 兜底（`GlassSurface.ets:150-161`）。

### 3.6 ⛔ 命令面板改 `bindContentCover`（D1）

视觉语义不符（`bindContentCover` 是全屏模态，`[P]components\page\ContentArea.ets:107-113` 是宽 92%/上限 560vp/高 420vp 的顶部居中卡片），且**不能修复真正缺陷**：`CommandPalette` 的 `KeyHintFooter`(`:108-135`) 声明了"↑↓ 选择 / ↵ 打开"但**没有 `onKeyEvent`、没有 selectedIndex、没有 `defaultFocus`**。换浮层宿主与键盘导航是两件事。

---

## 4. 不确定项

| # | 不确定内容 | 已知证据 | 待验方式 |
|---|---|---|---|
| 4.1 | **`bindContextMenu` 同一节点链式双绑（RightClick + LongPress）的运行时行为** | `[C]common.d.ts:21495` `bindContextMenu(content, responseType, options?)` 的签名**未禁止重复调用**，链式调用在类型面完全合法；`[P]pages\SpikeHarness.ets:153-154` 已布置探针，但 `:118-122` 的 builder **未回写** `:28` 的 `menuHit` 状态位，**当前探针无法自动化采集结论**（需目视） | ① 先给 `SpikeHarness.ets` 的 `SpikeMenu` 补 `menuHit` 回写；② 真机分别右键/长按，观察是否为 `MENU:RightClick`/`MENU:LongPress` 还是被后者覆盖；③ 备选方案：`bindContextMenuWithResponse(CustomBuilderT<ResponseType>, options?)`（`[C]common.d.ts:21526`，`@since 23`；`CustomBuilderT<T> = (t: T) => void` 见 `:22841`）——**这是官方为"按触发方式分流"提供的形态，可能直接消除该不确定性**，但需验证 ArkTS 下 `@Builder` 能否满足 `(t: T) => void` |
| 4.2 | **`systemMaterial` 的容器作用域限制** | d.ts 中**无任何**"仅 Navigation 标题栏 / Tabs 底部栏生效"的文字。能查到的只有：`[C]navigation.d.ts:1891`（TitleBar 用途）、`[C]tabs.d.ts:895`（`FloatingTabBarStyle`）、`[A]@ohos.arkui.uiMaterial.d.ts:365-366`（提及 `TabContent` 的 `tabBar` 在 `BottomTabBarStyle` 下）。`[C]common.d.ts:22642` 作为 CommonMethod 的注释**只讲影响哪些视觉属性，不讲容器** | 项目的 THREAD_BLOCK_6S 属自有实证，本次无法从类型面复现/证伪。建议：① 在真机（非模拟器）上分别验证"合法槽位（`title` options / `barFloatingStyle`）"与"非法槽位（普通 Stack 子节点）"的差异；② 记录 `MaterialType`(`[A]@ohos.arkui.uiMaterial.d.ts:43`) 各档位在低算力设备上的降级行为 |
| 4.3 | **`SheetType.SIDE`（`@since 20`）能否替代 `FloatingPanel` 的"四边留白悬浮面板"** | `[C]common.d.ts:11517` `SIDE = 3` 存在且 `@since 20`（项目 compatibleSdkVersion=26 可用）；`SheetOptions.preferType`(`:11833`) 可指定；`[A]@ohos.arkui.UIContext.d.ts:5300-5302` 提示 `openBindSheet` 下 `preferType` 不能为 `POPUP`（会被替换为 `CENTER`）、`mode=EMBEDDED` 需 `targetId`。但 **`FloatingPanel.ets:11-16` 自述的约束**（宽度占屏 ≤0.95、四边留白、距底 ≥10vp、独立圆角/阴影/描边）在 `SIDE` 下是否可控**未验证** | 真机上以 `preferType: SheetType.SIDE` + `SheetOptions` 实测宽度/圆角/留白，与 `[P]components\common\FloatingPanel.ets:80-98` 的现有视觉逐项对照 |
| 4.4 | ~~**`bindTips` 的 `@since`、`syscap` 与触发条件**~~ → **已解决**：`[C]common.d.ts:21434` `bindTips(message: TipsMessageType, options?: TipsOptions)`，`@since 19`，`@syscap SystemCapability.ArkUI.ArkUI.Full`，`@stagemodelonly`/`@crossplatform`/`@atomicservice`（见 `:21422-21433`）；`TipsOptions` 见 `[C]common.d.ts:13009` | 已定位声明与 `@since`；**触发条件（hover 还是长按）仍未从 d.ts 确认** | 打开 `[C]common.d.ts:13009+` 的 `TipsOptions` 字段（`enableArrow`/`showAt` 之类）并查官方 `bindTips` 文档的触发时机说明 |
| 4.5 | ~~**`[P]components\outliner\BlockDragHandler.ets:501` 的单参 `vibrator.startVibration` 是否能通过编译**~~ → **已定性为"缺必填参数"**：`[A]@ohos.vibrator.d.ts` 全库仅 2 处 `startVibration` 声明（`:126`、`:159`），**均为 2 必填参数**；`[K]@kit.SensorServiceKit.d.ts:20-21` 直接 `import vibrator from '@ohos.vibrator'` 后原样 `export`，**无宽松包装**；`Callaite` 全仓（含 `oh_modules`）**无本地 shim**（仅 `:66` 注释与 `:501` 调用两处命中）。故该调用**预期无法通过 ArkTS 编译** | 证据链完整（SDK 侧 + 项目侧双向排除）。**唯一残余不确定**：本环境不存在 `F:\DevEcoStudioProjects\errorlog.txt` 与 `Callaite\errorlog.txt`，`entry\build` 下无 `*.log`，**无法证明项目上一次构建的实际结果** | 跑一次 `Sync Project` / 构建，检查 `errorlog.txt` 是否报该行；若构建通过则说明存在本环境 SDK 之外的声明来源（如 DevEco 插件注入），需进一步定位 |
| 4.6 | **`HandwriteComponent` 与 `.canvas` 数据模型的双向兼容** | `[P]components\whiteboard\Whiteboard.ets:69-75` 注释断言"两种引擎共享同一 StrokeData 模型…引擎切换不改变数据格式"；但 `PenCanvasPage.ets:67` 的持久化文件是 `callaite_whiteboard.hw`，`:114` 走 `controller.save(filePath)`（Pen Kit 自有格式），而 `Whiteboard.ets:144` 是 `default.canvas`（JSON Canvas 1.0）。**两者格式不同**，"不改变数据格式"的说法**存疑** | ① 在有笔真机上画 `.hw` 后切到无笔路径，观察内容是否可见；② 核对 `HandwriteController` 是否有导入/导出通用矢量格式的能力（`[H]api\@hms.stylus.HandwriteComponent.d.ets` 中 `save`/`load`/`getThumbnail`/`getContentRange` 均未见导出 API） |
| 4.7 | **`DrawingRenderingContext` 与项目 `CanvasMath` NaN 防护的关系** | `[C]canvas.d.ts:3360-3392` 提供 `size`/`canvas`/`invalidate()`；`Whiteboard.ets:668-670` 注释记录了"API 26 行为变更：Canvas 传入 NaN/Infinity 后，其它绘制方法会'正常绘制'而污染整幅画面"——该行为是 `CanvasRenderingContext2D` 的特性还是底层渲染器的特性，决定 `drawing.Canvas`（`[A]@ohos.graphics.drawing.d.ts:1666`）是否也需要同样的防护 | 用 `drawing.Canvas` 传 NaN 做一次隔离实验（可复用 `[P]pages\SpikeHarness.ets` 的探针模式） |
| 4.8 | **`XComponent` 的性能结论** | 本次**未做任何实测**，仅从架构上判断"当前瓶颈不在渲染管线"（依据是 F2 的逐段 `stroke()` 与 `drawGrid` 全量重绘）。这是**推理而非测量** | 若未来要做宿主选型，需先做基准测试：同一 500 点笔触在 `CanvasRenderingContext2D`（逐段）、`DrawingRenderingContext`（批量）、`XComponent`+`drawing`（批量）三种宿主下的单帧耗时 |
| 4.9 | **`[K]@kit.ArkUI.d.ts` 导出的 `MultiNavPathStack` / `SplitLayout` 等符号语义** | `[K]@kit.ArkUI.d.ts:125` 的导出列表中同时出现 `MultiNavPathStack`、`SplitLayout`、`FoldSplitContainer`、`PresetSplitRatio` 等，**本次未核验其声明位置与语义** | 若未来坚持用 Navigation 做分屏（不推荐，见 3.1），需先核验 `MultiNavPathStack` 是否允许"双独立返回栈"；`SplitLayout`/`FoldSplitContainer` 是否提供本项目所需的分屏折叠适配 |

---

## 附录 A：本次审查的证据索引（便于复核）

### A.1 项目侧关键行号

| 主题 | 位置 |
|---|---|
| 外壳根/中列/分屏 Builder | `[P]components\layout\MainContainer.ets:236`、`:252`、`:273`、`:210-233` |
| Navigation 迁移失败记录 | `[P]components\layout\MainContainer.ets:268-272` |
| 断点来源论证 | `[P]components\layout\MainContainer.ets:78-109`、`:119-134`、`:415-417` |
| 侧栏 Resizer（PanGesture） | `[P]components\layout\MainContainer.ets:423-472` |
| 移动浮层（胶囊栏/sheet/菜单） | `[P]components\layout\MainContainer.ets:306-334`、`:336-360`、`:362-410` |
| 内容区 Scroll + 焦点 + 快捷键 | `[P]components\page\ContentArea.ets:42-48`、`:71-86`、`:94-153`、`:159-169` |
| Block 列表（LazyForEach/Column） | `[P]components\outliner\BlockList.ets:16-51`、`:73`、`:85-98`、`:101-124` |
| 子块递归 | `[P]components\outliner\BlockChildren.ets:44-69` |
| 分隔条 | `[P]components\layout\SplitDivider.ets:20-26`、`:41-82` |
| 标签栏 + TabItemView 不变式 | `[P]components\layout\TabBar.ets:99-222`、`:124-140`、`:215-218`、`:254-352` |
| 路由 if/else 链 | `[P]components\page\PageView.ets:126-153` |
| 命令面板（缺键盘导航） | `[P]components\commandpalette\CommandPalette.ets:22`、`:38-95`、`:108-135` |
| 自绘模态 | `[P]components\common\NewFileDialog.ets:131-196`、`[P]components\common\VaultSwitcherDialog.ets:22-41` |
| 悬浮侧面板（否决 bindSheet） | `[P]components\common\FloatingPanel.ets:4-17`、`:39-98` |
| 底部菜单（假指示条） | `[P]components\layout\MobileMenuSheet.ets:120-150` |
| 标签总览卡片 | `[P]components\layout\TabOverviewSheet.ets:44-60` |
| 材质禁用记录 + THREAD_BLOCK_6S | `[P]components\common\GlassSurface.ets:86-96`、`:143-161`；`[P]theme\MaterialTokens.ets:107-114` |
| 白板 Canvas/绘制 | `[P]components\whiteboard\Whiteboard.ets:69-75`、`:88-89`、`:666-697`、`:703-722`、`:728-765`、`:898-914`、`:917-1000`、`:1005-1018` |
| Pen Kit 白板（未接线） | `[P]components\whiteboard\PenCanvasPage.ets:1`、`:28`、`:67`、`:80-87`、`:193-212`、`:226-228` |
| 图谱绘制/布局 | `[P]components\graph\GraphView.ets:64`、`:73`、`:104`、`:155-157`、`:287-342`、`:449-514`；`[P]components\graph\GraphLayout.ets:89-139`、`:172-235` |
| Block 拖拽（自研） | `[P]components\outliner\BlockDragHandler.ets:13`、`:107`、`:220-260`、`:267-327`、`:331+`、`:499-505` |
| 触感调用 + 权限缺失 | `[P]components\outliner\BlockDragHandler.ets:5`、`:271`、`:305`、`:499-505`；`[P]..\..\module.json5` `requestPermissions` |
| 快捷键 | `[P]services\ShortcutService.ets:162`、`:356-470`；`[P]components\page\ContentArea.ets:81-86`、`:159-169` |
| 沉浸式与安全区 | `[P]entryability\EntryAbility.ets:63`、`:107`、`:119`、`:134-165`、`:202-210` |
| bindSheet 竞态历史 | `[P]state\AppState.ets:191-206`（`:195` 注释）；浮层状态键 `:217-224` |
| 右键双绑探针 | `[P]pages\SpikeHarness.ets:12`、`:28`、`:118-122`、`:145-154` |

### A.2 SDK 侧关键声明行号

| API | 声明位置 |
|---|---|
| `NavigationMode` / `Split` / `Auto` | `[C]navigation.d.ts:122`、`:159`、`:172`、`:184` |
| `NavPathStack` | `[C]navigation.d.ts:615`、`:638`、`:651`、`:723`、`:1002`、`:1019` |
| `Navigation` 属性族 | `[C]navigation.d.ts:2163`、`:2204`、`:2222`、`:2234`、`:2292`、`:2324`、`:2392`、`:2577`、`:2594`、`:2613`、`:2684`、`:2716`、`:2729`、`:2769` |
| `NavigationTitleOptions.systemMaterial` | `[C]navigation.d.ts:1891`（`@since 26.0.0`） |
| `NavDestination.title(..., NavigationTitleOptions)` | `[C]nav_destination.d.ts:622` |
| `systemMaterial`（CommonMethod） | `[C]common.d.ts:22642`（`@since 26.0.0`） |
| `SystemUiMaterial` | `[C]common.d.ts:16964` |
| `uiMaterial` 命名空间 | `[A]@ohos.arkui.uiMaterial.d.ts:32`、`:43`、`:465`、`:503`、`:365-366` |
| `bindSheet` / `SheetOptions` / `SheetType` / `SheetSize` | `[C]common.d.ts:21649`、`:11753`、`:11477`（`SIDE=11517`）、`:7947` |
| `bindContentCover` / `ContentCoverOptions` / `ModalTransition` | `[C]common.d.ts:21628`、`:11379`、`:6911` |
| `bindContextMenu` 家族 | `[C]common.d.ts:21495`、`:21511`、`:21526`、`:21541`、`:21562`；`CustomBuilderT` `:22841` |
| `ResponseType` / `HoverEffect` | `[C]enums.d.ts:2979`（`RightClick=2989`）、`:3009` |
| `bindPopup` / `bindTips` / `bindMenu` | `[C]common.d.ts:21452`、`:21434`（`bindTips` `@since 19`，见 `:21422-21433`）、`:21466`、`:21480` |
| `Tabs` 属性族 | `[C]tabs.d.ts:1054`、`:1066`、`:1079`、`:1095`、`:1108`、`:1174`、`:1313`、`:1355`、`:1452`、`:1467`、`:1479`、`:1548`、`:1576`、`:1589`、`:1605`、`:1636`、`:1683` |
| `TabsCacheMode` / `cachedMaxCount` | `[C]tabs.d.ts:229`、`:1605`（默认「全缓存不释放」见 `:1591-1592`） |
| `FloatingTabBarStyle`（含 `systemMaterial`） | `[C]tabs.d.ts:824`、`:895` |
| `TabContent.tabBar` 重载 / `onWillShow` / `onWillHide` | `[C]tab_content.d.ts:926`、`:952`、`:976`、`:993`、`:1010` |
| `List` 属性族 | `[C]list.d.ts:915`、`:948`、`:1195`、`:1227`、`:1276`、`:1328`、`:1360`、`:1423`、`:1439`、`:1452`、`:1573`、`:1592`、`:1605`、`:1624`、`:1641`、`:1661`、`:1690`、`:1701`、`:1713`、`:1744`、`:1756`、`:1768`、`:1780`、`:1800` |
| `StickyStyle` | `[C]list.d.ts:178`（`Header=201`、`Footer=212`） |
| `LazyForEach` 虚拟化前提 | `[C]lazy_for_each.d.ts:878`、`:881-883` |
| `Repeat` + `virtualScroll` | `[C]repeat.d.ts:297`、`:321`、`:339`、`:355`、`:373`、`:417`、`:430`；`VirtualScrollOptions` `:94`（`totalCount` `:127`、`onTotalCount` `:208`） |
| `Scroll` / `Scroller` | `[C]scroll.d.ts:351`、`:379`、`:395`、`:416`、`:428`、`:467`、`:533`、`:550`、`:566`、`:590`、`:612`、`:930`、`:1015`、`:1034`、`:1053`、`:1186`、`:1305`、`:1350`、`:1381` |
| `Refresh` | `[C]refresh.d.ts:281`、`:293`、`:305`、`:320`、`:337`、`:352`、`:383`、`:400` |
| `SideBarContainer` | `[C]sidebar.d.ts:27`、`:381`、`:396`、`:407`、`:419`、`:436`、`:453`、`:471`、`:488`、`:506`、`:525`、`:544`、`:562`、`:573`、`:587`、`:623` |
| `Grid` 无 `sticky` / `onScrollIndex` | `[C]grid.d.ts:561`；（`sticky` 命中 0） |
| `WaterFlow` 无 `sticky` / `cachedCount` | `[C]water_flow.d.ts:679`、`:705`、`:817`、`:428` |
| `RenderingContextSettings` / `CanvasRenderingContext2D` | `[C]canvas.d.ts:1213`、`:1250`、`:2787`、`:2908` |
| **`DrawingRenderingContext`** / `DrawingCanvas` / `Canvas` 重载 | `[C]canvas.d.ts:3360`、`:3371`、`:3382`、`:3392`、`:29`、`:3472`、`:3586` |
| `OffscreenCanvas` / `drawImage` | `[C]canvas.d.ts:3205`、`:3244`、`:3285`、`:3270`、`:3098`、`:3133`、`:1426`、`:1454`、`:1502` |
| `drawing` 命名空间与图元 | `[A]@ohos.graphics.drawing.d.ts:41`、`:734`、`:1666`、`:1689`、`:1794`、`:2018`、`:2033`、`:2084`、`:2174`、`:2191`、`:2218`、`:2247`、`:2264`、`:2335`、`:2380`、`:2478`、`:2641`、`:2959`、`:4528`、`:4909`、`:3821`、`:1594` |
| `XComponent` | `[C]xcomponent.d.ts:151`、`:171`、`:183`、`:196`、`:212`、`:225`、`:263`、`:277`、`:289`、`:381`、`:585`、`:597`、`:619` |
| `displaySync` | `[A]@ohos.graphics.displaySync.d.ts:26`、`:72`、`:81`、`:91`、`:98`、`:105` |
| `taskpool` / `worker` | `[A]@ohos.taskpool.d.ts:49`、`:134`、`:821`、`:841`、`:863`、`:883`、`:900`、`:923`、`:1269`；`[A]@ohos.worker.d.ts:816`、`:826`、`:1101` |
| 拖拽族 | `[C]common.d.ts:20636`、`:20650`、`:20664`、`:20678`、`:20694`、`:20713`、`:20727`、`:20757`、`:20770`、`:20811`、`:20844`、`:22612` |
| hover / key / gesture | `[C]common.d.ts:18556`、`:18569`、`:18581`、`:18607`、`:18618`、`:18643`、`:18656`、`:18687`、`:19002`、`:19023`、`:19041`、`:17311` |
| `vibrator` | `[A]@ohos.vibrator.d.ts:30`、`:126`、`:159`、`:261`、`:276`、`:291`、`:511`、`:520`、`:532`、`:542`、`:560`、`:569`、`:601`；Kit 再导出 `[K]@kit.SensorServiceKit.d.ts:20-21` |
| `promptAction` | `[A]@ohos.promptAction.d.ts:147`、`:156`、`:435`、`:1274`、`:1831`、`:1860`、`:1990` |
| `UIContext` | `[A]@ohos.arkui.UIContext.d.ts:725`、`:973`、`:997`、`:1013`、`:2987`、`:3016`、`:3038`、`:3066`、`:3239`、`:3264`、`:4555`、`:4703`、`:4834`、`:4903`、`:4926`、`:4937`、`:4953`、`:5239`、`:5323`、`:5352`、`:5374` |
| Pen Kit（HMS） | `[H]kits\@kit.Penkit.d.ts`（`@since 5.0.0(12)`）；`[H]api\@hms.stylus.HandwriteComponent.d.ets:13`、`:82`、`:98`、`:114`、`:131`、`:142`、`:151`、`:161` |
| `@kit.ArkUI` 导出（含 `uiMaterial`） | `[K]@kit.ArkUI.d.ts:115`、`:125` |

---

## 附录 B：本次审查的统计

| 项 | 数量 |
|---|---|
| 路线清单行数 | **45**（A1-A6=6；B1-B8=8；C1-C3=3；D1-D10=10；E1-E3=3；F1-F4=4；G1-G3=3；H1-H8=8） |
| 其中 **强烈推荐** | **8 条**：A6（材质合法入口）、B1（`List` 虚拟化）、D6（`bindSheet` 底部菜单）、D8（`bindContextMenuWithResponse`）、E3（`Tabs` + `barFloatingStyle` 底栏）、F1（Pen Kit 接线）、F2（绘制批处理/`DrawingRenderingContext`）、G1（力导向移出主线程） |
| 其中 **可选** | 23 条 |
| 其中 **不建议** | 13 条 |
| 纯引用行（无独立判定） | 1 条（H8「系统材质：见 A6」） |
| 附带的缺陷/不一致发现 | 3 条（H6 振动缺参+权限缺失（**已定性**）、D1 命令面板键盘导航缺失、D6 假拖动指示条） |
| 存疑项 | 9 条（其中 4.4、4.5 已在收尾阶段核验并收窄；4.9 仍未核验） |

> 说明：本报告只包含本次实际打开 d.ts 原文核对过行号的内容。凡仅通过 `grep` 命中名称而未打开原文的（4.4 `bindTips` 的**触发条件**、4.9 `MultiNavPathStack`/`SplitLayout`）均已显式列入第 4 节存疑项，未据此得出迁移结论。
