#!/usr/bin/env bash
# Step 15 — NVIDIA proprietary driver for GPU compute (requires sudo + reboot).
# Run: sudo ./15-nvidia-offload.sh
#
# WHY: the MX350 runs on nouveau, whose kernel log says
#     nouveau 0000:01:00.0: pmu: firmware unavailable
# Without PMU firmware nouveau cannot manage the card's clocks, so it is stuck
# at boot clocks forever. NVK (Mesa's nouveau Vulkan) does support Pascal since
# Mesa 25.1, but on a card pinned to boot clocks it is slower than the CPU.
# The proprietary driver is the only way to get real clocks, real Vulkan, and
# CUDA out of this GPU.
#
# WHAT THIS DOES NOT DO: it does not move the desktop onto the NVIDIA card.
# The MX350 is a 3D controller with no display outputs — the Intel iGPU owns
# eDP-1 and keeps rendering Hyprland. That is deliberate: it avoids the usual
# Hyprland-on-NVIDIA problems entirely and keeps battery life.
#
# ROLLBACK (if anything misbehaves):
#     sudo apt purge '^nvidia-.*' && sudo apt autoremove
#     sudo rm -f /etc/modprobe.d/nvidia-kali-hyprland.conf
#     sudo update-initramfs -u && sudo reboot
# nouveau returns automatically once the nvidia packages are gone.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Run: sudo $0"
    exit 1
fi

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────
say "Preflight"

lspci -nn | grep -qi "10de:" || die "no NVIDIA GPU on the PCI bus"
gpu=$(lspci -nn | grep -i "10de:" | head -1)
ok "GPU: ${gpu#*: }"

# Secure Boot would refuse the unsigned DKMS module.
sb=1
for v in /sys/firmware/efi/efivars/SecureBoot-*; do
    [[ -r $v ]] && sb=$(od -An -t u1 "$v" 2>/dev/null | awk '{print $NF}')
done
if [[ ${sb:-1} == 0 ]]; then
    ok "Secure Boot disabled — DKMS modules will load"
else
    die "Secure Boot is ENABLED. An unsigned DKMS module will not load; either
        disable Secure Boot in firmware or enrol a MOK key first."
fi

# DKMS builds against the RUNNING kernel, so its headers must be present.
kernel=$(uname -r)
if dpkg-query -W -f='${Status}' "linux-headers-$kernel" 2>/dev/null | grep -q "ok installed"; then
    ok "headers for $kernel installed"
else
    say "installing headers for $kernel"
    apt-get install -y "linux-headers-$kernel" || die "no headers for $kernel — cannot build the module"
fi

# ── Install ───────────────────────────────────────────────────────────────
say "Installing the driver (this builds a kernel module, it takes a few minutes)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y \
    nvidia-driver \
    nvidia-kernel-dkms \
    nvidia-vulkan-icd \
    nvidia-smi \
  || die "driver install failed — see the apt output above"
ok "driver packages installed"

# CUDA is optional but it is the point of the exercise for compute: it is what
# hashcat and voxtype's ONNX backend use.
if apt-get install -y nvidia-cuda-toolkit; then
    ok "CUDA toolkit installed"
else
    warn "CUDA toolkit failed to install — Vulkan compute will still work"
fi

# ── Configure ─────────────────────────────────────────────────────────────
say "Configuring"

# nvidia-drm modeset is required for the card to cooperate with Wayland, and
# costs nothing when the card drives no outputs.
cat >/etc/modprobe.d/nvidia-kali-hyprland.conf <<'EOF'
# kali-hyprland: NVIDIA is compute-only here — the Intel iGPU drives eDP-1.
# modeset=1 is required for any Wayland interaction with the card.
options nvidia-drm modeset=1
# Free the GPU when nothing is using it, so the dGPU can power down on battery.
options nvidia NVreg_DynamicPowerManagement=0x02
EOF
ok "wrote /etc/modprobe.d/nvidia-kali-hyprland.conf"

update-initramfs -u >/dev/null 2>&1 && ok "initramfs updated"

echo
say "Done — a REBOOT is required for nouveau to be replaced by nvidia."
cat <<NEXT

After rebooting, verify with:
    nvidia-smi                      # should list the GeForce MX350
    lsmod | grep -E '^nvidia|^nouveau'
    hyprctl monitors                # eDP-1 must still be on the Intel GPU

Then give voxtype a GPU build:
    <repo>/16-voxtype-gpu.sh

If the desktop misbehaves, roll back with the commands in the header of
this script — nouveau comes back automatically.

NEXT
