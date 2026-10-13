# Changelog

All notable changes to PingStamp are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Log file option: `--log FILE` (bash) and `-LogFile <path>` (PowerShell).
  Every line is appended to the log as shown, including ping's statistics
  after Ctrl+C, which `tee` and `Tee-Object` lose. The option may appear
  anywhere in the arguments. An unwritable log stops the script with exit
  code 2 before pinging.
- Lost replies are visible on Linux. iputils `ping` prints nothing for a
  lost reply, so both scripts now add `-O` there, and each lost reply shows
  as a timestamped `no answer yet for icmp_seq=N` line. Turn it off with
  `--hide-drops` (bash) or `-HideDrops` (PowerShell). Windows and macOS
  `ping` already report lost replies.

### Changed

- The README now covers using the scripts only. How they work, testing and
  publishing moved to the new CONTRIBUTING.md.

### Fixed

- PowerShell 7 on Linux and macOS: the script failed at the first reply. A
  variable named `$date` clashed with the `$Date` parameter, because
  PowerShell variable names ignore case.
- PowerShell: an internal error no longer ends the script with exit code 0.
- With Linux `ping -v`, the `PING ...` header line no longer gets a
  timestamp. `-v` prints an extra line first, which was taken for the
  header.
- Docs: options may follow the target only where the native `ping` allows
  it (Windows, Linux), not on macOS.

## [0.0.1] - 2026-10-13

### Added

- `Invoke-PingStamp.ps1` for Windows PowerShell 5.1 and PowerShell 7+.
- `pingstamp.sh` for bash 3.2+ on Linux, macOS, and Git Bash/MSYS2/Cygwin.
- Reply lines are prefixed with a `YYYY-MM-DD HH:MM:SS:MS TZ` timestamp;
  header and summary lines are left unchanged.
- All native ping switches are passed through unchanged, in any order.
- Ping's statistics are still shown when a continuous ping is stopped with
  Ctrl+C.
- PowerShell: falls back to a plain pipeline under Constrained Language Mode.
- Version display: `-Version` (PowerShell) and `--version` (bash).

[Unreleased]: https://github.com/kismetgerald/PingStamp/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/kismetgerald/PingStamp/releases/tag/v0.0.1
