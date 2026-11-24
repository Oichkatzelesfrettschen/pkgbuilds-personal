# System specification and configuration rationale

This file records the hardware the package targets, the state measured on
2026-11-24, and, for each value the package sets, the value, its justification
and the observation that would show it wrong. Measurement outranks older
documentation; where they disagree the disagreement is listed.

## Target hardware

| Part | Measured or documented value | Source |
|---|---|---|
| CPU | AMD Ryzen 5 5600X3D, Zen 3 Vermeer (family 25, model 33, stepping 2), 6 cores, 12 threads, 1 NUMA node, microcode 0xa201213 | `lscpu` |
| Cache | L1d 32 KiB and L1i 32 KiB per core, L2 512 KiB per core, L3 96 MiB (one shared instance, 16-way) | `lscpu -C` |
| Clock | min 563.6 MHz, max 4455 MHz, `amd-pstate` status `active`, boost enabled | `lscpu`, `/sys/devices/system/cpu/amd_pstate/status` |
| Board | ASUS TUF GAMING B550-PLUS WIFI II, BIOS 3645, Nuvoton NCT6798D super-I/O | DMI `bios_version`; RE notes |
| Memory | four 16 GiB DDR4 modules in DIMM_A1, A2, B1, B2: two CMN32GX4M2Z3600C16 (XMP 3600) and two CMK32GX4M2A2666C16 (2666), all configured at 3200 MT/s, 1.2 V, no ECC; `MemTotal` 65726588 kB (62.7 GiB) | `dmidecode` (root read, serials removed), `/proc/meminfo` |
| NVMe 1 | Samsung 980 PRO 2 TB, TLC with DRAM, PCIe 4.0 x4 (16 GT/s), firmware 5B2QGXA7, 7% of rated endurance used | `nvme id-ctrl`, `nvme smart-log`, `lspci` |
| NVMe 2 | Crucial P3 4 TB (CT4000P3SSD8), QLC, DRAM-less (host memory buffer 8192), PCIe 3.0 x4 (8 GT/s), firmware P9CR30D, 32% of rated endurance used | same |
| SATA | Crucial MX500 1 TB, SATA 6 Gb/s, firmware M3CR046, mounted at `/srv/data` | `smartctl`, `lsblk` |
| GPU | NVIDIA GeForce RTX 4070 Ti (AD104) on PCIe x16; `lspci` reads 2.5 GT/s x16 (downgraded) at idle | `lspci` |
| Network | Realtek RTL8126 5 GbE, Realtek RTL8125 2.5 GbE, MediaTek MT7921 Wi-Fi | `lspci` |

The GPU link generation maximum is not measured: `nvidia-smi` failed with a
driver and library version mismatch on 2026-11-24, and the idle `lspci` reading
is a power-state value, so the maximum link speed stays unrecorded until the
driver is reloaded.

## Measured state, 2026-11-24

Every command ran read-only without privilege except the `dmidecode` and
`nvme` reads, which a prior privileged pass captured. Serial numbers, UUIDs and
the host name are removed.

```text
free -b            Mem 67304026112 total, 47857659904 used, 2779308032 free,
                   19072798720 buff/cache, 19446366208 available
swapon --show      /swapfile             file 17179865088 bytes  used 1101824     prio 10
                   /srv/fasttmp/swapfile file 51539603456 bytes  used 35012911104 prio 50
zswap parameters   enabled=Y compressor=zstd max_pool_percent=25
                   shrinker_enabled=Y accept_threshold_percent=90
/proc/meminfo      Zswap 2950240 kB holding Zswapped 14060672 kB (4.77:1)
                   SwapTotal 67108856 kB, AnonPages 37786936 kB
/proc/vmstat       zswpin 190588748, zswpout 475837039, zswpwb 131770312
                   pswpin 58141739 (counters since boot)
THP                enabled=madvise defrag=defer+madvise shmem_enabled=advise
block queues       nvme0n1 kyber (nr_requests 256, read_ahead 256 KiB)
                   nvme1n1 kyber (256, 256 KiB)
                   sda     mq-deadline (64, 256 KiB)
filesystems        /            rw,noatime,commit=60      size 3.93 TB, 55.7 GB free
                   /tmp, /var/tmp, /srv/fasttmp  rw,nosuid,nodev,relatime
                                128 GiB partition on the 980 PRO, 25.3 GB free
                   /srv/data    rw,nosuid,nodev,noatime   983 GB, 109 GB free
bounded-build.slice MemoryHigh=50478018560 MemoryMax=infinity MemorySwapMax=42949672960
sysctl             vm.swappiness 150, vfs_cache_pressure 100, page-cluster 0,
                   min_free_kbytes 262144, watermark_scale_factor 50,
                   compaction_proactiveness 20, max_map_count 1048576,
                   dirty_ratio 10, dirty_background_ratio 3,
                   fs.inotify.max_user_instances 1152, max_user_watches 647168
sensors (jc42)     two sensors, SMBus addresses 0x18 and 0x19, high 75 C, crit 85 C,
                   reading 37.0 C and 37.2 C
/etc/kernel/cmdline  rw iommu=pt amd-pstate=active transparent_hugepage=madvise
                   pcie_aspm=off pci=realloc mitigations=off split_lock_mitigate=0
                   nvme_core.default_ps_max_latency_us=0 libata.force=5:disable,6:disable
                   tsc=reliable reserve_mem=16M:4096:ramoops   (root= elided)
```

### Disagreements between measurement and older documentation

| Item | Older statement | Measured | Resolution |
|---|---|---|---|
| RAM capacity | 2 x 16 GiB kit (hardware notes); 47 GiB "installed" (package README and zswap comment); 15.5 GiB "half installed" (2026-09-23 snapshot) | 4 x 16 GiB from two kits, 62.7 GiB usable | The package targets 64 GiB. The 15.5 GiB and 47 GiB figures describe earlier states of the same machine; the documents keep them as history. |
| DIMM speed | XMP 3600 for the CMN kit | all four modules at 3200 MT/s | The CMK modules are 2666-rated, and four populated slots run below the XMP rate; 3200 MT/s is measured. |
| BIOS | 3631 in the hardware notes | 3645 | BIOS 3645 is current. |
| DIMM sensors | "two jc42 sensors" read as "all modules" | two sensors answer for four modules | The other pair exposes no readable sensor at 0x1a and 0x1b, or lacks the driver binding. The package limits apply to the two that answer. |
| Swap sizes | 48 GiB plus 16 GiB | 51539603456 and 17179865088 bytes, a 64 GiB total | Confirmed. |
| Schedulers | `kyber` for NVMe, `mq-deadline` for SATA from cachyos-settings | same | Confirmed. |
| inotify | package value 1152 instances | 1152 live (an earlier read of 1024 predates the install) | Confirmed. |
| `amd_iommu=on` | present on the 2026-06 command line | absent from `/etc/kernel/cmdline` | The kernel ignores the value "on"; the token was removed 2026-11-24. |

## Configuration values

Each section gives the value, the justification (measurement or document), the
falsifier, and the 2026-11-24 verdict. The reconciliation pass of the same day
(sections "Sources" through "Refuted claims" below) changed no live value: it
split the VM sysctls into one file per concern, pinned two values the running
kernel already holds, corrected three documentation claims, and moved the
values only a load window can decide into measurement plans.

### Swappiness 150

- Value: `vm.swappiness = 150` in `99-swap-reclaim.conf`.
- Justification: zswap pools compressed anonymous pages in RAM, so a swap-in
  usually decompresses from memory. A value above 100 tells reclaim that
  anonymous pages cost less to bring back than file pages (kernel
  `vm.rst`, range 0 to 200); `SWAP_POLICY_RESEARCH.md` carries the build
  measurements.
- Falsifier: `workingset_refault_file` per second above 3x
  `workingset_refault_anon` per second in a build window while `pswpin`
  carries most swap-ins. The earlier falsifier compared `zswpwb` with
  `zswpin`; `zswpwb` counts writes, so the swap-in source is `pswpin`
  against `zswpin`.
- Verdict: confirmed. Since boot (10.1 days) `zswpin` is 190.7 M against
  `pswpin` 58.2 M (77% of swap-ins from RAM) and the file-to-anon refault
  ratio is 2.19. A quiet 421 s window on 2026-11-24 was dominated by one 10 s
  burst (51,513 `pswpin` and 38,280 `zswpin`, a process faulting back pages
  written out earlier); outside that burst 23% of swap-ins read the disk. The
  disk reads come from the TLC 980 PRO, still cheaper than a QLC file read.

### VFS cache pressure 100, free-memory reserve and compaction

- Value: `vfs_cache_pressure = 100` (`99-vfs-cache-pressure.conf`);
  `min_free_kbytes = 262144` (256 MiB), `watermark_scale_factor = 50`,
  `watermark_boost_factor = 0`, `compaction_proactiveness = 20`
  (`99-free-memory-reserve.conf`).
- Justification: full-tree scans retained 14 GiB of dentry and inode slab under
  the CachyOS value of 50 and fragmented the normal zone until a 32 KiB NVIDIA DRM
  allocation hit global OOM (package README). At 62.7 GiB the reserve is 0.4% of
  RAM and `watermark_scale_factor = 50` spaces the watermarks by 0.5% of RAM
  (about 320 MiB), which is larger than the 32 KiB order-3 allocation that failed.
- Falsifier: an allocation-failure or compaction-stall message for an order-3 or
  higher request in `dmesg`, or `Slab` (8.0 GB now, of which `KReclaimable` 6.5 GB)
  growing past a quarter of RAM during a scan.
- Verdict: confirmed. Zero "page allocation failure" lines in the kernel log
  window (2026-11-21 to 2026-11-24; the journal holds 3.3 days).

### Swap read-ahead off

- Value: `vm.page-cluster = 0` (`99-swap-reclaim.conf`; cachyos-settings sets
  the same value).
- Justification: zswap loads one page per fault; neighboring-slot reads
  decompress pages nobody asked for. `swap_ra_hit` of 11,821 against zero use
  recorded in the research notes.
- Falsifier: `swap_ra_hit` in `/proc/vmstat` growing in step with `pswpin` under
  a sequential swap-in workload.
- Verdict: confirmed.

### mmap region ceiling

- Value: `vm.max_map_count = 1048576`.
- Justification: the Arch default; `60-elasticsearch.conf` lowers it to 262144
  and sorts earlier than `99-max-map-count.conf`.
- Falsifier: `sysctl vm.max_map_count` reading anything but 1048576 after boot.
- Verdict: confirmed (1048576 live).

### zswap and no zram

- Value: zswap enabled, zstd, `max_pool_percent = 25`, shrinker on; zram
  declared empty in `zram-generator.conf`.
- Justification: zram at higher priority than disk keeps the first pages that
  reach it; zswap's shrinker writes the coldest entries back and keeps recent
  pages in RAM (`SWAP_POLICY_RESEARCH.md`, F6). The 25% cap is 15.7 GiB at
  62.7 GiB. The pool holds 2.95 GB for 14.06 GB of pages, a 4.77:1 ratio, so the
  cap stays far from binding (19% of the cap used). The 4.2:1 ratio of the earlier
  measurement and 4.77:1 today both support zstd.
- Falsifier: `Zswapped/Zswap` staying above 3:1 while swap-in latency limits a
  build (lz4 trial, F10), or `Zswap` reaching 15.7 GiB (the cap).
- Verdict: confirmed for zstd, the cap and zram off. The pool needs about 19%
  of its cap, so 25% leaves room for the 28 GiB build peak: 28 GiB at 4.77:1 is
  5.9 GB. The shrinker is contested: later in the day the pool held 1.0 GB
  while 17 GB sat in disk slots, 62% of the boot's writeback came from
  bounded.slice (throttled at memory.high 1.79 M times), and one 10 s burst in a
  quiet window read 51,513 pages back from disk; plan M1 decides it.

### Swap tiers

- Value: 48 GiB swapfile on the 980 PRO partition at priority 50 with
  `discard`; 16 GiB `/swapfile` on the P3 root at priority 10 (operator-owned,
  `/etc/fstab`). Total 64 GiB, 1.02 times RAM.
- Justification: a swap slot survives a read fault while total swap is under half
  full, so the fast device must fill first (`mm/memory.c`,
  `should_try_to_free_swap`). The 980 PRO (TLC, DRAM, PCIe 4.0) outruns the
  DRAM-less QLC P3 under small random I/O. The fast partition is 128 GiB with 25.3 GB
  free; the swapfile is preallocated by `fallocate`, so its 48 GiB is already
  counted in that free figure and cannot compete with /tmp for space later.
- Falsifier: `/swapfile` (P3) usage above 1% while the 980 PRO swapfile has free
  slots (priority order broken), or `SwapFree` under 10% of `SwapTotal`.
- Verdict: confirmed. Used swap is 35.0 GB on the 980 PRO (68%) and 1.1 MB on the
  P3.

### systemd-oomd swap backstop

- Value: `SwapUsedLimit = 90%` and `ManagedOOMSwap=kill` on `-.slice`.
- Justification: oomd acts only when memory and swap both exceed the limit and
  kills only a cgroup holding over 5% of total swap. With 64 GiB of swap the limit
  sits at 57.6 GiB. Budgets on the workloads, not this limit, bound pressure.
- Falsifier: a 40%-style limit's symptom, an oomd candidate dump repeated without a
  kill, or a global kernel OOM with swap under 90% used.
- Verdict: confirmed.

### bounded-build.slice

- Value: `MemoryHigh = 75%`, `MemorySwapMax = 40G`, no `MemoryMax`.
- Justification: 75% of 62.7 GiB is 47.0 GiB (measured 50478018560 bytes),
  leaving 15.7 GiB for the desktop. 40 GiB is 1.43 times the 28 GiB
  Android-build swap peak and 62.5% of total swap, so one build cannot take every
  slot. Above 20 GiB slots free on swap-in (`mem_cgroup_swap_full`).
- Falsifier: a build stalling on `memory.high` throttling (slice
  `memory.events` `high` count rising with PSI `full` above a few percent), or
  the desktop losing memory while a build runs.
- Verdict: confirmed. 5192 `high` throttles during the 2026-09-25 build left
  PSI `some` at 0.109%.

### bounded-workload.slice and storage-inventory

- Value: `MemoryHigh 50%`, `MemoryMax 60%`, `MemorySwapMax 12G`, oomd pressure
  kill at 70% for 30 s; `oom_score_adj 500` in the launcher; `storage-inventory`
  capped at 2 GiB high, 3 GiB max, 2 GiB swap.
- Justification: 50% is 31.4 GiB and 60% is 37.6 GiB of 62.7 GiB, below the
  47.0 GiB build budget, so an interactive job cannot starve a system build.
  The inventory cap bounds the scan that once pinned 14 GiB of slab.
- Falsifier: a workload killed by the 60% cap while below its measured working
  set, or a scan reaching 3 GiB.
- Verdict: confirmed.

### Scratch directory

- Value: `/srv/scratch` sticky, 3-day retention.
- Justification: regenerable job output; `/` mounts `noatime`, so reads do not
  extend life. Root has 55.7 GB free of 3.93 TB (98.6% full).
- Falsifier: root free space under 20 GB with scratch holding aged entries.
- Verdict: confirmed, with a watch item on root free space.

### inotify ceilings

- Value: `max_user_instances = 1152`, `max_user_watches = 647168`.
- Justification: the larger of the KDE survey and LLM-lab values; git fsmonitor
  daemons hold one instance each. Both live values match the file.
- Falsifier: an `EMFILE` or "no space left on device" watch failure while the
  count is under the ceiling, or the ceilings read lower than the file after boot.
- Verdict: confirmed.

### Board sensors

- Value: NCT6798D labels, unused inputs ignored; DDR4 `jc42` high 75 C, crit 85 C.
- Justification: JEDEC DDR4 modules rate 85 C case temperature; the limit
  registers power up at 0 C and raise alarms at any reading. Both live sensors read
  37 C with the limits applied.
- Falsifier: a sensor alarm below 75 C, or the limits reading 0 after boot (the
  `lm_sensors.service` apply step failed). Two sensors answer for four modules;
  the two without a reading are not covered.
- Verdict: confirmed for the two sensors that answer.

### journald, coredump, logind and sleep

- Value: journal 1.5 GiB, 128 MiB files, one month; coredumps 2 GiB per dump, 1 GiB
  total, 1 GiB kept free; idle action and suspend, hibernate keys ignored;
  suspend, hibernate, hybrid sleep refused.
- Justification: the 50 MiB baseline held about two boots, and a boot regression
  surfaced several boots later. The machine serves remote builds and CI while
  unattended, and an idle suspend drops them.
- Falsifier: `journalctl --disk-usage` at the cap before one month elapsed, root
  free space falling under the coredump `KeepFree`, or the machine suspending.
- Verdict: journald retention refuted by its own falsifier. On 2026-11-24 the
  journal held 1012M and its oldest entry was 3.3 days old (about 310 MB a
  day; warp-svc wrote 70k lines in 24 hours), so `SystemMaxUse=1G` binds long
  before one month and the kernel log of the current boot (started 2026-11-14)
  is already gone. Owner decision of 2026-11-24 (D3): "Quiet the noisy
  services and raise to 1.5GiB". `SystemMaxUse=1536M` and per-unit rate
  limits follow; coredump, logind and sleep are confirmed.

#### Journal sources, 2026-11-21 to 2026-11-24

Measured with `journalctl -S -3d -o json`, grouped by `_SYSTEMD_UNIT` and,
inside `user@1000.service`, by `_SYSTEMD_USER_UNIT`. Total: 1,839,747 entries,
472 MB of `MESSAGE` text; 1020M on disk.

| Unit | Manager | Lines | Message bytes | PRIORITY | Shape | Action |
|------|---------|-------|---------------|----------|-------|--------|
| app-dev.lizardbyte.app.Sunshine.service | user | 1,418,386 | 110 MB | all 6 | one burst: 9 hours on 2026-11-22 at about 197,500 lines an hour, a device probe loop ("/dev/dri/card1 -> nvidia-drm") | operator decision D7 |
| warp-svc.service | system | 181,367 | 336 MB | all 6 | steady, 63k to 74k a day | rate limit, 10 per 10 min |
| llm-ollama-runtime.service | user | 112,254 | 5.6 MB | all 6 | steady, 2,915 lines an hour: a repeating BrokenPipeError traceback | operator decision D7 |
| vmware-usbarbitrator.service | system | 34,734 | 4.4 MB | all 6 | steady, USB enumeration status | rate limit, 10 per hour |
| ollama-local.service | user (home unit) | 30,408 | 4.0 MB | - | steady | below the cut; unit lives in the home directory |
| kernel | - | 12,104 | 1.3 MB | mixed | - | none |

Every heavy unit logs at PRIORITY 6 because each writes its own levels to
stdout as text, so `LogLevelMax=info` drops nothing and `notice` drops every
line. A rate limit keeps the first lines of each window and journald logs a
"Suppressed N messages" line, so the rate stays observable. journald scales
each burst by 1 to 6 from free journal space (journald.conf(5)). Per-unit
limits reach journald only for system units: `unit_export_state_files()` in
src/core/unit.c (systemd v258) returns before exporting log settings when the
manager is not the system manager, and journald-context.c reads them from
`/run/systemd/units/` keyed by the system unit. A drop-in on a user unit would
therefore be inert, and the two user units go to D7.

Predicted effect: warp-svc falls from about 112 MB of message text a day to at
most about 13 MB, vmware-usbarbitrator to at most 1,440 lines a day, and the
journal grows by at most about 60 MB a day without a Sunshine burst, so 1536M
spans weeks and `MaxRetentionSec=1month` binds. Falsifier: M7 below showing
the cap reached within 14 days, or warp-svc above 8,640 lines a day.

### KSM off

- Value: `/sys/kernel/mm/ksm/run` 2 at boot (ksmd.service runs `ksmctl -d`),
  `MemoryKSM=no` on user@.service, gdm.service and getty@.service.
- Layering: cachyos-ksm-settings 5-1 enables KSM through ksmd.service (enabled
  symlink, `ksmctl -e` writes run=1) and `10-ksm.conf` drop-ins with
  `MemoryKSM=yes`. This package overrides at both layers with
  `90-custom-cachyos-system-tuning.conf` drop-ins, which sort after `10-`.
- Measured cost, 2026-11-24, 10.2 days of uptime: ksmd CPU 4 h 17 min (1.76% of
  one thread); general_profit 268 MiB (0.4% of RAM); pages_sharing 355 MiB;
  pages_volatile 4.8 GiB rescanned without merging; cow_ksm 32.0 million
  copy-on-write breaks; ksm_swpin_copy 1.9 million.
- Justification: the saving is 0.4% of RAM, while the scan costs a steady CPU
  share and every write to a merged page takes a copy-on-write fault. zswap
  compresses cold anonymous pages at 4.2:1 or better and recovers more memory
  than KSM's merging on this workload.
- Falsifier: run reading 1 after a boot; MemAvailable lower by more than
  268 MiB at a comparable load.

### Pacman and Docker retention

- Value: `paccache --keep 2` weekly; `docker buildx prune --max-used-space 20GB
  --reserved-space 10GB` daily.
- Justification: two cached versions give one rollback without unbounded growth on
  a root with 55.7 GB free; the builder cache is derived from Dockerfiles.
- Falsifier: `/var/cache/pacman/pkg` growing past the two-version footprint, or a
  rebuild missing a layer within the reserved 10 GB.
- Verdict: confirmed.

### Block I/O scheduler (package ships none)

- Value: the cachyos-settings defaults, `kyber` on both NVMe drives and
  `mq-deadline` on the MX500.
- Justification: the 2026-11-01 A/B (`docs/IO_SCHEDULER_AB_20261101.md`) found no
  alternative beating the baseline by more than 5% with non-overlapping ranges.
  The P3 result is inconclusive because the drive is QLC and 93% full; at 98.6%
  now, the same limit holds.
- Falsifier: a repeat with a warm-up pass and Latin-square rotation showing a
  scheduler more than 5% ahead with non-overlapping ranges on a drive.
- Verdict: confirmed (measured schedulers equal the defaults).

### Transparent huge pages

- Value: `madvise` (kernel command line); `defrag = defer+madvise`.
- Justification: huge pages apply to allocators that ask for them; the 96 MiB L3
  and 62.7 GiB of RAM give no measured gain for `always`.
- Falsifier: a benchmark with `always` beating `madvise` by more than 5%, or
  `thp_fault_fallback` dominating `thp_fault_alloc`.
- Verdict: confirmed (`madvise` live); no measured claim favors `always`.

### Fast temporary directories (separate package)

- Value: `/tmp` and `/var/tmp` bind from the 980 PRO partition, mounted
  `nosuid,nodev`; `/var/tmp` entries age after 2 days.
- Justification: the root disk is a 93%-full QLC drive; large temporary
  workloads belong on the TLC drive. The partition holds 107.4 GB used.
- Falsifier: the partition filling, which would also leave the swapfile intact
  since its space is preallocated.
- Verdict: confirmed, with a watch item: 25.3 GB free of 128 GiB.

## Kernel command line

`/etc/kernel/cmdline` is unowned by any package. Each token and its reason:

| Token | Reason | Falsifier |
|---|---|---|
| `rw` | mount root read-write | root mounting read-only |
| `iommu=pt` | passthrough mode keeps IOMMU translation off the DMA path of host devices; reason not recorded in the sources examined | a DMA mapping cost measured with `iommu=pt` removed |
| `amd-pstate=active` | selects the EPP driver (status reads `active`) | status reading `passive` or `guided` |
| `transparent_hugepage=madvise` | see THP section | `always` measurably faster |
| `pcie_aspm=off` | reason not recorded in the sources examined | a link stability or power result with ASPM enabled |
| `pci=realloc` | reason not recorded in the sources examined | BAR allocation failures when removed |
| `mitigations=off` | the operator disabled speculative-execution mitigations for performance (host security posture note); a deliberate trade | a measured throughput difference under 2% |
| `split_lock_mitigate=0` | reason not recorded in the sources examined | split-lock throttling observed when set to 1 |
| `nvme_core.default_ps_max_latency_us=0` | disables NVMe autonomous power-state transitions (APST reads Disabled on the P3) | a latency or stall difference with the default |
| `libata.force=5:disable,6:disable` | SATA6G_5 and SATA6G_6 are unusable while M.2_2 holds an NVMe drive (board specification) | the ports working with M.2_2 populated |
| `tsc=reliable` | reason not recorded in the sources examined | clocksource watchdog events when removed |
| `reserve_mem=16M:4096:ramoops` | reserves memory for the pstore ramoops crash log, which survives a hard reset | no `dmesg-ramoops` record after a panic |
| `amd_iommu=on` | removed 2026-11-24: the kernel ignores the value "on" | not applicable |
| `zswap.enabled=0` | absent; the zswap tmpfiles file enables the tier at boot | not applicable |

## Sources

Evidence classes: M measurement on this host (read-only), P primary
documentation, I implementation source or installed configuration, C
commentary. All read 2026-11-24 unless stated. The docs.kernel.org pages
render 7.4.0-rc4 while the running kernel is linux-cachyos 7.3.3. The v7.3 tag
of each document was fetched from the kernel's GitHub mirror and the quoted
phrases grepped there: vm.rst lines 878, 1077-1081 and 1132-1147;
multigen_lru.rst 69-77; transhuge.rst 183-191; cgroup-v2.rst 1385, 1873 and
1920-1926; zswap.rst 109-131.

| Id | Source | Read | Class |
|---|---|---|---|
| S1 | docs.kernel.org admin-guide/sysctl/vm (swappiness, page-cluster, watermark_*, min_free_kbytes, compaction_proactiveness, dirty_*, vfs_cache_pressure); v7.3 `Documentation/admin-guide/sysctl/vm.rst` | 2026-11-24 | P |
| S2 | docs.kernel.org admin-guide/mm/zswap; v7.3 `zswap.rst` | 2026-11-24 | P |
| S3 | docs.kernel.org admin-guide/mm/multigen_lru, "Thrashing prevention" | 2026-11-24 | P |
| S4 | docs.kernel.org admin-guide/mm/transhuge, "sysfs" defrag modes, khugepaged | 2026-11-24 | P |
| S5 | docs.kernel.org admin-guide/cgroup-v2, memory.high, memory.swap.max, memory.zswap.writeback | 2026-11-24 | P |
| S6 | `mm/zswap.c` v7.3: max_pool_percent 20, accept_thr 90, shrinker nr_disk_swapins protection, pool_limit_hit | 2026-11-24 | I |
| S7 | `mm/page_alloc.c` v7.3: watermark_boost_factor 15000, min_free_kbytes = int_sqrt(lowmem * 16) clamped to 262144 | 2026-11-24 | I |
| S8 | `mm/vmscan.c` v7.3: lru_gen_min_ttl defaults to 0; lru_gen_age_node() calls out_of_memory() from kswapd when every generation is younger than min_ttl | 2026-11-24 | I |
| S9 | `mm/swapfile.c` v7.3: discard_swap() walks swap extents; SWAP_FLAG_DISCARD sets area and page discard, DISCARD_ONCE keeps area only | 2026-11-24 | I |
| S10 | Arch Wiki Zswap, revision 2026-10-10 (`action=raw`) | 2026-11-24 | C |
| S11 | Arch Wiki Swap, revision 2026-08-23, "Swappiness" | 2026-11-24 | C |
| S12 | Arch Wiki Sysctl, revision 2026-10-28, "Virtual memory" | 2026-11-24 | C |
| S13 | Arch Wiki Improving performance, revision 2026-09-07, "Input/output schedulers" | 2026-11-24 | C |
| S14 | cachyos-settings 1:1.4.5 installed files: `70-cachyos-settings.conf`, `thp.conf`, `thp-shrinker.conf`, `60-ioschedulers.rules`, `61-writeback-limits.rules`, `30-zram.rules`, `zram-generator.conf`, `system.slice.d/10-oomd-per-slice-defaults.conf`, `session.slice.d/10-ignore-session-slice.conf`, `00-journal-size.conf`, `system.conf.d/10-limits.conf` | 2026-11-24 | I |
| S15 | CachyOS/kernel-patches `cachy.patch` (6.6 to 6.9 series) via code search: watermark_boost_factor initialized to 0; `le9uo` patches touch lru_gen_min_ttl. The 7.3 patch was not read, so the 7.3 attribution is an inference | 2026-11-24 | I |
| S16 | linux-cachyos 7.3.3 `/proc/config.gz`: ZSWAP_DEFAULT_ON, ZSTD, SHRINKER_DEFAULT_ON, TRANSPARENT_HUGEPAGE_ALWAYS, LRU_GEN_ENABLED, PSI, KSM, MQ_IOSCHED_ADIOS | 2026-11-24 | I |
| S17 | Live state, 10.1 days of uptime: sysctl, sysfs, `/proc/vmstat`, `/proc/meminfo`, PSI, cgroup `memory.stat`, `/proc/diskstats`, journal | 2026-11-24 | M |
| S18 | `tools/swap-sample`, 421 s quiet window, `docs/zswap-writeback-sample-20261124/swap-sample.csv` | 2026-11-24 | M |
| S19 | `docs/SWAP_POLICY_RESEARCH.md`, the 2026-09 swap snapshots (private notes, not published), `docs/IO_SCHEDULER_AB_20261101.md` | 2026-09 to 2026-11 | M |
| S20 | terminal tab-scope OOM drop-in (private package): `ptyxis-spawn-.scope.d` and `tmux-spawn-.scope.d/10-tab-scope-oom.conf` | 2026-11-24 | I |
| S21 | Chris Down, "zswap vs zram: when to use what" (2026-03-24), cited through S19, not re-read | 2026-09 | C |
| S23 | Kernel commit b5ba474f3f518701249598b35c581b92a3c95b48, "zswap: shrink zswap pool based on memory pressure" (the change the Arch Wiki links; read through the GitHub API in place of the blocked lore thread): memcg- and NUMA-aware shrinker, warm-region protection, 14% to 35% less kernel CPU time in a memory-limited kernel build with cold tmpfs data | 2026-11-24 | P |
| S24 | CachyOS-Settings README at the repository head: says sysctl sets dirty_bytes, dirty_background_bytes and dirty_writeback_centisecs, while installed 1:1.4.5 sets ratios (S14) | 2026-11-24 | C |
| S25 | CachyOS wiki, "General system tweaks" (last updated 2026-07-26): adios example udev rule for SSD and NVMe; zswap in place of zram through kernel parameters | 2026-11-24 | C |
| S22 | Owner document trees (technical, public, private): `rg -il` for zswap, multigen, min_ttl, swappiness, watermark_boost, dirty_background, page-cluster, memory.high matched only general operating-systems texts; nothing decisive | 2026-11-24 | null |

Blocked: the lore.kernel.org zswap shrinker series (HTTP 403; S23 stands in).
Not attempted: the CachyOS forum, the Arch BBS, and vendor QLC endurance
documents. No claim below rests on them. S22 searched the owner's three document trees.

## Reconciliation per value

Recommendations: K kernel default, D kernel documentation, A Arch Wiki, C
CachyOS, P this package. "Refuted" names the source whose mechanism or target
does not hold here.

| Value | Recommendations | Mechanism | Verdict | Chosen | Falsifier |
|---|---|---|---|---|---|
| vm.swappiness | K 60; D above 100 for zswap or swap faster than the filesystem (133 at 2x); A 100 or more when zswap caches swap I/O; C 100 (150 only under zram); P 150 | anon:file reclaim cost ratio (200 - s):s | K and C refuted for this hardware by D's own cost model: 77% of swap-ins decompress from RAM, the rest read TLC, file reads hit QLC | 150 | file:anon refault rate above 3:1 in a build window with pswpin dominant |
| vm.page-cluster | K 3; D 0 disables readahead; C 0 (comment: 1 for SSD swap); P 0 | readahead of adjacent swap slots | C's SSD comment targets plain disk swap, not a zswap front; survives | 0 | swap_ra_hit tracking pswpin under sequential swap-in |
| vm.vfs_cache_pressure | K 100; D warns above the denominator; A and C 50; P 100 | dentry/inode slab reclaim weight | A and C refuted for this workload: 14 GiB slab and a fragmentation OOM under 50 (S19) | 100 | KReclaimable above 25% of RAM during a scan |
| vm.min_free_kbytes | K about 32 MiB here; D "too high will OOM"; P 256 MiB | free reserve for atomic and high-order allocations | survives at 0.4% of RAM | 262144 | order-3 or higher allocation failure in the kernel log |
| vm.watermark_scale_factor | K 10 (0.1%); P 50 | kswapd starts 0.5% of RAM above min | survives | 50 | allocstall rate rising while kswapd is idle |
| vm.watermark_boost_factor | K 15000; C kernel 0; P none, now pinned 0 | post-fragmentation boost reclaims up to 150% of high watermark | unproven either way: compact_stall 8.46 M with 12% success since boot, zero allocation failures in the 3.3-day log | 0 (pin of live) | M4 |
| vm.compaction_proactiveness | K 20; P 20 | background compaction toward a fragmentation score | default adequate, pinned | 20 | none measured; the upstream default |
| vm.dirty_ratio, dirty_background_ratio | K 20/10; A 10/5, or 3 for large RAM; C 10/3; P none | throttling and flusher thresholds of dirtyable memory (bdi max_bytes reads 4.4 GB) | C survives globally; a QLC-only cap is unproven (M3); the 5 s diskstats sample showed 13 writes against 2626 reads on the QLC | C 10/3 | M3 |
| zswap enabled, compressor | K (Kconfig) Y, zstd; A example lz4; P Y, zstd | compression ratio against decompress latency | lz4 unproven: zstd holds 4.2 to 4.8:1 and the pool never nears its cap | Y, zstd | pool ratio above 3:1 while swap-in latency, not capacity, limits a build |
| zswap max_pool_percent | K 20; A example 30; P 25 | pool cap as a fraction of RAM | A's 30 buys nothing here: 25% at 4.5:1 already holds more pages than the 64 GiB of slots | 25 | Zswap reaching 25% of MemTotal |
| zswap accept_threshold_percent | K 90; D hysteresis, 100 disables | refill hysteresis after the cap binds | default adequate (cap never binds) | 90 | pool_limit_hit rising |
| zswap shrinker_enabled | D "disabled by default"; K (Kconfig) Y; A enabled by default, saves CPU on cold pages; P Y | memcg-aware writeback with nr_disk_swapins protection | undecided, kept at the build default: 62% of zswpwb is bounded.slice, whose memory.events shows 1.79 M memory.high throttles, and one 10 s burst in a quiet window read 51,513 written-back pages from disk (23% of swap-ins outside it) | Y | M1 |
| zram | C zram-size = ram at priority 100; P none | zram is a swap device filled in arrival order | C refuted on this host (S19 F6: cold desktop pages held zram while the build heap went to QLC) | none | a zswap-era build with QLC swap reads above 10% of swap-ins |
| swap tiers, priorities | P 980 PRO 48 GiB prio 50, QLC 16 GiB prio 10 | priority order, slot pinning below vm_swap_full | survives: QLC tier holds 1 MB | as is | QLC tier above 1% used with free 980 PRO slots |
| swap discard | 980 PRO unit Options=discard; QLC fstab none | discard_swap() and per-cluster discard reach swapfile extents (S9) | 980 PRO survives; QLC gap (decision D1) | as is | D1 |
| MGLRU enabled | K (Kconfig) 0x0007 | multi-generation LRU | default adequate | 0x0007 | none needed |
| lru_gen min_ttl_ms | K 0; D 1000 for desktops without oomd, 3000 risks premature OOM; C kernel 100 (inferred) | kswapd calls out_of_memory() when every generation is younger than min_ttl | D's 1000 targets hosts without oomd; this host runs oomd, so the narrower 100 stays | 100 (set elsewhere) | a CONSTRAINT_NONE OOM kill invoked from kswapd |
| THP enabled | K (Kconfig) always; operator cmdline madvise | huge pages only where madvised | adequate: thp_fault_alloc 17.9 M, fallback 6.4% | madvise | no measured gain claim for always |
| THP defrag | D and K madvise; C defer+madvise (tcmalloc guidance) | both stall madvised regions in direct compaction; C also wakes kcompactd for others | unproven (M5) | defer+madvise (C) | M5 |
| I/O scheduler | A example none for NVMe; C kyber NVMe, mq-deadline SATA; CachyOS wiki adios (S25); P none | queueing and latency targets | A and the wiki's adios unproven here: the 2026-11-01 A/B kept adios within 6% of kyber on the 980 PRO, none raised the 980 PRO mixed read p99 by 16%, and the P3 result was inconclusive (S19) | C | repeat A/B with warm-up beating C by more than 5% |
| oomd SwapUsedLimit | K 90%; earlier P 40% | kill when memory and swap both exceed the limit, victim above 5% of swap | 40% refuted (S19 F2: 5,560 candidate dumps, no kill) | 90% | a candidate-dump loop without a kill |
| bounded-build.slice | P MemoryHigh 75%, MemorySwapMax 40G | throttle plus per-cgroup swap-full slot freeing | survives | as is | memory.events high rising with PSI full above a few percent |
| journald SystemMaxUse | C 50M; P 1G | size cap against time cap | P's month claim refuted: 3.3 days | 1536M with rate limits on warp-svc and vmware-usbarbitrator | D3 decided |

## Tunable census

Status: here (this package), elsewhere (file and owning package), default
(kernel or systemd default judged adequate, with the reason), gap (decision or
plan). Every value is a live read of 2026-11-24.

| Domain | Tunable | Live | Status |
|---|---|---|---|
| VM | swappiness, page-cluster | 150, 0 | here, `99-swap-reclaim.conf` |
| VM | vfs_cache_pressure | 100 | here, `99-vfs-cache-pressure.conf` |
| VM | vfs_cache_pressure_denom | 100 | default: 100 makes vfs_cache_pressure 100 the neutral weight |
| VM | min_free_kbytes, watermark_scale_factor, watermark_boost_factor, compaction_proactiveness | 262144, 50, 0, 20 | here, `99-free-memory-reserve.conf` |
| VM | max_map_count | 1048576 | here, `99-max-map-count.conf` |
| VM | extfrag_threshold | 500 | default: kernel default, no measured fragmentation failure |
| VM | zone_reclaim_mode, numa_balancing | 0, Kconfig y | default: one NUMA node |
| VM | overcommit_memory | 0 | default: heuristic overcommit; builds rely on it |
| VM | stat_interval | 1 | default |
| Writeback | dirty_ratio, dirty_background_ratio | 10, 3 | elsewhere, `70-cachyos-settings.conf` (cachyos-settings) |
| Writeback | dirty_expire_centisecs, dirty_writeback_centisecs | 3000, 500 | default; ext4 `commit=60` on / is operator fstab |
| Writeback | bdi strict_limit, max_bytes | 0 on NVMe | elsewhere for slow devices, `61-writeback-limits.rules` (cachyos-settings); gap for the QLC root, M3 |
| zswap | enabled, compressor, max_pool_percent, shrinker_enabled | Y, zstd, 25, Y | here, tmpfiles `custom-cachyos-system-tuning-zswap.conf` |
| zswap | accept_threshold_percent | 90 | default: cap never binds |
| zswap | memory.zswap.writeback, memory.zswap.max per cgroup | 1, max | default; decision D5 for interactive cgroups |
| Swap | 980 PRO swapfile, priority 50, discard | 48 GiB | here, `srv-fasttmp-swapfile.swap` |
| Swap | QLC /swapfile, priority 10 | 16 GiB | elsewhere, operator `/etc/fstab`; discard gap, D1 |
| zram | device | none | here, `/etc/systemd/zram-generator.conf` shadows cachyos-settings |
| THP | enabled | madvise | elsewhere, operator kernel command line over Kconfig always |
| THP | defrag, khugepaged/max_ptes_none | defer+madvise, 409 | elsewhere, `thp.conf`, `thp-shrinker.conf` (cachyos-settings); M5 |
| THP | shmem_enabled, khugepaged/defrag, max_ptes_swap | advise, 1, 64 | default: no userspace writer found |
| MGLRU | enabled, min_ttl_ms | 0x0007, 100 | elsewhere, linux-cachyos build (Kconfig; min_ttl source inferred) |
| KSM | run, MemoryKSM on user@, gdm, getty@ | 2, no | here, `ksmd.service.d/90-custom-cachyos-system-tuning.conf` and `<unit>.d/90-custom-cachyos-system-tuning.conf` over cachyos-ksm-settings `10-ksm.conf` |
| cgroup | DefaultMemoryAccounting | yes | default (systemd) |
| cgroup | user@.service Delegate | cpu cpuset io memory pids | elsewhere, `delegate.conf` (cachyos-settings) |
| cgroup | bounded-build.slice, bounded-workload.slice | 75%/40G, 50%/60%/12G | here |
| cgroup | terminal tab scopes | MemoryMax 16G, MemorySwapMax 2G | elsewhere, the terminal tab-scope OOM drop-in (private package) |
| cgroup | PSI | enabled | default (Kconfig PSI=y) |
| oomd | SwapUsedLimit | 90% | here, `oomd.conf.d/95-custom-cachyos-system-tuning.conf` |
| oomd | DefaultMemoryPressureLimit, duration | 60%, 30s | default (systemd) |
| oomd | ManagedOOMSwap=kill | -.slice, system.slice | here (-.slice); elsewhere (system.slice, cachyos-settings) |
| oomd | ManagedOOMMemoryPressure | system.slice 80%; bounded-workload 70% 30s | elsewhere (cachyos-settings); here (bounded-workload) |
| oomd | ManagedOOMPreference | session.slice omit; tab scopes avoid | elsewhere (cachyos-settings; the terminal tab-scope OOM drop-in) |
| Block | scheduler | kyber, kyber, mq-deadline | elsewhere, `60-ioschedulers.rules` (cachyos-settings) |
| Block | nr_requests, read_ahead_kb, wbt_lat_usec | 256, 256, 2000 | default |
| Block | NVMe APST | disabled | elsewhere, operator kernel command line |
| Block | filesystem TRIM | fstrim.timer enabled | elsewhere (util-linux timer) |
| Files | inotify instances, watches | 1152, 647168 | here, `99-inotify-limits.conf` |
| Files | fs.file-max | 2097152 | elsewhere twice: `70-cachyos-settings.conf:44` and `99-network-performance.conf:41` (eirikr-network), same value |
| Files | DefaultLimitNOFILE | 2048:2097152 system, 1024:1048576 user | elsewhere, `system.conf.d`, `user.conf.d/10-limits.conf` (cachyos-settings) |
| Files | kernel.pid_max | 4194304 | elsewhere, `50-pid-max.conf` (systemd) |
| journald | SystemMaxUse, SystemMaxFileSize, MaxRetentionSec | 1536M, 128M, 1month | here, over `00-journal-size.conf` (cachyos-settings) |
| journald per-unit | LogRateLimitIntervalSec, LogRateLimitBurst | 10min/10 (warp-svc), 1h/10 (vmware-usbarbitrator) | here, `<unit>.service.d/50-custom-cachyos-system-tuning.conf` |
| coredump | Storage, sizes, MaxUse, KeepFree | external, 2G, 1G, 1G | here |
| coredump | kernel.core_pattern | systemd-coredump | elsewhere, `50-coredump.conf` (systemd) |

## Overlap trace

systemd-sysctl reads `/etc`, `/run`, `/usr/local/lib` and `/usr/lib`
`sysctl.d`; a file name in `/etc` shadows the same name in `/usr/lib`,
and across names files apply in lexical order, so the last assignment wins.
systemd drop-ins apply in lexical order across directories with `/etc`
winning a name tie. Boot order for sysfs values: Kconfig default, kernel
command line, then `systemd-tmpfiles --boot` and udev writes.

| Key | Setters in load order | Live | Owner and resolution |
|---|---|---|---|
| vm.swappiness | `70-cachyos-settings.conf:4` 100; `30-zram.rules:13` 150 on zram0 init (inert, no zram); `99-swap-reclaim.conf:29` 150 | 150 | this package |
| vm.page-cluster | `70-cachyos-settings.conf:20` 0; `99-swap-reclaim.conf:30` 0 | 0 | this package; kept because the rationales differ (zram against zswap) and the cachyos comment points to 1 for SSD swap |
| vm.vfs_cache_pressure | `70-cachyos-settings.conf:8` 50; `99-vfs-cache-pressure.conf:16` 100 | 100 | this package |
| vm.max_map_count | `10-arch.conf:8` 1048576; `60-elasticsearch.conf:1` 262144; `99-max-map-count.conf:11` 1048576 | 1048576 | this package |
| fs.inotify.* | `10-arch.conf:3-4` 1024, 524288; `99-inotify-limits.conf:8-9` 1152, 647168 | 1152, 647168 | this package |
| vm.watermark_boost_factor | page_alloc.c 15000; CachyOS patch 0; `99-free-memory-reserve.conf:31` 0 | 0 | this package pins the live value |
| fs.file-max | `70-cachyos-settings.conf:44`; `99-network-performance.conf:41` | 2097152 | outside this package; eirikr-network repeats the cachyos value (decision D6) |
| kernel.nmi_watchdog, kernel.panic | `20-panic-sysctls.conf:15` -1; `70-cachyos-settings.conf:28` 0; `99-panic-readable.conf:7,20` 10 and 1 | 10, 1 | outside this package; eirikr-crash-forensics wins deliberately |
| zswap parameters | Kconfig; command line (absent); `30-zram.rules:14` N (inert); tmpfiles lines 41-44 | Y, zstd, 25, Y | this package; only max_pool_percent differs from Kconfig |
| zram device | `/usr/lib/systemd/zram-generator.conf:1-3` zram0 = ram; `/etc/systemd/zram-generator.conf` empty | none | this package; zram-generator reads only the first file found |
| THP enabled, defrag | Kconfig always; cmdline madvise; `thp.conf:3` defer+madvise | madvise, defer+madvise | operator (enabled), cachyos-settings (defrag) |
| ManagedOOMSwap | `-.slice.d/10-managed-oom-swap.conf` kill; `system.slice.d/10-oomd-per-slice-defaults.conf:2` kill | kill on both | nested, see below; the root entry is the one that covers user.slice and bounded.slice |
| journald SystemMaxUse | `00-journal-size.conf:2` 50M; `50-custom-cachyos-system-tuning.conf` 1536M | 1536M | this package |
| I/O scheduler | `60-ioschedulers.rules:7,11` | kyber, mq-deadline | cachyos-settings; this package ships none |

## Nested layers and feedback loops

1. Memory limits nest by cgroup path. `bounded-build.slice` runs at
   `/bounded.slice/bounded-build.slice`: systemd creates the parent
   `bounded.slice` from the dashed name and gives it no limit, so the child
   limit is the effective one. Terminal tabs run at
   `user@UID.service/app.slice/<tab>.scope` with MemoryMax 16G and
   MemorySwapMax 2G (S20); `bounded-workload.slice` sits beside them under
   the user manager with 50% high, 60% max and 12G swap. No ancestor of either
   carries a limit, so each leaf budget is the binding one.
2. Swap slots, zswap pool and reclaim form one loop. Reclaim at swappiness 150
   picks anonymous pages; each stored page takes a slot on the highest-priority
   device with space and a zswap entry. Reclaim inside a cgroup (its own
   memory.high or memory.max) or global reclaim runs the memcg-aware shrinker,
   which writes entries to their slots (zswpwb) and frees pool memory. A fault
   on a written-back page reads the disk (pswpin) and adds to nr_disk_swapins,
   which exempts that many entries from the next shrink pass (S6). The loop
   stabilizes when disk refaults raise the protection until writeback stops
   evicting the working set. A slot frees on swap-in only when global swap is
   half used or a cgroup reaches half its swap.max (2G tabs at 1G, builds at
   20G, global at 32G), so below those points written-back pages keep their
   disk slots. The pool cap (25%) holds more than the slot capacity, so slots,
   not the cap, bound the tier; at slot exhaustion zswap cannot store and
   reclaim falls to file pages.
3. Swap "used" includes zswap entries, so oomd's SwapUsedLimit (90% of 64 GiB)
   and each cgroup's MemorySwapMax count pages that sit compressed in RAM.
   Measured: a terminal tab scope read `memory.swap.current` 1023 MB with
   `zswapped` 863 MB and a lifetime `zswpwb` of 2,497 pages (10 MB), so at
   least 853 MB of its swap charge is pool-resident.
4. Kill paths, outermost last: a memcg OOM at a leaf MemoryMax (all 11 kills in
   the 3.3-day log are CONSTRAINT_MEMCG in transient scopes; vmstat oom_kill
   reads 130 for the 10.1-day boot, which includes the rotated part);
   oomd memory-pressure kills (bounded-workload 70% for 30 s, system.slice
   80%); oomd swap kills at 90% memory and 90% swap, victim above 5% of swap
   (3.2 GiB, which the 2G tab budget keeps tabs under); the MGLRU min_ttl
   kswapd OOM; and the allocator's global OOM.
5. ManagedOOMSwap=kill on `-.slice` and on `system.slice` both reach the same
   descendants under system.slice; the root entry alone reaches user.slice and
   bounded.slice. The duplicate is harmless and lives in cachyos-settings.

## Measurement plans

Each runs on a build host or in a maintenance window, never as a load test on
this workstation. Root-only reads are marked.

- M1 zswap shrinker. Arms: shrinker Y against N (runtime write, root), one
  Android build each from a warm ccache, same tree. Counters per build:
  zswpin, zswpout, zswpwb, pswpin deltas; PSI memory some and full total
  deltas; build wall time; bounded.slice `memory.events` high;
  `/sys/kernel/debug/zswap/pool_limit_hit` (root); 980 PRO
  `data_units_written` (root). N wins if PSI full falls 10% or more, wall
  time does not rise, and pool_limit_hit stays 0. The 421 s quiet sample
  (S18: pswpin 55,155, zswpin 50,209, zswpwb 852, PSI full avg10 peak 2.36)
  is the idle baseline; one 10 s interval carries 93% of its pswpin, so M1
  compares per-interval distributions, not window totals.
- M2 swappiness. Arms 150 against 100 and 180 across three builds each;
  counters workingset_refault_file and workingset_refault_anon rates, pswpin,
  PSI memory full, wall time.
- M3 QLC writeback cap. Arm: `bdi/strict_limit=1` and `max_bytes=1 GiB` on
  the P3 (sysfs, root, reversible) against none, five build cycles each.
  Counters at 1 s: Dirty and Writeback from `/proc/meminfo`, PSI io full,
  nvme1n1 write sectors and in-flight from `/proc/diskstats`, `git commit`
  and `pacman -Sy` wall times. Predicted with the cap: lower PSI io full
  peaks, earlier writer throttling. A win becomes a udev rule keyed on the
  P3 model, mirroring `61-writeback-limits.rules`.
- M4 watermark boost. Arms 0 against 15000; counters compact_stall,
  compact_fail, allocstall_*, pgsteal_kswapd, workingset_refault_file, PSI
  memory, and any "page allocation failure" line, over one week each.
- M5 THP defrag. Arms defer+madvise against defer; counters compact_stall per
  thp_fault_alloc, thp_fault_fallback, PSI memory some, build wall time.
  First identify the madvising processes (`hg` in VmFlags of
  `/proc/PID/smaps`, own processes readable without root).
- M6 QLC write budget. nvme1n1 wrote 5.73 TB in 10.1 days (567 GB a day,
  `/proc/diskstats`) at 32% of rated endurance used. Weekly
  `data_units_written` deltas (root) and per-process `write_bytes` from
  `/proc/PID/io` attribute the writers; decision D2 follows.
- M7 journal rate. Daily `journalctl --disk-usage` and per-identifier line
  counts; decision D3 follows.

## Refuted claims

| Claim | Where | Refutation |
|---|---|---|
| cachyos-settings sets dirty_bytes 256M and dirty_background_bytes 64M | README, and the CachyOS-Settings README (S24) | installed `70-cachyos-settings.conf` sets dirty_ratio 10 and dirty_background_ratio 3; live dirty_bytes is 0 (S14, S17) |
| 1G of journal holds about a month of boots | journald comment, this file | 1012M spans 3.3 days (S17) |
| watermark_scale_factor and the inotify limits are left alone | README | this package sets both |
| nf_conntrack_max is left to the kernel auto-default | .install | eirikr-network sets 262144 |
| the shrinker writes the coldest entries and keeps recent pages in the pool | zswap header | narrowed, not refuted: the v7.3 shrinker walks a per-memcg LRU with a second-chance referenced bit and exempts as many entries as recently refaulted from disk (S6), so it writes the oldest entries of the cgroup under reclaim; whether it keeps disk refaults rare is open: one 10 s burst in a quiet window read 51,513 written-back pages from disk (S18) |
| zswpwb against zswpin falsifies swappiness | this file | zswpwb counts writes; the swap-in source is pswpin against zswpin |
| vfs_cache_pressure 50 (Arch Wiki Sysctl example, cachyos-settings) | S12, S14 | 14 GiB of slab and a fragmentation OOM on this workload (S19) |
| zram at priority 100 (cachyos-settings) | S14 | LRU inversion on this host (S19 F6) |
| an oomd SwapUsedLimit of 40% | earlier package | 5,560 candidate dumps and no kill (S19 F2) |
| max_pool_percent 30 (Arch Wiki example) | S10 | above 25% the slots bind first on this host |
| min_ttl_ms 1000 (multigen_lru) | S3 | scoped to hosts without oomd; narrowed, not refuted |
| "the zswap shrinker is disabled by default" | S2 | true of upstream Kconfig; linux-cachyos builds SHRINKER_DEFAULT_ON (S16) |

## Decisions for the operator

- D1: add `discard=once` to the QLC `/swapfile` line in `/etc/fstab`, or
  retire that tier (1 MB used). The swapon-time discard (S9) tells the drive
  that the file's 16 GiB of written blocks hold no data, which frees them for
  its garbage collection on a filesystem 98.6% full; how much the P3's
  cache behavior gains is vendor behavior this record did not read.
- D2: move build outputs and caches off the QLC root (567 GB a day of writes,
  M6) to the 980 PRO or a compute host.
- D3 (decided 2026-11-24): 1536M with rate limits on the two noisiest system
  units; see "Journal sources".
- D4 (decided 2026-11-24, "Turn KSM off"): see "KSM off" above.
- D5: `memory.zswap.writeback=0` (systemd `MemoryZSwapWriteback=no`) on
  interactive cgroups would keep desktop pages in RAM and leave writeback to
  builds; S2 warns that repeated store failures then make reclaim inefficient.
  Run M1 first.
- D7: the two noisy user units. A package drop-in cannot limit them (only
  the system manager exports log settings). Sunshine: its burst was a 9-hour
  device probe loop; `min_log_level` in the user's Sunshine configuration, or
  a fix of the loop, quiets it at the source. llm-ollama-runtime: a
  BrokenPipeError traceback repeats about 2,900 lines an hour, a defect in
  llm-lab's runtime rather than a logging setting; fixing it in llm-lab
  removes the noise. A rate limit on `user@1000.service` would throttle every
  user unit together and is not recommended.
- D6: eirikr-network repeats the cachyos `fs.file-max`; dropping it there
  leaves one owner.
