# Fitting the card, and what each request shape costs

## The recommendation that never loaded

`12-serving.md` and `F-llamacpp-resident-q2kxl-full.toml` published a command
pairing `--n-gpu-layers 99` with `--mmproj`, and attached 9720 MiB and
36.20 tok/s to it. That configuration has never loaded on this machine. The
measurement behind those numbers was text-only: the run log carries no
`clip_init` and no multimodal load line. Adding the projector aborts the
process:

    common_fit_params: failed to fit params to free device memory:
      n_gpu_layers already set by user to 99, abort
    ggml_backend_cuda_buffer_type_alloc_buffer: allocating 884.62 MiB on
      device 0: cudaMalloc failed: out of memory
    #7  clip_init  #10 mtmd_init_from_file

The projector is allocated after the text model is placed, so the failure lands
at the end of a two-minute load rather than at argument parsing. Both files are
corrected; this records why.

## Three spellings of --n-gpu-layers, and only one keeps fitting on

`-ngl` accepts an integer, `all`, or `auto`, and defaults to `auto`. The first
two disable `common_fit_params`, which is the routine that sizes unset arguments
to the memory that exists. `all` resolves to `-2` and aborts fitting exactly as
`99` does, so it is not a safer spelling of the same request:

    n_gpu_layers already set by user to -2, abort

That is the whole dynamic-VRAM story. llama.cpp can adapt to the card it finds,
and any explicit layer count turns that off. With fitting left on, the same
command that aborts instead loads at a lower placement: with another process
holding 900 MiB, `auto` took 8028 MiB rather than failing.

## Where the vision tower should live

The projector costs 917 MiB of device memory and is charged in full at every
layer count, because it is neither a block nor part of the cache. On a 12282 MiB
card holding a 1935 MiB desktop, that is about six blocks -- and blocks near the
top are worth roughly 2x each. Paying for the projector in blocks is paying in
the most expensive currency the card has.

The vision tower runs once per image during prefill, not once per token, so the
device is the wrong place for it. `--no-mmproj-offload` keeps it in host memory:

| projector       | VRAM     | chat  | vision | image TTFT |
|-----------------|----------|-------|--------|------------|
| on the device   | 10138    | 17.08 | --     | --         |
| on the host     | 9720     | 33.82 | 31.45  | 4.90 s     |
| on the host     | 9720     | 36.70 | 36.44  | 4.45 s     |
| absent entirely | 9720     | 32.18 | --     | --         |

Host projector and no projector reach the same 9720 MiB and the same decode
rate, so the tower costs nothing while idle. It is paid for once per image, in
prefill, and the model answers a four-shape grounding question correctly at
either placement. This is the finding that makes vision and a 30 tok/s floor
compatible on this card, and it reverses the conclusion the on-device sweep was
heading toward.

## The fit margin is a throughput dial, not a safety setting

`--fit-target` reserves memory per device, default 1024 MiB. With the projector
on the device, reclaiming that margin is worth more than doubling:

| --fit-target | VRAM  | tok/s |
|--------------|-------|-------|
| 1024         | 9120  | 6.10  |
| 512          | 9714  | 9.50  |
| 256          | 9918  | 12.53 |
| 128          | 10064 | 13.58 |
| 64           | 10064 | 12.68 |

Explicit placement reaches higher than fitting does at the same memory, because
fitting is conservative about the projector:

| -ngl, projector on device | VRAM  | tok/s |
|---------------------------|-------|-------|
| 64                        | --    | aborts in `clip_init` |
| 62                        | 10138 | 17.08 |
| 60                        | 10178 | 15.02 |
| 58                        | 9918  | 12.56 |
| 56                        | 9714  | 10.55 |

Text-only, the gap closes entirely. `auto` at a 64 MiB margin and `all` reach
the same 9720 MiB and the same rate, 36.35 against 34.18, which is inside
run-to-run spread:

    auto --fit-target 64   9720 MiB   36.35 tok/s
    all                    9720 MiB   34.18 tok/s

So `auto` with a small margin is not a compromise. It matches the fastest
explicit placement when there is room and degrades instead of aborting when
there is not, which is what a desktop needs.

## Where the promotion actually happens

`11-placement-curve-and-capabilities.md` reported 64 as a trap worth 1.47x and
99 as the fix, but never measured between them, and the GGUF header says this
model has 65 blocks rather than 64. Measured at a 16384 context with the rate
read from llama.cpp's own timings:

| -ngl | VRAM  | tok/s | what it holds |
|------|-------|-------|---------------|
| 64   | 9516  | 24.43 | one block and the output projection on the host |
| 65   | 9618  | 28.17 | every block, projection still on the host |
| 66   | 9720  | 39.22 | everything, projection promoted |
| all  | 9720  | 39.27 | identical to 66 |

So `all` is exactly `blocks + 1`, and the two steps are separable: the
sixty-fifth block costs 102 MiB and buys 1.15x, the output projection costs
another 102 MiB and buys 1.39x. Together, 204 MiB for 1.61x.

This matters to the step-down ladder. A rung at 65 is not a rounding of `all`
and not a trap: it is the smallest memory reduction available, 102 MiB for a
known 1.39x, and it is the right rung to try when `all` does not fit.

## A load that succeeds is not a configuration that serves

At `-ngl 64` with the projector and a 4096 context, the server printed
`listening on`, took 10212 MiB, and died inside the first decode:

    ggml-cuda.cu:106: CUDA error
    CUDA error: out of memory

The graph reserved at load is not every allocation inference makes. Any tool
that picks a placement has to generate a token before believing it, so the probe
generation is a rung of the ladder rather than a report on it.

## The envelope, and the instrument that understated it

The first sampler summed `--query-compute-apps` into a `nonmodel_mib` column and
reported 518 to 540 MiB over 89.9 idle minutes. That query enumerates CUDA
contexts, and a desktop keeps most of its VRAM in graphics contexts, so the
column understated the true figure by about 1.4 GiB -- more than the margin it
existed to protect. Its `free_mib` column was honest, and the figures once
quoted here were recomputed from it.

The corrected sampler records total minus free minus the inference server's own
draw, and has now been run: 470 samples over 39.2 minutes, 45 of them with a
server loaded.

| samples                       | non-model VRAM        |
|-------------------------------|-----------------------|
| 276 with no server on the card| 1924 to 2124 MiB      |
| 45 with a server loaded       | 1930 to 1932 MiB      |

The second row is the check that matters. While a 9720 MiB server held the card,
the reported non-model figure stayed inside 2 MiB, which is what a correct
subtraction looks like; the broken column would have moved by gigabytes.

The first row finally caught the event the idle window could not. For fifteen
seconds a fourth compute process appeared, took the desktop from 1924 to
2124 MiB, and left. Two hundred megabytes, which on this card is the difference
between 24.43 and 39.22 tok/s if it lands during a load. That is one measured
event rather than a distribution, so it bounds nothing -- but it is the shape of
the thing a reserve exists for, and `qwen-lab-serve` reserving 384 MiB by
default is sized above it rather than by taste.

## What each request shape costs

The endpoint serves three request shapes, not five. A file upload is a prompt:
no file API exists in `llama-server`, so a front end reads the bytes and sends
text. A skill is a system prompt plus tool definitions. Images are the one
genuinely separate path, because the projector emits tokens into the same cache
the text is using.

Measured against the recommended configuration -- Q2_K_XL, `auto` at a 64 MiB
margin, 16384 context, tower on the host, 9720 MiB on the card -- with every row
read from llama.cpp's `timings` so the rows are comparable to each other:

| request shape                      | tok/s | prefill | tokens | termination |
|------------------------------------|-------|---------|--------|-------------|
| chat, short answer                 | 37.20 | 0.55 s  | 49     | stop |
| chat, long answer                  | 37.91 | 0.20 s  | 232    | stop |
| file upload, 10187 prompt tokens   | 36.39 | 7.71 s  | 512    | budget |
| file upload, 18851 prompt tokens   | --    | --      | --     | HTTP 400 |
| tools declared, not called         | 38.05 | 0.41 s  | 66     | stop |
| one tool call                      | 38.24 | 0.20 s  | 76     | tool_calls |
| three tool calls                   | 37.93 | 0.21 s  | 223    | tool_calls |
| image, four shapes, answered right | 38.01 | 0.83 s  | 384    | budget |
| skill: system, tools, and a log    | 37.89 | 0.11 s  | 1265   | tool_calls |

Every shape clears 30 tok/s, and the spread across all of them is 36.39 to
38.24 -- narrow enough that request shape is not a throughput variable on this
configuration at all. Prefill is where the shapes differ, and it tracks prompt
length as it must: 7.71 s for a ten-thousand-token upload against 0.2 s for a
one-line question.

### The envelope the 30 tok/s result holds inside

The claim is not that this configuration serves 30 tok/s. It is narrower, and
the qualifiers are the finding rather than hedging:

> Q2_K_XL, one slot, adaptive placement, multimodal projector on the host,
> ordinary compositor load, and up to roughly 14K of occupied context sustain at
> least 32 tok/s of **server-reported decode** across the chat, long-answer,
> file-upload, image, skill, and tool-call request forms.

What it does not establish, and what no measurement here speaks to:

| unestablished | why it is open |
|---|---|
| 30 tok/s at 32K or deeper occupancy | measured to 14021 tokens and no further; 09 shows the rate falls with depth |
| 30 tok/s under concurrent requests | every figure is `--parallel 1`, batch one |
| 30 tok/s end to end | the floor is a decode floor; prefill in the divisor put the same run at 31.35 |
| image encode latency parity | the image row reports post-prefill decode, not the projector's own cost |
| immunity to larger VRAM excursions | the envelope walk caught a 200 MiB transient; it does not bound the worst case |

The projector placement result is a decode result specifically. Moving the tower
to the host trades a once-per-image cost for language-model residency that every
generated token uses, which is unambiguously right for long answers. A short
answer to an image question could still prefer the tower on the device, and
deciding that needs image encode time, prompt evaluation, first token, and total
request time reported separately rather than a single decode figure.

An earlier version of this table put chat at 33.36 and one tool call at 23.15,
and both were the instrument. See the retraction below.

The skill shape is resolved. It failed to terminate at 384 and again at 1024
tokens, which looked like a reasoning loop; escalating settles it. At 2048 it
stopped on its own after 1265 tokens with `finish=tool_calls`, having reached
the `get_weather` call its procedure asked for. It was a budget shortfall, and
the budget needed was four times the first guess. The escalation also shows the
prefix cache working: `prompt_n` fell from 1921 on the first request to 4 on the
repeats.

Decode holds against cache depth, which is where a floor is usually lost:

| occupancy   | decode tok/s | TTFT    |
|-------------|--------------|---------|
| 68 tokens   | 32.36        | 1.21 s  |
| 5943 tokens | 34.07        | 5.43 s  |
| 14021 tokens| 32.03        | 12.12 s |

Prefill grows with the prompt, as it must, but the per-token rate does not fall
across the served context.

## The supervisor

`qwen-lab-serve` makes the placement decision the two llama.cpp settings leave
open. It reads block count and the per-token cache cost from the checkpoint's
own GGUF header, minimises free VRAM over a window rather than sampling it once,
predicts the placement that fits, verifies by generating a token, and steps down
only when a load or a probe actually fails. A successful decision is cached
against the inputs that determine it, because each attempt re-reads gigabytes of
weights.

It takes `--min-tps`, and reports the shortfall with the knob that would close
it rather than serving quietly below the floor. On this card, with the projector
on the device, no placement reaches 30 tok/s; with the tower on the host, every
request shape does.
