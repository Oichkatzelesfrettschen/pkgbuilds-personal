# eirikr-nvidia-tuning

Workstation NVIDIA driver hygiene as a single owned, upgrade-safe pacman
package. Replaces a pile of unowned `/etc/modprobe.d/` and `/etc/profile.d/`
hand-edits.

## Why

Hand-edits in `/etc/` are not tracked by `pacman -Qkk`, get reported as
"UNOWNED" in audit passes, and have no rollback / no upgrade story. Bundling
them in a real package fixes all three.

## What is in here

| Path | Purpose |
|---|---|
| `/etc/modprobe.d/nvidia.conf` | `InitializeSystemMemoryAllocations=0` (restated from the cachyos-settings file it replaces), `PreserveVideoMemoryAllocations=1`, software DDC/CI I2C. RTD3 and S0ix keep driver defaults, which already disable both on a desktop. |
| `/etc/modprobe.d/tty-only-nvidia.conf` | Blacklists every non-NVIDIA graphics module so NVIDIA stays the sole DRM master. |
| `/etc/modprobe.d/nouveau-blacklist.conf` | Independent nouveau lockout (`blacklist` + `modeset=0`) as a defence-in-depth layer. |
| `/etc/modprobe.d/nvidia-uvm-sam.conf` | `uvm_disable_sam_migration=0`: UVM migrates system-allocated (HMM) memory into VRAM. |
| `/usr/lib/environment.d/60-eirikr-nvidia.conf` | `__GL_YIELD=USLEEP`, `LIBVA_DRIVER_NAME=nvidia` for every user-manager unit. `__GL_SYNC_TO_VBLANK` stays unset: NVIDIA applies it to EGL and deadlocks Wayland Qt and Firefox clients. |
| `/usr/lib/eirikr-nvidia-tuning/nvidia-profiler-device-setup.sh` | Grants the R610 `profiler-device` capability to the `nvidia-profiler` group. |
| `/usr/lib/systemd/system/nvidia-profiler-device.service` | Oneshot that applies that grant after the NVIDIA module loads. |
| `/usr/lib/sysusers.d/eirikr-nvidia-tuning.conf` | Declares the `nvidia-profiler` group. |

## Profiling counters are a group capability, not a global regkey

Through 1.0.0 this package shipped `NVreg_RestrictProfilingToAdminUsers=0`,
which opens GPU performance counters to every local user and which NVIDIA
states is superseded and slated for removal. NVIDIA restricted those counters
because a counter stream is a side channel, and R610 replaces the
all-or-nothing key with a capability exposed as a device node: read permission
grants profiling to the reader alone.

1.1.0 drops the regkey and grants the capability instead. The oneshot resolves
`profiler-device` from `/proc/driver/nvidia-caps/sys-minors` on every boot
rather than hard-coding a minor, runs `nvidia-modprobe -f` to create the node,
applies a `g:nvidia-profiler:r` ACL, writes `DeviceFileModify: 0` so a later
NVIDIA user-space tool cannot recreate the node over the grant, and verifies
each of those facts by reading them back before it exits. Any mismatch fails
the unit, because a partial grant reads at the next profiling attempt as a
driver fault rather than a configuration one.

`profiler-device` already subsumes `profiler-context`. `trace-device` stays
ungranted: CUPTI tracing works without it, and an unused grant widens the
surface for nothing. `NVreg_RestrictProfilingToAdminUsers` keeps its
restrictive default, so no other local user gains counter access.

Applying it needs no reboot. Enabling the unit and joining the group are the
two steps, and group membership reaches a process at its next login:

```sh
sudo systemctl enable --now nvidia-profiler-device.service
sudo gpasswd -a "$USER" nvidia-profiler
# verify, after logging back in
minor=$(awk '$1=="profiler-device"{print $2}' /proc/driver/nvidia-caps/sys-minors)
getfacl /dev/nvidia-caps/nvidia-cap"$minor"
ncu --version
```

## What is NOT in here

- **OC / clock-offset / power-limit policy** — that lives in `nvidia-oc-nvml`
  + the local `/etc/nvidia-oc-nvml.conf`. Different concern.
- **`/usr/local/sbin/nvidia-gpu-profile-apply`** — that is a separate
  apply-tool; if it ever gets packaged it should be its own thing
  (`eirikr-nvidia-oc-apply` or similar).
- **The kernel module itself** — that is `nvidia-utils` +
  `linux-cachyos-nvidia-open` (or `nvidia-open-dkms`, or proprietary
  `nvidia-580xx-dkms`).

## How

```sh
cd ~/Github/PKGBUILDS/pkgbuilds-in-progress/eirikr-nvidia-tuning
makepkg -s
sudo pacman -U eirikr-nvidia-tuning-*.pkg.tar.zst
# verify
pacman -Qkk eirikr-nvidia-tuning
```

After install, every file is tracked. `pacman -Qo /etc/modprobe.d/nvidia.conf`
returns this package name instead of "No package owns ...".

## Reload semantics

- Module options take effect on next module load. After upgrade either reboot
  or rebuild the initramfs and reload manually from a TTY with no compositor:
  `sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia && sudo modprobe nvidia_drm modeset=1`.
- The session environment takes effect at the next login.
