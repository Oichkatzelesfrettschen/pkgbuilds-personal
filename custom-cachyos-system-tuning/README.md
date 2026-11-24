# custom-cachyos-system-tuning

A minimal, evidence-justified memory-policy package for a CachyOS workstation
used primarily for heavy software compilation and local/agentic LLM tooling. It
ships only the deltas that are genuinely *not* already provided by
`cachyos-settings` and the Arch sysctl defaults, plus a three-tier swap layout:
zswap (a compressed cache in RAM) in front of a 48 GiB swapfile on the Samsung
980 PRO and a low-priority swapfile on the QLC root disk, per-workload memory and
swap budgets, and a systemd-oomd swap backstop near exhaustion. It also bounds heavy interactive workloads, retains two
Pacman package versions, and caps private Docker builder cache at 20 GiB while
retaining 10 GiB for incremental rebuilds. The `storage-inventory` command
serializes filesystem counts inside the bounded-workload slice, and
`/srv/scratch` ages regenerable service-data scratch after 3 days.

It supersedes the older `eirikr-system-tuning` package and its own former name
`private-cachyos-system-tuning` (`provides`/`conflicts`/`replaces` for both).

## Migration from private-cachyos-system-tuning

The rename renames the package-owned units and paths: the timers
`custom-paccache-retention.timer` and `custom-docker-build-cache-retention.timer`,
the oneshot `custom-fast-swapfile.service`, `/usr/lib/custom-cachyos-system-tuning/`,
the oomd, journald, coredump, logind and sleep drop-ins, and the zswap tmpfiles
file. The swap unit keeps its path-derived name `srv-fasttmp-swapfile.swap`.

pacman removes the old package before it installs this one (libalpm
`_alpm_sync_commit` removes conflicting and replaced packages first), and the
old 1.11.0 `post_remove` runs in between. Measured from the installed scriptlet,
it disables its two timers, stops and disables `systemd-oomd.socket` (which
stops `systemd-oomd.service` through `Requires=`), reapplies the sysctl
baseline and reloads systemd. It runs neither `swapoff` nor `umount`; systemd
keeps active swap and mount units after their unit files disappear. This
package's `post_install` then retires the two old timer names, adopts
`/var/lib/private-docker-build-cache-retention` as the new StateDirectory,
reapplies the sysctl files, starts the swap unit (already active, so the
oneshot finds the existing swap area and exits) and restarts systemd-oomd. The
transient is the oomd gap and the cachyos-settings sysctl baseline for the
length of the transaction. The former oneshot `private-fast-swapfile.service`
stays loaded as not-found until reboot and is deliberately not stopped.

Install with `pacman -U` and answer `y` to the conflict question; `--noconfirm`
answers it with the default `N` and aborts the transaction. A sync-repository
`pacman -Syu` applies `replaces` without the question. Earlier backups named
`*.bak-private-cachyos-system-tuning` keep their names. The live
`/etc/sensors.d/tuf-b550-nct6798.conf` (3,664 bytes, dated 2025-12-25) is the
operator's earlier file that the first install kept, with the package copy
beside it as `.pacnew`. The removal saves the live file as `.pacsave` and this
package installs its own copy (4,276 bytes, with the DDR4 jc42 block), so labels
the operator file sets differently change at the rename. The jc42 limits read
75 and 85 degC live already, so `sensors -s` rewrites the same values.

## Target hardware

AMD Ryzen 5 5600X3D (6c/12t), 62.7 GiB of RAM (4 x 16 GiB, two kits, 3200 MT/s), root on a
Crucial P3 (QLC, DRAM-less, PCIe 3.0), fast partition on a Samsung 980 PRO (TLC
with DRAM, PCIe 4.0), kernel 7.3.x-cachyos, systemd 262. zswap (zstd, pool 25%
of RAM) caches compressed pages in front of the 980 PRO swapfile (priority 50)
and the root-disk swapfile (priority 10). zram is disabled. The pool limit is a
fraction of RAM, so it scales across a RAM change.
`SYSTEM.md` records the measured hardware and, per value, the justification and falsifier. `docs/SWAP_POLICY_RESEARCH.md` carries the measurements, sources, and
falsification tests behind this layout.

## What it sets, and why (each backed by research)

| Item | Decision | Evidence |
|------|----------|----------|
| VM reclaim and allocation reserve | **swappiness 150, VFS pressure 100, 256 MiB minimum free** | Reclaim prefers anonymous pages, which land compressed in the zswap pool, over compiler and source page cache. Upstream VFS pressure prevents inode and dentry slab from outrunning page-cache reclaim during full-tree scans. Wider watermarks and proactive compaction preserve contiguous kernel allocations for the display path. |
| Compressed tier | **zswap, zstd, pool 25% of RAM; zram disabled** | zram at priority 100 keeps whichever pages reached it first: with a 7.8 GiB zram full of desktop pages (kwin, krfb, portal), an Android build's hot heap swapped to the QLC disk at 50k major faults per second with the disk at 100% utilization. zswap's shrinker writes its coldest entries to disk and keeps recent pages compressed in RAM. Both changes are boot-only, so zram and zswap are never live together. |
| Disk tiers | **48 GiB on the 980 PRO** (prio 50), **16 GiB on the root disk** (prio 10, `/etc/fstab`) | A disk swap slot survives a read fault while total swap is under half full (`should_try_to_free_swap` in `mm/memory.c`), so a read-hot page stays on the device it was first written to; the fast device must be the one that fills first. The QLC tier is emergency capacity: a clean m8 build left it unused (`the swap snapshot of 20260925 (private notes, not published)`). |
| `systemd-oomd` swap guard | **90% backstop** | oomd kills only a cgroup holding more than 5% of total swap. With the Android build `omit`-exempt, a 40% limit logged 5,560 candidate lists in 23 minutes and killed nothing. Budgets on the workloads replace it. |
| Bounded system builds | **`bounded-build.slice`: 75% memory.high, 40 GiB swap max** | A system batch build run with `-p Slice=bounded-build.slice -p ManagedOOMPreference=avoid` is throttled before it pushes the desktop below a quarter of RAM, and above 20 GiB of swap the kernel frees its disk slots on swap-in. |
| Bounded interactive workloads | **50% high, 60% max, 12 GiB swap max** | `bounded-workload COMMAND...` launches a command in `bounded-workload.slice`, separating builds, VMs, debuggers, and analysis jobs from their terminal scope. The workload carries a higher kernel OOM preference than desktop applications, throttles at 50%, stops at 60%, and cannot consume more than 12 GiB of swap. |
| Filesystem inventory | **one scan, 3 GiB hard memory cap** | `storage-inventory OUTPUT DEPTH PATH...` uses a persistent lock, one-filesystem walks, low CPU and I/O weight, a 2 GiB soft limit, and the bounded-workload slice. Concurrent full-tree scans previously retained about 14 GiB of inode and dentry slab and fragmented the normal zone until NVIDIA DRM invoked global OOM. |
| Service scratch | **3-day `/srv/scratch` retention** | `/srv` is the FHS service-data namespace. `/srv/scratch` is local regenerable state rather than a CachyOS default, so a tmpfiles rule gives it explicit ownership, sticky permissions, and aging. Images that must outlive the window live in the device repositories; a job holding a BSD lock on its directory keeps that subtree. |
| Pacman cache retention | **Two versions, weekly** | Two cached versions preserve one rollback while preventing `/var/cache/pacman/pkg` from growing without a bound. The service skips an active Pacman transaction. |
| Docker builder cache retention | **20 GiB private-cache cap, 10 GiB reserve, daily** | Buildx caps private and reclaimable cache data while preserving 10 GiB for incremental rebuilds. Layers shared with retained images remain accounted under both surfaces and cannot be removed without removing the images. Images, containers, and volumes remain outside the service target. |
| mmap region ceiling | **`vm.max_map_count = 1048576`** | Arch `10-arch.conf` sets 1048576, and `60-elasticsearch.conf` (elasticsearch, a dependency of `python-flow.record`) sorts later and lowers it to 262144. `99-max-map-count.conf` sorts after both and restores the Arch value, which also satisfies elasticsearch's 262144 minimum. |
| `nf_conntrack_max=262144` | **Dropped** | Verifiably identical to the kernel's RAM-based auto-default on any 64-bit box above 4 GiB (htable caps at 262144). Live `nf_conntrack_count` was 112. Pure cargo-cult; left to the kernel. |
| IPv6 / IPv4 disable | **Dropped** | Both stay enabled. |
| coredump `suid_dumpable=0` override | **Dropped** | Live system uses the systemd default (`suid_dumpable=2`); the override was not in effect. |
| ML dirty-ratio / hung_task overrides | **Dropped** | `cachyos-settings` sets `vm.dirty_ratio = 10` and `vm.dirty_background_ratio = 3` in `70-cachyos-settings.conf` (live `dirty_bytes` reads 0), and `61-writeback-limits.rules` caps slow devices per device. A per-device cap for the QLC root waits on the writeback measurement plan in `SYSTEM.md`. |

## What it deliberately does NOT set (already optimal upstream)

- `kernel.pid_max = 4194304` - CachyOS `50-pid-max.conf`
- `fs.file-max = 2097152` - CachyOS `70-cachyos-settings.conf`
- `nofile` ulimit 524288 / systemd `DefaultLimitNOFILE=2097152`
- THP `madvise` (kernel command line, over the linux-cachyos Kconfig default `always`), THP `defrag=defer+madvise` (cachyos-settings `thp.conf`), MGLRU enabled (Kconfig) with `min_ttl_ms` 100 (no userspace writer found; the linux-cachyos build is the inferred source)

Overcommit and THP `always`-versus-`madvise` were left alone: no surviving
research claim quantified a win for this workload. `SYSTEM.md` carries the
full census of tunables in these domains, which file owns each, and the
measurement plans for the values only a load window can decide.

## Primary sources

- CachyOS-Settings: `70-cachyos-settings.conf`, `zram-generator.conf`,
  `30-zram.rules`, PR #22 (swappiness rationale) -
  https://github.com/CachyOS/CachyOS-Settings
- Chris Down, "zswap vs zram: when to use what" (2026) -
  https://chrisdown.name/2026/03/24/zswap-vs-zram-when-to-use-what.html
- Kernel admin-guide vm.rst (swappiness, MAX_SWAPPINESS=200) -
  https://docs.kernel.org/admin-guide/sysctl/vm.html
- `nf_conntrack` auto-sizing (kernel networking docs + nf_conntrack_core.c) -
  https://docs.kernel.org/networking/nf_conntrack-sysctl.html
- Fedora SwapOnZRAM (prio-100 zram, OOM-over-oversize philosophy) -
  https://fedoraproject.org/wiki/Changes/SwapOnZRAM

## Note on swappiness persistence

`vm.swappiness=150` is applied by the CachyOS zram udev rule only when a zram
device initializes, which no longer happens, so `/etc/sysctl.d/99-swap-reclaim.conf`
is the only source of the value; without it the static baseline of 100 applies.
