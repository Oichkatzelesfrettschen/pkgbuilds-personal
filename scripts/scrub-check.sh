#!/bin/sh
# usage: scrub-check.sh [-H HOSTS_FILE] [PATH...]
# Fails when a tracked file holds: an IPv4 literal in a private or shared
# range (RFC 1918, RFC 6598), an IPv6 unique-local or link-local
# literal, a home-directory path, a home-relative path into a
# private documentation tree, a credential file path (cloud CLI credentials,
# Oracle wallet files), a localhost mailbox, a private key header, a common
# token shape, or a host name listed in HOSTS_FILE (one name per line, matched
# case-insensitively as fixed text; the SCRUB_HOSTS_FILE variable names the
# same file). Binary files are scanned as text. Prints "file:line: class" per
# hit. With no PATH, checks every tracked file of the repository at the cwd.
# Exit 0 accepted, 1 refused (hits), 2 input failure: empty path list, a path
# that is missing or unreadable, an unreadable or blank-line hosts file, or a
# grep error. Input failure never reads as accepted.
set -eu

hosts=${SCRUB_HOSTS_FILE:-}
while getopts 'H:h' opt; do
    case "$opt" in
        H) hosts=$OPTARG ;;
        *) sed -n '2,17p' "$0"; exit 0 ;;
    esac
done
shift $((OPTIND - 1))

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM
list=$work/files
hits=$work/hits
: > "$hits"

refuse() {
    printf 'scrub=refused reason=%s\n' "$1" >&2
    exit 2
}

explicit=no
if [ "$#" -gt 0 ]; then
    explicit=yes
    printf '%s\n' "$@" > "$list"
else
    git ls-files > "$list" || refuse git_ls_files_failed
fi
[ -s "$list" ] || refuse empty_input

# A tracked directory is a submodule entry; every other path must be a
# readable regular file.
: > "$work/scan"
while IFS= read -r path; do
    if [ -d "$path" ] && [ "$explicit" = no ]; then
        printf 'scrub: skipped submodule entry %s\n' "$path" >&2
        continue
    fi
    if [ ! -f "$path" ] || [ ! -r "$path" ]; then
        refuse "unreadable_or_missing_path"
    fi
    printf '%s\n' "$path" >> "$work/scan"
done < "$list"
[ -s "$work/scan" ] || refuse empty_input

if [ -n "$hosts" ]; then
    [ -r "$hosts" ] && [ -s "$hosts" ] || refuse hosts_file_unreadable_or_empty
    if grep -q '^[[:space:]]*$' "$hosts"; then
        refuse hosts_file_has_blank_line
    fi
fi

# Runs grep with the given options over every path; records "path:line: class".
scan() {
    class=$1
    shift
    while IFS= read -r path; do
        rc=0
        grep -an "$@" -- "$path" > "$work/g.out" 2> "$work/g.err" || rc=$?
        case "$rc" in
            0)
                while IFS= read -r line; do
                    printf '%s:%s: %s\n' "$path" "${line%%:*}" "$class"
                done < "$work/g.out" >> "$hits"
                ;;
            1) ;;
            *) refuse "grep_error_$class" ;;
        esac
    done < "$work/scan"
}

# Patterns are written so that this file does not match itself.
scan home-path -E -e '(^|[^A-Za-z0-9_.-])/home/[A-Za-z0-9_][A-Za-z0-9_.-]*/'
scan home-relative-private-path -E -e '(~|\$HOM[E]|\$\{HOM[E]\})/(Project[s]|Githu[b])(/|$)'
scan credential-path -E -e '(^|[^A-Za-z0-9_])\.oc[i]/|\.aw[s]/(credentials|config)|cwalle[t]\.sso|ewalle[t]\.p12|tnsname[s]\.ora|Walle[t]_[A-Za-z0-9_]+'
scan ipv6-local -E -e '(^|[^0-9A-Fa-f:])([fF][cdCD][0-9A-Fa-f]{2}|[fF][eE][89abAB][0-9A-Fa-f])(:[0-9A-Fa-f]{0,4}){2,}'
scan localhost-mailbox -E -e '@local[h]ost'
scan private-key -E -e '-----BEGIN [A-Z ]*PRIVATE[ ]KEY'
scan github-token -E -e '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}'
scan aws-key -E -e '(AKIA|ASIA)[0-9A-Z]{16}'
scan slack-token -E -e 'xox[baprs]-[0-9A-Za-z-]{10,}'
scan api-key -E -e 'sk-[A-Za-z0-9_-]{32,}|AIza[0-9A-Za-z_-]{35}'
if [ -n "$hosts" ]; then
    scan private-host -i -F -f "$hosts"
fi

# IPv4: candidate dotted quads, then the private-range filter in awk. Four-part
# version strings (26.09.0.8, 6.7.80.0) look like public addresses, so only the
# ranges that name a local network or mesh peer are flagged.
while IFS= read -r path; do
    rc=0
    grep -anoE -e '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}($|[^0-9.]|\.[^0-9])' -- "$path" \
        > "$work/g.out" 2> "$work/g.err" || rc=$?
    case "$rc" in
        0) ;;
        1) continue ;;
        *) refuse grep_error_ipv4 ;;
    esac
    awk -F: -v path="$path" '
        {
            num = $1
            rest = substr($0, length($1) + 2)
            if (match(rest, /([0-9]{1,3}\.){3}[0-9]{1,3}/) == 0) next
            ip = substr(rest, RSTART, RLENGTH)
            split(ip, o, ".")
            for (i = 1; i <= 4; i++) if (o[i] + 0 > 255) next
            priv = (o[1] == 10) ||
                (o[1] == 172 && o[2] >= 16 && o[2] <= 31) ||
                (o[1] == 192 && o[2] == 168) ||
                (o[1] == 100 && o[2] >= 64 && o[2] <= 127)
            if (!priv) next
            printf "%s:%s: ipv4-literal\n", path, num
        }' "$work/g.out" >> "$hits"
done < "$work/scan"

if [ -s "$hits" ]; then
    sort -u "$hits"
    printf 'scrub=refused hits=%s\n' "$(sort -u "$hits" | wc -l)" >&2
    exit 1
fi
printf 'scrub=accepted\n'
