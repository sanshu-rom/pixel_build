#!/bin/bash

rom_fp="$(date +%y%m%d)"
mkdir -p release/$rom_fp/

set -e

if [ -z "$USER" ];then
    export USER="$(id -un)"
fi
export LC_ALL=C

if [[ -n "$3" ]];then
    jobs=$3
else
    if [[ $(uname -s) = "Darwin" ]];then
        jobs=$(sysctl -n hw.ncpu)
    elif [[ $(uname -s) = "Linux" ]];then
        jobs=$(nproc)
    fi
fi

## handle command line arguments
read -p "Do you want to sync? (y/N) " choice

# define branch
pe="pie"
phh="android-9.0"

repo init -u https://github.com/PixelExperience-P/manifest -b $pe

if [ -d .repo/local_manifests ] ;then
    ( cd .repo/local_manifests; git fetch; git reset --hard; git checkout origin/$phh)
else
    git clone https://github.com/phhusson/treble_manifest .repo/local_manifests -b $phh
fi

if [ -z "$local_patches" ];then
    if [ -d patches ];then
        ( cd patches; git fetch; git reset --hard; git checkout origin/$phh)
    else
        git clone https://github.com/phhusson/treble_patches patches -b $phh
    fi
else
    rm -Rf patches
    mkdir patches
    unzip  "$local_patches" -d patches
fi

#TUNA fetch="https://android.googlesource.com" 
sed -i -e 's/fetch=\"https:\/\/android.googlesource.com\"/fetch=\"https:\/\/aosp.tuna.tsinghua.edu.cn\"/g' .repo/local_manifests/manifest.xml

#We don't want to replace from AOSP since we'll be applying patches by hand
rm -f .repo/local_manifests/replace.xml

# Remove exfat entry from local_manifest if it exists in ROM manifest 
if grep -rqF exfat .repo/manifests || grep -qF exfat .repo/manifest.xml;then
    sed -i -E '/external\/exfat/d' .repo/local_manifests/manifest.xml
fi

if [[ $choice == *"y"* ]];then
    repo sync -c -j$jobs --force-sync --no-tags --no-clone-bundle
fi

# phh patches
bash "$(dirname "$0")/apply-patches.sh" patches

# Revert Sample in ROM manifest 
if grep -qF sample .repo/manifests/snippets/remove.xml;then
    sed -i -E '/device\/sample/d' .repo/manifests/snippets/remove.xml
fi

# add pixel.mk to phh-treble
cp $(dirname "$0")/pixel.mk device/phh/treble/

# increase system.img size
sed -i -e 's/BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2147483648/BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2621440000/g' device/phh/treble/phhgsi_arm64_ab/BoardConfig.mk

# Fake Pixel Devices :P
export PRODUCT_MANUFACTURER="Google"
sed -i -e 's/PRODUCT_BRAND := Android/PRODUCT_BRAND := Google/g' device/phh/treble/generate.sh
sed -i -e 's/PRODUCT_MODEL := Phh-Treble $apps_name/PRODUCT_BRAND := Pixel 2 XL/g' device/phh/treble/generate.sh

if grep -qF eligible_device device/phh/treble/system.prop;then
    sed -i -e '$a\ro.opa.eligible_device=true' device/phh/treble/system.prop
fi

# TO BUILD
. build/envsetup.sh

buildVariant() {
	lunch $1
	make WITHOUT_CHECK_API=true BUILD_NUMBER=$rom_fp installclean
	make WITHOUT_CHECK_API=true BUILD_NUMBER=$rom_fp -j$jobs systemimage
	make WITHOUT_CHECK_API=true BUILD_NUMBER=$rom_fp vndk-test-sepolicy
	xz -c $OUT/system.img > release/$rom_fp/system-${2}.img.xz
}

repo manifest -r > release/$rom_fp/manifest.xml
# buildVariant treble_arm64_bvN-userdebug arm64-ab-vanilla-nosu
buildVariant treble_arm64_bgS-userdebug arm64-ab-gapps-su

