# Storage memo: swap, partitions, cache homes and block sizes

Status: decision memo for the owner, 2026-11-24. Nothing in this package
changes partitions, `/etc/fstab` or swap; each option below names what it
would change, its cost, its risk, its justification and its falsifier. The
measurements are read-only (`lsblk -b`, `df -B1`, `findmnt`, `stat -f`,
`/proc/swaps`, `/proc/meminfo`, `/sys/block/*/queue`, partition start and
size from `/sys/class/block`) plus the root-only facts captured earlier the
same day (NVMe `id-ctrl` fields and SMART wear).

## Owner requests, verbatim

- "rescope and research online with optimal performance stats, cachyos and
  archlinux best practice, to have the 980 Pro swap be the same size as RAM
  available vs. otherwise items and present the decisions for what survives to
  optimize based upon RAM, disks and partitions available and remembering the
  windows disk is what it is but is more durable/reliable"
- "decide how all items are partitioned, block size, etc across the board"

## Inventory

RAM: MemTotal 65,726,588 kB (62.7 GiB), four 16 GiB DDR4 modules. Swap total
64 GiB; at measurement 17.3 GiB used on the 980 PRO file, 1 MB on the root
file; the zswap pool held 4.0 GiB of pages in 1.0 GiB.

| Device | Bus, NAND | Wear (SMART percentage_used) | Logical / physical sector | Partitions |
|--------|-----------|------------------------------|---------------------------|------------|
| Samsung 980 PRO 2 TB (nvme0n1, 2,000,398,934,016 B) | PCIe 4.0 x4 (16 GT/s), TLC, DRAM | 7% | 512 / 512 | p1 EFI 100 MiB; p2 MSR 16 MiB; p3 NTFS 1,799,331,250,176 B (Windows data, 1,223 GB used, 576 GB free, mounted read-only by the desktop automounter); p4 NTFS 862 MiB (Windows recovery); p5 ext4 "linux-fast" 128 GiB at /srv/fasttmp |
| Crucial P3 4 TB (nvme1n1, 4,000,787,030,016 B) | PCIe 3.0 x4 (8 GT/s), QLC, DRAM-less (HMB 32 MiB) | 32% | 512 / 512 | p1 vfat 2 GiB /boot; p2 ext4 3.998 TB / |
| Crucial MX500 1 TB (sda, 1,000,204,886,016 B) | SATA 6 Gb/s, TLC, DRAM | not captured | 512 / 4096 | p1 ext4 "data" /srv/data |

Free space and filesystems:

| Mount | Device | Size | Available | Block size | Inodes used | Options |
|-------|--------|------|-----------|------------|-------------|---------|
| / (and /home) | P3 p2 ext4 | 3,934.7 GB | 34.1 GB (df 100%) | 4096 | 36.0 M of 244.1 M | noatime, commit=60 |
| /srv/fasttmp, /tmp, /var/tmp | 980 p5 ext4 | 134.1 GB | 25.1 GB | 4096 | 0.48 M of 8.4 M | nosuid, nodev, relatime |
| /srv/data | MX500 p1 ext4 | 983.3 GB | 109.2 GB | 4096 | 1.1 M of 61.1 M | noatime, nosuid, nodev, nofail |
| /boot | P3 p1 vfat | 2.1 GB | 1.8 GB | 4096 | - | umask 0077 |

Swap areas: `/srv/fasttmp/swapfile` 48 GiB, priority 50, discard
(srv-fasttmp-swapfile.swap); `/swapfile` 16 GiB on the QLC root, priority 10
(`/etc/fstab`). Hibernation is not in use: this package's
`sleep.conf.d` drop-in refuses suspend and hibernate, so the classic reason to
size swap at RAM (holding the hibernation image) does not apply here.

### Unallocated space on the 980 PRO

The 980 PRO's partitions end before the disk does. p5 spans sectors
3,516,923,904 to 3,785,359,359; the disk has 3,907,029,168 sectors, so
121,669,808 sectors after p5 (62.3 GB, 58.0 GiB, less the 33-sector backup
GPT) are unallocated and adjacent to p5. A further 600,064 sectors (293 MiB)
lie between p4 and p5. This space is the cheapest route to swap = RAM on the
TLC drive: it needs neither an NTFS shrink nor a smaller `/tmp`. Its origin
is not recorded; confirm that nothing reserves it (a planned Windows or
recovery partition) before using it.

### Alignment and block size

- Every partition starts on a 1 MiB boundary (start sector times 512 is a
  multiple of 1,048,576 for all eight partitions), so every 4 KiB filesystem
  block maps to whole NAND pages as far as the drives report them.
- All three ext4 filesystems use 4096-byte blocks, equal to the page size, so
  page-cache writeback and swap I/O issue whole blocks.
- Both NVMe drives expose 512-byte logical blocks (`queue/logical_block_size`).
  The Arch Wiki (Advanced Format, read 2026-11-24) describes switching an NVMe
  namespace to a 4096-byte LBA format with `nvme format --lbaf` when
  `nvme id-ns -H` lists one with better "Relative Performance"; the format
  erases the namespace. The LBA format list was not captured (`nvme id-ns`
  needs root), so whether either drive offers 4096 is unknown. With 4 KiB
  filesystem blocks on 1 MiB aligned partitions, the drive already receives
  4 KiB-aligned requests; the remaining gain of a 4Kn format is smaller
  mapping tables in the controller, which no measurement here quantifies.
- The MX500 reports 4096-byte physical sectors behind 512-byte logical ones;
  1 MiB alignment and 4 KiB blocks already match it.
- Discard: `fstrim.timer` runs weekly; the 980 swapfile mounts with
  `discard` (both swapon-time and per-cluster trimming, swapon(8)); the QLC
  `/swapfile` has none (SYSTEM.md decision D1).

Decision on block size and partition geometry: no change. Every layer already
uses 4 KiB units on 1 MiB boundaries, and the only remaining lever (4Kn LBA
format) destroys data and has no measured benefit here. Falsifier: `nvme
id-ns -H` showing a 4096-byte format rated better than the 512-byte format in
use, which would justify a 4Kn format at the next reinstall of that drive.

## Sources

| Id | Source | Read | Claim used |
|----|--------|------|------------|
| A1 | Arch Wiki, Partitioning, section Swap (raw page) | 2026-11-24 | "Swap files and swap partitions are equally performant, but swap files are much easier to resize as needed." A sane default size is 4 GiB; for hibernation, swap at the size of RAM. |
| A2 | Arch Wiki, Swap, sections Swap file, Priority, Discard (raw page) | 2026-11-24 | Higher-priority areas fill first; equal priorities round-robin; discard per swapon(8). |
| A3 | Arch Wiki, Solid state drive, section swap | 2026-11-24 | `discard` without a mode enables both `once` and `pages`. |
| A4 | Arch Wiki, Advanced Format | 2026-11-24 | NVMe LBA format selection by Relative Performance; `nvme format` erases data. |
| K1 | docs.kernel.org, admin-guide/mm/zswap | 2026-11-24 | zswap evicts LRU pages to the backing swap device when the pool is full; the shrinker writes cold pages back proactively. |
| C1 | CachyOS wiki, General system tweaks | 2026-11-24 | CachyOS defaults to zram; its zswap recipe uses a swapfile with `max_pool_percent=30`; it gives no swap-size, block-size or partitioning guidance. |
| P1 | This package, zswap.conf and SYSTEM.md | 2026-11-24 | Each zswap entry holds a slot on a swap device, so total swap slots bound the compressed tier (pool cap 15.7 GiB at 4.2:1 to 4.8:1 holds 66 to 75 GiB of pages). |

Vendor endurance ratings (TBW) were not read: the Samsung and Crucial product
pages refused automated fetches. The SMART wear figures above are the measured
substitute: the QLC root has used 32% of its rated life, the 980 PRO 7%.

## Swap options

The question is how many swap slots exist and on which drive they live. Swap
slots bound zswap (P1), so the 64 GiB total sets how much compressed memory the
host can hold, even for pages that never reach disk. Writeback put about 540 GB
through the 980 file in 10 days (SYSTEM.md), so the drive that holds the slots
takes real writes.

### S0: keep 48 GiB on the 980 and 16 GiB on the QLC root

- Change: none.
- Cost: none. The QLC file holds 16 GiB of the 99%-full root.
- Risk: when the 980 file fills, swap spills to the QLC drive (32% worn,
  DRAM-less) at the moment the host is most loaded.
- Justification: measured use is 17.3 GiB on the 980 and 1 MB on the QLC file;
  the second tier has not been needed in this sample.
- Falsifier: `/swapfile` used above 1 GiB in any sample, or the 980 file above
  44 GiB (90%).

### S1: grow the 980 swapfile to 64 GiB inside the current p5

- Change: swapoff the 980 file, re-create it at 64G, swapon; retire the QLC file.
- Cost: 16 GiB more of p5, leaving about 8 GB for /tmp and /var/tmp.
- Risk: /tmp at 8 GB free breaks large builds and archive extraction (ENOSPC);
  the swapoff pages up to the in-use amount back into RAM.
- Justification: swap = RAM on the TLC drive with no partition change.
- Falsifier: /tmp writes failing with ENOSPC, or p5 available below 5 GB.
- Verdict: refuted by the free space; /tmp loses two thirds of its room.

### S2: grow p5 into the 58 GiB that follows it, then a 64 GiB swapfile

- Change: extend p5 to the end of the disk (`growpart` or `parted resizepart`,
  then `partx -u`), grow ext4 online with `resize2fs` (ext4 supports online
  growth of a mounted filesystem), re-create the 980 swapfile at 64 GiB, then
  retire the QLC `/swapfile` and its fstab line.
- Cost: one maintenance window; no data moves; NTFS untouched.
- Result: p5 about 186 GiB; swap 64 GiB (= RAM) all on TLC; /tmp and /var/tmp
  gain about 45 GB (25.1 GB + 62.3 GB of tail - 17.2 GB of swapfile growth,
  about 70 GB free);
  the root gains 16 GiB.
- Risk: a partition-table edit on the disk that holds the Windows install and
  its ESP. Growing the last partition rewrites only p5's end sector, and the
  ext4 grow is online, but an error in the device name or the sector arithmetic
  hits the Windows data. A full backup of the GPT (`sfdisk -d`) comes first.
- Justification: A1 puts swapfile and partition at equal performance, so the
  file keeps its resize flexibility; all swap slots move to the drive with 7%
  wear; the QLC root stops being a swap target.
- Falsifier: `swapon --show` after the change showing anything but one 64 GiB
  area at priority 50; or the unallocated range turning out to be reserved.

### S3: a 58 GiB swap partition in the unallocated tail, beside the 48 GiB file

- Change: create p6 (type 8200) in the tail, `mkswap`, priority 50 equal to the
  file so the kernel stripes pages across both (A2), retire the QLC file.
- Result: 106 GiB of swap on TLC; /tmp unchanged at 25 GB free.
- Cost: two swap areas to manage; the partition cannot be resized later
  without moving p6.
- Risk: same partition-table risk as S2; 106 GiB of slots exceeds RAM by 70%,
  and pages swapped beyond about RAM size usually signal a workload that
  oomd should stop rather than page.
- Justification: no swapoff of the live file is needed; striping two areas on
  one drive gains nothing (same device), so the only benefit is capacity.
- Falsifier: swap use above 64 GiB ever observed (then capacity was needed).

### S4: carve a swap partition from the NTFS partition

- Change: shrink p3 by 64 GiB from Windows (Disk Management) or with
  `ntfsresize`, then create a swap partition in the freed range.
- Cost: an NTFS resize on the Windows data partition, which needs Windows Fast
  Startup and hibernation off and a clean NTFS journal; BitLocker, if enabled,
  must be suspended.
- Risk: the highest of the options: a failed NTFS shrink endangers 1.2 TB of
  Windows data. The owner's note that the Windows disk "is what it is" argues
  for leaving p3 alone.
- Justification: only if the unallocated tail is reserved for something else.
- Falsifier: none needed while S2 is available; it is dominated.

### Recommendation

S2. It meets "980 PRO swap the same size as RAM" (64 GiB on a 62.7 GiB host),
puts every swap slot on the drive with the lowest wear, frees 16 GiB on the
full QLC root, and enlarges /tmp instead of shrinking it, all without touching
the Windows partitions. The ordering inside the window: back up the GPT;
extend p5; `resize2fs`; `swapoff /srv/fasttmp/swapfile` (only with
MemAvailable above the swap in use); re-create the file at 64G with
`ensure-fast-swapfile`'s procedure (staging file, `mkswap`, rename);
`swapon`; then `swapoff /swapfile` and remove its fstab line. The package's
`ensure-fast-swapfile` size (48G) and its documentation change with that
window, not before.

## Cache and build-tree homes

| Home | Device | Free | Write endurance position | Fit |
|------|--------|------|--------------------------|-----|
| / | P3 QLC, DRAM-less | 34.1 GB | 32% worn; SLC-cache-limited sustained writes | keep: system, packages, small hot caches only |
| /tmp, /var/tmp (980 p5) | 980 TLC, PCIe 4 | 25.1 GB (67 GB after S2) | 7% worn | build trees and other volatile, write-heavy work |
| /srv/data | MX500 TLC, SATA | 109.2 GB | wear not captured | compiler caches (ccache, sccache), package build output, Docker/BuildKit state, model files: large, mostly read after warm-up |

Recommendation: move compiler caches and package build directories from the
root to /srv/data, and point large build trees at /tmp on the 980 (after S2)
or /srv/data when they exceed it. Justification: the root wrote about 567 GB a
day in the SYSTEM.md M6 sample, and QLC endurance and sustained-write speed are
the weakest of the three drives; ccache hits are reads, so SATA bandwidth
(about 550 MB/s) is not the bottleneck for a warm cache. Cost: one
configuration change per tool (`CCACHE_DIR`, `BUILDDIR` in makepkg.conf,
Docker `data-root`) and a one-time copy. Falsifier: build wall time with the
cache on /srv/data more than 5% above the same build with the cache on the
root, or `/sys/block/sda/stat` showing the MX500 saturated (time in queue near
100%) during builds.

## Mount options

- / uses `noatime,commit=60`; /srv/data uses `noatime`; p5 uses
  `relatime`. `noatime` on p5 would drop the remaining atime updates on /tmp
  (relatime already limits them to once a day per file); a small gain, safe
  because nothing on /tmp relies on atime except tmpfiles aging, which
  uses the newest of atime, mtime and ctime (tmpfiles.d(5)), so noatime makes
  aging depend on mtime and ctime. Decision for the owner; not recommended
  until a measurement shows atime writes matter.

## Not measured (needs root or a tool not run)

- `nvme id-ns -H` for both NVMe drives: LBA formats and Relative Performance.
- SMART `data_units_written` for both NVMe drives and MX500 attributes
  (Total_LBAs_Written, wear leveling count): absolute write volume and MX500 wear.
- `du` of /srv/fasttmp subdirectories (root-only `legacy-shared-root`): how
  much of p5 the old shared-root archive still holds; reclaiming it changes the
  S1 arithmetic.
- `filefrag` of both swapfiles (root-only): extent counts.
- `tune2fs -l`: ext4 feature flags. The reserved blocks follow from `stat -f`
  (free minus available): 40.0 GB on the root (1.0%), 1.4 GB on p5 (1.0%) and
  16 MiB on /srv/data, so the reserve is already near 1% and lowering it
  recovers little.
- The origin of the unallocated 58 GiB on the 980 PRO.
- P3 power-state behavior: `id-ctrl` feature 0x0c shows Autonomous Power
  State Transition disabled on the P3; it affects idle power, not this memo.
