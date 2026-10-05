#!/bin/bash
# UI 截图补采（第二轮）：设置页全部二级分区 + 整页编辑器「阅读」模式
#
# 背景：首轮采集有两处缺口
#   ① 编辑器「阅读」模式拍错——按文本「阅读」查找时**子串命中了标签栏的「PDF 阅读」**
#      → 本次限定 x 范围到编辑器工具栏（设备 px ≥ 2000）避开标签栏
#   ② 设置页只采到「外观与语言」→ 本次逐个进入全部导航项
#
# 用法：bash capture_ui_screens_2.sh [连接键，默认 127.0.0.1:5555]
set -u
export MSYS2_ARG_CONV_EXCL='*'
export PYTHONIOENCODING=utf-8

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
PY="C:/Users/DouHaoyang/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
T="${1:-127.0.0.1:5555}"
WT=/f/DevEcoStudioProjects/uiwalk/tablet
OUT=/f/DevEcoStudioProjects/Callaite-工作文档/06-UI截图与改造计划/01-应用截图
DEV=/data/local/tmp
SETTINGS_X=135; SETTINGS_Y=1810          # 活动栏底部「设置」图标
NAV_MIN_X=610; NAV_MAX_X=930             # 设置页左侧导航面板（dump 实测 [620,382] 300×1430px）
TOOLBAR_MIN_X=2000                       # 编辑器模式 chip 所在工具栏（避开标签栏「PDF 阅读」）

mkdir -p "$OUT"
cd "$WT" || exit 1

sh_() { "$HDC" -t "$T" shell "$1" >/dev/null 2>&1; }
click() { sh_ "uitest uiInput click $1 $2"; }
xy() { "$PY" find_node.py "$1.json" "$2" "${@:3}" 2>/dev/null | tr -d '\r\n'; }
dump() { sh_ "uitest dumpLayout -p $DEV/$1.json"; "$HDC" -t "$T" file recv "$DEV/$1.json" "$1.json" >/dev/null 2>&1; }
shot() {  # ⚠️ hdc 会把 CWD 拼到本地路径前 → 必须 cd 后用裸文件名
  sh_ "snapshot_display -f $DEV/$1.jpeg"
  ( cd "$OUT" && "$HDC" -t "$T" file recv "$DEV/$1.jpeg" "$1.jpeg" >/dev/null 2>&1 )
  dump "$1_dump"; cp "$1_dump.json" "$OUT/$1_dump.json" 2>/dev/null
  echo "  ▸ $1"
}
wait_ui() {
  local i
  for i in 1 2 3 4 5 6 7 8; do
    dump ready
    if grep -q "搜索或开始搜索" ready.json 2>/dev/null; then return 0; fi
    sleep 3
  done
  return 1
}

echo "== 启动应用 =="
sh_ "aa start -a EntryAbility -b com.example.callaite"
wait_ui && echo "  ✔ 界面就绪"
sleep 3

echo ""
echo "== A. 设置页全部二级分区 =="
click $SETTINGS_X $SETTINGS_Y; sleep 5
dump nav
# 导航项清单（来自首轮 dump 实测：设置 / 外观与语言 / 编辑器 / 快捷键 / 同步 / 账户 / 插件）
ITEMS="外观与语言 编辑器 快捷键 同步 账户 插件"
i=0
for item in $ITEMS; do
  i=$((i+1))
  pos=$(xy nav "$item" --min-x $NAV_MIN_X --max-x $NAV_MAX_X)
  if [ -z "$pos" ]; then
    # 重新 dump：上一项进入后导航可能重排
    dump nav
    pos=$(xy nav "$item" --min-x $NAV_MIN_X --max-x $NAV_MAX_X)
  fi
  if [ -n "$pos" ]; then
    click $pos; sleep 4
    shot "7${i}-Settings-${item}"
    dump nav   # 为下一项刷新坐标
  else
    echo "  ⚠ 未定位到设置项「$item」"
  fi
done

echo ""
echo "== B. 整页编辑器「阅读」模式（限定工具栏 x 范围，避开「PDF 阅读」标签）=="
click $SETTINGS_X $SETTINGS_Y; sleep 3    # 先离开设置
# 打开一个有内容的页面
dump t0
PAGE=""
for cand in "未命名 2" "未命名 3" "未命名" "Home"; do
  if [ -n "$(xy t0 "$cand" --max-x 700 --last)" ]; then PAGE="$cand"; break; fi
done
echo "  选中页面：${PAGE:-（未找到，用当前页）}"
[ -n "$PAGE" ] && { pos=$(xy t0 "$PAGE" --max-x 700 --last); click $pos; sleep 5; }
shot "80b-DayPage-recheck"

dump t1
pos=$(xy t1 "整页编辑")
if [ -n "$pos" ]; then
  click $pos; sleep 5
  for m in 阅读:92-Integral-preview-FIXED 源码:91b-Integral-source-FIXED 分屏:93b-Integral-split-FIXED 实时:90b-Integral-live-FIXED; do
    lab="${m%%:*}"; out="${m##*:}"
    dump mm
    p2=$(xy mm "$lab" --min-x $TOOLBAR_MIN_X)
    if [ -n "$p2" ]; then click $p2; sleep 4; shot "$out"; else echo "  ⚠ 未定位模式「$lab」"; fi
  done
  dump t2; p3=$(xy t2 "返回大纲视图"); [ -n "$p3" ] && { click $p3; sleep 3; }
else
  echo "  ⚠ 未找到「整页编辑」入口"
fi

echo ""
echo "== 补采结果 =="
ls -1 "$OUT"/*.jpeg | wc -l | tr -d ' ' | sed 's/^/  累计 jpeg 总数: /'
