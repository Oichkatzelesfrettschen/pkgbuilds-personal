# Block I/O scheduler A/B, 2026-11-01

Question: does any block-layer scheduler beat the CachyOS defaults that
`cachyos-settings` applies through `/usr/lib/udev/rules.d/60-ioschedulers.rules`
(`kyber` for NVMe, `mq-deadline` for SATA SSDs) on this workstation (Ryzen 5
5600X3D, kernel 7.3.1-1-cachyos, fio 3.42)?

Answer: no. No alternative clears the adoption bar on any drive, so the package
ships no scheduler rule and the `cachyos-settings` defaults stay in force.

## Method

`tools/io-scheduler-ab/fio-sched-ab.sh` runs fio with `io_uring`, direct I/O and
a 2 GiB file on a mounted ext4 filesystem of each drive, so no raw device is
written. Per scheduler it runs five workloads for 12 s after 2 s of ramp: 4 KiB
random read at queue depth 1 (`rr4k_qd1`); 4 KiB random read at high depth
(`rr4k_hi`); 128 KiB sequential read at depth 8 (`sr128k`); 4 KiB random
read/write at 70/30 (`mix4k`); and 4 KiB random write at high depth
(`rw4k_hi`). High depth is 4 jobs of depth 32 on NVMe and 2 jobs of depth 16 on
SATA. Three repetitions alternate the scheduler order forward and reversed.
`tools/io-scheduler-ab/summarize.py` reports the median and min-max range of
IOPS and the p99 completion latency; `*` marks a range that does not overlap the
baseline scheduler's range. The raw fio JSON is in
`docs/io-scheduler-ab-20261101/raw-results.tzst`, the full tables in
`summary.md`, and the run log in `run.log`.

Prediction and decision rule were fixed before the run. An alternative replaces
the baseline only when its median beats the baseline's by more than 5% with
non-overlapping ranges on the workload that matters, without raising the
mixed-workload read p99 by more than 5%.

## Results

| drive | scheduler tested | outcome |
|---|---|---|
| Samsung 980 PRO (`nvme0n1`, baseline `kyber`) | `none`, `adios` | `none` leads on throughput (+10.8% on `rr4k_qd1`, 24.5k vs 22.1k IOPS; +5.8% on `rr4k_hi`) but raises the mixed-workload read p99 from 618 us to 717 us (+16%) and the high-depth read p99 from 465 us to 528 us. `adios` stays within 6% of `kyber` everywhere and raises the mixed read p99 by 4%. Baseline kept. |
| Crucial MX500 (`sda`, baseline `mq-deadline`) | `none`, `kyber`, `bfq`, `adios` | Every scheduler lands within 5% of the baseline on every workload, and within 3% on all but one result; the SATA link and NAND set the ceiling. `none` is +2.6% on `rr4k_qd1`; `kyber` is +4.5% on `rw4k_hi` and halves its write p99 (457 us vs 881 us), below the 5% bar. Baseline kept. |
| Crucial CT4000P3 (`nvme1n1`, baseline `kyber`) | `none`, `adios` | Inconclusive; see below. Baseline kept. |

The prediction that `bfq` costs 10-30% throughput on SATA failed: `bfq` stays
within 2% of `mq-deadline`. The prediction that `kyber` or `adios` beats `none`
on mixed-workload read p99 on the 980 PRO held (618 us and 643 us against 717
us), at the price of `none`'s lower write p99 (44 us against 70 us).

## Limits

- The CT4000P3 hosts the root filesystem, is 93% full and uses QLC flash.
  Within the run every scheduler's throughput fell by up to ten times between
  repetitions (for `rr4k_qd1`, every scheduler reads about 15k IOPS in
  repetition 1 and between 1.5k and 9.6k later), and the slowest scheduler
  changed from repetition to repetition. The drive state, driven by the earlier
  write workloads and live system I/O, outweighs any scheduler effect, so the
  data cannot rank schedulers on that drive.
- The first scheduler in repetition 1 of each drive reads from freshly written
  data and shows inflated or deflated values (`mq-deadline` `rr4k_hi` 99.7k
  IOPS in repetition 1 against 83-85k later; `kyber` 593k against 935-967k on the
  980 PRO). The medians shrug off one outlier; the min-max ranges overstate the
  baseline's noise. A warm-up pass and a Latin-square scheduler rotation would
  remove the effect from a rerun.
- Direct I/O from one process bypasses the page cache and says nothing about
  fairness among competing processes, which is what `bfq` targets, or about
  buffered read-ahead (`read_ahead_kb`).
- fio ran with `sudo` dropping `ONLY`, `REPS`, `RUNTIME` and `SIZE` through
  `env_reset`; the run used the script defaults (listed in `env.txt`). Pass
  overrides with `sudo env NAME=value sh fio-sched-ab.sh OUTDIR`.

## What would change the decision

A rerun with a warm-up pass that shows `none` within 5% of `kyber` on the 980
PRO mixed-workload read p99, or a workload trace from real use (a compile with a
concurrent copy) where `none` wins end to end. Reproduce with
`sudo sh tools/io-scheduler-ab/fio-sched-ab.sh OUTDIR` followed by
`python -I tools/io-scheduler-ab/summarize.py OUTDIR`.
