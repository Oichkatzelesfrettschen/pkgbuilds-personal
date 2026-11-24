"""Register source-analysis-mcp with local Codex and Claude clients."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import tomlkit

SERVER_NAME = "source-analysis"
COMMAND = "/usr/bin/source-analysis-mcp"
ARGS = ["serve"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="source-analysis-mcp-register")
    parser.add_argument("--client", choices=("codex", "claude", "both"), default="both")
    parser.add_argument("--mode", choices=("dry-run", "apply"), default="dry-run")
    parser.add_argument("--codex-config", default=str(Path.home() / ".codex" / "config.toml"))
    args = parser.parse_args(argv)

    changed: list[dict[str, Any]] = []
    if args.client in {"codex", "both"}:
        changed.append(register_codex(Path(args.codex_config).expanduser(), args.mode))
    if args.client in {"claude", "both"}:
        changed.append(register_claude(args.mode))
    print(json.dumps(changed, indent=2, sort_keys=True))
    return 0


def register_codex(config_path: Path, mode: str) -> dict[str, Any]:
    desired = {
        "command": COMMAND,
        "args": ARGS,
        "startup_timeout_sec": 20,
        "tool_timeout_sec": 300,
        "default_tools_approval_mode": "prompt",
        "enabled": True,
    }
    current_text = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    doc = tomlkit.parse(current_text) if current_text else tomlkit.document()
    servers = doc.setdefault("mcp_servers", tomlkit.table())
    current = dict(servers.get(SERVER_NAME, {})) if SERVER_NAME in servers else {}
    result = {
        "client": "codex",
        "config": str(config_path),
        "mode": mode,
        "before": current,
        "after": desired,
        "changed": current != desired,
    }
    if mode == "apply" and current != desired:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        if config_path.exists():
            backup = config_path.with_suffix(config_path.suffix + ".source-analysis-mcp.bak")
            shutil.copy2(config_path, backup)
            result["backup"] = str(backup)
        table = tomlkit.table()
        for key, value in desired.items():
            table[key] = value
        servers[SERVER_NAME] = table
        config_path.write_text(tomlkit.dumps(doc), encoding="utf-8")
    return result


def register_claude(mode: str) -> dict[str, Any]:
    command = [
        "claude",
        "mcp",
        "add",
        SERVER_NAME,
        "--scope",
        "user",
        "--",
        COMMAND,
        *ARGS,
    ]
    result: dict[str, Any] = {
        "client": "claude",
        "mode": mode,
        "command": command,
        "changed": mode == "apply",
    }
    if mode == "dry-run":
        return result
    completed = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )
    result.update(
        {
            "exit_code": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }
    )
    return result


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
