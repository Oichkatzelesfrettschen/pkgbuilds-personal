#!/bin/sh
set -eu

# Grant the R610 profiler-device capability to one group, and to nothing else.
#
# NVIDIA restricted GPU performance counters to root because a counter stream
# is a side channel. R610 replaces the all-or-nothing
# NVreg_RestrictProfilingToAdminUsers regkey with a capability the driver
# exposes as a device node: read permission on that node grants profiling to
# the reader and to no other user, and the legacy key stays at its restrictive
# default. This script applies the narrow grant so that Nsight Compute collects
# counters as an ordinary user while nothing runs as root.
#
# The minor is resolved from /proc/driver/nvidia-caps/sys-minors on every run
# rather than written here. The name profiler-device is the stable identity;
# the number behind it belongs to the driver and moves when the driver decides
# it does.
#
# profiler-device already subsumes profiler-context. trace-device is a separate
# capability for hardware tracing and is deliberately left ungranted, because
# CUPTI tracing already works without it and an unused grant is a widened
# attack surface for nothing.
#
# Every step is verified after it is applied and any mismatch ends the run
# non-zero, since a silent partial grant reads at the next profiling attempt as
# a driver fault rather than as a configuration one.

capability_name=profiler-device
capability_group=${NVIDIA_PROFILER_GROUP:-nvidia-profiler}
sys_minors=/proc/driver/nvidia-caps/sys-minors
capability_proc=/proc/driver/nvidia/capabilities/$capability_name
wait_deadline_seconds=${NVIDIA_PROFILER_WAIT_SECONDS:-30}

fail() {
    printf 'nvidia-profiler-device-setup: %s\n' "$1" >&2
    exit 1
}

# The unit orders itself after the module loads, and the capability tree
# appears as the driver initializes rather than at module insertion, so the
# wait covers the interval between them and ends rather than spinning.
waited=0
while [ ! -r "$sys_minors" ]; do
    [ "$waited" -lt "$wait_deadline_seconds" ] ||
        fail "$sys_minors stayed absent for ${wait_deadline_seconds}s"
    sleep 1
    waited=$((waited + 1))
done

getent group "$capability_group" >/dev/null 2>&1 ||
    fail "group $capability_group is absent"

minor=$(awk -v want="$capability_name" '$1 == want { print $2 }' "$sys_minors")
case $minor in
    '' ) fail "$capability_name is absent from $sys_minors" ;;
    *[!0-9]* ) fail "$capability_name resolved to a non-numeric minor: $minor" ;;
esac

# nvidia-modprobe creates the device node for a capability the driver exposes.
# It is idempotent, and it is what makes the node exist on a boot where no
# CUDA process has run yet.
[ -r "$capability_proc" ] || fail "$capability_proc is unreadable"
nvidia-modprobe -f "$capability_proc" ||
    fail "nvidia-modprobe refused to create the node for $capability_name"

node=/dev/nvidia-caps/nvidia-cap$minor
[ -c "$node" ] || fail "$node is absent after nvidia-modprobe"

setfacl -m "g:$capability_group:r" "$node" ||
    fail "setfacl refused to grant $capability_group read on $node"

# DeviceFileModify: 0 stops a later NVIDIA user-space tool from recreating the
# node, which would restore its default mode and discard the ACL applied above.
printf 'DeviceFileModify: 0\n' >"$capability_proc" ||
    fail "writing DeviceFileModify to $capability_proc failed"

# Read every applied fact back rather than trusting the writes, and print what
# was verified so the journal carries the grant that is actually in force.
getfacl -p "$node" 2>/dev/null | grep -q "^group:$capability_group:r--$" ||
    fail "the ACL on $node does not grant $capability_group read"
grep -q 'DeviceFileModify: 0' "$capability_proc" ||
    fail "$capability_proc does not report DeviceFileModify: 0"

printf 'capability=%s minor=%s node=%s group=%s device_file_modify=0 granted\n' \
    "$capability_name" "$minor" "$node" "$capability_group"
