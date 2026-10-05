#!/bin/bash
# O1 验收脚本 v2：强杀生存测试（即时落盘 / SaveQueue）
#
# 用法：bash verify_o1_wal.sh [连接键，默认 127.0.0.1:5555]
# 环境：平板实例 MatePad Pro 13（2880x1920）——坐标**动态解析**，不写死，换设备也能跑
#
# v2 相对 v1 的三处修正（均为实测发现）：
#   1. 旧版写死坐标 (22,105)/(1500,800) 是 O5 双栏改造前的布局，点不中目标 → 改为
#      从 dumpLayout 里按文本查节点中心（find_node.py）。
#   2. `uitest uiInput text` **注入中文无效**（实测多次不落屏），故测试文本改 ASCII。
#   3. 旧版强杀重启后直接断言，但重启落在 Home 标签、页面内容不在屏上 → 补「点开树节点
#      再断言」这一步。
set -u

# Git Bash(MSYS2) 会把 /data/local/tmp/... 之类的**设备端路径**改写成 Windows 本地路径，
# 导致 dump/recv 静默失败 —— 必须关闭参数转换（v1 未处理，属脚本缺陷）。
export MSYS2_ARG_CONV_EXCL='*'
# Python 输出含 ✅/❌ 等字符，Windows 控制台默认 GBK 会抛 UnicodeEncodeError
export PYTHONIOENCODING=utf-8

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
PY="${USERPROFILE:-$HOME}/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
T="${1:-127.0.0.1:5555}"
WORK=/f/DevEcoStudioProjects/uiwalk/tablet
# 每轮唯一 marker：固定文本会被上一轮遗留页面"满足"，导致假通过（v2 首版即有此缺陷）
MARK="WALT$(date +%H%M%S)"
STRIP_NEW_X=135            # 活动栏「新建」图标（LeftSidebar strip 首个图标，布局稳定）
STRIP_NEW_Y=132
GRAPH_DIR="/data/app/el2/100/base/com.example.callaite/haps/entry/files/graph"

cd "$WORK" || { echo "工作目录不存在：$WORK"; exit 1; }

sh_() { "$HDC" -t "$T" shell "$1" >/dev/null 2>&1; }
dump() {
  sh_ "uitest dumpLayout -p /data/local/tmp/$1.json"
  "$HDC" -t "$T" file recv "/data/local/tmp/$1.json" "$1.json" >/dev/null 2>&1
}
# 按文本找坐标：xy <dumpname> <text> [额外参数...]
# 注意：Windows 上 Python 输出为 CRLF，必须裁掉 \r，否则坐标参数带控制字符 → 点击不生效
xy() { "$PY" find_node.py "$1.json" "$2" "${@:3}" 2>/dev/null | tr -d '\r\n'; }
click_xy() { sh_ "uitest uiInput click $1 $2"; }
# 等待界面可交互：轮询直到 dump 中出现侧栏搜索框文本（冷启动应用约需 14~18s）
wait_ui() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    dump ready
    if grep -q "搜索或开始搜索" ready.json 2>/dev/null; then return 0; fi
    sleep 3
  done
  return 1
}

echo "== O1 强杀验收（设备 $T） =="

echo "[1/7] 启动应用"
sh_ "aa start -a EntryAbility -b com.example.callaite"
if wait_ui; then echo "  ✔ 界面就绪"; else echo "  ⚠ 等待界面超时，继续尝试"; fi

echo "[2/7] 新建一个页面（活动栏新建图标 → 新建大纲笔记）"
click_xy "$STRIP_NEW_X" "$STRIP_NEW_Y"; sleep 4
dump dlg
POS=$(xy dlg "新建大纲笔记")
if [ -z "$POS" ]; then           # 首次未弹出则重试一次（冷启动后首点偶发不响应）
  click_xy "$STRIP_NEW_X" "$STRIP_NEW_Y"; sleep 4
  dump dlg
  POS=$(xy dlg "新建大纲笔记")
fi
if [ -z "$POS" ]; then POS=$(xy dlg "新建 Markdown 笔记"); fi
if [ -n "$POS" ]; then click_xy $POS; sleep 5; echo "  ✔ 页面已创建"; else echo "  ⚠ 新建对话框未出现，改用当前页面继续"; fi

echo "[3/7] 进入正文块编辑态并注入 $MARK（带重试：uitest 注入实测不稳定）"
dump e1
# 入口优先级：① 空页占位「输入内容」 ② 页面底部「添加」按钮（已有内容时用，点它会新建并聚焦块）
POS=$(xy e1 "输入内容")
if [ -z "$POS" ]; then POS=$(xy e1 "添加" --min-x 700); fi
[ -z "$POS" ] && POS="995 402"        # 兜底：新建页空块的稳定位置
PX=${POS% *}; PY_=${POS#* }
ONSCREEN=""
for i in 1 2 3; do
  # 方式 A：inputText 在目标坐标点直接输入（一步完成点击+输入）
  sh_ "uitest uiInput inputText $PX $PY_ $MARK"
  sleep 3
  dump "try$i"
  if grep -q "$MARK" "try$i.json"; then ONSCREEN=1; echo "  ✔ 已上屏（第 $i 轮 / inputText）"; break; fi
  # 方式 B：先点两次取得焦点，再用 text 注入
  click_xy "$PX" "$PY_"; sleep 2
  click_xy "$PX" "$PY_"; sleep 2
  sh_ "uitest uiInput text $MARK"
  sleep 3
  dump "try${i}b"
  if grep -q "$MARK" "try${i}b.json"; then ONSCREEN=1; echo "  ✔ 已上屏（第 $i 轮 / 双击+text）"; break; fi
  echo "  … 第 $i 轮未上屏，重试"
done
if [ -z "$ONSCREEN" ]; then
  # ⚠️ 注入未上屏时必须**作废本轮**，而不是继续跑断言 —— 否则脚本会把
  #    「uitest 注入抖动」误报成「即时落盘未生效」，制造假失败（2026-09-25 实测踩坑：
  #    全盘 grep 不到 marker，说明文本从未进入页面，与保存链路无关）。
  echo "  ✘ 三轮注入均未上屏（uitest uiInput 文本注入抖动，Enter 键注入正常）"
  echo "O1 验收: ⚠️ 未结论（本轮作废，非落盘缺陷）—— 建议重跑，或改用软键盘/真机输入"
  exit 2
fi
echo "[4/7] 等待 SaveQueue 静默窗口(1.2s)"
sleep 4

echo "[5/7] 强杀（跳过 onBackground —— 验收关键）"
sh_ "aa force-stop com.example.callaite"; sleep 3

echo "[6/7] 重启应用并打开该页面"
sh_ "aa start -a EntryAbility -b com.example.callaite"; sleep 14
dump r1
POS=$(xy r1 "未命名" --max-x 700 --last)
if [ -n "$POS" ]; then click_xy $POS; sleep 5; else echo "  ⚠ 树中未找到页面节点"; fi

echo "[7/7] 断言（唯一 marker：$MARK）"
dump r2
# ── 权威断言：磁盘上必须存在含本 run marker 的 .md（强杀后未丢失）──
DISK=$("$HDC" -t "$T" shell "grep -l $MARK $GRAPH_DIR/*.md 2>/dev/null" 2>/dev/null | tr -d '\r')
if [ -n "$DISK" ]; then
  echo "  ✔ 磁盘断言：marker 已落盘 → $DISK"
else
  echo "  ✘ 磁盘断言：marker 未落盘（即时落盘未生效）"
fi
# ── 界面断言：重启后打开页面能看到该文本 ──
"$PY" - "$MARK" <<'PYEOF'
import json, sys
mark = sys.argv[1]
try:
    data = json.load(open('r2.json', encoding='utf-8'))
except Exception:
    print('O1 验收: ❌ 采集失败（设备未连接或 dump 未生成）'); raise SystemExit(1)
texts = []
def walk(n):
    a = n.get('attributes', {}) or {}
    t = (a.get('text') or '').strip()
    if t: texts.append(t)
    for c in n.get('children', []) or []:
        walk(c)
walk(data)
hit = [t for t in texts if mark in t]
print('界面断言:', '✅ 重启后页面内可见' if hit else '⚠ 未在屏上（可能点开了其它同名页面，以磁盘断言为准）', hit[:2])
raise SystemExit(0)
PYEOF
if [ -n "$DISK" ]; then
  echo "O1 验收: ✅ 通过（强杀生存：写入 → 无 onBackground 落盘 → force-stop → 重启后数据完好）"
  exit 0
else
  echo "O1 验收: ❌ 未通过"
  exit 1
fi
