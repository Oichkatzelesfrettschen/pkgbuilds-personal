# What Tract 1 has not closed

Everything below needs a measurement that has not been taken. Each entry names
the claim at risk, the instrument that settles it, and what a result would
falsify. Nothing here is packaging debt; the package ships and serves.

## 0. Closed: the layer count, the rungs, and the C placement table

Settled from llama.cpp b10549 (`b2e5e9b28b2484fbf94b543432ece638996a8b97`), not
inferred from the VRAM curve. `--n-gpu-layers` builds a suffix over
`n_layer_all + 1` slots (`llama-model.cpp:1361`), `n_layer_all` is
`qwen35.block_count` = 65 (line 1118), the output tensor takes the extra slot at
index `n_layer_all` (line 1386), and `-ngl all` resolves to `n_layer_all + 1`
(line 1754). Slots are 0..63 decoder blocks, 64 the MTP block an ordinary
target-model load does not execute, 65 the output layer, and
`i_gpu_start = 66 - ngl`.

That resolves both rungs: 64 -> 65 adds `blk.1` (101.51 MiB) and 65 -> 66 adds
`blk.0` (109.72 MiB), against 102 MiB measured at each. The output layer is
already device-resident at ngl 64, which is why the 682.03 MiB ledger refuted
promotion -- no promotion happens at either transition. The 1.39x at the second
rung is the last host-resident decoder block leaving, and with it the round trip
its inputs and outputs crossed every token.

It also corrects 08's placement table by two slots rather than one, and moves
`output.weight` out of the host read entirely. Recomputed from the tensor index:
ngl 40 reads 5.175 GiB per token, not 5.665, for a DDR4 ceiling of 6.804 tok/s
and an efficiency of 0.561 -- not 6.22 and 0.615. C's memory-derived ceiling
advantage over A is 2.481x, not 2.267x.

A verbose load is still worth having as a regression witness, and it would
confirm the MTP slot is skipped rather than merely unexecuted, but the mapping
itself no longer depends on one.

The naming consequence stands. An arm called "all 64 decoder blocks resident"
means 66 slots, and `-ngl 64` is not that arm; it is two blocks short and 1.60x
slower. Name a resident arm by its flag, not by a block count.

## 1. A's decode rate and its fraction of ceiling are floors, not values

2.556 tok/s and 0.932 were both taken with the SSE delta counter that 13 shows
undercounts -- 33.36 against a server-reported 37.20 on llama.cpp. The direction
is known, so both figures are lower bounds. **Instrument:** rerun A with the
count taken from `usage.completion_tokens`, and take first-token time from
vLLM's `/metrics` or engine log rather than the socket.

**Falsifier:** a fraction above 1.0 does not mean the arm beat its ceiling. It
means the 8.774 GiB/traversal denominator is wrong, and the decimal-to-binary
conversion of vLLM's `9.4212 GB` is the first place to look.

The mechanism conclusion survives either way: confirmed prefetch engagement,
24.5 GiB/s of link traffic against a 24.06 GiB/s payload ceiling, and 1.6 ms of
spread over 105 samples are three independent readings that no token count
touches.

## 2. "Resident cannot reach 64K" is not yet a structural claim

What was measured is narrower than what was written:

> Fully GPU-resident Q2_K_XL, q8_0 K and V, projector on the device, failed at
> 64K in the tested allocation envelope.

That is not impossibility. `--no-mmproj-offload` recovering roughly 917 MiB
already falsifies the strong form -- a resident arm has currencies other than
context. Untried currencies remain: q4_0 or mixed K/V precision, `--no-kv-offload`
to keep the cache off the device, and fitted placement that keeps every block
while leaving non-repeating tensors on the host.

**Instrument:** load at 64K with q4_0 K/V, projector on host, and generate a
token; then repeat with host KV. **Falsifier:** any load that serves a token at
64K with every layer on the device retires the claim outright.

Two cautions on the arms this would add. `--no-kv-offload` may move attention
work to the CPU rather than merely letting CUDA read a host cache; that has to
be established from PCIe counters, CPU utilisation, and timings before the arm
can be called resident at all, and the honest name is *resident weights with
host context*. And a q4_0 cache raises a quality question that allocation does
not answer: it needs retrieval at 32K, 64K, and 128K before it counts as a
working configuration rather than a load that succeeded.

## 3. Split Q2_K_XL at long context is unmeasured and is the most likely win

The Q4_K_M depth curve confounds two causes: fewer resident blocks as context
grows, and more attention work as occupancy grows. Separating them needs two
curves at 2K, 8K, 32K, 64K, 96K, and 115K -- one at fixed `ngl 28`, one at
whatever placement the supervisor picks at each depth. The fixed curve isolates
depth cost; the fitted curve is what a user would actually run.

Then repeat the fitted curve on split Q2_K_XL. It combines lower static weight
traffic, more resident blocks, the same native context, and quality that tied at
16K. **Falsifier:** long-context quantisation damage or termination failure that
the 16K tie cannot predict. That has to be measured, not inferred.

## 4. Checkpoint host memory is unmeasured

The 2 MiB in 14 is a device-memory delta from `nvidia-smi --query-compute-apps`,
which cannot see host RAM. Serialised recurrent state at a reported ~149.6 MiB
per checkpoint and 32 per slot is a ~4.7 GiB host exposure that this instrument
would report as zero. The telemetry needs `checkpoint_count`,
`checkpoint_positions`, `checkpoint_serialized_bytes`, host RSS and commit deltas
across the same walk, `cache_ram_current_bytes`, and `slot_count`.

This is bounded here by geometry -- `--checkpoint-min-step 8192` admits two
checkpoints at 16K and thirty-two only past 256K -- and unbounded in Tract 2,
where 32 GiB of host RAM makes the checkpoint and `--cache-ram` pools larger
concerns than the KV cache.

| occupied context | positional maximum at 8192 spacing |
|---|---|
| 16K | 2 |
| 32K | 4 |
| 64K | 8 |
| 128K | 16 |
| 256K | 32 |

Actual counts run lower, because checkpoints form at prompt boundaries rather
than at every interval.

## 5. Image cost is reported as decode, and decode is the wrong column for it

The image row reads 38.01 tok/s, which is post-prefill generation and says
nothing about what the projector cost. Encode time, prompt evaluation, first
token, post-prefill decode, and total request time have to be separate columns
before host-versus-device projector placement can be decided for short answers.
The current recommendation is correct for long answers and unevidenced for
short ones.

## 6. The quality result is two-dimensional and asymmetrically replicated

| dimension | C, Q4_K_M | E, Q2_K_XL |
|---|---|---|
| standard tasks completed | 16/16 | 15/16 |
| hard tasks completed | 9/9 | 8/9 |
| accuracy on mutually completed tasks | 1.0 | 1.0 |
| completion rate | 25/25 | 23/25 |

Excluding unfinished tasks from the correctness score is right. Letting that
exclusion hide the completion gap is not, so both stay headline: **conditional
correctness** and **task-completion rate** are separate measures and neither
substitutes for the other. E was not less correct where it finished; it was less
reliable at finishing inside a fixed 3072-token budget.

The two E failures reproduced at multiple budgets across three runs, which is
stronger than a single-run failure. The comparison is still asymmetric: C's
successes on those same two tasks were not replicated three times. A symmetric
three-run replay of exactly those two C cases closes the gap cheaply.

The next quality tier should stop adding deterministic short-answer puzzles and
measure the work these configurations exist to do: multi-file repair that
compiles and passes tests, API-contract reconciliation across distant files,
long-form synthesis with traceable factual requirements, a patch whose
correctness depends on facts separated by tens of thousands of tokens, tool use
that must terminate with a final answer, and retrieval combined with reasoning
rather than retrieval alone. The 6/6 needle result at 62K and 115K shows the
context stayed addressable. It does not show 128K reasoning.

## What the supervisor still conflates

`qwen-lab-serve` carries three different margins under names that invite reading
them as one:

1. **Environmental reserve**, 384 MiB, sized from observed desktop variance.
2. **llama.cpp fit target**, 64 MiB, the internal post-fit headroom.
3. **Request-time transient reserve**, which is unmeasured -- the buffers a
   representative image, a maximum-batch prompt, or a near-full context needs
   after startup.

A reader should not take `--fit-target 64` for the whole safety margin. The
one-token text probe validates decode allocation and nothing else; it does not
exercise the image encoder's scratch or a large-prompt batch buffer, so each
serving profile should carry its own verification request rather than inherit
the default one.

The placement cache is keyed on model, projector, context, K/V types, parallel
slots, and a bucketed VRAM budget. It should also key on the llama.cpp build,
the driver and CUDA version, batch and ubatch sizes, the Flash Attention
setting, and the checkpoint policy. A cache hit across a driver upgrade is a
placement decision made against a machine that no longer exists.
