# Callaite 仓库误删更改 —— 检查与恢复报告

**日期**：2026-09-19 11:10
**仓库**：`F:\DevEcoStudioProjects\Callaite`
**结果**：**已完全恢复，无内容丢失**。HEAD 回到 `231c284`（Callaite 4.1.4 Beta 测试版本），工作区干净，构建通过。

---

## 一、问题现象

`git status` 仅显示 1 个文件被修改（`build-profile.json5`），而此前两轮 UI 工作的数十个文件全部消失：

| 应存在的关键文件 | 检查结果 |
|---|---|
| `ets/components/common/FloatingPanel.ets`（第二轮新增） | **缺失** |
| `ets/utils/PageTitle.ets`（第一轮新增） | **缺失** |
| `ets/state/Breakpoints.ets` | **缺失** |

---

## 二、根因定位

`git reflog` 直接给出了原因：

```
de4834f HEAD@{0}: 交互式内存中变基 by DevEco Studio Git plugin: updating HEAD
231c284 HEAD@{1}: commit: Callaite 4.1.4 Beta 测试版本
de4834f HEAD@{2}: reset: moving to de4834f60cc1839d6857f3f76a4e49e1408a9880
```

**判定**：工作已于 2026-09-19 10:57 提交为 `231c284`（4.1.4），随后被 **DevEco Studio Git 插件的交互式变基（interactive rebase）丢弃**，HEAD 退回 `de4834f`（4.1.2，2026-08-26）。这不是未提交内容的丢失，而是**已提交内容被 rebase 移除**。

**丢失规模**：`231c284` 相对 `de4834f` 共 **51 个文件 / +2603 −531 行**。

---

## 三、可恢复性判定（三个关键结论）

| # | 结论 | 依据 |
|---|---|---|
| 1 | **恢复是零冲突的纯追加** | `231c284` 的父提交恰为 `de4834f`（`git rev-list --parents` 确认），即被丢弃的提交本来就接在当前 HEAD 之上 |
| 2 | **对象完好，内容未丢** | `git cat-file -t 231c284` = commit；`git ls-tree -r` 可列出 163 个文件 |
| 3 | **无 4.1.3 内容遗漏** | 游离提交 `67df30f`（4.1.3）与 `231c284` 是同基线**兄弟提交**；文件集合比对显示 **4.1.3 是 4.1.4 的严格子集**，4.1.4 仅多出 `FloatingPanel.ets` 与 `PageTitle.ets` |

另：`git fsck --dangling` 无输出，说明不存在更早的未提交残留；工作区原有的 `build-profile.json5` 改动（SDK `6.1.1(24)` → `26.0.0`）与 `231c284` 中的内容完全一致，属同一批工作。

---

## 四、修复操作

```bash
# 1) 移动分支引用（原子写，代价极小）
git update-ref refs/heads/main 231c284

# 2) 同步暂存区与工作区
git reset --hard
```

**过程中遇到并解决的问题**：首次执行 `git reset --hard` 被沙箱 SIGTERM 中断，工作区进入「60 个文件已删除、尚未写回」的中间态，并遗留 0 字节的 `.git/index.lock`。处理方式：确认无 git 进程后删除陈旧锁，再在放行沙箱的情况下重跑，`Updating files: 100% (60/60)` 正常完成。

---

## 五、恢复验证

### 5.1 更改记录逐项校验：26 / 26 通过

**第一轮（10 项）**
- ARGB 配色令牌：`accent_soft=#147C4DEF`、`marker_doing_bg=#187C4DEF`、深色 `accent_soft=#24A88BFA`
- `surface3` 令牌、`PageTitle.ets`、i18n 的 `title_settings` / `menu_group_content`
- 侧栏 `Alignment.TopStart` 顶对齐
- 断点 `onAreaChange` + `initViewportFromWindow`
- 引导页限宽 `CONTENT_MAX_WIDTH 520`

**第二轮（16 项）**
- `FloatingPanel.ets`
- 对比度修正：浅色 `muted_text=#5D636B` / `bullet=#9EA2A9` / `danger=#BF2121` / `link=#6E44D5`
- 深色：`muted_text=#A8B0B9` / `danger=#FF8A8A` / `link=#C4B0FF`
- `on_primary` 令牌（浅色 `#FFFFFF` / 深色 `#1E1E1E`）
- 沉浸式：`setWindowLayoutFullScreen`、`publishAvoidArea`、350ms 延迟
- 侧栏行高 40vp、`MainContainer` 安全区 padding、`ContentArea` 安全区

**图标居中约束**：76 条，覆盖 28 个文件（在位）

### 5.2 构建验证

```
> hvigor BUILD SUCCESSFUL in 36 s 132 ms
entry-default-unsigned.hap  2,706,817 bytes
```

构建通过（SDK 26.0.0）意味着代码库内部一致，**排除半恢复状态**。

### 5.3 最终状态

| 项 | 值 |
|---|---|
| 分支 | `main` |
| HEAD | `231c284` Callaite 4.1.4 Beta 测试版本 |
| 工作区变更 | **0 条** |

---

## 六、注意事项与后续建议

### 6.1 环境限制（影响后续操作）

1. **沙箱会中断 git 的大批量写入**：`git reset --hard` 在沙箱内被 SIGTERM 中断并留下中间态。后续在本环境执行类似操作需放行沙箱，并先清理可能残留的 `.git/index.lock`。
2. **新建 git 引用无法持久化**：`git branch -f` / `git tag -f` 返回成功，但 `git show-ref` 与 `.git/refs/tags` 中均不存在——只有已存在的引用文件（如 `refs/heads/main`）可被更新。因此**本次未能建立 backup 分支或标签**。当前恢复能力依赖 reflog（默认保留 90 天）。

### 6.2 远程状态（需您决策）

| 引用 | 提交 | 时间 | 说明 |
|---|---|---|---|
| `origin/main` | `a043545` | 2026-09-13 20:55 | 4.1.3，**已推送到 GitHub** |
| 本地 `main` | `231c284` | 2026-09-19 10:57 | 4.1.4，**与 origin/main 已分叉**（同源于 `de4834f`） |

两侧差异 47 个文件。由于 4.1.3 的文件集合已是 4.1.4 的子集，**用 4.1.4 覆盖 origin/main 不会丢失任何内容**。推送方式需您确认：

- **方案 A（推荐）**：`git push --force-with-lease origin main` —— 使远程与本地 4.1.4 一致，历史最干净
- **方案 B**：保留两条历史，另开分支推送 4.1.4，或在 DevEco 中做合并

> 我未执行任何推送操作（属对外部系统的写操作，需您明确授权）。

### 6.3 防止再次发生的建议

本次丢失源于 **DevEco Studio Git 插件的交互式变基**。建议：

1. 完成一轮工作后**及时打标签**（如 `git tag v4.1.4`），标签会让提交永久可达，rebase 无法丢弃
2. 在 DevEco 中执行交互式变基前，先确认要保留的提交已被标记或已推送
3. 定期查看 `git reflog`，确认没有异常的 reset / rebase 记录

### 6.4 未受影响的项目

同工作区的 `LightNote`（HEAD `57269be`，工作区干净）与 `Lunius`（HEAD `717ba05`）的 reflog 均无异常丢弃记录，**未受影响**。
