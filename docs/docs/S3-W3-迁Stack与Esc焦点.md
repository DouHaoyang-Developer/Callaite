# S3 · W3 迁 Stack（W13-2）+ Esc 焦点前提（W13-5）（EXEC-SPRINT-03 / W3）

> **窗口**：EXEC-SPRINT-03 / **W3** —— 两件事：① **U2.4 第 2 件后半「迁 Stack」**（`PLAN-UI-Alignment.md (v1.md:321`，登记号 **W13-2**）
> ② **W13-5「Esc 有焦点前提」**（计划 §U2.4 验收 `:326` 原文是「Esc 关闭」，**无前提**）
> **代码基线**：`2d71ae4`（S3-W2 交付，`git status --short` 开工时为**空** ✓）→ 本窗口交付后**未提交**（见 §7）
> **设备**：模拟器 **`MateBook Pro`（2in1）**，`hdc` 目标 `127.0.0.1:5555`；应用窗口 `[515,281,2090,1394]`（截图 3120×2080）。**一台设备一个任务** ✓（交还时仍在运行，见 §8）
> **交付改动**：**3 个文件**（`MainContainer.ets` · `BlockList.ets` · `FindInPage.ets`），**无新增文件**、**无探针** ✓

---

## 0. 结论速览

| # | 结论 | 证据等级 |
|---|---|---|
| **T1-1** | **开窗核实：迁移前 `FindInPage` 确实还在 `BlockList` 内联**（`BlockList.ets:313` 内嵌分支 / `:357` 整页分支）⇒ **本项不是「已迁、转验收」，是要做的活** ✓ | Ⓑ 源码 `grep`（§1） |
| **T1-2** | **迁 Stack 已实现并设备验收 ⇒ W13-2 闭合 ✓**：挂载点**唯一化**到 `MainContainer.build()` 顶层 `Stack`，渲染为**右上角浮动小卡**（380×44 vp，圆角 + 阴影） | Ⓐ 设备实测（§3） |
| **T1-3** | **判据的更正（重要）**：`Ctrl+Shift+F` 的**原始像素数只降了 46%**（88 609 → **47 529**），**远不是「覆盖面积变小」能解释的量级** —— 真正的判据是**几何**：差分 bbox 从**整条内容列**（`784×953`）塌缩成**右上角一小块**（`752×120`） | Ⓐ 设备实测（§3.2） |
| **T1-4** | **决定性判据（几何无关）**：搜索条打开前后，**卡片矩形以外的整块屏幕逐像素为 0 px**（内容列 0 px · 卡片下方 0 px · 半屏 0 px）⇒ 「**不再把 List 往下推**」被直接测出来 ✓（迁移前它占 Column 纵向空间，必定推动整条列表） | Ⓐ 设备实测（§3.2） |
| **T2-1** | **Esc 三态全过 ✓**（输入框持焦 0 px / 按钮持焦后节点归零 / 焦点在内容区 0 px）—— 修法是**三层落点 + 1 个根因修复**（§5） | Ⓐ 设备实测（§5.3） |
| **T2-2** | **根因不是路由器，是「焦点没人管」** ✗：`FindInPage` **从打开到关闭全程不碰焦点** ⇒ ① 按钮点完焦点离开本子树（Esc 落点收不到键）② **关闭后焦点谁都不在 ⇒ 所有全局快捷键一起失效** ✗（实测：Esc 关条后 `Ctrl+Shift+F` **再也打不开**） | Ⓐ 设备实测（§5.1/§5.2） |
| **T2-3** | **不破坏输入法的论据**：本次改动**一处 `onKeyPreIme` 都没有新增**；三个新落点与既有两处**全是 post-IME 的 `onKeyEvent`**；路由器只认 ↑/↓/Esc，**回车刻意不在其中**（走 `onSubmit`，由输入法在合成结束后发出）⇒ 与 `BlockEditor`（Enter 挂 preIme 并返回 true = 对输入法截胡）**不是同一条路径** ✓ | Ⓑ 源码逐行 + Ⓐ 设备（Esc 三态无副作用） |
| **T3-1** | **发现并修掉一条迁移引入的真回归** ✗→✓：迁出 `ContentArea` 后 ① 键入不再经过 `ContentArea` 的快捷键投递 ⇒ 卡片内 `Ctrl+K/F` 失效；② 关闭后焦点无人接管 ⇒ **全局快捷键全灭**。两条都在本窗口补回（`dispatchShortcut` / `restoreFocusId`）| Ⓐ 设备实测（§5.2 阳性对照：修前 0 节点、修后同值 47 529 px） |
| **T4-1** | **一条 ArkUI 布局事实（可推广）** ✗：在**没有显式 `alignContent`** 的 `Stack` 里，给**子节点**加 `.align(Alignment.TopEnd)` **不改变落点**（两次构建两次装机，卡片都落在正中）；真正生效的是**宿主 Stack 的 `alignContent`** ⇒ 本窗口改用「一个只服务定位的嵌套 `Stack({alignContent: TopEnd})` + `HitTestMode.None`」 | Ⓐ 设备实测（§2.3） |
| **T5-1** | 编译 `BUILD SUCCESSFUL` ✓ · **§7b 对抗性验证对 3 个改动文件逐个做** ✓ · 探针串残留 **0** ✓ · 行尾 CRLF **0** ✓ | Ⓐ / Ⓑ（§6） |

---

## 1. 任务·开窗第一步：核实**当前挂载点**（**不重复劳动** ✗）

**结论：未迁** ✗ —— `FindInPage` 当时仍内联在 `BlockList` 里，两处挂载点。

**grep 证据（开工时，HEAD `2d71ae4`）**：

```
$ git grep -n "FindInPage(" -- entry/src/main/ets
entry/src/main/ets/components/outliner/BlockList.ets:313:            FindInPage({ pageId: this.pageUuidForDrag })
entry/src/main/ets/components/outliner/BlockList.ets:357:            FindInPage({ pageId: this.pageUuidForDrag })
```

配套三行（同一份证据链）：

```
BlockList.ets:4    import { FindInPage } from './FindInPage';
BlockList.ets:132  @StorageLink('callaite_findInPageOpen') private findInPageVisible: boolean = false;
BlockList.ets:307  if (this.findInPageVisible) {     ← 内嵌分支（JournalFeed 的每一节）
BlockList.ets:355  if (this.findInPageVisible) {     ← 整页分支（PageView）
```

**判定**：`MainContainer` 里 **0 命中** `FindInPage` ⇒ **W12/W13 没有迁过** ⇒ 本项**要做**，不是转验收 ✓。
（`BlockList.ets:313/357` 的注释还写着 W13 修 `pageId` 的事 —— 说明那两处正是 W13 交付时留下的形态。）

**同时核实的计划原文**（**自己读，不凭转述** ✓）—— `docs/PLAN-UI-Alignment.md (v1.md`：

| 行 | 原文（逐字） |
|---|---|
| **`:321`** | `2. 渲染位置：从 BlockList 内联移到 MainContainer 顶部 Stack（ContentArea 之上，右上角浮动小卡，Obsidian 布局位）` |
| **`:322`** | `3. navigatePrev/Next：matchedUuids[current] → \`AnchorRegistry.locate()\` + 高亮（复用 U2.1）；匹配块内的**文本级高亮**沿用 SearchPanel 的 splitHighlight 段渲染（把匹配块临时切到高亮样式）` |
| **`:326`** | `**验收**：Ctrl+F → 输入 → Enter 循环跳转，每次跳转滚动+块高亮+块内文本高亮；Esc 关闭。` |

> **注**：计划 `:326` 写的 `Ctrl+F` 是**当时的键位口径**；本仓实际注册表（`ShortcutService.ets:530`）里
> **`Ctrl+F` = 全局搜索（SearchPanel）**，**`Ctrl+Shift+F` = 页内搜索（FindInPage）**（计划 `:303/:304` 的「用户决策 1」）。
> 本窗口的验收**一律以真实键位 `Ctrl+Shift+F` 执行**，并把 `Ctrl+F` 当作**阴性对照**用（§4）✓。

---

## 2. 任务 1 · 迁 Stack 的实现（文件:行号）

### 2.1 改动面

| 文件 | 改动 | 关键行号 |
|---|---|---|
| **`components\layout\MainContainer.ets`** | ① 新增 `@StorageLink('callaite_findInPageOpen') findInPageOpen`；② 新增 `findInPagePageId()`（**页名 → 真实 uuid**，口径与 `ContentArea.resolvePageName` 同源）；③ 在 `build()` 顶层 `Stack` 里**唯一挂载** `FindInPage`（右上角，嵌套 `Stack({alignContent: TopEnd})` + `HitTestMode.None`）；④ 根 `Stack` 加**宿主兜底** `onKeyEvent → OverlayKeyRouter.handleFromHost`（W13-5 的根因面） | `:76` 开合态 · `:180` `findInPagePageId` · `:349-368` 挂载 · `:520` 宿主兜底 |
| **`components\outliner\BlockList.ets`** | 删掉两处内联挂载 + `import { FindInPage }` + `@StorageLink('callaite_findInPageOpen') findInPageVisible`（该字段**全仓只被那两处 `if` 读**） | `:122-132`（原字段位置改为说明）· `:305` 与 `:353`（原挂载位置改为说明） |
| **`components\outliner\FindInPage.ets`** | ① 外观从「整宽横条」改成「380×44 vp 浮动小卡」（圆角 + 边框 + 阴影，`width('100%')` → `width(380)`）；② 上/下/关三个按钮各补 `onKeyEvent` 落点；③ `restoreInputFocus()`；④ `dispatchShortcut()`；⑤ `restoreFocusId` + **关闭时归还焦点**；⑥ 类尾新增 **§焦点契约**（三态判据表） | `:14` 输入框 id 常量 · `:83` `restoreFocusId` · `:113` 归还焦点 · `:322` `restoreInputFocus` · `:341` `dispatchShortcut` · `:437/470/492` 三个按钮落点 · `:521` 卡片样式 · `:527` 根部落点 · `:561+` §焦点契约 |

### 2.2 为什么放在**这一层**（Stack 的绘制顺序 = 层级）

`MainContainer.build()` 的根是 `Stack`，子节点按书写顺序叠放（后者在上）。挂载点插在**主体 `Row()` 之后、各模态浮层之前**：

```
Stack() {
  Column()  氛围渐变（HitTestMode.None）
  Row()     Ribbon | 左侧栏 | [TabBar + ContentArea + StatusBar] | 右侧栏
  ★ FindInPage（本窗口新增，唯一挂载点，右上角）★
  Column()  移动端顶栏/底栏（compact）
  FloatingPanel ×2 / NewFileDialog / VaultSwitcherDialog / TabOverlay / MobileMenu
}
```

三条理由：
1. **在主体之后** ⇒ 画在内容之上（这是「浮动」的前提；迁移前它挤在 `BlockList` 的 `Column` 里占纵向空间）；
2. **在各模态之前** ⇒ 模态（新建文件 / 仓库切换）打开时盖住它 —— 与 `OverlayKeyRouter` 的优先级表一致（`findInPage = 100`，是最底层浮层）；
3. **唯一挂载点** ⇒ 不可能出现两个实例各自 `registerOverlay`（那会让「一次按压走两步」）。

`pageId` 由 `findInPagePageId()` 解析：本组件手里只有 `callaite_currentPage`（**页名**），而 `FindInPage` 要 **uuid**。
口径与 `ContentArea.resolvePageName` 同源（`Journal` → 今天日期），**不换算就会在日记页上恒 0 匹配** —— 这正是 W13 修过的同一个坑（`@Prop pageId` 恒为 `''`）。

### 2.3 ⚠️ 一个折了两次的坑：`Stack` 子节点的 `.align()` 在本层**不生效** ✗（实测，两次构建两次装机）

| 尝试 | 写法 | 实测落点 |
|---|---|---|
| ① | `Column() { FindInPage(...) }.align(Alignment.TopEnd).margin({top:12,right:16})` | **窗口正中** ✗ —— 卡片中心 `(1544,1020)` vs 窗口 `[515,281,2090,1394]` 中心 `(1560,978)` |
| ② | `FindInPage(...).align(Alignment.TopEnd).margin({...})`（照抄 `BlockList` 里 `SlashMenu` 的同型写法） | **仍在正中** ✗ |
| ③ | `Stack({ alignContent: Alignment.TopEnd }) { FindInPage(...).margin({...}) }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)` | **右上角** ✓ |

**结论（可推广）**：`SlashMenu` 那条同型写法之所以生效，是因为它的宿主是 **`Stack({ alignContent: Alignment.Bottom })`** ——
**真正决定落点的是宿主 Stack 的 `alignContent`**；在默认（`Alignment.Center`）的 Stack 里，子节点自己的 `.align()` 不改变落点。
因此本窗口**不赌**子节点修饰符，改为显式给一个**只服务定位**的嵌套 `Stack`：

* `alignContent: Alignment.TopEnd` ⇒ 位置确定；
* `HitTestMode.None` ⇒ 该层**自身不参与触摸测试**（子节点与兄弟节点照常参与）⇒ **卡片以外的区域仍然点得到正文**，不多一块「挡板」（与文件顶部氛围渐变层同一模式）。

> 该推论**只在本仓本设备上实测成立** ✗（真机 / 其它 API 版本未验，见 §9）。

---

## 3. 任务 1 · 验收（**整屏像素差分**，验证纪律 8）

### 3.1 现场与判据量

| 项 | 值 |
|---|---|
| 设备 / 窗口 | `MateBook Pro`（2in1），`callaite0` 窗口 `[515,281,2090,1394]`（`hidumper -s WindowManagerService`） |
| 截图 | `snapshot_display` 3120×2080；**差分裁到 `(0,0)-(3120,1940)`**（避开系统任务栏时钟） |
| 稳定性对照 | **同一状态连拍两张 ⇒ 0 px** ✓（脚本同一次运行、同一把尺子） |
| 像素判据 | 「**任一通道有差异**」的像素计数 + 差分 bbox（与 W13 同口径） |

### 3.2 三组基准（**同一次会话、同一个窗口几何、同一份脚本**）

| 注入 | 本窗口（**迁 Stack 后**） | W13（**迁移前**，同仓文档 §6） | 判定 |
|---|---|---|---|
| **`Ctrl+K`**（快速切换） | `bbox=(1104,424,3114,1940)` · **379 549 px** | `bbox=(1104,424,3114,1969)` · **385 190 px** | 同一量级 ✓ **未回归**（W12: 385 908） |
| `Esc` | **`bbox=None` · 0 px** | 0 px | **逐像素回基线** ✓ |
| **`Ctrl+F`**（全局搜索） | `bbox=(1104,424,3114,1940)` · **1 182 058 px** | `bbox=(1104,424,3114,1969)` · **1 188 841 px** | 同一量级 ✓ **未回归** |
| `Esc` | **0 px** | 0 px | ✓ |
| **`Ctrl+Shift+F`**（页内搜索，**本窗口交付的本体**） | `bbox=(1840,360,2592,480)` · **47 529 px** | `bbox=(1192,671,1976,1624)` · **88 609 px** | **−46.4%**，且**几何完全不同**（见下） |
| `Esc` | **0 px** | 0 px | ✓ |

> **几何才是主判据**：差分 bbox 从 **`784×953`（整条内容列，含被推下去的列表）** 塌缩为 **`752×120`（右上角一小块）**。
> ⚠️ **对用户口径的一处更正** ✗：任务里预期的「`Ctrl+Shift+F` 组应**显著下降**」**只兑现了一半** ——
> 原始像素数 88 609 → 47 529（−46%），**不是数量级下降**。原因是**两边面积本来就接近**：
> 迁移前那条是「内容列宽 × 44 vp 高」的横条（≈784×88）+ 列表位移；迁移后这张卡是「380 vp × 44 vp」（≈752×88）+ 它盖住的右侧栏顶部。
> ⇒ **「迁成功」不能只靠这一组数字判**，真正的判据是 §3.3 的**几何无关**证据。**不得把 47 529 写成「显著下降」** ✗。

### 3.3 决定性判据：**卡片以外的屏幕逐像素不动**（几何无关）

把 `Ctrl+Shift+F` 打开态与**同一次会话的基线**比，**按区域切**：

| 区域 | 与基线的差分 | 含义 |
|---|---|---|
| `(0,0)-(1840,1940)`（卡片左侧 = 左栏 + 整个内容列 + 页头） | **`bbox=None` · 0 px** | **List 一行都没动** ✓（迁移前这里必定整列变，因为横条把列表推下去了） |
| `(1150,300)-(1830,1900)`（内容列，排除卡片） | **0 px** | 同上，收窄复核 |
| `(1840,520)-(2600,1700)`（卡片正下方的右侧栏） | **0 px** | 卡片外的右侧栏也没动 ✓ |
| 卡片自身 `(1840,360)-(2592,480)` | 47 529 px | 只有这张卡在变 ✓ |

⇒ **「浮层不再占布局空间、只覆盖右上角一小块」被直接测出来** ✓ ——
这正是计划 `:321` 要的「**ContentArea 之上，右上角浮动小卡**」，也是「迁 Stack」区别于「内联」的**本质**。

### 3.4 位置与节点的双重钉定

| 判据 | 实测 |
|---|---|
| 卡片实际矩形（像素差分 bbox） | `(1840,360)-(2592,480)` = **752×120 px**（密度 2 ⇒ **376×60 vp**，含阴影外溢；卡片本体 `380×44 vp`） |
| 卡片矩形在窗口中的方位 | 距窗口右边 `2605−2592 = 13 px`（≈ `right:16 vp` 去掉阴影）· 距窗口上边 `360−281 = 79 px`（≈ 标题栏 40 px + `top:12 vp`）⇒ **右上角** ✓ |
| `dumpLayout` 按 `id` 查（验证纪律 8：不看文本看 id） | `callaite_findInPageInput` **=1** · `callaite_findInPagePrev` **=1** · `callaite_findInPageNext` **=1** · `callaite_findInPageClose` **=1** · `callaite_findInPagePlaceholder` **=0** ✓ |
| 输入框 bounds | `[1922,384][2291,445]` —— **落在卡片 bbox 内** ✓（亦可反证 bbox 不是误判） |

### 3.5 全链路（计划 `:326` 三样 + Esc）

夹具 = 现有页 `2026-09-30`（**1037 块**；查询词用**单字符 ASCII**，理由见 §9）。查询 `o` ⇒ **3 个命中**。

| 步 | 动作 | 观测 | 判定 |
|---|---|---|---|
| 1 | `Ctrl+Shift+F` → 点输入框 → 注入 `o`(2031) | 计数 **`1/3`**；输入框 `text='o'` | 搜索生效 ✓ |
| 2 | 向下 `swipe` **6 次**（把命中块甩出视口） | 窗口内 `#FEF08A`（文本级高亮色）**0 px** | 命中**在视口外** ✓（先造难度，防「本来就在视口里」✗） |
| 3 | 点「下一个」 | 计数 **`1/3 → 2/3`** · 窗口内差分 **132 350 px** · `#FEF08A` **84 px** @ `y=624..654` | **滚动 + 跳块** ✓ |
| 4 | 再点「下一个」 | `2/3 → 3/3` · `#FEF08A` **178 px** @ `(1391,624)-(1703,654)` | ✓ |
| 5 | 再点「下一个」 | **`3/3 → 1/3`** | **循环** ✓ |
| 6 | **块高亮**（跳转瞬间抓帧） | `#E3E5E8`（`surface2`，闪块底色）在 `(1400,600)-(1800,700)`：**20 160 / 18 028 / 26 451 px**（三次抓帧） —— **阴性对照**：无搜索条时 **213 px**、搜索条开着但命中不在视口时 **200 px** | **块高亮** ✓（约 **100×** 于对照） |
| 7 | **块内文本高亮** | `#FEF08A` **0 → 84 / 178 / 192 px** | ✓ |
| 8 | `Esc` | `callaite_findInPage*` **全部 = 0** · `#FEF08A` **= 0** | **关闭 + 高亮清除** ✓ |

> **关于「Esc 后逐像素回基线 = 0 px」**：三组基准（§3.2，**未做跳块**）**每一组都是 0 px** ✓。
> 全链路（第 2–5 步做过跳块）之后再 Esc，与「未导航基线」的残差是 **52 432 px** ——
> 经核对**残差全部是列表滚动位置**（跳块把列表滚到目标块），**不是搜索条或高亮的残留**：
> 同一帧 `callaite_findInPage*` = 0、`#FEF08A` = 0 ✓。**这一条如实写，不写成 0 px** ✗。

### 3.6 阴性对照与键位隔离（**按 id 双向钉住**）

| 注入 | `searchPanelInput` | `commandPaletteInput` | `callaite_findInPageInput/Next/Prev/Close` | `callaite_findInPagePlaceholder` | 判定 |
|---|---|---|---|---|---|
| **`Ctrl+F`** | **1** | 0 | **0 / 0 / 0 / 0** | 0 | **W12-4 阴性不回退 ✓**（`Ctrl+F` **不**触发页内搜索） |
| **`Ctrl+K`** | 0 | **1** | **0 / 0 / 0 / 0** | 0 | 未串 ✓ |
| **`Ctrl+Shift+F`** | **0** | **0** | **1 / 1 / 1 / 1** | **0** | **不属于全局搜索** ✓ · 本体（非占位）✓ |

---

## 4. 任务 2 · W13-5「Esc 有焦点前提」——根因与修法

### 4.1 根因（**不是路由器，是「焦点没人管」**）

W13 登记的措辞是「按钮点击后焦点不留在 FindInPage 的 `Row` 子树内」。本窗口把它拆成**两条可测的事实**：

1. **按钮持焦态**：点过上/下之后注入 `Esc` ⇒ 搜索条**不关** ✗（W13 已登记）。
2. **关闭后焦点无人接管**（**本窗口新发现**）✗：`Esc` 关掉搜索条之后，**焦点谁都不在** ⇒
   `ContentArea` 的全局快捷键落点（挂在**内容区焦点容器**上）收不到键 ⇒ **`Ctrl+Shift+F` 再也打不开搜索条** ✗。
   **实测证据**：关条后注入 `Ctrl+Shift+F` ⇒ `dumpLayout` 里 `callaite_findInPageInput` **= 0**（没开）；
   **点一下正文**（把焦点还给内容区）再注入同一个组合键 ⇒ **立即打开** ✓。

> 两条同源：**`FindInPage` 从打开到关闭，全程不碰焦点** —— 它既不抢、也不还。
> W13 报告里的「根因未深挖」到此收敛。

### 4.2 修法：**三层落点 + 2 个补投**（自定 ✓，理由如下）

任务给的二选一是 (a) 按钮后焦点回输入框 / (b) Esc 处理上浮不依赖焦点。**本窗口两个都做**，因为**单做任何一个都不闭合**：

| 层 | 落点 | 覆盖态 | 为什么必须有 |
|---|---|---|---|
| ① | `TextInput.onKeyEvent` → `OverlayKeyRouter`（**既有**） | 输入框持焦 | 原路径，未动 |
| ② | **上/下/关三个按钮各自的 `onKeyEvent`** → 路由器（**新增**） | 按钮持焦 | 这是 W13 现象的直接面：焦点在按钮上时，键只会经过按钮自己与它的**祖先**；按钮**自己的**落点是最近的一环 ✓ |
| ③ | 卡片根 `Row.onKeyEvent` → 路由器（**既有**，保留） | 卡片内其它位置 | 兜底 |
| ④ | **`MainContainer` 根 `Stack.onKeyEvent` → `handleFromHost`（新增）** | **焦点谁都不在 / 焦点在内容区以外** | **根因修复面**。焦点「谁都不在」时 ArkUI 把键投给**根容器**；`ContentArea` 那份宿主兜底（`ContentArea.ets:243`）在**迁 Stack 之后**已经够不到（本组件不再是它的后代）⇒ 兜底必须上浮到**整页根容器** |
| (a) | **`restoreInputFocus()`：点完上/下把焦点要回输入框**（新增） | 按钮持焦（UX 侧） | ④ 只保证「能关」；不还焦点则**点完「下一个」再按 ↵ / 继续打字都没有落点**（循环跳转变成一堆鼠标点击）。`focusControl.requestFocus` = 用户「点回输入框」的同一动作 ✓ |
| (a′) | **`restoreFocusId` + 关闭时归还焦点**（新增） | 关闭后 | 修 §4.1 的第 2 条（全局快捷键全灭）。与 `SearchPanel.RESTORE_FOCUS_ID` / `CommandPalette.restoreFocusId` **同一个 id、同一条既有约定**（`'contentAreaScroll'`）✓ |
| (b′) | **`dispatchShortcut()`：卡片内 ctrl/alt 组合转投 `ShortcutService`**（新增） | 卡片内任意焦点 | 迁 Stack 的**直接后果**：迁移前键入经 `ContentArea.onKeyPreIme/onKeyEvent` 进快捷键表，迁出后这条通路断了 ⇒ 卡片内 `Ctrl+K/F` 失效。判据**逐字照抄** `ContentArea.onKeyPreIme` 的两行（仅 ctrl/alt）✓ |

**为什么不给按钮加 `.focusable(false)`**（W13 报告里的备选）：那会让**键盘用户（Tab 遍历）永远够不到**上/下/关三个按钮 ——
用一个可达性缺陷换另一个，不取。**为什么不只做 (a)**：`requestFocus` 可能落空（离屏 / 布局未完成），
**单个落点不足以关闭一条 ✗ 态**；四层共用 `OverlayKeyRouter` **同一份去重标记** ⇒ 一次按压只走一步，不会双触发 ✓。

### 4.3 为什么**不破坏输入法**（W9 教训逐条对照）

W9 的教训是：`BlockEditor` 的 Enter 落在 `onKeyPreIme` 且**返回 true** ⇒ 对输入法「截胡」
（SDK 顺序 `preIme → keyboardShortcut → input method events → onKeyEventDispatch → onKeyEvent`，`common.d.ts:18672-18687`）。

| 项 | 本窗口 |
|---|---|
| 新增 `onKeyPreIme` | **0 处** ✓（`git diff` 可查） |
| 三个新落点（按钮 ×3 + 根 Stack ×1） | **全是 post-IME 的 `onKeyEvent`** ✓ ⇒ 输入法**先拒绝**，它不要的键才轮到应用 |
| 路由器可路由的键 | 只有 **↑ / ↓ / Esc**（`OverlayKeyRouter.isNavKey`）✓ |
| **回车** | **刻意不在** `isNavKey` 里 —— 走 `TextInput.onSubmit`，由输入法在**合成结束之后**发出（组词中的回车被输入法吃掉、不触发 `onSubmit`）✓ |
| `restoreInputFocus` / `restoreFocusId` | 只做 `focusControl.requestFocus`（= 用户点一下控件），**不改变任何按键的消费顺序** ✓ |
| `dispatchShortcut` | 只转 **ctrl/alt 组合**键（与 `ContentArea.onKeyPreIme` 同一判据）—— 它们不参与拼音组词 ✓ |
| 与块编辑器的区别 | `BlockEditor` 要抢的是**回车**（会与组词上屏冲突）；本浮层**只碰 Esc/↑/↓**，回车全交给输入法与 `onSubmit` ✓ |

⇒ **本窗口对 `Esc` 的处理是「加落点」，不是「抢占 preIme」** —— 与 W9 的问题**不在同一条路径**上 ✓。

### 4.4 Esc 三态验收（设备实测）

| 态 | 重现方式 | 判据 | 结果 |
|---|---|---|---|
| ① **输入框持焦** | `Ctrl+Shift+F` → 点输入框 → 注入 `Esc(2070)` | 与基线整屏差分 | **0 px** ✓ |
| ② **按钮持焦** | `Ctrl+Shift+F` → 点输入框 → 注入 `o` → **点「下一个」** → 立刻注入 `Esc` | `dumpLayout` 按 id 查 + 高亮色扫描 | `callaite_findInPage*` **全部 = 0** ✓ · `#FEF08A` **= 0** ✓（与基线残差 **52 432 px = 跳块造成的列表滚动位移**，**不是**搜索条残留 —— 如实标注 ✗） |
| ③ **焦点不在搜索条里** | `Ctrl+Shift+F`（**不点卡片**，焦点留在内容区）→ 注入 `Esc` | 与基线整屏差分 | **0 px** ✓ |

**修前对照（② 的阴性）**：W13 登记「点过按钮后 Esc 不关」✗；本窗口修后在**同一注入序列**下节点归零 ✓。

### 4.5 焦点归还的阳性对照（§4.1 第 2 条的修复）

| 步 | 动作 | 修前（本窗口复现） | 修后 |
|---|---|---|---|
| 1 | `Ctrl+Shift+F` → `Esc`（关条） | —— | —— |
| 2 | 再注入 `Ctrl+Shift+F` | `callaite_findInPageInput` **= 0** ✗（打不开）；**点一下正文**才恢复 ✓ | **打开** ✓，整屏差分 `bbox=(1840,360,2592,480)` · **47 529 px** —— 与首次打开**逐字节同一组数** ✓ |

---

## 5. 回归面

### 5.1 本窗口复跑（设备）

| 项 | 结果 |
|---|---|
| `Ctrl+K` / `Ctrl+F` / `Ctrl+Shift+F` 三组开合 | 全部正常，Esc 后 **0 px** ✓（§3.2） |
| 键位隔离双向 | ✓（§3.6） |
| `Ctrl+Shift+F` 本体（非占位） | ✓（`Placeholder=0`） |
| 关闭后全局快捷键仍可用 | ✓（§4.5，**修前 ✗**） |

### 5.2 **E 组（E1–E20）未复跑** ✗（如实登记）

**源码级论证**（不是「应该没事」，而是**改动面交集为空**）：

* `git diff --stat` = **3 个文件**，全部在 `components/`：`layout/MainContainer.ets` · `outliner/BlockList.ets` · `outliner/FindInPage.ets`；
* **未触碰**：`core/engine/**`（`OutlinerEngine`/`BlockTree`/`OutlinerOps`/`MarkdownExporter`）· `core/db/**`（`DataStore`/`IndexStore`/`FileRepository`）· `core/models/**` · `services/**`（含 `EditorService`/`SaveQueue`/`DirtyPageTracker`/`BlockAnchorService`/`ShortcutService`/`WorkspaceService`/`AnchorRegistry`）· `components/outliner/BlockEditor.ets` · `WebEditor.ets` · `IntegralEditor.ets` · `BlockView.ets` · `state/**`；
* ⇒ **E1–E11、E13–E20（打字落盘 / 回车建块 / 缩进 / 撤销重做 / 行刷新 / 性能与内存）的代码路径 = 零交集** ✓；
* **E12（Esc）**：本窗口**只新增落点、没有改任何既有 Esc 语义**（`applyNavKey` 的 ESC 分支一字未动；三组基准的 `Esc ⇒ 0 px` 直接复跑了「不写坏数据 / 可关闭」这一面 ✓）；
* `BlockList` 的改动是**删挂载 + 删一个只服务挂载的 `@StorageLink`**，`refreshBlocks` / `LazyForEach` / `keyGenerator` / `scroller` 全部未动 ✓。

> **未复跑就是未复跑** ✗ —— 上表只是**代码级**论证，**E 组的设备判据本窗口没有重跑**（本窗口定位是 U2.4 两件，不是全量回归窗口）。

---

## 6. 编译、安装与纪律

| 项 | 结果 |
|---|---|
| 编译 | **`BUILD SUCCESSFUL`** ✓（多次；改动后首次 / 还原 §7b 注入后 / 末版各一次） |
| **§7b 对抗性验证**（3 个改动文件**逐个**做） | 向三个文件各注入 `const __S3W3_TYPE_CHECK: number = 'deliberate-string';` ⇒ **构建失败 4 error**，报错**逐个落在文件内**：<br>`BlockList.ets:85:7` · `FindInPage.ets:57:7` · `MainContainer.ets:51:7`（均为 `Type 'string' is not assignable to type 'number'`）✓ ⇒ **三者都确在编译图里**；撤销后**复绿** ✓ |
| 更强的一层（运行时） | 末版新增的 `restoreFocusId` / `restoreInputFocus` 代码产生了**可观测的行为变化**（§4.5）⇒ 「被编译并在运行」由**运行时行为**直接证明，强度高于注入法 ✓ |
| 安装 | `hdc install -r`（**未用 `uninstall`** ✓）；`updateTime` **逐次前进**：`1790931091951`（开工时已装的 S3-W2 版）→ `1790931819405` → `1790931925777` → **`1790932289582`（末版）** ✓（**不用 HAP MD5**，陷阱 27） |
| 行尾 | 3 个改动文件 **CRLF = 0** ✓（陷阱 10；Python 字节级核对） |
| 探针残留 | 全仓 `git grep "S3W3_TYPE_CHECK\|__S3W3"` = **0 命中** ✓（`W11PROBE` 在 `OverlayKeyRouter.ets:58` 有 1 命中，是**既有注释里提到探针名**，本窗口未改该文件、HEAD 里也有 —— **不是残留** ✓） |
| 禁区 | **未触碰** `main_pages.json` · `rawfile/spike/*` · `rawfile/libs/**` ✓ · **未加任何页面级探针** ✓ · 启动链未插桩 ✓ |
| 临时产物 | 全部落在 `%TEMP%\callaite_w3\`（截图 / 差分脚本 / dump json），**仓库内 0 新增** ✓ |
| `git status --short` **前**（开工时） | **空** ✓（= `2d71ae4` 干净树） |
| `git status --short` **后** | 恰好 **3 个 ` M`**：`MainContainer.ets` · `BlockList.ets` · `FindInPage.ets` —— **无 `??`、无未跟踪产物、无探针** ✓ |
| 提交 | **未提交**（本窗口只交付到工作区 + 本报告；按纪律逐个列文件提交，**禁用 `git add -A/-u`**） |

---

## 7. 对症 vs 顺手加固（**分开说明** ✓）

| 类别 | 项 | 为什么算这一类 |
|---|---|---|
| **对症（迁 Stack 本身）** | ① `MainContainer` 唯一挂载 + 右上角定位（嵌套 `Stack` + `HitTestMode.None`）② 删 `BlockList` 两处内联挂载 + 其 `@StorageLink` ③ `findInPagePageId()`（页名 → uuid）④ 卡片外观 `width('100%')` → `width(380)` + 圆角/阴影/边框 | 计划 `:321` 的字面要求；不做就不算迁 |
| **对症（W13-5）** | ⑤ 三个按钮的 `onKeyEvent` ⑥ `restoreInputFocus()` ⑦ `restoreFocusId` + 关闭归还焦点 ⑧ `MainContainer` 根 `Stack` 的宿主兜底 | 都是「Esc 有焦点前提」这条 ✗ 的直接面：⑥⑦ 管「焦点该在哪」，⑤⑧ 管「键该到哪」；**不做任何一条都会留一个 ✗ 态** |
| **对症（迁移的必然连带）** | ⑨ `dispatchShortcut()` | **不是**可选加固：迁出 `ContentArea` 后卡片内 `Ctrl+K/F` **实测失效** ✗（通路断在拓扑上），不补就是回归 |
| **顺手加固** | —— **本窗口没有** ✗ | 唯一「多出来」的是把 W12/W13 的旧注释更新成迁移后的事实（纯注释）；**没有**改任何引擎/服务/编辑器/解析/落盘代码 |

---

## 8. 交还时的实例与 vault 状态

| 项 | 状态 |
|---|---|
| **实例** | **`MateBook Pro`（2in1）运行中** ✓ —— 本窗口**未换实例、未重启设备**（未触发陷阱 26 的场景）· **一次只跑一个实例** ✓ · 开工时设备**原本没在跑**，用 `emulator.exe -hvd 'MateBook Pro'` 拉起（`-start` 名字带空格过不了参 ✗）· 设备曾锁屏，已 `power-shell wakeup` ✓ |
| **已装包** | 本窗口末版 · `updateTime=1790932289582` ✓ |
| **屏幕** | 应用停在前台，页 `2026-09-30`；FindInPage **已关闭**（`callaite_findInPage*` = 0）· 右侧栏反链面板开着 ✓ |
| **vault** | `2026-09-25.md` = **76 B**（2026-10-02 16:48）· `2026-09-30.md` = **3954 B / 1037 行 / MD5 `c9f23996c6c3d6f381c6248d1db0e159`** · `未命名.md` = **93 B**。三者**各复读两次一致** ✓（陷阱 24） |
| **对 vault 的影响（如实登记）** ✗ | `2026-09-30.md` 在 **19:19（设备时间 ≈ 本窗口 17:07）** 被写过一次：**W13 交还时是 3928 B**，现在是 **3954 B（+26 B）**。原因是本窗口做**输入注入验收**时，`o` 键经 2in1 的中文输入法**同时**落进了搜索框与第 1 块（该行现为 `- 你好TODO 📌 今日要点: nihao` 形态）。**这是注入通道的副作用，不是代码改动造成的** ✓（此后 20 分钟内该文件字节与 MD5 未再变化）。该页**本来就是前几个窗口留下的夹具**（磁盘里已有 3 行含 `nihao`），**未做清场**（vault 不可由 shell 写 ⇒ 清场需另想办法，陷阱 23/§7c）|
| **vault 可写性** | 本窗口**未重跑** shell 写入阳性对照 ✗（沿用 W7/W12：`touch` ⇒ `Permission denied`）；全程未从 shell 写 vault ✓ |
| **残留的未归因现象** | 该夹具页在**内存模型 / 渲染**上出现过与磁盘不一致的形态（首块带 IME 残留文本、行序与磁盘不同；`aa force-stop` + 冷启动后**与基线逐像素相同 = 0 px**）⇒ 属 **W1b / W13-3 家族**，**未归因** ✗；本窗口的改动**不写任何数据**，且磁盘 MD5 在观察窗口内不变 ✓ |

---

## 9. 不可自证项 / 未验项（**如实列出**）

1. **`Ctrl+Shift+F` 像素数「只降 46%」这一事实与用户预期不符** ✗ —— 本报告给出的是**几何判据**（bbox + 卡片外 0 px）。
   若上级口径坚持「必须显著下降」，那需要**把卡片做小**（改 UI 取舍）**或**改用「内容列 0 px」作为正式判据 —— **本窗口不改判据去迁就数字** ✗（验证纪律 5）。
2. **`Stack` 子节点 `.align()` 不生效** 的结论只在**本机 2in1 + API 26 + 这个根 Stack**上实测 ✗；未查 SDK 文档、未在真机复验。**它不是「ArkUI 一定如此」的通则**。
3. **手势层面未验**：`-slide`/`swipe` 只能滚动（陷阱 13）；「按住拖动滚动卡片」这类真实手势**注入不可达** ✗。
4. **多字符命中词的块内高亮仍缺设备证据** ✗（= 既有 `W13-1`）：本窗口只能注入**单字符 ASCII**（`-fill`/`uitest uiInput text` 不触发 `onChange`；2in1 注入字母**过 IME**，会被组词/迟提交污染）。本窗口因此**改用单字符查询 `o`**（3 个命中）完成全链路验收 ✓，**但多字符仍未验** ✗。
5. **块高亮的抓帧是「尽力而为」**：`#E3E5E8` 的 20 160 px 是**点完「下一个」后立刻截图**拿到的（闪块是瞬态）；**未测闪块持续时长** ✗，三次抓帧的矩形略不同（18 028 / 20 160 / 26 451）即为此故 —— **但都 ≫ 对照的 200/213 px** ✓。
6. **E 组本窗口未复跑** ✗（§5.2 只有代码级论证）。
7. **该夹具页「内存模型 ≠ 磁盘」的现象未归因** ✗（§8 末）。
8. 本报告所有设备结论**只在 `MateBook Pro`（2in1 模拟器）成立** ✗；真机未验（= S3-5 口径）。
9. **`Ctrl+Shift+F` 关闭后焦点归还的 id 是硬编码默认值 `'contentAreaScroll'`**（主窗格）—— **分屏（二级窗格）下未验** ✗：二级窗格的焦点容器 id 是 `contentAreaScroll_<paneId>`，本窗口**未传**该值（`FindInPage` 挂在 `MainContainer`，那里拿不到 `paneId`）。

---

## 10. 对 `AGENTS.md` / 后续窗口的建议

1. **新增陷阱（ArkUI 布局）**：**`Stack` 子节点的 `.align()` 不一定生效** —— 决定落点的是**宿主 Stack 的 `alignContent`**。
   判据 = **像素 bbox 落在预期的角**（本窗口的「卡片落在正中」就是这么发现的）；修法 = 嵌套一个 `Stack({alignContent: …})`，
   并用 `HitTestMode.None` 让它**不吃触摸**（`None` = 自身不参与、子与兄弟照常参与 ✓）。
2. **补强陷阱族「浮层要管焦点」**：本仓已有约定「浮层关闭时归还焦点」（`CommandPalette.restoreFocusId` / `SearchPanel.RESTORE_FOCUS_ID`），
   但 **`FindInPage` 一直没接** ⇒ 表现为**关闭后所有全局快捷键失效**（§4.1-2），**极易被误判成「快捷键坏了」** ✗。
   ⇒ 凡新增/迁移浮层，**打开慢一点没关系，关闭必须还焦点** ✓。
3. **「迁 Stack」这类位置迁移，判据必须是几何**：像素数会因「新位置压住的东西比旧位置多」而**不降反平**（本例 −46%，不是数量级）。
   ⇒ 用 **bbox 形状** + **「卡片外逐像素 0 px」** 判 ✓。

---

**维护规则**：本窗口两项交付已按 §3 / §4 / §5.1 的设备判据闭合 ✓；**§5.2（E 组未复跑）与 §9 的九条不得写成已通过** ✗，须随 `docs/待验收清单.md` 与 `docs/S3-回归矩阵-编辑器行.md` 一起清账。
