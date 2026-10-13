# PingStamp

Run the system `ping` command with a timestamp on every reply line.

PingStamp is two small, self-contained scripts, one for PowerShell and one for
Bash. Each wraps the operating system's own `ping` and prefixes each reply with
the date, time to the millisecond, and time zone. Everything else is native
`ping`: the same switches, the same output, the same exit code.

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

## Scripts

| Script | Runs on | Requires |
| --- | --- | --- |
| `Invoke-PingStamp.ps1` | Windows; Linux and macOS with PowerShell 7 | Windows PowerShell 5.1 or PowerShell 7+ |
| `pingstamp.sh` | Linux, macOS, Git Bash / MSYS2 / Cygwin on Windows | bash 3.2+ |

Each script is a single file with no dependencies. Copy it wherever you need it.

## Installation

Download the script you need from the
[Releases page](https://github.com/kismetgerald/PingStamp/releases), or clone
the repository:

```bash
git clone https://github.com/kismetgerald/PingStamp.git
```

**Windows:** files downloaded from the internet may be blocked by the execution
policy. Unblock the script once:

```powershell
Unblock-File .\Invoke-PingStamp.ps1
```

**Linux / macOS:** make the script executable:

```bash
chmod +x pingstamp.sh
```

## Usage

Both scripts take exactly the same arguments as the native `ping` on that
system, in any order. The target is a hostname or IPv4 address.

### PowerShell

```powershell
.\Invoke-PingStamp.ps1 192.168.1.10                       # 4 echo requests (Windows default)
.\Invoke-PingStamp.ps1 -t server01.example.com            # until Ctrl+C
.\Invoke-PingStamp.ps1 -n 100 192.168.1.10                # 100 echo requests
.\Invoke-PingStamp.ps1 192.168.1.10 -n 3 -l 1472 -f       # MTU test with Don't Fragment
.\Invoke-PingStamp.ps1 -n 100 192.168.1.10 | Tee-Object -FilePath .\ping.log
```

On Linux or macOS with PowerShell 7, use that system's switches:

```powershell
./Invoke-PingStamp.ps1 -c 5 -i 0.2 192.168.1.10
```

Script options:

| Option | Description |
| --- | --- |
| `-?` | Show help (or `Get-Help .\Invoke-PingStamp.ps1 -Full`) |
| `-Version` | Show the script version (use it on its own) |

### Bash

```bash
./pingstamp.sh google.com                        # until Ctrl+C (Linux, macOS)
./pingstamp.sh -c 10 192.168.1.10                # 10 echo requests
./pingstamp.sh -c 5 -i 0.2 -s 1400 192.168.1.10  # any native options
./pingstamp.sh 192.168.1.10 -c 100 | tee ping.log
```

Script options (use them on their own):

| Option | Description |
| --- | --- |
| `--help` | Show help |
| `--version` | Show the script version |

Native `ping` help is still available: `ping -h` (Linux), `man ping` (macOS),
`ping /?` (Windows).

## How it works

- **Which lines are stamped.** `ping` output has three parts: a header line, a
  line per echo request, and a summary after a blank line. Only the
  per-request lines get a timestamp. Indented continuation lines, such as the
  route printed by `-r` or `-R`, are left alone. Because the scripts split the
  output at the blank line rather than matching English text, they also work
  with localized `ping` output.
- **Timestamp format.** `YYYY-MM-DD HH:MM:SS:MS TZ`, local time. Milliseconds
  are truncated, not rounded.
- **Time zone abbreviation.** Linux and macOS supply it directly. Windows only
  has long names such as "Eastern Daylight Time", so the PowerShell script
  abbreviates them (EDT), with a built-in table for zones whose initials would
  be wrong (for example CET/CEST, GMT/BST, AEST/AEDT, JST).
- **Ctrl+C.** Stopping a continuous ping still shows ping's statistics in both
  scripts. In PowerShell, these final lines go to the console rather than the
  pipeline, because PowerShell has already stopped the pipeline by then.
- **Exit code.** Each script exits with `ping`'s own exit code, so it works in
  scripts and monitoring checks just like `ping`. Running a script with no
  arguments exits with code 2.

## Notes

- **IPv4 vs IPv6.** As with `ping` itself, a hostname may resolve to an IPv6
  address (`localhost` usually does on Windows). Add `-4` to force IPv4.
- **Constrained Language Mode.** On systems where AppLocker or WDAC puts
  PowerShell in Constrained Language Mode, `Invoke-PingStamp.ps1` falls back
  to a plain pipeline. The output is the same, but Ctrl+C discards ping's
  closing statistics. Signing the script or allowing it in policy restores
  full behavior.
- **PowerShell argument parsing.** PowerShell parses arguments before the
  script sees them. Quote values that must keep their exact text, such as a
  `ping -p` padding pattern with leading zeros: `-p '0101'`.
- **Git Bash.** Use dash-style switches (`-n 4`), not slash-style (`/n 4`).
  MSYS treats arguments that start with `/` as paths and rewrites them.

## Tested on

- Windows 11: Windows PowerShell 5.1, PowerShell 7.6, Git Bash (bash 5.3)
- Debian 13 (WSL): bash 5.2, iputils ping 20240905
- bash timestamp fallbacks for older bash and macOS (GNU `date`, `perl`),
  exercised on Debian

Windows Ctrl+C behavior is checked with
[`tests/ctrlc_harness.py`](tests/ctrlc_harness.py), which sends a real
console Ctrl+C to the script.

## Versioning

PingStamp follows [Semantic Versioning](https://semver.org/). Every version is
tagged `vMAJOR.MINOR.PATCH`, and changes are listed in
[CHANGELOG.md](CHANGELOG.md).

| Versions | Stage | Published on GitHub as |
| --- | --- | --- |
| `v0.0.x` | Development | Pre-release |
| `v0.1.0` up to `v1.0.0` | Beta, starting at `v0.1.0` | Pre-release |
| `v1.0.0` and later | Stable, starting at `v1.0.0` | Release |

To publish a version, update it in each of these places, then commit and tag:

- `Invoke-PingStamp.ps1`: `.VERSION` in the `PSScriptInfo` block
- `pingstamp.sh`: the `Version:` header line and `VERSION=`
- `CHANGELOG.md`: a new section, plus the compare links at the bottom

## License

[MIT](LICENSE.txt) © 2026 Kismet Agbasi
