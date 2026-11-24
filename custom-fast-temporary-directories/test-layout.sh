#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f ${script_directory}/custom-fast-temporary-directories-prepare ]]; then
  package_root=${script_directory}
else
  package_root=$(cd -- "${script_directory}/.." && pwd)
fi
fixture_root=$(mktemp -d)
cleanup() {
  rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

storage_fixture=${fixture_root}/storage
mkdir -p -- \
  "${storage_fixture}/lost+found" \
  "${storage_fixture}/tmp" \
  "${storage_fixture}/var-tmp" \
  "${storage_fixture}/ordinary directory"
printf 'volatile\n' >"${storage_fixture}/ordinary directory/file"
printf 'legacy tmp\n' >"${storage_fixture}/tmp/file"
printf 'legacy var tmp\n' >"${storage_fixture}/var-tmp/file"
mkdir -m0700 -- "${storage_fixture}/legacy-shared-root"
printf '%s\n' pending >"${storage_fixture}/.custom-fast-temporary-directories-layout"
chmod 0600 "${storage_fixture}/.custom-fast-temporary-directories-layout"

CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_ROOT=${storage_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-prepare"

[[ $(<"${storage_fixture}/.custom-fast-temporary-directories-layout") == complete ]]
[[ -f ${storage_fixture}/legacy-shared-root/ordinary\ directory/file ]]
[[ -f ${storage_fixture}/legacy-shared-root/tmp/file ]]
[[ -f ${storage_fixture}/legacy-shared-root/var-tmp/file ]]
[[ -d ${storage_fixture}/lost+found ]]
[[ $(stat -c '%a' "${storage_fixture}/tmp") == 1777 ]]
[[ $(stat -c '%a' "${storage_fixture}/var-tmp") == 1777 ]]
[[ $(stat -c '%a' "${storage_fixture}/legacy-shared-root") == 700 ]]

printf 'new tmp\n' >"${storage_fixture}/tmp/new-file"
printf 'new var tmp\n' >"${storage_fixture}/var-tmp/new-file"
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_ROOT=${storage_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-prepare"
[[ -f ${storage_fixture}/tmp/new-file ]]
[[ -f ${storage_fixture}/var-tmp/new-file ]]

interrupted_fixture=${fixture_root}/interrupted
mkdir -p -- \
  "${interrupted_fixture}/lost+found" \
  "${interrupted_fixture}/legacy-shared-root/tmp" \
  "${interrupted_fixture}/legacy-shared-root/var-tmp" \
  "${interrupted_fixture}/tmp" \
  "${interrupted_fixture}/var-tmp"
chmod 0700 "${interrupted_fixture}/legacy-shared-root"
printf 'legacy-moved\n' >"${interrupted_fixture}/.custom-fast-temporary-directories-layout"
chmod 0600 "${interrupted_fixture}/.custom-fast-temporary-directories-layout"
printf 'old\n' >"${interrupted_fixture}/legacy-shared-root/tmp/old"
printf 'new\n' >"${interrupted_fixture}/tmp/new"
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_ROOT=${interrupted_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-prepare"
[[ -f ${interrupted_fixture}/legacy-shared-root/tmp/old ]]
[[ -f ${interrupted_fixture}/tmp/new ]]
[[ $(<"${interrupted_fixture}/.custom-fast-temporary-directories-layout") == complete ]]

former_fixture=${fixture_root}/former-name
mkdir -p -- \
  "${former_fixture}/lost+found" \
  "${former_fixture}/legacy-shared-root" \
  "${former_fixture}/tmp" \
  "${former_fixture}/var-tmp"
chmod 0700 "${former_fixture}/legacy-shared-root"
printf 'complete\n' >"${former_fixture}/.private-fast-temporary-directories-layout"
chmod 0600 "${former_fixture}/.private-fast-temporary-directories-layout"
printf 'live\n' >"${former_fixture}/tmp/live"
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_ROOT=${former_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-prepare"
[[ $(<"${former_fixture}/.custom-fast-temporary-directories-layout") == complete ]]
[[ ! -e ${former_fixture}/.private-fast-temporary-directories-layout ]]
[[ -f ${former_fixture}/tmp/live ]]
[[ -z $(ls -A -- "${former_fixture}/legacy-shared-root") ]]

symlink_fixture=${fixture_root}/symlink
mkdir -p -- "${symlink_fixture}/legacy-shared-root"
chmod 0700 "${symlink_fixture}/legacy-shared-root"
printf 'unchanged\n' >"${fixture_root}/symlink-target"
ln -s "${fixture_root}/symlink-target" \
  "${symlink_fixture}/.custom-fast-temporary-directories-layout"
if CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
   CUSTOM_FAST_TEMPORARY_DIRECTORIES_ROOT=${symlink_fixture} \
   bash "${package_root}/custom-fast-temporary-directories-prepare" 2>/dev/null; then
  printf 'test-layout: unsafe state symlink was accepted\n' >&2
  exit 1
fi
[[ $(<"${fixture_root}/symlink-target") == unchanged ]]

fstab_fixture=${fixture_root}/fstab
tmpfiles_fixture=${fixture_root}/tmp.conf
reservation_fixture=${fixture_root}/reservation
mkdir -m1777 -- "${reservation_fixture}"
cat >"${fstab_fixture}" <<'EOF'
UUID=f80f3ba8-49f9-46ae-9101-c8638f017a64 /tmp ext4 rw,nosuid,nodev 0 2
/tmp /var/tmp none bind 0 0
EOF
printf 'D! /tmp 1777 root root -\n' >"${tmpfiles_fixture}"

CUSTOM_FAST_TEMPORARY_DIRECTORIES_FSTAB=${fstab_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TMPFILES_OVERRIDE=${tmpfiles_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-migrate-config" --check

CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_FSTAB=${fstab_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TMPFILES_OVERRIDE=${tmpfiles_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_LIVE_TMP=${reservation_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_FAIL_AFTER_FSTAB=1 \
  bash "${package_root}/custom-fast-temporary-directories-migrate-config" --apply && {
    printf 'test-layout: injected fstab interruption did not stop migration\n' >&2
    exit 1
  }

[[ -e ${tmpfiles_fixture} ]]

CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_FSTAB=${fstab_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TMPFILES_OVERRIDE=${tmpfiles_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_LIVE_TMP=${reservation_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_FAIL_AFTER_RESERVE_DIRECTORY=1 \
  bash "${package_root}/custom-fast-temporary-directories-migrate-config" --apply && {
    printf 'test-layout: injected reservation interruption did not stop migration\n' >&2
    exit 1
  }

[[ -d ${reservation_fixture}/legacy-shared-root ]]
[[ ! -e ${reservation_fixture}/.custom-fast-temporary-directories-layout ]]

CUSTOM_FAST_TEMPORARY_DIRECTORIES_TESTING=1 \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_FSTAB=${fstab_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TMPFILES_OVERRIDE=${tmpfiles_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_LIVE_TMP=${reservation_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-migrate-config" --apply

[[ ! -e ${tmpfiles_fixture} ]]
[[ $(<"${reservation_fixture}/.custom-fast-temporary-directories-layout") == pending ]]
[[ $(stat -c '%a' "${reservation_fixture}/legacy-shared-root") == 700 ]]
grep -Fq '# UUID=f80f3ba8-49f9-46ae-9101-c8638f017a64 /tmp ext4' \
  "${fstab_fixture}"
grep -Fq '# /tmp /var/tmp none bind' "${fstab_fixture}"

CUSTOM_FAST_TEMPORARY_DIRECTORIES_FSTAB=${fstab_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_TMPFILES_OVERRIDE=${tmpfiles_fixture} \
CUSTOM_FAST_TEMPORARY_DIRECTORIES_LIVE_TMP=${reservation_fixture} \
  bash "${package_root}/custom-fast-temporary-directories-migrate-config" --check

printf 'test-layout: all fixture checks passed\n'
