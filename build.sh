#!/bin/bash

set -eo pipefail

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

function msg() {
    echo -e "${GREEN}[INFO]${NC} $1"
    if [ -n "$2" ]; then echo -e "${GREEN}[INFO]${NC} $2"; fi
}
function warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    if [ -n "$2" ]; then echo -e "${YELLOW}[WARN]${NC} $2"; fi
}
function err() {
    echo -e "${RED}[ERROR]${NC} $1"
    if [ -n "$2" ]; then echo -e "${RED}[ERROR]${NC} $2"; fi
}

msg '检查所需依赖项 / Checking required dependencies...'
for dep in git curl zip make; do
    if ! command -v "$dep" &> /dev/null; then
        err "未找到所需命令 '$dep'，请先安装" \
           "Required command '$dep' is not installed. Please install it first."
        exit 1
    fi
done

if ! command -v "${CC:-clang}" &> /dev/null; then
    err "未找到编译器 '${CC:-clang}'，请检查环境" \
       "Compiler '${CC:-clang}' not found. Please check your environment."
    exit 1
fi

RESOURCE_DIR="$(${CC:-clang} --print-resource-dir)"
TOOLCHAIN_PATH="$(dirname "$(dirname "$(dirname "$RESOURCE_DIR")")")"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD)
else
    warn "不是 git 仓库，COMMIT_ID 设为 'unknown'" \
         "Not a git repository. Setting COMMIT_ID to 'unknown'."
    GIT_COMMIT_ID="unknown"
fi

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    err "工具链路径 [$TOOLCHAIN_PATH] 不存在，请确保工具链位于该路径，或在脚本中修改 TOOLCHAIN_PATH" \
       "TOOLCHAIN_PATH [$TOOLCHAIN_PATH] does not exist. Please ensure the toolchain is at this path, or modify TOOLCHAIN_PATH in the script."
    exit 1
fi

msg "工具链路径 / TOOLCHAIN_PATH: [$TOOLCHAIN_PATH]"
export PATH="$TOOLCHAIN_PATH:$PATH"

MAKE_ARGS='ARCH=arm64 O=out CC=clang LLVM=1 LLVM_IAS=1 LD=ld.lld CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_COMPAT=arm-linux-androideabi- AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip'
export KBUILD_OUTPUT=out

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SSL_INCLUDE="$SCRIPT_DIR/../.build-deps/ssl-usr/include"
LOCAL_SSL_ARCH_INCLUDE="$SCRIPT_DIR/../.build-deps/ssl-usr/include/x86_64-linux-gnu"
if [ ! -f /usr/include/openssl/bio.h ]; then
    if [ -f "$LOCAL_SSL_INCLUDE/openssl/bio.h" ]; then
        warn "未找到系统 openssl 头文件，使用本地副本 [$LOCAL_SSL_INCLUDE]" \
             "System openssl headers not found. Using local copy at [$LOCAL_SSL_INCLUDE]."
        export HOSTCFLAGS="-I$LOCAL_SSL_INCLUDE -I$LOCAL_SSL_ARCH_INCLUDE"
    else
        err "未找到 OpenSSL 头文件，请安装 libssl-dev 或将头文件放入 .build-deps/ssl-usr" \
           "OpenSSL headers not found. Install libssl-dev or place headers under .build-deps/ssl-usr."
        exit 1
    fi
fi

msg '检查 Clang 版本 / Checking Clang version:'
clang --version

export KBUILD_BUILD_USER='github'
export KBUILD_BUILD_HOST='bcggxx'
export KBUILD_LAST_COMMIT=${GIT_COMMIT_ID}

msg '清理上次构建的残留文件（强制清理） / Performing cleanup of previous build files (Forced Clean)...'
rm -rf out/
rm -f error.log
rm -f .config
rm -rf include/config
mkdir -p out/

msg '执行 mrproper 清理源树 / Running mrproper to clean the source tree...'
make ARCH=arm64 mrproper

msg '准备 AnyKernel3 / Preparing AnyKernel3...'
if [ -d 'anykernel/.git' ]; then
    msg 'AnyKernel3 已克隆，跳过克隆 / AnyKernel3 already cloned. Skipping clone.'
    rm -rf anykernel/kernels/*
else
    rm -rf anykernel
    msg '为 pipa 克隆 AnyKernel3 / Cloning AnyKernel3 for pipa...'
    git clone https://github.com/bcggxx/AnyKernel3 -b n0-A16 --single-branch --depth=1 anykernel
fi

msg '为 PIPA 配置 (pipa_user_defconfig) / Configuring for PIPA (pipa_user_defconfig)...'
unset BRANCH KMI_GENERATION
echo '-gc80e50029' > "$SCRIPT_DIR/.scmversion"
make $MAKE_ARGS pipa_user_defconfig
cat arch/arm64/configs/xiaomi.config >> out/.config
printf "%s\\n" CONFIG_PANIC_ON_OOPS=y CONFIG_PANIC_TIMEOUT=0 CONFIG_LOCKUP_DETECTOR=y CONFIG_HARDLOCKUP_DETECTOR=y CONFIG_BOOTPARAM_HARDLOCKUP_PANIC=y CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC=y CONFIG_DETECT_HUNG_TASK=y CONFIG_BOOTPARAM_HUNG_TASK_PANIC=y CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=60 CONFIG_WQ_WATCHDOG=y CONFIG_PSTORE_CONSOLE=y CONFIG_PSTORE_PMSG=y CONFIG_PANIC_ON_WARN=y >> out/.config   # FIX(full-xiaomi-fragment-user-defconfig)
# 'yes' may get SIGPIPE and exit non-zero when the reader finishes early.
# With 'set -o pipefail' that would abort the script — ignore the pipeline
# exit status to avoid failing the whole build step on benign Broken pipe.
printf '%s\n' CONFIG_DEBUG_KERNEL=y CONFIG_LOCKUP_DETECTOR=y CONFIG_SOFTLOCKUP_DETECTOR=y CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC=y CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=45 >> out/.config
printf '%s\n' CONFIG_PANIC_TIMEOUT=5 >> out/.config
yes '' | make $MAKE_ARGS olddefconfig || true

msg '检查源树残留配置 / Checking for source tree config artifacts...'
if [ -f .config ] || [ -d include/config ]; then
    warn '检测到源树残留 .config 或 include/config，将清理它们以避免 prepare3 失败'
    rm -f .config
    rm -rf include/config
fi

if [ -z "${JOBS:-}" ]; then
    MEM_AVAIL_KB=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
    SWAP_FREE_KB=$(awk '/SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
    MEM_BASED_JOBS=$(( (MEM_AVAIL_KB + SWAP_FREE_KB) / 1500000 ))
    [ "$MEM_BASED_JOBS" -lt 1 ] && MEM_BASED_JOBS=1
    CPU_JOBS=$(nproc --all)
    if [ "$MEM_BASED_JOBS" -lt "$CPU_JOBS" ]; then
        JOBS=$MEM_BASED_JOBS
        warn "内存不足：并行度限制为 -j${JOBS}（cpus=${CPU_JOBS}，可用≈$((MEM_AVAIL_KB/1024))MB），可用 JOBS=<n> 覆盖" \
             "Low memory: capping parallelism to -j${JOBS} (cpus=${CPU_JOBS}, avail≈$((MEM_AVAIL_KB/1024))MB). Override with JOBS=<n>."
    else
        JOBS=$CPU_JOBS
    fi
fi
msg "使用 -j${JOBS} 编译 / Building with -j${JOBS}"

msg '开始为 PIPA 编译内核 / Starting Kernel Build for PIPA...'
BUILD_START=$(date +"%s")
set +e
make $MAKE_ARGS -j"${JOBS}" 2>&1 | tee error.log
MAKE_EXIT_CODE=${PIPESTATUS[0]}
set -e
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))

if [ "$MAKE_EXIT_CODE" -ne 0 ]; then
    err "内核编译失败，退出码 $MAKE_EXIT_CODE" \
       "Kernel build failed with exit code $MAKE_EXIT_CODE!"
    err '请查看 error.log 获取详细失败原因 / Check error.log for detailed failure reasons.'
    exit 1
fi

if [ ! -f 'out/arch/arm64/boot/Image' ]; then
    err '文件 [out/arch/arm64/boot/Image] 不存在，构建失败' \
       'The file [out/arch/arm64/boot/Image] does not exist. Build failed!'
    err '请查看 error.log 获取详细失败原因 / Check error.log for detailed failure reasons.'
    exit 1
fi

msg "内核编译成功，耗时 $((DIFF / 60)) 分 $((DIFF % 60)) 秒"
msg '使用 AnyKernel3 打包 / Packaging with AnyKernel3...'
cp out/arch/arm64/boot/Image anykernel/ || { err '拷贝 Image 失败 / Failed to copy Image.'; exit 1; }

if [ -f 'out/arch/arm64/boot/dtb' ]; then
    cp out/arch/arm64/boot/dtb anykernel/ || { err '拷贝 dtb 失败 / Failed to copy dtb.'; exit 1; }
else
    warn '未找到 dtb，跳过 / dtb not found, skipping.'
fi

if [ -f 'out/arch/arm64/boot/dtbo.img' ]; then
    cp out/arch/arm64/boot/dtbo.img anykernel/ || { err '拷贝 dtbo.img 失败 / Failed to copy dtbo.img.'; exit 1; }
else
    warn '未找到 dtbo.img，跳过 / dtbo.img not found, skipping.'
fi

cp -f out/System.map out/.config anykernel/ 2>/dev/null || true
cd anykernel || { err '进入 anykernel 目录失败 / Failed to enter anykernel directory.'; exit 1; }

timestamp=$(date +%Y%m%d)
ZIP_FILENAME="Kernel_N0_pipa_A16_AOSP_MIUI_${timestamp}.zip"

if zip -r9 "$ZIP_FILENAME" ./* -x "*.git*" "*out*" "*.zip" > /dev/null; then
    mv "$ZIP_FILENAME" ../
else
    err '创建刷机 zip 失败 / Failed to create flashable zip.'
    exit 1
fi

cd ..

msg 'PIPA 构建完成 / Build for PIPA finished.'
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}完成！刷机包位于: ./$ZIP_FILENAME${NC}"
echo -e "${GREEN}Done! The flashable zip is: ./$ZIP_FILENAME${NC}"
echo -e "${GREEN}=====================================================${NC}"
