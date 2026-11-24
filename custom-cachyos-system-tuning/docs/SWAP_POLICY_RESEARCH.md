# Swap policy research: Ryzen 5 5600X3D workstation

The host does not run out of swap. It runs out of RAM, and the overflow goes to
the wrong device. During the Android build of 2026-09-22, swap held 27 of
128 GiB. `soong_build` ran with 2.1 GiB resident and 20 GiB swapped, taking
50,500 major faults per second. The Crucial P3 root disk sat at 99.98%
utilization serving 42,852 reads per second, and at least 84% of all swap-ins
came from the QLC `/swapfile`. The 980 PRO tier held 0.6 GiB. The systemd-oomd
swap guard at 40% never killed anything. Between 23:17:24 and 23:40:39 it
matched on its 150 ms check, logged 5,560 candidate lists (about 4 per
second), and found no eligible victim. The five kills in the retained journal
were memory-pressure kills of Konsole tabs, which Konsole itself opts into.

The recommended design makes three changes. zswap replaces zram. The 980 PRO
swapfile becomes the device that fills first and the QLC disk becomes
emergency capacity. Per-workload budgets (`MemoryHigh`, `MemorySwapMax`,
`ManagedOOMPreference=avoid`) replace the total-swap percentage. The draft
patch is `private-cachyos-system-tuning` 1.8.0 on branch `swap-policy-research`.

Measurements were taken read-only on 2026-09-22/23 with kernel 7.2.5-1-cachyos,
systemd 261.3, zram-generator 1.2.1, and 15.5 GiB RAM (half installed).
the swap snapshot of 20260923 (private notes, not published) holds the raw state at 00:05.

## Why oomd killed at 40%, and why that threshold fails

**Rationale when it was set.** Commit 56439eb (2026-08-24) moved
`SwapUsedLimit` from 85% to 40%. At that time the tiers were zram at 16 GiB
(ram/2 of 32 GiB) and the 72 GiB QLC swapfile, 88 GiB in total. Forty percent
of 88 GiB is 35 GiB, which allows about 19 GiB of QLC overflow after zram fills
before oomd acts. The goal was to kill the largest swap user before prolonged
QLC thrashing set in.

**Why a percentage of total swap measures the wrong thing:**

1. **It counts zram as if it were disk.** zram is RAM. A full zram means only
   1.8 GiB of RAM holds compressed pages. It says nothing about disk thrashing.
2. **It moves whenever a tier changes.** Adding the 48 GiB 980 PRO tier raised
   the trigger from 32 GiB to 51 GiB with no edit to the limit. Halving RAM
   moved it again.
3. **It measures capacity, not cost.** 27 GiB of swap is harmless when cold
   and fatal when read at 50k pages per second. Pressure stall information
   (PSI) and major-fault rates measure the cost. Swap occupancy does not.
4. **It needs a large victim.** systemd 261 kills only an eligible cgroup
   holding more than 5% of total swap (`THRESHOLD_SWAP_USED_PERCENT` in
   `src/oom/oomd-manager.h`; `oomd.conf(5)`: "eligible descendant control
   groups with swap usage greater than 5% of total swap"). At 23:17 the
   total was 79.8 GiB, so the bar was 4.0 GiB. The only cgroup above it was
   `android-build.service` (21.9 GiB), which is `ManagedOOMPreference=omit`.
   The largest bystander, `session-3.scope`, held 1.3 GiB. The guard therefore
   fired, dumped ten desktop candidates, killed nothing, and repeated on its
   `SWAP_INTERVAL_USEC` (150 ms) check for 23 minutes. The journal holds about
   4 dumps per second (5,560 over 1,395 s); journal rate limiting may have
   dropped some.
5. **An exemption turns the guard against bystanders.** When a bystander does
   cross 5%, it dies for pressure the exempt job created. Konsole tabs running
   LLM CLIs reach 0.5-0.8 GiB of swap, so on a smaller swap total they would
   qualify.

**What replaces it:**

- **Per-workload budgets.** `MemoryHigh` and `MemorySwapMax` on the slice that
  runs the heavy job, measured against that job's own `memory.peak` and
  `memory.swap.peak`.
- **`ManagedOOMPreference=avoid` instead of `omit`.** The build becomes the last
  candidate instead of an untouchable one.
- **A 90% backstop.** The upstream default fires only near true exhaustion.
- **PSI to detect thrashing.** Memory-pressure duration (`ManagedOOMMemoryPressure`,
  or a systemd 261 `OOMRules=` ruleset with `MemoryPressureAbove=` and
  `LastingSec=`) replaces swap occupancy as the signal.

## Findings

Each finding lists its claim, evidence, and source. Status is VERIFIED when a
measurement or a primary-source read confirms it, and UNVERIFIED otherwise.

### F1. zram fills while using a fraction of RAM (VERIFIED)

`mm_stat` shows 8,090,480,640 B of original data held in 1,916,605,049 B
compressed and 1,974,554,624 B of pool memory. That is 4.2:1, so 7.5 GiB is
stored in 1.84 GiB of RAM, 12% of 15.5 GiB. `disksize` is 8,323,072,000 B
(ram/2), so the device refuses pages once 7.75 GiB of uncompressed data is
stored. Incompressible pages are negligible: `huge_pages` is 3,337 pages, or
13 MiB. The README's justification for ram/2 (bound RAM use on
incompressible pages) matches this host's data only in the worst case, and a
separate control exists for it: `mem_limit`, exposed by zram-generator 1.2.1
as `zram-resident-limit=` (`zram-generator.conf(5)`).

### F1a. zram `mem_limit` cannot act as a tier boundary (VERIFIED from source)

`zram_can_store_page()` in `drivers/block/zram/zram_drv.c` (v7.2) returns false
past `limit_pages`. The write then fails with `-ENOMEM`, and
`__end_swap_bio_write()` in `mm/page_io.c` re-dirties the folio and logs
"Write-error on swap-device". The swap slot allocator keeps choosing the
priority-100 device, because nothing tells it the device is full. A larger
`disksize` capped by `zram-resident-limit` therefore produces write-error
churn, not a fall-through to the next tier. `mem_limit` is a safety cap, never
a sizing mechanism.

### F1b. zram writeback needs a partition and a timer (VERIFIED from docs; not applicable here)

The kernel zram guide (https://docs.kernel.org/admin-guide/blockdev/zram.html)
requires `backing_dev` to be a partition, set before `disksize`. Writeback
runs only when userspace writes `idle`, `huge`, or `huge_idle` to `writeback`.
The kernel has `CONFIG_ZRAM_WRITEBACK=y`, `CONFIG_ZRAM_TRACK_ENTRY_ACTIME=y`,
`CONFIG_ZRAM_MULTI_COMP=y`, and a new `compressed_writeback` attribute. The
980 PRO has no free partition: nvme0n1p5 is the 128 GiB ext4 fast partition
in use, 29 GiB free. zram writeback would need repartitioning or a loop device
over a file, plus a timer. zswap needs neither.

### F2. The 40% oomd swap guard is inert with an omitted build (VERIFIED)

The mechanism is covered in the previous section. The journal shows the first
candidate dump at 2026-09-22T23:17:24 and the last at 23:40:39. There are
5,560 "Considered ... cgroups" lines and zero "Marked ... for killing" lines
for swap. Source: systemd v261 `src/oom/oomd-manager.c`, lines 478-501. Kills
require memory used and swap used both above the limit, then
`oomd_select_by_swap_usage()` with `threshold = swap_total * 5 / 100`, and
"No cgroup candidates found" is logged at debug level.

This corrects the earlier reading of "40 s spent selecting". oomd selected
nothing for 23 minutes.

### F2a. The real kills were Konsole's own memory-pressure policy (VERIFIED)

The retained journal covers 49 boots, from 2026-09-16. It holds five
`Marked ... for killing due to memory pressure` events, on 09-18 15:18,
09-20 15:44, and 09-22 at 22:56, 23:16, and 23:29. Each victim was a
`tab(N).scope` under `app-org.kde.konsole-*.scope`, killed at 71-88% pressure
against the 60%/30 s default.

`libkonsoleprivate.so.26.08.1` carries the UTF-16 strings
`ManagedOOMMemoryPressure`, `app-%1-%2.scope`, and `tab(%1).scope`. Konsole
sets `ManagedOOMMemoryPressure=kill` on its app scope and runs each tab in its
own child scope. `oomctl` lists the Konsole scope as the only cgroup monitored
for memory pressure. No kernel OOM kill appears in the retained journal
(`oom_kill 0` this boot).

The patch leaves these kills alone. Their frequency is the falsifier for the
zswap change: less thrash means less tab pressure.

### F3. The QLC tier served the hot pages (VERIFIED, share is a bound)

The 10 s sample at 00:06 showed:

- `pswpin` at 54.1k pages/s, `pswpout` at 10.9k/s, and major faults at 54.5k/s.
- Device reads per second: nvme1n1p2 (QLC root) 50.7k, nvme0n1p5 (980 PRO)
  6.0k, zram0 2.4k.
- `iostat -x`: the QLC at 99.98% utilization with `r_await` 0.29 ms and
  194 MB/s of 4.5 KiB reads. The 980 PRO at 24% utilization with `r_await`
  0.06 ms.

QLC swap reads are at least pswpin minus every 980 PRO and zram read, which is
45.7k/s, or 84% of swap-ins. They are at most 94%, the QLC's total reads.
`plocate-updatedb` was active during the sample, so the QLC count includes
some file reads. The lower bound does not depend on that.

PSI io `some` avg300 was 33.3% and `full` 26.3%. PSI memory `some` avg300 was
3.6%, so I/O stall dominated.

### F4. Disk swap slots stay pinned to the device first written (VERIFIED from source and measurement)

`should_try_to_free_swap()` in `mm/memory.c` (v7.2) frees the swap slot on a
read fault only in three cases:

- the device is `SWP_SYNCHRONOUS_IO` (zram is, NVMe swapfiles are not);
- `mem_cgroup_swap_full()` is true;
- the page is mlocked, or the fault is an exclusive write.

`mem_cgroup_swap_full()` in `mm/memcontrol.c` (v7.2) returns true when global
swap is more than half used (`vm_swap_full()`). It also returns true when any
non-root ancestor cgroup's swap usage is at least half its `memory.swap.max`
or `memory.swap.high`.

With 128 GiB of total swap and 27 GiB used, neither condition held. A
read-mostly page keeps its QLC slot, and when it is evicted again, clean, it
is dropped without a write and stays on the QLC. `SwapCached` was 5.46 GiB
during the build, which is RAM holding pages whose slots were kept.

Two consequences follow:

- The 980 PRO tier added at 00:00 could not help the running build. `/swapfile`
  stayed at 18.7 GiB while being read at up to 50k pages/s. It dropped to
  0.66 GiB only when `soong_build` exited.
- More total swap makes pinning worse, because `vm_swap_full()` becomes harder
  to reach. A per-cgroup `MemorySwapMax` restores slot freeing for that
  workload once it passes half its budget.

### F5. The build's footprint exceeds RAM (VERIFIED)

`/sys/fs/cgroup/system.slice/android-build.service` reported a `memory.peak`
of 8,728,281,088 B (8.1 GiB) and a `memory.swap.peak` of 30,058,856,448 B
(28.0 GiB). The footprint was about 36 GiB on a 15.5 GiB host. `soong_build`
alone had a VSZ of 31.5 GiB, RSS of 2.1-6.5 GiB, and 20 GiB swapped. At
32 GiB of RAM the same job fits in RAM plus a compressed pool. It fits in a
compressed pool only if the pool holds the coldest pages, not the first ones.
Job 009 exited 1 on a Kati duplicate-module error, not a memory event.

### F6. zram above disk inverts the LRU (VERIFIED on this host)

zram took pages in arrival order, and early arrivals were long-lived desktop
pages. kwin_wayland held 1.3 GiB of swap, krfb 0.7 GiB, and
xdg-desktop-portal-kde 0.6 GiB. The build's hot heap then went to disk.

Chris Down (https://chrisdown.name/2026/03/24/zswap-vs-zram-when-to-use-what.html)
describes the same mechanism: "your fastest storage tier is clogged with the
coldest data, with no way to evict it". He concludes "If in doubt, prefer to
use zswap". zswap's shrinker (`shrinker_enabled=Y`, the kernel default here
via `CONFIG_ZSWAP_SHRINKER_DEFAULT_ON`) writes cold entries back to disk under
pressure.

### F7. Kernel and cmdline state for the switch (VERIFIED)

The kernel config is `CONFIG_ZSWAP=y`, `CONFIG_ZSWAP_DEFAULT_ON=y`,
`CONFIG_ZSWAP_COMPRESSOR_DEFAULT="zstd"`, and `CONFIG_ZSMALLOC=y`. zswap is off
for two reasons:

- `zswap.enabled=0` sits in `/etc/kernel/cmdline`, which the operator owns and
  no package owns.
- The cachyos-settings udev rule `30-zram.rules` writes `N` to
  `/sys/module/zswap/parameters/enabled` when zram0 initializes.

A zram-generator dry run (`ZRAM_GENERATOR_ROOT` in a scratch root holding the
cachyos `/usr/lib` config) creates `dev-zram0.swap` when no `/etc` file
exists. It reports "No devices configured, exiting" when
`/etc/systemd/zram-generator.conf` is comment-only. The package's `/etc` file
therefore shadows `[zram0] zram-size = ram` from cachyos-settings, and without
a zram device the udev rule never fires. A tmpfiles `w!` line applies at boot
only, the same pattern cachyos-settings uses in `thp.conf`.

### F8. MGLRU, THP, watermarks (VERIFIED where stated)

- **MGLRU** is enabled (`lru_gen/enabled 0x0007`, `min_ttl_ms 100`), and no
  kernel OOM has fired. It is left unchanged.
- **THP is not a factor.** THP is `madvise` with `defrag defer+madvise`.
  `AnonHugePages` is 0, `thp_swpout` is 0, and `thp_swpout_fallback` is 8.
  `khugepaged/max_ptes_swap` 64 matters only for THP-eligible regions, and
  there are none.
- **Watermarks** are unchanged. At `min_free_kbytes` 262144 and
  `watermark_scale_factor` 50, the Normal zone has min 52,391 pages and low
  68,635, a 63 MiB gap at 15.5 GiB. At 32 GiB the gap becomes about 160 MiB
  (0.5% of RAM).
- **Direct compaction is an open finding (UNVERIFIED cause).**
  `compact_stall` reads 16,113,561 and `compact_fail` 15,571,913 (97% failure)
  after 4 days, with `allocstall_normal` at 88,827. Tracing which allocation
  order and caller triggers it needs root. See Tooling.

### F9. swappiness above 100 and page-cluster (VERIFIED semantics, UNVERIFIED optimum)

`vm.swappiness` ranges from 0 to 200 (docs.kernel.org admin-guide
`sysctl/vm`). 100 means equal I/O cost for anonymous and file pages, and a
value above 100 says anonymous pages are cheaper to bring back. With zswap,
most swap-ins decompress from RAM, so 150 stays justified. It becomes wrong if
`zswpwb` (writeback to disk) dominates `zswpin`.

`page-cluster=0` disables swap readahead. `swap_ra` is 0 and `swap_ra_hit` is
11,821 since boot, so readahead contributes nothing measurable either way.

### F10. zstd vs lz4 on Zen 3 (UNVERIFIED)

No compressor benchmark ran on this host, so the patch keeps zstd, the kernel
default. zstd achieved 4.2:1 on this host's swap contents. The falsifier is
the zswap pool ratio: if `Zswapped/Zswap` in `/proc/meminfo` stays above 3:1
while swap-in latency, not pool capacity, limits the build, lz4 is worth a
trial.

## Recommended design, 32 GiB RAM (47 GiB as installed)

| Layer | Setting | Numbers and reason |
|---|---|---|
| Compressed tier | zswap on, zstd, `max_pool_percent=25`, shrinker on; zram off | The pool is 8 GiB of RAM at 32 GiB (11.7 GiB at 47 GiB), holding about 33 GiB (49 GiB) of anonymous pages at the measured 4.2:1. The build's 28 GiB swap peak fits. The shrinker keeps recent pages in the pool. Each pooled page holds a swap slot, so total swap bounds the pool as well (the swap snapshot of 20260925 (private notes, not published)). |
| Disk tier 1 | 980 PRO `/srv/fasttmp/swapfile` 48 GiB, prio 50 (unchanged) | zswap writeback and pool rejects land here: 0.06 ms `r_await`, PCIe 4.0, TLC with DRAM. |
| Disk tier 2 | QLC `/swapfile` 16 GiB, prio 10 (operator-owned, `/etc/fstab`) | Emergency capacity, reached only after the 48 GiB above is full; sized in the swap snapshot of 20260925 (private notes, not published). Stage 3 decides whether to remove it. |
| Build budget | `bounded-build.slice`: `MemoryHigh=75%`, `MemorySwapMax=40G`; unit runs with `ManagedOOMPreference=avoid` | 75% of 32 GiB is 24 GiB, which keeps 8 GiB for the desktop (35.2 GiB and 11.7 GiB at 47 GiB). 40G is 1.4x the measured swap peak. Above 20 GiB of swap, slots free on swap-in (F4). |
| User job budget | `bounded-workload.slice` (unchanged): 50% high, 60% max, 12 GiB swap | Already measured-safe for terminal-launched jobs. |
| oomd swap guard | `SwapUsedLimit=90%`, `-.slice ManagedOOMSwap=kill` | Backstop near exhaustion. With 64 GiB of disk swap, that is 57.6 GiB. |
| oomd pressure | unchanged (Konsole's own 60%/30 s) | Kept as the falsifier for the zswap change. |
| sysctl | swappiness 150, page-cluster 0, `min_free_kbytes` 256 MiB, `watermark_scale_factor` 50 (unchanged) | See F8 and F9. |

A build runner from another repository launches into this slice with
`systemd-run --unit=NAME --uid=$(id -u) --gid=$(id -g) -p Slice=bounded-build.slice
-p ManagedOOMPreference=avoid -p KillMode=control-group COMMAND`.

`avoid` is honored for root-owned cgroups, as `omit` is
(`systemd.resource-control(5)`). `MemorySwapMax=` alone would push reclaim onto
bystanders once the cap is hit, which is why it is paired with `MemoryHigh=`.

### 64 GiB note

At 64 GiB the same fractions give a 16 GiB zswap pool (about 67 GiB of
anonymous pages at 4.2:1) and `MemoryHigh` of 48 GiB. The measured 36 GiB build
footprint then fits in RAM plus pool. The QLC tier becomes removable, and a
48 GiB 980 PRO swapfile remains ample. No setting needs to change, because
every value is a fraction of RAM except the 40G swap budget.

### Alternatives evaluated and rejected

- **Larger zram (ram\*1.5 or ram\*2) with `zram-resident-limit`.** The LRU
  inversion remains (F6). At the resident cap, writes fail instead of falling
  through (F1a).
- **zram writeback to the 980 PRO.** It needs a free partition, which does
  not exist, and a userspace idle-marking timer. Pages come back through a
  4 KiB synchronous read (F1b).
- **Keeping three swap tiers under zram.** Slots pin to whichever device
  received the page (F4), so tier order decides placement once and never
  corrects it.

## Falsification tests

Each test states what is measured after the change and which result refutes
the recommendation.

1. **zswap replaces zram.** After the reboot, run an Android build and sample
   `/sys/kernel/debug/zswap/*` (root), `Zswap`/`Zswapped` in
   `/proc/meminfo`, and `zswpin`/`zswpout`/`zswpwb` from `/proc/vmstat` every
   60 s. Also record `iostat -x` for nvme0n1 and nvme1n1 and pidstat major
   faults for `soong_build`.
   - **Prediction:** most swap-ins are `zswpin`, the QLC stays under 20%
     utilization, and the build's major-fault rate stays below 10k/s at the
     same phase.
   - **Refuted if** `zswpwb` exceeds `zswpin` over the build, or QLC reads
     remain above 20k/s. In either case the pool is too small or the shrinker
     evicts hot pages: raise `max_pool_percent` to 35, then reconsider zram at
     `zram-size = ram` without disk tiers.
2. **Slot pinning (F4), Stage 0, operator-run.** During a build, when
   `/swapfile` use is below the 980 PRO free space, run
   `SUDO_ASKPASS=/usr/bin/unified-askpass sudo -A swapoff /swapfile`.
   - **Prediction:** nvme1n1 reads fall from about 50k/s to the file-read
     baseline, and nvme0n1p5 reads rise by the same order.
   - **Refuted if** QLC reads persist at the same rate after swapoff
     completes. The QLC load would then be file I/O, not swap.
3. **Build budget.** Run a build under `bounded-build.slice` and watch
   `memory.swap.current`, `memory.events` (`high` count), and the slice's
   `memory.pressure`.
   - **Prediction:** swap-in slots free above 20 GiB, so `SwapCached` stays
     below 1 GiB, and desktop cgroups keep their swap under 2 GiB.
   - **Refuted if** the `high` events stall the build for longer than the
     unbounded run's wall time (01:06:38 for job 009 to its failure point), or
     `memory.events` `max`/`oom_kill` appear.
4. **oomd backstop.**
   - **Prediction:** no "Considered ... cgroups" dumps without a following
     kill during a build (`journalctl -u systemd-oomd`).
   - **Refuted if** a dump loop recurs. That would mean a cgroup other than
     the build reached 90%, which is a sizing failure, not a policy
     success.
5. **Konsole pressure kills.**
   - **Prediction:** after zswap, Konsole tab kills fall from 5 in 7 days to
     0-1 under the same workload mix.
   - **Refuted if** the count stays at 5 or more. Tab pressure would then
     come from the tabs' own jobs, and those jobs belong in
     `bounded-workload`.
6. **swappiness 150.**
   - **Refuted if** `workingset_refault_file` per second exceeds
     `workingset_refault_anon` per second by more than 3x during builds
     while `zswpwb` is high. File cache would be the scarcer resource, and
     the value should drop to 100.

## Staged rollout

1. **Stage 0, now, no package change.**
   - Enable history: `systemctl enable --now sysstat.service
     sysstat-collect.timer sysstat-summary.timer`. The last `sa` file is from
     April.
   - Run falsification test 2 during the next build.
   - Change the `BUILD_HOST.md` command from `omit` to `avoid`. Until 1.8.0
     is installed, add `-p MemoryHigh=75% -p MemorySwapMax=40G` in place of
     the slice.
2. **Stage 1, install 1.8.0.** The oomd 90% backstop and `bounded-build.slice`
   take effect at once, since the `.install` reloads systemd and try-restarts
   oomd. The zram and zswap files stay inert until boot, and the running zram
   is untouched. The pacman tmpfiles hook runs `systemd-tmpfiles --create`
   without `--boot`, so it skips the `w!` lines. The live
   `/etc/systemd/zram-generator.conf` matches 1.7.0's checksum, so pacman
   replaces it without a `.pacnew`.
3. **Stage 2, the 32 GiB reboot.** zram is absent and zswap is on. First
   confirm the switch: `cat /sys/module/zswap/parameters/enabled` reads `Y`,
   `swapon --show` lists no `zram0`, and
   `journalctl -b -u systemd-tmpfiles-setup` shows no write error. Then run
   falsification tests 1, 3, and 4 on the first build. Remove
   `zswap.enabled=0` from `/etc/kernel/cmdline` and `/etc/default/limine`; the
   tmpfiles line overrides it, but the cmdline should not contradict the
   policy.
4. **Stage 3, after a week of sysstat and journal data.** If `/swapfile` stays
   unused, remove it from `/etc/fstab` and reclaim its 16 GiB on the root
   disk, weighing the oomd limit that 48 GiB of total swap leaves
   (the swap snapshot of 20260925 (private notes, not published), "Tier change"). If it fills, the 980 PRO
   tier or the pool is undersized.
5. **Rollback.** Reinstall 1.7.0-2. zram returns at the next boot, and the
   `.install` of 1.7.0 starts it at once.

## Tooling

Tools from `~/Documents/AI/Notes/1_TOOLS.md` and the base system that serve
this analysis. "Used" means it produced a measurement in this report.

| Tool (package) | Installed | Evidence it gives | Verdict |
|---|---|---|---|
| `iostat`, `pidstat`, `sar` (sysstat 12.8.0) | yes | Per-device r/s, `r_await`, util; per-process majflt/s; history when collection runs | Used (iostat, pidstat). History is off: `sysstat-collect.timer` is disabled and `/var/log/sa` ends in April. Enabling it is the cheapest history fix. |
| `/proc/vmstat`, `/proc/pressure/*`, cgroup `memory.*` files (kernel) | yes | pswpin/out, zswp*, compaction, PSI, per-cgroup swap and peaks | Used. |
| `zramctl`, `swapon` (util-linux 2.42.3) | yes | Per-device swap use, zram ratio | Used. |
| `oomctl`, `journalctl` (systemd 261) | yes | oomd limits, monitored cgroups, kill history | Used. |
| `biolatency`, `biotop`, `drsnoop`, `cachestat`, `oomkill` (bcc-libbpf-tools 0.37.0) | yes | Per-device I/O latency histogram (QLC vs 980 PRO), direct-reclaim latency per process, page-cache hit ratio, kernel OOM events | Not run: requires root. `sudo -A biolatency -D 10 1` and `sudo -A drsnoop -d 30` settle per-tier latency and reclaim stalls. |
| `bpftrace` 0.26.1 with `/usr/share/bpftrace/tools/swapin.bt` | yes | Swap-ins per process | Not run: requires root. `sudo -A bpftrace /usr/share/bpftrace/tools/swapin.bt` attributes swap-in to processes. |
| `perf` 7.2.6, `trace-cmd` 3.4, `kernelshark` | yes | Tracepoints `compaction:*`, `vmscan:*`, `swap` events; `perf trace -F maj` | Not run: requires root. `sudo -A trace-cmd record -e compaction:mm_compaction_try_to_compact_pages -e vmscan:mm_vmscan_direct_reclaim_begin sleep 30` finds the source of the 97% compaction failure rate (F8). |
| `perfetto` 58.2, `sysprof` 50, `lttng` 2.15, `systemtap` 5.5 | yes | Whole-system timelines with memory counters | Capable, redundant with trace-cmd for this question. |
| `nvme` (nvme-cli 3.0), `smartctl` (smartmontools 7.5) | yes | Wear (`percentage_used`, data units written) on the QLC under swap load | Not run: device nodes need root. Worth one reading before and after Stage 3. |
| `btop`, `htop`, `glances`, `nmon`, `iotop` | yes | Live views only | No history; not evidence. |
| `fio` 3.42 | yes | 4 KiB random-read latency per device | Useful for a tier baseline on an idle host; a write test on the QLC costs endurance, so read-only jobs only. |
| `gnuplot`, `duckdb`, `mlr`, `vd`, `sqlite3`, `python-pandas` | yes | Reduce sadf/CSV series into plots and tables | Use on sysstat output after Stage 0. |
| `atop` | no (extra 2.13.0) | Per-process history with swap and PSI, 10-minute samples, daily logs | Worth installing if per-process history is wanted. sysstat gives system-wide history only. |
| `below` | no (AUR 0.11.0, 2 votes) | Per-cgroup history incl. PSI and swap, the best fit for cgroup questions | Worth it only if atop proves insufficient. It is unofficial and low-review. |
| `smem` | no (not in the repos) | PSS/USS per process | Not needed; cgroup `memory.current` answers the same question. |
| `blktrace`, `ioping`, `iotop-c` | no | Block-layer traces, latency probe | `biolatency` covers them. |

## Sources

- systemd v261 `src/oom/oomd-manager.c` and `oomd-manager.h`:
  https://github.com/systemd/systemd/tree/v261/src/oom (`SWAP_INTERVAL_USEC`
  150000, `THRESHOLD_SWAP_USED_PERCENT` 5, `DEFAULT_SWAP_USED_LIMIT_PERCENT`
  90).
- `oomd.conf(5)` and `systemd.resource-control(5)` from systemd 261.3:
  `SwapUsedLimit=`, OOM rulesets, `ManagedOOMPreference=`, `OOMRules=`, and
  `MemorySwapMax=`.
- Linux v7.2 `mm/memory.c` (`should_try_to_free_swap`), `mm/memcontrol.c`
  (`mem_cgroup_swap_full`), `drivers/block/zram/zram_drv.c`
  (`zram_can_store_page`), and `mm/page_io.c`:
  https://github.com/torvalds/linux/tree/v7.2
- zram admin guide: https://docs.kernel.org/admin-guide/blockdev/zram.html
- `zram-generator.conf(5)` 1.2.1 (`zram-resident-limit`, `writeback-device`,
  config precedence).
- Chris Down, "Debunking zswap and zram myths" (2026):
  https://chrisdown.name/2026/03/24/zswap-vs-zram-when-to-use-what.html
- Kernel sysctl vm documentation:
  https://docs.kernel.org/admin-guide/sysctl/vm.html
