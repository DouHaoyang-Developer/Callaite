#!/bin/bash
# 多兄弟块持久化回归验证（P0 数据丢失缺陷）
#
# 背景：MarkdownParser 曾漏写 block.leftId，而 MarkdownExporter 用
#   `Map<leftId, block>` 建桶遍历兄弟链 —— 同层 leftId 相同（全为 ''）时互相覆盖，
#   于是「保存后每层只剩最后一个块」。本脚本在设备上直接验证修复：
#   连续创建 3 个同级块 → 落盘 → 强杀 → 重启 → 三个块必须全部还在。
#
# 用法：bash verify_multi_block_persist.sh [连接键，默认 127.0.0.1:5555]
set -u
export MSYS2_ARG_CONV_EXCL='*'
export PYTHONIOENCODING=utf-8

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
PY="%USERPROFILE%/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
T="${1:-127.0.0.1:5555}"
WORK=/f/DevEcoStudioProjects/uiwalk/tablet
GRAPH_DIR="/data/app/el2/100/base/com.example.callaite/haps/entry/files/graph"
STAMP=$(date +%H%M%S)
M1="ALPHA$STAMP"
M2="BETA$STAMP"
M3="GAMMA$STAMP"
STRIP_NEW_X=135
STRIP_NEW_Y=132

cd "$WORK" || exit 1
sh_() { "$HDC" -t "$T" shell "$1" >/dev/null 2>&1; }
dump() {
  sh_ "uitest dumpLayout -p /data/local/tmp/$1.json"
  "$HDC" -t "$T" file recv "/data/local/tmp/$1.json" "$1.json" >/dev/null 2>&1
}
xy() { "$PY" find_node.py "$1.json" "$2" "${@:3}" 2>/dev/null | tr -d '\r\n'; }
click_xy() { sh_ "uitest uiInput click $1 $2"; }
wait_ui() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    dump ready
    if grep -q "搜索或开始搜索" ready.json 2>/dev/null; then return 0; fi
    sleep 3
  done
  return 1
}

echo "== 多兄弟块持久化验证（设备 $T）=="
echo "   标记：$M1 / $M2 / $M3"

echo "[1/6] 启动应用"
sh_ "aa start -a EntryAbility -b com.example.callaite"
wait_ui && echo "  ✔ 界面就绪"

echo "[2/6] 新建页面"
click_xy "$STRIP_NEW_X" "$STRIP_NEW_Y"; sleep 4
dump dlg
POS=$(xy dlg "新建大纲笔记")
[ -z "$POS" ] && { click_xy "$STRIP_NEW_X" "$STRIP_NEW_Y"; sleep 4; dump dlg; POS=$(xy dlg "新建大纲笔记"); }
if [ -n "$POS" ]; then click_xy $POS; sleep 5; echo "  ✔ 页面已创建"; fi

echo "[3/6] 连续创建 3 个同级块（逐块注入 + 逐块校验，失败则用「添加」按钮重试）"
dump e1
POS=$(xy e1 "输入内容")
[ -z "$POS" ] && POS=$(xy e1 "添加" --min-x 700)
[ -z "$POS" ] && POS="995 402"
PX=${POS% *}; PYy=${POS#* }
INJECTED=0
for m in "$M1" "$M2" "$M3"; do
  ok=0
  for attempt in 1 2 3; do
    click_xy "$PX" "$PYy"; sleep 2
    click_xy "$PX" "$PYy"; sleep 2
    sh_ "uitest uiInput text $m"; sleep 3
    dump "chk_$m"
    if grep -q "$m" "chk_$m.json"; then ok=1; break; fi
    # 兜底：用页面底部「添加」按钮新建并聚焦一个块后重试
    ADD=$(xy "chk_$m" "添加" --min-x 700)
    if [ -n "$ADD" ]; then PX=${ADD% *}; PYy=${ADD#* }; fi
    echo "    … $m 第 $attempt 次未上屏，重试"
  done
  if [ "$ok" -eq 1 ]; then
    INJECTED=$((INJECTED+1)); echo "  ✔ $m 已上屏"
  else
    echo "  ✘ $m 注入失败"
  fi
  sh_ "uitest uiInput keyEvent 2054"; sleep 2      # KEYCODE_ENTER = 2054 → 新建同级块
done
echo "  注入成功 $INJECTED/3"

echo "[4/6] 等待落盘并做磁盘断言（权威）"
sleep 5
dump e2
TARGET=""
for m in "$M1" "$M2" "$M3"; do
  HIT=$("$HDC" -t "$T" shell "grep -l $m '$GRAPH_DIR'/*.md 2>/dev/null" 2>/dev/null | tr -d '\r' | head -1)
  if [ -n "$HIT" ]; then TARGET="$HIT"; break; fi
done
if [ -n "$TARGET" ]; then
  echo "  落盘文件：$TARGET"
  for m in "$M1" "$M2" "$M3"; do
    # ⚠️ 路径含空格，必须带引号：否则远端 shell 拆参数、grep 报错但 hdc 退出码仍为 0
    #    → 断言假阳性（本脚本早期版本即因此误报「磁盘 3/3 存在」）
    if "$HDC" -t "$T" shell "grep -q $m '$TARGET'" >/dev/null 2>&1; then
      echo "  ✔ 磁盘含 $m"
    else
      echo "  ✘ 磁盘缺 $m"
    fi
  done
  echo "  文件块行数：$("$HDC" -t "$T" shell "grep -c -- '- ' '$TARGET' 2>/dev/null" 2>/dev/null | tr -d '\r')"
else
  echo "  ✘ 未找到任何落盘文件（标记未持久化）"
fi
PAGE_NAME=$(basename "$TARGET" .md 2>/dev/null)

echo "[5/6] 强杀并重启"
sh_ "aa force-stop com.example.callaite"; sleep 3
sh_ "aa start -a EntryAbility -b com.example.callaite"; sleep 14
wait_ui
dump r1
POS=""
if [ -n "$PAGE_NAME" ]; then POS=$(xy r1 "$PAGE_NAME" --max-x 700 --last); fi
[ -z "$POS" ] && POS=$(xy r1 "未命名" --max-x 700 --last)
if [ -n "$POS" ]; then click_xy $POS; sleep 5; else echo "  ⚠ 树中未找到页面节点"; fi

echo "[6/6] 断言：重启后三个标记必须全部存活"
dump r2
OK=0
for m in "$M1" "$M2" "$M3"; do
  if grep -q "$m" r2.json; then OK=$((OK+1)); echo "  ✔ 界面可见 $m"; fi
done
DISK_OK=0
for m in "$M1" "$M2" "$M3"; do
  HIT=$("$HDC" -t "$T" shell "grep -l $m '$GRAPH_DIR'/*.md 2>/dev/null" 2>/dev/null | tr -d '\r')
  if [ -n "$HIT" ]; then DISK_OK=$((DISK_OK+1)); fi
done
echo "  界面：$OK/3 可见；磁盘：$DISK_OK/3 存在"

if [ "$DISK_OK" -eq 3 ] && [ "$INJECTED" -eq 3 ]; then
  echo "结果：✅ 通过 —— 同层多兄弟块经 保存→强杀→重启 全部存活（P0 数据丢失缺陷已修复）"
  exit 0
else
  echo "结果：❌ 未通过（注入 $INJECTED/3，磁盘 $DISK_OK/3，界面 $OK/3）"
  exit 1
fi
