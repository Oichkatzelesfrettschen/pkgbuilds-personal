from __future__ import annotations

from pathlib import Path

import tomlkit

from source_analysis_mcp.register import register_codex


def test_register_codex_dry_run_preserves_file(tmp_path: Path) -> None:
    config = tmp_path / "config.toml"
    config.write_text('model = "gpt-5.5"\n', encoding="utf-8")
    result = register_codex(config, "dry-run")
    assert result["changed"] is True
    assert config.read_text(encoding="utf-8") == 'model = "gpt-5.5"\n'


def test_register_codex_apply_writes_server(tmp_path: Path) -> None:
    config = tmp_path / "config.toml"
    config.write_text('model = "gpt-5.5"\n', encoding="utf-8")
    result = register_codex(config, "apply")
    assert result["changed"] is True
    doc = tomlkit.parse(config.read_text(encoding="utf-8"))
    assert doc["mcp_servers"]["source-analysis"]["command"] == "/usr/bin/source-analysis-mcp"
    assert doc["mcp_servers"]["source-analysis"]["args"] == ["serve"]
