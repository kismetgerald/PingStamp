#!/usr/bin/env bash
#
# Smoke tests for pingstamp.sh on Linux and macOS. Pings 127.0.0.1 only.
#
# Usage:  bash tests/test-pingstamp.sh
#
# Set BASH_UNDER_TEST to run pingstamp.sh with a different bash, e.g.
# BASH_UNDER_TEST=/bin/bash on macOS to test bash 3.2. Exits 1 if any test
# fails.

set -u

cd "$(dirname "$0")/.." || exit 1
SCRIPT=./pingstamp.sh
SHELL_UNDER_TEST=${BASH_UNDER_TEST:-bash}
STAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{3} [A-Za-z0-9+-]+ '
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0

case $(uname -s) in
    Linux)  OS=linux ;;
    Darwin) OS=macos ;;
    *)      echo "SKIP: these tests need Linux or macOS ping (found $(uname -s))"; exit 0 ;;
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

# Run a script with job control on, so it gets its own process group with
# SIGINT at its default (a plain "&" job would start with SIGINT ignored),
# then send Ctrl+C to the whole group as a terminal would.
ctrl_c_run() {   # ctrl_c_run SCRIPT OUTFILE [EXTRA_ARGUMENTS...]
    local script=$1 out=$2
    shift 2
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

"$SHELL_UNDER_TEST" "$SCRIPT" -c 3 127.0.0.1 > "$TMP/run" 2>&1
check "-c 3 exits 0" test $? -eq 0
check "3 reply lines are stamped" test "$(stamped_count "$TMP/run")" -eq 3
check "header line is not stamped" grep -q '^PING ' "$TMP/run"
check "summary lines are not stamped" grep -qE '^[0-9]+ packets transmitted' "$TMP/run"
gap=$(min_gap_ms "$TMP/run")
check "lines are stamped as they arrive (smallest gap ${gap} ms >= 500)" test "$gap" -ge 500

# --- Native ping behavior -----------------------------------------------------

ping -c 1 no-such-host.invalid > /dev/null 2>&1
native_rc=$?
"$SHELL_UNDER_TEST" "$SCRIPT" -c 1 no-such-host.invalid > /dev/null 2>&1
check "exit code matches ping's for an unknown host ($native_rc)" test $? -eq "$native_rc"
check "ping's exit code for an unknown host is non-zero" test "$native_rc" -ne 0

"$SHELL_UNDER_TEST" "$SCRIPT" -c 2 -s 100 127.0.0.1 > "$TMP/opts" 2>&1
check "native options pass through (-s 100)" grep -q '^PING .*100' "$TMP/opts"
check "native options pass through (-c 2)" test "$(stamped_count "$TMP/opts")" -eq 2

# Linux ping -v prints a line before the "PING ..." header.
"$SHELL_UNDER_TEST" "$SCRIPT" -c 1 -v 127.0.0.1 > "$TMP/verbose" 2> /dev/null
check "-v: only the reply is stamped" test "$(stamped_count "$TMP/verbose")" -eq 1
check "-v: the PING header is not stamped" grep -q '^PING ' "$TMP/verbose"

if [ "$OS" = linux ]; then
    # Linux ping also accepts options after the target; macOS ping does not.
    "$SHELL_UNDER_TEST" "$SCRIPT" 127.0.0.1 -c 2 > "$TMP/order" 2>&1
    check "options after the target (Linux)" test "$(stamped_count "$TMP/order")" -eq 2
fi

# --- Lost replies -------------------------------------------------------------
# 192.0.2.1 (TEST-NET-1) is reserved for documentation and never answers.

"$SHELL_UNDER_TEST" "$SCRIPT" -c 3 -W 1 192.0.2.1 > "$TMP/drops" 2>&1
check "lost replies get stamped lines" test "$(stamped_count "$TMP/drops")" -ge 1

if [ "$OS" = linux ]; then
    check "Linux: lost replies show as 'no answer yet' (-O added)" \
        grep -qE "${STAMP_RE}no answer yet" "$TMP/drops"
    "$SHELL_UNDER_TEST" "$SCRIPT" --hide-drops -c 3 -W 1 192.0.2.1 > "$TMP/hidden" 2>&1
    check "Linux: --hide-drops leaves -O out" test "$(grep -c 'no answer yet' "$TMP/hidden")" -eq 0
    "$SHELL_UNDER_TEST" "$SCRIPT" -O -c 3 -W 1 192.0.2.1 > "$TMP/both" 2>&1
    check "Linux: -O given by the user as well still works" \
        grep -qE "${STAMP_RE}no answer yet" "$TMP/both"
fi

"$SHELL_UNDER_TEST" "$SCRIPT" --hide-drops -c 1 127.0.0.1 > "$TMP/hide-ok" 2>&1
check "--hide-drops is accepted" test $? -eq 0
check "--hide-drops is not passed to ping" test "$(stamped_count "$TMP/hide-ok")" -eq 1

# --- --log --------------------------------------------------------------------

log=$TMP/ping.log
"$SHELL_UNDER_TEST" "$SCRIPT" --log "$log" -c 2 127.0.0.1 > "$TMP/logrun" 2>&1
check "--log: exits 0" test $? -eq 0
check "--log: the log matches the screen" cmp -s "$log" "$TMP/logrun"
check "--log: the log has 2 stamped lines" test "$(stamped_count "$log")" -eq 2

"$SHELL_UNDER_TEST" "$SCRIPT" -c 1 127.0.0.1 "--log=$log" > /dev/null 2>&1
check "--log=FILE after the target appends (now 3 stamped lines)" \
    test "$(stamped_count "$log")" -eq 3

"$SHELL_UNDER_TEST" "$SCRIPT" -c 1 127.0.0.1 --log > /dev/null 2>&1
check "--log without a file name exits 2" test $? -eq 2

"$SHELL_UNDER_TEST" "$SCRIPT" --log "$TMP/no-such-dir/ping.log" -c 1 127.0.0.1 \
    > "$TMP/badlog" 2>&1
check "--log to an unwritable path exits 2" test $? -eq 2
check "--log to an unwritable path does not ping" test "$(stamped_count "$TMP/badlog")" -eq 0

# --- Ctrl+C -------------------------------------------------------------------

ctrl_c_run "$SCRIPT" "$TMP/ctrlc" --log "$TMP/ctrlc.log"
check "Ctrl+C: exits 0" test $? -eq 0
check "Ctrl+C: statistics are shown" grep -q 'ping statistics' "$TMP/ctrlc"
check "Ctrl+C: replies before it are stamped" test "$(stamped_count "$TMP/ctrlc")" -ge 2
check "Ctrl+C with --log: the log matches the screen, statistics included" \
    cmp -s "$TMP/ctrlc.log" "$TMP/ctrlc"

# Control: without the filter's "trap '' INT" the statistics must be lost.
# If they are not, the test above proves nothing.
sed "s/^    trap '' INT\$/    : no trap/" "$SCRIPT" > "$TMP/notrap.sh"
check "control: no-trap copy was made" grep -q '^    : no trap$' "$TMP/notrap.sh"
ctrl_c_run "$TMP/notrap.sh" "$TMP/ctrlc-control"
check "control: without the trap, Ctrl+C loses the statistics" \
    test "$(grep -c 'ping statistics' "$TMP/ctrlc-control")" -eq 0

# ------------------------------------------------------------------------------

if [ "$failures" -gt 0 ]; then
    echo "$failures test(s) failed"
    exit 1
fi
echo "All tests passed"
