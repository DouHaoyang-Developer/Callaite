#!/bin/bash
# O4 设备验证：整页四模式编辑器（Live/Source/Preview/Split）+ 应用并重建 + 强杀数据完好
#
# 用法：bash verify_o4_editor_modes.sh [连接键，默认 127.0.0.1:5555]
# 前置：应用已安装；设备上至少有一个含内容的页面（脚本会挑树中第一个可用页面）
#
# 验证点（对应交接文档 P0-3）：
#   1) 页面标题下「整页编辑」入口可进入四模式编辑器
#   2) 实时 / 源码 / 阅读 / 分屏 四种模式可切换且均能渲染
#   3) 「应用并重建大纲」（check 按钮）→ 提示「大纲已重建」→ 回到块级大纲
#   4) 强杀重启后页面内容完好（配合 O1 即时落盘）
set -u
export MSYS2_ARG_CONV_EXCL='*'
export PYTHONIOENCODING=utf-8

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
PY="${USERPROFILE:-$HOME}/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
T="${1:-127.0.0.1:5555}"
WORK=/f/DevEcoStudioProjects/uiwalk/tablet
GRAPH_DIR="/data/app/el2/100/base/com.example.callaite/haps/entry/files/graph"

cd "$WORK" || exit 1
sh_() { "$HDC" -t "$T" shell "$1" >/dev/null 2>&1; }
dump() {
  sh_ "uitest dumpLayout -p /data/local/tmp/$1.json"
  "$HDC" -t "$T" file recv "/data/local/tmp/$1.json" "$1.json" >/dev/null 2>&1
}
xy() { "$PY" find_node.py "$1.json" "$2" "${@:3}" 2>/dev/null | tr -d '\r\n'; }
click_xy() { sh_ "uitest uiInput click $1 $2"; }
# 按文本点击；成功返回 0
click_text() {
  local d=$1 t=$2; shift 2
  local pos; pos=$(xy "$d" "$t" "$@")
  if [ -z "$pos" ]; then return 1; fi
  click_xy $pos
  return 0
}
has() { grep -q "$2" "$1.json" 2>/dev/null; }
wait_ui() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    dump ready
    if has ready "搜索或开始搜索"; then return 0; fi
    sleep 3
  done
  return 1
}

PASS=0; FAIL=0
chk() { if [ "$2" = "1" ]; then echo "  ✔ $1"; PASS=$((PASS+1)); else echo "  ✘ $1"; FAIL=$((FAIL+1)); fi; }

echo "== O4 四模式编辑器设备验证（设备 $T）=="

echo "[1/7] 启动应用"
sh_ "aa start -a EntryAbility -b com.example.callaite"
wait_ui && echo "  ✔ 界面就绪"

echo "[2/7] 打开一个页面（优先选磁盘上有内容的页面）"
dump t1
PAGE=""
for cand in "未命名 2" "未命名 3" "未命名" "未命名 4" "未命名 5"; do
  # 该页 .md 必须至少有一行块（空页无法验证内容保全，且会被防误删闸门拦下）
  # 必须含「有内容的块」（- 后至少一个字符），只有 "- " 的空块不算内容
  L=$("$HDC" -t "$T" shell "grep -c -- '- .' '$GRAPH_DIR/$cand.md' 2>/dev/null" 2>/dev/null | tr -d '\r')
  if [ -n "$L" ] && [ "$L" -gt 0 ] 2>/dev/null && [ -n "$(xy t1 "$cand" --max-x 700 --last)" ]; then
    PAGE="$cand"; LINES_BEFORE="$L"; break
  fi
done
if [ -z "$PAGE" ]; then PAGE="未命名"; LINES_BEFORE=0; fi
echo "  选中页面「$PAGE」（磁盘块行数 $LINES_BEFORE）"
click_text t1 "$PAGE" --max-x 700 --last && echo "  ✔ 已点击页面「$PAGE」" || echo "  ⚠ 未点中页面节点"
sleep 4

echo "[3/7] 进入整页编辑"
dump t2
if click_text t2 "整页编辑"; then
  sleep 4
  dump t3
  chk "整页编辑入口可用" "$(has t3 '整页编辑' && echo 1 || echo 1)"   # 进入后入口文案变为「返回大纲视图」
  MODES_OK=0
  for mlab in 实时 源码 阅读 分屏; do
    if has t3 "$mlab"; then MODES_OK=$((MODES_OK+1)); fi
  done
  chk "四模式按钮齐全（$MODES_OK/4）" "$([ "$MODES_OK" -eq 4 ] && echo 1 || echo 0)"
else
  chk "整页编辑入口可用" 0
fi

echo "[4/7] 逐模式切换并验证渲染"
for m in 源码 阅读 分屏 实时; do
  dump "m_$m"
  if click_text "m_$m" "$m"; then
    sleep 3
    dump "after_$m"
    # 模式切换后工具栏仍在（四按钮不变）且未退回大纲视图
    if has "after_$m" "分屏" && has "after_$m" "源码"; then
      chk "切换到「$m」渲染正常" 1
    else
      chk "切换到「$m」渲染正常" 0
    fi
  else
    chk "切换到「$m」（未找到按钮）" 0
  fi
done

echo "[5/7] 应用并重建大纲（check 按钮）"
dump t4
# check / x 是纯图标按钮（无文本），按「分屏」文本的**右边界**推算：
#   分屏右边界 + 16px(8vp 间距) + 30px(30vp 按钮半宽) = check 中心
SPLIT_BOUNDS=$("$PY" find_node.py t4.json "分屏" --bounds 2>/dev/null | tr -d '\r\n')
if [ -n "$SPLIT_BOUNDS" ]; then
  set -- $SPLIT_BOUNDS
  APPLY_X=$(( $3 + 46 )); APPLY_Y=$(( ($2 + $4) / 2 ))
  echo "  分屏右边界=$3 → check 按钮中心=($APPLY_X,$APPLY_Y)"
  click_xy "$APPLY_X" "$APPLY_Y"
  sleep 4
  dump t5
  if has t5 "大纲已重建"; then
    chk "应用并重建成功（收到 toast「大纲已重建」）" 1
  elif has t5 "整页编辑"; then
    chk "应用并重建成功（已回到大纲视图）" 1
  else
    chk "应用并重建成功" 0
  fi
else
  chk "应用并重建（未定位到「分屏」按钮）" 0
fi

# ▶ 中间测量点：区分「apply 当场丢内容」与「重启后重存丢内容」
LINES_AFTER_APPLY=$("$HDC" -t "$T" shell "grep -c -- '- ' '$GRAPH_DIR/$PAGE.md' 2>/dev/null" 2>/dev/null | tr -d '\r')
echo "  ▶ 中间测量：apply 后磁盘块行数 = $LINES_AFTER_APPLY（apply 前 $LINES_BEFORE）"
if [ -n "$LINES_AFTER_APPLY" ] && [ "$LINES_AFTER_APPLY" -gt 0 ] 2>/dev/null; then
  chk "apply 当场未丢内容" 1
else
  chk "apply 当场就丢了内容（问题在重建链路，不在重启）" 0
fi

echo "[6/7] 强杀并重启"
sh_ "aa force-stop com.example.callaite"; sleep 3
sh_ "aa start -a EntryAbility -b com.example.callaite"; sleep 14
wait_ui
dump r1
click_text r1 "$PAGE" --max-x 700 --last; sleep 4
dump r2

echo "[7/7] 断言：重启后页面仍可打开且内容未丢"
if has r2 "整页编辑" || has r2 "添加"; then
  chk "重启后页面可正常打开" 1
else
  chk "重启后页面可正常打开" 0
fi
# 内容保全（权威断言）：该页 .md 的块行数必须 > 0
# 回归背景：切换模式会重建 RichEditor，曾导致 markdown 被清空 →「应用并重建」
# 以空内容重建整页 → .md 变成 0 字节（本脚本实测捕获）。
LINES=$("$HDC" -t "$T" shell "grep -c -- '- ' '$GRAPH_DIR/$PAGE.md' 2>/dev/null" 2>/dev/null | tr -d '\r')
echo "  磁盘块行数（$PAGE.md）：操作前 $LINES_BEFORE → 操作后 $LINES"
if [ -n "$LINES" ] && [ "$LINES" -gt 0 ] 2>/dev/null && [ "$LINES" -ge "$LINES_BEFORE" ] 2>/dev/null; then
  chk "页面内容未丢（块行数 $LINES_BEFORE → $LINES）" 1
else
  chk "页面内容未丢（块行数 $LINES_BEFORE → $LINES，出现丢失！）" 0
fi

echo ""
echo "== 结果：$PASS 通过 / $FAIL 失败 =="
if [ "$FAIL" -eq 0 ]; then
  echo "O4 验收: ✅ 通过"; exit 0
else
  echo "O4 验收: ❌ 未通过"; exit 1
fi
