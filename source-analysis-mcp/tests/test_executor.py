from __future__ import annotations

from pathlib import Path

import pytest

from source_analysis_mcp.catalog import catalog, lookup_tool
from source_analysis_mcp.executor import HAZARD_ACK, ToolRequest, create_plan


def test_catalog_preserves_spatch_and_joern_paths() -> None:
    tools = catalog()
    assert tools["spatch"]["executable"] == "/usr/bin/spatch"
    assert tools["spatch"]["package_hint"] == "coccinelle-bin"
    assert tools["joern_parse"]["executable"] == "/opt/joern/joern-cli/bin/joern-parse"


def test_lookup_aliases() -> None:
    assert lookup_tool("ripgrep").key == "rg"
    assert lookup_tool("coccinelle").key == "spatch"
    assert lookup_tool("git-grep").key == "git_grep"


def test_dry_run_plan_uses_query_and_path(tmp_path: Path) -> None:
    source = tmp_path / "a.c"
    source.write_text("int main(void) { return 0; }\n", encoding="utf-8")
    plan = create_plan(
        ToolRequest(tool="rg", repo_root=str(tmp_path), query_or_rule="main", paths=["a.c"])
    )
    assert plan.dry_run is True
    assert "--" in plan.argv
    assert "main" in plan.argv
    assert "a.c" in plan.argv


def test_path_escape_is_rejected(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="escapes"):
        create_plan(ToolRequest(tool="rg", repo_root=str(tmp_path), paths=["../outside"]))


def test_hazard_requires_exact_ack(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="hazard_ack"):
        create_plan(ToolRequest(tool="spatch", repo_root=str(tmp_path), mode="approved"))

    plan = create_plan(
        ToolRequest(
            tool="spatch",
            repo_root=str(tmp_path),
            mode="approved",
            hazard_ack=HAZARD_ACK,
        )
    )
    assert plan.dry_run is False
