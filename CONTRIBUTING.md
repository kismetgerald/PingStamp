# Contributing to PingStamp

This guide is for anyone changing PingStamp. It covers how the scripts work,
the rules they follow, how to test them, and how a version is published. For
using the scripts, see the [README](README.md).

The repository is public. Never put real hostnames, IP addresses or
organization names in code, tests, examples or commit messages. Use
placeholders such as `server01.example.com` and `192.168.1.10`.

## Repository layout

| Path | Contents |
| --- | --- |
| `Invoke-PingStamp.ps1` | The PowerShell script |
| `pingstamp.sh` | The Bash script |
| `tests/test-pingstamp.sh` | Bash tests: Linux, macOS, Git Bash on Windows |
| `tests/Test-InvokePingStamp.ps1` | PowerShell tests: Windows, Linux, macOS |
| `tests/ctrlc_harness.py` | Sends a real console Ctrl+C on Windows (used by both test scripts) |
| `.github/workflows/ci.yml` | Runs the tests and linters on every push |
| `CHANGELOG.md` | Changes per version ([Keep a Changelog](https://keepachangelog.com/)) |
| `TODO.md` | Planned work |

## Design rules

- **Monolithic and self-contained.** Each script is one file with no
  dependencies: no modules, no dot-sourcing, no helper files.
- **Native passthrough.** Every argument goes to `ping` unchanged and in
  order. Where options may go relative to the target is up to the native
  `ping`: Windows and Linux accept either side, macOS needs them first.
- **The scripts' own options must never clash with a native `ping` switch**
  on any platform. They are `-LogFile`, `-Utc`, `-HideDrops`, `-?` and
  `-Version` (PowerShell), and `--log`, `--utc`, `--hide-drops`, `--help`
  and `--version` (Bash). The log, UTC and hide-drops options are taken out
  of the arguments wherever they appear; everything else goes to `ping`.
- **The one addition to `ping`'s arguments** is `-O` on Linux, so lost
  replies get a line (see [Lost replies on Linux](#lost-replies-on-linux)).
- **PowerShell: no `param()` block and no `[CmdletBinding()]`.** Declared
  parameters, and the common parameters that `[CmdletBinding()]` adds
  (`-Verbose`, `-WarningAction`, ...), would capture native switches such as
  `-t`, `-v`, `-w` and `-i`. Arguments come from `$args`.
- **Compatibility.** The PowerShell script must run on Windows PowerShell 5.1
  (.NET Framework) and in Constrained Language Mode. The Bash script must run
  on bash 3.2, the system bash on macOS: no `${var,,}`, associative arrays or
  `mapfile`. Newer features, such as bash 5's `EPOCHREALTIME`, are
  feature-detected.
- **ASCII only** in both scripts. Line endings are fixed by `.gitattributes`:
  LF for `.sh`, CRLF for `.ps1`.

## How the scripts work

### Which lines get a timestamp

`ping` output has three sections: a header line, one line per echo request,
and a summary that starts after the first blank line. Only lines in the
middle section get a timestamp, with two exceptions that are left alone:

- indented lines, which continue the line above (such as the route printed by
  `-r` or `-R`);
- a line starting with `PING `, which is the real header when Linux
  `ping -v` prints an extra line before it.

The sections are found by position and blank lines, not by matching English
text, because `ping`'s output is localized. After Windows `ping -t` prints
interim statistics on Ctrl+Break, a `Control-Break` line switches back to the
middle section.

### Timestamps

Format: `YYYY-MM-DD HH:MM:SS:MS TZ`, local time, milliseconds truncated.
With `--utc` / `-Utc`, the time is UTC and the zone is `UTC`: Bash exports
`TZ=UTC0` (the POSIX form, which needs no time zone database and is honored by
`printf`, `date` and `perl` alike), and PowerShell uses `[datetime]::UtcNow`.

- **Bash** uses `EPOCHREALTIME` and `printf '%(...)T'` on bash 5 (no external
  processes). It falls back to GNU `date +%3N` on older bash, then to `perl`
  (BSD `date` on macOS has no milliseconds), then to whole seconds.
- **PowerShell** formats `[datetime]::Now` with the invariant culture, because
  `:` in a format string means "the culture's time separator". Windows only
  has long time zone names, so they are abbreviated to their initials, with a
  table for zones where that would be wrong (CET/CEST, GMT/BST, AEST/AEDT,
  JST and others). On Linux and macOS, `date +%Z` supplies the real
  abbreviation.

### Lost replies on Linux

Windows and macOS `ping` print a line for every lost reply. Linux (iputils)
`ping` prints nothing unless given `-O`, so both scripts add `-O` when `ping -V`
reports iputils s20121221 or later. `--hide-drops` / `-HideDrops` turns this
off. A second `-O`, if the user passed one too, is harmless.

### Logging

`--log` / `-LogFile` appends each line, exactly as written to the screen. The
file is opened (or, in PowerShell, test-appended) before `ping` starts, so a
bad path fails with exit code 2 straight away. In PowerShell, every output
path must also write to the log: the normal loop, the Ctrl+C drain in the
`finally` block, and the Constrained Language Mode fallback.

### Ctrl+C

Ctrl+C reaches both `ping` and the script. `ping` responds by printing its
statistics and exiting; the script's job is to stay alive long enough to pass
them on.

- **Bash.** The filter runs in the pipeline's subshell with `trap '' INT`, so
  it ignores Ctrl+C and passes the statistics through. `ping`, on the other
  side of the pipe, keeps its own handler.
- **PowerShell.** `& ping | ForEach-Object` would lose the statistics, because
  PowerShell stops the pipeline at once. Instead the script starts `ping` with
  `System.Diagnostics.Process` and reads its output itself. After Ctrl+C, the
  `finally` block reads the rest and writes it with `$Host.UI.WriteLine`. It
  can't use `Write-Output`: after Ctrl+C, that silently ends the `finally`
  block. Two details matter here:
  - On the blank line that ends the replies (the first thing `ping` prints
    after Ctrl+C), the script pauses 100 ms. PowerShell's own Ctrl+C
    handling lags slightly behind, and the pause makes its stop land before
    the line is written rather than part-way through. Without it, the blank
    line is sometimes doubled or lost.
  - The `finally` block passes the remaining output on only after a real
    Ctrl+C. A downstream stop such as `| Select-Object -First 5` must not
    print anything more. On Windows, Ctrl+C is recognized by `ping`'s exit
    code `0xC000013A` (STATUS_CONTROL_C_EXIT). On Linux and macOS, `ping`
    exiting within 500 ms is taken to mean it got Ctrl+C (SIGINT); after a
    downstream stop, it is still running and gets killed.
- **Constrained Language Mode** blocks `System.Diagnostics.Process`, so the
  PowerShell script falls back to `& ping | ForEach-Object` there, and Ctrl+C
  loses the statistics.

## Testing

Every push to `main` runs the tests on GitHub Actions:

| Script | Tested with |
| --- | --- |
| `Invoke-PingStamp.ps1` | Windows PowerShell 5.1; PowerShell 7 on Windows, Ubuntu and macOS |
| `pingstamp.sh` | bash 5 on Ubuntu; `/bin/bash` 3.2 on macOS (the only bash on macOS runners); Git Bash on Windows |

CI also runs ShellCheck and PSScriptAnalyzer, and both must be clean.

The tests ping `127.0.0.1`, plus `192.0.2.1` (an address reserved for
documentation, which never answers) for lost replies. Every change to a
script gets a test. Run them locally before pushing:

```bash
bash tests/test-pingstamp.sh
```

```powershell
pwsh -File tests/Test-InvokePingStamp.ps1
powershell -ExecutionPolicy Bypass -File tests\Test-InvokePingStamp.ps1
```

Set `BASH_UNDER_TEST=/path/to/bash` to run `pingstamp.sh` with a different
bash. On Windows, the Ctrl+C tests need Python.

Things the tests rely on, which are easy to break:

- **Ctrl+C on Linux and macOS.** The script under test must not start with
  SIGINT ignored, which is what a plain `&` job gets in a non-interactive
  shell. The tests turn on job control (`set -m`) and send SIGINT to the
  whole process group, as a terminal does. A control run with the filter's
  `trap '' INT` removed must lose the statistics; otherwise the test proves
  nothing.
- **Ctrl+C on Windows** (PowerShell and Git Bash) needs a real console
  event. `tests/ctrlc_harness.py` starts the script in a hidden console and
  raises `CTRL_C_EVENT` there. Expected output: the replies, exactly one
  blank line, then the full statistics ending in `Control-C`.
- **Git Bash's own window (mintty)** can't be driven from a test. Check
  Ctrl+C there by hand after changing how Ctrl+C is handled.
- **The PowerShell tests count an unexpected error as a failure**, through a
  script-level `trap`. Without it, a broken test would be skipped silently.

## Publishing a version

PingStamp follows [Semantic Versioning](https://semver.org/), and every version
gets an annotated `vMAJOR.MINOR.PATCH` tag.

| Versions | Stage | Published on GitHub as |
| --- | --- | --- |
| `v0.0.x` | Development | Pre-release (`gh release create --prerelease`) |
| `v0.1.0` up to `v1.0.0` | Beta, starting at `v0.1.0` | Pre-release |
| `v1.0.0` and later | Stable | Release |

To publish:

1. Update the version in all three places: `.VERSION` in the `PSScriptInfo`
   block of `Invoke-PingStamp.ps1`, and both the `# Version:` line and
   `VERSION=` in `pingstamp.sh`.
2. In `CHANGELOG.md`, turn `[Unreleased]` into a section for the new version,
   and update the compare links at the bottom.
3. Commit, create the annotated tag, and push both.
4. Create the GitHub release (a pre-release before v1.0.0) and attach both
   scripts.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`,
`fix:`, `docs:`, `test:`, `ci:`, `chore:`.
