"""MCP server surface for source-analysis tooling."""

from __future__ import annotations

import json
from typing import Any

from mcp.server.mcpserver import MCPServer

from .catalog import catalog
from .executor import HAZARD_ACK, ToolRequest, execute_tool, version_result

INSTRUCTIONS = (
    "Use this server for local source, static-analysis, binary, tracing, profiling, "
    "and fuzzing evidence. Dry-run is the default. Mutation, fuzzing, tracing, sudo, "
    "and long-running captures require mode=approved plus the exact hazard_ack. "
    "Commands are argv-only; no arbitrary shell strings are accepted. Keep the first "
    "result claim tied to command, cwd, executable, exit code, and tool limits."
)

mcp = MCPServer("source-analysis", instructions=INSTRUCTIONS, log_level="ERROR")


@mcp.tool()
def source_analysis_catalog() -> dict[str, Any]:
    """Return the full source-analysis tool catalog with aliases and resolved paths."""
    return catalog()


@mcp.tool()
def source_analysis_hazard_ack() -> dict[str, str]:
    """Return the exact approval string needed for hazardous approved-mode tools."""
    return {"hazard_ack": HAZARD_ACK}


@mcp.tool()
def source_analysis_version(tool: str) -> dict[str, Any]:
    """Run a bounded version probe for a catalog tool."""
    return version_result(tool)


@mcp.tool()
def source_search(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    timeout_s: int = 60,
    max_output_bytes: int = 65536,
) -> dict[str, Any]:
    """Run lexical, tracked, syntax, semantic-pattern, or structural search tools."""
    return _run(
        tool,
        repo_root,
        query_or_rule,
        paths,
        extra_args,
        mode,
        timeout_s,
        max_output_bytes,
    )


@mcp.tool()
def source_transform(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    hazard_ack: str | None = None,
    timeout_s: int = 60,
) -> dict[str, Any]:
    """Run transform tools such as Coccinelle spatch or comby."""
    request = ToolRequest(
        tool=tool,
        repo_root=repo_root,
        query_or_rule=query_or_rule,
        paths=paths or [],
        extra_args=extra_args or [],
        mode=mode,
        hazard_ack=hazard_ack,
        timeout_s=timeout_s,
    )
    return execute_tool(request)


@mcp.tool()
def source_index(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    timeout_s: int = 60,
) -> dict[str, Any]:
    """Run symbol index, cross-reference, and call graph tools."""
    return _run(tool, repo_root, query_or_rule, paths, extra_args, mode, timeout_s, 65536)


@mcp.tool()
def source_static_analysis(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    hazard_ack: str | None = None,
    timeout_s: int = 300,
    artifact_dir: str | None = None,
) -> dict[str, Any]:
    """Run static analyzers and rule engines."""
    return execute_tool(
        ToolRequest(
            tool=tool,
            repo_root=repo_root,
            query_or_rule=query_or_rule,
            paths=paths or [],
            extra_args=extra_args or [],
            mode=mode,
            hazard_ack=hazard_ack,
            timeout_s=timeout_s,
            artifact_dir=artifact_dir,
        )
    )


@mcp.tool()
def source_metrics(
    tool: str,
    repo_root: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    timeout_s: int = 120,
) -> dict[str, Any]:
    """Run source size, complexity, and scope metrics."""
    return _run(tool, repo_root, None, paths, extra_args, mode, timeout_s, 65536)


@mcp.tool()
def binary_analysis(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    hazard_ack: str | None = None,
    timeout_s: int = 120,
    artifact_dir: str | None = None,
) -> dict[str, Any]:
    """Run binary, ABI, debugger, RE, and symbolization tools."""
    return execute_tool(
        ToolRequest(
            tool=tool,
            repo_root=repo_root,
            query_or_rule=query_or_rule,
            paths=paths or [],
            extra_args=extra_args or [],
            mode=mode,
            hazard_ack=hazard_ack,
            timeout_s=timeout_s,
            artifact_dir=artifact_dir,
        )
    )


@mcp.tool()
def trace_profile(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    allow_sudo: bool = False,
    hazard_ack: str | None = None,
    timeout_s: int = 120,
    artifact_dir: str | None = None,
) -> dict[str, Any]:
    """Run tracing and profiling tools with explicit approval gates."""
    return execute_tool(
        ToolRequest(
            tool=tool,
            repo_root=repo_root,
            query_or_rule=query_or_rule,
            paths=paths or [],
            extra_args=extra_args or [],
            mode=mode,
            allow_sudo=allow_sudo,
            hazard_ack=hazard_ack,
            timeout_s=timeout_s,
            artifact_dir=artifact_dir,
        )
    )


@mcp.tool()
def fuzz_instrument(
    tool: str,
    repo_root: str | None = None,
    query_or_rule: str | None = None,
    paths: list[str] | None = None,
    extra_args: list[str] | None = None,
    mode: str = "dry_run",
    allow_sudo: bool = False,
    hazard_ack: str | None = None,
    timeout_s: int = 120,
    artifact_dir: str | None = None,
) -> dict[str, Any]:
    """Run fuzzing and dynamic instrumentation tools with explicit gates."""
    return trace_profile(
        tool,
        repo_root,
        query_or_rule,
        paths,
        extra_args,
        mode,
        allow_sudo,
        hazard_ack,
        timeout_s,
        artifact_dir,
    )


@mcp.tool()
def source_analysis_doctor() -> dict[str, Any]:
    """Return availability information for every cataloged tool."""
    return {
        key: {
            "display": value["display"],
            "resolved_executable": value["resolved_executable"],
            "package_hint": value["package_hint"],
            "group": value["group"],
        }
        for key, value in catalog().items()
    }


@mcp.resource("source-analysis://catalog/tools")
def catalog_resource() -> str:
    """Full JSON tool catalog."""
    return json.dumps(catalog(), indent=2, sort_keys=True)


@mcp.resource("source-analysis://catalog/manpages")
def manpage_resource() -> str:
    """Compact note describing how manpage/help provenance is collected."""
    return (
        "Tool provenance is collected with command -v, man -w, --help, --version, "
        "and pacman -Qo. Missing manpages are recorded as catalog gaps, not ignored."
    )


@mcp.resource("source-analysis://safety/hazard-gates")
def hazard_resource() -> str:
    """Hazard approval policy."""
    return json.dumps(
        {
            "default_mode": "dry_run",
            "approved_mode_requires": ["mode=approved", "exact hazard_ack"],
            "hazard_ack": HAZARD_ACK,
            "sudo": "sudo -n is used only when allow_sudo=true and the tool declares sudo support.",
        },
        indent=2,
    )


@mcp.prompt()
def source_analysis_triage(goal: str) -> str:
    """Plan a source-analysis tool sequence for a concrete evidence goal."""
    return (
        f"Goal: {goal}\n"
        "Start with source_search or source_index. Escalate to static analysis, binary "
        "inspection, tracing, or fuzzing only when the cheaper evidence leaves a named unknown. "
        "Keep every claim tied to command, cwd, executable, exit code, and limits."
    )


def run_stdio() -> None:
    mcp.run(transport="stdio")


def _run(
    tool: str,
    repo_root: str | None,
    query_or_rule: str | None,
    paths: list[str] | None,
    extra_args: list[str] | None,
    mode: str,
    timeout_s: int,
    max_output_bytes: int,
) -> dict[str, Any]:
    return execute_tool(
        ToolRequest(
            tool=tool,
            repo_root=repo_root,
            query_or_rule=query_or_rule,
            paths=paths or [],
            extra_args=extra_args or [],
            mode=mode,
            timeout_s=timeout_s,
            max_output_bytes=max_output_bytes,
        )
    )
