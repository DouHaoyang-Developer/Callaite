#!/bin/bash
# 本次计划改动（W1–W4 + P0 修复）的截图采样
#
# 采样清单：
#   CHG-01 侧栏-文件视图（W1：单图标列 + 面板加宽 + 顶部四 chip 视图切换器）
#   CHG-02 侧栏-标签视图（W1：视图切换生效）
#   CHG-03 设置页（W2 内容顶对齐 + W4 搜索设置框 + 导航分组标题）
#   CHG-04 设置-插件分类（W4 三段式：加粗标题 + 说明小字 + 右侧开关 + 行间细线）
#   CHG-05 所有页面（W3：行高 32vp + 顶部操作行）
#   CHG-06 PDF 空态（W4：刷新 / 导入 PDF 按钮）
#   CHG-07 图谱（P0：画布图元修复）
#   CHG-08 单日页（W3：Properties 属性区，无属性时整块隐藏属预期）
#   CHG-09 闪卡页（W4：开始复习主 CTA + 卡片统计；入口不确定，尽力而为）
#
# 用法：bash capture_changes.sh [连接键，默认 127.0.0.1:5555]
set -u
export MSYS2_ARG_CONV_EXCL='*'
export PYTHONIOENCODING=utf-8

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
PY="%USERPROFILE%/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
T="${1:-127.0.0.1:5555}"
WT=/f/DevEcoStudioProjects/uiwalk/tablet
OUT=/f/DevEcoStudioProjects/Callaite-工作文档/06-UI截图与改造计划/01-应用截图
DEV=/data/local/tmp

mkdir -p "$OUT"; cd "$WT" || exit 1
sh_() { "$HDC" -t "$T" shell "$1" >/dev/null 2>&1; }
xy() { "$PY" find_node.py "$1.json" "$2" "${@:3}" 2>/dev/null | tr -d '\r\n'; }
dump() { sh_ "uitest dumpLayout -p $DEV/$1.json"; "$HDC" -t "$T" file recv "$DEV/$1.json" "$1.json" >/dev/null 2>&1; }
shot() {  # ⚠️ hdc 会把 CWD 拼到本地路径前 → 必须 cd 后用裸文件名
  sh_ "snapshot_display -f $DEV/$1.jpeg"
  ( cd "$OUT" && "$HDC" -t "$T" file recv "$DEV/$1.jpeg" "$1.jpeg" >/dev/null 2>&1 )
  dump "$1_dump"; cp "$1_dump.json" "$OUT/$1_dump.json" 2>/dev/null
  echo "  ▸ $1"
}
click() { sh_ "uitest uiInput click $1 $2"; }
has() { grep -q "$2" "$1.json" 2>/dev/null; }
click_text() { local p; p=$(xy "$1" "$2" "${@:3}"); [ -z "$p" ] && return 1; click $p; return 0; }

echo "== 启动应用 =="
sh_ "aa start -a EntryAbility -b com.example.callaite"
for i in 1 2 3 4 5 6; do dump ready; has ready "搜索或开始搜索" && break; sleep 3; done
sleep 3

echo "== CHG-01/02 侧栏（W1）=="
shot "CHG-01-sidebar-files"
if click_text CHG-01-sidebar-files_dump "标签" --max-x 700; then
  sleep 3; shot "CHG-02-sidebar-tags"; click_text CHG-02-sidebar-tags_dump "文件" --max-x 700; sleep 2
else
  echo "  ⚠ 未定位「标签」chip"
fi

echo "== CHG-03/04 设置页（W2 顶对齐 + W4 搜索框/分组/三段式）=="
click 64 1817; sleep 6
shot "CHG-03-settings-top"
if click_text CHG-03-settings-top_dump "插件"; then
  sleep 4; shot "CHG-04-settings-plugins"
else
  echo "  ⚠ 未定位「插件」分类"
fi

echo "== CHG-05 所有页面（W3 行高 + 工具栏）=="
click 46 834; sleep 5; shot "CHG-05-allpages"

echo "== CHG-06 PDF 空态（W4 按钮）=="
click 46 922; sleep 5; shot "CHG-06-pdf-empty"

echo "== CHG-07 图谱（P0 修复）=="
click 46 306; sleep 6; shot "CHG-07-graph"

echo "== CHG-08 单日页（W3 Properties 区）=="
click 46 746; sleep 5
dump t1
for cand in "2026-09-25" "未命名 3" "未命名 2"; do
  if click_text t1 "$cand" --max-x 700 --last; then sleep 4; break; fi
done
shot "CHG-08-daypage"
has CHG-08-daypage_dump "属性" && echo "  ✔ 属性区可见" || echo "  · 属性区未显示（该页无属性，属预期）"

echo "== CHG-09 闪卡（W4 CTA）=="
click 46 482; sleep 5; shot "CHG-09-flashcards"
has CHG-09-flashcards_dump "开始复习" && echo "  ✔ 主 CTA 可见" || echo "  ⚠ 未出现「开始复习」（该入口可能不是闪卡页）"

echo ""
echo "== 采样结果 =="
ls -1 "$OUT"/CHG-*.jpeg 2>/dev/null | wc -l | tr -d ' ' | sed 's/^/  CHG 截图数: /'
ls -1 "$OUT" | grep '^CHG-' | sed 's/^/  /'
