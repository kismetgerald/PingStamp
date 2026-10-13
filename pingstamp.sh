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
# Usage:    pingstamp.sh [--log FILE] [--hide-drops] [PING_OPTIONS] TARGET
#           pingstamp.sh --help | --version
#
# Apart from the script's own options, every argument is passed to ping
# unchanged, so all of this system's ping options work as usual. On Linux,
# -O is added so lost replies are reported. Exit status is ping's own exit
# status, or 2 for a usage error or a log file that can't be written.

set -u

readonly VERSION="0.0.1"
readonly PROG=${0##*/}

usage() {
    cat <<EOF
Usage: $PROG [--log FILE] [--hide-drops] [PING_OPTIONS] TARGET
       $PROG --help | --version

Run this system's ping command and prefix each reply line with a timestamp in
the format "YYYY-MM-DD HH:MM:SS:MS TZ". Header and summary lines are printed
unchanged.

TARGET is a hostname or IPv4 address. Apart from the options below, all
arguments are passed to ping as-is, so every native ping option works; see
'ping -h' (Linux), 'man ping' (macOS) or 'ping /?' (Windows).

Linux ping prints nothing for a lost reply, so $PROG adds -O there: each
lost reply then shows as a timestamped "no answer yet for icmp_seq=N" line.
Windows and macOS ping report lost replies on their own.

  --log FILE    Also append every line, as shown, to FILE (created if
                needed). Unlike '| tee', this keeps ping's statistics after
                Ctrl+C. May appear anywhere; --log=FILE also works.
  --hide-drops  Don't add -O on Linux. No effect elsewhere.
  --help        Show this help and exit (first argument only).
  --version     Show the version and exit (first argument only).

Examples:
  $PROG google.com                         Ping until Ctrl+C (Linux, macOS)
  $PROG -c 10 192.168.1.10                 Send 10 echo requests
  $PROG --log ping.log 192.168.1.10        Ping until Ctrl+C, keeping a log
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
# a summary that starts after a blank line. Only probe lines get a timestamp.
# Left alone inside the probe section: indented lines, which continue the line
# above (e.g. the route from -R/-r), and a "PING ..." line, which is the real
# header when Linux ping -v prints a line before it. Splitting on the blank
# line instead of matching text keeps this working with localized ping output.
# ---------------------------------------------------------------------------

# True if ping is iputils (Linux) and new enough for -O, which arrived in
# s20121221. Other pings fail "ping -V" or don't mention iputils.
iputils_has_outstanding() {
    local version re='([0-9]{8})'
    version=$(command ping -V 2>&1) || return 1
    [[ $version == *iputils* && $version =~ $re ]] || return 1
    (( 10#${BASH_REMATCH[1]} >= 20121221 ))
}

# Print a line, and append it to the --log file (fd 3) if there is one.
emit() {
    printf '%s\n' "$1"
    if [[ -n $LOG_FILE ]]; then
        printf '%s\n' "$1" >&3
    fi
}

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
                emit "$line"
                ;;
            probes)
                if [[ -z ${line//[[:space:]]/} ]]; then
                    state=summary
                    emit "$line"
                elif [[ $line == [[:space:]]* || $line == 'PING '* ]]; then
                    emit "$line"
                else
                    stamp
                    emit "$STAMP $line"
                fi
                ;;
            summary)
                emit "$line"
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

case ${1:-} in
    --help)    usage; exit 0 ;;
    --version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
esac

# --log and --hide-drops are this script's own options: take them out of
# the arguments, which are otherwise all for ping. They may appear anywhere.
LOG_FILE=""
log_given=false
hide_drops=false
ping_args=()
while (( $# > 0 )); do
    case $1 in
        --hide-drops)
            hide_drops=true
            shift
            ;;
        --log)
            log_given=true
            LOG_FILE=${2:-}
            shift $(( $# > 1 ? 2 : 1 ))
            ;;
        --log=*)
            log_given=true
            LOG_FILE=${1#--log=}
            shift
            ;;
        *)
            ping_args+=("$1")
            shift
            ;;
    esac
done

if [[ $log_given == true && -z $LOG_FILE ]]; then
    printf '%s: --log needs a file name\n' "$PROG" >&2
    exit 2
fi
if (( ${#ping_args[@]} == 0 )); then
    usage >&2
    exit 2
fi

if [[ -n $LOG_FILE ]]; then
    # Open the log once for appending; fail now, before pinging, if that
    # can't be done.
    if ! { exec 3>>"$LOG_FILE"; } 2>/dev/null; then
        printf "%s: cannot write to log file '%s'\n" "$PROG" "$LOG_FILE" >&2
        exit 2
    fi
fi

if ! command -v ping >/dev/null 2>&1; then
    printf '%s: ping command not found\n' "$PROG" >&2
    exit 127
fi

# Linux ping prints nothing for a lost reply, so timestamps couldn't show
# when a drop happened. -O makes it print "no answer yet for icmp_seq=N".
# A second -O, if the user passed one too, is harmless.
if [[ $hide_drops == false ]] && iputils_has_outstanding; then
    ping_args=(-O "${ping_args[@]}")
fi

command ping "${ping_args[@]}" 3>&- | stamp_lines
exit "${PIPESTATUS[0]}"
