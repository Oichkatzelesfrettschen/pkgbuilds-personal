#!/bin/sh
# Arm dynamic netconsole against a target named by hostname.
# The kernel cannot resolve names, so the address is resolved here at start time
# and written to configfs. Keep the DHCP lease for the target reserved.
set -eu

TARGET_HOST="${TARGET_HOST:?set TARGET_HOST in /etc/eirikr-crash-forensics/netconsole.conf}"
TARGET_PORT="${TARGET_PORT:-6666}"
LOCAL_PORT="${LOCAL_PORT:-6665}"
NAME=hangcapture

DEV=$(ip route show default | awk '{print $5; exit}')
SRC=$(ip -4 -br addr show dev "$DEV" | awk '{sub(/\/.*/,"",$3); print $3}')
DST=$(getent ahostsv4 "$TARGET_HOST" | awk '{print $1; exit}')
[ -n "$DST" ] || { echo "cannot resolve $TARGET_HOST" >&2; exit 1; }

# netconsole writes raw frames and never resolves anything, so the hardware
# address has to be in the neighbour table before the target is armed. A ping
# populates it for a host that answers.
ping -c1 -W2 "$DST" >/dev/null 2>&1 ||
	echo "warning: $TARGET_HOST does not answer; the neighbour entry may be missing" >&2
MAC=$(ip neigh show "$DST" dev "$DEV" | awk '{print $5; exit}')
if [ -z "$MAC" ]; then
	# Off-link targets are reached through the gateway's hardware address.
	# An on-link target has no gateway, and passing the empty string to
	# "ip neigh show" is an error rather than an empty result, so the
	# lookup only runs when a gateway exists.
	GW=$(ip route get "$DST" | awk '/ via /{print $3; exit}')
	[ -n "$GW" ] && MAC=$(ip neigh show "$GW" dev "$DEV" | awk '{print $5; exit}')
fi
[ -n "$MAC" ] || {
	echo "no hardware address for $TARGET_HOST ($DST) on $DEV: the target is" >&2
	echo "unreachable, so netconsole cannot arm. Power it on and start the unit." >&2
	exit 1
}

modprobe configfs 2>/dev/null || true
modprobe netconsole 2>/dev/null || true
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

D=/sys/kernel/config/netconsole/$NAME
[ -d "$D" ] && { echo 0 > "$D/enabled" 2>/dev/null || true; rmdir "$D"; }
mkdir "$D"
printf '%s' "$DEV"         > "$D/dev_name"
printf '%s' "$SRC"         > "$D/local_ip"
printf '%s' "$DST"         > "$D/remote_ip"
printf '%s' "$LOCAL_PORT"  > "$D/local_port"
printf '%s' "$TARGET_PORT" > "$D/remote_port"
printf '%s' "$MAC"         > "$D/remote_mac"
printf '1'                 > "$D/enabled"
echo "netconsole armed: $DEV $SRC -> $TARGET_HOST ($DST):$TARGET_PORT via $MAC"
