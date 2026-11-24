# The placement curve, speculation, and the vision tower

The arms in 06, 08, and 10 compared mechanisms at a fixed placement. Sweeping
placement on one checkpoint turns out to matter more than the choice of
mechanism, and two capabilities the model ships with had never been switched on.

## Decode against block placement

Qwen3.8-27B-UD-Q2_K_XL, 16384 context, q8_0 KV, six threads. Rates from
streamed inter-token timing, cross-checked against the server's own `eval time`,
which agreed within five percent at every point.

| n-gpu-layers | Process VRAM | Decode, empty cache | Decode, 14021 tokens |
|---|---|---|---|
| 38 | 6438 MiB | 4.10 tok/s | 3.14 tok/s |
| 44 | 7330 MiB | 4.49 tok/s | -- |
| 56 | 8578 MiB | 10.46 tok/s | 9.11 tok/s |
| 63 | 9410 MiB | 18.26 tok/s | 17.48 tok/s |
| 64 | 9516 MiB | 24.16 tok/s | 23.43 tok/s |
| 99 | 9720 MiB | 36.10 tok/s | 34.45 tok/s |

The curve is steeply non-linear. The 1.28x per ten blocks measured on Q4_K_M
between ngl 28 and 38 is a local slope near the bottom of this curve and does
not extrapolate.

## `--n-gpu-layers 64` is not every block, and the layer count is 65

The checkpoint carries 64 decoder blocks plus a `blk.64` multi-token-prediction
head, and `qwen35.block_count` counts all 65. llama.cpp takes its layer index
from that key, so `-ngl 64` leaves one of the 65 on the host and `-ngl all`
resolves to 66. The promotion identity confirms it independently: `all` measures
identical to 66 and strictly faster than 65, which can only hold if the layer
count is 65 and promotion happens one past it.

That makes the 204 MiB and **1.47x** between `ngl 64` and `ngl 99` a composite
of two steps, not one:

| step | VRAM | decode | ratio |
|---|---|---|---|
| ngl 64 | 9516 MiB | 24.43 tok/s | -- |
| ngl 65 | 9618 MiB | 28.17 tok/s | 1.15x |
| ngl 66 | 9720 MiB | 39.22 tok/s | 1.39x |
| ngl `all` | 9720 MiB | 39.27 tok/s | 1.00x, `all` == 66 |

Attributing the whole 1.47x to `output.weight` was wrong, and the checkpoint's
own tensor table says the residual attribution is wrong too. Sizes below are
offset deltas from the GGUF tensor index, which sum to 9363 MiB against a
9374 MiB file and therefore account for it:

| tensor | size |
|---|---|
| `blk.0` | 109.72 MiB |
| `blk.1` | 101.51 MiB |
| `blk.32` | 116.36 MiB |
| `blk.63` | 180.67 MiB |
| `blk.64`, the MTP head | 334.73 MiB |
| `output.weight` | 682.03 MiB |
| `token_embd.weight` | 397.85 MiB |

Both rungs are decoder blocks, and the pinned source says which. b10549
(`b2e5e9b28b2484fbf94b543432ece638996a8b97`) builds a suffix over `n_layer_all +
1` slots, `llama-model.cpp:1361`:

    const int i_gpu_start = std::max(n_layer_all + 1 - n_gpu_layers, 0);

with `n_layer_all` read from `qwen35.block_count` (line 1118), the output tensor
taking the extra slot at index `n_layer_all` (line 1386), and `-ngl all`
resolving to `n_layer_all + 1` (line 1754). The slots are 0..63 decoder blocks,
64 the MTP block an ordinary target-model load does not execute, and 65 the
output layer, so `i_gpu_start = 66 - ngl`:

| ngl | i_gpu_start | what the suffix covers | decoder blocks executing on GPU |
|---|---|---|---|
| 64 | 2 | `blk.2..63`, MTP slot, output | 62 |
| 65 | 1 | `blk.1..63`, MTP slot, output | 63 |
| 66, `all` | 0 | `blk.0..63`, MTP slot, output | 64 |

So 64 -> 65 adds `blk.1` at 101.51 MiB and 65 -> 66 adds `blk.0` at 109.72 MiB,
against measured steps of 102 MiB each. **The output layer is already on the
device at ngl 64**, because slot 65 is the last slot every one of these suffixes
reaches. That is why the 682.03 MiB tensor ledger refuted output promotion: no
promotion occurs at either transition.

The 1.39x at the second rung is therefore not an unidentified allocation. It is
the removal of the last host-resident decoder block, and with it the CPU
execution of that block and the device-to-host-to-device boundary its inputs and
outputs had to cross every token. One block is worth 1.15x when 62 are already
resident and 1.39x when it is the last one, because the last one is the only one
still forcing a round trip.

This is the tensor whose placement 10-quality-c-vs-e.md names as a candidate
mechanism for the truncation flips, and it is the last operation before greedy
sampling. It is not the whole explanation there: ngl 63, 56, 48 and 38 all keep
it on the host and still disagree with each other about which tasks truncate.

## A smaller quant does not buy speed at a fixed split

At ngl 38 the host holds roughly 4.0 GiB of Q2_K_XL against 6.4 GiB of Q4_K_M,
and the DDR4 bound predicts about 1.6x.

| Occupancy | Q4_K_M ngl 38 | Q2_K_XL ngl 38 |
|---|---|---|
| empty | 3.67 tok/s | 4.10 tok/s |
| 14021 | 3.30 tok/s | 3.14 tok/s |

1.12x at an empty cache and nothing at working occupancy. The split arm is
substantially bound by CPU dequantisation rather than by DDR4 delivery, and
2-bit K-quant unpacking costs more arithmetic per weight than 4-bit does. This
is why 08-test-c-cpu-split.md found the split reaching only 61 to 63 percent of
its bandwidth bound while the prefetch arm reached 93 percent of its own.

What a smaller quant buys is VRAM, and VRAM should be spent on blocks:

| | VRAM | Decode |
|---|---|---|
| Q4_K_M, ngl 38 | 9758 MiB | 3.67 tok/s |
| Q2_K_XL, ngl 99 | 9720 MiB | **36.10 tok/s** |

Same card occupancy, **9.8x the throughput**.

## Speculation with the MTP head works and is the wrong purchase here

`MTP/mtp-Qwen3.8-27B-Q4_0.gguf` is the `blk.64` the loader has not been running
as an unused tensor since the first run. It loads as `--spec-draft-model` and
speculative decoding runs.

| Configuration | VRAM | Decode |
|---|---|---|
| ngl 44 | 7330 MiB | 4.80 tok/s |
| ngl 44 plus MTP draft | 8914 MiB | 5.42 tok/s |
| ngl 56 | 8578 MiB | 9.57 tok/s |

The draft costs 1584 MiB and returns 1.13x. The same memory spent on blocks
returns 2.0x, and slightly less memory than the draft configuration uses. On a
card where placement is not yet maxed, blocks beat speculation.

Speculation raises the bound rather than approaching it, so it remains the right
purchase once every block is resident and memory is left over. That is not this
card at this context. At ngl 56 with the draft the pair loaded and then died
allocating compute buffers on the first request, which is the same failure the
ngl 42 attempt and vLLM's attention workspace produced: weights resident,
buffers homeless.

## The vision tower

The checkpoint is `Qwen3_5ForConditionalGeneration` and carries a
`vision_config`. Every measurement in this lab before this section describes the
text tower: vLLM logged `All limits of multimodal modalities supported by the
model are set to 0, running in text-only mode`, its profile sets
`language-model-only`, and no projector had been fetched for llama.cpp.

`mmproj-F16.gguf` was in the same repository as the GGUFs, 927607488 bytes.
Loaded with `--mmproj` at ngl 56, 9700 MiB resident, the model reads a
generated image of four coloured shapes and answers `red square, blue circle,
green triangle, yellow square`, correct and complete, in 13.7 s with
`finish_reason` `stop`.

llama.cpp warns that Qwen-VL needs at least 1024 image tokens for grounding
tasks and that `--image-min-tokens 1024` should be set if accuracy is poor. The
KV arithmetic in 09-context-capability.md counts text tokens only; image tokens
enter the same cache and have not been budgeted.
