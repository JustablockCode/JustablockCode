#!/usr/bin/env bash
# Experimental BlissRoms Xylobium (Android 17) for Redmi 9 (lancelot).
# Execute ONLY inside a queued Crave build worker, not in Devspace.
# Crave base: LOS 23.2 (ID 99, Android 16); the worker switches to Bliss Android 17.
# Unsupported cross-version build. FOSSonTop recommends matching Android base versions.
# Use a SEPARATE Crave clone at /crave-devspaces/Bliss20, never the working Lineage23 clone.
set -Eeo pipefail
trap 'echo "[ERROR] Bliss build failed at line $LINENO (status $?)" >&2' ERR

DEVICE=lancelot
PRODUCT_OUT_DIR="out/target/product/$DEVICE"
BLISS_TAG=refs/tags/v20.1-stable-xylobium

echo '=== Experimental BlissRoms Android 17 build for lancelot ==='
[[ -d .repo ]] || { echo 'Missing .repo; run from the Crave clone root' >&2; exit 1; }
[[ -f /opt/crave/resync.sh ]] || { echo 'Missing /opt/crave/resync.sh' >&2; exit 1; }

# Crave mounts the selected clone as its worker workspace; its basename is NOT
# required to equal the Devspace clone folder. We already checked for .repo.
# Choose /crave-devspaces/Bliss20 in Devspace BEFORE calling crave run.
echo "==> Crave worker source root: $(pwd -P)"
echo 'WARNING: Android 16 Crave base to Bliss Android 17 is experimental.'
echo 'Ensure Crave permits this Android-version mismatch before queueing.'

# Rewrite public GitHub SSH remotes to HTTPS. This also avoids an
# interactive "Are you sure you want to continue connecting?" prompt in workers.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf
export GIT_CONFIG_VALUE_0=ssh://git@github.com/
export GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf
export GIT_CONFIG_VALUE_1=git@github.com:

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

# Fail early if expected Bliss/Lineage integration points have changed.
# These paths and modules were checked against Bliss 20.1 Xylobium and
# LineageOS 24.0; failing clearly is safer than silently broken sed commands.
echo '==> Checking Bliss/Lineage port prerequisites (supports prior patched checkout)'
for required in \
  device/xiaomi/lancelot/lineage_lancelot.mk \
  device/xiaomi/lancelot/AndroidProducts.mk \
  device/xiaomi/mt6768-common/mt6768.mk \
  device/xiaomi/mt6768-common/BoardConfigCommon.mk \
  vendor/bliss/config/common_full_phone.mk \
  vendor/bliss/config/BoardConfigReservedSize.mk \
  vendor/bliss/vars/aosp_target_release \
  vendor/bliss/build/envsetup.sh \
  vendor/bliss/build/tasks/blissify.mk \
  device/bliss/sepolicy/libion/sepolicy.mk \
  device/bliss/sepolicy/libperfmgr/sepolicy.mk \
  device/mediatek/sepolicy_vndr/SEPolicy.mk \
  hardware/bliss/interfaces/health/aidl/default/Android.bp \
  hardware/bliss/interfaces/light/Android.bp \
  hardware/bliss/interfaces/power-libperfmgr/Android.bp \
  hardware/lineage/compat/frameworks/compat.mk; do
  [[ -f "$required" ]] || { echo "ERROR: Missing required file: $required" >&2; exit 1; }
done

require_source_text() {
  local needle="$1" file="$2"
  grep -Fq -- "$needle" "$file" || {
    echo "ERROR: Expected upstream text not found: $needle in $file" >&2
    exit 1
  }
}
require_source_text 'aosp_target_release=cp2a' vendor/bliss/vars/aosp_target_release
require_source_text 'PRODUCT_NAME := lineage_lancelot' device/xiaomi/lancelot/lineage_lancelot.mk
require_source_text 'vendor/lineage/config/common_full_phone.mk' device/xiaomi/lancelot/lineage_lancelot.mk
# Crave reuses build workers. Previous Bliss attempts can leave the local
# device checkout already converted; accepting either known state is essential.
require_one_of_text() {
  local file="$1" original="$2" converted="$3"
  if ! grep -Fq -- "$original" "$file" && ! grep -Fq -- "$converted" "$file"; then
    echo "ERROR: Unexpected upstream content in $file" >&2
    echo "Expected either: $original OR $converted" >&2
    exit 1
  fi
}
require_one_of_text device/xiaomi/lancelot/AndroidProducts.mk \
  'lineage_lancelot.mk' 'bliss_lancelot.mk'
require_one_of_text device/xiaomi/mt6768-common/mt6768.mk \
  'hardware/lineage/interfaces/power-libperfmgr' 'hardware/bliss/interfaces/power-libperfmgr'
require_one_of_text device/xiaomi/mt6768-common/BoardConfigCommon.mk \
  'device/lineage/sepolicy/libion/sepolicy.mk' 'device/bliss/sepolicy/libion/sepolicy.mk'
require_one_of_text device/xiaomi/mt6768-common/BoardConfigCommon.mk \
  'vendor/lineage/config/BoardConfigReservedSize.mk' 'vendor/bliss/config/BoardConfigReservedSize.mk'
require_one_of_text device/mediatek/sepolicy_vndr/SEPolicy.mk \
  'device/lineage/sepolicy/libperfmgr/sepolicy.mk' 'device/bliss/sepolicy/libperfmgr/sepolicy.mk'
require_source_text 'name: "vendor.lineage.health-service.default"' hardware/bliss/interfaces/health/aidl/default/Android.bp
require_source_text 'name: "android.hardware.light-service.lineage"' hardware/bliss/interfaces/light/Android.bp
require_source_text 'name: "android.hardware.power-service.lineage-libperfmgr"' hardware/bliss/interfaces/power-libperfmgr/Android.bp

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
# MediaTek sepolicy has a separate, mandatory Lineage-specific include.
# Crave build 308132 failed here before product configuration could complete.
sed -i 's|device/lineage/sepolicy/libperfmgr/sepolicy.mk|device/bliss/sepolicy/libperfmgr/sepolicy.mk|g' \
  device/mediatek/sepolicy_vndr/SEPolicy.mk

grep -q 'PRODUCT_NAME := bliss_lancelot' "$PRODUCT_TREE/bliss_lancelot.mk"
grep -q 'vendor/bliss/config/common_full_phone.mk' "$PRODUCT_TREE/bliss_lancelot.mk"
grep -q 'bliss_lancelot.mk' "$PRODUCT_TREE/AndroidProducts.mk"
require_source_text 'hardware/bliss/interfaces/power-libperfmgr' "$COMMON_TREE/mt6768.mk"
require_source_text 'device/bliss/sepolicy/libion/sepolicy.mk' "$COMMON_TREE/BoardConfigCommon.mk"
require_source_text 'vendor/bliss/config/BoardConfigReservedSize.mk' "$COMMON_TREE/BoardConfigCommon.mk"
require_source_text 'device/bliss/sepolicy/libperfmgr/sepolicy.mk' device/mediatek/sepolicy_vndr/SEPolicy.mk

# Android 17 Soong graph analysis exhausted the worker memory in build 308274.
# A Go heap target can reduce memory spikes, but a fixed 20 GiB limit is wrong
# without knowing the worker's actual RAM/cgroup allocation.
# Soong runs with a sanitized environment; patch the Go entrypoint itself.
# Dynamic heap sizing: 60% of the smaller of /proc/meminfo and cgroup limits.
# Ninja concurrency: CPU allocation, capped by a conservative 3 GiB/job budget.
# Do not change the known-working Lineage23 script or workspace.
echo '==> Detecting Crave worker CPU/RAM constraints'
WORKER_RESOURCES="$(python3 - <<'PY'
import os
import re
from pathlib import Path

GIB = 1 << 30

def read_positive_int(path):
    try:
        val = Path(path).read_text().strip().split()[0]
        num = int(val)
        return num if 0 < num < (1 << 60) else None
    except (OSError, ValueError, IndexError):
        return None

meminfo = Path('/proc/meminfo').read_text()
match = re.search(r'^MemTotal:\s*(\d+)\s*kB$', meminfo, re.M)
if match is None:
    raise RuntimeError('Cannot determine physical RAM from /proc/meminfo')
physical = int(match.group(1)) * 1024
mem_limits = [physical]
for path in (
    '/sys/fs/cgroup/memory.max',
    '/sys/fs/cgroup/memory/memory.limit_in_bytes',
):
    limit = read_positive_int(path)
    if limit is not None:
        mem_limits.append(limit)
effective_ram = min(mem_limits)

cores = len(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else (os.cpu_count() or 1)
try:
    quota, period = Path('/sys/fs/cgroup/cpu.max').read_text().strip().split()[:2]
    if quota != 'max' and int(period) > 0:
        cores = min(cores, max(1, (int(quota) + int(period) - 1) // int(period)))
except (OSError, ValueError, IndexError):
    pass
v1_quota = read_positive_int('/sys/fs/cgroup/cpu/cpu.cfs_quota_us')
v1_period = read_positive_int('/sys/fs/cgroup/cpu/cpu.cfs_period_us')
if v1_quota is not None and v1_period is not None:
    cores = min(cores, max(1, (v1_quota + v1_period - 1) // v1_period))
cores = max(1, cores)

# This is a cautious tuning heuristic, not a tested guarantee for all workers.
ninja_jobs = max(1, min(cores, effective_ram // (3 * GIB)))
soong_heap_bytes = max(512 * (1 << 20), effective_ram * 60 // 100)
print(effective_ram, cores, ninja_jobs, soong_heap_bytes)
PY
)"
read -r WORKER_RAM_BYTES WORKER_CPU_CORES WORKER_NINJA_JOBS SOONG_HEAP_BYTES <<< "$WORKER_RESOURCES"
for value in "$WORKER_RAM_BYTES" "$WORKER_CPU_CORES" "$WORKER_NINJA_JOBS" "$SOONG_HEAP_BYTES"; do
  [[ "$value" =~ ^[0-9]+$ ]] || { echo 'ERROR: Invalid resource detection output' >&2; exit 1; }
done
echo "Worker effective RAM: $(( WORKER_RAM_BYTES / 1073741824 )) GiB (rounded down)"
echo "Worker effective CPU cores: $WORKER_CPU_CORES"
echo "Selected Ninja jobs: $WORKER_NINJA_JOBS (auto; not fixed -j4)"
echo "Selected Soong soft Go heap: $(( SOONG_HEAP_BYTES / 1048576 )) MiB (60% of RAM limit)"
echo '==> Memory/CPU diagnostics (host values may differ from cgroup allocation)'
nproc || true
free -h || true
for metric in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory.current /sys/fs/cgroup/cpu.max; do
  if [[ -r "$metric" ]]; then
    printf '%s: ' "$metric"
    cat "$metric"
  fi
done

# Exact Bliss v20.1 source revision is pinned in the official manifest:
# build/soong @ f4d674a9b9edba3dca3c024bf69f290096523246.
# Update only one Go line and import, and accept a previously patched checkout.
echo '==> Applying RAM-adaptive Android 17 Soong heap protection'
SOONG_MAIN=build/soong/cmd/soong_build/main.go
[[ -f "$SOONG_MAIN" ]] || { echo "ERROR: Missing $SOONG_MAIN" >&2; exit 1; }
python3 - "$SOONG_MAIN" "$SOONG_HEAP_BYTES" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
cap = int(sys.argv[2])
if cap <= 0:
    raise SystemExit('ERROR: Invalid Soong memory limit')

source = path.read_text()
import_anchor = '\t"runtime"\n\t"strings"'
if '\t"runtime/debug"' not in source:
    if source.count(import_anchor) != 1:
        raise SystemExit('ERROR: Bliss Soong imports changed; aborting')
    source = source.replace(import_anchor, '\t"runtime"\n\t"runtime/debug"\n\t"strings"', 1)

anchor = 'func main() {\n\tflag.Parse()\n'
if source.count(anchor) != 1:
    raise SystemExit('ERROR: Bliss Soong main() changed; aborting')

new_line = f'\tdebug.SetMemoryLimit({cap})'
previous = list(re.finditer(r'(?m)^\tdebug\.SetMemoryLimit\([^\n]*\)$', source))
if len(previous) > 1:
    raise SystemExit('ERROR: Multiple Soong memory limits; aborting')
if previous:
    source = source[:previous[0].start()] + new_line + source[previous[0].end():]
else:
    source = source.replace(
        anchor,
        anchor + '\n\t// Dynamic Go heap target calculated from worker RAM/cgroup.\n' + new_line + '\n',
        1,
    )
if source.count('debug.SetMemoryLimit(') != 1:
    raise SystemExit('ERROR: Soong memory patch verification failed')
path.write_text(source)
print(f'Soong Go heap target patched to {cap} bytes')
PY
grep -Fq '"runtime/debug"' "$SOONG_MAIN" || { echo 'ERROR: Missing Soong debug import' >&2; exit 1; }
grep -Fq "debug.SetMemoryLimit($SOONG_HEAP_BYTES)" "$SOONG_MAIN" || {
  echo 'ERROR: Dynamic Soong limit missing after patch' >&2
  exit 1
}
echo '==> Soong adaptive heap target confirmed (not a hard RSS limit)'

echo '==> Building BlissRoms vanilla (userdebug)'
# Crave's baseline image intentionally leaves out ccache and ships a passthrough
# replacement. Bliss 20.1 checks CCACHE_EXEC when sourcing envsetup.sh.
if [[ -x /opt/crave/not_ccache.sh ]]; then
  export CCACHE_EXEC=/opt/crave/not_ccache.sh
  export USE_CCACHE=0
  echo 'Using the official Crave no-ccache wrapper.'
else
  echo 'WARNING: Crave no-ccache wrapper not found; Bliss may warn about ccache.'
fi

# Android/Bliss envsetup and blissify use some normal short-lived pipelines.
# With global "set -Eeo pipefail", their grep/head/sort pipelines can raise
# SIGPIPE (141) and trigger our ERR trap despite non-fatal operation.
# Run these functions in a subshell with explicit exit-status checks instead,
# keeping strict mode enabled in the outer worker script.
if (
  set +e
  set +o pipefail
  trap - ERR
  source build/envsetup.sh
  env_rc=$?
  if (( env_rc != 0 )); then
    echo "ERROR: Bliss envsetup returned $env_rc" >&2
    exit "$env_rc"
  fi
  if [[ "$(type -t blissify || true)" != function ]]; then
    echo 'ERROR: Bliss build function was not loaded by build/envsetup.sh' >&2
    exit 1
  fi
  export TARGET_BUILD_VARIANT=userdebug
  # Validate the actual Android product configuration before any compilation.
  # Blissify can otherwise proceed after a failed internal breakfast call.
  if ! breakfast lancelot; then
    echo 'ERROR: Bliss product configuration failed during breakfast.' >&2
    exit 1
  fi
  # Bliss Android 17 uses Siso by default. It rejects Ninja's "-j16"
  # when passed through NINJA_ARGS (Crave build 308387). Soong itself
  # supplies Siso's --local_jobs using its detected worker CPU allocation.
  # Use the upstream scheduler rather than injecting raw Ninja-only flags.
  unset NINJA_ARGS NINJA_EXTRA_ARGS NINJA_HIGHMEM_NUM_JOBS
  echo "Build concurrency: Bliss/Soong automatic (Siso --local_jobs); worker CPUs: $WORKER_CPU_CORES"
  echo "RAM-based reference (not passed to Siso): $WORKER_NINJA_JOBS jobs"
  blissify -v lancelot
); then
  echo '==> Bliss compilation returned success'
else
  build_rc=$?
  echo "ERROR: Bliss compilation failed (exit code $build_rc)" >&2
  exit "$build_rc"
fi

shopt -s nullglob
roms=("$PRODUCT_OUT_DIR"/Bliss-v20.1-"$DEVICE"-*.zip)
(( ${#roms[@]} > 0 )) || { echo "No Bliss v20.1 ZIP in $PRODUCT_OUT_DIR" >&2; exit 1; }
# Do not accidentally upload an old ZIP left by a prior run.
newest_rom="${roms[0]}"
for candidate in "${roms[@]:1}"; do
  [[ "$candidate" -nt "$newest_rom" ]] && newest_rom="$candidate"
done
roms=("$newest_rom")

images=()
[[ ! -f "$PRODUCT_OUT_DIR/recovery.img" ]] || images+=("$PRODUCT_OUT_DIR/recovery.img")
ls -lh "${roms[@]}" "${images[@]}"
sha256sum "${roms[@]}" "${images[@]}" | tee "$PRODUCT_OUT_DIR/SHA256SUMS-bliss-lancelot.txt"

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
      "${roms[@]}" "${images[@]}" "$PRODUCT_OUT_DIR/SHA256SUMS-bliss-lancelot.txt" \
      || echo 'WARNING: Telegram upload failed; artifacts remain available via crave pull.'
  else
    echo 'WARNING: Telegram uploader unavailable; use crave pull.'
  fi
else
  echo 'Telegram upload skipped (no worker credentials or TG_AUTO_UPLOAD=0).'
fi

echo '=== BlissRoms build completed; retrieve artifacts using crave pull ==='
