#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fixture_root=$(mktemp -d)
cleanup() {
  rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

stub_directory=${fixture_root}/bin
mkdir -p -- "${stub_directory}"

cat >"${stub_directory}/findmnt" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *UUID*) printf '%s\n' f80f3ba8-49f9-46ae-9101-c8638f017a64 ;;
  *FSROOT*'/var/tmp') printf '%s\n' /var-tmp ;;
  *FSROOT*'/tmp') printf '%s\n' /tmp ;;
  *) exit 1 ;;
esac
EOF
cat >"${stub_directory}/stat" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'%a %U:%G'*'/var/tmp') printf '%s\n' '1777 root:root' ;;
  *'%a %U:%G'*'/tmp') printf '%s\n' '1777 root:root' ;;
  *'%D:%i'*'/var/tmp') printf '%s\n' '1:11' ;;
  *'%D:%i'*'/tmp') printf '%s\n' '1:10' ;;
  *) exit 1 ;;
esac
EOF
cat >"${stub_directory}/cat" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' complete
EOF
cat >"${stub_directory}/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${VERIFY_ALL_ACTIVE:-0} != 1 && $* == *var-tmp.mount* ]]; then
  exit 3
fi
exit 0
EOF
cat >"${stub_directory}/systemd-tmpfiles" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' \
  'D! /tmp 1777 root root -' \
  'q  /var/tmp 1777 root root 2d'
EOF
chmod 0755 "${stub_directory}"/*

failure_output=${fixture_root}/failure-output
if PATH="${stub_directory}:${PATH}" \
   bash "${script_directory}/custom-fast-temporary-directories-verify" \
     >"${failure_output}" 2>&1; then
  printf 'test-verifier: mixed unit state incorrectly passed\n' >&2
  exit 1
fi
grep -Fq 'FAIL: unit is inactive: var-tmp.mount' "${failure_output}"
grep -Fq 'verify: 1 checks failed' "${failure_output}"

PATH="${stub_directory}:${PATH}" VERIFY_ALL_ACTIVE=1 \
  bash "${script_directory}/custom-fast-temporary-directories-verify" \
  >"${fixture_root}/success-output"
grep -Fq 'verify: all checks passed' "${fixture_root}/success-output"

printf 'test-verifier: known-good and mixed-unit fixtures passed\n'
