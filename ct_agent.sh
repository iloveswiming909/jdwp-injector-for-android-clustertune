#!/system/bin/sh
# ============================================================
# ClusterTune system agent (runs as uid=system inside GameAssistant)
#
# SECURITY MODEL (read before editing):
#  - This runs as system (uid 1000). It must therefore be paranoid.
#  - It reads a request file that a normal app can write. It must treat
#    that input as fully untrusted.
#  - It NEVER evals, NEVER executes anything from the request file, and
#    NEVER writes to any path derived from the request file.
#  - It only ever writes integer values (validated against a fixed
#    allow-list of real frequency bins) to three FIXED sysfs paths.
#  - Worst case for an attacker who can write the request file: pick one
#    of the allowed CPU frequency caps. No path traversal, no code exec.
# ============================================================

# ---- Fixed paths (never derived from input) ----
REQ="/sdcard/ClusterTune/ct_profile"      # app writes here (KEY=VALUE lines)
STATUS="/sdcard/ClusterTune/ct_status"    # agent writes status here
P0="/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq"
P3="/sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq"
P7="/sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq"

# ---- Allow-lists: the ONLY values we will ever write, per cluster ----
# (exact bins from scaling_available_frequencies on this device)
BINS0=" 307200 441600 556800 672000 787200 902400 1017600 1113600 1228800 1344000 1459200 1555200 1670400 1785600 1900800 2016000 "
BINS3=" 499200 614400 729600 844800 940800 1056000 1171200 1286400 1401600 1536000 1651200 1785600 1920000 2054400 2188800 2323200 2457600 2592000 2707200 "
BINS7=" 595200 729600 864000 998400 1132800 1248000 1363200 1478400 1593600 1708800 1843200 1977600 2092800 2227200 2342400 2476800 2592000 2726400 2841600 2956800 "

APPLY_INTERVAL=3      # seconds between re-applies (handles idle resets)
AGENT_TAG="CT_AGENT"

log() { log -t "$AGENT_TAG" "$1" 2>/dev/null; }

# is_valid_bin <value> <bins-string>  -> 0 if value is exactly one listed bin
is_valid_bin() {
    v="$1"; list="$2"
    # value must be all digits (no signs, no spaces, no path chars)
    case "$v" in
        ''|*[!0-9]*) return 1 ;;
    esac
    # must appear as a whole token in the allow-list
    case "$list" in
        *" $v "*) return 0 ;;
        *) return 1 ;;
    esac
}

# write_freq <path> <value>  -> only ever called with a validated value
write_freq() {
    echo "$2" > "$1" 2>/dev/null
}

# parse one KEY=VALUE line safely; echoes "policy value" if valid, else nothing
read_val() {
    key="$1"
    # grab last matching line, take text after '='; strip spaces
    line=$(grep "^${key}=" "$REQ" 2>/dev/null | tail -n 1)
    [ -z "$line" ] && return 1
    val=${line#*=}
    # trim whitespace/CR
    val=$(printf '%s' "$val" | tr -d ' \t\r\n')
    printf '%s' "$val"
}

apply_once() {
    applied=""
    v0=$(read_val P0); if is_valid_bin "$v0" "$BINS0"; then write_freq "$P0" "$v0"; applied="$applied P0=$v0"; fi
    v3=$(read_val P3); if is_valid_bin "$v3" "$BINS3"; then write_freq "$P3" "$v3"; applied="$applied P3=$v3"; fi
    v7=$(read_val P7); if is_valid_bin "$v7" "$BINS7"; then write_freq "$P7" "$v7"; applied="$applied P7=$v7"; fi
    echo "$applied"
}

# ---- single-instance guard: don't stack agents ----
LOCK="/sdcard/ClusterTune/ct_agent.lock"
mkdir -p /sdcard/ClusterTune 2>/dev/null
if [ -f "$LOCK" ]; then
    # if a lock exists and is fresh (<10s), assume another agent is alive
    now=$(date +%s 2>/dev/null || echo 0)
    then_=$(cat "$LOCK" 2>/dev/null || echo 0)
    case "$then_" in ''|*[!0-9]*) then_=0 ;; esac
    if [ $((now - then_)) -lt 10 ]; then
        log "another agent appears alive; exiting"
        exit 0
    fi
fi

log "agent starting (uid=$(id -u))"
echo "agent_started $(id -u) $(date +%s 2>/dev/null)" > "$STATUS" 2>/dev/null

# ---- main loop ----
# Runs a bounded number of iterations then exits, so a stale agent never
# lives forever. ClusterTune's per-boot setup re-injects if needed.
# 20000 iters * 3s ~= 16h, plenty for a session; re-inject after reboot.
i=0
while [ $i -lt 20000 ]; do
    # refresh liveness lock (epoch seconds)
    date +%s > "$LOCK" 2>/dev/null || echo 0 > "$LOCK" 2>/dev/null

    if [ -f "$REQ" ]; then
        result=$(apply_once)
        if [ -n "$result" ]; then
            echo "ok$result $(date +%s 2>/dev/null)" > "$STATUS" 2>/dev/null
        else
            echo "reject (no valid P0/P3/P7 in request) $(date +%s 2>/dev/null)" > "$STATUS" 2>/dev/null
        fi
    else
        echo "idle (no request file) $(date +%s 2>/dev/null)" > "$STATUS" 2>/dev/null
    fi

    i=$((i + 1))
    sleep "$APPLY_INTERVAL"
done

log "agent exiting after max iterations"
rm -f "$LOCK" 2>/dev/null
exit 0
