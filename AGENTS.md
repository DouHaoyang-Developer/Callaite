# AGENTS.md

本文件为在本仓库工作的 AI Agent 提供指导。**内容以实测为准**——凡与代码或设备行为冲突处，以实测结果为准，并请顺手修正本文件。

---

## 0. 第一条规则：`docs/` 是本地私密库，不上传

- **`Callaite-工作文档/`（含其下 `docs/`）位于本仓库之外**（仓库的兄弟目录），因此**天然不会进入 git**。
- 其中的内容（计划文档、验证报告、审查报告、判定表、待验收清单、截图证据）**属本地私密资产，禁止上传/分享/提交** ✗
- **不要把 `docs/` 迁入仓库**，也不要为它添加 git 引用。
- ⚠️ **另一处红线**：逆向工程产物目录（如 `obsidian-analysis/`）**严禁提交、上传、分享**；只能产出**行为规格**（clean-room），**不得搬运其代码、图标、文案、商标**。

---

## 1. 项目概览

**Callaite** —— HarmonyOS ArkTS 构建的 Obsidian 风格知识管理 / 大纲笔记应用。

| 项 | 实测值（2026-09-29） |
|---|---|
| 源文件 | **136 个 `.ets`** |
| 代码量 | **约 37,650 行** |
| bundleName | `com.example.callaite` |
| 版本 | `versionName 1.0.0` / `versionCode 1000000` |
| SDK | `targetSdkVersion` = `compatibleSdkVersion` = **26.0.0**（`runtimeOS: HarmonyOS`） |
| 权限 | `ohos.permission.DISTRIBUTED_DATASYNC` · `ohos.permission.VIBRATE` |
| 入口 | `windowStage.loadContent('pages/Index')`（`EntryAbility`） |

**数据落盘位置**（Vault 根）：`/data/app/el2/100/base/com.example.callaite/haps/entry/files/graph/*.md`
> ⚠️ 该路径**对本机 shell 只读**（可 `ls`/`cat`/`grep`，写入 `Permission denied`）——**这是一个很有用的验证能力**：磁盘内容可作硬证据（如「页面是否被写成 0 字节」）。

---

## 2. 构建

```powershell
cd F:\DevEcoStudioProjects\Callaite
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:JAVA_HOME='D:\Program Files\Huawei\DevEco Studio\jbr'
$env:PATH='D:\Program Files\Huawei\DevEco Studio\jbr\bin;'+$env:PATH
node 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon
```

- **判据是输出里的 `BUILD SUCCESSFUL`，不是 exit code** —— 签名 WARN 走 stderr 会让 pwsh 假报 `exit code: 1`。
- 产物：`entry\build\default\outputs\default\entry-default-unsigned.hap`（**未签名 HAP 可直接 `hdc install -r` 安装**）。
- 出现 `Error Code: 00308018 manifest.json or module.json is lost` ⇒ hvigor 缓存问题：删 `entry\build` + `.hvigor\cache` 后重建。
- **清洁构建**（排除陈旧缓存）：先删 `entry\build`、`.hvigor\cache` 再构建。
  > ⚠️ 基线可能是**陈旧的 UP-TO-DATE 缓存**：本会话发现 `SearchPanel.ets` 在**从未被编译**的情况下藏着 2 个编译错误 ✗ ⇒ **「零引用文件」不进构建，其错误不会被任何构建暴露**（详见 §7 陷阱 1）。

---

## 3. 设备与验证工作流

- **模拟器**：平板 `MatePad Pro 13`（HarmonyOS 7.0.0 / API 26 / 2880×1920 / density 2.0 ⇒ **1440×960 vp**）。
  - 由 IDE 管理，IDE 关闭会随之退出；可用 `emulator.exe -start "MatePad Pro 13"` 重新拉起（约 25 s 后 `hdc` 可见）。
  - **每步设备操作前先断言 `hdc list targets`**（该模拟器会反复掉线）。
- **安装**：`hdc install -r <hap>`（未签名可装）；`hdc shell aa force-stop com.example.callaite` + `aa start -a EntryAbility -b com.example.callaite` 做冷启动。
  > `aa force-stop` **不触发 `onBackground`** ⇒ 用它验证「持久化是否真的落盘」比正常退出更严格 ✓
- **UI 取证**：`hdc shell uitest dumpLayout -p /data/local/tmp/x.json` + `hdc file recv`；截图 `hdc shell snapshot_display -f /data/local/tmp/x.jpeg` + `hdc file recv`。
- **输入注入不可靠** ✗：`uitest uiInput text` 会整行丢失；`keyEvent`/`uinput -K` 注入的按键**不达 ArkUI 按键管线**（做阴性对照可证：注入前后截图**逐字节 MD5 相同**）。
  ⇒ **凡依赖按键/文本输入的验收，默认标注「代码就绪、待验收」，不要写成「通过」** ✓ 并尽量提供**可点击的等价入口**。

### 验证纪律（本会话用代价换来的）

1. **先看图**，再算指标 —— 多个缺陷（嵌套子块全丢、空白带）都是**目视截图**发现的，dump 数字没暴露。
2. **测量尺度必须与目标尺度匹配**；基线必须**可比**（本会话曾把「38 个 UI 节点」与「34 个已布局行」当成同一把尺子 ✗）。
3. `dumpLayout` **有已知盲区**：部分节点不输出 `text`、`--props` 不输出 `text=`、默认尺寸过滤会静默排除大容器、`RichEditor` 内容不进树。**读不到不等于不存在。**
4. 一个动作「看起来没生效」时，**先验证这个动作是否真的被送达**（阳性/阴性对照）。
5. **不得把「无法验证」写成「通过」** —— 写「代码就绪、待验收」，并把判据与步骤登记到 `docs/待验收清单.md`。
6. **子代理/他人的高危断言（尤其「会导致数据损坏/静默丢数据」）必须独立复现后才可引用** —— **行号的存在不等于结论成立**（本会话曾把一个假结论传播了 3–4 轮 ✗）。

---

## 4. 架构

```
entryability/        EntryAbility（启动链）
pages/                Index（唯一生产页面）
state/               AppState / TabState / StatePersistence / Breakpoints
core/
  models/            BlockData 等数据模型
  engine/            OutlinerEngine / OutlinerOps / BlockTree / …（大纲引擎）
  db/                DataStore / IndexStore / FileRepository（持久化与索引）
services/            WorkspaceService / EditorService / SaveQueue / DirtyPageTracker /
                     BlockAnchorService / ShortcutService / PluginManager / …
components/
  outliner/          BlockList / BlockView / BlockChildren / IntegralEditor /
                     WebEditor / BlockDragLayer …
  layout/            MainContainer / Ribbon / TabBar / MobileMenuSheet / …
  sidebar/           LeftSidebar / RightSidebar / PageTree / PageContextMenu …
  page/              ContentArea / PageView / HomePage / JournalFeed …
  search/            SearchPanel / CommandPalette
  extensions/        CodeBlock / MathRenderer / MermaidRenderer / PdfViewer
  whiteboard/        Whiteboard / WbShape / PenCanvasPage …
  property/          PropertyEditor / PropertyConfig / PropertyValueEditor
plugins/             插件框架（预编译 ArkTS 模块，无动态 require/eval）
utils/               工具类（LivePreviewHelper / MarkdownSegmenter / ContentRenderer …）
```

**关键单例**（`static getInstance()`）：`WorkspaceService` · `EditorService` · `SaveQueue` · `DirtyPageTracker` · `BlockAnchorService` · `ShortcutService` · `PluginManager` · `PropertyEngine` · `WhiteboardFileService` · `PenKitService` · `CollaborationService`

**数据流**：`Component` → `Service`/`Engine` → `DataStore` → `FileRepository`（`.md` 落盘）。
**落盘模型**：文本变更走**惰性落盘**（`DirtyPageTracker` 脏页 + 事件驱动 flush + 5 s 硬截止），**结构性操作前强制 flush**。

---

## 5. ArkTS 编译约束（本仓已验证）

| 禁止 | 替代方案 |
|---|---|
| `any` / `unknown` | 显式类型 |
| 对象字面量作类型 `{ a: string }` | 定义 `interface` |
| `Record<K,V>` | `Map` 或自定义 interface |
| `[key: string]` 索引签名 | 自定义类 + `get/set` 方法 |
| 解构 `const { a } = obj` | 索引访问 `obj.a` |
| `for (const [k,v] of map)` | `map.forEach((v,k)=>{})` |
| `...spread` | 显式逐个赋值 |
| 嵌套三元 > 2 层 | `if/else` 链 |
| `build()` 多根节点 | 单一容器根（`Stack`/`Column`） |
| **`@Builder` 调用处链式加属性** | `.margin()` 等**必须写进 Builder 内部**（`@Builder` 返回值是 `void`，链式调用会报 `Property 'x' does not exist on type 'void'`）|
| `enum` 当字符串用 | 注意有些 SDK 类型是**字符串字面量联合**而非 enum（如 `vibrator.Usage`，正确写法 `{ usage: 'unknown' }`）|

---

## 6. 文件 I/O（CoreFileKit）

```typescript
import { fileIo as fs } from '@kit.CoreFileKit';

const exists = fs.accessSync(path);
const raw = fs.readTextSync(path);                       // 读

const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
fs.writeSync(file.fd, content);                          // 写：必须走 fd
fs.closeSync(file);
```

`fs.writeSync(path, string)` / `fs.writeTextSync(path, string)` **不存在** —— 必须通过 `fd` 写入。

---

## 7. 已知陷阱（全部为实测，非推测）

1. **零引用文件从未进入构建 ⇒ 它内部可能藏着编译错误** ✗
   实例：`SearchPanel.ets` 接线前从未被编译，内藏 2 个错误（`.maxHeight` 不属于 `ColumnAttribute`、`.justifyContent` 不属于 `StackAttribute`）；一次清扫中 23 个零引用文件里 **5 个根本无法编译**。
   ⇒ **接线任何零引用文件前，第一步先把它拉进真实构建，验证它本身能否编译**，再谈功能。
2. **「死代码」的判据不能只看「零引用」** ✗
   实例：`PageContextMenu` / `BacklinkFilters` 零引用，但**路线图明确要接线它们**，删除造成往返。
   ⇒ **先扫零引用面，再拿路线图逐条排除「计划内待接线」的文件**。**一个文件是「死代码」还是「未接线的资产」，取决于路线图，不取决于 grep。**
3. **HSP / 原生库依赖会在「模块加载期」崩溃，早于任何 `canIUse` 守卫** ✗
   实例：`@kit.Penkit` 是 HSP 形式，无该 HSP 的设备**启动即 SIGABRT**（崩溃点在 `LoadJSPandaFile`）⇒ **「运行时探测 + if 包住」无效**，`await import()` 也会被降级为 `require` 而无效。
   ⇒ 这类能力**必须用构建期隔离**（product flavor / 独立模块 / 注入点）。
4. **`List` 的 item 内容里出现 `height('100%')` 会造成「视口高度反馈环」** ✗
   实例：`BlockView` 的缩进引导线与引用块竖条用 `height('100%')`，父 `Row` 高度由内容决定 ⇒ 百分比对**父级约束上限（List 视口）**解析 ⇒ 子撑高父、父再抬高子，行被拉成数百 vp。
   ⇒ 装饰性「撑满高度」的竖条用 `Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch })` 链，**不要用百分比高度**。
5. **`@Builder` 返回值是 `void`** —— 不能在调用处链式追加属性（见 §5）。
6. **`bindSheet` 的观感**：`SheetSize.FIT_CONTENT`/`detents` 都存在，但 `preferType: SheetType.POPUP` 只是**「偏好」**，系统可依窗口尺寸改判为 `BOTTOM`（贴底抽屉）⇒ **不要把「悬浮弹窗」观感押在它上面**。
7. **零引用的组件不等于「不可用」，也不等于「能用」**：`CodeBlock` 接线后才发现它从未运行过；`BlockDragHandler`（已删）里藏着方向盲、无 noop 守卫、无折叠守卫三个真缺陷。
   ⇒ **删是安全的（不跑就没风险）；「接线」必须先验证。**
8. **`LazyForEach` 只在 `List`/`Grid`/`WaterFall` 等滚动容器里才虚拟化**；放在普通 `Column` 中不虚拟化 ✗。
9. **`Scroller.scrollToIndex` 只对 `ArcList`/`Grid`/`List`/`WaterFlow` 生效** —— 对 `Scroll` 无效。

---

## 8. 工程纪律（必须遵守）

1. **改源码一律用 `edit`/`write` 工具或 Python 字节级读写** ✓
   **禁用 PowerShell 的 `Set-Content`/`Out-File`/`-replace` 写源码** ✗ —— 本仓已因此**损坏文件 5 次**（CRLF 污染 + 内容截断）。
   同理：**不要用 PowerShell here-string 做源码替换**（CRLF/LF 不匹配会静默落空）。
2. **提交时永远逐个列出文件**，**禁用 `git add -A` / `git add -u` 扫目录** ✗ —— 它会把该目录下**未跟踪的探针/临时产物一并提交**（本会话已发生一次）。
   **提交后核对 `git status` 的差异**（若某个本该未跟踪的文件消失了，说明被误提交）。
3. **临时产物禁止落在仓库内** ✗（放 `%TEMP%` 或用完立即删除）。探针页/插桩用完后必须删除。
4. **本项目长期存在的探针产物（禁止提交）**：
   - `entry/src/main/ets/pages/SpikeHarness.ets`
   - `entry/src/main/resources/rawfile/spike/`
   - `entry/src/main/resources/base/profile/main_pages.json` 中 `pages/SpikeHarness` 的注册行
   提交前请确认这些**不在索引里**。
5. **不要用 `git stash` / `git checkout -- <目录>` / `git reset --hard`**（工作区常有他人/其它窗口的未提交产物）。
6. **构建产物与依赖目录**已在 `.gitignore`（`**/build`、`/.hvigor`、`/oh_modules`、`/node_modules` 等）。

---

## 9. 本地私密资产（不上传）

| 路径 | 内容 |
|---|---|
| `../Callaite-工作文档/` | 计划（`EXEC-PLAN` / `EXEC-MASTER-PLAN` / `EXEC-SPRINT-*`）· 验证与审查报告 · `docs/D-GATE-1-判定表.md` 与证据截图 · `docs/待验收清单.md` |

**红线**：以上内容 + 逆向工程产物目录**一律不上传、不提交、不分享**；对外只能产出**行为规格**（clean-room），**不得搬运代码 / 图标 / 文案 / 商标**。
