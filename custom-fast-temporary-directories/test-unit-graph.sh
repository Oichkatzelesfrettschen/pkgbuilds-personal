#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f ${script_directory}/srv-fasttmp.mount ]]; then
  package_root=${script_directory}
else
  package_root=$(cd -- "${script_directory}/.." && pwd)
fi

fixture_root=$(mktemp -d)
cleanup() {
  rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

install -d -m755 \
  "${fixture_root}/etc/systemd/system" \
  "${fixture_root}/usr/lib/custom-fast-temporary-directories" \
  "${fixture_root}/usr/lib/systemd/system"
install -Dm644 \
  "${package_root}/tmp.mount" \
  "${fixture_root}/etc/systemd/system/"
install -Dm644 \
  "${package_root}/srv-fasttmp.mount" \
  "${package_root}/custom-fast-temporary-directories-prepare.service" \
  "${package_root}/var-tmp.mount" \
  "${fixture_root}/usr/lib/systemd/system/"
install -Dm755 \
  "${package_root}/custom-fast-temporary-directories-prepare" \
  "${fixture_root}/usr/lib/custom-fast-temporary-directories/prepare"

systemd-analyze verify --root="${fixture_root}" \
  srv-fasttmp.mount \
  custom-fast-temporary-directories-prepare.service \
  tmp.mount \
  var-tmp.mount

grep -Eq '^Requires=.*var-tmp\.mount' "${package_root}/tmp.mount"

printf 'test-unit-graph: systemd dependency validation passed\n'
