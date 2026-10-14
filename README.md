# PingStamp

[![CI](https://github.com/kismetgerald/PingStamp/actions/workflows/ci.yml/badge.svg)](https://github.com/kismetgerald/PingStamp/actions/workflows/ci.yml)

Run `ping` with a timestamp on every reply.

PingStamp is a pair of small, self-contained scripts, one for PowerShell and
one for Bash. Each runs your system's own `ping` and puts the date, time (to
the millisecond) and time zone in front of every reply, so you can see exactly
when replies slowed down or stopped. Everything else is plain `ping`: the same
switches, the same output, the same exit code.

**Windows** (`Invoke-PingStamp.ps1`)

```text
Pinging server01.example.com [192.168.1.10] with 32 bytes of data:
2026-10-13 05:35:40:020 EDT Reply from 192.168.1.10: bytes=32 time=3ms TTL=127
2026-10-13 05:35:41:020 EDT Reply from 192.168.1.10: bytes=32 time=4ms TTL=127
2026-10-13 05:35:42:020 EDT Reply from 192.168.1.10: bytes=32 time=7ms TTL=127
2026-10-13 05:35:43:020 EDT Reply from 192.168.1.10: bytes=32 time=3ms TTL=127

Ping statistics for 192.168.1.10:
    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),
Approximate round trip times in milli-seconds:
    Minimum = 3ms, Maximum = 7ms, Average = 4ms
```

**Linux** (`pingstamp.sh`)

```text
PING google.com (192.178.155.101) 56(84) bytes of data.
2026-10-13 05:35:40:020 EDT 64 bytes from yuiadrs-in-f101.1e100.net (192.178.155.101): icmp_seq=1 ttl=108 time=9.05 ms
2026-10-13 05:35:41:020 EDT 64 bytes from yuiadrs-in-f101.1e100.net (192.178.155.101): icmp_seq=2 ttl=108 time=9.10 ms
2026-10-13 05:35:42:020 EDT 64 bytes from yuiadrs-in-f101.1e100.net (192.178.155.101): icmp_seq=3 ttl=108 time=9.07 ms
2026-10-13 05:35:43:020 EDT 64 bytes from yuiadrs-in-f101.1e100.net (192.178.155.101): icmp_seq=4 ttl=108 time=9.60 ms
2026-10-13 05:35:44:020 EDT 64 bytes from yuiadrs-in-f101.1e100.net (192.178.155.101): icmp_seq=5 ttl=108 time=9.42 ms
^C
--- google.com ping statistics ---
5 packets transmitted, 5 received, 0% packet loss, time 4005ms
rtt min/avg/max/mdev = 9.057/9.255/9.608/0.221 ms
```

## Requirements

| Script | Runs on | Needs |
| --- | --- | --- |
| `Invoke-PingStamp.ps1` | Windows; Linux and macOS with PowerShell 7 | Windows PowerShell 5.1 or PowerShell 7+ |
| `pingstamp.sh` | Linux and macOS; Windows with Git Bash, MSYS2 or Cygwin | bash 3.2+ |

Each script is a single file with no dependencies.

## Installation

Download the script you need from the
[Releases page](https://github.com/kismetgerald/PingStamp/releases), or clone
the repository:

```bash
git clone https://github.com/kismetgerald/PingStamp.git
```

**Windows:** a script downloaded from the internet may be blocked by the
execution policy. Unblock it once:

```powershell
Unblock-File .\Invoke-PingStamp.ps1
```

**Linux and macOS:** make the script executable:

```bash
chmod +x pingstamp.sh
```

## Usage

Give the script the same arguments you would give `ping`. The target is a
hostname or IPv4 address. Windows and Linux `ping` accept options before or
after the target; macOS `ping` needs them first. For `ping`'s own options, run
`ping /?` (Windows), `ping -h` (Linux) or `man ping` (macOS).

### PowerShell

```powershell
.\Invoke-PingStamp.ps1 192.168.1.10                         # 4 echo requests (Windows default)
.\Invoke-PingStamp.ps1 -t server01.example.com              # until Ctrl+C
.\Invoke-PingStamp.ps1 -n 100 192.168.1.10                  # 100 echo requests
.\Invoke-PingStamp.ps1 192.168.1.10 -n 3 -l 1472 -f         # MTU test with Don't Fragment
.\Invoke-PingStamp.ps1 -t 192.168.1.10 -LogFile .\ping.log  # until Ctrl+C, keeping a log
```

On Linux or macOS with PowerShell 7, use that system's `ping` switches:

```powershell
./Invoke-PingStamp.ps1 -c 5 -i 0.2 192.168.1.10
```

The script's own options:

| Option | Description |
| --- | --- |
| `-LogFile <path>` | Also append every line to a log file (see [Keeping a log](#keeping-a-log)). `-LogFile:<path>` also works |
| `-Utc` | Timestamps in UTC instead of local time |
| `-HideDrops` | On Linux, don't report lost replies (see [Lost replies](#lost-replies)). No effect elsewhere |
| `-?` | Show help. `Get-Help .\Invoke-PingStamp.ps1 -Full` shows all of it |
| `-Version` | Show the script version (use it on its own) |

### Bash

```bash
./pingstamp.sh google.com                        # until Ctrl+C (Linux, macOS)
./pingstamp.sh -c 10 192.168.1.10                # 10 echo requests
./pingstamp.sh -c 5 -i 0.2 -s 1400 192.168.1.10  # any other ping options
./pingstamp.sh --log ping.log 192.168.1.10       # until Ctrl+C, keeping a log
```

The script's own options:

| Option | Description |
| --- | --- |
| `--log FILE` | Also append every line to a log file (see [Keeping a log](#keeping-a-log)). `--log=FILE` also works |
| `--utc` | Timestamps in UTC instead of local time |
| `--hide-drops` | On Linux, don't report lost replies (see [Lost replies](#lost-replies)). No effect elsewhere |
| `--help` | Show help (first argument only) |
| `--version` | Show the script version (first argument only) |

These options can go anywhere in the arguments. Everything else is passed to
`ping` unchanged.

### Keeping a log

Use `--log` / `-LogFile` rather than `tee`, `Tee-Object` or `>`. The log gets
every line exactly as shown, as it happens, including ping's statistics after
Ctrl+C. With the other methods those statistics are lost: in Bash, Ctrl+C
stops `tee` too, and in PowerShell they go to the console instead.

The log is appended to, never overwritten, and created if it doesn't exist. If
it can't be written, the script stops with exit code 2 before pinging.

### Lost replies

Timestamps are most useful for seeing *when* replies were lost, so every lost
reply should produce a line.

- **Windows** and **macOS** `ping` already print one (`Request timed out.`,
  `Request timeout for icmp_seq 4`), and it gets a timestamp like any reply.
- **Linux** `ping` prints nothing for a lost reply; you would only notice a
  gap in the `icmp_seq` numbers. So on Linux, PingStamp adds `ping`'s `-O`
  option, and each lost reply shows up as a timestamped line:

  ```text
  2026-10-13 17:01:48:916 EDT no answer yet for icmp_seq=1
  ```

  Use `--hide-drops` / `-HideDrops` to turn this off. The last request of a
  `-c` run is not reported this way, because `ping` exits right after sending
  it; it shows only in the statistics.

## Good to know

- **What gets a timestamp.** Every reply line, and every "request timed out"
  line. The header and the closing statistics are printed unchanged, as are
  indented continuation lines such as the route printed by `-r`. Non-English
  `ping` output works too.
- **Timestamps** are local time in the format `YYYY-MM-DD HH:MM:SS:MS TZ`,
  or UTC with `--utc` / `-Utc` (handy for matching logs from different time
  zones). Milliseconds are truncated, not rounded. Windows only has long time
  zone names, so the PowerShell script abbreviates them (Eastern Daylight
  Time becomes EDT).
- **Ctrl+C** stops a continuous ping and still shows ping's statistics.
- **Exit code.** Each script exits with `ping`'s own exit code, so it works in
  other scripts and monitoring checks just like `ping`. A usage error exits
  with code 2.
- **IPv4 vs IPv6.** As with `ping` itself, a hostname may resolve to an IPv6
  address (on Windows, `localhost` usually does). Add `-4` to force IPv4.
- **Locked-down PowerShell.** Where AppLocker or WDAC puts PowerShell in
  Constrained Language Mode, `Invoke-PingStamp.ps1` still works, but Ctrl+C
  then loses ping's statistics. Signing the script, or allowing it in the
  policy, restores full behavior.
- **PowerShell argument parsing.** PowerShell reads arguments before the script
  sees them. Quote values that must keep their exact text, such as a `ping -p`
  padding pattern with leading zeros: `-p '0101'`.
- **Git Bash** runs Windows `ping`, so use Windows switches (`-n`, `-t`, `-l`)
  in dash style: `-n 4`, not `/n 4`, because Git Bash rewrites arguments that
  start with `/` as file paths. After Ctrl+C, the exit code is 130 (the usual
  code for a command stopped by Ctrl+C) rather than ping's own.

## Versions

PingStamp follows [Semantic Versioning](https://semver.org/). Versions before
v1.0.0 are published as pre-releases: v0.0.x are development versions, and
v0.1.0 starts the beta. [CHANGELOG.md](CHANGELOG.md) lists what changed in
each version.

## Contributing

To work on PingStamp, see [CONTRIBUTING.md](CONTRIBUTING.md). It covers how the
scripts work, the design rules, testing, and publishing a version.

## License

[MIT](LICENSE.txt) © 2026 Kismet Agbasi
