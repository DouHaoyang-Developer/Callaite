#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Callaite — hvigor 命令行构建脚本（Windows / Git Bash）
#
# 用法：
#   bash build_callaite.sh            # 构建 debug HAP
#   bash build_callaite.sh release    # 构建 release HAP（含混淆）
#   bash build_callaite.sh clean      # 清理构建产物
#
# 说明：
#   WorkBuddy 的 bash shim 未注入 coreutils 与 Java，故在此脚本内显式补齐 PATH。
#   DEVECO_SDK_HOME 必须为 Windows 原生路径（正斜杠亦可），MSYS 路径会导致
#   hvigor 校验失败：Invalid value of 'DEVECO_SDK_HOME'。
# ---------------------------------------------------------------------------
set -u

export MSYSTEM=MINGW64
# 基础工具链（coreutils/sed/dirname 等，shim 默认未注入）
export PATH="/c/Users/DouHaoyang/.workbuddy/binaries/PortableGit/versions/1.2.0/usr/bin:/c/Users/DouHaoyang/.workbuddy/binaries/PortableGit/versions/1.2.0/bin:/usr/bin:/bin:$PATH"
# 关键：node 的 child_process.spawn 走 Windows 原生 PATH 解析，
# 这里必须用 POSIX 风格（/d/...）条目，MSYS 才会转换为 D:\...; 形式；
# 写成 D:/... 不会被转换，导致 PackageHap 阶段 spawn java ENOENT。
export PATH="/d/Program Files/Huawei/DevEco Studio/jbr/bin:/d/Program Files/Huawei/DevEco Studio/tools/node:$PATH"

DEV_ECO_HOME="D:/Program Files/Huawei/DevEco Studio"
export NODE_HOME="${DEV_ECO_HOME}/tools/node"
export JAVA_HOME="${DEV_ECO_HOME}/jbr"
# hvigor 用 existsSync 校验，必须是 Windows 原生路径
export DEVECO_SDK_HOME="${DEV_ECO_HOME}/sdk"

BUILD_MODE="${1:-debug}"
PROJECT_DIR="F:/DevEcoStudioProjects/Callaite"
HVIGOR_JS="${DEV_ECO_HOME}/tools/hvigor/bin/hvigorw.js"

echo "=== 环境 ==="
echo "NODE_HOME        = ${NODE_HOME}"
echo "JAVA_HOME        = ${JAVA_HOME}"
echo "DEVECO_SDK_HOME  = ${DEVECO_SDK_HOME}"
echo "BUILD_MODE       = ${BUILD_MODE}"
"${NODE_HOME}/node.exe" -v
"${JAVA_HOME}/bin/java.exe" -version 2>&1 | head -1
echo ""

cd "${PROJECT_DIR}" || exit 1

if [ "${BUILD_MODE}" = "clean" ]; then
  "${NODE_HOME}/node.exe" "${HVIGOR_JS}" --mode module clean --no-daemon
  exit $?
fi

echo "=== 构建开始 $(date '+%F %T') ==="
"${NODE_HOME}/node.exe" "${HVIGOR_JS}" \
  --mode module \
  -p product=default \
  -p buildMode="${BUILD_MODE}" \
  assembleHap \
  --no-daemon
RC=$?
echo "=== 构建结束 $(date '+%F %T')，退出码 ${RC} ==="
if [ "${RC}" -ne 0 ]; then
  exit ${RC}
fi

# ---------------------------------------------------------------------------
# T3（优化方案 v2 §七）：本地单元测试门禁 —— 测试失败即构建失败。
# 覆盖 Markdown 往返不变式、BlockTree/Validator 操作与循环引用负例等纯逻辑。
# 可用 SKIP_TEST=1 跳过（仅限本地临时调试，提交/发版前必须跑）。
# ---------------------------------------------------------------------------
if [ "${SKIP_TEST:-0}" = "1" ]; then
  echo "=== 已跳过单元测试（SKIP_TEST=1）==="
  exit 0
fi

echo "=== 单元测试开始 $(date '+%F %T') ==="
"${NODE_HOME}/node.exe" "${HVIGOR_JS}" \
  --mode module \
  -p product=default \
  test \
  --no-daemon
TEST_RC=$?
echo "=== 单元测试结束 $(date '+%F %T')，退出码 ${TEST_RC} ==="
exit ${TEST_RC}
