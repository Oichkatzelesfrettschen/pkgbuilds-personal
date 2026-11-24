# Root of the qwen-lab mutable state: the Python environment, downloaded
# checkpoints, per-run directories, and captured backend help text. The
# packaged tooling under /usr/lib/qwen-lab is read-only and holds none of it.
export QWEN_LAB_HOME="${QWEN_LAB_HOME:-$HOME/ai/qwen-lab}"
