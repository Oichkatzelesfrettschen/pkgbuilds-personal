#!/bin/sh
# Add or remove the kernel command-line tokens that arm crash capture on this
# workstation, and keep the change reversible.
#
# /etc/kernel/cmdline is a single line with no drop-in directory, so a package
# cannot own it the way it owns a file under /etc/sysctl.d. This tool manages a
# set of parameter keys and leaves every other token untouched, so a later
# unrelated edit survives an uninstall. Matching is by key rather than by whole
# token, so an upgrade that changes a value replaces the old token instead of
# leaving it behind beside the new one. The pre-install snapshot beside it
# records the legacy line verbatim for a full restore.
set -eu

cmdline_file=/etc/kernel/cmdline
state_dir=/var/lib/eirikr-crash-forensics
snapshot="$state_dir/kernel-cmdline.pre-install"

# reserve_mem names a region that survives a reset and that kdumpst-load.sh
# finds by parsing this parameter, then hands to ramoops as mem_name. 16 MiB
# holds the 2 MiB console zone this package configures in
# /etc/modprobe.d/50-ramoops-console.conf plus 56 dump zones of 256 KiB.
managed_tokens='reserve_mem=16M:4096:ramoops'
# Every parameter key this tool owns. A token on the live line whose key
# appears here is this package's to replace or remove, and a key that appears
# here without a counterpart in managed_tokens is one this package deletes.
#
# nowatchdog zeroes watchdog, nmi_watchdog and soft_watchdog together, so the
# perf NMI hard-lockup detector never arms and a CPU spinning with interrupts
# disabled produces no panic, no kmsg dump, and no backtrace. Deleting it is
# what turns a hard lockup into recorded evidence. revert reads the token back
# out of the snapshot, so a machine whose legacy line lacked it does not gain
# it on uninstall.
managed_keys='reserve_mem nowatchdog'

usage() {
    printf 'usage: %s {apply|revert|snapshot|status}\n' "${0##*/}" >&2
    exit 2
}

require_cmdline() {
    if [ ! -f "$cmdline_file" ]; then
        printf 'eirikr-crash-forensics: %s is absent\n' "$cmdline_file" >&2
        exit 1
    fi
}

# One space between tokens, no leading or trailing space, so two normalized
# lines compare as strings.
normalize() {
    tr -s ' \t\n' ' ' < "$1" | sed -e 's/^ *//' -e 's/ *$//'
}

token_key() {
    case "$1" in
    *=*) printf '%s' "${1%%=*}" ;;
    *) printf '%s' "$1" ;;
    esac
}

is_managed_key() {
    for _key in $managed_keys; do
        [ "$1" = "$_key" ] && return 0
    done
    return 1
}

# Every token of the given file whose key this tool does not own, in order.
foreign_tokens() {
    _result=''
    for _token in $(normalize "$1"); do
        is_managed_key "$(token_key "$_token")" && continue
        _result="${_result:+$_result }$_token"
    done
    printf '%s' "$_result"
}

# Every token of the given file whose key this tool does own, in order.
own_tokens() {
    _result=''
    for _token in $(normalize "$1"); do
        is_managed_key "$(token_key "$_token")" || continue
        _result="${_result:+$_result }$_token"
    done
    printf '%s' "$_result"
}

# The command line this package produces from the given line.
applied_form() {
    _foreign=$(foreign_tokens "$1")
    printf '%s' "${_foreign:+$_foreign }$managed_tokens"
}

has_token() {
    # shellcheck disable=SC2086
    for _candidate in $2; do
        [ "$_candidate" = "$1" ] && return 0
    done
    return 1
}

# The command line an uninstall produces from the given line, rebuilt in the
# snapshot's own token order so a revert is byte-stable and running it twice
# changes nothing. Appending the restored tokens instead would move them to the
# end of the line on every revert after the first.
#
# A snapshot token is emitted when this tool owns its key, which is the restore,
# or when it is still on the live line, which preserves its original position. A
# snapshot token absent from the live line was deleted after the install and
# stays deleted. A live token the snapshot never had was added after the install
# and is appended, so a later edit survives.
reverted_form() {
    _live=$(normalize "$1")
    _snap=''
    [ -f "$snapshot" ] && _snap=$(normalize "$snapshot")
    _result=''

    # shellcheck disable=SC2086
    for _token in $_snap; do
        if is_managed_key "$(token_key "$_token")" || has_token "$_token" "$_live"; then
            _result="${_result:+$_result }$_token"
        fi
    done
    # shellcheck disable=SC2086
    for _token in $_live; do
        is_managed_key "$(token_key "$_token")" && continue
        has_token "$_token" "$_snap" && continue
        _result="${_result:+$_result }$_token"
    done
    printf '%s' "$_result"
}

# Rewrite the line through a temporary file in the same directory so a failed
# write cannot leave a half-written command line behind.
write_line() {
    tmp=$(mktemp "$cmdline_file.XXXXXX")
    trap 'rm -f "$tmp"' EXIT INT TERM
    printf '%s\n' "$1" > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$cmdline_file"
    trap - EXIT INT TERM
}

case "${1-}" in
snapshot)
    require_cmdline
    mkdir -p "$state_dir"
    # Only the first install records the legacy line; a reinstall must not
    # overwrite it with an already-modified command line.
    if [ ! -f "$snapshot" ]; then
        cp -a "$cmdline_file" "$snapshot"
    fi
    ;;
apply)
    require_cmdline
    write_line "$(applied_form "$cmdline_file")"
    ;;
revert)
    require_cmdline
    # When the live line is exactly what this package would have produced from
    # the snapshot, nothing else has edited it, so the legacy line is restored
    # byte for byte including its original token order. Otherwise a later edit
    # exists and must survive, so only this package's own keys are undone.
    if [ -f "$snapshot" ] && [ "$(normalize "$cmdline_file")" = "$(applied_form "$snapshot")" ]; then
        cp -a "$snapshot" "$cmdline_file"
    else
        write_line "$(reverted_form "$cmdline_file")"
    fi
    ;;
status)
    require_cmdline
    printf 'cmdline:  %s\n' "$(normalize "$cmdline_file")"
    printf 'applied:  %s\n' "$(applied_form "$cmdline_file")"
    printf 'snapshot: %s\n' "$([ -f "$snapshot" ] && echo "$snapshot" || echo none)"
    ;;
*)
    usage
    ;;
esac
