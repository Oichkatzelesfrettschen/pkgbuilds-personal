# Context capability: what each arm can actually hold

The latency matrix in 06-results-matrix.md and the split measurements in
08-test-c-cpu-split.md were taken at 4096 tokens of context. That is the
context at which the fully resident arm wins by 10.2x, and it is not a context
anyone works at. Raising it changes which arms exist.

## KV cost is set by 16 layers, not 64

Qwen3.8-27B is hybrid: `layer_types` counts 48 `linear_attention` blocks and 16
`full_attention` blocks, with `full_attention_interval` 4. Only the full
attention blocks hold a cache that grows with context. The linear blocks carry
constant recurrent and convolution state regardless of how long the sequence
is.

With `num_key_value_heads` 4 and `head_dim` 256, each full-attention block
stores 4 x 256 keys and the same values per token, so

    2 * 4 * 256 = 2048 elements per token per block
    x 16 blocks = 32768 elements per token

which is **64 KiB per token at f16 and 34 KiB at q8_0**. A dense 64-layer model
of this size would cost four times as much, and six-figure contexts on a 12 GiB
card would not be a question worth asking.

    context   f16 KV     q8_0 KV
      4096     256 MiB     136 MiB
     32768       2 GiB    1088 MiB
     65536       4 GiB    2176 MiB
    131072       8 GiB    4352 MiB
    262144      16 GiB    8704 MiB

`max_position_embeddings` is 262144, so everything up to 128K is inside the
trained window and needs no RoPE scaling.

## Free VRAM is not a constant, and only one arm can absorb that

A workstation card is shared with whatever is drawing to the screen. Over one
evening the non-model consumers on this card moved between 1419 MiB and
1542 MiB as a Discord GPU process started and the compositor grew. The resident
arm at 32768 loaded successfully against the first figure and failed against
the second, with the weights already on the card and the compute buffer short
by a few megabytes.

That variance is not symmetric between the arms. A split arm answers a
compositor spike by moving one block to the host and losing a few percent of
decode rate. A resident arm has no such currency: every block is on the card by
definition, so the only thing it can return is context. **Desktop variance is
paid in context, and only by the arm that cannot trade.**

A ceiling measured against one reading is therefore not a ceiling. The usable
setting is the one that survives the swing, and the headroom has to be budgeted
rather than discovered: 16384 uses 9720 MiB and leaves 616 MiB, which is wider
than the observed swing. 24576 fits at 10032 MiB with roughly 300 MiB spare,
which is not.

## Measured ceilings

Free VRAM with a compositor running is between 10.7 and 10.85 GiB of the card's
12282 MiB, depending on what else is drawing.

| Arm | Context | KV type | Result | Process VRAM | Card total |
|---|---|---|---|---|---|
| E resident Q2_K_XL | 65536 | q8_0 | **fails**, KV allocation | -- | -- |
| E resident Q2_K_XL | 32768 | q8_0 | fits only on a quiet desktop | 10344 MiB | 11763 MiB |
| E resident Q2_K_XL | 32768 | q8_0 | **fails** once Discord holds 103 MiB | -- | -- |
| E resident Q2_K_XL | 24576 | q8_0 | fits, ~300 MiB spare | 10032 MiB | 11579 MiB |
| E resident Q2_K_XL | 16384 | q8_0 | fits, ~616 MiB spare | 9720 MiB | 11666 MiB |
| C split Q4_K_M, ngl 38 | 32768 | q8_0 | fits | 10208 MiB | 11627 MiB |
| C split Q4_K_M, ngl 28 | 131072 | q8_0 | fits | 10186 MiB | 11605 MiB |

E's failure is the 2176 MiB KV allocation, with the weights already resident:

```
ggml_backend_cuda_buffer_type_alloc_buffer: allocating 2176.00 MiB on device 0:
cudaMalloc failed: out of memory
llama_init_from_model: failed to initialize the context:
failed to allocate buffer for kv cache
```

## The ceiling is structural, not a tuning miss

A fully resident arm holds every block on the card by definition. Whatever the
checkpoint did not take is the entire KV budget, and no setting trades one for
the other -- the moment blocks move to the host the arm is no longer the
resident arm. Q2_K_XL takes about 9.0 GiB of the 10.7 to 10.85 available, so KV
gets roughly 1.6 GiB less whatever headroom the desktop swing demands. f16 KV
is not an option at any context this arm can reach, so **E is doubly
quantised**: 2-bit weights and 8-bit KV. The paired quality comparison runs at
16384 for that reason -- it is the largest context this arm holds with margin
wider than the observed variance, not the largest it can be made to load.

The split arm has the knob the resident arm lacks. Context is bought with
blocks: 128K costs 4352 MiB of KV, which is paid for by dropping from ngl 38 to
ngl 28 and reading ten more blocks per token from DDR4 instead. That is a rate
penalty rather than a wall.

This is the finding the 4096 matrix could not see. The resident arm's decode
advantage is real and was measured correctly, but it is **conditional on a
context that arm cannot reach**. At 64K and above there is no resident arm to
compare against on this card.

## Rates at the larger context

C at 32768 with ngl 38, q8_0 KV, measured on a 23858-token prompt:

    prompt eval  48540 ms / 23858 tokens =  491.5 tokens/s
    eval         367.9 ms per token      =    2.72 tokens/s

Prefill at 491 tokens per second makes a full 32K prompt about 65 s, which is
affordable for retrieval testing. Decode falls from the 3.820 tok/s measured at
4096 with ngl 40 to 2.72, from two causes that the split cannot avoid: two
fewer blocks on the card, and attention over a longer sequence.

## Getting Q2 speed at a long context

The path exists and is not tested here: split the Q2_K_XL checkpoint the way C
splits Q4_K_M. At 128K, KV takes 4352 MiB and leaves about 6.1 GiB for weights,
which is roughly 39 of the 64 Q2 blocks on the card and the rest on the CPU.
That arm would be slower than resident Q2 and faster than split Q4, and it is
the obvious next measurement if long context at Q2 quality is what the work
needs.

## The split arm reaches 131072 and retrieves correctly there

Run `C-llamacpp-split-q4km-128k-ctx128k-0824-031658`, ngl 28, q8_0 KV,
six threads, serving at `n_ctx=131072` with 10186 MiB resident and 131 MiB of
the card free. A fact was planted at a known depth in a haystack of
non-repeating filler and retrieved by exact match.

| Window | Prompt tokens | Depth | Prefill | Decode | Result |
|---|---|---|---|---|---|
| 62k | 62304 | 0.02 | 377.1 tok/s | 1.29 tok/s | correct |
| 62k | 62304 | 0.50 | 383.8 tok/s | 1.30 tok/s | correct |
| 62k | 62304 | 0.98 | 388.0 tok/s | 1.31 tok/s | correct |
| 115k | 115014 | 0.02 | 329.6 tok/s | 0.79 tok/s | correct |
| 115k | 115014 | 0.50 | 333.7 tok/s | 0.71 tok/s | correct |
| 115k | 115014 | 0.98 | 330.6 tok/s | 0.69 tok/s | correct |

Six of six correct, and depth does not move the result: the fact is recovered as
reliably at two percent into the prompt as at ninety-eight. Only 42 tokens were
served from the prompt cache in each case, which is the template prefix, so
every row is a full prefill rather than a cached one.

### Retrieval holding is not the same as decoding usefully

Decode falls from 3.6 tok/s at 16384 to 1.30 at 62k and 0.73 at 115k. A
sixty-token answer costs about 46 seconds at 62k and about 86 at 115k, and the
prefill in front of it costs 165 and 348 seconds. The arm holds the context and
answers from it; it does not do so interactively.

Two changes are folded into that decline: blocks on the card fall from 38 to 28
to pay the 4352 MiB q8_0 KV bill, so more weight bytes are read from DDR4 per
token, and attention runs over a cache two orders of magnitude larger. They
separate by holding placement fixed and varying how full the cache actually is.

### The axis is occupancy, not the context the server was started with

A server given a 131072 context and handed a 64-token prompt does almost no
attention work. The allocation is not the load, and it is measurable that it is
not: at ngl 28 with 14021 tokens in the cache, decode is 2.58 tok/s whether the
server was started at 16384 or at 131072, agreeing to three significant figures.
Everything below is therefore indexed by tokens resident in the cache at
generation time. Rates are the server's own `eval time` and were cross-checked
against streamed inter-token timing, which agreed exactly at every point.

| Placement | Occupancy | Decode |
|---|---|---|
| ngl 38 | 14021 | 3.30 tok/s |
| ngl 28 | 14021 | 2.58 tok/s |
| ngl 28 | 62252 | 1.33 tok/s |
| ngl 28 | 114962 | 0.88 tok/s |

### The two terms

    block count, ngl 38 -> 28 at fixed occupancy 14021 : 3.30 / 2.58 = 1.279
    cache growth, 14021 -> 114962 at fixed ngl 28      : 2.58 / 0.88 = 2.932
                                              product  :               3.750
    measured, ngl 38 at 14021 -> ngl 28 at 114962      : 3.30 / 0.88 = 3.750

The product reproduces the measured total, so the two effects compose
multiplicatively and neither is an artifact of the other. **The cache dominates:
2.93x of the 3.75x, against 1.28x for the ten blocks that moved to the host.**
Paying for context in blocks is the cheaper half of what context costs; the
expensive half is attending over what was bought.

That ordering is worth stating because it inverts the intuition the split
mechanism invites. The arm looks like it is trading decode rate for context at
the layer boundary, and it is, but that trade is a 28 percent effect. The
remaining slowdown would be paid by any arm holding this much context, including
one that never touched the host at all.

A caveat on the absolute figures: the retrieval run above measured 0.69 to
0.79 tok/s at 115k where this one measures 0.88 at the same occupancy, and the
three retrieval requests themselves drifted from 1270 to 1444 ms per token
without occupancy changing. Run-to-run variation at this occupancy is therefore
of order 15 percent, and the decomposition is stated as ratios within one
internally consistent sweep rather than across sweeps.

### Which arm can do this

E cannot. 65536 fails outright on the 2176 MiB KV allocation with the weights
already resident, and 32768 loads only when the desktop is quiet. The resident
arm has no currency to spend: every block is already on the card, so context is
the only thing it can give back, and it runs out before 64k. The split arm pays
for context in blocks and keeps serving. That is the whole of the difference at
this end of the range, and it does not appear at all at 4096.
