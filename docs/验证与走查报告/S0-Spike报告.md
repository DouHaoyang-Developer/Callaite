# S0 Spike 报告（执行总纲 §1 · M0 交付物）

- **版本**：v1.0｜**日期**：2026-09-27｜**状态**：类型层已定论 3 项，运行期探针 4 项待跑
- **执行人**：AI（DSH 会话）｜**依据**：`EXEC-MASTER-PLAN.md` §1（S0 阶段，5 项 spike）
- **证据分级**：`T`=SDK 类型定义（可复核，硬证据）｜`C`=代码结构（可复核，硬证据）｜`R`=运行期实测（**未取得**，需上机）

---

## 0. 结论速览

| # | Spike | 现状判定 | 证据 | 对设计的影响 |
|---|---|---|---|---|
| ① | ArkWeb MessagePort 双向往返 | **API 存在（T）**；延迟/JSON 完整性**待测（R）** | `@ohos.web.webview.d.ts:1792/1822/1835` | 若 <5ms 且 JSON 无损 → 采用 MessagePort；否则回退字符串通道（协议层已解耦） |
| ② | `$rawfile` 相对路径 | **API 存在（T）**；HTML 内相对引用 CSS/JS **待测（R）** | `common.d.ts:1917` `declare function $rawfile(value: string): Resource` | 决定 JS 端能否「零构建」（多个 .js/.css 文件）还是必须内联单文件 |
| ③ | `bindContextMenu` 双绑 | **API 单参数（T）**→ 双绑只能**链式两次调用**，行为**待测（R）** | `common.d.ts:21495` `bindContextMenu(content, responseType, options?)`；`ResponseType` 含 `RightClick` | 若能双绑 → 2in1 触屏同时支持右键与长按；否则形态二选一（方案已备降级） |
| ④ | 渲染层可寻址化 | **`scrollToIndex` 存在（T）** + **容器现状确认为 Scroll（C）** | `scroll.d.ts:533` `scrollToIndex(value, smooth?, align?, options?)`；`BlockList.ets:101-113` = Stack→Column→LazyForEach | **路线 A（Scroll→List）API 可行**；路线 B（粗滚物化）不依赖该 API。二选一由实测物化时延决定 |
| ⑤ | `pdf.worker` rawfile 化 | **无 SDK 类型面**（引擎加载行为） | — | 决定 U3.5「离线 PDF」能否成立；失败则 PDF 需保留联网或换渲染方案 |

**一句话**：5 项里 **①④ 的 API 面已排除「不存在」风险**，②③⑤ 属引擎行为，**必须在设备上跑探针**才能定论。S0 尚未闭合。

---

## 1. 逐项详述

### ① ArkWeb MessagePort 双向往返
**类型层（T，已定论）**：SDK 提供完整接口 —— `interface WebMessagePort`（1792）、`postMessageEvent(message: WebMessage): void`（1822）、`onMessageEvent(callback)`（1835），另有 `onMessageEventExt` / `WebMessageExt`（1528、1774）支持结构化类型。**「API 不存在」这一失败风险已排除。**

**待测（R）**：双向 echo 的往返延迟（决策阈值 <5ms）与 JSON 无损性（中文、emoji、嵌套对象、10KB 级负载）。
**探针设计**：rawfile 内 HTML 建 `messageChannel` → N 次 echo → JS 侧记录 `performance.now()` 差值 → 汇总经通道回传 → ArkTS 侧打印。判定：中位延迟 <5ms 且 N=1000 次无损坏 → 采用。

### ② `$rawfile` 相对路径
**类型层（T）**：`declare function $rawfile(value: string): Resource` 存在。

**待测（R）**：WebView `src($rawfile('spike/index.html'))` 加载后，HTML 内的 `<link href="style.css">` 与 `<script src="app.js">` 能否按相对路径解析（引擎是否把 rawfile 目录映射为可解析的 base URL）。这是「JS 端零构建」的成立前提。
**探针设计**：rawfile 放 `spike/index.html` + `spike/style.css`（设一个可测的 `body` 背景色）+ `spike/app.js`（写入 `document.title`）→ 加载后由 ArkTS 侧用 `runJavaScript('document.title')` 与截图双证。
**回退**：全部内联为单个 HTML（牺牲可维护性，不阻塞其它 WP）。

### ③ `bindContextMenu` 双绑
**类型层（T）**：签名 `bindContextMenu(content: CustomBuilder, responseType: ResponseType, options?: ContextMenuOptions): T` —— **只有一个 `responseType` 参数**。因此「同一节点同时支持右键与长按」只能写成两次链式调用。`ResponseType` 枚举含 `RightClick`（已见），`LongPress` 需确认成员名（**未验证**）。

**待测（R）**：同一节点链式两次 `bindContextMenu` 是否两个都生效、是否互相覆盖。
**探针设计**：一个 `Row` 连续两次 `.bindContextMenu(@Builder, ResponseType.RightClick)` 与 `(…, ResponseType.LongPress)`，各自弹不同文案的菜单 → 桌面形态测右键、2in1/触屏测长按，记录实际弹出哪一个。
**影响**：U1.1 的桌面右键菜单与 2in1 长按菜单能否统一实现。失败则按形态二选一（方案降级已备，可接受）。

### ④ 渲染层可寻址化
**类型层（T，已定论）**：`scroll.d.ts:533` 存在 `scrollToIndex(value: number, smooth?: boolean, align?: ScrollAlign, options?: ScrollToIn...)` —— **路线 A 的 API 前提成立**。
**代码结构（C，已定论）**：`BlockList.ets:101` `Stack` → `:102` `Column` → `:113` `LazyForEach`；全仓 `Scroller` 0 命中、`scrollToIndex` 0 命中，真正滚动宿主是 `ContentArea.ets:71-80` 的外层 `Scroll`（不支持 `scrollToIndex`）。**与 UI 方案 v1.0 的前提矛盾已由 v1.1 修正收录。**

**待测（R）**：两条路线的物化时延 ——
- 路线 A：顶层 `LazyForEach` 从 `Scroll` 迁到 `List`（List 天然支持 LazyForEach + `Scroller.scrollToIndex`），测第 N 块定位耗时与子树物化时延；
- 路线 B：保留 `Scroll` 粗滚（按累计高度估算）→ 再精调，测同一指标。
**判定**：取时延达标者；UI 方案已给 80ms 假设，需实测校准。
**注意**：路线 A 会改动内容区容器（`ContentArea.ets` 与 `BlockList.ets` 同批），**须与编辑器重铸的 Phase 3 overlay 改造错开**（见总纲文件锁 L3 精神）。

### ⑤ `pdf.worker` rawfile 化
**类型层**：无 SDK 类型面（属 ArkWeb 引擎对 `Worker`/`importScripts` + `resource://rawfile/...` 的支持范围）。
**待测（R）**：pdf.js 在 WebView 内以 rawfile 路径 `workerSrc` 创建 Worker 能否成功（Worker 脚本通常要求同源可脚本化 URL，`resource://` 协议可能被拒）。
**探针设计**：rawfile 放 `pdf/pdf.min.js` + `pdf/pdf.worker.min.js` + 一个 1 页测试 PDF → `pdfjsLib.GlobalWorkerOptions.workerSrc = 'pdf/pdf.worker.min.js'` → 渲染首页到 canvas → 截图判定。
**回退选项**（按优先级）：① `disableWorker: true` 主线程解析（功能可用、性能下降）；② 换轻量渲染方案；③ PDF 保留联网。
**影响**：U3.5 的验收口径必须包含「断网可开 PDF」，失败则需改写该条（当前口径与 U3.1 自相矛盾一事已在总纲 §2 记录）。

---

## 2. S0 出口判定（当前状态：**未闭合**）

| 门禁项 | 状态 |
|---|---|
| 5 项均产出结论（可用 / 回退路线） | ❌ 仅 ①④ 完成类型层与结构层判定；②③⑤ 待运行期探针 |
| ④ 直接决定 U2.1b/U2.4/U2.5 是否按原设计走 | ⏸ 待路线 A/B 实测 |
| 探针代码可复用为回归资产 | ⬜ 未创建 |

**下一步（一次构建跑完 4 项运行期探针）**：新增临时页 `SpikeHarness`（`pages/` 或隐藏路由，不入正式导航），一处集中验证 ①②③⑤，加上 ④ 的两条路线对比；构建 → 装包 → 用 `uitest` 驱动 → 采集：延迟统计（hilog）、截图（CSS 生效/PDF 渲染/菜单弹出）、dump（菜单项文本）。跑完即移除该页并记录结论。

**风险提示**：探针页是**临时产物**，须遵守总纲 A4（一步一提交）：建议单独提交「S0 探针页」一次，验证完再提交一次「移除探针页」，避免混入正式功能改动。

---

## 3. 未验证项登记（不猜测）

1. `ResponseType` 是否含 `LongPress` 成员 —— 类型定义中已见 `RightClick`，其余成员未逐一核对。
2. MessagePort 是否需在 `Web` 组件 `onControllerAttached` 之后才能创建端口 —— 官方示例时序未核实。
3. `$rawfile` 的返回值能否直接用于 `Web.src()`（还是必须 `$rawfile('x.html')` 之外的 `resource://rawfile/x.html` 字符串形式）—— 两种写法在项目既有 `WebEditor.ets` 中的用法未核对。
4. `LazyForEach` 在 `List` 内的虚拟化行为与 `Scroll` 内的差异 —— 需 Profiler 实测（UI 方案 §存疑项已登记）。
5. pdf.js 具体版本与 `workerSrc` 在 ArkWeb 下的兼容性 —— 未开始。

---

## 4. 运行期实测结果（2026-09-27，平板模拟器 MatePad Pro 13）

探针页 `pages/SpikeHarness.ets`（临时页）+ rawfile `spike/*`（index.html + style.css + app.js + probe.worker.js），一次构建跑完 ①②④⑤，证据经 `hilog -T SPIKE` 采集。

| # | Spike | **运行期结论** | 原始证据 |
|---|---|---|---|
| ② | `$rawfile` 相对路径 | ✅ **成立** | 引擎 loader 日志三连：`resources/rawfile/spike/index.html` → `style.css` → `app.js` 均按相对路径加载成功。**JS 端「零构建」多文件方案可行**（不必内联单文件） |
| ④ | 渲染层可寻址化 | ✅ **性能充裕** | `SCROLL_SYNC_MS=1`（`scrollToIndex` 同步返回 1ms）；`SCROLL_SETTLE_MS=45`（32ms 定时后确认，即约 13ms 内已就位）。**路线 A（Scroll→List）无性能顾虑**，方案中 80ms 的保守假设应下修 |
| ⑤ | 从 rawfile 创建 Worker | ❌ **失败（不可绕过的引擎限制）** | `Failed to construct 'Worker': Script at 'resource://rawfile/spike/probe.worker.js' cannot be accessed from origin 'null'` |
| ① | MessagePort 双向往返 | ◐ **半通过** | ✅ 端口建立成功（`PORT_SETUP_OK`）且 **JS 侧确实收到端口**（`port:"ok"`）；❌ 回程未确认——`rttSamples=0` 且 `jsonOk=false`，即 ArkTS→JS 方向未生效。**需修探针重测**（疑点：JS 侧是否需显式 `port.start()`、或读取窗口 3s 不足以跑完 200 次往返） |
| ③ | `bindContextMenu` 双绑 | ◐ **仅编译层** | 两次链式调用通过类型检查（证明 `ResponseType.LongPress` 成员存在）；**运行时是否互相覆盖未测** |

### 4.1 PDF Kit 路线探测（新增 spike，2026-09-27）

**背景**：⑤ 的失败使 pdf.js 离线化受阻，故评估 HarmonyOS 原生 PDF Kit（`@kit.PDFKit`，导出 `pdfService` / `pdfViewManager` / `PdfView` 组件）能否替代。

**SDK 侧（类型层，已核）**：kit 与 API 齐备；`PDFKit.json` 声明 phone/tablet since 5.0.0(12)、2in1 since 5.0.1(13)；syscap 为 `SystemCapability.OfficeService.PDFService.Core`；能力面含 `PdfController.loadDocument/loadDocumentFromMemory`、文本搜索、**原生标注 API**（`PdfAnnotation`/`TextAnnotationInfo`/`FreeTextAnnotationInfo`/`Square`/`Oval`/`Polygon`/`LinkAnnotationInfo` + `registerAnnotationSelectedListener`）、水印/背景/页眉页脚。

**设备侧（运行期，已测）**：

```
PDFKIT_SYSCAP=false
PDFKIT_CTRL_ERR=the requested module '@hms:officeservice.PdfView' does not provide an export name 'pdfViewManager'
```

**结论：PDF Kit 在本模拟器上不可用**——① syscap 判定为 false；② 即使强行 `new pdfViewManager.PdfController()`，运行时模块也不提供 SDK 类型中声明的该导出（**SDK 类型面 ⊃ 设备运行时 HMS 能力面**，模拟器镜像的 HMS 集被裁剪）。

**因此对计划的修订建议**：
1. **PDF Kit 不能作为主路线**，只能作为**分级增强**：入口处用 `canIUse('SystemCapability.OfficeService.PDFService.Core')` 判定——真机（有 HMS Core）走原生 `PdfView`（离线、可标注）；模拟器/无 HMS 设备回退 pdf.js。
2. **U3.5 的第四处（pdf.js）不能删**：原拟「用 PDF Kit 绕开 ⑤」的方案不成立；pdf.js 离线化仍需在三条回退中选一条（`disableWorker: true` 主线程解析 / worker 内联为 Blob URL / 保留联网）。**建议先补一次 Blob-URL worker 探针**（成本低，若能通过则离线 PDF 在有 HMS 与无 HMS 两类设备上都成立）。
3. **新增风险项**：SDK 类型面与设备运行时 HMS 能力面不一致（本例已实证）——凡引用 `@hms.*` 的能力，**必须用 `canIUse` 或 try-catch 运行期判定**，不得仅凭类型检查通过就认为可用。
4. **正向收益**：真机上「PDF 标注」从「缺 UI 入口」变为「有原生 API 可支撑」，可作为真机专属增强排入 S4；同时 `loadDocumentFromMemory(ArrayBuffer)` 可用于「把沙箱文件读入内存再渲染」，绕开路径权限问题。
