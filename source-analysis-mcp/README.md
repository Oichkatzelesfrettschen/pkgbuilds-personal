# source-analysis-mcp

`source-analysis-mcp` is a local stdio Model Context Protocol server for
source navigation, static analysis, binary inspection, tracing, profiling,
fuzzing, and dynamic instrumentation tools.

The package is built and installed with pacman through the PKGBUILD in this
directory.  It installs one unified server command:

```sh
/usr/bin/source-analysis-mcp serve
```

It also installs a registration helper:

```sh
source-analysis-mcp-register --client both --mode dry-run
source-analysis-mcp-register --client both --mode apply
```

The helper registers:

- Codex in `~/.codex/config.toml`
- Claude through `claude mcp add --scope user`

The pacman install script prints these commands but does not edit user home
configuration as root.

## Safety model

Every tool defaults to `mode=dry_run`.  Tools that can mutate files, launch
long captures, run fuzzers, inspect live processes, or use sudo require:

- `mode=approved`
- the exact hazard acknowledgement returned by `source_analysis_hazard_ack`
- `allow_sudo=true` for sudo-capable probes

The server builds argv arrays directly and does not accept arbitrary shell
command strings.

## Tool groups

- Search and transform: `rg`, `git grep`, `ast-grep`, `tree-sitter`,
  `weggli`, `comby`, Semgrep, Coccinelle `spatch`.
- Index and reachability: `ctags`, `readtags`, GNU Global, `cscope`, `cflow`,
  `clangd`.
- Static analysis: `cppcheck`, `clang-tidy`, `scan-build`, `sparse`, `smatch`,
  Infer, CodeQL.
- Metrics: `lizard`, `scc`, `cloc`.
- Binary and reverse engineering: `readelf`, `nm`, `objdump`, `addr2line`,
  `gdb`, `strace`, `ltrace`, `radiff2`, `r2`, Rizin, `binwalk`, LIEF, Ghidra.
- Trace and profile: `bpftrace`, BCC tools, `trace-cmd`, LTTng, SystemTap,
  Perfetto, Sysprof, Heaptrack, Valgrind, Hotspot.
- Fuzz and instrumentation: Radamsa, AFL++, honggfuzz, Frida, Python ptrace,
  Python Frida, Joern.

## Build and install

```sh
makepkg --syncdeps --cleanbuild --clean --force
sudo pacman -U source-analysis-mcp-*.pkg.tar.*
source-analysis-mcp-register --client both --mode apply
```

## Verify

```sh
source-analysis-mcp doctor
codex mcp list
claude mcp list
```
