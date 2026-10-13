#!/usr/bin/env bash
#
# pingstamp.sh - Run the system ping command and prefix each reply line with a
#                "YYYY-MM-DD HH:MM:SS:MS TZ" timestamp.
#
# Version:  0.0.1
# Project:  https://github.com/kismetgerald/PingStamp
# License:  MIT (see LICENSE.txt)
#
# Self-contained: needs only bash 3.2+ and ping. Works with Linux (iputils),
# macOS/BSD ping, and Windows ping.exe under Git Bash, MSYS2 or Cygwin.
#
# Usage:    pingstamp.sh [PING_OPTIONS] TARGET
#           pingstamp.sh --help | --version
#
# Every argument is passed to ping unchanged, so all of this system's ping
# options work as usual. Exit status is ping's own exit status.

set -u

readonly VERSION="0.0.1"
readonly PROG=${0##*/}

usage() {
    cat <<EOF
Usage: $PROG [PING_OPTIONS] TARGET
       $PROG --help | --version

Run this system's ping command and prefix each reply line with a timestamp in
the format "YYYY-MM-DD HH:MM:SS:MS TZ". Header and summary lines are printed
unchanged.

TARGET is a hostname or IPv4 address. All arguments are passed to ping as-is,
so every native ping option works; see 'ping -h' (Linux), 'man ping' (macOS)
or 'ping /?' (Windows).

  --help      Show this help and exit.
  --version   Show the version and exit.

Examples:
  $PROG google.com                         Ping until Ctrl+C (Linux, macOS)
  $PROG -c 10 192.168.1.10                 Send 10 echo requests
  $PROG -c 5 -i 0.2 -s 1400 192.168.1.10   Any other native options
  $PROG -n 10 192.168.1.10                 Windows ping under Git Bash
EOF
}

# ---------------------------------------------------------------------------
# Timestamps
#
# STAMP is set rather than echoed so the bash 5 path stays fork-free.
# Milliseconds are truncated, not rounded.
# ---------------------------------------------------------------------------

if (( BASH_VERSINFO[0] >= 5 )) && [[ -n ${EPOCHREALTIME:-} ]]; then
    # bash 5+: builtin clock and strftime, no external processes.
    stamp() {
        local now=$EPOCHREALTIME secs frac
        secs=${now%[.,]*}       # the decimal separator follows the locale
        frac=${now#*[.,]}
        printf -v STAMP '%(%Y-%m-%d %H:%M:%S)T:%s %(%Z)T' \
            "$secs" "${frac:0:3}" "$secs"
    }
elif [[ $(date +%3N 2>/dev/null) =~ ^[0-9]{3}$ ]]; then
    # GNU date (older bash, e.g. RHEL 7/8).
    stamp() { STAMP=$(date '+%Y-%m-%d %H:%M:%S:%3N %Z'); }
elif command -v perl >/dev/null 2>&1; then
    # BSD/macOS date has no sub-second field; perl ships with macOS.
    stamp() {
        STAMP=$(perl -MPOSIX=strftime -MTime::HiRes=time -e \
            '$t = time; printf "%s:%03d %s", strftime("%Y-%m-%d %H:%M:%S", localtime $t), ($t - int $t) * 1000, strftime("%Z", localtime $t)')
    }
else
    # Last resort: whole seconds only.
    stamp() { STAMP=$(date '+%Y-%m-%d %H:%M:%S:000 %Z'); }
fi

# ---------------------------------------------------------------------------
# Output filter
#
# Native ping output has three parts: a header line, one line per probe, and
# a summary that starts after a blank line. Only probe lines get a timestamp;
# indented lines inside the probe section continue the line above (e.g. the
# route from -R/-r) and are left alone. Splitting on the blank line instead
# of matching text keeps this working with localized ping output.
# ---------------------------------------------------------------------------

stamp_lines() {
    # Ctrl+C goes to ping and to us. Ping answers it by printing its
    # statistics; ignoring it here keeps us alive to pass them through.
    # This runs in the pipeline's subshell, so ping keeps its own handler.
    trap '' INT

    local line state=header
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}      # Windows ping.exe ends lines with CRLF
        case $state in
            header)
                [[ -n ${line//[[:space:]]/} ]] && state=probes
                printf '%s\n' "$line"
                ;;
            probes)
                if [[ -z ${line//[[:space:]]/} ]]; then
                    state=summary
                    printf '%s\n' "$line"
                elif [[ $line == [[:space:]]* ]]; then
                    printf '%s\n' "$line"
                else
                    stamp
                    printf '%s %s\n' "$STAMP" "$line"
                fi
                ;;
            summary)
                printf '%s\n' "$line"
                # Windows ping -t prints interim statistics on Ctrl+Break,
                # then carries on pinging.
                [[ $line == Control-Break* ]] && state=probes
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if (( $# == 0 )); then
    usage >&2
    exit 2
fi
case $1 in
    --help)    usage; exit 0 ;;
    --version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
esac

if ! command -v ping >/dev/null 2>&1; then
    printf '%s: ping command not found\n' "$PROG" >&2
    exit 127
fi

command ping "$@" | stamp_lines
exit "${PIPESTATUS[0]}"
