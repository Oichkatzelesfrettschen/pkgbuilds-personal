#!/bin/sh
# Archive the pstore records kdumpst leaves behind, then release their buffers.
#
# save-dumps.sh collects a record only when its name contains "dmesg-ramoops",
# so console-ramoops and pmsg-ramoops records are never copied out and never
# unlinked. systemd-pstore would collect them, but it is ordered
# Before=sysinit.target while ramoops is loaded by kdumpst-init.service at
# basic.target, so its ConditionDirectoryNotEmpty fails and it exits before the
# records exist. Nothing else archives them, so this does.
#
# Unlinking a record frees the kernel's copy of the previous boot's buffer and
# zaps the zone, so the next boot's archive holds that boot alone.
set -eu

pstore=/sys/fs/pstore
dest=/var/crash/eirikr-crash-forensics
stamp=$(date -u +%Y%m%dT%H%M%SZ)
found=0

for record in "$pstore"/console-ramoops-* "$pstore"/pmsg-ramoops-*; do
    [ -f "$record" ] || continue
    name=${record##*/}
    mkdir -p "$dest"
    cat "$record" > "$dest/$name.$stamp"
    sync "$dest/$name.$stamp"
    rm -f "$record"
    found=$((found + 1))
done

if [ "$found" -gt 0 ]; then
    logger -t eirikr-crash-forensics \
        "archived $found pstore record(s) from the previous boot to $dest"
fi
exit 0
