# AGENTS.md

> **适用范围**：本文件面向工作区根目录下的 **`Callaite/`** 项目（HarmonyOS ArkTS 大纲笔记应用）。
> 工作区内还有其它项目（`LightNote/` · `Lunius/` · `logseq/` · `Penkit/` · `Obsidian Pictures/` 等），
> **本文件的规则与陷阱只针对 `Callaite/`**；其它项目请以各自的 README / AGENTS 为准。
> 项目内的描述文档是 **`Callaite/README.md`**（工作区根 `../AGENTS.md` 副本不入版本控制；**本副本随 `docs/` 入库**）。
> 📁 **陷阱 1–25 · 32 · 34 · 35 的完整正文已由用户于 2026-10-02 删除**（判断为不再需要 ✗）⇒ **本文件不再有归档文件** ✗
> ⚠️ **但其中几条仍被本文件交叉引用** ⇒ 已就地保留要点：
>   - **陷阱 33**（`preferences/` 是 shell 可写的 ✓ —— 除 `graph/` 外本仓唯一可写的应用数据目录 ✓；
>     删 `callaite_app_state` 可回 onboarding ✓ —— **但它不是夹具复位方案** ✗）—— **与下方陷阱 36 配合使用** ✓
>   （其余 1–25/32/34/35 的要点已随文件删除 ✗ —— 若将来发现某条反复被需，可从
>    `%TEMP%\AGENTS.md.w15.orig.bak`（68,552 B）取回 ✓ —— ⚠️ **但 `%TEMP%` 会被清理，不要当作长期保险** ✗）

---

本文件为在本仓库工作的 AI Agent 提供指导。**内容以实测为准**——凡与代码或设备行为冲突处，以实测结果为准，并请顺手修正本文件。

---

## 0.0 第一条红线（用户 2026-10-02 定，**优先级高于本文件其余全部内容**）

> **应用发布后必须有 HarmonyOS 原生的应用功能体验。**（用户原话）
> 派生要求：**上架时，白板这个功能一定要有 HarmonyOS 的原生体验**（同一用户的更具体表述）

**这条是「标准」，不是「偏好」** —— 它决定技术选型与路线图排序：
- **凡「用非原生方案实现、或降级为非原生体验」的设计，一律不合格** ✗
- **凡能力依赖 HarmonyOS 原生 Kit / HSP 的**，**要保证上架的产品里有它**（而不是「没有就降级」✗）
- ⚠️ **它与「在不支持的设备上不能崩」并不冲突** ✓ —— 但**实现手段不是代码** ✗✓：
  **API 26 Stage 模型上不存在「按 syscap 的安装门禁」** ✗（W18 实测：`reqCapabilities` 只存在于 **FA 模型** `config.json`；
  Stage 唯一的相近字段 `requiredDeviceFeatures` 是**按设备形态**（`phone`/`2in1`/`wearable`）**而非按 syscap** ✓）
  ⇒ **该效果只能靠 AppGallery 上架时的「支持设备集」** = **发布期交付物，本地无从验证** ✗✓
  ⇒ 而**代码侧的正解是「单 product + 静态 import + 无条件用原生」** ✓（**不做隔离、不做降级分支** ✓）
- ⚠️ **反过来说**：**凡为了「兼容没有该能力的设备」而做的降级/兜底分支，都要重新审视其必要性** ✗✓
  （**已由 W18 裁决：不做隔离** ✗✓ —— 正解 = **单 product + 静态 import + 无条件用原生** ✓）

⚠️ **对本仓的直接影响（待确认 ✗）**：仓里存在**基于 WebView 的功能**（`WebEditor` · `PdfViewer` 用 WebView `mouseup` ✓ ·
可能还有 `MermaidRenderer`/`MathRenderer`/`CodeBlock` ✓）⇒ **它们是否违反本红线，需要用户确认口径** ✗✓
（**「原生功能体验」= 全栈 ArkUI 原生？还是 = 关键能力（白板/笔）用原生？** ✓）
  > ✅ **已由 W19 已回答（R1/R2/R3** ✓ —— 推荐「**关键能力原生 + 内容渲染类允许 WebView**」✓ **待用户拍板** ✗）

---

## 0.1 第二条红线（用户 2026-10-02 定，**与 §0.0 同级**）

> **界面 UI 必须达到 Obsidian 的 UI 界面设计水平。**（用户原话：「还有UI方面的问题，界面UI还是无法达到Obsidian的UI界面设计水平」）

**同样是「标准」，不是「偏好」** ✓ —— 它是一条**验收维度**，与功能/性能红线并列：
- **凡「功能能用但观感/信息密度/一致性不达标」的界面，一律不合格** ✗
- ⚠️ **它与 §0.0（原生体验）是两条独立的尺子** ✗✓：**原生 ≠ 好看** ——
  **§0.0 管「用什么实现」，§0.1 管「呈现成什么样」** ✓ 两条都要满足 ✓
- ⚠️ **「达到 Obsidian 水平」必须拆成可验收的维度** ✗✓（**否则无法判分** ✓）：
  **视觉基调（配色/暗色）· 排版与字号层级 · 间距与节奏（spacing scale）· 图标语言 · 圆角/描边/阴影 ·
  信息密度与留白 · 侧栏/标签/面板的布局与层级 · 交互态（hover/focus/active/拖拽反馈）· 动效克制程度 · 各界面一致性**
- 🔴 **法律红线（与本文件 §0 一致，不得违反）** ✗✓：**只能产出「视觉/行为规格」（clean-room）** ✓ ——
  **严禁搬运 Obsidian 的图标、文案、截图、主题文件、代码、商标** ✗✗
  ⇒ **可以学「为什么这样排」，不可以拷「它的资源长什么样」** ✓✓

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
  - 由 IDE 管理，IDE 关闭会随之退出；重新拉起：**`emulator.exe -hvd 'MatePad Pro 13'`** ✓
  - ⚠️ **实例名含空格时，必须是一个带引号的实参** ✗✓（W10 实测：`emulator.exe -hvd '"MateBook Pro"'` ✓ —— shell 会把不加引号的名字拆成两个参数 ✓ 与 `-start` 报 `Invalid command` 同源 ✓）（W7 实测：**`-start '名字带空格'` 过不了参** ✗ 报 `Invalid command: please attach - or --`；`-hvd` 是 `-start` 的别名 ✓）；约 25–30 s 后 `hdc` 可见 ✓
  - ⚠️ **`hdc` 报 `Offline` / 无进程 ⇒ 先确认模拟器到底在不在跑** ✗（W7：以为设备坏了，其实**根本没在跑** ✓）
  - **每步设备操作前先断言 `hdc list targets`**（该模拟器会反复掉线）。
- **安装**：`hdc install -r <hap>`（未签名可装）；`hdc shell aa force-stop com.example.callaite` + `aa start -a EntryAbility -b com.example.callaite` 做冷启动。
  > `aa force-stop` **不触发 `onBackground`** ⇒ 用它验证「持久化是否真的落盘」比正常退出更严格 ✓
- **UI 取证**：`hdc shell uitest dumpLayout -p /data/local/tmp/x.json` + `hdc file recv`；截图 `hdc shell snapshot_display -f /data/local/tmp/x.jpeg` + `hdc file recv`。
- **输入通道现状（2026-09-30 W11 重大更正 ✗→✓）**：
  | 通道 | 结论 |
  |---|---|
  | `uitest uiInput text` | ✗ 会整行丢失 |
  | **`uitest uiInput keyEvent <code>`** | ✅ **可达 ArkUI 按键管线**；**是否过输入法取决于设备**（平板✗ / 2in1✓ —— 见陷阱 21 定论）（W11 用**阳性+阴性对照**证实：↓↑↵esc/Ctrl+K 全部驱动路由器；无浮层时同注入截图**逐字节 MD5 相同**）—— **此前「按键不达」的结论是错的** ✗ 很可能是早前几次在**没有任何组件挂键处理**时注入 ⇒ 无可观测现象 ⇒ 误判 ✗ |
  | `emulator.exe -instance … -fill "<id> <text>"` | ✅ 文本真送达（UI+落盘）／ ✗ **仅 ASCII**、**语义 = 追加、不能替换** ✗✓（W10 实测：想「删掉模板行」只能靠退格，`-fill` 做不到 ✓） · ✗ **静默截断到 ~2000 字符**（W1b 实测：送 8000 报 `Widget may not be input field` ✓ 实测只落 2000）⇒ **构造超长夹具不能靠它** ✗ |
  | `uitest uiInput keyEvent 2055`（退格） | ✅ 可达 ／ ⚠️ **偶发丢键**（W1b 实测 **15 次落 13–14** ✓）⇒ **不要用「按 N 次退格」当清空判据** ✗ |
  | `emulator.exe -instance … -click <id>` / `-slide` | ✅ 点击等价坐标点击 ／ `-slide` **只能滚动、不能做「按住拖动」** ✗ |
  | **`emulator.exe -instance … -click <widgetId>`** | ✅ **在 2in1 上比「原始坐标」可靠** ✗✓（W12 实测：同一「添加」行**两个坐标点都无反应** ✗，而按 **widgetId** 一次成功 ✓）⇒ **改用 widgetId 通道** ✓ |
  | `emulator.exe -instance … -uiLayout -i` | ✅ 产出 `<imageRoot>/<实例名>/uiLayout/analysis.md`，**带数字 id** ✓ ⇒ 可直接喂 `-fill`/`-click` ✓ **⚠️ 但 id 每轮枚举都会重新生成** ✗（W5 实测：用**上一轮**枚举的 `id:218` 在下一轮点击 ⇒ **点掉了应用窗口** ✓ 而 **W2「点『新建』落到设置」疑为同源** ✗✓）⇒ **必须「当轮枚举、当轮点击」** ✓ |（⚠️ 其**坐标系未证实**：同会话观测到**两套**（相对窗口内容 vs 绝对屏幕 ✓）⇒ **只信 widgetId，bounds 仅作判据量** ✗）|
  | **`uitest uiInput dircFling <dir> <velocity>`** | ✅ **可靠的滚动通道** ✗✓（W16 实测：`emulator -slide`（widgetId 与坐标两种形式）**逐像素 0 变化** ✗ 而 `dircFling` 有效 ✓ 滚动条出现、行推进、实例化行数保持在视口量 ✓） ⚠️ **但推进量仅 7–40 px/次（查看陷阱 49）** ✗|
  ⇒ 按键类验收**先用 `uitest uiInput keyEvent` 试**，并**务必配阴性对照**（无浮层时注入应无变化）✓
  ⇒ **仍不可注入的**：真实**手势拖拽**（S1-H）✗
  ⇒ ⚠️ **「注入键是否过输入法」= 设备差异**（09-30 定论，见陷阱 21）：**平板 ✗ 不过 IME**（点屏上键组词 ✓ 但注入不组词 ✗）· **2in1 ✓ 过 IME** ✓
     ⇒ 做此类验收**必须在当台设备先跑阳性对照**（点屏上键是否出 `candidateWord`/`candidateView`）✓ **不要再归因于「IME 未授权」** ✗（已被证伪 ✓）

### 验证纪律（本会话用代价换来的）

1. **先看图**，再算指标 —— 多个缺陷（嵌套子块全丢、空白带）都是**目视截图**发现的，dump 数字没暴露。
2. **测量尺度必须与目标尺度匹配**；基线必须**可比**（本会话曾把「38 个 UI 节点」与「34 个已布局行」当成同一把尺子 ✗）。
3. `dumpLayout` **有已知盲区**：部分节点不输出 `text`、`--props` 不输出 `text=`、默认尺寸过滤会静默排除大容器、`RichEditor` 内容不进树。**读不到不等于不存在。**
4. 一个动作「看起来没生效」时，**先验证这个动作是否真的被送达**（阳性/阴性对照）。
5. **不得把「无法验证」写成「通过」** —— 写「代码就绪、待验收」，并把判据与步骤登记到 `docs/待验收清单.md`。
6b. **「点了没反应」先怀疑坐标，不要先怀疑设备坏** ✗✓（W7 实测，代价是 W6 误判「设备损坏到进不去应用」）
    实例：onboarding 的 `上一步 [920,1768][1428,1856]` 与 `下一步 [1452,1768][1960,1856]`，
    **W6 点的 `x=1440` 正好落在两者之间 12 px 的空隙里** ✗ ⇒ 表现为「点击不推进」✓
    （W6 记录的是**整行** bounds `[920,1768][1960,1856]`，不是单个按钮的 ✓）
    ⇒ **判据**：① 用 `dumpLayout` 取**目标控件自身**的 bounds（**不要用父容器/整行** ✗）② 点**其中心** ✓
      ③ 「点了没反应」时**先换坐标重试一次**，再考虑设备/注入通道问题 ✓
8. **「浮层是否打开」不能用 `dumpLayout` 文本检索判分 —— 会假阴性** ✗✓（W12 实测）
    实例：对 `Ctrl+K`（CommandPalette）与 `Ctrl+F`（SearchPanel）**双双读出「无新增文本」** ✗，
    而**整屏像素差分证明它们真的打开了** ✓ ⇒ **文本检索不可作为浮层开合的判据** ✓✓
    ⇒ **判据**：**整屏像素差分**（开/关各取一张，比差异像素数 ✓；Esc 后应**逐像素回基线 = 0 px** ✓）
      或**按 `id` 定位节点是否存在** ✓（`dumpLayout` 里按 `id` 查比按文本查可靠 ✓）
    > 本仓已有浮层约定：开合态收敛到 `AppState` 单一写入口 ✓（`SlashMenu` / `FindInPage` 同约定 ✓）
9. **子代理/他人的高危断言（尤其「会导致数据损坏/静默丢数据」）必须独立复现后才可引用** —— **行号的存在不等于结论成立**（本会话曾把一个假结论传播了 3–4 轮 ✗）。

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

> 📁 **陷阱 1–25**（Sprint-01/02 期）与 **32 · 34 · 35**（W5/W6 现象登记）**已由用户于 2026-10-02 删除** ✗ —— **本文件不再有归档**；仍被引用的要点见文件顶部的说明 ✓

26. **ANR 之后应用的 a11y 子树会整体消失，且只有「设备级重启」能恢复** ✗（W11 实测）
    表现：`dumpLayout` **只剩桌面** ✓；`-b`/`-w` 返回**空树** ✓；`force-stop` + `start` **无效** ✗；
    **必须停掉并重启模拟器**才恢复 ✓ ⇒ **正确写法：`emulator.exe -stop '<实例名>'`** ✓（W5 补：**`-instance … -stop` 过不了参** ✗ —— 与 `-start` 同族的参数形态 ✓）再 `emulator.exe -hvd '<实例名>'` ✓
    ⇒ 遇到时**先截图确认应用在不在渲染** ✗（避免又把「工具读不到」当成「应用坏了」✓ —— 与验证纪律 6b 同族 ✓）
    ⚠️ 相关：**本仓仍可在正常操作下触发系统 `THREAD_BLOCK_3S`**（W11 在 1018 块页做「点面包屑→点侧栏」时触发一次 ✗ **未归因** ✓）
    ⇒ 性能红线相关窗口请留意 ✓

27. **HAP 产物 MD5 不可复现 ⇒ 不得当作「源码一致性」判据** ✗（W1 实测，2026-10-02）
    **同一份源码、两次清洁构建 ⇒ 产物 MD5 不同**（块大小相同 ✓）⇒ 例如 `A39A8F75…` 与 `71ED9F72…` 都是同一 HEAD 的产物 ✓
    ⇒ **判据**：要判「设备上跑的是不是这份源码」✗ ⇒ **看包内 abc 标识 / 关键字符串**（如 `git grep` 得到的独特符号 ✓）
      或**核对 HAP mtime 早于 `updateTime`** ✓ —— **不要用 HAP MD5** ✗
    > ⚠️ 本文件早期的记录里曾多次把「产物 MD5 与设备已装包一致」当作证据 ✓ —— **那条推理不成立** ✗

28. **🔴 静默丢块：某页「第一次编辑触发 flush」后，尾部若干块从磁盘永久消失** ✗（W1b 实测，2026-10-02）
    **现象** ✗：页 `未命名` 首次编辑触发 flush 后，磁盘 **32 行 / 114 B → 20 行 / 92 B** ⇒ **12 个尾部块永久消失** ✓
    **关联** ✗：这与既有登记 **W13-3**（状态栏计数「20 块」vs 磁盘「32 行」）**同源** ✓ ——
    那不是显示问题，而是 **内存模型与磁盘真的不同，落盘把磁盘改写成内存模型** ✗✓
    **归属**：**解析/落盘层** ✓（W1 只动索引层 + `savePage` **写盘之后**的对账 ⇒ 不在其改动面内 ✓）
    **状态**：已登记 **W1-8** ✓ **未修** ✗ —— **凡涉及「块数与磁盘行数不一致」的现象，先怀疑这条** ✗

29. **元数据边界判据必须与「是否块」的判据一致，否则**空块行**会被吞进元数据区** ✗（W2 实测，2026-10-02）
    **根因** ✗（`MarkdownParser.ets:55-65` 修复前）：边界判定用 `trimmed.startsWith('- ')` 问「是不是块」✓，
    而 **`'- '.trim() === '-'`**（尾部空格被吃掉 ✗）⇒ **空块行不满足** ⇒ 被当成**页面元数据** ✓；
    但**真正的判据** `countIndent().isBlock` 对空块行答 **true** ✓ ⇒ **两套判据不一致** ✗
    叠加 `metadataEndIndex = i + 1` **写在每一行上** ✗ ⇒ 文件里没有「非空 `- ` 行」时边界推到 `lines.length`
    ⇒ **整个文件并入元数据区 ⇒ 0 块 ⇒ 下一次落盘写 0 字节** ✗✓
    **离线逐行复刻（修复前 → 修复后）**：32 行全 `- `（95 B）⇒ **0 B** ✗ → 95 B ✓；19 空块 + 尾块 `- X` ⇒ **3 B**（丢 19 块 ✗）→ 60 B ✓
    **修法**：边界改为「文件开头**连续**的 `PROPERTY_REGEX` 行」（空行中性 ✓ 第一条非属性行即内容起点 ✓）✓ **只改 1 处** ✓
    ⇒ **教训**：**同一个概念（「这是不是一个块」）在仓里有两套判据时，二者迟早会分叉** ✗
      ⇒ 新增/修改任何「行 → 块」的判定，**必须与既有判据对齐**（本仓以 `countIndent().isBlock` 为准 ✓）
    > ⚠️ **同时更正一条早前的归因** ✗：W1b 曾判断「落盘把磁盘改写成内存模型」✓ —— **已被证伪** ✓
    > （真机字节级往返证明**导出/落盘层完全无损** ✓；且 **W13-3 在当前镜像上已不成立** ✓ 状态栏与磁盘一致 ✓）

30. **`Stack` 子节点的 `.align()` 在根 `Stack` 里可能不生效 —— 用宿主 `alignContent` 或嵌套 `Stack`** ⚠️（W3 实测，**仅本机 2in1 / API 26** ✗）
    **现象**：把浮层作为子节点放进根 `Stack` 并给**子节点**加 `.align(Alignment.TopEnd)` ⇒ **不生效**（两次构建两次装机，卡片都落在**正中** ✗）
    **可用做法** ✓：由**宿主** `Stack({ alignContent: Alignment.TopEnd })` 决定位置 ✓，或**再嵌一层 `Stack`** ✓
    ⇒ 本项目已有浮层定位约定：**宿主 Stack 的 `alignContent`** ✓（W3 采用 ✓）
    ⚠️ **证据范围**：**只在本机 2in1 / API 26 实测** ✗ ⇒ 换形态/换 API 时**重新确认**，不要无条件外推 ✓

31. **清理「零引用」字段时，`@Watch` / `$` 双向绑定 / 静态常量是三类必查的假阳性** ✗（W4 实测，2026-10-02）
    **W4 的扫描脚本首版有 3 个假阳性源，不修就会直接误删** ✗✓：
    ① **`@StorageLink('k') @Watch('h')`** —— 值**从不被读**，但 **`@Watch` 就是消费方** ✓（本仓 **18 个**这类字段 ✓）
    ② **`StructName.CONST` 形态** —— **静态常量**被 `类名.常量` 引用 ✓ ⇒ 只 grep `this.` 会漏 ✓
    ③ **`$` 双向绑定** —— `$字段` 传给子组件 `@Link` ✓ ⇒ 只 grep `this.` 会漏 ✓（本仓 `Whiteboard.currentBrushColor/currentBrushSize` ✓）
    ⇒ **判据（5 条须同时满足才可删）** ✓：C1 零读 ✓ · C2 无 `$` / 无 `@Watch` / 零写 ✓ ·
      **C3 枚举全部构造点并逐点核对实参（`git grep "<Struct>("`，覆盖全仓）** ✓ ·
      C4 路线图/注释未记为**待接线或契约面** ✓ · C5 **纯删除**（不改任何 build 分支/回调）✓
    ⚠️ **C3 是本仓最容易错的一条** ✗：**`@Prop`/`@Link`/`@ObjectLink` 是「由外部驱动」的字段** ✓
    ⇒ **判据是「所有构造点是否都不传它」** ✓，**不是「本组件是否读它」** ✗✓
    > **W4 实测的收益** ✓：按此判据只删 **5 个字段 / 6 处** ✓，而**保留 32 个「看着零引用」的字段** ✓ ——
    > 其中 **4 类是真隐患**（`MobileBottomBar` 三个触发器**键被 `AppState` 主动写却没挂 `@Watch`** ✗ ·
    > `MarkdownToolbar.canUndo/canRedo` **只在 `aboutToAppear` 算一次**（= 陷阱 18 同型 ✗）·
    > `RightSidebar.blocksVersion` **注释声称驱动刷新但代码未接** ✗ · `TabBar.currentPage` **空挂** ✗）
    > ⇒ **保留项的判定比清理清单更有价值** ✓（误保留只浪费几行 ✓ **误删会静默破坏功能且构建多半仍绿** ✗）

33. **`preferences/` 是 shell 可写的，与 `graph/` 不同** ✓（W5 实测，2026-10-02）
    **事实** ✓：`.../haps/entry/files/graph/` 写入仍被拒（SELinux Enforcing ✓，与 W7/W8 一致 ✓），
    但 **`preferences/` 下 `cp` / `rm` 均成功** ✓ —— **这是本会话第一个「shell 可写的应用数据目录」** ✗✓
    **用途** ✗✓：删 **`callaite_app_state`** 可让应用**回到 onboarding 态**
      （W5 用它把 822 MB 的膨胀态**清零回 81.5 MB** ✓）⇒ **造「干净冷启动」基线的一条可用路径** ✓
    ⚠️ **但它不是夹具复位方案** ✗：**不改 `graph/` 的不可写性** ✓ ⇒ 造页面夹具**仍需应用内构造** ✓

36. **`preferences/callaite_app_state` 的 `page` 字段可直接改 ⇒ 切换「默认落点」的通用对照手段** ✓（W6 实测，2026-10-02）
    **用途** ✗✓：把活动标签的 `page` **字节级替换**成目标页 ⇒ **冷启动即落在该页** ✓
      ⇒ 造「**同一份包、同一 vault、只换落点**」的 A/B 对照 ✓✓（W6 正是靠它把日志流/文档页两个落点分离 ✓）
    **配合**：陷阱 33（`preferences/` 是 shell 可写的 ✓）
    ⚠️ **用完必须还原** ✗（W6 已还原 ✓）；⚠️ **删整个 `callaite_app_state` = 回 onboarding**（代价大 ✓）

37. **🔴 `[[` 死循环 ⇒ JS 堆 383 MB ⇒ **OOM 崩应用**（14 秒确定性复现）** ✗（W7 实测，2026-10-02）
    **最小复现** ✗✓：点进一个「**文本以 `[[` 开头、且 `]]` 之后还有字符**」的块（如 `[[W]]Y]]Z` 或 `[[链接]] ` —— **尾随一个空格也算** ✓）⇒ **14 s 后进程消失** ✓；`]]` 结尾的块点击正常 ✓
    **崩溃栈**（两次逐字相同 ✓）：`OutOfMemoryError / Heap::AllocateHugeObject 79,232,544 B / local heap oom, used size 383,707,920`
      ← `parseInlineMarkdown (MarkdownSegmenter.ets:231)` ← `parseMarkdownSegments (:110)` ← `buildSpansInternal (LivePreviewHelper.ets:278)` ← `buildSpans (:185)` ← `rebuildSpans (BlockEditor.ets:221)` ← `onReady (:269)` / `onSelectionChange (:432)` ✓
    **根因** ✗✓（逐行可验）：`MarkdownSegmenter.ets:223` 的 `if (text.startsWith('[['))` **没有 position 实参 = 只看串首** ✓，
      而 `i` 是**游标** ✓ ⇒ 当 `i` 已越过首个 `]]` 后该分支**仍成立** ⇒ `i = closeIdx + 2` **不前进** ⇒ **while 永不退出、每轮 push 3 段 ⇒ 无界增长** ✓
    **归属** ✓：`git blame` ⇒ 该分支出自 **`eb00adc`（2026-09-25「Callaite 4.2.1 Beta」）** ⇒ **不是 Sprint-03 引入** ✓；
      **同函数 `d4d1b5f` 已修过一个同族「孤立 `!` 死循环」** ✗ ⇒ **同族第 2 例** ✓✓
    ✅ **W8 已修**（2026-10-02）✓ —— 见下三条。**设备级复验**：`RichEditor [[W]]Y]]Z` 与 `[[A]]ZZ`
      在编辑器内**稳定存活 ≥30 s / ≥25 s**、`/data/log/faultlog/faultlogger/` **0 新增 jscrash** ✓✓

    **⚠️⚠️ W8 的一条重要更正：早前建议的修法会造成语义漂移，不要照抄** ✗✓
      建议修法是 `text.startsWith('[[', i)` + `indexOf(']]', i+2)`（即「三处实参都跟游标走」）。
      但 `startsWith`（无实参）是**全局属性**、与游标无关 ⇒ 原判定**恒等价于 `i === 0 && startsWith('[[')`** ✓。
      把它换成带 position 的版本 = **把「串中间的 wikilink」也纳入语法识别**，那是**语义扩展、不是修 bug** ✗：
      受控差分实测（`w8/diff_test.js`，4112 条语料）它让 **64 条**原本正常终止的输入**分段结果改变** ✗
      （`未命名页的 [[2026-09-25]] 引用` 由「1 段 content」变「5 段」；`b[[a]]` / `![[a]]` 同理）。
      ⇒ **W8 采用的零漂移修法**（`MarkdownSegmenter.parseInlineMarkdown`）：
      ```ts
      const wikiClose: number = text.startsWith('[[') ? text.indexOf(']]', 2) : -1;
      const isWikiTail: boolean = wikiClose !== -1 && wikiClose + 2 <= i;   // ← 只拦「会把游标写回去」
      if (!isWikiTail && text.startsWith('[[')) { const closeIdx = wikiClose; ... }
      ```
      ⇒ 「分支会把 `i` 写回去」的**充要条件**就是 `closeIdx + 2 <= i` ⇒ 守卫**恰好**只拦这一种情形 ✓
      ⇒ 对**所有修复前能正常终止的输入**守卫**恒假** ⇒ 分段结果**逐字节不变** ✓（**60,112 条差分：drift = 0** ✓）
      ⚠️ **踩过的坑**：只写 `i === 0` 守卫会让**未闭合 `[[`** 的输入也跳过该分支 ⇒ 实测 **30 条漂移** ✗
        ⇒ 必须用 `isWikiTail`（`closeIdx === -1` 时**不能**拦）✓
      > 若真要让编辑态识别串中间 wikilink，那是**产品/语义决策**（需与 `ContentRenderer` 对齐 + 独立验收），另开窗口 ✓

    **无条件前进兜底**（W8 新增；防的是「类」不是这一个 bug）✓：
      `parseInlineMarkdown` 的 `while` 体**末尾**比较水位 `guardMark`，`i <= guardMark` 就 `i = guardMark + 1`
      并打一条 `hilog.warn('… cursor stalled: forced advance …')`（**可 grep，兼作活体探针** ✓）。
      位置选在循环末尾是对的：带 `continue` 的分支跳过它，而那些分支的 `continue` 之前**都**写了 `i =`/`i +=` ✓。
      > **仓内先例**：渲染态解析器 `ContentRenderer.parse`（`:117-129`）**早就有同类兜底**（自述「P0 死循环兜底，既有缺陷」，
      > 归因 `e5fc508`，做法是「逐字消费一个字符」）⇒ 本仓的约定是 **游标式 while 必须有无条件前进兜底** ✓✓

    **同族第 3 例的排查结论**（逐分支形式化，W8）✓✓：把 11 个分支逐个写成「出口游标 `i' ≥ i+1`？」，
      **只有 wikilink 分支不满足** ✗；其余 10 个（含 `#11` 的既有兜底）**全部安全** ✓。
      ⚠️ 但函数里已经有过 **2 例**同族缺陷（`d4d1b5f` 的孤立 `!`、本条）⇒
      **不变量必须落成代码**（上面的兜底），不能靠「每次都逐分支证明」✗✓
      > 另：外层 `parseMarkdownSegments` 用的是 `for (i = 0; i < lines.length; i++)` ⇒ **结构上不可能不推进** ✓；
      > 且全仓**只有这一处**无 position 的 `startsWith('[[…')` ✓（`ContentRenderer.tryMatchAt` 用的是 `indexOf(']]', pos + 2)`，
      > **本来就跟游标** ✓ ⇒ 无需同批修改 ✓）

    **修法的归属与验收** ✓：归属仍是 `eb00adc`（**不是 Sprint-03 引入**）✓；
      **独立复现**（离线逐行移植，非手抄）证实卡死游标恰为 `closeIdx + 2` ✓；
      **活体夹具已清除** ✓✓（`2026-09-25.md` 全文复核：**不含**任何「以 `[[` 开头且 `]]` 之后还有字符」的串）——
      W7 交还时「点进去必崩」的状态**不再存在** ✓。
    ⚠️ **清场教训** ✗：清掉夹具靠的是**应用内的退格/删除**，而 W8 实测**设备按键注入会在会话中途整体失效**
      （`keyEvent 2055/2075/2082/2070` 全 0 效果，而同一时刻 `emulator -fill` **仍有效** ⇒ 是**通道**问题，
      不是应用/设备问题 ✓）；叠加 `选择`/`命令` 两按钮**布局重叠** ⇒ 多选删除也不可达 ✗
      ⇒ **清场前先把「删除通道」验活**（与 §7c 的「写入阳性对照」同一条纪律 ✓），否则会在 vault 里留下残块 ✗✓

38. **「行号存在」≠「判据的数据契约成立」—— 写守卫/判据前必须先核数据形状** ✗（W10 实测，2026-10-02）
    **实例** ✗✓：给「今日日志页占位块」加按天幂等守卫时，第一版判据用**含 marker 的模板串**（`'📌 今日要点: '`）去匹配块内容
    ⇒ **命中 0/28 ⇒ 守卫一次都没生效，7 次连续 +26 B** ✓（`572→598→624→650→676→702→728` ✗）—— **那 7 个块是调试产物** ✓
    **两个被忽略的数据契约事实** ✗：
    ① 入参带**尾随空格**，而模型 `content` **已被 `MarkdownParser.ets:170` 的 `trim()` 剥掉** ✓
    ② **marker 不在 `content` 里**（在 `block.marker` ✓）
    ⇒ **教训** ✓：**「我知道这个函数在这一行」不等于「我知道它收到的数据长什么样」** ✗
      ⇒ **凡新增「匹配既有内容」的守卫/判据，第一步先把真实数据形状打出来** ✓（或从消费侧反推 ✓）
      ⇒ 尤其当**判据串来自调用方的字面量**而**被匹配的数据经过解析/规范化**时 ✗✓ —— **两侧的空白与结构往往已经不同** ✓

39. **同一份文件有「shell 视角」与「应用视角」两个路径 —— 导入类验收必须用应用视角** ✗✓（W11 实测，2026-10-02）
    **事实** ✗✓：vault 的同一份 `.md` 有**两个不同路径名**：
    | 视角 | 路径 |
    |---|---|
    | **shell / hdc** | `/data/app/el2/100/base/com.example.callaite/haps/entry/files/graph/…` ✓ |
    | **应用内（`readTextSync`）** | `/data/storage/el2/base/haps/entry/files/graph/…` ✓ |
    ⇒ **把 shell 视角的路径喂给「导入」⇒ 应用读不到 ⇒ 对话框报「导入失败」** ✗（W11 实测 1 反例 + 1 正例 ✓）
    ⇒ **凡「让应用自己去读某个文件」的验收（导入/挂载/引用），一律用应用视角路径** ✗✓
    ⚠️ 机制**未归因**（沙箱命名空间映射 ✓ 只登记现象 ✓）

40. **基类 `UIAbility.onNewWant` 是空实现 ⇒ 不实现它 = 拉起被「静默吞掉」** ✗（W12 实测，2026-10-02）
    **机制** ✗✓：`launchType` 取默认 **`SINGLETON = 0`**（SDK `bundleManager.d.ts:689`）⇒ **首次启动走 `onCreate`，此后每次拉起都走 `onNewWant`** ✓
    ⇒ **若不实现 `onNewWant`，第二次及以后的拉起「送到了但没人接」** ✗ —— **基类是空实现 ⇒ 不报错、不打日志、完全静默** ✓✓
    **取证方式（无需插桩 ✓✓）**：**系统/框架自己会打印每次入口** ✓ ——
      `isNewWant:1` → **`[JUA2177] call js, name: onNewWant`** → `WindowSessionImpl OnNewWant` → `Ace UIContent OnNewWant` ✓
      ⇒ **在 hilog 里数「框架调了几次 vs 应用处理了几次」即可定位** ✓✓
    **判决表（修前）** ✓：`onCreate` **1/0/0** · `onNewWant` **0/1/1** · **真正处理 1/0/0** · 磁盘 **+8/+0/+0** ✓
    ⚠️ **复现「首次拉」路径时配方必须显式含 `force-stop`** ✗✓ —— **否则 Mission 已在 FOREGROUND ⇒ 全部走 `onNewWant`** ✓（`aa dump -l` 可查 Mission 状态 ✓）
    **修法选择** ✓：补 `onNewWant`（**不动 `launchType`** ✗ —— 改 `multiton` 会**每次拉起新建一个窗口/任务** ✗ = 新增缺陷 ✓）
    ⚠️ **并注意时序** ✗：**`onNewWant` 可能早于 `loadContent` 回调** ⇒ 需一个「窗口是否就绪」的标志来分流 ✓

41. **§7b 的「注入 — 回退」循环之后，必须再做一次清洁构建** ✗✓（W12 实测，2026-10-02）
    **原因** ✗：**失败的构建不动产物，但 `build/` 会留下「探针版」中间物** ✓ ⇒ 若直接增量构建并装机 ⇒ **装进去的可能是探针版** ✗✓
    ⇒ **流程** ✓：注入 ⇒ 构建失败（取证）⇒ 回退 ⇒ **清洁构建**（删 `entry\build` + `.hvigor\cache`）⇒ 装机 ✓
42. **@7b / any injected-probe check: ASSERT THE INJECTION TOOK EFFECT before judging the build result** (W13, 2026-10-02)
    **The pit** : the first injection did NOT take effect at all (a PowerShell here-string ate the quotes),
    yet the build was still SUCCESSFUL => **reading only the build result would misread "the probe never got injected"
    as "the file is not in the compile graph"** - i.e. the opposite conclusion.
    => **Always**: write the injection from a script FILE (not a shell here-string), and **assert the injected string is
       present in the source before building**; after reverting, assert the string is absent.
    > Same family as trap 9 ("a line number existing does not mean the conclusion holds"): **the instrument itself must be verified**.

43. **A value that looks like "defaults" may come from a @StorageLink LOCAL default, not from any initialize() function** (W13, 2026-10-02)
    **Instance** : `@StorageLink('callaite_onboarded')` in `pages/Index.ets:7` **creates the key in place with a local default**
    when it does not exist. Repo-wide, only 3 places touch that key (`Index.ets:7` local default /
    `StatePersistence.ets:21` whitelist / `OnboardingPage.ets:282` set-true on completion) =>
    **`AppState.initialize()` never touches it at all**.
    => The criterion is therefore "**establish the key before the page is CONSTRUCTED**",
       NOT "call the initializer" => and the fix belongs in `onCreate`, **before `loadContent`**.
    > Same family as trap 38: **before writing a guard, find out where the value ACTUALLY comes from.**


44. **7b variant: an injection INSIDE a UI-builder body may NEVER TAKE EFFECT** (W16, 2026-10-02)
    **The pit** : injecting `hilog.info(...)` **inside a `ForEach` body** fails ArkTS's UI-component-syntax rule
    => **the injection silently never applies**, yet the build behaves exactly as if the file were not in the compile graph
    => **you would conclude the opposite of the truth**.
    => **Rule**: put §7b probes in an ORDINARY METHOD BODY, never inside `build()` / `@Builder` / `ForEach` item bodies.
    > Same family as trap 42: **assert the injection actually landed in the source before you read the build result.**
45. **`canIUse` 在 `runtimeOS: "HarmonyOS"` 上不做运行时探测 —— 会为设备根本没有的能力返回 `true`** ✗（W18 实测，2026-10-02）
    **实测**：在一台**根本没有该 HSP** 的模拟器上，`canIUse('SystemCapability.Stylus.Handwrite')` 返回 **`true`** ✗
    **根因** ✓：`runtimeOS: "HarmonyOS"` ⇒ hvigor 的 `abstract-syscap-transform.js` 的 `doTaskAction()` **第一行就 return**
      （`if (this.targetData.isHarmonyOS()) return;`）⇒ **SysCap 变换被整段跳过** ⇒ `canIUse` 的答案来自**编译期注入的集合**，**不是运行时探测** ✗✓
    ⇒ **在 HarmonyOS 目标上，永远不要用 `canIUse` 当运行时能力探测** ✗ —— **它无法告诉你设备上有没有那个 HSP** ✓
      （OpenHarmony 目标上该变换会执行 ⇒ 行为不同 ✓）
    > **由此暴露的本仓真缺陷** ✗：`Whiteboard.ets:78-84` 的注释自称「官方 SysCap 运行时探测」**与实测不符**；
    > 且 `WhiteboardBrushPanel.ets:33` / `WhiteboardStatusBar.ets:18` **显示「Pen Kit 原生」而实际走 Canvas** ⇒ **UI 在对用户说谎** ✗✓

46. **并行窗口下「git status 前后逐字相同」这条判据不成立** ✗（W19 实测，2026-10-02）
    **实例**：两个窗口并行操作同一仓库时，W19 开工看到 ` M module.json5`（**不是它产生的**），
      收工时工作区**干净** —— 因为**并行的 W18 在收尾时把它还原了** ✓
    ⇒ 若沿用「开工/收工状态相同」的判据 ⇒ **会把别人的改动记成自己的成绩（或自己的破坏记成别人的）** ✗✓
    ⇒ **正确判据**：**「本窗口自己的写入面是否为空」** ✓ —— 即**逐条列出本窗口确实写过的文件**，
      并声明**未触碰**其余一切 ✓✓（**而不是比对一个会被他人改变的全局状态** ✓）

47. **一条被张冠李戴的实测证据：`previewText` 不投递 ≠ WebView 的问题** ✗（W19 更正，2026-10-02）
    **本仓长期引用**的「`onChange` 的 `previewText` 在真实组词时不投递」✗ ⇒ **常被用来论证「WebView 承载编辑器体验差」**
    **但实验对象是原生 `TextInput`（浮层）** ✓（`OverlayKeyRouter.ets:56-75` + 本文件 **§3 输入通道表下方那段 IME 结论** ✓ —— 原始记录已随归档删除 ✗）
    ⇒ 它证明的是「**HarmonyOS 应用侧 IME 合成态信号整体薄弱**」✓ —— **与 WebView 无关** ✗✓
    **⚠️ 而且方向相反的一条事实** ✗：**web 标准有 `compositionstart` / `isComposing`，原生 `RichEditor` 没有等价信号** ✓
      ⇒ **IME 合成态这一项，WebView 理论上更强** ✓（本仓 `WebEditor` 更差是**因为实现陈旧**：全仓 `isComposing` **0 命中** ✓ 页内层用**已废弃的 `document.execCommand`** ✓）
    ⇒ **教训**：**引用一条实测证据前，先确认它的实验对象是什么** ✗✓ —— 与陷阱 38 同族（**数据契约** ✓），
      但这里错的是**主体归属**：**「在 A 上测到的现象」不能拿来论证「B 不行」** ✓

48. **🔴 本机两条截图通道都返回陈旧帧**（**已由 W20 收窄为：现象保留 · 阳性对照要求升为无条件**） ✗✗（W17 实测，2026-10-02）
    **实测** ✗：`dumpLayout` 在三个不同界面给出 **916 → 740 → 466 节点**（**确实在变** ✓），
      而同期的 `snapshot_display` 截图 **md5 恒为 `E08B04E4…`** ✗、`emulator -screenshot` **md5 恒为 `C0607F07…` / 字节恒 1,388,504** ✗
    ⇒ **两条截图通道都吐旧帧** ✓ ⇒ **凡以「像素/观感」为判据的验收，在本机一律得不出结论** ✗✓
    **⇒ 判据** ✓✓：**用截图判分前，先对「已变的状态」跑一次阳性对照 —— md5 必须不同** ✗✓
      （**没跑阳性对照就引用截图 ⇒ 结论无效** ✗）
    > **与验证纪律 8 正好互补** ✓✓ —— 那条说「**文本检索**会假阴性」✓，本条说「**像素差分**在本机也假阴性」✓
    > ⇒ **本机两条通道各有一个盲区**；**修截图通道的优先级应上调** ✗（它挡死一整类验收：主题跟随 · 浮层开合 · R0 的「逐像素回基线」✓）

    > **⚠️ 收窄（2026-10-02 W20 裁决）** ✗✓：**本条的「现象」暂时不复现** ✗ —— W20 按本条自己要求的阳性对照跑了三腿：
    > `snapshot_display` = **227,757 B / `8CEA729C…`**（运行中）→ **197,132 B / `AEB50154…`**（force-stop 后桌面）→ **247,795 B / `BBC22C0E…`**（重启后）
    > ⇒ **三态三 md5 ⇒ 通道是活的** ✓✓（W20 当日像素类验收**可用** ✓）
    > **但本条不删除** ✗✓ —— **W20 无法解释 W17 当时的观测、也未复现其原始条件** ✗ ⇒
    >   **保留「现象登记」层面的描述**（W17 当日两条通道均陈旧 ✗）✓ **但把「判据」升为无条件要求** ✗✓：
    >   **凡用截图判分，必须先对「已变的状态」跑阳性对照（md5 必须不同）** ✓✓
    >   —— **这条要求与通道是否陈旧无关，它本身就该永久成立** ✓✓

49. **`uitest uiInput fling` 会崩应用；`swipe` 可用；`dircFling` 的推进量远小于预期** ✗（W17 实测，2026-10-02）
    **实测** ✗：`fling` 连续 4 次 ⇒ **pid 消失** + 新增 `cppcrash-…-20261002225818927.log`（418,969 B）✓；
      `swipe` 连续 15 次 ⇒ **应用全程存活** ✓
    ⚠️ **崩溃未归因** ✓（未做小页面阴性对照 ✓）⇒ **只登记，不主张因果** ✓
    ⚠️ **并修正 W16 的一条说法** ✗：**`dircFling` 的实际推进量只有 7–40 px/次** ✓（W16 说「行推进 ✓」方向成立 ✓ **但量级不符** ✗）
    ⇒ **滚动类验收的通道优先级** ✓：**`swipe`（慢速拖拽）> `dircFling` > `fling`（会崩，别用）** ✗✓

50. **`uitest uiInput` 用的坐标系 = `dumpLayout` 那一套（不是屏幕绝对坐标）** ✓（W17 实测，2026-10-02）
    **实测** ✓：点 `设置` 行中心 **(558,1626) 不加偏移** ⇒ 成功切到设置页 ✓；同会话内 **+515 / +518 偏移都无效** ✗
    ⚠️ **与 W13 的「dump 坐标 + (518,288) = 屏幕坐标」不矛盾** ✓ —— **那是换算到物理屏幕用的** ✓，**两者用途不同** ✓✓

51. **「首屏只有 N 个 X」≠「一共只有 N 个 X」** ✗✓（W17 实测，2026-10-02）
    **实例** ✗✓：W16 报「日志流首屏只渲染今天一节 ⇒ 其余 6 天不在首屏、`dumpLayout` 读不到」⇒ **被当成待归因异常** ✓
    **W17 用 `swipe` 慢速拖拽** ⇒ **第 2、3 个日期标题依次出现** ✓（**含那 1037 块的一天** ✓）⇒ **现象 = 在屏幕下方，不是缺陷** ✓✓ **结案** ✓
    **W16 为何被误导（三条机制 ✓）**：`dumpLayout` **只输出已布局节点** ✓（虚拟化下视口外**连节点都不存在** ✓）；
      **首屏那一节自身就比视口高 3 倍** ✓（今天 48 行 ≈3456 px vs 视口 1198 px ⇒ 第 2 个标题必然在 ≈2250 px 之下 ✓）；**当天滚动通道不可用** ✓
    ⇒ **可复用判据** ✗✓：**凡用 `dumpLayout` 数「滚动容器内的重复元素」，必须先证明滚动通道可用** ✓✓
      （**否则「数不到」会被误读成「不存在」** ✗ —— **与陷阱 3「工具读不到 ≠ 不存在」同族** ✓）

52. **`dumpLayout` 在本机取不到字号 —— `-a` 也是 no-op** ✗（W20 实测，2026-10-02）
    **三路都试了** ✗：默认 28 键**无 font\*** ✓；**`-a`（帮助自述 "include font attributes"）与不加 `-a` 逐节点 diff ⇒ 唯一差异是系统时钟文本** ✗；`-e fontSize` 报 `supported names are 'uniqueId'` ✗
    ⇒ **字号证据改走** ✓✓：**源码字面量普查 + 截图 ink 像素反推**（标定 CJK≈0.75em / 拉丁≈0.63–0.70em ✓）
    ⚠️ **本条已经开始让每个 UI 窗口重踩** ✗ ⇒ **先读本条再选通道** ✓


## 7b. 一条对抗性验证方法（值得复用）

**「构建绿了」不等于「这个文件真的被编译了」** —— 零引用文件可能被 tree-shake 成**假绿** ✗
**做法**：往目标文件**注入一处故意的类型错误**，重新构建 ——
- 若构建失败且**报错落在该文件内** ⇒ 它确实在编译图里 ✓（可放心继续）
- 若构建仍绿 ⇒ 它没被编译，**先前的「能编译」结论无效** ✗

本仓已在 `PageContextMenu.ets` 上用过此法：注入后报 `PageContextMenu.ets:44:11 Type 'string' is not assignable to type 'number'`，撤销后复绿 ✓

### 7c. 另一条：**夹具（fixture）字节级复位法**（W10 新增，值得复用）

反复在同一个合成夹具上做破坏性实验（删除/撤销/重做）时，用 shell 手工修补会把夹具
越改越乱（实测把 `__S1_long.md` 改成过 297/296/295 行且顺序错乱）。
**正确做法**：
1. 先在本地用脚本**重建夹具**，并核对 MD5 与最初基线**逐字节相同**
   （`__S1_long.md` = `测试块 2..299` 共 298 行、**无结尾换行** ⇒ 4661 字节 /
   MD5 `501bf94f19171bd19844d1724f2ecaa2`）。
2. `hdc file send` 推到 `/data/local/tmp/`，再
   `hdc shell "cp /data/local/tmp/X.md <vault>/X.md"`。
   > **修正一条旧说法**：本文件 §1 说该 vault 路径「对 shell 只读」——
   > 实测 `cp` **可以写成功**（`ls -l` 属主 20020059，模拟器 shell 有权限）。
   > 只读的是**宿主机的普通写操作**，不代表 `hdc shell` 里的 `cp`/`>` 不行。
3. 每次实验前 `md5sum` 断言夹具已复位，再冷启动；这样各轮实验的基线**可比**。
   > ⚠️ **环境前提（2026-09-30 W6 实测，会让 §7c 整体失效）**：**`hdc uninstall` 会重建沙箱，并使其不可 shell 写** ✗ ——
   > 重建后 `.../haps/entry/files` 为 `drwxrwx---`、属主为 app uid、父目录不可 traverse、**SELinux Enforcing**（`debug_hap_data_file`）⇒
   > `touch` / `echo >` / `cp` / `hdc file send` / `chmod` **全部 `Permission denied`** ✗，`run-as` **不存在** ✗，
   > `/mnt/debugtmp/.../el2/base`（同一 ext4）与 `preferences/` 同样拒绝 ✗ ⇒ **夹具无法从 shell 恢复** ✓
   > **⇒ 不要用 `uninstall` 去排除「包是否更新」** ✗ —— 改为**核对 HAP mtime 与安装时刻**、或看包内 abc 标识 ✓
   > （W6 就是这样踩的：首次验收跑出修复前的行为，原因是**装到了旧包**，而它用 uninstall 去验证 ⇒ 代价是夹具被删且不可恢复 ✓）
   > ⚠️ **补充（W7 实测）**：`files/graph` 即使已是 `drwxrwxrwx`（**Unix 位允许** ✓）**写入仍被拒** ✗
   > ⇒ **除权限位外 SELinux（Enforcing）也在拦** ✓；`force-stop` / 冷启动 / 模拟器冷启**三种重启都不恢复** ✓
   > ⇒ **沙箱权限是「创建时定死」的，该 uninstall 代价不可逆** ✗
   > ⇒ **凡依赖「shell 写 vault」的验收，必须先跑一次写入阳性对照** ✗ 不要假定 §7c 成立 ✓
   > ✅ **替代路线（W7 已验证）**：**应用内构造** —— 每注入一次 `Enter`(2054) 就多一块并落盘（**+3 B/块** ✓），
   > **完全不需要 vault 写权限** ✓，约 0.3 s/块 ⇒ 298 块约 2–3 分钟 ✓（适合造压测用长页 ✓）
   ⇒ 没有这一步，「撤销是否回到删除前」这类断言根本无法复核。


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
