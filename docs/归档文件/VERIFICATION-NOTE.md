# 逆向报告归档说明与使用边界（VERIFICATION-NOTE）

- **归档**：2026-09-26，两份报告入 `docs/reverse/`：
  - `Obsidian-Parser-Editor-Deep-Dive.md`（原「解析器与编辑器拆解报告」，下称 R1）
  - `Obsidian-Reverse-Architecture.md`（原「obsidian逆向分析报告」，下称 R2）
- **外部核验**：DeepSeek 三份核验报告（2026-09-26）对两报告做了独立取证。核验结论摘要：

## 核验要点（影响 Callaite 使用的部分）

1. **实证等级高**：分析产物（worker.pretty.js / api-exports.txt / asar 解包）经磁盘取证真实存在；关键代码原文（IndexedDB 建库、worker 正则）与产物一致；用户数据交叉验证通过。**版本绑定注意**：本机实际运行 1.13.7（2026-09-19 热更新），报告逆向的是 1.10.6——两版间差异未审计，引用时以「1.10.6 实证」口径。
2. **R1 含 7 处错误**（核验报告 §3）：spec 从 3.x（非 1.10.6 自带）、d+ 正则含义（`d+` 是缺省页语法 `\d+`）、保存 API 事件名未检出、userHook 未检出等——**均已标注**，引用 R1 时先过其勘误表。
3. **CM6 机制对 Callaite 的可迁移性警示（N1-N3）**：核验指出装饰/StateField/Compartment 是 CM6 专有机制，不可直接移植到 ArkTS RichEditor——**Callaite 不受此限**：DocumentEditor 是 WebView+DOM 路线，装饰翻转在 DOM 中是常规实现（PLAN-DocumentEditor ADR-001 论证时已确认这一点）。
4. **N8 方言差异**：Obsidian 连续文本 vs Callaite 块模型——附录 C 已加总则（行为为兼容参考非判定标准）。
5. **合规边界（R1-R3，用户本人执行项）**：
   - 逆向产物目录（`WorkBuddy\...\obsidian-analysis\`）**不入库、不上传**——本仓库归档的仅是两份**行为分析报告**文本
   - Callaite 不得复刻 Obsidian 的 UI 外观/图标/商标；对外文案中 "Obsidian" 仅指称性使用
   - 附录 C 只含**行为规格**（输入 → 期望行为），不含函数名/正则原文——保持 clean-room 界限，此为使用两报告的铁律

## 使用规则（写给我自己/未来会话）

- 引用 R1/R2 任何结论 → 同时标注版本（1.10.6）与核验勘误状态
- 附录 C 维护时新增用例：只写行为断言，不抄实现细节
- PLAN-DocumentEditor v1.1/v1.2 的「R1 §x / R2 §x」引用均指向本目录归档版
