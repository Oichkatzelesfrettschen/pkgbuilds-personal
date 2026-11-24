# Quality: split Q4_K_M against resident Q2_K_XL

Latency chose the mechanism; this chooses the checkpoint. The two arms the lab
ends on differ by roughly a factor of ten in decode rate, and that gap is only
worth taking if the faster arm answers as well.

## What is held equal

Two reports are comparable only when the suite, the tier, the haystack length,
the served context, and the chat template all match. Each of those was a real
near-miss here rather than a hypothetical:

- E's first report was stamped `suite_version: 1` because the suite file was
  rewritten while the run was in flight. Python reads a script once at start,
  so the run used the older definitions and the newer version string never
  applied to it. The harness is now hashed before each arm and left untouched
  until both finish.
- The first C and E runs used different haystack lengths at different contexts
  -- C at 32768 with 1180 sentences, E at 16384 with 700 -- which would have
  compared retrieval difficulty rather than retrieval ability.

Verified from each server's own `/props` rather than from the profile that
launched it, because a profile records what was requested and `/props` records
what is being served:

| | E resident Q2_K_XL | C split Q4_K_M |
|---|---|---|
| Served context | 16384 | 16384 |
| Chat template sha256 | `12827f24b742ea4e` | `12827f24b742ea4e` |
| Haystack | 700 sentences | 700 sentences |
| Suite version | 4 | 4 |
| Token budget, reasoning chains | 3072 | 3072 |
| Process VRAM | 9860 MiB | 9758 MiB |
| Resident weight fraction | 1.003 | 0.621 |

Both GGUFs carry the same 9993-character chat template, confirmed by reading
`tokenizer.chat_template` out of each file's header independently of any server.
Template equality is checked rather than assumed because a differing template
changes the prompt the model actually sees, and the resulting score difference
would be indistinguishable from a quantisation difference.

## The haystack fits by measurement, not by estimate

700 filler sentences tokenise to 13980 tokens for the standard tier and 14105
for the hard tier. Against a 16384 context and the retrieval budget of 512 and
768 tokens, the worst case is 14873, leaving roughly 1500 tokens of headroom.
1180 sentences reach 24704 and require a 32768 context, which is why the
earlier C run needed one.

## Token budget

The budget is uniform at 3072 tokens for every task whose answer is reached
through a reasoning chain, so `unusable` means one thing in every category.
Retrieval keeps 512 and 768 because its answer is a single number and a larger
cap only gives a loop room to run against a 14000-token prompt.

Arriving at that number took three passes, and the intermediate results are the
reason it is uniform:

| Budget | E standard | E hard |
|---|---|---|
| 1280 / 2048 | 14/16 usable | not run |
| 3072 / 2048 | 15/16 usable | 8/9 usable |
| 3072 uniform | 15/16 usable | 8/9 usable |

`follow-terse` recovered from truncated to 1.0 when its budget rose from 1280 to
3072, so the first pass was measuring the harness rather than the model.
`hard-reason-ratio` completed using 2644 tokens, which the 2048 budget the code
and structured tasks still carried would have cut off. Making the budget uniform
removed a category-dependent definition of failure before the expensive arm ran.

## Truncation is reported, never scored

A sample whose `finish_reason` is not `stop` hit the budget rather than
answering, so it is reported unusable rather than wrong, and the comparison runs
over the intersection of tasks both arms completed.

Two tasks resist every budget tried. `reason-units` asks for 9.4212 decimal GB
in gibibytes and `hard-code-median` asks for a running median over a list with
negative values and float ties. Both emit thousands of reasoning characters and
no answer at 1280, 2048, and 3072 tokens. A budget that three doublings do not
satisfy is describing a loop in the checkpoint, not a shortfall in the harness,
and that distinction is what the escalation established.

## Answer keys

Every exact-match and code-assertion key is verified against a reference
implementation before the arms run. This is not ceremony: three of four hard-tier
keys were wrong when first written -- the KV chain gives 30720 rather than 30115,
the ratio 1.496 rather than 1.495, and `running_median([3,-1,4,-1,5])` is
`[3, 1.0, 3, 1.0, 3]` rather than `[3, 1.0, 3, 1.5, 3]`. A wrong key scores both
arms zero and is indistinguishable from quantisation damage in the report.

## Results

Run `C-llamacpp-split-q4km-cmp16k-cmpq-0823-213825` against
`E-llamacpp-resident-q2kxl-32k-cmp16k-0823-203150`.

| | C split Q4_K_M | E resident Q2_K_XL |
|---|---|---|
| Standard, tasks completed | 16 of 16 | 15 of 16 |
| Standard, score over the 15 both completed | 1.0 | 1.0 |
| Hard, tasks completed | 9 of 9 | 8 of 9 |
| Hard, score over the 8 both completed | 1.0 | 1.0 |
| Disagreements on shared tasks | none | none |
| Standard wall | 1707.5 s | 279.1 s |
| Hard wall | 2476.1 s | 230.9 s |

Every category -- code, reasoning, structured, adherence, and all five retrieval
depths -- scores 1.0 for both arms on every task both completed. The compare
tool found no task where the two disagree.

The separation is entirely in termination:

| Task | C split Q4_K_M | E resident Q2_K_XL |
|---|---|---|
| `reason-units` | answered in 1391 tokens | 3072 tokens, no answer |
| `hard-code-median` | assertions passed in 2501 tokens | 3072 tokens, no answer |

That difference is invisible to the headline score by construction, because the
comparison runs over the intersection of completed tasks and these two are
excluded from it. Reporting truncation beside the score rather than folded into
it is what makes it visible at all.

### Two headline metrics, not one

The exclusion is the right way to score correctness and the wrong way to
summarise the arms, so both numbers stay at the top and neither substitutes for
the other:

| | C split Q4_K_M | E resident Q2_K_XL |
|---|---|---|
| conditional correctness, over tasks both completed | 1.0 | 1.0 |
| task-completion rate, all 25 | 25 of 25, 100% | 23 of 25, 92% |

The defensible reading is that Q2_K_XL was not measurably less correct on what
it finished, and was less reliable at finishing inside a fixed 3072-token
budget. Collapsing that to a single 1.0 tie would state the first half and
delete the second.

The two E failures carry more weight than an ordinary single-run loss, because
they reproduced at multiple budgets across three runs. The comparison remains
asymmetric all the same: C's successes on those same two tasks were measured
once each. A three-run replay of exactly those two C cases is the cheap way to
close it, and until it runs the completion gap is one-sided evidence rather than
a matched result.

Read as a checkpoint difference, though, this table is wrong, and the control
that shows why is in the next section. Two of these three tasks flip with
placement alone.

## The placement control, and what it costs this table

The paragraph below originally claimed the placement confound could not be
removed, because Q4_K_M does not fit resident in 12 GiB. That is true in one
direction only. The checkpoint is isolated by moving the other arm instead:
Q2_K_XL served at C's placement, ngl 38, 16384 context, q8_0 KV, six threads.

Run `P-llamacpp-split-q2kxl-cmp16k-plc-0824-084955`, 6438 MiB resident:

| Task | C Q4 split ngl 38 | E Q2 resident | P Q2 split ngl 38 |
|---|---|---|---|
| `reason-units` | stop, 1391 | **length, 3072** | stop, 1322 |
| `hard-code-median` | stop, 2501 | **length, 3072** | **length, 3072** |
| `hard-reason-ratio` | stop, 2983 | stop, 2644 | **length, 3072** |
| Truncations | **0 of 25** | 2 of 25 | 2 of 25 |

The same checkpoint, moved from fully resident to a 38-block split, answers
`reason-units` and stops answering `hard-reason-ratio`. Whatever that table
measures, it is not quantisation alone.

### A placement sweep separates the robust case from the fragile ones

Same checkpoint, same context, same 3072-token budget; only the block count on
the card changes.

| ngl | VRAM | `hard-code-median` | `hard-reason-ratio` | `reason-units` |
|---|---|---|---|---|
| 64 | 9860 MiB | length | stop, 2644 | **length** |
| 63 | 9410 MiB | length | stop, 2892 | stop, 1990 |
| 56 | 8578 MiB | length | stop, 2723 | **length** |
| 48 | 7788 MiB | length | stop, 2902 | stop, 1565 |
| 38 | 6438 MiB | length | **length** | stop, 1322 |

`reason-units` fails at 64, passes at 63, fails again at 56, then passes at 48
and 38. A quantity that reverses twice as one parameter moves in one direction
is not a function of that parameter. It is not the amount of host computation
and it is not the presence of any, so it is not placement in the sense either
phrase would mean.

What it is instead: these tasks put the model into a self-checking loop it
escapes or does not, and which way it goes turns on differences far below the
level of the mechanism. CPU and CUDA kernels accumulate in different orders, so
two arms holding identical weights emit different logits, and greedy decoding
turns an arbitrarily small logit difference into a different token and a
different trajectory. Near that threshold the outcome is decided by numerical
noise.

`hard-code-median` is the exception that survives: it truncates at every one of
the five Q2_K_XL placements and passes on Q4_K_M. That one is attributable to
the checkpoint.

### What the comparison actually supports

- **The checkpoint sets the rate.** Q2_K_XL truncates 2 of 25 at both full
  placements measured, resident and ngl 38; Q4_K_M truncates 0 of 25. Two
  independent Q2 configurations agree on the count while disagreeing on the
  members.
- **Placement, or rather numerical noise reached through placement, selects
  which tasks.** The two Q2 arms share only one of their two failures.
- **One task is robustly checkpoint-attributable.** `hard-code-median`, 5 of 5
  Q2 placements failing, Q4_K_M passing.
- **`reason-units` is not evidence of anything about the checkpoint**, and this
  document previously led with it. A single observation of a task that reverses
  under a parameter that should not affect it cannot carry an attribution.

The general form of the error is worth keeping: a difference measured once
between two arms that differ in two ways was attributed to the interesting
variable. The control was available the whole time and was dismissed on a
constraint that only bound in one direction.

### Token counts do not support a verbosity claim

E emitted 1.19 times C's completion tokens over the 23 shared tasks, but the
pattern reverses by tier: E used more on 12 of 15 standard tasks and on only 2
of 8 hard tasks. A direction that inverts between tiers is not a property of the
checkpoint, so no conclusion about reasoning length is drawn from it.

### Wall time

The wall ratio is 6.12x on the standard tier and 10.72x on the hard tier against
a decode ratio near 11x. The standard tier compresses because five of its
sixteen tasks are retrieval, which is dominated by prefilling roughly 14000
tokens at about 490 tokens per second rather than by decode, and because E spent
a full 3072-token budget on the task it failed. Neither figure is a clean
latency measurement; the latency numbers are in 06-results-matrix.md and
08-test-c-cpu-split.md.

### What follows for the choice between them

On every task this suite can check, the 2-bit checkpoint matches the 4-bit
checkpoint on answer quality, at both placements measured, and the resident
arrangement produces those answers about ten times faster. Against that, the
2-bit checkpoint failed to terminate on two of twenty-five tasks at each
placement while the 4-bit arm terminated on all of them, and it cannot reach a
context beyond 32768 under any setting, where the split arm reaches 131072.

Only one of those truncations is a stable property to plan around. The others
move with numerical noise, which means a 2-bit deployment should be expected to
loop occasionally on some task, without that task being predictable in advance
from a single measurement. The speed argument and the context argument point in
opposite directions, and which one governs depends on whether the work is
short-context interactive or long-context batch.

## What this comparison cannot settle

The two arms differ in two ways at once. The checkpoints differ, which is the
intended variable, and the placement differs -- E holds every block on the card
while C computes roughly 27 of the 65 layers on CPU kernels. The placement half is removable
after all, by serving Q2_K_XL at C's placement rather than trying to make
Q4_K_M resident, and doing so overturned this document's original finding. What
remains is that scores over the shared tasks are identical, so nothing here
distinguishes the checkpoints on answer quality; the difference is in
termination, and only one of the three termination differences survives the
control.

Every scorer here checks a short, verifiable answer. Quantisation damage is
reported to surface most in long-form coherence, multi-step agentic work, and
rare-token handling, none of which a deterministic scorer measures well. A tie
therefore supports "not measurably worse at these tasks" and does not support
"equivalent".
