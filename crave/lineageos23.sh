#!/usr/bin/env bash
# Run this launcher INSIDE a Crave Devspace clone directory.
# The source synchronization and compilation happen in a queued crave run job,
# NEVER in Devspace itself.
set -euo pipefail

if ! command -v crave >/dev/null 2>&1; then
  echo 'ERROR: crave CLI is missing.' >&2
  exit 1
fi
if [ ! -d .repo ]; then
  echo 'ERROR: cd into your Crave clone directory (with .repo) first.' >&2
  echo 'For example: cd /crave-devspaces/Lineage23' >&2
  exit 1
fi

BUILD_COMMAND="$(cat <<'CRAVE_BUILD_JOB'
set -eo pipefail

echo '===== LineageOS 23.2 for Redmi 9 (lancelot) ====='
echo 'Source init and build are running in a Crave build job.'

repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs

mkdir -p .repo/local_manifests
# Do not silently overwrite other device manifests, which may cause duplicate projects.
for existing in .repo/local_manifests/*.xml; do
  [ -e "$existing" ] || continue
  if [ "$existing" != '.repo/local_manifests/lancelot.xml' ]; then
    echo "ERROR: Existing local manifest $existing. Review/remove conflicts before re-running." >&2
    exit 1
  fi
done

cat > .repo/local_manifests/lancelot.xml <<'LANCELOT_XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <!-- Redmi 9 (lancelot), LineageOS 23.2 / Android 16 -->
  <project name="LineageOS/android_device_xiaomi_lancelot" path="device/xiaomi/lancelot" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_device_xiaomi_mt6768-common" path="device/xiaomi/mt6768-common" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_device_mediatek_sepolicy_vndr" path="device/mediatek/sepolicy_vndr" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_hardware_mediatek" path="hardware/mediatek" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_hardware_xiaomi" path="hardware/xiaomi" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_kernel_xiaomi_mt6768" path="kernel/xiaomi/mt6768" revision="lineage-23.2" clone-depth="1" />
  <project name="TheMuppets/proprietary_vendor_xiaomi_lancelot" path="vendor/xiaomi/lancelot" revision="lineage-23.2" clone-depth="1" />
  <project name="TheMuppets/proprietary_vendor_xiaomi_mt6768-common" path="vendor/xiaomi/mt6768-common" revision="lineage-23.2" clone-depth="1" />
</manifest>
LANCELOT_XML

if [ ! -x /opt/crave/resync.sh ]; then
  echo 'ERROR: /opt/crave/resync.sh unavailable in this Crave image.' >&2
  exit 1
fi
/opt/crave/resync.sh

# Sanity checks after sync
for tree in device/xiaomi/lancelot device/xiaomi/mt6768-common \
  kernel/xiaomi/mt6768 vendor/xiaomi/lancelot vendor/xiaomi/mt6768-common; do
  if [ ! -d "$tree" ]; then
    echo "ERROR: Expected tree not synced: $tree" >&2
    exit 1
  fi
done

source build/envsetup.sh
lunch lineage_lancelot-bp4a-userdebug
m bacon

OUTPUT_DIR=out/target/product/lancelot
shopt -s nullglob
roms=("$OUTPUT_DIR"/lineage-23.2-*.zip)
if [ ${#roms[@]} -eq 0 ]; then
  echo "ERROR: Build command completed but no LineageOS 23.2 zip found in $OUTPUT_DIR" >&2
  exit 1
fi
printf '===== ROM packages =====\n'
ls -lh "${roms[@]}"
sha256sum "${roms[@]}" | tee "$OUTPUT_DIR/SHA256SUMS-lancelot.txt"
if [ -f "$OUTPUT_DIR/recovery.img" ]; then
  ls -lh "$OUTPUT_DIR/recovery.img"
fi
printf '===== Build successful =====\n'
CRAVE_BUILD_JOB
)"

# Do not use --clean unless Crave staff authorizes it.
# --no-patch follows Crave's documented sample commands.
crave run --no-patch -- "$BUILD_COMMAND"
