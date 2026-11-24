"""Tool catalog for the source-analysis MCP server."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from shutil import which
from typing import Final


@dataclass(frozen=True)
class ToolSpec:
    key: str
    display: str
    aliases: tuple[str, ...]
    group: str
    evidence_class: str
    executable: str
    package_hint: str
    version_args: tuple[str, ...] = ("--version",)
    requires_approval: bool = False
    allows_write: bool = False
    allows_sudo: bool = False
    notes: str = ""

    def resolved_executable(self) -> str | None:
        if self.executable.startswith("/"):
            if which(self.executable) or _path_exists(self.executable):
                return self.executable
            return None
        return which(self.executable)

    def to_public_dict(self) -> dict[str, object]:
        result = asdict(self)
        result["resolved_executable"] = self.resolved_executable()
        return result


def _path_exists(path: str) -> bool:
    from pathlib import Path

    return Path(path).exists()


TOOLS: Final[dict[str, ToolSpec]] = {
    "rg": ToolSpec("rg", "ripgrep", ("ripgrep",), "search", "text", "rg", "ripgrep"),
    "git_grep": ToolSpec(
        "git_grep", "git grep", ("git-grep",), "search", "tracked text", "git", "git"
    ),
    "ast_grep": ToolSpec(
        "ast_grep", "ast-grep", ("sg",), "search", "syntax", "ast-grep", "ast-grep"
    ),
    "tree_sitter": ToolSpec(
        "tree_sitter", "tree-sitter", ("tree-sitter-cli",), "search", "syntax", "tree-sitter",
        "tree-sitter-cli"
    ),
    "weggli": ToolSpec("weggli", "weggli", (), "search", "semantic pattern", "weggli", "weggli"),
    "comby": ToolSpec("comby", "comby", (), "transform", "structural rewrite", "comby", "comby"),
    "semgrep": ToolSpec(
        "semgrep", "semgrep", (), "static", "semantic rule", "semgrep", "semgrep"
    ),
    "spatch": ToolSpec(
        "spatch",
        "Coccinelle spatch",
        ("coccinelle",),
        "transform",
        "semantic patch",
        "/usr/bin/spatch",
        "coccinelle-bin",
        requires_approval=True,
        allows_write=True,
        notes="Coccinelle executable; cite --sp-file and target path set.",
    ),
    "ctags": ToolSpec("ctags", "ctags", (), "index", "symbol index", "ctags", "ctags"),
    "readtags": ToolSpec(
        "readtags", "readtags", ("read-tags",), "index", "tag query", "readtags", "ctags"
    ),
    "gtags": ToolSpec("gtags", "gtags", (), "index", "cross reference", "gtags", "global"),
    "global": ToolSpec(
        "global", "GNU Global", ("gnu-global",), "index", "cross reference", "global", "global"
    ),
    "cscope": ToolSpec("cscope", "cscope", (), "index", "cross reference", "cscope", "cscope"),
    "cflow": ToolSpec("cflow", "cflow", (), "index", "call graph", "cflow", "cflow"),
    "clangd": ToolSpec("clangd", "clangd", (), "index", "LSP", "clangd", "clang"),
    "cppcheck": ToolSpec(
        "cppcheck", "cppcheck", (), "static", "static analysis", "cppcheck", "cppcheck"
    ),
    "clang_tidy": ToolSpec(
        "clang_tidy", "clang-tidy", (), "static", "static analysis", "clang-tidy",
        "clang"
    ),
    "scan_build": ToolSpec(
        "scan_build", "scan-build", (), "static", "static analysis", "scan-build", "clang"
    ),
    "sparse": ToolSpec("sparse", "sparse", (), "static", "static analysis", "sparse", "sparse"),
    "smatch": ToolSpec("smatch", "smatch", (), "static", "static analysis", "smatch", "smatch"),
    "infer": ToolSpec("infer", "infer", (), "static", "static analysis", "infer", "infer-static"),
    "codeql": ToolSpec(
        "codeql", "CodeQL", (), "static", "dataflow analysis", "codeql", "codeql",
        requires_approval=True,
        allows_write=True,
    ),
    "lizard": ToolSpec(
        "lizard", "lizard", (), "metrics", "complexity", "lizard", "python-lizard"
    ),
    "scc": ToolSpec("scc", "scc", (), "metrics", "size metrics", "scc", "scc"),
    "cloc": ToolSpec("cloc", "cloc", (), "metrics", "size metrics", "cloc", "cloc"),
    "readelf": ToolSpec("readelf", "readelf", (), "binary", "ELF metadata", "readelf", "binutils"),
    "nm": ToolSpec("nm", "nm", (), "binary", "symbols", "nm", "binutils"),
    "objdump": ToolSpec("objdump", "objdump", (), "binary", "disassembly", "objdump", "binutils"),
    "addr2line": ToolSpec(
        "addr2line", "addr2line", (), "binary", "symbolization", "addr2line", "binutils"
    ),
    "gdb": ToolSpec("gdb", "gdb", (), "binary", "debugger", "gdb", "gdb", requires_approval=True),
    "strace": ToolSpec(
        "strace", "strace", (), "binary", "syscall trace", "strace", "strace",
        requires_approval=True
    ),
    "ltrace": ToolSpec(
        "ltrace", "ltrace", (), "binary", "library trace", "ltrace", "ltrace",
        requires_approval=True
    ),
    "radiff2": ToolSpec("radiff2", "radiff2", (), "binary", "binary diff", "radiff2", "radare2"),
    "r2": ToolSpec(
        "r2", "radare2", ("radare2",), "binary", "reverse engineering", "r2", "radare2",
        requires_approval=True
    ),
    "rizin": ToolSpec(
        "rizin", "rizin", (), "binary", "reverse engineering", "rizin", "rizin",
        requires_approval=True
    ),
    "binwalk": ToolSpec(
        "binwalk", "binwalk", (), "binary", "firmware scan", "binwalk", "binwalk",
        requires_approval=True,
        allows_write=True,
    ),
    "ghidra": ToolSpec(
        "ghidra", "Ghidra", (), "binary", "decompiler", "ghidra", "ghidra",
        requires_approval=True,
        allows_write=True,
    ),
    "lief": ToolSpec(
        "lief", "LIEF", (), "binary", "binary format library", "python3", "python-lief",
        notes="Use Python module import; LIEF is library-first here."
    ),
    "bpftrace": ToolSpec(
        "bpftrace", "bpftrace", (), "trace", "eBPF trace", "bpftrace", "bpftrace",
        requires_approval=True,
        allows_sudo=True,
    ),
    "bcc": ToolSpec(
        "bcc", "BCC tools", ("bcc-tools",), "trace", "eBPF trace", "opensnoop",
        "bcc-libbpf-tools",
        requires_approval=True,
        allows_sudo=True,
        notes="BCC is exposed as individual commands such as opensnoop, execsnoop, statsnoop.",
    ),
    "trace_cmd": ToolSpec(
        "trace_cmd", "trace-cmd", (), "trace", "ftrace", "trace-cmd", "trace-cmd",
        requires_approval=True,
        allows_sudo=True,
        allows_write=True,
    ),
    "lttng": ToolSpec(
        "lttng", "LTTng", ("lttng-tools-generic-kernel",), "trace", "kernel/user trace",
        "lttng", "lttng-tools-generic-kernel",
        requires_approval=True,
        allows_sudo=True,
        allows_write=True,
    ),
    "stap": ToolSpec(
        "stap", "SystemTap", ("systemtap",), "trace", "kernel/user probes", "stap",
        "systemtap",
        requires_approval=True,
        allows_sudo=True,
    ),
    "perfetto": ToolSpec(
        "perfetto", "Perfetto", (), "trace", "timeline trace", "perfetto", "perfetto",
        requires_approval=True,
        allows_write=True,
    ),
    "sysprof": ToolSpec(
        "sysprof", "Sysprof", (), "profile", "profile", "sysprof", "sysprof",
        requires_approval=True,
        allows_write=True,
    ),
    "heaptrack": ToolSpec(
        "heaptrack", "heaptrack", (), "profile", "heap profile", "heaptrack", "heaptrack",
        requires_approval=True,
        allows_write=True,
    ),
    "valgrind": ToolSpec(
        "valgrind", "Valgrind", (), "profile", "instrumentation", "valgrind", "valgrind",
        requires_approval=True,
        allows_write=True,
    ),
    "hotspot": ToolSpec(
        "hotspot", "Hotspot", (), "profile", "callgrind viewer", "hotspot", "hotspot",
        requires_approval=True,
    ),
    "radamsa": ToolSpec(
        "radamsa", "Radamsa", (), "fuzz", "mutation", "radamsa", "radamsa",
        requires_approval=True,
        allows_write=True,
    ),
    "afl_fuzz": ToolSpec(
        "afl_fuzz", "AFL++", ("afl++",), "fuzz", "coverage fuzzing", "afl-fuzz", "afl++",
        requires_approval=True,
        allows_write=True,
    ),
    "honggfuzz": ToolSpec(
        "honggfuzz", "honggfuzz", (), "fuzz", "coverage fuzzing", "honggfuzz", "honggfuzz",
        requires_approval=True,
        allows_write=True,
    ),
    "frida": ToolSpec(
        "frida", "Frida", ("python-frida", "python-frida-tools", "frida-tools"), "instrument",
        "dynamic instrumentation", "frida", "python-frida-tools",
        requires_approval=True,
    ),
    "frida_trace": ToolSpec(
        "frida_trace", "frida-trace", ("frida-tools",), "instrument",
        "dynamic instrumentation", "frida-trace", "python-frida-tools",
        requires_approval=True,
        allows_write=True,
    ),
    "python_ptrace": ToolSpec(
        "python_ptrace", "python-ptrace", (), "instrument", "ptrace", "python3",
        "python-ptrace",
        requires_approval=True,
        allows_sudo=True,
    ),
    "joern_parse": ToolSpec(
        "joern_parse", "joern-parse", ("joern",), "graph", "code property graph",
        "/opt/joern/joern-cli/bin/joern-parse", "joern",
        requires_approval=True,
        allows_write=True,
    ),
    "joern_scan": ToolSpec(
        "joern_scan", "joern-scan", ("joern",), "graph", "code property graph",
        "/opt/joern/joern-cli/bin/joern-scan", "joern",
        requires_approval=True,
        allows_write=True,
    ),
}


GROUPS: Final[dict[str, tuple[str, ...]]] = {}


def lookup_tool(key: str) -> ToolSpec:
    normalized = key.replace("-", "_")
    if normalized in TOOLS:
        return TOOLS[normalized]
    for spec in TOOLS.values():
        if key == spec.display or key in spec.aliases:
            return spec
    msg = f"unknown source-analysis tool: {key}"
    raise KeyError(msg)


def catalog() -> dict[str, dict[str, object]]:
    return {key: spec.to_public_dict() for key, spec in sorted(TOOLS.items())}
