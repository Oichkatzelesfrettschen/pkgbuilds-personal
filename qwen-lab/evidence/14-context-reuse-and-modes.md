# Context reuse, recurrent checkpoints, and three serving modes

## The subsystem a weights-and-cache budget misses

Forty-eight of this model's sixty-five blocks are linear-attention and carry
recurrent state. That state is not the KV cache and is not priced by it, so a
budget built from weights plus cache has priced none of it. llama.cpp keeps
snapshots of it, and the defaults in this build are:

    --ctx-checkpoints        32      per slot
    --checkpoint-min-step    8192    tokens between checkpoints
    --cache-ram              8192    MiB, host side, a distinct mechanism

The exposure is per slot, which is why `--parallel 1` is a correctness setting
rather than a tuning preference: `--parallel` defaults to `-1`, meaning auto,
and the server will size its own slot count.

## What checkpoints buy, and what they cost

Five appending turns against a 16384 context, each adding a longer log, with
device memory sampled from outside the process between turns:

| turn | prompt_n off | prefill off | prompt_n on | prefill on |
|------|--------------|-------------|-------------|------------|
| 1    | 1435         | 1.46 s      | 1435        | 1.53 s     |
| 2    | 4216         | 3.20 s      | 2785        | 2.25 s     |
| 3    | 8426         | 6.27 s      | 4214        | 3.42 s     |
| 4    | 14067        | 10.66 s     | 5645        | 4.81 s     |

With `--ctx-checkpoints 0` the server reprocesses the whole conversation every
turn: by the fourth turn it re-reads 14067 tokens to answer a question about the
few hundred just added. With the default it re-reads 5645, and prefill falls
from 10.66 s to 4.81 s. Decode is unaffected either way, holding between 34 and
38 tok/s, because this is a prefill mechanism.

The **device** cost of that reuse, at this context, is 2 MiB: 9854 MiB with
checkpoints off and 9856 MiB with thirty-two of them allowed. That number comes
from `nvidia-smi --query-compute-apps`, which reports GPU memory and nothing
else, so it is a device-memory delta and carries no information about host cost.
Checkpoints are serialised recurrent state and the reported ~149.6 MiB apiece is
host RAM, which this instrument cannot see. **Host checkpoint cost is not
measured**; closing it needs process RSS and commit sampled across the same
walk, and matters most on the 32 GiB machines of Tract 2. Narrowing the
spacing does not change either number -- `--checkpoint-min-step 1024` produced
prompt_n 1435, 2785, 4214, 5645 and 9856 MiB, identical to the 8192 default.

That last result bounds the concern rather than confirming it. A checkpoint can
only exist where the context has tokens to span, so a 16384 context reaches two
of the thirty-two the default permits and the rest are a ceiling that is never
approached. The reported figure of roughly 149.6 MiB per checkpoint and 4.7 GiB
at the default is a long-context exposure: it needs about 262144 tokens of span
to be realised, which this card cannot hold in any case. On a 32 GiB machine
serving a genuine 128K context it is the dominant unpriced term, and it is why
`--parallel 1` matters there more than here.

## Three modes, because one set of flags cannot serve both purposes

**Capacity and one-shot correctness.** Checkpoints off, so that a measurement of
what fits is not measuring checkpoint growth as well:

    --parallel 1 --ctx-checkpoints 0 --cache-ram 0 --no-context-shift

This proves an allocation fits and measures prefill and decode at a fixed depth.
It is not a conversational mode: the table above is what it costs to hold a
five-turn conversation this way.

**Multi-turn operation.** The daily mode, and the one the recommended profile
uses:

    --parallel 1 --ctx-checkpoints 32

At a 16384 context the default spacing is already correct, because the ceiling
is never reached. At longer contexts the count is what bounds the memory, and
four or eight checkpoints hold the exposure to roughly 0.58 or 1.17 GiB while
keeping append-only reuse.

**Persistent append-only context.** The remaining 5645 tokens of turn-four
reprocessing are the tail that a stateless endpoint cannot avoid: the OpenAI
shape hands the server the whole conversation every time and the server
reconstructs what it can. A broker that owns one sequence and appends only the
new tokens would cut that tail to the new turn alone. What this lab can say is
the size of the prize -- 4.81 s of prefill per turn at 14K depth, against
roughly 1.2 s for the new tokens alone -- and that the cheaper half of it is
already obtained by leaving checkpoints on. The broker is worth building for
strictly linear agentic sessions, where branching and prompt edits are absent by
construction; it is not worth building to recover what `--ctx-checkpoints`
already recovers.

## The boundary

All three arms ended the same way. A fifth turn pushed the conversation past
16384 tokens and the server refused it with `HTTP 400`, exactly as a single
oversized file upload is refused. Context is the binding limit on this card for
conversational work, and it is reached in five turns of a few hundred lines
each.
