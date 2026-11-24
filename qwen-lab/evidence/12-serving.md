# Serving it: one command, and what may sit in front of it

The lab answers which configuration to run. This is how to drive it, and the
constraint that decides the front end is the one the measurements produced:
204 MiB of VRAM is the difference between 24.63 and 36.20 tok/s, so anything
that takes a slice of the card is spending throughput, not just memory.

## The server

    qwen-lab-serve \
      --model .../Qwen3.8-27B-UD-Q2_K_XL.gguf \
      --mmproj .../mmproj-F16.gguf \
      --ctx 16384 --min-tps 30

which measures free VRAM over a window, picks a placement, verifies it by
generating a token, and reports the shortfall if it cannot reach the floor. The
command it settles on here is:

    llama-server \
      --model .../Qwen3.8-27B-UD-Q2_K_XL.gguf \
      --mmproj .../mmproj-F16.gguf --no-mmproj-offload \
      --n-gpu-layers auto --fit-target 64 --threads 6 \
      --ctx-size 16384 --cache-type-k q8_0 --cache-type-v q8_0 \
      --flash-attn on --parallel 1 \
      --host 127.0.0.1 --port 8807 --alias qwen38

Packaged as `F-llamacpp-resident-q2kxl-full.toml`. Five of those values are
measurements rather than preferences, and `13-fitting-vram-and-modalities.md`
carries the runs:

- `--no-mmproj-offload`. The vision tower costs 917 MiB of device memory,
  charged whatever the layer count, which is about six blocks -- and blocks near
  the top are worth roughly 2x each. It runs once per image during prefill, so
  on the host it costs image latency and nothing else: 33.82 tok/s against 17.08
  at the best on-device placement, at 9720 MiB either way.
- `--n-gpu-layers auto`, not 99 and not `all`. Both of those disable
  `common_fit_params` and abort when the card is short; `all` resolves to `-2`
  and aborts exactly as 99 does. At a 64 MiB margin `auto` reaches the same
  9720 MiB and the same rate as `all`, and loads rather than aborting when
  another process takes 900 MiB.
- `--threads 6`, one per physical core. Twelve is 1.87x slower while package
  power falls, because SMT siblings share one load/store path.
- `q8_0` KV. f16 at 16384 costs about 1 GiB against roughly 1.1 GiB of budget.
- `--ctx-size 16384` costs 544 MiB of cache against a card holding a desktop
  measured between 1923 and 1955 MiB over 90 minutes. Headroom is budgeted, not
  discovered.

An earlier version of this section paired `--n-gpu-layers 99` with `--mmproj`
and attached 9720 MiB and 36.20 tok/s to the pair. That measurement was
text-only and the pair never loaded: the projector is allocated after the text
model and the process aborts inside `clip_init`.

## What the endpoint already supports

`--jinja` is **on by default**, so the chat template's tool-calling path works
without further flags; any OpenAI-compatible client that emits `tools` will get
tool calls back.

`--reasoning-format` controls whether the chain is extracted into
`reasoning_content` or left inline. This matters more than it looks: this model
routinely spends a whole small token budget reasoning and returns an empty
`content`, which reads downstream as a dead server. Two measurements in this lab
were misread that way before the cause was found. A client that shows nothing
should be checked against `reasoning_content` before the server is blamed.

`--mmproj` makes the endpoint multimodal; images go in the standard
`image_url` content part as a `data:` URI. llama.cpp warns that Qwen-VL wants at
least 1024 image tokens for grounding work, `--image-min-tokens 1024`. Those
tokens share the KV cache with text. Keep the tower on the host with
`--no-mmproj-offload`: the endpoint stays multimodal, the grounding answers stay
correct, and every block stays on the card.

There is no file API. A front end that offers "upload a file" reads the bytes
and puts them in the prompt, so the limit is the context and the server reports
the overflow rather than truncating: a 700-line log tokenised to 18837 and came
back `HTTP 400, request exceeds the available context size`. Text of that shape
runs about 2.6 characters to the token, not the 3.6 a prose estimate assumes.

Upstream llama.cpp embeds a SvelteKit web UI in `llama-server` and enables it by
default, with image input, PDF and text attachment, JSON-schema constrained
generation, conversation branching, and an experimental MCP proxy. **This build
has it.** Open the server's address in a browser and it is there.

That took two tries to establish, and the first answer was wrong in a way worth
recording. `GET /` returned `HTTP 415` and 44 bytes of `text/plain`, which was
read as a build without the web assets, and the reading survived into a published
document and a package comment. The 44 bytes were never opened. They say:

    Error: gzip is not supported by this browser

The assets are stored gzip-encoded and served only to a client that advertises
it. `curl` does not, unless asked. `curl --compressed` returns `HTTP 200` and a
static SvelteKit build. A status code was treated as a diagnosis, and 415,
Unsupported Media Type, was in fact describing exactly what had gone wrong.

**Use the built-in UI.** It is maintained, does more than anything shipped here,
and costs the card nothing.

The package also ships a single-file page at
`/usr/share/qwen-lab/webui/index.html`, served by `llama-server` itself:

    --path /usr/share/qwen-lab/webui

It exists as a diagnostic panel rather than as a better chat client, and three of
its behaviours come from measurements in this lab: it folds `reasoning_content`
beside the answer and says so when the answer is empty, it counts an attachment
at 2.6 characters per token and warns before the server returns a 400, and it
reports prefill and decode separately per request because the floor this lab was
built around is a decode floor. It is one file of vanilla HTML and JavaScript
with no build step, which is the shape the maintained third-party options take
too -- `chatbox-lite` and `vllm-chat-template` are each one file against any
OpenAI-compatible endpoint.

## Choosing a front end by what it costs the card

| Option | Cost on the card | Notes |
|---|---|---|
| OpenAI-compatible client, CLI or editor plugin | none | coding, scripting, agents |
| Static assets via `--path` | none | `llama-server` serves them itself; the packaged diagnostic page uses this |
| Upstream llama.cpp web UI | none | built in and enabled by default; the recommended choice |
| Browser front end (Open WebUI, LibreChat) | none beyond a browser already running | full surface: images, tools, history |
| Electron desktop client | a GPU process of its own | measured at 103 MiB here |

The last row is the one this lab can put a number on. A Discord GPU process
appearing mid-session moved free VRAM by roughly that much and was the
difference between a 32768 context loading and failing. Against a configuration
where 204 MiB buys 1.47x of throughput, a dedicated Electron client is the most
expensive way to get a chat box.

For coding, the endpoint is ordinary OpenAI-compatible: point the editor plugin
at it. Fill-in-the-middle is a separate matter -- llama.cpp's `--fim-qwen-*`
presets fetch dedicated small coder models, and hosting one alongside costs
VRAM that, on this card, buys more by staying in blocks.
