#!/bin/sh
# usage: changed-recipes.sh [BASE]
# Prints each top-level directory that holds a PKGBUILD and differs from BASE
# (a revision, default origin/main), one per line. BASE "all" prints every
# recipe directory; an all-zero BASE (the before-SHA of a branch's first push)
# compares against the empty tree. A BASE that does not resolve, a failed git
# command, or a recipe directory name outside [A-Za-z0-9._+-] exits non-zero:
# an unreadable change set never reads as "no recipes changed".
# Exit 0 listed (possibly nothing changed), 1 refused name, 2 unusable BASE or git.
set -eu

base=${1:-origin/main}
empty_tree=4b825dc642cb6eb9a060e54bf8d69288fbee4904
zero=0000000000000000000000000000000000000000

work=$(mktemp -d)
trap 'rm -rf "$work"' 0 HUP INT TERM

case "$base" in
    all)
        git ls-files -z > "$work/raw" || { printf 'changed=refused reason=git_failed\n' >&2; exit 2; }
        ;;
    "$zero")
        git diff --name-only -z "$empty_tree" HEAD > "$work/raw" ||
            { printf 'changed=refused reason=git_failed\n' >&2; exit 2; }
        ;;
    *)
        if ! git rev-parse --verify --quiet "$base^{commit}" > /dev/null; then
            printf 'changed=refused reason=base_unresolved base=%s\n' "$base" >&2
            exit 2
        fi
        git diff --name-only -z "$base"...HEAD > "$work/raw" ||
            { printf 'changed=refused reason=git_failed\n' >&2; exit 2; }
        ;;
esac

tr '\0' '\n' < "$work/raw" > "$work/paths"
sed -n 's|^\([^/]*\)/.*|\1|p' "$work/paths" > "$work/tops"
sort -u "$work/tops" > "$work/dirs"

status=0
while IFS= read -r dir; do
    [ -f "$dir/PKGBUILD" ] || continue
    case "$dir" in
        *[!A-Za-z0-9._+-]*|[!A-Za-z0-9]*)
            printf 'changed=refused reason=recipe_name_outside_allowed_characters\n' >&2
            status=1
            continue
            ;;
    esac
    printf '%s\n' "$dir"
done < "$work/dirs"
exit "$status"
