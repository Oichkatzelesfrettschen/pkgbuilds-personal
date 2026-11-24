#!/bin/sh
# Block-scheduler A/B with fio on file-backed test data (direct I/O, no raw
# device writes). Each target runs REPS repetitions; the scheduler order
# alternates per repetition (forward, then reversed) so thermal and cache drift
# cancel instead of favoring the last scheduler. Original schedulers return on
# exit. Usage: sudo sh fio-sched-ab.sh OUTDIR
set -eu

OUT=${1:?usage: fio-sched-ab.sh OUTDIR}
SIZE=${SIZE:-2G}
RUNTIME=${RUNTIME:-12}
RAMP=${RAMP:-2}
REPS=${REPS:-3}
SETTLE=${SETTLE:-3}

[ "$(id -u)" -eq 0 ] || { echo "root required (scheduler writes)" >&2; exit 1; }
mkdir -p "$OUT"

current_sched() {
    sed -n 's/.*\[\(.*\)\].*/\1/p' "/sys/block/$1/queue/scheduler"
}

: >"$OUT/schedulers.orig"
for d in nvme0n1 nvme1n1 sda; do
    printf '%s %s\n' "$d" "$(current_sched "$d")" >>"$OUT/schedulers.orig"
done

datafiles=
cleanup() {
    while read -r d s; do
        printf '%s' "$s" >"/sys/block/$d/queue/scheduler" 2>/dev/null || true
    done <"$OUT/schedulers.orig"
    for f in $datafiles; do
        rm -f -- "$f"
    done
}
trap cleanup EXIT INT TERM

set_sched() {
    printf '%s' "$2" >"/sys/block/$1/queue/scheduler"
    [ "$(current_sched "$1")" = "$2" ] || { echo "could not set $2 on $1" >&2; exit 1; }
}

rev_words() {
    out=
    for w in $1; do out="$w $out"; done
    printf '%s' "$out"
}

{
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "kernel: $(uname -r)"
    fio --version
    echo "size=$SIZE runtime=$RUNTIME ramp=$RAMP reps=$REPS"
    echo "--- originals"
    cat "$OUT/schedulers.orig"
} >"$OUT/env.txt"

run_target() { # name device dir "schedulers" numjobs iodepth
    name=$1 dev=$2 dir=$3 scheds=$4 nj=$5 qd=$6
    mkdir -p "$dir"
    f=$dir/fio-ab.dat
    datafiles="$datafiles $f"
    echo "[$(date +%T)] $name: prefill $SIZE"
    fio --name=prefill --filename="$f" --size="$SIZE" --rw=write --bs=1M \
        --direct=1 --ioengine=io_uring --iodepth=4 --output="$OUT/$name.prefill.txt" >/dev/null
    r=1
    while [ "$r" -le "$REPS" ]; do
        if [ $((r % 2)) -eq 1 ]; then order=$scheds; else order=$(rev_words "$scheds"); fi
        for s in $order; do
            set_sched "$dev" "$s"
            for wl in rr4k_qd1 rr4k_hi sr128k mix4k rw4k_hi; do
                case $wl in
                    rr4k_qd1) a="--rw=randread --bs=4k --iodepth=1 --numjobs=1" ;;
                    rr4k_hi) a="--rw=randread --bs=4k --iodepth=$qd --numjobs=$nj" ;;
                    sr128k) a="--rw=read --bs=128k --iodepth=8 --numjobs=1" ;;
                    mix4k) a="--rw=randrw --rwmixread=70 --bs=4k --iodepth=$qd --numjobs=$nj" ;;
                    rw4k_hi) a="--rw=randwrite --bs=4k --iodepth=$qd --numjobs=$nj" ;;
                esac
                echo "[$(date +%T)] $name rep=$r sched=$s wl=$wl"
                # shellcheck disable=SC2086
                fio --name="$wl" --filename="$f" --size="$SIZE" --direct=1 \
                    --ioengine=io_uring --time_based --runtime="$RUNTIME" \
                    --ramp_time="$RAMP" --group_reporting --randseed=1 \
                    --percentile_list=50:99:99.9 --output-format=json \
                    --output="$OUT/$name.$s.r$r.$wl.json" $a
                sleep "$SETTLE"
            done
        done
        r=$((r + 1))
    done
}

# ONLY="sda nvme0n1" restricts the run to the named targets.
want() {
    [ -z "${ONLY:-}" ] && return 0
    case " $ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
if want nvme0n1; then run_target nvme0n1 nvme0n1 /tmp/fio-ab "kyber none adios" 4 32; fi
if want nvme1n1; then run_target nvme1n1 nvme1n1 /srv/scratch/fio-ab "kyber none adios" 4 32; fi
if want sda; then run_target sda sda /srv/data/fio-ab "mq-deadline none kyber bfq adios" 2 16; fi
echo "[$(date +%T)] done"
