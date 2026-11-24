"""Command-line entrypoint for source-analysis-mcp."""

from __future__ import annotations

import argparse
import json
import sys

from .catalog import catalog
from .executor import HAZARD_ACK
from .server import run_stdio


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="source-analysis-mcp")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("serve", help="Run the stdio MCP server")
    subparsers.add_parser("catalog", help="Print the JSON tool catalog")
    subparsers.add_parser("doctor", help="Print tool availability and hazard policy")
    args = parser.parse_args(argv)

    if args.command == "serve":
        run_stdio()
        return 0
    if args.command == "catalog":
        print(json.dumps(catalog(), indent=2, sort_keys=True))
        return 0
    if args.command == "doctor":
        print(json.dumps({"tools": catalog(), "hazard_ack": HAZARD_ACK}, indent=2, sort_keys=True))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
