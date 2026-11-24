"""Safe argv execution helpers for source-analysis tools."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from shutil import which
from typing import Any

from pydantic import BaseModel, Field, field_validator

from .catalog import ToolSpec, lookup_tool

MAX_DEFAULT_OUTPUT_BYTES = 64 * 1024
MAX_DEFAULT_TIMEOUT_S = 60
HAZARD_ACK = (
    "I understand this source-analysis tool may mutate files, run code, trace "
    "processes, or use sudo."
)


class ToolRequest(BaseModel):
    tool: str
    repo_root: str | None = None
    paths: list[str] = Field(default_factory=list)
    query_or_rule: str | None = None
    extra_args: list[str] = Field(default_factory=list)
    artifact_dir: str | None = None
    timeout_s: int = Field(default=MAX_DEFAULT_TIMEOUT_S, ge=1, le=86_400)
    max_output_bytes: int = Field(default=MAX_DEFAULT_OUTPUT_BYTES, ge=1024, le=4 * 1024 * 1024)
    mode: str = Field(default="dry_run", pattern="^(dry_run|approved)$")
    allow_sudo: bool = False
    hazard_ack: str | None = None

    @field_validator("paths", "extra_args")
    @classmethod
    def reject_empty_tokens(cls, value: list[str]) -> list[str]:
        for token in value:
            if not token:
                msg = "empty argv tokens are not allowed"
                raise ValueError(msg)
            if "\x00" in token:
                msg = "NUL bytes are not allowed in argv tokens"
                raise ValueError(msg)
        return value


@dataclass(frozen=True)
class ExecutionPlan:
    spec: ToolSpec
    cwd: Path
    argv: tuple[str, ...]
    dry_run: bool
    requires_approval: bool
    requires_sudo: bool


def create_plan(request: ToolRequest) -> ExecutionPlan:
    spec = lookup_tool(request.tool)
    executable = spec.resolved_executable()
    if executable is None:
        executable = spec.executable

    cwd = _resolve_cwd(request.repo_root)
    _validate_paths(cwd, request.paths)

    argv = [executable]
    if request.allow_sudo:
        if not spec.allows_sudo:
            msg = f"{spec.key} is not declared sudo-capable"
            raise ValueError(msg)
        argv = ["sudo", "-n", executable]

    argv.extend(_default_args(spec, request))
    argv.extend(request.extra_args)
    argv.extend(request.paths)

    requires_approval = spec.requires_approval or spec.allows_write or spec.allows_sudo
    if request.mode == "approved" and requires_approval and request.hazard_ack != HAZARD_ACK:
        msg = f"approved mode for {spec.key} requires exact hazard_ack"
        raise ValueError(msg)
    if request.allow_sudo and request.mode != "approved":
        msg = "sudo-capable execution requires mode=approved"
        raise ValueError(msg)

    return ExecutionPlan(
        spec=spec,
        cwd=cwd,
        argv=tuple(argv),
        dry_run=request.mode == "dry_run",
        requires_approval=requires_approval,
        requires_sudo=request.allow_sudo,
    )


def execute_tool(request: ToolRequest) -> dict[str, Any]:
    plan = create_plan(request)
    base = _base_result(plan, request)
    if plan.dry_run:
        base["exit_code"] = None
        base["stdout_excerpt"] = ""
        base["stderr_excerpt"] = "dry_run: command was not executed"
        return base

    started = time.monotonic()
    completed = subprocess.run(
        list(plan.argv),
        cwd=plan.cwd,
        text=False,
        capture_output=True,
        timeout=request.timeout_s,
        check=False,
        env=_clean_env(),
    )
    duration_s = round(time.monotonic() - started, 3)
    base.update(
        {
            "exit_code": completed.returncode,
            "duration_s": duration_s,
            "stdout_excerpt": _decode_clip(completed.stdout, request.max_output_bytes),
            "stderr_excerpt": _decode_clip(completed.stderr, request.max_output_bytes),
        }
    )
    _write_run_manifest(base, request.artifact_dir)
    return base


def version_result(tool: str, timeout_s: int = 15) -> dict[str, Any]:
    spec = lookup_tool(tool)
    executable = spec.resolved_executable()
    if executable is None:
        return {
            "tool": spec.key,
            "resolved_executable": None,
            "available": False,
            "package_hint": spec.package_hint,
        }
    completed = subprocess.run(
        [executable, *spec.version_args],
        text=True,
        capture_output=True,
        timeout=timeout_s,
        check=False,
    )
    return {
        "tool": spec.key,
        "resolved_executable": executable,
        "available": True,
        "exit_code": completed.returncode,
        "stdout_excerpt": completed.stdout[:4096],
        "stderr_excerpt": completed.stderr[:4096],
        "package_hint": spec.package_hint,
    }


def _base_result(plan: ExecutionPlan, request: ToolRequest) -> dict[str, Any]:
    return {
        "tool": plan.spec.key,
        "display": plan.spec.display,
        "aliases": list(plan.spec.aliases),
        "resolved_executable": plan.spec.resolved_executable(),
        "package_hint": plan.spec.package_hint,
        "cwd": str(plan.cwd),
        "argv": list(plan.argv),
        "argv_shell_escaped": shlex.join(plan.argv),
        "mode": request.mode,
        "requires_approval": plan.requires_approval,
        "requires_sudo": plan.requires_sudo,
        "evidence_class": plan.spec.evidence_class,
        "group": plan.spec.group,
        "limits": {
            "timeout_s": request.timeout_s,
            "max_output_bytes": request.max_output_bytes,
        },
        "artifacts": [],
        "next_stronger_probe": _next_probe(plan.spec),
    }


def _resolve_cwd(repo_root: str | None) -> Path:
    path = Path(repo_root).expanduser().resolve() if repo_root else Path.cwd().resolve()
    if not path.exists() or not path.is_dir():
        msg = f"repo_root is not a directory: {path}"
        raise ValueError(msg)
    return path


def _validate_paths(cwd: Path, paths: list[str]) -> None:
    for raw_path in paths:
        raw = Path(raw_path)
        candidate = raw.resolve() if raw.is_absolute() else (cwd / raw).resolve()
        if not _is_relative_to(candidate, cwd):
            msg = f"path escapes repo_root: {raw_path}"
            raise ValueError(msg)


def _is_relative_to(path: Path, base: Path) -> bool:
    try:
        path.relative_to(base)
        return True
    except ValueError:
        return False


def _default_args(spec: ToolSpec, request: ToolRequest) -> list[str]:
    query = request.query_or_rule
    if spec.key == "rg" and query:
        return ["-n", "--", query]
    if spec.key == "git_grep" and query:
        return ["grep", "-n", "--", query]
    if spec.key == "global" and query:
        return ["-x", query]
    if spec.key == "readtags" and query:
        return ["-p", query]
    if spec.key == "ast_grep" and query:
        return ["--pattern", query]
    if spec.key == "weggli" and query:
        return [query]
    if spec.key == "semgrep" and query:
        return ["--config", query]
    if spec.key == "spatch" and query:
        return ["--sp-file", query]
    if spec.key == "cflow" and query:
        return ["--main", query]
    if spec.key == "addr2line" and query:
        return [query]
    if spec.key == "lief" and request.paths:
        return ["-c", "import lief,sys; print(lief.parse(sys.argv[1]))"]
    if query:
        return [query]
    return []


def _decode_clip(data: bytes, limit: int) -> str:
    clipped = data[:limit]
    suffix = b"\n[output clipped]\n" if len(data) > limit else b""
    return (clipped + suffix).decode("utf-8", errors="replace")


def _clean_env() -> dict[str, str]:
    env = os.environ.copy()
    # MCP traffic uses stdout; child tools may inherit noisy debug variables.
    env.setdefault("NO_COLOR", "1")
    return env


def _write_run_manifest(result: dict[str, Any], artifact_dir: str | None) -> None:
    if artifact_dir is None:
        return
    artifact_path = Path(artifact_dir).expanduser().resolve()
    artifact_path.mkdir(parents=True, exist_ok=True)
    manifest = artifact_path / "source-analysis-mcp-run.json"
    manifest.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    result["artifacts"] = [str(manifest)]


def _next_probe(spec: ToolSpec) -> str:
    if spec.group == "search":
        return "Escalate to ctags/global/clangd when text hits do not prove reachability."
    if spec.group == "static":
        return (
            "Escalate to build-backed analyzer or CodeQL when file-local warnings "
            "are inconclusive."
        )
    if spec.group == "binary":
        return "Verify loaded module mappings before symbolizing runtime addresses."
    if spec.group in {"trace", "profile"}:
        return "Record PID, duration, events, permissions, and stop condition before capture."
    if spec.group == "fuzz":
        return "Stabilize harness oracle and seed corpus before long fuzzing runs."
    return "Use the next evidence tier only after this result leaves a concrete unknown."


def executable_available(name: str) -> bool:
    return which(name) is not None
