#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Callaite 单设备运行验证脚本
#
# 用法：
#   bash verify_device.sh <设备实例名> <hdc端口> <输出目录名>
#   例：bash verify_device.sh phone 5555 phone
#
# 前置：模拟器已启动且 hdc 可连接；HAP 已构建。
# 产出：布局树 JSON、截图 PNG、hilog 文本，均落在 F:/DevEcoStudioProjects/verify/<输出目录名>/
# ---------------------------------------------------------------------------
set -u

export MSYSTEM=MINGW64
export PATH="%USERPROFILE%/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:%USERPROFILE%/.workbuddy/binaries/PortableGit/versions/1.2.0/bin:/usr/bin:/bin:$PATH"

HDC="D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
HAP_DIR="F:/DevEcoStudioProjects/Callaite/entry/build/default/outputs/default"
HAP_NAME="entry-default-unsigned.hap"
OUT_ROOT="F:/DevEcoStudioProjects/verify"

DEV_NAME="$1"
PORT="$2"
OUT="$3"
TARGET="127.0.0.1:${PORT}"
DIR="${OUT_ROOT}/${OUT}"
BUNDLE="com.example.callaite"

mkdir -p "$DIR"
cd "$DIR" || exit 1

echo "############ 设备 ${DEV_NAME} (${TARGET}) ############"

echo "--- [1/6] 设备信息"
"$HDC" -t "$TARGET" shell "param get const.product.devicetype; param get const.product.model; param get const.ohos.apiversion" 2>&1
"$HDC" -t "$TARGET" shell "hidumper -s DisplayManagerService -a '-a' 2>/dev/null | grep -iE 'width|height|density' | head -8" 2>&1

echo "--- [2/6] 卸载旧版本（确保冷启动）"
"$HDC" -t "$TARGET" uninstall "$BUNDLE" 2>&1 | head -2

echo "--- [3/6] 安装 HAP"
cd "$HAP_DIR" || exit 1
"$HDC" -t "$TARGET" install "$HAP_NAME" 2>&1 | head -3
cd "$DIR" || exit 1

echo "--- [4/6] 冷启动"
"$HDC" -t "$TARGET" shell "hilog -r" >/dev/null 2>&1
"$HDC" -t "$TARGET" shell "aa start -a EntryAbility -b ${BUNDLE}" 2>&1 | head -2
sleep 8

echo "--- [5/6] 运行状态"
PID=$("$HDC" -t "$TARGET" shell "pidof ${BUNDLE}" 2>&1 | tr -d '\r' | head -1)
echo "  PID = ${PID}"
"$HDC" -t "$TARGET" shell "aa dump -a" 2>&1 | grep -c "com.example.callaite" |
  xargs echo "  mission 记录数 ="

echo "--- [6/6] 采集产物"
"$HDC" -t "$TARGET" shell "uitest dumpLayout -p /data/local/tmp/${OUT}.json" 2>&1 | head -2
"$HDC" -t "$TARGET" file recv "/data/local/tmp/${OUT}.json" "${OUT}.json" 2>&1 | head -2

"$HDC" -t "$TARGET" shell "uitest screenCap -p /data/local/tmp/${OUT}.png" 2>&1 | head -2
"$HDC" -t "$TARGET" file recv "/data/local/tmp/${OUT}.png" "${OUT}.png" 2>&1 | head -2

# 抓 8 秒运行日志
timeout 10 "$HDC" -t "$TARGET" shell hilog > "${OUT}_hilog.txt" 2>&1
echo "  hilog 行数 = $(wc -l < "${OUT}_hilog.txt")"

echo "--- 应用进程 E/F 级日志"
grep -E " ${PID} +" "${OUT}_hilog.txt" 2>/dev/null | grep -E " E | F " | head -15
echo "--- JS 崩溃 / 卡死关键字"
grep -iE "jscrash|appfreeze|JsError|TypeError|Cannot read|SyntaxError" "${OUT}_hilog.txt" 2>/dev/null |
  grep -v "Settings\|SEARCH\|AOD" | head -10

echo "############ ${DEV_NAME} 采集完成 -> ${DIR} ############"
