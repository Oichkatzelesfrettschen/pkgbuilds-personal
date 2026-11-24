#!/bin/sh
# usage: srcinfo-check.sh PACKAGE_DIRECTORY
# Renders .SRCINFO with makepkg --printsrcinfo as an unprivileged user and
# compares it byte for byte with the tracked file. Exit 0 accepted, 1 refused,
# 2 usage.
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: srcinfo-check.sh PACKAGE_DIRECTORY\n' >&2
    exit 2
fi
cd -- "$1"
if [ ! -f PKGBUILD ] || [ ! -f .SRCINFO ]; then
    printf 'srcinfo=refused reason=missing_recipe_or_metadata\n' >&2
    exit 1
fi

# makepkg refuses root even for metadata rendering. setpriv changes
# credentials without a PAM session, which avoids a logind session for nobody.
as_nobody() {
    setpriv --reuid=nobody --regid=nobody --clear-groups -- \
        env HOME=/ USER=nobody LOGNAME=nobody "$@"
}
if [ "$(id -u)" -eq 0 ]; then
    render_directory=$(as_nobody mktemp -d)
    trap 'rmdir "$render_directory"' 0
    if ! rendered_metadata=$(as_nobody env \
        BUILDDIR="$render_directory" SRCDEST="$render_directory" \
        PKGDEST="$render_directory" SRCPKGDEST="$render_directory" \
        LOGDEST="$render_directory" makepkg --printsrcinfo); then
        printf 'srcinfo=refused reason=render_failed\n' >&2
        exit 1
    fi
else
    if ! rendered_metadata=$(makepkg --printsrcinfo); then
        printf 'srcinfo=refused reason=render_failed\n' >&2
        exit 1
    fi
fi
if [ -z "$rendered_metadata" ]; then
    printf 'srcinfo=refused reason=empty_render\n' >&2
    exit 1
fi
if ! printf '%s\n' "$rendered_metadata" | cmp -s .SRCINFO -; then
    printf 'srcinfo=refused reason=metadata_mismatch\n' >&2
    exit 1
fi
printf 'srcinfo=accepted\n'
