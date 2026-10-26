#!/usr/bin/env bash
# Experimental BlissRoms Xylobium (Android 17) for Redmi 9 (lancelot).
# Execute ONLY inside a queued Crave build worker, not in Devspace.
# Base Crave project: DerpFest-aosp (ID 64).
set -Eeo pipefail
trap 'echo "[ERROR] Bliss build failed at line $LINENO (status $?)" >&2' ERR

DEVICE=lancelot
OUT_DIR="out/target/product/$DEVICE"
BLISS_TAG=refs/tags/v20.1-stable-xylobium

echo '=== Experimental BlissRoms Android 17 build for lancelot ==='
[[ -d .repo ]] || { echo 'Missing .repo; run from the Crave clone root' >&2; exit 1; }
[[ -f /opt/crave/resync.sh ]] || { echo 'Missing /opt/crave/resync.sh' >&2; exit 1; }

# The Bliss stable manifest uses SSH URLs for public GitHub repos.
# Rewrite these public URLs to HTTPS so worker SSH keys are not required.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=url.https://github.com/BlissRoms/.insteadOf
export GIT_CONFIG_VALUE_0=ssh://git@github.com/BlissRoms/

echo '==> Initializing official BlissRoms 20.1 stable manifest'
repo init -u https://github.com/BlissRoms/stable_releases.git \
  -b "$BLISS_TAG" --git-lfs --depth=1

mkdir -p .repo/local_manifests
for other in .repo/local_manifests/*.xml; do
  [[ -e "$other" ]] || continue
  if [[ "$other" != .repo/local_manifests/lancelot-bliss.xml ]]; then
    echo "Conflicting local manifest: $other" >&2
    echo 'Review conflicting manifests before running this build.' >&2
    exit 1
  fi
done

cat > .repo/local_manifests/lancelot-bliss.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="github-public" fetch="https://github.com" />
  <project remote="github-public" name="LineageOS/android_device_xiaomi_lancelot" path="device/xiaomi/lancelot" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="LineageOS/android_device_xiaomi_mt6768-common" path="device/xiaomi/mt6768-common" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="LineageOS/android_device_mediatek_sepolicy_vndr" path="device/mediatek/sepolicy_vndr" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="LineageOS/android_hardware_mediatek" path="hardware/mediatek" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="LineageOS/android_hardware_xiaomi" path="hardware/xiaomi" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="LineageOS/android_kernel_xiaomi_mt6768" path="kernel/xiaomi/mt6768" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="TheMuppets/proprietary_vendor_xiaomi_lancelot" path="vendor/xiaomi/lancelot" revision="lineage-24.0" clone-depth="1" />
  <project remote="github-public" name="TheMuppets/proprietary_vendor_xiaomi_mt6768-common" path="vendor/xiaomi/mt6768-common" revision="lineage-24.0" clone-depth="1" />
</manifest>
XML

echo '==> Syncing with Crave worker helper'
bash /opt/crave/resync.sh

for tree in \
  device/xiaomi/lancelot device/xiaomi/mt6768-common \
  device/mediatek/sepolicy_vndr hardware/mediatek hardware/xiaomi \
  kernel/xiaomi/mt6768 vendor/xiaomi/lancelot vendor/xiaomi/mt6768-common \
  device/bliss/sepolicy hardware/bliss/interfaces vendor/bliss; do
  [[ -d "$tree" ]] || { echo "Missing synced tree: $tree" >&2; exit 1; }
done

# The upstream Lineage device product must inherit Bliss configuration and
# advertise bliss_lancelot before Bliss's breakfast/blissify can select it.
PRODUCT_TREE=device/xiaomi/lancelot
COMMON_TREE=device/xiaomi/mt6768-common

cp "$PRODUCT_TREE/lineage_lancelot.mk" "$PRODUCT_TREE/bliss_lancelot.mk"
sed -i \
  -e 's|PRODUCT_NAME := lineage_lancelot|PRODUCT_NAME := bliss_lancelot|' \
  -e 's|vendor/lineage/config/common_full_phone.mk|vendor/bliss/config/common_full_phone.mk|' \
  "$PRODUCT_TREE/bliss_lancelot.mk"
sed -i 's|lineage_lancelot.mk|bliss_lancelot.mk|' "$PRODUCT_TREE/AndroidProducts.mk"

# Lineage interfaces and sepolicy have equivalent Bliss paths.
sed -i 's|hardware/lineage/interfaces|hardware/bliss/interfaces|g' \
  "$COMMON_TREE/mt6768.mk"
sed -i \
  -e 's|device/lineage/sepolicy/libion/sepolicy.mk|device/bliss/sepolicy/libion/sepolicy.mk|g' \
  -e 's|vendor/lineage/config/BoardConfigReservedSize.mk|vendor/bliss/config/BoardConfigReservedSize.mk|g' \
  "$COMMON_TREE/BoardConfigCommon.mk"

grep -q 'PRODUCT_NAME := bliss_lancelot' "$PRODUCT_TREE/bliss_lancelot.mk"
grep -q 'vendor/bliss/config/common_full_phone.mk' "$PRODUCT_TREE/bliss_lancelot.mk"
grep -q 'bliss_lancelot.mk' "$PRODUCT_TREE/AndroidProducts.mk"

echo '==> Building BlissRoms vanilla'
source build/envsetup.sh
blissify -v lancelot

shopt -s nullglob
roms=("$OUT_DIR"/Bliss*.zip)
(( ${#roms[@]} > 0 )) || { echo "No Bliss ZIP in $OUT_DIR" >&2; exit 1; }

images=()
[[ ! -f "$OUT_DIR/recovery.img" ]] || images+=("$OUT_DIR/recovery.img")
ls -lh "${roms[@]}" "${images[@]}"
sha256sum "${roms[@]}" "${images[@]}" | tee "$OUT_DIR/SHA256SUMS-bliss-lancelot.txt"

# Optional personal Telegram Saved Messages upload.
# Account session files must be securely pushed to THIS project's worker.
echo '==> Optional Telegram backup'
if [[ "${TG_AUTO_UPLOAD:-1}" != 0 ]] && \
   [[ -s "$HOME/.config/telegram-upload.json" ]] && \
   [[ -s "$HOME/.config/telegram-upload.session" ]]; then
  tg_bin="$(command -v telegram-upload || true)"
  if [[ -z "$tg_bin" ]] && command -v python3 >/dev/null 2>&1; then
    echo '==> Installing user-local telegram-upload if needed'
    python3 -m pip install --user --break-system-packages -q -U telegram-upload || true
    [[ ! -x "$HOME/.local/bin/telegram-upload" ]] || tg_bin="$HOME/.local/bin/telegram-upload"
  fi
  if [[ -n "$tg_bin" ]]; then
    "$tg_bin" --to me --large-files split --force-file \
      "${roms[@]}" "${images[@]}" "$OUT_DIR/SHA256SUMS-bliss-lancelot.txt" \
      || echo 'WARNING: Telegram upload failed; artifacts remain available via crave pull.'
  else
    echo 'WARNING: Telegram uploader unavailable; use crave pull.'
  fi
else
  echo 'Telegram upload skipped (no worker credentials or TG_AUTO_UPLOAD=0).'
fi

echo '=== BlissRoms build completed; retrieve artifacts using crave pull ==='
