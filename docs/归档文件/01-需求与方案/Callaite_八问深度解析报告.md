# Callaite 深度解析报告 —— 八问逐一回答

> 分析对象：Callaite（本会话持续开发的项目）· 140 个 .ets 源文件 · 34,195 行
> 分析日期：2026-09-24 · 证据来源：全程会话代码改动与实测 + 本轮针对性代码取证
> 结论分级：✔ 已实证 / ◐ 代码完成未实证 / ✘ 未实现

---

## 一、与 Obsidian 的功能差异与完成度统计

### 功能对照（Obsidian 核心功能 → Callaite 状态）

| Obsidian 功能 | Callaite 状态 | 完成度 |
|---|---|---|
| Markdown 编辑（所见即所得） | 块级 WebView 编辑器 + Live Preview v1（闭合标记即时格式化） | ◐ 75% |
| 双向链接 [[ ]] / (( )) | 页面/块引用 + 反向链接面板 + 重命名传导 | ✔ 90% |
| 文件树（层级/折叠/高亮） | 命名空间树 + 箭头折叠 + 当前页高亮 + 统计行 | ✔ 90% |
| 标签页系统 | 多标签 + 分屏 + 新标签页（Obsidian 式三链接） | ✔ 85% |
| 知识图谱 | 力导向 Canvas + 当前页高亮分色 | ✔ 85% |
| 快速切换 / 命令面板 | 搜索面板 + 提示行（功能合并于一个面板） | ◐ 80% |
| 查询 | 三层查询引擎（多条件 + Datalog + 递归规则）—— **超出 Obsidian 原生** | ✔ 85% |
| 任务管理（TODO 循环/计划面板） | 完成 | ✔ 90% |
| 闪卡（FSRS-4.5） | 完成（Obsidian 需插件） | ◐ 85% |
| 白板 | Canvas 白板（形状/连线/笔触/.canvas）+ Pen Kit 引擎选择 | ◐ 60% |
| PDF 阅读/标注 | WebView pdf.js + 高亮持久化 | ◐ 80% |
| 插件系统 | 预编译插件框架 + 4 内置插件 | ✔ 85% |
| 模板/属性系统 | 模板变量 + 6 类型属性引擎 | ✔ 85% |
| 多窗口/设置窗口 | 应用内页面（非独立窗口） | ◐ 50% |
| 主题（明暗） | 双套 token（对齐 Obsidian 官方变量） | ✔ 90% |
| 同步 | 端云协同（Obsidian 为付费 Sync） | ◐ 代码 90% |
| 碰一碰/NFC | **未实现** | ✘ 0% |

**综合完成度：约 78%**（按上表加权）。结构层基本齐平；差距集中在：① 全文连续编辑器与完整 Live Preview；② 白板形态；③ 独立窗口；④ 同步真机验证。

## 二、Markdown 编辑器技术路径与 Obsidian 体验评析

### 技术路径（实证）
1. **架构**：每 Block 一个 WebView contenteditable 微编辑器；HTML 写入应用沙箱后以 `file://` 加载（`src` 直传/`loadData` 实测渲染空白，沙箱文件是唯一可靠方案）
2. **通信**：JS keydown 拦截（Enter/Tab/Backspace/Arrow）→ `NativeBridge.onAction` → EditorService → OutlinerEngine → DataStore → MarkdownExporter → FileRepository
3. **保存**：输入防抖 400ms 自动落库（只保存不退编辑态）；失焦保存并持久化 .md
4. **渲染**：非编辑态由原生 ContentSegments 渲染（粗体/斜体/高亮/代码/链接/`[[ ]]`/`(( ))`/`#标签`/KaTeX/Mermaid/表格）
5. **Live Preview v1**（本会话新增）：闭合标记即时格式化（`**粗体** ` `==高亮== ` `[[链接]]` 等 6 类）+ **DOM→Markdown 序列化器**（nodeToMd/editorToMarkdown/rangeToMarkdown），save/autosave/Enter 分割全部走序列化，防止格式化后丢标记

### 能否复刻 Obsidian 编辑体验 —— 评析
- **可复刻**：块级编辑 + 所见即所得渲染 + 双链/标签 + 快捷键体系 + Live Preview 打字期格式化 —— 核心体验闭环成立。**同工作区的 Lunius 项目已实证**：其 MarkdownEditor 实现了 Live/Source/Preview/Split 四模式（代码中 16 处模式引用），证明该技术栈内完整 Live Preview 可行
- **当前代差**：① Obsidian 为**全文连续编辑器**（跨块选择、块间拖拽、光标感知语法隐藏——活动行源码/其余行渲染），Callaite 为块级离散编辑，v1 格式化仅覆盖"打字时"；② 编辑器受限于 contenteditable（长文档性能、IME 复杂粘贴）；③ Obsidian 的主题 CSS 变量/插件化编辑器扩展无对应
- **演进建议**：参照 Lunius 的整页编辑器 + 段级渲染管线重构，将四模式引入 Callaite；这是复刻完整 Obsidian 编辑体验的关键路径

## 三、UI/UX 与 HarmonyOS 规范符合性 + 还原度评定

### 规范符合项（实证）
- 一多断点三形态（sm<600≤md<840≤lg：手机玻璃悬浮 / 中屏收起 / 平板完整桌面）
- 交互热区 40vp（官方 7.1.1.3.3），圆角/间距/动效（stateStyles + 140ms）体系统一
- 沉浸式布局 + avoidArea 避让 + 系统栏全透明 + 内容色随主题（本会话实机验证 ✔）
- 深浅色双套 token（对齐 Obsidian 官方变量，浅色像素级实测 #F2F3F5/#FFFFFF ✔）
- appRecovery 崩溃恢复、StatePersistence 自管持久化、无第三方运行时依赖
- 已知偏差：PC/2in1 全屏按官方限制分支处理 ✔；API 26 模拟器 THREAD_BLOCK_6S 未定位（真机待确认）

### 还原度评定（对照 Obsidian Pictures 21 张截图）
- **结构层 ~90%**：Ribbon + 侧栏(文件树) + 标签页 + 编辑区 + 状态栏 + 双分屏 + 新标签页三链接 + 快速切换 + 文件树统计行 + 图谱分色（当前页紫）+ 模态规范
- **细节层 ~75%**：白板原生形态（右竖排工具栏/中央提示卡）未复刻（用户明确排除）；设置窗口为应用内双栏而非独立窗口；仓库切换器为功能映射近似
- **综合还原度 ≈ 82%**

## 四、文件管理机制深度分析

### 架构（自上而下）
```
编辑/操作 → OutlinerEngine（17 种操作 + 50 层撤销）→ DataStore（内存 BlockTree + IndexStore 三索引）
  → MarkdownExporter（Logseq .md 兼容）→ FileRepository（fd 写入）
沙箱 filesDir：页面 .md / 白板 .canvas（JSON Canvas 1.0）/ 配置 JSON / 加密密钥
```
- **原子写**：临时文件 + `fs.fsyncSync` + `fs.renameSync` 原子替换（代码实证，异常退出不破坏原文件）
- **加密**：AES-256-CBC + `cryptoFramework` 随机 32 字节密钥（持久化沙箱文件，非硬编码）+ 随机 IV
- **重命名**：`DataStore.renamePage` + IndexStore 反向链接索引传导
- **导入导出**：MD/HTML/OPML；回收站（RecycleEngine）

### 潜在漏洞与风险（按严重度）
1. **【高 · 已实证】强杀丢数据**：多次 `force-stop` 跳过 onBackground/onSaveState，未落盘的页面丢失（本会话实测工作区两次清空）。建议：编辑后即时增量持久化，或缩短防抖与后台存盘间隔
2. **【中】云同步 last-write-wins**：按 mtime 取舍，双端并发编辑将丢失较旧一侧改动（无合并/冲突副本）
3. **【中】保存竞态未证实**：多标签同时编辑同一页时，异步保存序列缺乏锁/序号机制（单 UI 线程缓解，但未验证）
4. **【低 · 待复核】路径穿越清洗**：README 声称页面名清洗 `/ \ ..`，本轮 grep 未在 FileService 直接命中，建议定位实现位置并补单元测试
5. **【低】无文件级版本历史**（回收站为 Block 级）

## 五、白板功能与 UI 评析

- **核心能力 ✔**：形状/连线/页面引用/压感笔触/撤销重做（50 层）/.canvas 持久化（JSON Canvas 1.0）/无限平移缩放；笔迹引擎运行时选择（`canIUse('SystemCapability.Stylus.Handwrite')` → Pen Kit 原生管线 / Canvas 压感兜底），两引擎共享数据模型
- **符合预期与否**：核心达标（可画/可存/可撤销/可重做/可引擎降级）；**Pen Kit 真机未验证**（HSP 硬依赖已隔离在启动路径外）
- **UI 合理性**：与应用统一（token/40vp 热区/三态动效）但**与 Obsidian 白板形态有差距**——Obsidian 为右侧竖排工具栏 + 中央提示卡 + 底部新建按钮，本项目为顶部横排工具栏 + 笔刷面板；贴纸/卡片节点未实现（该项复刻此前已由用户明确排除）

## 六、传输功能（多端流转 / 超级协同 / 碰一碰 / 云同步）

| 能力 | 实现状态 | 设备验证 |
|---|---|---|
| 多端流转 | ◐ `continuable: true` + onContinue/onRestoreData（迁移 5 项状态字段） | ✘ 需双设备 |
| 超级协同 | ◐ DistributedKVStore + autoSync + dataChange 监听 | ✘ 需双设备同账号 |
| 碰一碰互传 | ✘ **无任何 NFC/TagSession/ShareKit 代码**（grep 全库证实） | — |
| 云同步 | ◐ CloudSyncService + AES 加密 + Free/Pro 配额门控 + LWW 冲突 + 元数据索引同步 | ✘ 需 AGC 配置 + 华为账号 |

**结论**：传输类功能全部处于"代码完成、系统级未验证"状态；**碰一碰互传为功能缺口**（如需实现，走 NFC TagSession 或 华为分享 Kit，需新增权限与能力声明）。

## 七、HarmonyOS 特性功能核验

| 特性 | 状态 |
|---|---|
| 华为账号（distributedAccount 读取） | ◐ 代码完成；返回值规则已按 API 26 适配 |
| IAP 订阅 | ◐ 代码完成（查询/购买/确认/24h 刷新/沙箱缓存）；需 AGC 商品 |
| 服务卡片（2×2 概览 + 速记） | ◐ 代码完成；设备端添加卡片未回归 |
| 分享接收（ShareReceiveAbility） | ◐ 代码完成；系统分享路径未回归 |
| 崩溃恢复 + 全局异常捕获 | ✔ 已启用（appRecovery + errorManager） |
| 状态持久化（自管 JSON） | ✔ 已启用（启动恢复 10 键） |
| 沉浸式布局 / 系统栏 / 深浅色主题 | ✔ **实机验证通过**（本会话） |
| API 26 行为变更适配（6 项 P0） | ✔ 代码完成（Canvas 防护/长按/Button/账号/PC 分支/动画） |
| Pen Kit 手写笔 | ◐ 按需模块（HSP 隔离）；真机未验证 |
| 碰一碰 | ✘ 未实现 |

**结论**：特性功能**代码层完整度高**；系统级真机验证覆盖率低——需真机 + 华为账号 + AGC 云端配置才能闭环。

## 八、发布条件评定

**结论：尚未具备发布条件；已具备"内部测试版（Beta）"条件。**

### 已具备
- 功能主体代码完成（140 文件 / 34,195 行），构建稳定（debug 全量通过）
- 核心编辑/组织/查询/图谱/白板/闪卡/插件闭环可用
- UI 对齐 Obsidian ≈82%，符合 HarmonyOS 一多与交互规范主体
- 安全基线（AES-256、原子写、沙箱、WebView 转义）
- 发布前检查清单已内置于 README

### 发布阻塞项（按优先级）
1. **签名与包名**：release 无证书、`bundleName` 仍为 `com.example.callaite` 占位
2. **AGC 云端**：项目/应用未创建，IAP 商品与云同步能力未配置（IAP/云同步在无 AGC 时不可用）
3. **真机回归**：多端流转/协同/云同步/IAP/服务卡片/分享接收/闪卡复习——全部未在真机系统级回归
4. **稳定性**：API 26 模拟器 THREAD_BLOCK_6S 未定位（建议真机复测确认是否模拟器特有）
5. **强杀丢数据**（文件管理高危项）需修复
6. Pen Kit 需 product flavor / HSP 模块架构决策
7. 碰一碰互传如属需求范围需立项实现

### 建议路径
① 真机修复强杀丢数据 → ② 配置签名 + AGC → ③ 三设备回归清单（README 第六节）→ ④ 内部 Beta → ⑤ 上架评审。

---
*本报告全部结论基于代码取证与 API 24/26 模拟器实测；"未验证"项均如实标注，不代表功能不可用。*
