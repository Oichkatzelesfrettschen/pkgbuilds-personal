# Benchmark matrix results

Host: Ryzen 5600X3D, 31 GiB DDR4, RTX 4070 Ti 12 GiB (AD104, sm_89),
kernel 7.1.8-cachyos, NVIDIA 610.57.04 open modules, CUDA 13.3.
Sustained pinned H2D 24.06 GiB/s (evidence/01-pcie-h2d.txt).

## How to read this matrix

Arms are lettered by the order they were run, not by rank. The letter stays as
an alias because the profiles and 08 through 14 all reference it; the role
standing column says what each arm is for.

| Arm | What it is | Standing |
|---|---|---|
| E | resident Q2_K_XL, every decoder block on the card | **recommended interactive/throughput arm**, within its measured context and VRAM envelope |
| F | E plus vision, projector on the host | the shipped serving profile, what `qwen-lab-serve` selects, same envelope as E |
| C | llama.cpp split Q4_K_M | **recommended capacity/long-context arm** |
| A | vLLM explicit prefetch | offload baseline |
| B | vLLM UVA | offload baseline, end-to-end rate only |
| D | llama.cpp CUDA managed memory | managed-memory negative control |
| E2 | resident IQ3_XXS | infeasible resident candidate under the measured desktop envelope |

Neither E nor C is the winner outright. E is recommended for interactive work
inside the envelope 13 states -- one slot, projector on the host, up to roughly
14K of occupied context -- and C is recommended wherever context matters more
than rate. Writing "E: recommended" unqualified would restore exactly the
global-winner reading this roster exists to remove.

A, B, and D were never candidates. They measure what host-backed weights cost,
and the order-of-magnitude gap between them and E is this document's central
result rather than a decline within it.

## E -- resident Q2_K_XL (recommended, interactive), llama.cpp b10549

Run `E-llamacpp-resident-q2kxl-0823-150355`.

| Measure | Value |
|---|---|
| Decode rate, P50 | 38.96 tok/s |
| Time to first token, P50 | 0.111 s |
| Inter-token latency, P50 | 25.4 ms |
| Inter-token latency, P95 | 28.0 ms |
| Process VRAM | 9398 MiB |
| Checkpoint | 9373 MiB |
| Resident fraction | 1.003 |
| PCIe receive, steady-state P50 | 42 MiB/s |
| PCIe transmit, steady-state P50 | 7 MiB/s |

Probe verdict `NOT_DECLARED`, meaning no offloading was requested and none
occurred: the process holds essentially the whole checkpoint in VRAM. The
steady-state receive figure confirms it physically -- 42 MiB/s is idle traffic,
not weight delivery, so decode never crosses the bus and the 24.06 GiB/s
ceiling does not constrain this arm at all.

Load took 30 s from warm page cache. The checkpoint carries 64 decoder blocks
and a `blk.64` multi-token-prediction head, and `qwen35.block_count` counts all
65. llama.cpp's layer index therefore runs to 65, and the suffix it places spans
`n_layer_all + 1` = 66 slots, the last being the output layer. `-ngl 64` leaves
two decoder blocks on the host and `-ngl all` resolves to 66. 11-placement-curve-and-capabilities.md
carries the corrected promotion curve; the earlier claim here that the loader
ignores `blk.64` was written from the tensor enumeration in 08 and never checked
against the metadata key that sets the layer count.

Qwen3.8 emits its chain of thought into `reasoning_content`; at 128 max tokens
the entire budget went to reasoning and the answer was empty. Latency figures
are unaffected, but any quality comparison needs a token budget large enough to
reach the answer.

## A -- vLLM prefetch, W4A16, two-thirds offload (offload baseline)

Run `A-vllm-prefetch-w4a16-0823-151009`. Offload confirmed from vLLM's own
accounting:

```
Offloader set to PrefetchOffloader
[PrefetchOffloader] Initialized 42 modules. Total GPU memory saved: 8.2694 GB,
Static buffer pool: 0.2525 GB
(group_size=3, num_in_group=2, prefetch_step=1, mode=cpu)
```

42 of the 64 decoder layers are offloaded, which is the two-thirds the group
parameters ask for. The 64 here is vLLM's, read from the HuggingFace config's
`num_hidden_layers`, which excludes the multi-token-prediction head; llama.cpp's
65 in the roster above counts it. The two backends disagree about the
denominator and both are right about their own. The measured 8.2694 GB is 7.70 GiB crossing PCIe per
traversal, below the 9.6 GiB the profile estimated, so the transfer ceiling is
**3.12 traversals/s** at 24.06 GiB/s. **A produced no benchmark at this setting: decode rate is unmeasured.** The
comparison available is between E's measured 38.96 tok/s and A's transfer
*bound* of 3.12 traversals/s, which is a measurement against a ceiling rather
than against a throughput. A could land anywhere below its ceiling.

Weight loading took 27.6 s; model loading reported 9.01 GiB of GPU memory.
Resident VRAM settled at 11722 MiB of 12282, leaving roughly 0.5 GiB of margin.
The CUDA caching allocator logged one failed 2.54 GB allocation during setup and
recovered, which is the allocator falling back rather than a fatal condition.

Initialisation after weight loading is dominated by Triton kernel compilation
for the hybrid attention stack -- 48 linear-attention and 16 full-attention
layers, with mamba and attention page sizes reconciled -- which emits no
progress output. Budget several minutes on a cold Triton cache.

### Telemetry limitation for vLLM

`launch.sh` records the pid of the `vllm serve` API server, but vLLM runs the
engine in a child `EngineCore` process, and that child holds the weights. The
`proc_rss_kib`, `proc_vmlck_kib`, and `proc_swap_kib` columns therefore describe
the API server, which is tens of megabytes, and understate host usage for
vLLM runs. The GPU and PCIe columns are device-global and remain correct, as do
`host_avail_kib` and per-process VRAM in `run_probe`.

llama.cpp is single-process, so its host columns are accurate. Resolving this
for vLLM means having the sampler follow the pidfile's children rather than the
pid itself.

### A failed to fit at two-thirds offload

The engine aborted during initialisation:

```
Available KV cache memory: 0.09 GiB
ValueError: To serve at least one request with the model's max seq len (4096),
0.29 GiB KV cache is needed, which is larger than the available KV cache
memory (0.09 GiB)
```

Weights and the staging pool consumed the card, leaving a third of the cache
the smallest possible request needs. Note also that vLLM measured only 6.55 GiB
of available RAM at load and disabled its own auto-prefetch on that basis: the
checkpoint at 18.12 GiB exceeded 90 percent of free host memory. Host memory
was constraining this run before VRAM was.

The failure is the tuning ladder's expected first outcome, not a defect. The
harness identified the cause and named the change that moves the binding
constraint -- raising the offloaded fraction from two thirds to three quarters,
which frees more VRAM than trimming context or utilisation. That rerun fit and is
recorded below.

## A -- vLLM prefetch, W4A16, three-quarters offload (offload baseline)

Run `A-vllm-prefetch-w4a16-g4n3-0823-151433`. Probe verdict CONFIRMED:
48 modules offloaded, 9.4212 GB saved, 0.2525 GB staging pool,
group_size=4, num_in_group=3, prefetch_step=1. KV cache rose from 0.09 GiB to
1.31 GiB (18,432 tokens), so the single change the tuning ladder recommended
was sufficient.

| Measure | Value |
|---|---|
| Decode rate, P50 | 2.556 tok/s (provisional, see instrument note) |
| Client-observed first streamed token, P50 | 37.3 s |
| Inter-token latency, P50 | 397.7 ms |
| Inter-token latency, P95 | 399.3 ms |
| PCIe receive, steady-state P50 | 25082 MiB/s = 24.5 GiB/s |
| Peak PCIe receive | 25.8 GiB/s |
| Predicted ceiling | 2.743 traversals/s |
| Fraction of ceiling reached | **0.932** (provisional) |

Verdict: transfer bound. Only streaming fewer bytes per traversal will move it.

### Instrument note on the 2.556 and the 0.932

Both figures were taken with the harness-side SSE delta counter that 13 later
shows undercounts: on llama.cpp the same counter read 33.36 tok/s against the
server's own 37.20. The direction is known even though the magnitude is not, so
A's true decode rate is **at least** 2.556 tok/s and its fraction of ceiling is
**at least** 0.932. Neither is exact until a rerun takes the count from vLLM's
own accounting. If that rerun pushes the fraction past 1.0, the error is in the
8.774 GiB/traversal denominator rather than in the arm.

The mechanism-level conclusion does not depend on either number. Confirmed
prefetch engagement, link traffic at 24.5 GiB/s against a 24.06 GiB/s isolated
payload ceiling, and a 1.6 ms spread over 105 inter-token samples each stand on
their own.

The row above is labelled *client-observed first streamed token*, not TTFT. B's
remeasurement below shows vLLM can hold a completion for two minutes and then
flush it whole, which makes a socket-side boundary a transport boundary. Calling
it engine TTFT requires reconciliation against `/metrics` or the engine log.

### Which denominator the 0.932 uses

vLLM reports `Total GPU memory saved: 9.4212 GB` in decimal gigabytes.
9.4212e9 bytes is 8.774 GiB, and that conversion is the step a reader cannot
reproduce from the log alone. The ceiling is the isolated pinned host-to-device
figure over that:

    24.06 GiB/s / 8.774 GiB = 2.742 traversals/s
    2.556 / 2.742 = 0.932

Substituting the observed median receive rate gives 24.5 / 8.774 = 2.794
traversals/s and a fraction of 0.915. The isolated figure is the one reported,
because the observed rate slightly exceeds the isolated measurement and the two
are therefore not counting the same bytes: `nvidia-smi dmon` reports link
traffic including protocol overhead, while `bench/h2d.cu` reports payload
delivered. Payload against payload is the comparison the bound is written in.

The bus is saturated. Median receive traffic during decode is 24.5 GiB/s
against the 24.06 GiB/s measured in isolation, so weight delivery rather than
compute sets the rate. GPU utilisation reads 99 to 100 percent throughout,
which is exactly the reading not to trust: the device is occupied waiting on
copies.

The inter-token distribution is deterministic: P50 397.7 ms against P95
399.3 ms is a spread of 1.6 ms over 105 samples. Read on its own that shows a
stable steady state and no more, because a transfer stall that is uncovered by
the same amount every token produces an equally flat distribution. An unstable
or intermittently uncovered transfer would tend to produce a tail; this run
instead exhibits a deterministic bandwidth-bound plateau.

What identifies the bandwidth wall is the conjunction of five readings, no one
of which carries it alone: the offloader is confirmed installed with its own
byte accounting, observed link traffic is 24.5 GiB/s, isolated payload
bandwidth is 24.06 GiB/s, throughput is 93.2 percent of the payload-derived
ceiling, and steady-state latency is tight.

Time to first token is 37.3 s because prefill must also stream every offloaded
weight before it can produce anything. vLLM logged `enable_prefix_caching=False`
and `Prefix cache hit rate: 0.0%` throughout, so all 64 prompt tokens were
prefilled on every repetition. The llama.cpp arms reuse 60 of 64 from their
prompt cache at their own defaults, which makes the warm time-to-first-token
column a comparison of backend defaults rather than of prefill cost. See
08-test-c-cpu-split.md for the equal-uncached-token column.

## The comparison

| | A, offload baseline | E, recommended |
|---|---|---|
| Decode, P50 | 2.556 tok/s (provisional) | 38.96 tok/s |
| Client-observed first streamed token | 37.3 s | 0.111 s |
| Inter-token latency, P50 | 397.7 ms | 25.4 ms |
| Weights crossing PCIe per token | 8.77 GiB | none |

**E is at most 15.2x faster at decode and 336x faster to first token** -- at the
placements these two arms used, and at most because A's rate is a floor rather
than a value. See the closing section: placement rather than
mechanism accounts for most of that gap.

This settles the question the request opened. vLLM asynchronous prefetch is
indeed the best available implementation of host-backed weights with GPU-only
arithmetic -- it engaged, it overlapped, and it reached 93 percent of the
ceiling that mechanism can have. The mechanism is not the limit; the bus is.
At batch one on this hardware, a quant that fits entirely in VRAM wins by more
than an order of magnitude, and it wins for a reason no amount of tuning
addresses: it does not use the bus at all.

The remaining tradeoff is quality, not speed. A serves INT4 group-128 weights
with BF16 activations; E serves a 2-bit quant. Deciding between them requires
task quality alongside these latencies, and that comparison has not been run.

Prefill and concurrent batching would move this the other way, because one
streamed weight block is reused across many rows. Every figure here is batch
one, single stream.

## The rest of the matrix

All five arms have now run.

| Arm | Role | Mechanism | Decode, batch one | End to end | Instrument |
|---|---|---|---|---|---|
| E | recommended, interactive | llama.cpp resident Q2_K_XL, `ngl 99` | **36.20 tok/s** | 31 to 35 tok/s | server `timings` |
| C | recommended, capacity | llama.cpp split Q4_K_M, ngl 38 | 3.30 to 3.67 tok/s | -- | delta counter |
| A | offload baseline | vLLM prefetch, W4A16 | 2.556 tok/s, provisional | -- | delta counter |
| B | offload baseline, end to end only | vLLM UVA, W4A16 | *not separable* | 2.11 tok/s | `usage.completion_tokens` |
| D | managed-memory negative control | llama.cpp managed memory | 0.499 tok/s | -- | delta counter |

B's decode cell is empty deliberately. Its 2.11 tok/s is total completion
tokens over total wall time, which is immune to when the transport flushes and
therefore trustworthy -- but it is not a decode rate and does not belong in that
column beside A, C, D, and E. Every cell marked *delta counter* inherits the
undercount 13 documents and is a floor rather than a value. E's decode figure is
the server's own, and its end-to-end range runs lower only because prefill sits
in the divisor.

E appears twice in this document with different numbers: 38.96 tok/s at the top
in run `E-llamacpp-resident-q2kxl-0823-150355` at 9398 MiB, and 36.20 here at
`ngl 99` and 9720 MiB. Both are real. They are different placements measured on
different days against a desktop whose VRAM moves, and the closing section is
the reason the difference is smaller than it looks.

B decomposes against A as `(10.04/8.774) x (0.932/0.836) = 1.28`: UVA streams
14 percent more bytes per traversal because it needs no staging buffer, and
reaches 83.6 percent of its own bound against prefetch's 93.2. At A's exact
0.85 utilisation B does not serve at all -- it confirms `UVAOffloader`, loads
its weights and a 2.79 GiB KV cache, then dies allocating FlashInfer's 394 MiB
prefill workspace, which is allocated after memory profiling and so appears in
no accounting. Freeing more VRAM than prefetch is what left no room for it.

D is the negative control and behaves like one: 0.499 tok/s against C's 3.820
at identical settings, with 9602 MiB/s of PCIe *transmit* alongside 8681
receive. Pages are evicted and immediately re-faulted. GPU utilisation reads
100 percent throughout, which is the reading the profile warns not to trust.

E2 (IQ3_XXS) has not been run. The earlier note that it was "too tight at
10.18 GiB against roughly 10.6 GiB free" is a judgement made against a single
free-VRAM reading, which 09 retires; it needs measuring rather than estimating.

## What supersedes the ordering above

Every figure in this document was taken at one block placement per arm, and
11-placement-curve-and-capabilities.md shows placement moves decode further
than any mechanism here. E ran at `n-gpu-layers all` and C at 38, so the 15.2x
between them is not a mechanism result. The same checkpoint at 16384 spans
4.10 tok/s at ngl 38 and 36.10 at ngl 99. Read the arm comparison as valid at
the placement each arm used and nothing more.

## E2 -- IQ3_XXS (infeasible), the arm that cannot be resident

Deferred earlier on a single free-VRAM reading, which `09` retires as a method.
Measured now, and the answer is arithmetic before it is a benchmark: IQ3_XXS
carries 10428 MiB of weights against 10346 MiB free on a quiet card. There is no
placement that holds it.

| placement | outcome |
|---|---|
| `--n-gpu-layers all` | aborts allocating the 544 MiB cache |
| `--n-gpu-layers auto` | loads at 10124 MiB, then CUDA out-of-memory in the first decode |

The `auto` row is the more useful one. Fitting reduced the placement until the
weights and cache fit, printed `listening on`, and produced a server that dies
on its first request -- the same failure `ngl 64` with the projector at a 4096
context produced, and the reason `qwen-lab-serve` generates a token before
believing a load.

IQ3_XXS is 1055 MiB larger than Q2_K_XL, and on this card that is the difference
between every block resident at 36 tok/s and no working configuration at all.
The finding generalises as placement, not as quality: a checkpoint that does not
fit is not a slower checkpoint, it is an absent one.


## B -- vLLM UVA (offload baseline), remeasured, and why its decode rate has no client-side value

Published provisionally at 2.004 tok/s on eleven streamed intervals, counted by
the same harness-side summation later shown to undercount llama.cpp. Rerun with
the token count taken from `usage.completion_tokens` in the stream's final
chunk, five requests, 1193 completion tokens:

| run | completion_tokens | TTFT    | streamed window | end to end |
|-----|-------------------|---------|-----------------|------------|
| 1   | 213               | 65.86 s | 35.8 s          | 2.10 tok/s |
| 2   | 256               | 118.19 s| 2.0 s           | 2.13 tok/s |
| 3   | 255               | 88.44 s | 38.4 s          | 2.01 tok/s |
| 4   | 213               | 62.42 s | 35.6 s          | 2.17 tok/s |
| 5   | 256               | 117.02 s| 2.0 s           | 2.15 tok/s |

End to end the arm is 2.11 tok/s and the five runs agree to within 0.16, which
is a firmer number than the eleven intervals it replaces. The columns before it
are worthless, and visibly so: runs 2 and 5 delivered all 256 tokens in 2.0
seconds after waiting nearly two minutes, which is 128 tok/s by arithmetic and
nothing at all by mechanism. Those are the two runs that ended on `length`
rather than `stop`. vLLM flushed the whole emission at once, so the boundary a
client draws between prefill and decode is a boundary in the transport.

This is why the original measurement was hard to pin down, and it is a limit on
the instrument rather than on the arm: separating TTFT from decode here needs
vLLM's own `/metrics`, not a stopwatch on the socket. Total time is immune,
because whatever the transport does, it cannot deliver tokens before they exist.

The mechanism is unchanged and confirmed: `UVAOffloader`, 10.04 GiB of
parameters offloaded, 27,989 tokens of GPU KV cache, and PCIe receive at a
median of 27254 MiB/s throughout, which is weights crossing the bus on every
forward pass rather than an idle link. GPU utilisation sits at 100% while
serving 2.11 tok/s, which is the arm's whole story: the device is never idle and
never has its weights.
