#!/usr/bin/env bash
# LineageOS 23.2 (Android 16) for Xiaomi Redmi 9 (lancelot)
# RUNS ON A CRAVE BUILD WORKER, via: crave run --no-patch -- "curl ... && bash ..."
# Do not run this directly in Devspace or on your laptop.
set -Eeo pipefail  # Android envsetup.sh may reference unset variables

trap 'printf "\n[ERROR] Build failed at line %s (exit code %s)\n" "$LINENO" "$?" >&2' ERR

ROM_BRANCH="lineage-23.2"
DEVICE="lancelot"
OUT_DIR="out/target/product/${DEVICE}"

printf '\n=== LineageOS 23.2 for %s: Crave worker build ===\n' "$DEVICE"
if [[ ! -d .repo ]]; then
  echo 'ERROR: Expected to run in the Crave LOS 23.2 source root (.repo not found).' >&2
  exit 1
fi

# Use the same LineageOS 23.2 manifest source as Crave project 99.
# Shallow history reduces unnecessary downloads; Git LFS is needed for vendor blobs.
echo '==> Initializing LineageOS 23.2 manifest'
repo init -u https://github.com/accupara/los23.2.git -b "$ROM_BRANCH" --git-lfs --depth=1

# A dedicated local manifest for the eight lancelot repositories.
# Do not silently delete unrelated manifests in a reused workspace.
mkdir -p .repo/local_manifests
for other in .repo/local_manifests/*.xml; do
  [[ -e "$other" ]] || continue
  if [[ "$other" != .repo/local_manifests/lancelot.xml ]]; then
    echo "ERROR: Another local manifest exists: $other" >&2
    echo 'Check it for conflicts before rebuilding.' >&2
    exit 1
  fi
done

cat > .repo/local_manifests/lancelot.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project name="LineageOS/android_device_xiaomi_lancelot" path="device/xiaomi/lancelot" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_device_xiaomi_mt6768-common" path="device/xiaomi/mt6768-common" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_device_mediatek_sepolicy_vndr" path="device/mediatek/sepolicy_vndr" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_hardware_mediatek" path="hardware/mediatek" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_hardware_xiaomi" path="hardware/xiaomi" revision="lineage-23.2" clone-depth="1" />
  <project name="LineageOS/android_kernel_xiaomi_mt6768" path="kernel/xiaomi/mt6768" revision="lineage-23.2" clone-depth="1" />
  <project name="TheMuppets/proprietary_vendor_xiaomi_lancelot" path="vendor/xiaomi/lancelot" revision="lineage-23.2" clone-depth="1" />
  <project name="TheMuppets/proprietary_vendor_xiaomi_mt6768-common" path="vendor/xiaomi/mt6768-common" revision="lineage-23.2" clone-depth="1" />
</manifest>
XML

echo '==> Syncing source with Crave resync helper'
if [[ ! -f /opt/crave/resync.sh ]]; then
  echo 'ERROR: /opt/crave/resync.sh is missing on this worker.' >&2
  exit 1
fi
bash /opt/crave/resync.sh

# Verify key trees after sync (fail now rather than with a confusing build error).
for tree in \
  device/xiaomi/lancelot \
  device/xiaomi/mt6768-common \
  device/mediatek/sepolicy_vndr \
  hardware/mediatek \
  hardware/xiaomi \
  kernel/xiaomi/mt6768 \
  vendor/xiaomi/lancelot \
  vendor/xiaomi/mt6768-common; do
  if [[ ! -d "$tree" ]]; then
    echo "ERROR: Missing source directory after sync: $tree" >&2
    exit 1
  fi
done

echo '==> Configuring build environment'
source build/envsetup.sh
lunch "lineage_${DEVICE}-bp4a-userdebug"

echo '==> Building LineageOS OTA ZIP'
# Do not clean the entire out/ directory: Crave expects incremental builds.
m bacon

echo '==> Listing build artifacts'
shopt -s nullglob
roms=("$OUT_DIR"/lineage-23.2-*-"$DEVICE".zip)
if (( ${#roms[@]} == 0 )); then
  echo "ERROR: Build finished but ROM ZIP not found in $OUT_DIR" >&2
  exit 1
fi

ls -lh "${roms[@]}"
images=()
[[ -f "$OUT_DIR/recovery.img" ]] && images+=("$OUT_DIR/recovery.img")
((${#images[@]} == 0)) || ls -lh "${images[@]}"

sha256sum "${roms[@]}" "${images[@]}" | tee "$OUT_DIR/SHA256SUMS-lancelot.txt"
# Optional Telegram backup. No changes to the tested build steps above.
echo '==> Optional Telegram Saved Messages upload'
if [[ "${TG_AUTO_UPLOAD:-1}" != "0" ]] && \
   [[ -s "$HOME/.config/telegram-upload.json" ]] && \
   [[ -s "$HOME/.config/telegram-upload.session" ]]; then
  tg_bin="$(command -v telegram-upload || true)"
  if [[ -z "$tg_bin" ]]; then
    tg_venv="$HOME/.local/share/telegram-upload-venv"
    if [[ ! -x "$tg_venv/bin/telegram-upload" ]]; then
      echo 'Installing telegram-upload in a user-local Python environment.'
      if command -v python3 >/dev/null 2>&1 && \
         python3 -m venv "$tg_venv" && \
         "$tg_venv/bin/python" -m pip install -q -U telegram-upload; then
        echo 'telegram-upload installed.'
      else
        echo 'WARNING: telegram-upload installation failed; skipping upload.'
      fi
    fi
    [[ ! -x "$tg_venv/bin/telegram-upload" ]] || tg_bin="$tg_venv/bin/telegram-upload"
  fi
  if [[ -n "$tg_bin" ]]; then
    # Telegram Free limit is 2 GiB; split larger ZIPs automatically.
    if "$tg_bin" --to me --large-files split --force-file \
        "${roms[@]}" "${images[@]}" "$OUT_DIR/SHA256SUMS-lancelot.txt"; then
      echo 'Telegram upload completed.'
    else
      echo 'WARNING: Telegram upload failed; ROM remains available via crave pull.'
    fi
  else
    echo 'Telegram upload skipped: executable is unavailable.'
  fi
else
  echo 'Telegram upload skipped: missing worker credentials or TG_AUTO_UPLOAD=0.'
fi

echo '=== Build finished; use crave pull from Devspace to retrieve outputs ==='
