#!/bin/sh
#
# A stand-in for ping, for testing outage lines: lost replies can't be
# produced on demand with a real network. The tests copy this file to a
# directory named first in PATH, under the name "ping".
#
# FAKE_PING_SCENARIO picks the output; lines are 0.2 s apart. Arguments are
# ignored, except that "ping -V" claims to be iputils (so -O gets added).

if [ "${1:-}" = -V ]; then
    echo "ping from iputils 20240905"
    exit 0
fi

say() {
    sleep 0.2
    printf '%s\n' "$1"
}

case ${FAKE_PING_SCENARIO:-recovery} in
    recovery)
        # Linux style: one reply, three lost, replies again.
        say "PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data."
        say "64 bytes from 192.0.2.1: icmp_seq=1 ttl=64 time=0.104 ms"
        say "no answer yet for icmp_seq=2"
        say "no answer yet for icmp_seq=3"
        say "no answer yet for icmp_seq=4"
        say "64 bytes from 192.0.2.1: icmp_seq=5 ttl=64 time=0.098 ms"
        say "64 bytes from 192.0.2.1: icmp_seq=6 ttl=64 time=0.101 ms"
        say ""
        say "--- 192.0.2.1 ping statistics ---"
        say "6 packets transmitted, 3 received, 50% packet loss, time 1004ms"
        ;;
    ongoing)
        # Replies stop and never come back before the statistics.
        say "PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data."
        say "64 bytes from 192.0.2.1: icmp_seq=1 ttl=64 time=0.104 ms"
        say "no answer yet for icmp_seq=2"
        say "no answer yet for icmp_seq=3"
        say ""
        say "--- 192.0.2.1 ping statistics ---"
        say "3 packets transmitted, 1 received, 66.6667% packet loss, time 402ms"
        ;;
    windows)
        # Windows style, down at the start. "Reply from ...: Destination host
        # unreachable." is a lost reply even though it says "Reply".
        say ""
        say "Pinging 192.0.2.1 with 32 bytes of data:"
        say "Request timed out."
        say "Reply from 192.0.2.254: Destination host unreachable."
        say "Reply from 192.0.2.1: bytes=32 time=3ms TTL=127"
        say ""
        say "Ping statistics for 192.0.2.1:"
        say "    Packets: Sent = 3, Received = 2, Lost = 1 (33% loss),"
        ;;
    unreadable)
        # German Windows pinging IPv6: replies have neither "time" nor "TTL",
        # so none can be recognized, and no outage may be reported.
        say ""
        say "Ping wird ausgefuehrt fuer ::1 mit 32 Bytes Daten:"
        say "Antwort von ::1: Zeit<1ms"
        say "Zeitueberschreitung der Anforderung."
        say "Antwort von ::1: Zeit<1ms"
        say ""
        say "Ping-Statistik fuer ::1:"
        ;;
esac
