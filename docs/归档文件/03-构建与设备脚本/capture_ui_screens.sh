#!/bin/bash
# UI 截图采集：在模拟器上遍历应用全部页面并截图（供与 Obsidian 参考图对比）
#
# 用法：bash capture_ui_screens.sh [连接键，默认 127.0.0.1:5555]
# 输出：F:\DevEcoStudioProjects\Callaite-工作文档\06-UI截图与改造计划\01-应用截图\*.jpeg
#      同名 .json 布局 dump 便于结构核对
set -u
export MSYS2_ARG_CONV_EXCL='*'
export PYTHONIOENCODING=utf-8

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
PY="C:/Users/DouHaoyang/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
T="${1:-127.0.0.1:5555}"
WT=/f/DevEcoStudioProjects/uiwalk/tablet
OUT=/f/DevEcoStudioProjects/Callaite-工作文档/06-UI截图与改造计划/01-应用截图
# ⚠️ MSYS2_ARG_CONV_EXCL='*' 会同时关闭**本地路径**转换，file recv 的本地目标必须是
#    Windows 原生路径（否则 hdc 会往字面量 /f/... 写，静默失败）
OUT_WIN='F:/DevEcoStudioProjects/Callaite-工作文档/06-UI截图与改造计划/01-应用截图'
DEV=/data/local/tmp

mkdir -p "$OUT"
cd "$WT" || exit 1

sh_() { "$HDC" -t "$T" shell "$1" >/dev/null 2>&1; }
xy() { "$PY" find_node.py "$1.json" "$2" "${@:3}" 2>/dev/null | tr -d '\r\n'; }
dump() {
  sh_ "uitest dumpLayout -p $DEV/$1.json"
  "$HDC" -t "$T" file recv "$DEV/$1.json" "$1.json" >/dev/null 2>&1
}
shot() {  # shot <输出名> [dump名]
  sh_ "snapshot_display -f $DEV/$1.jpeg"
  # ⚠️ hdc 会把**当前工作目录**拼到本地路径前（实测报错 path:F:\...\F:/...），
  #    因此必须传相对路径：先 cd 到输出目录再用裸文件名。
  ( cd "$OUT" && "$HDC" -t "$T" file recv "$DEV/$1.jpeg" "$1.jpeg" >/dev/null 2>&1 )
  if [ -n "${2:-}" ]; then
    dump "$2"
    cp "$WT/$2.json" "$OUT/$2.json" 2>/dev/null
  fi
  echo "  ▸ $1"
}
click() { sh_ "uitest uiInput click $1 $2"; }

echo "== 启动应用 =="
sh_ "aa start -a EntryAbility -b com.example.callaite"
for i in 1 2 3 4 5 6 7 8; do
  dump ready
  if grep -q "搜索或开始搜索" ready.json 2>/dev/null; then break; fi
  sleep 3
done
sleep 3

echo "== 活动栏坐标确认（动态解析，避免写死）=="
dump nav0
# 活动栏 = LeftSidebar 的 44vp 图标条（x 约 99..171）；图标按 y 递增
echo "  参考：Ribbon 在 x≈6..86，活动栏在 x≈99..171"

echo "== 逐页采集 =="
# 活动栏图标顺序：新建(132) / Journal(208) / AllPages(284) / Graph(360) / Flashcards(436) / Whiteboards(512) / Pdf(588)
# 底部：收藏(1658) / 仓库(1734) / 设置(1810)
declare -a PAGES=(
  "10-Journal:135:208"
  "20-AllPages:135:284"
  "30-Graph:135:360"
  "40-Flashcards:135:436"
  "50-Whiteboards:135:512"
  "60-Pdf:135:588"
  "70-Settings:135:1810"
)
for p in "${PAGES[@]}"; do
  name="${p%%:*}"; rest="${p#*:}"; x="${rest%%:*}"; y="${rest##*:}"
  click "$x" "$y"
  sleep 5
  shot "$name" "${name}_dump"
done

echo "== 单日页（点击树中第一个有内容的页面）=="
click 135 208; sleep 4          # 回 Journal
dump t1
for cand in "未命名 2" "未命名 3" "未命名"; do
  pos=$(xy t1 "$cand" --max-x 700 --last)
  if [ -n "$pos" ]; then click $pos; sleep 5; break; fi
done
shot "80-DayPage" "80-DayPage_dump"

echo "== 整页编辑器四模式 =="
dump t2
pos=$(xy t2 "整页编辑")
if [ -n "$pos" ]; then
  click $pos; sleep 5
  shot "90-Integral-live" "90-Integral-live_dump"
  for m in 源码:91-Integral-source 阅读:92-Integral-preview 分屏:93-Integral-split; do
    lab="${m%%:*}"; out="${m##*:}"
    sleep 3; dump mm
    p2=$(xy mm "$lab")
    if [ -n "$p2" ]; then click $p2; sleep 4; shot "$out" "${out}_dump"; fi
  done
  # 退出（返回大纲视图），避免影响后续
  dump t3
  p3=$(xy t3 "返回大纲视图")
  [ -n "$p3" ] && { click $p3; sleep 3; }
else
  echo "  ⚠ 未找到「整页编辑」入口"
fi

echo "== 设置页二级：回收站 / 关于（尽力而为）=="
click 135 1810; sleep 5
dump s1
for item in 回收站:94-Recycle 关于:95-About; do
  lab="${item%%:*}"; out="${item##*:}"
  dump ss
  p4=$(xy ss "$lab" --min-x 700)
  if [ -n "$p4" ]; then click $p4; sleep 5; shot "$out" "${out}_dump"; click 135 1810; sleep 4; else echo "  ⚠ 未找到入口「$lab」"; fi
done

echo ""
echo "== 采集结果 =="
ls -1 "$OUT"/*.jpeg 2>/dev/null | wc -l | tr -d ' ' | sed 's/^/  jpeg 数量: /'
ls -1 "$OUT" | sed 's/^/  /'
