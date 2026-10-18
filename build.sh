#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
MAKE_ARGS="ARCH=arm64 O=out CC=clang LLVM=1 LLVM_IAS=1 LD=ld.lld CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_COMPAT=arm-linux-androideabi- AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip"
export KBUILD_BUILD_USER=zszwnes KBUILD_BUILD_HOST=gh
ALT_REPO="https://github.com/utziacre/android_kernel_xiaomi_pipa"
ALT_BRANCH="16-hyperos3"
ZIPNAME="Kernel_utz_pipa_$(date +%Y%m%d).zip"
echo "===== ALT BUILD $ALT_REPO @ $ALT_BRANCH ====="
rm -rf alt error.log Image *.zip || true
git clone --depth 1 --single-branch -b "$ALT_BRANCH" "$ALT_REPO" alt
cd alt
echo "--- toolchain"; clang --version | head -2; ld.lld --version | head -1
echo "--- defconfig"; make $MAKE_ARGS vendor/pipa_stock_defconfig 2>&1 | tail -15
echo "--- prep"; yes '' | make $MAKE_ARGS olddefconfig 2>&1 | tail -5 || true
grep -E 'CONFIG_LOCALVERSION=|CONFIG_LOCALVERSION_AUTO|CONFIG_MODVERSIONS|CONFIG_KSU|CONFIG_BPF_LSM|CONFIG_MODULE_SIG' out/.config || true
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
upzip() { zip -q -j "$1" Image; }
upzip "$ZIPNAME"
ls -l "$ZIPNAME" Image
echo "===== ALT BUILD OK"
