#!/usr/bin/env bash
#
# Smoke tests for pingstamp.sh on Linux, macOS, and Windows (Git Bash, MSYS2
# or Cygwin with Windows ping). Pings 127.0.0.1, and 192.0.2.1 for lost
# replies.
#
# Usage:  bash tests/test-pingstamp.sh
#
# Set BASH_UNDER_TEST to run pingstamp.sh with a different bash, e.g.
# BASH_UNDER_TEST=/bin/bash on macOS to test bash 3.2. On Windows the Ctrl+C
# tests need Python (tests/ctrlc_harness.py). Exits 1 if any test fails.

set -u

cd "$(dirname "$0")/.." || exit 1
SCRIPT=./pingstamp.sh
SHELL_UNDER_TEST=${BASH_UNDER_TEST:-bash}
STAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{3} [A-Za-z0-9+-]+ '
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0

# 192.0.2.1 (TEST-NET-1) is reserved for documentation and never answers.
case $(uname -s) in
    Linux)
        OS=linux; COUNT=-c; SIZE=-s; DROPS=(-c 3 -W 1 192.0.2.1) ;;
    Darwin)
        OS=macos; COUNT=-c; SIZE=-s; DROPS=(-c 3 -W 1 192.0.2.1) ;;
    MINGW*|MSYS*|CYGWIN*)
        case $(command -v ping | tr '[:upper:]' '[:lower:]') in
            */system32/*) ;;
            *) echo "SKIP: ping here is not Windows ping"; exit 0 ;;
        esac
        OS=windows; COUNT=-n; SIZE=-l; DROPS=(-n 2 -w 500 192.0.2.1) ;;
    *)
        echo "SKIP: no tests for $(uname -s)"; exit 0 ;;
esac

check() {   # check NAME COMMAND...: pass if COMMAND succeeds
    local name=$1
    shift
    if "$@"; then
        printf 'ok   %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        failures=$((failures + 1))
    fi
}

stamped_count() { grep -cE "$STAMP_RE" "$1"; }

# Smallest gap in milliseconds between consecutive stamped lines.
min_gap_ms() {
    grep -E "$STAMP_RE" "$1" | awk '{
        split($2, t, ":")
        ms = ((t[1] * 60 + t[2]) * 60 + t[3]) * 1000 + t[4]
        if (NR > 1) { gap = ms - prev; if (gap < 0) gap += 86400000
                      if (min == "" || gap < min) min = gap }
        prev = ms
    } END { print (min == "" ? 0 : min) }'
}

# Seconds since midnight for HH:MM:SS (anything after the seconds is ignored).
seconds_of_day() { printf '%s\n' "$1" | awk -F: '{ print ($1 * 60 + $2) * 60 + $3 }'; }

# True if two HH:MM:SS times are at most two minutes apart (across midnight too).
within_two_minutes() {
    local a b diff
    a=$(seconds_of_day "$1")
    b=$(seconds_of_day "$2")
    diff=$(( a > b ? a - b : b - a ))
    (( diff <= 120 || diff >= 86400 - 120 ))
}

# True if the statistics follow exactly one blank line after a stamped reply.
blank_before_statistics() {
    local line prev1="" prev2=""
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%$'\r'}
        case $line in
            *[Pp]ing\ statistics*)
                [ -z "$prev1" ] && printf '%s\n' "$prev2" | grep -qE "$STAMP_RE"
                return
                ;;
        esac
        prev2=$prev1
        prev1=$line
    done < "$1"
    return 1
}

# Ctrl+C a continuous ping of 127.0.0.1 after about 3 seconds.
ctrl_c_run() {   # ctrl_c_run SCRIPT OUTFILE [EXTRA_ARGUMENTS...]
    local script=$1 out=$2
    shift 2
    if [ "$OS" = windows ]; then
        # Windows ping needs a real console Ctrl+C.
        "$PYTHON" -I tests/ctrlc_harness.py 3.5 "$SHELL_WIN_PATH" "$script" "$@" -t 127.0.0.1 \
            > "$out" 2>&1
        return 0
    fi
    # Job control gives the script its own process group with SIGINT at its
    # default (a plain "&" job would start with SIGINT ignored); then Ctrl+C
    # goes to the whole group, as a terminal sends it.
    set -m
    "$SHELL_UNDER_TEST" "$script" "$@" 127.0.0.1 > "$out" 2>&1 &
    local pid=$!
    set +m
    sleep 3
    kill -INT -- -"$pid"
    wait "$pid"
}

# shellcheck disable=SC2016  # $BASH_VERSION is for the bash under test to expand
echo "pingstamp.sh tests on $OS, running it with: $("$SHELL_UNDER_TEST" -c 'echo "bash $BASH_VERSION"')"

# --- Version and usage --------------------------------------------------------

version=$(sed -n 's/^readonly VERSION="\(.*\)"$/\1/p' "$SCRIPT")
check "--version prints $version" \
    test "$("$SHELL_UNDER_TEST" "$SCRIPT" --version)" = "pingstamp.sh $version"
check "header Version: line matches VERSION" \
    test "$(sed -n 's/^# Version: *//p' "$SCRIPT")" = "$version"

"$SHELL_UNDER_TEST" "$SCRIPT" > /dev/null 2> "$TMP/usage"
check "no arguments exits 2" test $? -eq 2
check "no arguments prints usage to stderr" grep -q '^Usage:' "$TMP/usage"

# --- A short run --------------------------------------------------------------

"$SHELL_UNDER_TEST" "$SCRIPT" "$COUNT" 3 127.0.0.1 > "$TMP/run" 2>&1
check "$COUNT 3 exits 0" test $? -eq 0
check "3 reply lines are stamped" test "$(stamped_count "$TMP/run")" -eq 3
check "header line is not stamped" grep -qiE '^ping' "$TMP/run"
check "statistics are shown and not stamped" \
    test "$(grep -ci 'ping statistics' "$TMP/run")" -eq 1 -a \
         "$(grep -E "$STAMP_RE" "$TMP/run" | grep -ci 'statistics')" -eq 0
gap=$(min_gap_ms "$TMP/run")
check "lines are stamped as they arrive (smallest gap ${gap} ms >= 500)" test "$gap" -ge 500

# --- Native ping behavior -----------------------------------------------------

ping "$COUNT" 1 no-such-host.invalid > /dev/null 2>&1
native_rc=$?
"$SHELL_UNDER_TEST" "$SCRIPT" "$COUNT" 1 no-such-host.invalid > /dev/null 2>&1
check "exit code matches ping's for an unknown host ($native_rc)" test $? -eq "$native_rc"
check "ping's exit code for an unknown host is non-zero" test "$native_rc" -ne 0

"$SHELL_UNDER_TEST" "$SCRIPT" "$COUNT" 2 "$SIZE" 100 127.0.0.1 > "$TMP/opts" 2>&1
check "native options pass through ($SIZE 100)" grep -qiE '^ping.*100' "$TMP/opts"
check "native options pass through ($COUNT 2)" test "$(stamped_count "$TMP/opts")" -eq 2

if [ "$OS" != macos ]; then
    # Linux and Windows ping accept options after the target; macOS's doesn't.
    "$SHELL_UNDER_TEST" "$SCRIPT" 127.0.0.1 "$COUNT" 2 > "$TMP/order" 2>&1
    check "options after the target" test "$(stamped_count "$TMP/order")" -eq 2
fi

if [ "$OS" != windows ]; then
    # Linux ping -v prints a line before the "PING ..." header.
    "$SHELL_UNDER_TEST" "$SCRIPT" -c 1 -v 127.0.0.1 > "$TMP/verbose" 2> /dev/null
    check "-v: only the reply is stamped" test "$(stamped_count "$TMP/verbose")" -eq 1
    check "-v: the PING header is not stamped" grep -q '^PING ' "$TMP/verbose"
fi

# --- Lost replies -------------------------------------------------------------

"$SHELL_UNDER_TEST" "$SCRIPT" "${DROPS[@]}" > "$TMP/drops" 2>&1
check "lost replies get stamped lines" test "$(stamped_count "$TMP/drops")" -ge 1

if [ "$OS" = linux ]; then
    check "Linux: lost replies show as 'no answer yet' (-O added)" \
        grep -qE "${STAMP_RE}no answer yet" "$TMP/drops"
    "$SHELL_UNDER_TEST" "$SCRIPT" --hide-drops "${DROPS[@]}" > "$TMP/hidden" 2>&1
    check "Linux: --hide-drops leaves -O out" test "$(grep -c 'no answer yet' "$TMP/hidden")" -eq 0
    "$SHELL_UNDER_TEST" "$SCRIPT" -O "${DROPS[@]}" > "$TMP/both" 2>&1
    check "Linux: -O given by the user as well still works" \
        grep -qE "${STAMP_RE}no answer yet" "$TMP/both"
fi

"$SHELL_UNDER_TEST" "$SCRIPT" --hide-drops "$COUNT" 1 127.0.0.1 > "$TMP/hide-ok" 2>&1
check "--hide-drops is accepted" test $? -eq 0
check "--hide-drops is not passed to ping" test "$(stamped_count "$TMP/hide-ok")" -eq 1

# --- --utc --------------------------------------------------------------------

# A TZ other than UTC shows that --utc overrides it.
TZ=Asia/Tokyo "$SHELL_UNDER_TEST" "$SCRIPT" --utc "$COUNT" 1 127.0.0.1 > "$TMP/utc" 2>&1
utc_now=$(date -u '+%H:%M:%S')
utc_line=$(grep -E "$STAMP_RE" "$TMP/utc" | head -n 1)
check "--utc is not passed to ping (1 stamped line)" test "$(stamped_count "$TMP/utc")" -eq 1
check "--utc: the zone is UTC" test "$(printf '%s\n' "$utc_line" | awk '{ print $3 }')" = UTC
check "--utc: the time is UTC (within 2 minutes of date -u)" \
    within_two_minutes "$(printf '%s\n' "$utc_line" | awk '{ print $2 }')" "$utc_now"

# --- --log --------------------------------------------------------------------

log=$TMP/ping.log
"$SHELL_UNDER_TEST" "$SCRIPT" --log "$log" "$COUNT" 2 127.0.0.1 > "$TMP/logrun" 2>&1
check "--log: exits 0" test $? -eq 0
check "--log: the log matches the screen" cmp -s "$log" "$TMP/logrun"
check "--log: the log has 2 stamped lines" test "$(stamped_count "$log")" -eq 2

"$SHELL_UNDER_TEST" "$SCRIPT" "$COUNT" 1 127.0.0.1 "--log=$log" > /dev/null 2>&1
check "--log=FILE after the target appends (now 3 stamped lines)" \
    test "$(stamped_count "$log")" -eq 3

"$SHELL_UNDER_TEST" "$SCRIPT" "$COUNT" 1 127.0.0.1 --log > /dev/null 2>&1
check "--log without a file name exits 2" test $? -eq 2

"$SHELL_UNDER_TEST" "$SCRIPT" --log "$TMP/no-such-dir/ping.log" "$COUNT" 1 127.0.0.1 \
    > "$TMP/badlog" 2>&1
check "--log to an unwritable path exits 2" test $? -eq 2
check "--log to an unwritable path does not ping" test "$(stamped_count "$TMP/badlog")" -eq 0

# --- Ctrl+C -------------------------------------------------------------------

if [ "$OS" = windows ]; then
    PYTHON=$(command -v python || command -v py || true)
    SHELL_WIN_PATH=$(cygpath -w "$(command -v "$SHELL_UNDER_TEST")")
fi

if [ "$OS" = windows ] && [ -z "$PYTHON" ]; then
    echo "skip Ctrl+C: Python not found (needed for tests/ctrlc_harness.py)"
else
    ctrl_c_run "$SCRIPT" "$TMP/ctrlc" --log "$TMP/ctrlc.log"
    rc=$?
    if [ "$OS" != windows ]; then
        # Under Git Bash, Windows ping's Ctrl+C exit makes bash exit with 130.
        check "Ctrl+C: exits 0" test "$rc" -eq 0
    fi
    check "Ctrl+C: statistics are shown, one blank line after the replies" \
        blank_before_statistics "$TMP/ctrlc"
    check "Ctrl+C: replies before it are stamped" test "$(stamped_count "$TMP/ctrlc")" -ge 2
    check "Ctrl+C with --log: the log has the statistics too" \
        blank_before_statistics "$TMP/ctrlc.log"
    if [ "$OS" = windows ]; then
        check "Ctrl+C with --log: the log ends with Control-C" \
            test "$(tail -n 1 "$TMP/ctrlc.log")" = "Control-C"
    else
        check "Ctrl+C with --log: the log matches the screen" cmp -s "$TMP/ctrlc.log" "$TMP/ctrlc"
    fi

    # Control: without the filter's "trap '' INT" the statistics must be
    # lost. If they are not, the tests above prove nothing.
    sed "s/^    trap '' INT\$/    : no trap/" "$SCRIPT" > "$TMP/notrap.sh"
    check "control: no-trap copy was made" grep -q '^    : no trap$' "$TMP/notrap.sh"
    ctrl_c_run "$TMP/notrap.sh" "$TMP/ctrlc-control"
    check "control: without the trap, Ctrl+C loses the statistics" \
        test "$(grep -ci 'ping statistics' "$TMP/ctrlc-control")" -eq 0
fi

# ------------------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
    echo "$failures test(s) failed"
    exit 1
fi
echo "All tests passed"
