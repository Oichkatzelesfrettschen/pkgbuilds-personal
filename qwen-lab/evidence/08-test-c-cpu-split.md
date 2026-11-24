# C -- conventional CPU/GPU layer split, llama.cpp b10549, Q4_K_M

Host and card as in 06-results-matrix.md. Sustained pinned host-to-device is
24.06 GiB/s (01-pcie-h2d.txt); sustained DDR4 read at six threads is
35.21 GiB/s (07-ddr4.txt).

C keeps the layers that do not fit in host memory and computes them on the
5600X3D, so those weights are read from DDR4 into the CPU instead of being
shipped to the GPU:

    A:  DDR4 -> PCIe at 24.06 GiB/s -> GPU arithmetic
    C:  DDR4 at 35.21 GiB/s -> CPU arithmetic

DDR4 read is 1.46x the bus. That ratio is one of three terms and not the
explanation on its own; the decomposition is below.

## Protocol

Identical to A and E: prompt `short` (64 prompt tokens), `max_tokens` 128,
temperature 0, three timed repetitions after one discarded warmup, decode rate
computed over the tokens after the first so prefill is excluded. Cold time to
first token is measured separately as a single request against a server that
has served nothing, with no warmup and no prompt-cache entry; the warm figure
follows the standard protocol and reuses 60 of the 64 prompt tokens from
llama.cpp's prompt cache, as E's does.

Cold here means a cold server, not a cold page cache. The three runs were
launched in sequence and the checkpoint became progressively resident: load
took 45 s, then 30 s, then 17 s. Cold time to first token falls across the same
sequence, 4.055 s to 2.917 s to 2.500 s, so that series is confounded by page
cache warming and the cold column is not a fair comparison between the three
configurations. Warm time to first token and every decode figure are
unaffected, because both are measured after the checkpoint is fully resident.

Prompt caching is not equal across backends, so the warm column is not a
controlled time-to-first-token comparison either. vLLM logged
`enable_prefix_caching=False` and reported `Prefix cache hit rate: 0.0%` on
every iteration of run A, so A prefilled all 64 prompt tokens on every
repetition while C and E prefilled 4. The warm column is each backend at its
own default, which is an operational reading; the controlled reading needs
equal uncached token counts and is given under the cross-arm comparison.

## Results

| | C, 6 threads, ngl 38 | C, 12 threads, ngl 38 | C, 6 threads, ngl 40 |
|---|---|---|---|
| Decode, P50, client | 3.578 tok/s | 1.916 tok/s | **3.820 tok/s** |
| Decode, server `eval time` | 3.60-3.69 tok/s | 1.76-2.03 tok/s | 3.88-3.90 tok/s |
| Time to first token, cold | 4.055 s | 2.917 s | 2.500 s |
| Time to first token, warm | 0.524 s | 0.786 s | 0.531 s |
| Prompt eval, 4 uncached tokens | 7.26-7.85 tok/s | 5.10-5.11 tok/s | 7.55-7.59 tok/s |
| Inter-token latency P50 / P95 | 271.7 / 295.9 ms | 464.9 / 942.1 ms | 256.4 / 272.5 ms |
| Process VRAM | 9578 MiB | 9578 MiB | 10056 MiB |
| Process RSS | 6.84 GiB | 6.85 GiB | 7.32 GiB |
| Process CPU, P50 | 474.8 % | 930.5 % | 466.6 % |
| Package power, P50 | 72.29 W | 65.45 W | 71.31 W |
| PCIe receive, P50 | 32 MiB/s | 27 MiB/s | 44 MiB/s |
| PCIe transmit, P50 | 15 MiB/s | 11 MiB/s | 16 MiB/s |
| Locked pages | 0 | 0 | 0 |

Client and server-side rates agree to within two percent in every run, so the
harness is measuring generation rather than transport.

## Weight placement, exactly

`llama-gguf` enumerates the checkpoint at 15.323 GiB of tensor data: 64 decoder
blocks at 13.359 GiB, `output.weight` at 0.9713 GiB, `token_embd.weight` at
0.6660 GiB, and a 0.327 GiB `blk.64` multi-token-prediction head that
llama.cpp reports as unused. `n_gpu_layers` places the last N blocks on the
card, so ngl 38 puts blocks 26..63 there and ngl 40 puts blocks 24..63.

`--n-gpu-layers` is not a count of decoder blocks. llama.cpp b10549
(`b2e5e9b28b2484fbf94b543432ece638996a8b97`) builds a suffix over
`n_layer_all + 1` slots, from `llama-model.cpp:1361`:

    const int i_gpu_start = std::max(n_layer_all + 1 - n_gpu_layers, 0);
    const int act_gpu_layers = devices.empty() ? 0 : std::min(n_gpu_layers, n_layer_all + 1);

`n_layer_all` is `qwen35.block_count` = 65 (line 1118), and the output tensor
takes the extra slot at index `n_layer_all` (line 1386,
`pimpl->dev_output = get_layer_buft_list(n_layer_all)`). `-ngl all` resolves to
`n_layer_all + 1` = 66 (line 1754). Slot 64 is the MTP block, which an ordinary
target-model load does not execute.

So the slot map is 0..63 decoder blocks, 64 MTP, 65 output, and
`i_gpu_start = 66 - ngl`. **The output layer is on the device at every ngl in
this table**, because slot 65 is the last slot the suffix reaches. The original
table charged `output.weight` to the host read and started the block ranges two
slots low; both are corrected below, recomputed from the checkpoint's own tensor
index rather than re-measured.

| ngl | i_gpu_start | GPU decoder blocks | Host decoder blocks | Read per token | DDR4 bound | Measured | Fraction |
|---|---|---|---|---|---|---|---|
| 38 | 28 | `blk.28..63`, 36 of 64 | `blk.0..27` | 5.625 GiB | 6.259 tok/s | 3.579 | 0.572 |
| 40 | 26 | `blk.26..63`, 38 of 64 | `blk.0..25` | 5.175 GiB | 6.804 tok/s | 3.820 | 0.561 |
| 42 | 24 | `blk.24..63`, 40 of 64 | `blk.0..23` | 4.694 GiB | 7.502 tok/s | fails | -- |

Read per token excludes `token_embd.weight`, which is a single row gather rather
than a full traversal, and now also excludes `output.weight`, which the suffix
places on the device at all three settings. The ledger validates against this
document's own figures: offset deltas sum to 15.3234 GiB against the stated
15.323 GiB of tensor data, with `output.weight` at 0.9713 GiB,
`token_embd.weight` at 0.6660 GiB, and `blk.64` at 0.3269 GiB.

ngl 42 loads its weights -- VRAM reached 11505 MiB -- and then dies allocating
a 195.07 MiB compute buffer for prompt processing. The card holds the weights
and cannot hold the scratch that uses them, so 40 is the working maximum at
4096 context.

## The thread sweep is the discriminator

Twelve threads are not merely no better than six; they are 1.87x worse, at
1.916 tok/s against 3.578. Three readings move together and identify the cause:

- Process CPU rises from 475 percent to 931 percent, so the threads are
  scheduled and running.
- Package power falls from 72.3 W to 65.5 W. Cores drawing less current while
  occupying twice the scheduler slots are stalled, not computing.
- Inter-token latency P95 rises from 295.9 ms to 942.1 ms, a spread of 477 ms
  against 24 ms at six threads. Six threads produce a tight distribution; twelve
  produce a ragged one, which is contention rather than a steady wall.

The DDR4 probe shows the same shape independently: 35.21 GiB/s at six threads
against 32.12 at twelve, because SMT siblings share one load/store path and the
second thread on a core adds contention without adding a request stream. The
probe loses 10 percent that way and llama.cpp loses 47 percent, so barrier
synchronisation across twice as many threads costs more than the memory
contention alone.

C is therefore memory-limited but not memory-saturated. At six threads it
reaches 61 to 63 percent of its DDR4 bound, and that fraction holds across two
different layer splits. That is consistent with the missing 38 percent being
proportional per-layer cost -- CPU arithmetic and thread barriers -- rather
than a fixed overhead that more bytes would amortise, but two nearby placements
four blocks apart do not establish proportionality; they rule out a large fixed
term over that interval and nothing wider.

## The falsifier passed

A contiguous split crosses the CPU/GPU boundary once per token and carries only
hidden state, about 20 KiB at hidden size 5120. Sustained PCIe receive traffic
would mean weights were moving and the run was not what it claims. Median
receive is 32 to 44 MiB/s across all three runs, which is idle traffic; the
bursts in the P95 and maximum columns land during prompt processing. Weights
stay where they were placed.

Host-resident weights are mmap'd page cache, not pinned: `proc_vmlck_kib` is 0
in every sample and RSS tracks the host-resident share rather than the whole
file. That is the right arrangement here -- systemd-oomd is armed and pinned
pages cannot be reclaimed -- but it means the kernel may evict weight pages
under memory pressure and turn decode into NVMe reads with no error anywhere.
Available host memory stayed near 20 GiB throughout, and the 191 to 205 MB of
process swap in the ngl 38 runs is pre-existing residue rather than growth; the
ngl 40 run showed none.

## Against the completed arms

| | A, vLLM prefetch W4A16 | C, CPU split Q4_K_M | E, resident Q2_K_XL |
|---|---|---|---|
| Decode, P50 | 2.556 tok/s | 3.820 tok/s | 38.96 tok/s |
| TTFT, 64 uncached prompt tokens | 37.282 s | 2.500 s | 0.702 s |
| TTFT, backend default cache | 37.282 s | 0.531 s | 0.111 s |
| Uncached prompt tokens at default | 64 | 4 | 4 |
| Inter-token latency P50 | 397.7 ms | 256.4 ms | 25.4 ms |
| Weight bytes per token over PCIe | 8.774 GiB | none | none |
| Weight bytes per token from DDR4 | none | 5.665 GiB | none |
| Bound reached | 0.932 of 2.742 tok/s | 0.615 of 6.22 tok/s | not bounded by either link |

**C beats A by 1.494x on decode**, and it does so while serving a 4-bit
checkpoint against A's 4-bit-weight, 16-bit-activation one. Ruling out the
conventional split was the wrong call for batch-one latency on this hardware.

E still beats C by 10.2x on decode. The ordering is set by which link carries
the weights: VRAM at hundreds of GB/s, then DDR4 at 35.21 GiB/s, then PCIe at
24.06 GiB/s, and each arm lands in that order.

### The 1.494x is not the 1.46x bandwidth ratio

The near match between the measured speedup and the DDR4-to-PCIe ratio is a
cancellation of three terms, not a demonstration that bandwidth ratio explains
the result. Each arm is its efficiency times its own ceiling:

    T_A = eta_A * (24.06 / 8.774),  eta_A >= 0.932,  so T_A >= 2.556 tok/s
    T_C = 0.561  * (35.21 / 5.1749) = 3.817 tok/s

A's efficiency is a floor rather than a value, because its rate came from the
SSE delta counter that 13 shows undercounts. Dividing by a floor gives an upper
bound, so the decomposition is an inequality:

    T_C / T_A <= (35.21 / 24.06) * (8.774 / 5.1749) * (0.561 / 0.932)
              =       1.463      *       1.696      *       0.602
              = 1.493

against a measured 3.820 / 2.556 = 1.494, which is itself an upper bound on the
true ratio for the same reason.

C holds two advantages and gives most of them back. The link is 1.463x faster,
and C moves 1.696x fewer host bytes per token -- 5.175 GiB against 8.774 --
because it keeps 38 of 64 decoder blocks and the output projection on the card
where A offloads 48 of the 64 layers vLLM counts, and because Q4_K_M is a
smaller checkpoint than the W4A16 one to begin with. Those combine to a **2.481x
memory-derived ceiling advantage**, not the 2.267x this document previously
stated, which was computed with `output.weight` wrongly charged to the host and
the block ranges two slots low. CPU arithmetic, dequantisation, thread barriers,
and layer transitions then cost a factor of at most 0.602 against A's floor.

Stated as a sentence: C avoids PCIe and reads a smaller host-resident working
set over the faster DDR4 path, and its CPU-side execution costs reduce a 2.48x
memory-derived ceiling advantage to a measured ratio of at most 1.49x.

The first time-to-first-token row is the controlled one: every arm prefills 64
tokens no cache holds. **A to C is 14.9x and A to E is 53.1x** there, against
the 70x and 336x the default-cache row shows.

One asymmetry survives in that row and it runs against the llama.cpp arms:
A's 37.282 s is a warm-server figure taken after a discarded warmup, while
C's 2.500 s and E's 0.702 s are each a server's first request, paying graph
warmup the vLLM figure had already paid. The true controlled gap is therefore
larger than 14.9x and 53.1x, not bounded by them.

E's 0.702 s comes from run `E-llamacpp-resident-q2kxl-coldttft-0823-175929`,
launched to fill this column. It differs from the original E run in one
argument: `--threads 6`, where the original took llama.cpp's default. For a
fully resident model that setting governs almost nothing, and the two runs
agree on warm decode to within two percent -- 38.125 against 38.96 -- which is
what supports treating them as the same measurement.

The default row is still worth keeping. It is what each backend does out of the
box on a repeated prompt, and vLLM's prefix cache being off under this offload
configuration is a property of the arm rather than a harness artefact.

C against A is an operational comparison, not a controlled one. The runtimes,
the quantisation structure, the kernels, and the packing all differ, so it
selects a daily runtime without proving anything about CPU arithmetic against
prefetch in isolation.

C against E is closer but still not controlled. It holds the runtime, the GGUF
lineage, the measurement path, the context, and the `flash-attn on` flag
constant, and it varies whether the model fits. It also varies the quantisation
-- Q4_K_M against Q2_K_XL -- and it varies what the constant flag covers, since
flash attention reaches all 16 full-attention blocks in E and only the subset
of them that landed on the device in C. Neither difference is large enough to
move a 10.2x, but the pairing selects a runtime rather than isolating a
mechanism, and the quantisation difference is the whole reason a quality
comparison is still owed.

## Not run

- Package power and CPU utilisation for A and E. The host sampler did not
  exist when those ran, and rerunning them to add columns would have replaced
  the completed record rather than extending it.
- Per-run DRAM traffic from hardware counters. See 07-ddr4.txt for why the
  data-fabric PMU yields nothing checkable on this part.
- Thread counts between 6 and 12, and ngl 41. The DDR4 curve peaks at six
  threads and ngl 42 fails, so both optima are bracketed rather than pinned.
- Output quality. Every figure here is latency.
