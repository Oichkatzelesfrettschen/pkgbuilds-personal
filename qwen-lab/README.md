# qwen-lab

A harness for deciding where a large model's weights should live when they do
not fit in VRAM, and for proving that the chosen mechanism actually engaged.

## What it compares

| Arm | Role | Mechanism | Where arithmetic runs | Host-memory behaviour |
|-----|------|-----------|----------------------|-----------------------|
| E | **recommended interactive/throughput**, within its measured context and VRAM envelope | llama.cpp resident | GPU | none; every weight is in VRAM |
| C | **recommended capacity/long-context** | llama.cpp split | mixed CPU and GPU | host-resident layers are computed on the CPU |
| A | explicit-prefetch offload baseline | vLLM prefetch | GPU | pinned weights copied layer-wise into bounded VRAM buffers |
| B | UVA offload baseline, end-to-end rate only | vLLM UVA | GPU | GPU reads pinned host weights directly through unified addressing |
| D | managed-memory negative control | llama.cpp managed memory | GPU | fault-driven page migration |

Letters record the order the arms were run, not their rank; the profiles and the
evidence files all still reference them. A, B, and D are baselines rather than
candidates -- they measure what host-backed weights cost. A against B and C
against D are the controlled comparisons: one checkpoint, one runtime, one
variable each. E is the arm that removes the per-token bus path entirely and is
frequently the fastest at batch one; the order-of-magnitude gap between it and
the offload baselines is the lab's central result. E and C are both
recommendations rather than rivals: E for interactive work inside its envelope,
C wherever context capacity matters more than rate.

## The bound

Single-token decode reads effectively every active decoder weight once per
traversal, so any host-resident arrangement obeys

    t_token >= streamed_bytes / measured_H2D_bandwidth

The `pcie_probe` tool measures that bandwidth with `bench/h2d.cu`. Measure it
before interpreting any result, and re-measure after a BIOS, driver, or slot
change. Two properties of the measurement matter: link generation reads low at
idle because it downtrains under ASPM and trains up under load, so it must be
read during transfer; and pinned transfer is roughly twice pageable, so a
backend that silently fails to pin loses more than half the ceiling.

A CPU-resident layer obeys the same form over a different link: DDR4 read
bandwidth rather than the bus. `bench/ddr4.c` measures it, and the ratio
decides whether a conventional CPU/GPU split beats a streaming backend. On the
reference host DDR4 read is 1.46x the pinned host-to-device ceiling, and the
split wins accordingly. Both probes take a thread sweep, because SMT siblings
share one load/store path and the peak lands at one thread per physical core.

## Why a probe verb exists

A weight-offload configuration that the runtime ignores yields a server that
starts cleanly, answers requests, and holds every weight in VRAM. Nothing in
the startup output says so, and its benchmark numbers describe a configuration
the profile does not name. `run_probe` reads the runtime's own offload
accounting -- vLLM's offloader class and saved-bytes line -- and refuses to
call a run offloaded without it. For llama.cpp it measures instead of reading:
per-process VRAM from `nvidia-smi --query-compute-apps`, against checkpoint
size. Log wording is not an interface, and build b10549 dropped the
layer-placement line an earlier version of this probe parsed.

## Quality

Latency selects a mechanism; quality selects a checkpoint. `qwen-lab-quality`
scores a served model on tasks whose answers a program can check: generated
code executed against fixed assertions, arithmetic matched exactly, structured
output parsed and its fields verified, instruction adherence counted against
constraints, and a fact retrieved from a known depth in a long prompt. No model
judges another model, because that would add a third quantisation to the
measurement.

Only the assistant's `content` is scored. A reasoning model emits its chain
into `reasoning_content`, which is recorded for diagnosis and is not the
answer. A sample whose `finish_reason` is not `stop` is reported unusable
rather than wrong: it hit the token budget, which is a harness fault, and
counting it as a quality loss would blame the model for the budget. Compare two
arms only on the tasks both completed.

Report truncation beside the score rather than folded into it. A checkpoint
that never terminates on a task its counterpart answers is the difference
between them, and excluding that task from the score is what makes the
exclusion list the place the difference appears. Escalating the budget is what
separates the two readings: a task that completes at a larger budget was
measuring the harness, and one that fails at three successive budgets is
describing a loop in the checkpoint.

`--tier hard` adds multi-needle retrieval whose distractors differ from the
needle only in the entity name, an arithmetic chain in which any wrong step
poisons the result, and six simultaneous stacked constraints. It exists because
the standard tier saturated: both arms scored 1.0 on every task, which measures
nothing about either.

Verify every answer key against a reference implementation before running an
arm. Three of four hard-tier keys were wrong when first written here, and a
wrong key scores both arms zero and reads exactly like quantisation damage.

`qwen-lab-quality-compare` folds two reports over the intersection of tasks both
arms completed. It refuses a pair whose suite version, tier, haystack length,
served context, or chat template differ, reading the last two from each server's
`/props` rather than from the profile that launched it, because a profile
records what was requested and `/props` records what is being served.

## Context

KV cost follows the attention layers that keep a growing cache, which on a
hybrid model is not all of them. Qwen3.8-27B has 16 full-attention blocks among
64, so it costs 64 KiB per token at f16 and 34 KiB at q8_0 rather than four
times that. Work the figure out before choosing a context; it decides which
arms exist.

A fully resident arm cannot buy context. Every block is on the card by
definition, so KV gets whatever the checkpoint did not take and there is no
setting that trades one for the other. A split arm buys context with blocks and
pays a rate penalty instead. That difference is invisible at a small context
and decides the outcome at a large one.

Decode against block placement is steeply non-linear, so a slope measured
between two nearby placements does not extrapolate. Sweep it before budgeting
against it.

`--n-gpu-layers N` where N equals the block count is not every tensor. Backends
promote the output projection to the device only when the requested count
exceeds the block count, and on this model the difference between 64 and 99 is
204 MiB of VRAM against 1.47x of throughput. Ask for more layers than exist.

A smaller quantisation does not buy speed at a fixed split. Halving the
host-resident bytes returned 1.12x at an empty cache and nothing at working
occupancy, because a split arm is substantially bound by dequantisation
arithmetic rather than by memory delivery -- which is why the split reaches only
61 to 63 percent of its bandwidth bound where a streaming arm reaches 93. What a
smaller quantisation buys is VRAM, and VRAM should be spent on blocks: at equal
card occupancy the smaller quant fully resident served 9.8x the larger quant
split.

## Speculation

A draft model verifies k tokens in one traversal of the target, so speculation
raises the bound rather than approaching it. That makes it the right purchase
only once placement is exhausted. Measured here, a 1584 MiB draft returned
1.13x while the same memory spent on blocks returned 2.0x, so on a card with
blocks still on the host, blocks win. Check what the checkpoint ships: a
multi-token-prediction head appears in the loader output as an unused trailing
block and is usable as the draft.

## Modalities

Confirm what the checkpoint is before concluding anything from it. A
vision-language model served without a projector is a text model, and nothing
in its throughput or quality numbers says so. vLLM announces this as
`All limits of multimodal modalities supported by the model are set to 0`;
llama.cpp simply has no projector unless given one. Image tokens share the KV
cache with text, so a context budget computed for text alone does not hold once
images are in play.

## Samplers

`qwen-lab-telemetry` runs from the generated launcher and records the device
side: GPU utilisation, VRAM, PCIe traffic in both directions, link state, and
the server process's resident, locked, and swapped pages.

`qwen-lab-cpu-telemetry` and `qwen-lab-cpu-summary` record and reduce the host
side, which decides a CPU-split arm and which the device-global columns cannot
show: per-core and per-process CPU, resident set, and package power. They stay
operator-invoked rather than wired into the launcher because package energy
comes from `perf stat -a -e power/energy-pkg/`, and that needs root, which a
detached tmux session cannot obtain without a password prompt.

    qwen-lab-cpu-telemetry --out RUN/cpu.tsv --pidfile RUN/server.pid --interval 1 &
    sudo perf stat -a -e power/energy-pkg/ -I 1000 -x, sleep 1800 2> RUN/pkgpower.csv &
    qwen-lab-cpu-summary RUN/cpu.tsv RUN/pkgpower.csv <wall second serving began>

The trailing argument excludes the load phase, which pins every core on
decompression and copies that decode never repeats.

Package power separates a memory-stalled arm from a compute-bound one: cores
drawing less current while occupying more scheduler slots are waiting, not
working. That reading is what identified SMT contention in the C thread sweep.

## Serving

`qwen-lab-serve` picks a block placement and runs the server at it. The two
settings llama.cpp offers are each wrong for a desktop on their own: an explicit
`--n-gpu-layers`, including the `all` spelling that resolves to `-2`, disables
`common_fit_params` and aborts when the card is short, while `auto` always loads
but reserves a margin that costs throughput at roughly 2x per block.

    qwen-lab-serve --model .../Qwen3.8-27B-UD-Q2_K_XL.gguf \
                   --mmproj .../mmproj-F16.gguf --ctx 16384 --min-tps 30

It reads the block count and the per-token cache cost from the checkpoint's own
GGUF header, minimises free VRAM over a window rather than sampling it once,
predicts the placement that fits, and verifies it by generating a token before
believing it -- a server can reach `listening on`, take 10212 MiB, and still die
inside the first decode. Failures step down the ladder and name the allocation
that failed. A working decision is cached against the inputs that determine it,
because each attempt re-reads gigabytes of weights.

`--min-tps` names a floor. Below it the shortfall is reported with the knob that
would close it rather than served quietly, and `--mmproj-device host` is usually
that knob: the vision tower costs 917 MiB of device memory whatever the layer
count, and it runs once per image rather than once per token.

## Layout

Package content is read-only and lives under `/usr/lib/qwen-lab`. Everything a
run writes lives under `QWEN_LAB_HOME`, default `~/ai/qwen-lab`: the Python
environment, downloaded checkpoints, per-run directories, and the backend help
text that profile validation checks against. An upgrade replaces the former and
never touches the latter.

Run `qwen-lab-setup` once to create the mutable half, then register the MCP
server as the command it prints. `qwen-lab-serve` is a `/usr/bin` command
because it is what you run to serve the model rather than to measure it; its
placement cache lives under `~/.cache/qwen-lab` with the per-attempt server
logs.

## License

Unless otherwise noted, the MIT license applies to the files under
`local/qwen-lab` only. It is not a statement about the rest of the PKGBUILDS
repository, which is a collection of independently licensed packages.
