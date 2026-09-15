#!/usr/bin/env bash
# Step 16 — swap voxtype to a GPU build (NO sudo). Run AFTER 15-nvidia-offload.sh
# and a reboot.
#
#   ./16-voxtype-gpu.sh            # Vulkan build (default)
#   ./16-voxtype-gpu.sh --cuda     # ONNX + CUDA build
#   ./16-voxtype-gpu.sh --pin-device N
#                                  # only write the Vulkan device pin, no download
#
# The AVX-512 build installed by 14-omarchy4-extras.sh is CPU-only by design;
# upstream ships GPU support as separate binaries. This fetches one, keeps the
# CPU build alongside as voxtype-cpu, and restarts the daemon.
#
# WHICH TO PICK
#   vulkan — Whisper on Vulkan. Single binary, uses the models you already have.
#   cuda   — ONNX/Parakeet on CUDA. Usually faster, but needs the CUDA runtime
#            and pulls ~150 MB of ONNX provider libraries.
set -euo pipefail

VOXTYPE_VERSION="${VOXTYPE_VERSION:-1.0.1}"
BASE="https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}"
MODE="vulkan"
PIN_ONLY=""
PIN_DEVICE=""
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROPIN="$HOME/.config/systemd/user/voxtype.service.d/10-gpu.conf"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cuda)       MODE="cuda"; shift ;;
        --pin-device) PIN_DEVICE="${2:-}"; PIN_ONLY=1; shift 2 ;;
        *)            shift ;;
    esac
done

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

export PATH="$HOME/.local/bin:$PATH"

# Pin voxtype's Vulkan backend to a specific device. This is NOT shipped
# pre-filled: ggml_vulkan's device order is per-machine, and pinning a stranger's
# laptop to index 1 would silently send the work to the wrong GPU — or to no GPU
# at all. The template in config/ carries the measurements that justify pinning;
# the index itself has to come from the machine.
write_pin() {
    local dev="$1" template="$PROJECT/config/systemd/voxtype.service.d/10-gpu.conf"
    [[ $dev =~ ^[0-9]+$ ]] || die "--pin-device takes a device index, got: '$dev'"
    [[ -f $template ]] || die "missing template: $template"
    mkdir -p "$(dirname "$DROPIN")"
    # `&&` alone would abort under `set -e` when there is no file to back up.
    if [[ -f $DROPIN ]]; then cp "$DROPIN" "$DROPIN.bak-$(date +%Y%m%d-%H%M%S)"; fi
    # Anchored to the directive so the placeholder stays readable in the
    # comment above it, which is what tells the next reader how to change it.
    sed "s/^Environment=GGML_VK_VISIBLE_DEVICES=@@VK_DEVICE@@$/Environment=GGML_VK_VISIBLE_DEVICES=$dev/" \
        "$template" >"$DROPIN"
    grep -q "^Environment=GGML_VK_VISIBLE_DEVICES=$dev$" "$DROPIN" \
        || die "substitution failed — template changed shape?"
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user restart voxtype.service 2>/dev/null || warn "voxtype restart failed"
    ok "pinned GGML_VK_VISIBLE_DEVICES=$dev  ($DROPIN)"
}

if [[ -n $PIN_ONLY ]]; then
    write_pin "$PIN_DEVICE"
    exit 0
fi

command -v voxtype >/dev/null || die "voxtype not installed — run 14-omarchy4-extras.sh first"

# ── Confirm the GPU is actually usable before swapping anything ───────────
say "Checking the GPU"
if ! command -v nvidia-smi >/dev/null; then
    die "nvidia-smi missing — run 15-nvidia-offload.sh and reboot first"
fi
if ! nvidia-smi --query-gpu=name,driver_version --format=csv,noheader >/dev/null 2>&1; then
    die "nvidia-smi cannot talk to the driver. Did you reboot after installing it?"
fi
ok "GPU: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)"

if lsmod | grep -q '^nouveau'; then
    die "nouveau is still loaded — the nvidia module did not take over. Reboot."
fi

if [[ $MODE == cuda ]]; then
    command -v nvcc >/dev/null || warn "nvcc not found; the ONNX CUDA provider may still work via the runtime"
fi

# ── Fetch ─────────────────────────────────────────────────────────────────
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

if [[ $MODE == vulkan ]]; then
    assets=("voxtype-${VOXTYPE_VERSION}-linux-x86_64-vulkan")
else
    assets=(
        "voxtype-${VOXTYPE_VERSION}-linux-x86_64-onnx-cuda-12"
        "voxtype-${VOXTYPE_VERSION}-linux-x86_64-onnx-cuda-12.libonnxruntime_providers_cuda.so"
        "voxtype-${VOXTYPE_VERSION}-linux-x86_64-onnx-cuda-12.libonnxruntime_providers_shared.so"
    )
fi

say "Downloading the $MODE build"
for a in "${assets[@]}"; do
    curl -fsSL --retry 3 --max-time 600 -o "$tmp/$a" "$BASE/$a" || die "download failed: $a"
    printf '   %s  %s\n' "$(du -h "$tmp/$a" | cut -f1)" "$a"
done

bin="$tmp/${assets[0]}"
chmod +x "$bin"
"$bin" --version >/dev/null 2>&1 || die "downloaded binary does not run"
"$bin" --help 2>&1 | grep -qiE "usage|command" || die "binary has no usage output — wrong asset?"
ok "verified: $("$bin" --version 2>/dev/null | head -1)"

# ── Install ───────────────────────────────────────────────────────────────
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/voxtype"

# Keep the CPU build so you can A/B it.
if [[ -f $HOME/.local/bin/voxtype && ! -f $HOME/.local/bin/voxtype-cpu ]]; then
    cp "$HOME/.local/bin/voxtype" "$HOME/.local/bin/voxtype-cpu"
    ok "kept the CPU build as voxtype-cpu (for comparison)"
fi

install -m755 "$bin" "$HOME/.local/bin/voxtype"
for a in "${assets[@]:1}"; do
    install -m644 "$tmp/$a" "$HOME/.local/lib/voxtype/${a##*.libonnxruntime}"
    install -m644 "$tmp/$a" "$HOME/.local/lib/voxtype/libonnxruntime${a##*.libonnxruntime}"
done
ok "installed ~/.local/bin/voxtype ($MODE)"

# ── Restart and report ────────────────────────────────────────────────────
if systemctl --user list-unit-files 2>/dev/null | grep -q voxtype; then
    say "Restarting the daemon"
    systemctl --user restart voxtype.service || warn "restart failed"
    sleep 4
fi

echo
say "Acceleration report"
voxtype info accel 2>&1 | head -12 | sed 's/^/  /'
echo
voxtype info variants 2>&1 | sed -n '/Hardware/,/^$/p' | sed 's/^/  /'

if [[ ! -f $DROPIN ]]; then
    echo
    warn "no Vulkan device pin is set. With more than one Vulkan device, ggml"
    warn "picks index 0 — usually the integrated GPU, which is often the slower"
    warn "one. Check which devices exist and what they are:"
    echo "      journalctl --user -u voxtype -n 50 | grep -i vulkan"
    echo "  then pin the one you want (and MEASURE, do not trust the flags):"
    echo "      $PROJECT/16-voxtype-gpu.sh --pin-device N"
fi

cat <<'NEXT'

If it still says cpu-fallback, check:
    voxtype setup gpu           # backend status and GPU selection
    VOXTYPE_VULKAN_DEVICE=nvidia voxtype info accel

Roll back to the CPU build with:
    cp ~/.local/bin/voxtype-cpu ~/.local/bin/voxtype
    systemctl --user restart voxtype

NEXT
