#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
ALT_REPO="https://github.com/utziacre/android_kernel_xiaomi_pipa"
ALT_BRANCH="16-hyperos3"
ZIPNAME="Kernel_utz2_pipa_$(date +%Y%m%d).zip"
echo "===== ALT2 BUILD $ALT_REPO @ $ALT_BRANCH ====="
rm -rf alt error.log Image *.zip || true
git clone --depth 1 --single-branch -b "$ALT_BRANCH" "$ALT_REPO" alt
cd alt
: > .scmversion
export KBUILD_BUILD_USER=zszwnes KBUILD_BUILD_HOST=gh
echo "--- install toolchain"
set +e
sudo apt-get update -qq >/dev/null 2>&1
sudo apt-get install -y -qq clang-14 lld-14 llvm-14 gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu >/dev/null 2>&1
set -e
CCBIN=clang; LDBIN=ld.lld
if command -v clang-14 >/dev/null 2>&1; then CCBIN=clang-14; LDBIN=ld.lld-14; fi
echo "--- using $CCBIN"; $CCBIN --version | head -2; $LDBIN --version | head -1
MAKE_ARGS="ARCH=arm64 O=out CC=$CCBIN LD=$LDBIN LLVM_IAS=1 CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- AR=llvm-ar-14 NM=llvm-nm-14 OBJCOPY=llvm-objcopy-14 OBJDUMP=llvm-objdump-14 STRIP=llvm-strip-14"
mkdir -p out
cp -f arch/arm64/configs/vendor/pipa_stock_defconfig out/.config
printf '%s\n' 'CONFIG_LITTLE_CPU_MASK=0' 'CONFIG_BIG_CPU_MASK=0' 'CONFIG_PRIME_CPU_MASK=0' >> out/.config
echo "--- olddefconfig"
make $MAKE_ARGS olddefconfig < /dev/null 2>&1 | tail -8
grep -E 'CONFIG_LITTLE_CPU_MASK|CONFIG_BIG_CPU_MASK|CONFIG_PRIME_CPU_MASK|CONFIG_LOCALVERSION|CONFIG_CLANG_VERSION|CONFIG_MODVERSIONS|CONFIG_KSU' out/.config || true
JOBS=$(nproc); echo "--- build JOBS=$JOBS"
set +e
make $MAKE_ARGS -j$JOBS 2>&1 | tee "$SCRIPT_DIR/error.log"
rc=$?
set -e
echo "===== MAKE RC=$rc"
if [ "$rc" != "0" ]; then echo "BUILD FAILED"; ls -l out/arch/arm64/boot/ 2>/dev/null || true; exit 1; fi
cp -f out/arch/arm64/boot/Image "$SCRIPT_DIR/Image"
cp -f out/.config "$SCRIPT_DIR/alt.config" || true
cp -f out/System.map "$SCRIPT_DIR/System.map" || true
cd "$SCRIPT_DIR"
zip -q -j "$ZIPNAME" Image
ls -l "$ZIPNAME" Image
echo "===== ALT2 BUILD OK"
