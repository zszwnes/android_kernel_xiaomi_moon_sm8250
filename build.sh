#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
ALT_REPO="https://github.com/utziacre/android_kernel_xiaomi_pipa"
ALT_BRANCH="16-hyperos3"
ZIPNAME="Kernel_utz4_pipa_$(date +%Y%m%d).zip"
echo "===== ALT4 BUILD ====="
rm -rf alt error.log Image *.zip || true
git clone --depth 1 --single-branch -b "$ALT_BRANCH" "$ALT_REPO" alt
cd alt
: > .scmversion
echo "--- patch 1: vmscan shrinker_rwsem"
sed -i 's/^static DEFINE_RWLOCK(shrinker_rwlock);$/static DEFINE_RWLOCK(shrinker_rwlock);\nstatic DECLARE_RWSEM(shrinker_rwsem);/' mm/vmscan.c
grep -n 'DECLARE_RWSEM(shrinker_rwsem)' mm/vmscan.c || { echo "PATCH1 FAILED"; exit 1; }
echo "--- patch 2: usbpd.h include err.h"
sed -i '0,/#include <linux\/list.h>/s//#include <linux\/list.h>\n#include <linux\/err.h>/' include/linux/usb/usbpd.h
sed -n '8,13p' include/linux/usb/usbpd.h
grep -n 'linux/err.h' include/linux/usb/usbpd.h || { echo "PATCH2 FAILED"; exit 1; }
export KBUILD_BUILD_USER=zszwnes KBUILD_BUILD_HOST=gh
set +e
sudo apt-get update -qq >/dev/null 2>&1
sudo apt-get install -y -qq clang-14 lld-14 llvm-14 gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu >/dev/null 2>&1
set -e
CCBIN=clang; LDBIN=ld.lld
if command -v clang-14 >/dev/null 2>&1; then CCBIN=clang-14; LDBIN=ld.lld-14; fi
echo "--- using $CCBIN"; $CCBIN --version | head -2
MAKE_ARGS="ARCH=arm64 O=out CC=$CCBIN LD=$LDBIN LLVM_IAS=1 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- AR=llvm-ar-14 NM=llvm-nm-14 OBJCOPY=llvm-objcopy-14 OBJDUMP=llvm-objdump-14 STRIP=llvm-strip-14"
mkdir -p out
cp -f arch/arm64/configs/vendor/pipa_stock_defconfig out/.config
printf '%s\n' 'CONFIG_LITTLE_CPU_MASK=0' 'CONFIG_BIG_CPU_MASK=0' 'CONFIG_PRIME_CPU_MASK=0' 'CONFIG_MMU_NOTIFIER=y' '# CONFIG_CORESIGHT_ADRENO is not set' '# CONFIG_CORESIGHT is not set' >> out/.config
echo "--- olddefconfig"
make $MAKE_ARGS olddefconfig < /dev/null 2>&1 | tail -6
grep -E 'CONFIG_LOCALVERSION=|CONFIG_CLANG_VERSION|CONFIG_MMU_NOTIFIER|CONFIG_CORESIGHT' out/.config || true
cp -f out/.config "$SCRIPT_DIR/alt.config" || true
JOBS=$(nproc); echo "--- build JOBS=$JOBS"
set +e
make $MAKE_ARGS -j$JOBS 2>&1 | tee "$SCRIPT_DIR/error.log"
rc=$?
set -e
echo "===== MAKE RC=$rc"
cp -f out/.config "$SCRIPT_DIR/alt.config" 2>/dev/null || true
if [ "$rc" != "0" ]; then echo "BUILD FAILED"; exit 1; fi
cp -f out/arch/arm64/boot/Image "$SCRIPT_DIR/Image"
cp -f out/System.map "$SCRIPT_DIR/System.map" || true
cd "$SCRIPT_DIR"
zip -q -j "$ZIPNAME" Image alt.config
ls -l "$ZIPNAME" Image
echo "===== ALT4 BUILD OK"
