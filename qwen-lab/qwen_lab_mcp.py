#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = ["mcp>=2.0.0"]
# ///
"""Granular control of local inference backends for the Qwen weight-offload lab.

The lab compares mechanisms that all produce a working server and differ only
in where weights live and how they reach the GPU. That shape drives three
design decisions here.

Profiles are data, and every flag in one is checked against the help text
captured from the installed binary before anything launches. vLLM's offload
vocabulary is recent and moves between releases, so a profile that names a flag
this build does not have is a defect that belongs at validation time, not at
launch time forty seconds into weight loading.

Startup is not evidence of offloading. vLLM emits specific lines when an
offloader is installed -- the offloader class name, the prefetch backend's
saved-bytes and buffer-pool line, the UVA backend's offloaded-parameter total
-- and a configuration that is silently ignored produces a server that answers
requests with every weight resident. `run_probe` reads those lines and the
resident VRAM together and refuses to call a run offloaded without them.

Preflight gates on host memory, not just VRAM. Offloaded weights are held in
pinned pages, which cannot be swapped or compressed, and this host has 31 GiB
total against a 19.5 GiB checkpoint with systemd-oomd armed. A run that pins
past the available floor takes the desktop down with it.
"""

import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import time
import tomllib
from dataclasses import dataclass, field
from difflib import get_close_matches
from pathlib import Path

try:
    # mcp 2.x renamed the high-level server; the decorator and run() shapes match.
    from mcp.server import MCPServer as _Server
except ImportError:  # mcp 1.x
    from mcp.server.fastmcp import FastMCP as _Server

LAB = Path(os.environ.get("QWEN_LAB_HOME", Path.home() / "ai" / "qwen-lab"))
PROFILES = LAB / "profiles"
RUNS = LAB / "runs"
EVIDENCE = LAB / "evidence"
SCRIPTS = LAB / "scripts"
VENV_BIN = LAB / ".venv" / "bin"

TMUX_PREFIX = "qwenlab-"
GIB = 1024 ** 3

# Sustained pinned H2D measured by bench/h2d.cu on this host.
H2D_GIB_S = 24.06

# Lines vLLM emits when an offloader is actually installed. Taken from
# vllm/model_executor/offloader/{base,prefetch,uva}.py in the installed build,
# so a version bump that reworks them shows up as an UNCONFIRMED probe rather
# than as a false positive.
OFFLOAD_SIGNATURES = {
    "offloader_class": re.compile(r"Offloader set to (\w+)"),
    "prefetch_summary": re.compile(
        r"\[PrefetchOffloader\] Initialized (\d+) modules\.\s*"
        r"Total GPU memory saved: ([\d.]+) GB,\s*"
        r"Static buffer pool: ([\d.]+) GB\s*"
        r"\(group_size=(\d+), num_in_group=(\d+), prefetch_step=(\d+), mode=([^)]*)\)"
    ),
    "uva_total": re.compile(r"Total CPU offloaded parameters:\s*(\S+\s*\S*)"),
}

READY_MARKERS = (
    "Application startup complete",     # vLLM / uvicorn
    "Uvicorn running on",
    "listening on http",                # llama-server b10549: "llama_server: listening on http://..."
    "server is listening",              # older llama-server wording
    "main: server is listening",
)

# Lines that mean the run is over. Weight loading with host offload legitimately
# takes minutes, so aborting on the wrong marker throws away a healthy run.
FATAL_MARKERS = (
    "torch.OutOfMemoryError",
    "CUDA out of memory",
    "Engine core initialization failed",
    "error loading model",
    "failed to load model",
    "Address already in use",
    # vLLM runs its engine in a child process, so a child killed by the OOM
    # reaper leaves the parent alive and the pidfile still resolving. Without
    # these the wait sits out its full timeout on an already-dead run.
    "Killed",
    "EngineCore died",
    "Engine core proc died",
    "engine core initialization failed",
)

# Lines that only mean failure once the process has also exited. vLLM prints
# tracebacks and RuntimeErrors during normal startup while probing attention
# backends and falling back on compilation paths, so on their own they say
# nothing about whether the server will come up.
SOFT_MARKERS = (
    "Traceback (most recent call last)",
    "RuntimeError:",
)

FAILURE_MARKERS = FATAL_MARKERS + SOFT_MARKERS

mcp = _Server("qwen-lab")


# --------------------------------------------------------------------------
# host and process state
# --------------------------------------------------------------------------

def _meminfo():
    out = {}
    with open("/proc/meminfo") as fh:
        for line in fh:
            key, _, rest = line.partition(":")
            try:
                out[key] = int(rest.split()[0])
            except (ValueError, IndexError):
                pass
    return out


def _gpu_state():
    fields = "memory.used,memory.total,utilization.gpu,pcie.link.gen.gpucurrent,pcie.link.width.current"
    try:
        raw = subprocess.run(
            ["nvidia-smi", f"--query-gpu={fields}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=8, check=True,
        ).stdout.strip().splitlines()[0]
        used, total, util, gen, width = (p.strip() for p in raw.split(","))
        return {
            "vram_used_mib": int(used), "vram_total_mib": int(total),
            "vram_free_mib": int(total) - int(used),
            "gpu_util_pct": int(util),
            "pcie_gen_current": int(gen), "pcie_width_current": int(width),
            "note": "link generation downtrains at idle; it is not a negotiation failure",
        }
    except Exception as exc:
        return {"error": f"nvidia-smi unavailable: {exc}"}


def _tmux(*args, timeout=10):
    return subprocess.run(["tmux", *args], capture_output=True, text=True, timeout=timeout)


def _sessions():
    res = _tmux("list-sessions", "-F", "#{session_name}\t#{session_created}")
    if res.returncode != 0:
        return []
    out = []
    for line in res.stdout.splitlines():
        name, _, created = line.partition("\t")
        if name.startswith(TMUX_PREFIX):
            out.append({"session": name, "run_id": name[len(TMUX_PREFIX):],
                        "created_epoch": int(created or 0)})
    return out


def _run_dir(run_id):
    return RUNS / run_id


def _read_pid(run_id):
    pidfile = _run_dir(run_id) / "server.pid"
    try:
        pid = int(pidfile.read_text().strip())
        return pid if Path(f"/proc/{pid}").exists() else None
    except (OSError, ValueError):
        return None


# --------------------------------------------------------------------------
# profiles
# --------------------------------------------------------------------------

@dataclass
class Profile:
    name: str
    path: Path
    raw: dict
    backend: str
    model: str
    port: int
    args: dict = field(default_factory=dict)
    env: dict = field(default_factory=dict)
    pin_budget_gib: float = 0.0
    vram_budget_gib: float = 0.0
    streamed_gib_per_traversal: float = 0.0
    description: str = ""


def _load_profile(name):
    path = PROFILES / (name if name.endswith(".toml") else f"{name}.toml")
    if not path.exists():
        available = sorted(p.stem for p in PROFILES.glob("*.toml"))
        raise FileNotFoundError(f"no profile {name!r}; available: {available}")
    raw = tomllib.loads(path.read_text())
    missing = [k for k in ("backend", "model", "port") if k not in raw]
    if missing:
        raise ValueError(f"profile {name} is missing required keys: {missing}")
    return Profile(
        name=path.stem, path=path, raw=raw,
        backend=raw["backend"], model=raw["model"], port=int(raw["port"]),
        args=raw.get("args", {}), env={k: str(v) for k, v in raw.get("env", {}).items()},
        pin_budget_gib=float(raw.get("pin_budget_gib", 0.0)),
        vram_budget_gib=float(raw.get("vram_budget_gib", 0.0)),
        streamed_gib_per_traversal=float(raw.get("streamed_gib_per_traversal", 0.0)),
        description=raw.get("description", ""),
    )


def _known_flags(backend):
    """Flags the installed binary accepts, from its captured help text."""
    capture = EVIDENCE / ("03-vllm-serve-help.txt" if backend == "vllm"
                          else "05-llama-server-help.txt")
    if not capture.exists():
        return None, f"no captured help at {capture}; run lab_refresh_help first"
    flags = set(re.findall(r"(?<![\w-])(--[a-z0-9][a-z0-9-]*)", capture.read_text()))
    return flags, None


def _argv(profile):
    """Render the profile into an argv list, exactly as it will be executed."""
    if profile.backend == "vllm":
        argv = [str(VENV_BIN / "vllm"), "serve", profile.model,
                "--port", str(profile.port)]
    elif profile.backend == "llamacpp":
        binary = shutil.which("llama-server") or "/opt/llama-cpp/bin/llama-server"
        argv = [binary, "--model", profile.model, "--port", str(profile.port)]
    else:
        raise ValueError(f"unknown backend {profile.backend!r}; expected vllm or llamacpp")

    for key, value in profile.args.items():
        flag = f"--{key.replace('_', '-')}" if not key.startswith("-") else key
        if value is True:
            argv.append(flag)                     # store_true flags carry no value
        elif value is False or value is None:
            continue                              # absent rather than negated
        elif isinstance(value, (list, tuple)):
            argv.append(flag)
            argv.extend(str(v) for v in value)
        elif isinstance(value, dict):
            argv.extend([flag, json.dumps(value)])  # vLLM accepts JSON for nested config
        else:
            argv.extend([flag, str(value)])
    return argv


# --------------------------------------------------------------------------
# tools: orientation
# --------------------------------------------------------------------------

@mcp.tool()
def lab_status() -> str:
    """Report GPU, host memory, active runs, backend availability, and known evidence.

    Start here. It answers whether anything is holding the GPU, whether there is
    enough free host memory to pin another run's weights, and which backends and
    captured help files are present.
    """
    mem = _meminfo()
    gpu = _gpu_state()
    runs = []
    for sess in _sessions():
        rid = sess["run_id"]
        pid = _read_pid(rid)
        runs.append({
            "run_id": rid, "pid": pid,
            "alive": pid is not None,
            "dir": str(_run_dir(rid)),
            "ready": _scan_log(rid, READY_MARKERS)["found"] if _run_dir(rid).exists() else False,
        })
    llama = shutil.which("llama-server") or (
        "/opt/llama-cpp/bin/llama-server"
        if Path("/opt/llama-cpp/bin/llama-server").exists() else None)
    return json.dumps({
        "lab_home": str(LAB),
        "gpu": gpu,
        "host_mem": {
            "total_gib": round(mem.get("MemTotal", 0) / 1048576, 2),
            "available_gib": round(mem.get("MemAvailable", 0) / 1048576, 2),
            "mlocked_gib": round(mem.get("Mlocked", 0) / 1048576, 3),
            "swap_used_gib": round(
                (mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)) / 1048576, 2),
        },
        "systemd_oomd": subprocess.run(
            ["systemctl", "is-active", "systemd-oomd"],
            capture_output=True, text=True).stdout.strip(),
        "backends": {
            "vllm": (VENV_BIN / "vllm").exists(),
            "llama_server": llama,
        },
        "captured_help": {
            p.name: p.stat().st_size for p in sorted(EVIDENCE.glob("*help*.txt"))
        },
        "profiles": sorted(p.stem for p in PROFILES.glob("*.toml")),
        "active_runs": runs,
        "h2d_gib_s": H2D_GIB_S,
    }, indent=2)


@mcp.tool()
def lab_refresh_help() -> str:
    """Re-capture backend help text so profile validation matches the installed builds.

    Run this after upgrading vLLM or llama.cpp. Validation is only as accurate
    as these captures, and a stale capture silently permits a flag the new build
    has dropped.
    """
    out = {}
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    vllm_bin = VENV_BIN / "vllm"
    if vllm_bin.exists():
        # vLLM paginates help by config group; only --help=all lists every flag.
        res = subprocess.run([str(vllm_bin), "serve", "--help=all"],
                             capture_output=True, text=True, timeout=180)
        target = EVIDENCE / "03-vllm-serve-help.txt"
        target.write_text(res.stdout + res.stderr)
        out["vllm"] = {"path": str(target), "bytes": target.stat().st_size,
                       "flags": len(set(re.findall(r"(?<![\w-])(--[a-z0-9][a-z0-9-]*)",
                                                   target.read_text())))}
    llama = shutil.which("llama-server") or "/opt/llama-cpp/bin/llama-server"
    if Path(llama).exists():
        res = subprocess.run([llama, "--help"], capture_output=True, text=True, timeout=120)
        target = EVIDENCE / "05-llama-server-help.txt"
        target.write_text(res.stdout + res.stderr)
        out["llamacpp"] = {"path": str(target), "bytes": target.stat().st_size,
                           "flags": len(set(re.findall(r"(?<![\w-])(--[a-z0-9][a-z0-9-]*)",
                                                       target.read_text())))}
    return json.dumps(out, indent=2)


@mcp.tool()
def pcie_probe(buffer_mib: int = 1024, iters: int = 20) -> str:
    """Measure sustained pinned host-to-device bandwidth, the streaming ceiling.

    Every streamed-weight decode rate is bounded by
    bytes_per_traversal / this number, so it is the reference against which
    bench results are judged. Builds bench/h2d.cu with nvcc on first use.
    Re-measure after any BIOS, driver, or slot change.
    """
    src = LAB / "bench" / "h2d.cu"
    binary = LAB / "bench" / "h2d"
    if not src.exists():
        return json.dumps({"error": f"missing {src}"})
    if not binary.exists() or binary.stat().st_mtime < src.stat().st_mtime:
        build = subprocess.run(["nvcc", "-O2", "-o", str(binary), str(src)],
                               capture_output=True, text=True, timeout=600)
        if build.returncode != 0:
            return json.dumps({"error": "nvcc build failed", "stderr": build.stderr[-2000:]})
    res = subprocess.run([str(binary), str(buffer_mib), str(iters)],
                         capture_output=True, text=True, timeout=600)
    return json.dumps({
        "stdout": res.stdout.strip(),
        "link_after": _gpu_state(),
        "interpretation": (
            "Divide bytes streamed per model traversal by the pinned H2D figure "
            "to get the decode ceiling. Pinned is roughly twice pageable here, so "
            "a backend that fails to pin loses more than half of it."
        ),
    }, indent=2)


# --------------------------------------------------------------------------
# tools: profiles
# --------------------------------------------------------------------------

@mcp.tool()
def profile_list() -> str:
    """List profiles with their backend, model, port, and declared budgets."""
    rows = []
    for path in sorted(PROFILES.glob("*.toml")):
        try:
            p = _load_profile(path.stem)
            rows.append({
                "name": p.name, "backend": p.backend, "model": p.model,
                "port": p.port, "description": p.description,
                "pin_budget_gib": p.pin_budget_gib,
                "vram_budget_gib": p.vram_budget_gib,
                "streamed_gib_per_traversal": p.streamed_gib_per_traversal,
            })
        except Exception as exc:
            rows.append({"name": path.stem, "error": str(exc)})
    return json.dumps(rows, indent=2)


@mcp.tool()
def profile_show(name: str) -> str:
    """Show a profile's TOML and the exact argv it renders to."""
    p = _load_profile(name)
    argv = _argv(p)
    return json.dumps({
        "name": p.name, "path": str(p.path),
        "toml": p.path.read_text(),
        "argv": argv,
        "command_line": " ".join(shlex.quote(a) for a in argv),
        "env": p.env,
    }, indent=2)


@mcp.tool()
def profile_validate(name: str) -> str:
    """Check every flag in a profile against the installed binary's help text.

    This is the gate that keeps a profile from being written against
    documentation rather than against the build actually present. Unknown flags
    come back with close matches from the real vocabulary.
    """
    p = _load_profile(name)
    known, err = _known_flags(p.backend)
    problems, unknown = [], []
    if err:
        problems.append(err)
    else:
        for key in p.args:
            flag = f"--{key.replace('_', '-')}" if not key.startswith("-") else key
            if flag not in known:
                unknown.append({"flag": flag,
                                "did_you_mean": get_close_matches(flag, known, n=4, cutoff=0.6)})

    mem = _meminfo()
    avail = mem.get("MemAvailable", 0) / 1048576
    if p.pin_budget_gib and p.pin_budget_gib > avail:
        problems.append(
            f"pin_budget_gib {p.pin_budget_gib} exceeds MemAvailable {avail:.1f} GiB; "
            "pinned pages cannot be swapped or compressed"
        )
    gpu = _gpu_state()
    if p.vram_budget_gib and "vram_free_mib" in gpu:
        if p.vram_budget_gib * 1024 > gpu["vram_free_mib"]:
            problems.append(
                f"vram_budget_gib {p.vram_budget_gib} exceeds free VRAM "
                f"{gpu['vram_free_mib'] / 1024:.1f} GiB"
            )
    if p.backend == "vllm" and p.args.get("offload-backend") == "prefetch":
        if not p.args.get("offload-group-size"):
            problems.append(
                "offload-backend=prefetch with offload-group-size unset or 0 offloads "
                "nothing; the prefetch path keys off group size"
            )
    if p.backend == "vllm" and p.args.get("offload-backend") == "uva":
        if not p.args.get("cpu-offload-gb"):
            problems.append(
                "offload-backend=uva with cpu-offload-gb unset offloads nothing"
            )
    gs, nig = p.args.get("offload-group-size"), p.args.get("offload-num-in-group")
    if gs and nig and int(nig) > int(gs):
        problems.append(f"offload-num-in-group {nig} exceeds offload-group-size {gs}")

    return json.dumps({
        "profile": p.name,
        "valid": not unknown and not problems,
        "unknown_flags": unknown,
        "problems": problems,
        "offload_fraction": (round(int(nig) / int(gs), 3) if gs and nig else None),
        "checked_against": str(EVIDENCE / ("03-vllm-serve-help.txt" if p.backend == "vllm"
                                           else "05-llama-server-help.txt")),
    }, indent=2)


# --------------------------------------------------------------------------
# tools: runs
# --------------------------------------------------------------------------

@mcp.tool()
def lab_preflight(profile: str) -> str:
    """Decide whether this host can start the profile without taking the desktop down.

    Offloaded weights live in pinned pages, which systemd-oomd cannot reclaim
    and swap cannot absorb. On a 31 GiB host running a desktop, a profile that
    pins past the available floor does not degrade -- it kills whatever oomd
    reaches first. This returns a go or no-go with the arithmetic shown.
    """
    p = _load_profile(profile)
    mem = _meminfo()
    gpu = _gpu_state()
    avail_gib = mem.get("MemAvailable", 0) / 1048576
    free_vram_gib = gpu.get("vram_free_mib", 0) / 1024

    headroom_gib = 3.0          # loader, tokenizer, CUDA context, desktop drift
    need_host = p.pin_budget_gib + headroom_gib
    blockers, warnings = [], []

    if p.pin_budget_gib and need_host > avail_gib:
        blockers.append(
            f"host memory: needs {need_host:.1f} GiB "
            f"({p.pin_budget_gib:.1f} pinned + {headroom_gib:.1f} headroom) "
            f"but only {avail_gib:.1f} GiB is available"
        )
    if p.vram_budget_gib and p.vram_budget_gib > free_vram_gib:
        blockers.append(
            f"VRAM: needs {p.vram_budget_gib:.1f} GiB but only {free_vram_gib:.1f} GiB is free"
        )
    busy = [s["run_id"] for s in _sessions() if _read_pid(s["run_id"])]
    if busy:
        blockers.append(f"runs already holding the GPU: {busy}; stop them first")

    oomd = subprocess.run(["systemctl", "is-active", "systemd-oomd"],
                          capture_output=True, text=True).stdout.strip()
    if oomd == "active" and p.pin_budget_gib >= 8:
        warnings.append(
            "systemd-oomd is active and this profile pins a large region; oomd has "
            "previously killed terminal scopes on this host under memory pressure. "
            "Close large browser sessions before launching."
        )
    try:
        limit = subprocess.run(["bash", "-lc", "ulimit -l"],
                               capture_output=True, text=True).stdout.strip()
        if limit not in ("unlimited",) and limit.isdigit() and int(limit) < 1048576:
            warnings.append(
                f"RLIMIT_MEMLOCK is {limit} kiB. The NVIDIA driver pins through its own "
                "path and normally ignores this, but a backend that pins through mlock "
                "would fail here."
            )
    except Exception:
        pass

    if p.streamed_gib_per_traversal:
        ceiling = H2D_GIB_S / p.streamed_gib_per_traversal
        warnings.append(
            f"expected transfer ceiling {ceiling:.2f} traversals/s "
            f"({p.streamed_gib_per_traversal:.1f} GiB per traversal at {H2D_GIB_S} GiB/s)"
        )

    return json.dumps({
        "profile": p.name,
        "go": not blockers,
        "blockers": blockers,
        "warnings": warnings,
        "host_available_gib": round(avail_gib, 2),
        "free_vram_gib": round(free_vram_gib, 2),
        "systemd_oomd": oomd,
    }, indent=2)


@mcp.tool()
def run_launch(profile: str, overrides: dict | None = None,
               force: bool = False, tag: str = "") -> str:
    """Start a profile in a detached tmux session with telemetry and provenance.

    Refuses to start when preflight finds a blocker unless force is set. Writes
    runs/<run_id>/ containing launch.sh (the exact script executed), provenance
    JSON, server.log, and telemetry.tsv. overrides patches the profile's args
    for this run only, which is how a single-variable tuning step is taken
    without editing the profile.
    """
    p = _load_profile(profile)
    if overrides:
        p.args = {**p.args, **overrides}

    gate = json.loads(lab_preflight(profile))
    if gate["blockers"] and not force:
        return json.dumps({"launched": False, "reason": "preflight blocked",
                           "preflight": gate}, indent=2)

    run_id = f"{p.name}{('-' + tag) if tag else ''}-{time.strftime('%m%d-%H%M%S')}"
    rdir = _run_dir(run_id)
    rdir.mkdir(parents=True, exist_ok=True)
    argv = _argv(p)

    env_lines = "\n".join(f"export {k}={shlex.quote(v)}" for k, v in p.env.items())
    launch = f"""#!/usr/bin/env bash
# Generated for run {run_id}. This file is the provenance of what actually ran.
set -uo pipefail
cd {shlex.quote(str(LAB))}
{env_lines}
export QWEN_LAB_RUN_ID={shlex.quote(run_id)}
{shlex.quote(str(SCRIPTS / 'qwen-lab-telemetry'))} \\
  --out {shlex.quote(str(rdir / 'telemetry.tsv'))} \\
  --pidfile {shlex.quote(str(rdir / 'server.pid'))} --interval 1 &
TELEM=$!
{' '.join(shlex.quote(a) for a in argv)} >> {shlex.quote(str(rdir / 'server.log'))} 2>&1 &
SERVER=$!
echo $SERVER > {shlex.quote(str(rdir / 'server.pid'))}
wait $SERVER; RC=$?
kill $TELEM 2>/dev/null
echo "SERVER_EXIT=$RC" >> {shlex.quote(str(rdir / 'server.log'))}
sleep 86400
"""
    launch_path = rdir / "launch.sh"
    launch_path.write_text(launch)
    launch_path.chmod(0o755)

    (rdir / "provenance.json").write_text(json.dumps({
        "run_id": run_id,
        "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "profile": p.name,
        "profile_toml": p.path.read_text(),
        "overrides": overrides or {},
        "argv": argv,
        "env": p.env,
        "backend": p.backend,
        "model": p.model,
        "port": p.port,
        "host_at_launch": {
            "mem_available_gib": round(_meminfo().get("MemAvailable", 0) / 1048576, 2),
            "gpu": _gpu_state(),
        },
        "preflight": gate,
        "h2d_gib_s": H2D_GIB_S,
    }, indent=2))

    session = f"{TMUX_PREFIX}{run_id}"
    res = _tmux("new-session", "-d", "-s", session, "-c", str(LAB),
                f"bash {shlex.quote(str(launch_path))}")
    if res.returncode != 0:
        return json.dumps({"launched": False, "error": res.stderr.strip()}, indent=2)

    return json.dumps({
        "launched": True,
        "run_id": run_id,
        "session": session,
        "dir": str(rdir),
        "port": p.port,
        "command_line": " ".join(shlex.quote(a) for a in argv),
        "next": ("Poll run_wait_ready, then run_probe. Do not treat a ready server "
                 "as proof that offloading occurred."),
        "attach": f"tmux attach -t {session}",
    }, indent=2)


def _scan_log(run_id, markers, tail=4000):
    log = _run_dir(run_id) / "server.log"
    if not log.exists():
        return {"found": False, "line": None, "exists": False}
    try:
        lines = log.read_text(errors="replace").splitlines()[-tail:]
    except OSError:
        return {"found": False, "line": None, "exists": True}
    for line in reversed(lines):
        for m in markers:
            if m in line:
                return {"found": True, "line": line.strip(), "marker": m, "exists": True}
    return {"found": False, "line": None, "exists": True}


@mcp.tool()
def run_wait_ready(run_id: str, timeout_s: int = 900) -> str:
    """Block until the run serves, fails, or the timeout expires.

    Watches for failure markers as well as readiness, so an out-of-memory abort
    during weight loading returns promptly instead of consuming the full
    timeout. Weight loading with host offload is slow by design; a large
    checkpoint streaming from cold page cache legitimately takes minutes.
    """
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        # Readiness is checked first: a server that is already serving is ready
        # regardless of what it printed on the way up.
        ok = _scan_log(run_id, READY_MARKERS)
        if ok["found"]:
            return json.dumps({"ready": True, "line": ok["line"],
                               "elapsed_s": round(timeout_s - (deadline - time.time()), 1),
                               "next": "run_probe to confirm offloading actually happened"},
                              indent=2)
        fatal = _scan_log(run_id, FATAL_MARKERS)
        if fatal["found"]:
            return json.dumps({"ready": False, "failed": True,
                               "marker": fatal["marker"], "line": fatal["line"],
                               "hint": "run_logs with a pattern for full context"}, indent=2)
        exited = _read_pid(run_id) is None and (_run_dir(run_id) / "server.pid").exists()
        if exited:
            soft = _scan_log(run_id, SOFT_MARKERS)
            return json.dumps({
                "ready": False, "failed": True,
                "reason": "server process exited",
                "last_error": soft["line"],
                "hint": "run_logs with a pattern for full context",
            }, indent=2)
        time.sleep(3)
    return json.dumps({"ready": False, "timed_out": True, "timeout_s": timeout_s}, indent=2)


@mcp.tool()
def run_probe(run_id: str) -> str:
    """Prove whether weight offloading actually happened, rather than assuming it.

    A configuration that the model runner ignores yields a server that starts
    cleanly, answers requests, and holds every weight in VRAM. The only
    trustworthy evidence is vLLM's own offloader lines together with resident
    VRAM. Returns CONFIRMED only when both agree; ABSENT when the run declared
    offloading and no offloader was installed.
    """
    rdir = _run_dir(run_id)
    if not rdir.exists():
        return json.dumps({"error": f"no run {run_id}"}, indent=2)
    prov = json.loads((rdir / "provenance.json").read_text())
    log = (rdir / "server.log")
    text = log.read_text(errors="replace") if log.exists() else ""

    if prov["backend"] == "llamacpp":
        return _probe_llamacpp(run_id, prov, text)

    findings = {}
    for key, pattern in OFFLOAD_SIGNATURES.items():
        m = pattern.search(text)
        findings[key] = m.group(0).strip() if m else None

    declared = (
        prov["backend"] == "vllm" and (
            prov["argv"].count("--offload-backend") > 0
            or any(a.startswith("--offload-group-size") for a in prov["argv"])
            or any(a.startswith("--cpu-offload-gb") for a in prov["argv"])
        )
    )
    cls = None
    m = OFFLOAD_SIGNATURES["offloader_class"].search(text)
    if m:
        cls = m.group(1)

    gpu = _gpu_state()
    saved_gb = None
    pm = OFFLOAD_SIGNATURES["prefetch_summary"].search(text)
    if pm:
        saved_gb = float(pm.group(2))

    if not declared:
        verdict = "NOT_DECLARED"
        reason = "this profile does not request weight offloading"
    elif cls in ("PrefetchOffloader", "UVAOffloader"):
        verdict = "CONFIRMED"
        reason = f"vLLM installed {cls} and reported its offload accounting"
    elif cls == "NoopOffloader" or (cls is None and text):
        verdict = "ABSENT"
        reason = ("offload was requested but no offloader line appears. The model "
                  "runner may have ignored the configuration; check that the run's "
                  "env pins the runner version, and compare resident VRAM against "
                  "the full checkpoint size.")
    else:
        verdict = "UNCONFIRMED"
        reason = "no offloader line yet; the run may still be loading weights"

    return json.dumps({
        "run_id": run_id,
        "verdict": verdict,
        "reason": reason,
        "offloader_class": cls,
        "signatures": findings,
        "gpu_memory_saved_gb": saved_gb,
        "vram_now": gpu,
        "declared_offload": declared,
        "env_at_launch": prov.get("env", {}),
        "argv": prov["argv"],
    }, indent=2)


def _proc_vram_mib(pid):
    """VRAM held by one process, from the driver rather than from log text.

    Log wording changes between builds -- b10549 dropped the layer-placement
    line the first probe parsed -- while this is a direct measurement of where
    the weights actually are.
    """
    if not pid:
        return None
    try:
        raw = subprocess.run(
            ["nvidia-smi", "--query-compute-apps=pid,used_memory",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=8).stdout
    except Exception:
        return None
    for line in raw.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) == 2 and parts[0] == str(pid):
            try:
                return int(parts[1])
            except ValueError:
                return None
    return None


def _probe_llamacpp(run_id, prov, text):
    """Report where llama.cpp put the weights, and whether managed memory engaged.

    GGML_CUDA_ENABLE_UNIFIED_MEMORY is read at allocator setup and is inert if
    the build lacks support, with no message either way. A run meaning to test
    fault-driven migration would then be an ordinary fitted split wearing the
    wrong label. Resident VRAM against checkpoint size is what separates those,
    and the telemetry transmit column corroborates it: migration moves pages in
    both directions, while prefetch and UVA are receive-dominated.
    """
    argv = prov["argv"]
    requested = None
    for flag in ("--n-gpu-layers", "-ngl", "--gpu-layers"):
        if flag in argv:
            raw = argv[argv.index(flag) + 1]
            # b10549 accepts an exact count, "auto", or "all"; "all" reaches the
            # loader as the sentinel -2, so a bare int() rejects a valid profile.
            requested = int(raw) if re.fullmatch(r"-?\d+", raw) else raw
            break

    pid = _read_pid(run_id)
    proc_vram_mib = _proc_vram_mib(pid)
    try:
        ckpt_mib = pathlib.Path(prov["model"]).stat().st_size / 1048576
    except OSError:
        ckpt_mib = None
    resident_fraction = (round(proc_vram_mib / ckpt_mib, 3)
                         if proc_vram_mib and ckpt_mib else None)

    managed = prov.get("env", {}).get("GGML_CUDA_ENABLE_UNIFIED_MEMORY") == "1"
    # Kept for builds that still print it; absence is not evidence either way.
    m = re.search(r"offloaded\s+(\d+)\s*/\s*(\d+)\s+layers to GPU", text)
    placed, total = (int(m.group(1)), int(m.group(2))) if m else (None, None)

    if proc_vram_mib is None:
        verdict = "UNCONFIRMED"
        reason = ("the server holds no GPU allocation yet; it may still be loading, "
                  "or it may be running entirely on the CPU")
    elif managed and resident_fraction and resident_fraction > 1.05:
        verdict = "CONFIRMED"
        reason = (f"the process holds {proc_vram_mib:.0f} MiB against a "
                  f"{ckpt_mib:.0f} MiB checkpoint, so the allocator is "
                  "oversubscribing and residency is left to fault-driven migration. "
                  "Confirm against the telemetry transmit column: bidirectional "
                  "traffic is migration, receive-only traffic is not.")
    elif managed:
        verdict = "ABSENT"
        reason = (f"unified memory was requested but the process holds only "
                  f"{proc_vram_mib:.0f} MiB against a {ckpt_mib:.0f} MiB checkpoint, "
                  "so the allocator fitted the model conventionally instead of "
                  "oversubscribing. This build may not honour the variable.")
    elif resident_fraction and resident_fraction >= 0.95:
        verdict = "NOT_DECLARED"
        reason = (f"fully resident: {proc_vram_mib:.0f} MiB of VRAM against a "
                  f"{ckpt_mib:.0f} MiB checkpoint. No weights cross PCIe during "
                  "decode, so the transfer ceiling does not apply to this arm.")
    else:
        spilled = (1 - resident_fraction) * 100 if resident_fraction else None
        verdict = "NOT_DECLARED"
        reason = (f"conventional split: {proc_vram_mib:.0f} MiB resident of a "
                  f"{ckpt_mib:.0f} MiB checkpoint"
                  + (f", roughly {spilled:.0f} percent computed on the CPU. Those "
                     "weights never cross PCIe." if spilled else "."))

    return json.dumps({
        "run_id": run_id,
        "verdict": verdict,
        "reason": reason,
        "process_vram_mib": proc_vram_mib,
        "checkpoint_mib": round(ckpt_mib) if ckpt_mib else None,
        "resident_fraction": resident_fraction,
        "layers_on_gpu": placed,
        "layers_total": total,
        "layers_requested": requested,
        "unified_memory_requested": managed,
        "vram_now": _gpu_state(),
        "env_at_launch": prov.get("env", {}),
        "argv": argv,
    }, indent=2)


@mcp.tool()
def run_logs(run_id: str, lines: int = 60, pattern: str = "") -> str:
    """Read a run's server log, optionally filtered by a regular expression."""
    log = _run_dir(run_id) / "server.log"
    if not log.exists():
        return json.dumps({"error": f"no log for {run_id}"}, indent=2)
    text = log.read_text(errors="replace").splitlines()
    if pattern:
        rx = re.compile(pattern, re.IGNORECASE)
        text = [ln for ln in text if rx.search(ln)]
    return json.dumps({
        "run_id": run_id, "matched": len(text),
        "tail": text[-lines:],
    }, indent=2)


@mcp.tool()
def run_list() -> str:
    """List every run directory with its state, whether alive or finished."""
    RUNS.mkdir(parents=True, exist_ok=True)
    live = {s["run_id"] for s in _sessions()}
    rows = []
    for rdir in sorted(RUNS.iterdir(), key=lambda p: p.name, reverse=True):
        if not rdir.is_dir():
            continue
        rid = rdir.name
        prov = {}
        try:
            prov = json.loads((rdir / "provenance.json").read_text())
        except (OSError, json.JSONDecodeError):
            pass
        rows.append({
            "run_id": rid,
            "profile": prov.get("profile"),
            "backend": prov.get("backend"),
            "port": prov.get("port"),
            "session_alive": rid in live,
            "process_alive": _read_pid(rid) is not None,
            "ready": _scan_log(rid, READY_MARKERS)["found"],
            "failed": _scan_log(rid, FATAL_MARKERS)["found"],
            "started": prov.get("started"),
        })
    return json.dumps(rows, indent=2)


@mcp.tool()
def run_stop(run_id: str = "", all_runs: bool = False) -> str:
    """Stop one run or every run, releasing VRAM and pinned host pages.

    Pinned memory is only returned when the process exits, so a stale run
    starves the next launch's preflight even while it is idle.
    """
    targets = [s["run_id"] for s in _sessions()] if all_runs else [run_id]
    stopped = []
    for rid in [t for t in targets if t]:
        pid = _read_pid(rid)
        if pid:
            subprocess.run(["kill", "-TERM", str(pid)], capture_output=True)
            for _ in range(20):
                if not Path(f"/proc/{pid}").exists():
                    break
                time.sleep(0.5)
            if Path(f"/proc/{pid}").exists():
                subprocess.run(["kill", "-KILL", str(pid)], capture_output=True)
        _tmux("kill-session", "-t", f"{TMUX_PREFIX}{rid}")
        stopped.append(rid)
    time.sleep(1.5)
    return json.dumps({"stopped": stopped, "gpu": _gpu_state(),
                       "host_available_gib": round(
                           _meminfo().get("MemAvailable", 0) / 1048576, 2)}, indent=2)


# --------------------------------------------------------------------------
# tools: measurement
# --------------------------------------------------------------------------

@mcp.tool()
def run_bench(run_id: str, prompt: str = "short", max_tokens: int = 128,
              reps: int = 3, served_model: str = "") -> str:
    """Measure TTFT, decode rate, and the ITL distribution against the PCIe ceiling.

    Reports P95 inter-token latency beside P50 because a prefetch window too
    short to cover a transfer shows up as a tail rather than as a shifted mean.
    When the profile declares bytes streamed per traversal, the result includes
    what fraction of the transfer ceiling the run reached, which is what decides
    whether tuning offload settings can help at all.
    """
    rdir = _run_dir(run_id)
    if not rdir.exists():
        return json.dumps({"error": f"no run {run_id}"}, indent=2)
    prov = json.loads((rdir / "provenance.json").read_text())
    port = prov["port"]
    model = served_model or _served_name(prov)
    profile = _load_profile(prov["profile"])

    cmd = [str(SCRIPTS / "qwen-lab-bench"),
           "--base-url", f"http://127.0.0.1:{port}",
           "--model", model, "--prompt", prompt,
           "--max-tokens", str(max_tokens), "--reps", str(reps),
           "--label", run_id,
           "--json-out", str(rdir / f"bench-{prompt}-{max_tokens}.json")]
    if profile.streamed_gib_per_traversal:
        cmd += ["--streamed-gib", str(profile.streamed_gib_per_traversal),
                "--h2d-gib-s", str(H2D_GIB_S)]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    if res.returncode != 0:
        return json.dumps({"error": "bench failed", "stderr": res.stderr[-2000:],
                           "hint": f"confirm the served model name; tried {model!r}"}, indent=2)
    return res.stdout


def _served_name(prov):
    """The name the endpoint answers to, which differs by backend.

    vLLM names the model with --served-model-name; llama-server uses --alias.
    Falling through to the checkpoint path would send a filesystem path in the
    request's model field, which llama-server tolerates but vLLM rejects.
    """
    argv = prov["argv"]
    for flag in ("--served-model-name", "--alias", "--model-alias"):
        if flag in argv:
            return argv[argv.index(flag) + 1]
    return prov["model"]


@mcp.tool()
def telemetry_summary(run_id: str) -> str:
    """Summarise a run's telemetry, reading the PCIe column as a mechanism signature.

    Each mechanism leaves a different mark once decode is under way. Near-zero
    receive traffic means the weights are resident and never cross the bus.
    Tall bursts over a low median mean bulk asynchronous prefetch overlapping
    compute. A sustained high median means a continuous host-read path such as
    UVA, or prefetch failing to overlap. Traffic in both directions means
    fault-driven page migration, since prefetch and UVA are receive-dominated.

    The signature is read only after resident VRAM plateaus. Weight loading
    moves the entire checkpoint across the bus once, at rates far above
    anything decode produces, so including it makes every run -- a fully
    resident one included -- look like bulk streaming.
    """
    tsv = _run_dir(run_id) / "telemetry.tsv"
    if not tsv.exists():
        return json.dumps({"error": f"no telemetry for {run_id}"}, indent=2)
    rows = [ln.split("\t") for ln in tsv.read_text().splitlines() if ln.strip()]
    if len(rows) < 2:
        return json.dumps({"error": "telemetry has no samples yet"}, indent=2)
    header, data = rows[0], rows[1:]
    idx = {name: i for i, name in enumerate(header)}

    def cell(row, name):
        try:
            return float(row[idx[name]])
        except (ValueError, IndexError, KeyError):
            return None

    peak = max((cell(r, "vram_used_mib") or 0.0 for r in data), default=0.0)
    steady_from = 0
    if peak > 0:
        for i, row in enumerate(data):
            if (cell(row, "vram_used_mib") or 0.0) >= 0.97 * peak:
                steady_from = i
                break
    steady = data[steady_from:] or data

    def stat(name):
        vals = [v for v in (cell(r, name) for r in steady) if v is not None]
        if not vals:
            return None
        ordered = sorted(vals)
        return {
            "min": ordered[0], "max": ordered[-1],
            "p50": ordered[len(ordered) // 2],
            "p95": ordered[min(len(ordered) - 1, int(0.95 * (len(ordered) - 1)))],
            "mean": round(sum(vals) / len(vals), 2),
        }

    rx = stat("rx_pci_mib_s") or {}
    tx = stat("tx_pci_mib_s") or {}
    signature = "insufficient data"
    if rx:
        rx_p50, rx_p95 = rx["p50"], rx["p95"]
        tx_p50 = tx.get("p50", 0)
        if rx_p50 < 50 and tx_p50 < 50:
            signature = ("weights are resident: receive traffic is near zero at the "
                         "median, so decode never crosses the bus and the transfer "
                         "ceiling does not apply")
        elif tx_p50 > 0.5 * max(rx_p50, 1):
            signature = ("traffic in both directions: consistent with fault-driven "
                         "page migration rather than one-way weight delivery")
        elif rx_p50 / 1024.0 >= 0.75 * H2D_GIB_S:
            signature = (f"the bus is saturated: median receive traffic is "
                         f"{rx_p50 / 1024.0:.1f} GiB/s against a measured ceiling of "
                         f"{H2D_GIB_S} GiB/s. Weight delivery, not compute, sets the "
                         "decode rate, and only streaming fewer bytes per traversal "
                         "will move it")
        elif rx_p95 > 4 * max(rx_p50, 1):
            signature = ("bursty receive traffic: consistent with bulk asynchronous "
                         "prefetch overlapping compute")
        else:
            signature = ("sustained receive traffic: consistent with a continuous "
                         "host-read path such as UVA, or with prefetch that is not "
                         "overlapping")

    return json.dumps({
        "run_id": run_id,
        "samples_total": len(data),
        "samples_steady_state": len(steady),
        "load_phase_samples": steady_from,
        "gpu_util_pct": stat("gpu_util_pct"),
        "vram_used_mib": stat("vram_used_mib"),
        "rx_pci_mib_s": rx,
        "tx_pci_mib_s": tx,
        "proc_rss_kib": stat("proc_rss_kib"),
        "proc_vmlck_kib": stat("proc_vmlck_kib"),
        "proc_swap_kib": stat("proc_swap_kib"),
        "host_avail_kib": stat("host_avail_kib"),
        "pcie_signature": signature,
        "signature_window": "after resident VRAM plateaued; the load phase is excluded",
        "peak_rx_gib_s": round(rx.get("max", 0) / 1024, 2) if rx else None,
        "h2d_ceiling_gib_s": H2D_GIB_S,
    }, indent=2)


@mcp.tool()
def tuning_advice(run_id: str) -> str:
    """Recommend the next single-variable change, given what this run actually did.

    Tuning more than one variable per step makes the result unattributable.
    This reads the run's failure mode, resident VRAM, and telemetry, and names
    one change with the reason it is the one that moves the binding constraint.
    """
    rdir = _run_dir(run_id)
    if not rdir.exists():
        return json.dumps({"error": f"no run {run_id}"}, indent=2)
    prov = json.loads((rdir / "provenance.json").read_text())
    profile = _load_profile(prov["profile"])
    probe = json.loads(run_probe(run_id))
    failed = _scan_log(run_id, FATAL_MARKERS)
    argv = prov["argv"]

    def arg(flag, cast=int):
        return cast(argv[argv.index(flag) + 1]) if flag in argv else None

    gs = arg("--offload-group-size")
    nig = arg("--offload-num-in-group")
    step = arg("--offload-prefetch-step")
    steps = []

    # The marker line names the symptom, not the cause: vLLM reports
    # "Engine core initialization failed" while the memory shortfall is stated
    # several lines earlier. Matching on the marker alone misses every
    # memory-bound failure, so the whole log is scanned for the shortfall.
    log_text = (rdir / "server.log").read_text(errors="replace") if (rdir / "server.log").exists() else ""
    kv_short = re.search(
        r"([\d.]+) GiB KV cache is needed, which is larger than the available "
        r"KV cache memory \(([\d.]+) GiB\)", log_text)
    memory_bound = bool(kv_short) or any(
        t in log_text for t in ("CUDA out of memory", "torch.OutOfMemoryError",
                                "No available memory for the cache blocks"))

    if failed["found"] and memory_bound:
        if kv_short:
            steps.append({
                "change": (f"KV cache came up short: {kv_short.group(1)} GiB needed, "
                           f"{kv_short.group(2)} GiB available"),
                "why": ("the weights and the staging pool left too little VRAM for the "
                        "cache. Moving more weights to host memory frees more than "
                        "trimming the cache request does."),
            })
        if gs and nig:
            steps.append({
                "change": f"offload-group-size {gs} -> 4, offload-num-in-group {nig} -> 3",
                "why": ("moves more weights out of VRAM, from "
                        f"{nig}/{gs} of layers to 3/4. This shifts the binding "
                        "constraint directly, unlike context or utilisation changes "
                        "which only trim allocations around it."),
            })
        steps.append({
            "change": "max-model-len -> 2048",
            "why": "shrinks KV cache reservation, a smaller effect than moving weights",
        })
        steps.append({
            "change": "gpu-memory-utilization -> 0.80",
            "why": "leaves more room for allocations vLLM does not account for",
        })
    elif probe["verdict"] == "ABSENT":
        steps.append({
            "change": "confirm the model runner honours the offload configuration",
            "why": ("the run declared offloading and no offloader was installed, so "
                    "every weight is resident and the measurement describes a "
                    "different configuration than the profile names"),
        })
    else:
        tele = json.loads(telemetry_summary(run_id)) if (rdir / "telemetry.tsv").exists() else {}
        vram = (tele.get("vram_used_mib") or {}).get("p95", 0)
        free_gib = (12282 - vram) / 1024 if vram else 0
        if free_gib > 1.5 and gs and nig:
            steps.append({
                "change": f"offload-group-size {gs} -> 2, offload-num-in-group {nig} -> 1",
                "why": (f"about {free_gib:.1f} GiB of VRAM stayed unused, so fewer "
                        "layers need to stream and each traversal moves less over PCIe"),
            })
        if free_gib > 1.0 and step == 1:
            steps.append({
                "change": "offload-prefetch-step 1 -> 2",
                "why": ("a deeper prefetch window hides more transfer latency at the "
                        "cost of another layer's staging buffer; take this only after "
                        "the offload fraction is settled"),
            })
        if "--enforce-eager" in argv:
            steps.append({
                "change": "drop --enforce-eager",
                "why": ("graph capture removes launch overhead but costs capture-time "
                        "memory; on a 12 GiB card that trade has to be measured, not assumed"),
            })
    if profile.streamed_gib_per_traversal:
        ceiling = H2D_GIB_S / profile.streamed_gib_per_traversal
        steps.append({
            "change": "compare against a fully resident low-bit quant",
            "why": (f"this configuration cannot exceed {ceiling:.2f} traversals/s at "
                    f"{H2D_GIB_S} GiB/s. A quant that fits entirely in VRAM removes the "
                    "per-token bus path and is not subject to that bound at all."),
        })

    return json.dumps({
        "run_id": run_id,
        "current": {"group_size": gs, "num_in_group": nig, "prefetch_step": step,
                    "offload_fraction": round(nig / gs, 3) if gs and nig else None},
        "probe_verdict": probe["verdict"],
        "failed": failed["found"],
        "recommended_order": steps,
        "rule": "apply one change per run so the result stays attributable",
    }, indent=2)


if __name__ == "__main__":
    for d in (PROFILES, RUNS, EVIDENCE):
        d.mkdir(parents=True, exist_ok=True)
    mcp.run()
