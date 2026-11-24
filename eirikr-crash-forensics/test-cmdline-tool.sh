#!/bin/sh
# Exercise kernel-cmdline-tool.sh against a command line in a temporary tree.
#
# The tool rewrites the file that decides whether this machine boots, and the
# two defects this suite was written to catch -- a stale token left behind by a
# value change, and a trailing space that made a second revert differ from the
# first -- were both invisible to shellcheck and to reading the code.
#
# usage: test-cmdline-tool.sh <path to kernel-cmdline-tool.sh> <work dir>
set -eu

tool_src=$1
work=$2
legacy='root=UUID=00000000-0000-0000-0000-000000000000 rw nowatchdog amd_iommu=on tsc=reliable'
# What apply produces from that line: nowatchdog deleted, reserve_mem appended.
applied='root=UUID=00000000-0000-0000-0000-000000000000 rw amd_iommu=on tsc=reliable reserve_mem=16M:4096:ramoops'
failures=0

# A copy of the tool rebound to the case directory, so no test touches /etc.
bind() {
    case_dir="$work/$1"
    mkdir -p "$case_dir/etc"
    sed -e "s#^cmdline_file=.*#cmdline_file=$case_dir/etc/cmdline#" \
        -e "s#^state_dir=.*#state_dir=$case_dir/var/state#" \
        "$tool_src" > "$case_dir/tool"
    chmod 0755 "$case_dir/tool"
}

live() { cat "$case_dir/etc/cmdline"; }

check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf 'FAIL %s\n     expected: [%s]\n     actual:   [%s]\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}

bind clean-cycle
printf '%s\n' "$legacy" > "$case_dir/etc/cmdline"
"$case_dir/tool" snapshot
"$case_dir/tool" apply
check 'apply adds the managed token and deletes the managed key' \
    "$applied" "$(live)"
"$case_dir/tool" revert
check 'revert restores the legacy line byte for byte' "$legacy" "$(live)"

bind value-change
printf '%s reserve_mem=4M:4096:ramoops\n' "$legacy" > "$case_dir/etc/cmdline"
"$case_dir/tool" snapshot
"$case_dir/tool" apply
check 'apply replaces a token of the same key rather than appending beside it' \
    "$applied" "$(live)"
"$case_dir/tool" revert
check 'revert restores the legacy value of a managed key' \
    "$legacy reserve_mem=4M:4096:ramoops" "$(live)"

bind later-edit
printf '%s\n' "$legacy" > "$case_dir/etc/cmdline"
"$case_dir/tool" snapshot
"$case_dir/tool" apply
printf '%s iommu=pt\n' "$(live)" > "$case_dir/etc/cmdline"
"$case_dir/tool" revert
check 'an unrelated edit made after install survives the revert, in order' \
    "$legacy iommu=pt" "$(live)"

bind idempotence
printf '%s\n' "$legacy" > "$case_dir/etc/cmdline"
"$case_dir/tool" snapshot
"$case_dir/tool" apply
once=$(live)
"$case_dir/tool" apply
check 'apply is idempotent' "$once" "$(live)"
"$case_dir/tool" revert
once=$(live)
"$case_dir/tool" revert
check 'revert is idempotent' "$once" "$(live)"

bind deleted-key
printf '%s\n' "$legacy" > "$case_dir/etc/cmdline"
"$case_dir/tool" snapshot
"$case_dir/tool" apply
check 'apply deletes a managed key that has no replacement token' \
    "$applied" "$(live)"
"$case_dir/tool" revert
check 'revert restores a deleted key in its original position' "$legacy" "$(live)"

bind deleted-key-absent
legacy_no_wd=$(printf '%s' "$legacy" | sed 's/nowatchdog //')
printf '%s\n' "$legacy_no_wd" > "$case_dir/etc/cmdline"
"$case_dir/tool" snapshot
"$case_dir/tool" apply
"$case_dir/tool" revert
check 'a line that never carried the deleted key does not gain it' \
    "$legacy_no_wd" "$(live)"

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'all kernel-cmdline-tool.sh tests passed\n'
