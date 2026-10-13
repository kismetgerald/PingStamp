# PingStamp

Two scripts that run the native `ping` and prefix each reply line with a
`YYYY-MM-DD HH:MM:SS:MS TZ` timestamp. Public repo:
https://github.com/kismetgerald/PingStamp (MIT).

- `Invoke-PingStamp.ps1`: Windows PowerShell 5.1 and PowerShell 7+
- `pingstamp.sh`: bash 3.2+ (Linux, macOS, Git Bash/MSYS2/Cygwin)

## Rules

- **Monolithic and self-contained.** Each script is one file with no
  dependencies. No modules, no dot-sourcing, no helper files.
- **Native passthrough.** Every argument goes to `ping` unchanged and in
  order. Where options may go relative to the target is up to the native
  `ping`: Windows and Linux accept either side, macOS needs them first.
  Don't add options that could clash with a native switch on any platform. The scripts' own options are `-?` and `-Version` (PowerShell), and
  `--help` and `--version` (Bash).
- **PowerShell: no `param()` block, no `[CmdletBinding()]`.** Declared and
  common parameters would capture native switches (`-t`, `-v`, `-w`, `-i`).
  Arguments come from `$args`.
- **Compatibility.** PowerShell must run on 5.1 (.NET Framework) and in
  Constrained Language Mode (the fallback pipeline). Bash must parse on 3.2
  (macOS): no `${var,,}`, associative arrays, or `mapfile`. Newer features
  are feature-detected.
- **ASCII only** in both scripts. Line endings are fixed by `.gitattributes`
  (`.sh` LF, `.ps1` CRLF).
- **No internal identifiers.** The repo is public. Use `server01.example.com`
  and `192.168.1.10` in examples, never real hostnames or IPs.

## Output and Ctrl+C

- Stamp only per-probe lines: header, then probes, then a summary that starts
  at the first blank line. Indented lines in the probe section are
  continuations and stay unstamped, as does a `PING ...` line (the real
  header when Linux `ping -v` prints a line before it). Otherwise, don't
  match English text; `ping` output is localized.
- Bash: the filter runs in the pipeline's subshell with `trap '' INT`, so
  `ping` prints its statistics on Ctrl+C and the filter survives to pass
  them through.
- PowerShell: `ping` runs via `System.Diagnostics.Process`, not
  `& ping | ForEach-Object`, which drops the statistics on Ctrl+C. Keep:
  - the `finally` drain, written with `$Host.UI.WriteLine`. `Write-Output`
    silently ends a `finally` block after Ctrl+C.
  - the 100 ms `Start-Sleep` on the probe-to-summary blank line, which makes
    PowerShell's stop land before the write. Without it, the blank line is
    sometimes doubled or lost.
  - Ctrl+C detection by ping's exit code `0xC000013A` (-1073741510). This
    tells it apart from a downstream stop such as `Select-Object -First`,
    which must not drain.

## Testing

CI (`.github/workflows/ci.yml`) runs the tests on every push to `main`.
PowerShell runs on Windows 5.1 and on PowerShell 7 under Windows, Ubuntu and
macOS. Bash runs on Ubuntu, macOS, and macOS `/bin/bash` 3.2. CI also runs
ShellCheck and PSScriptAnalyzer. Every change to a script gets a test.

Run the tests locally before pushing:

- `bash tests/test-pingstamp.sh` in WSL (`wsl -d Debian`). Set
  `BASH_UNDER_TEST=/path/to/bash` to test another bash.
- `pwsh -File tests/Test-InvokePingStamp.ps1`, and again with
  `powershell -ExecutionPolicy Bypass -File tests\Test-InvokePingStamp.ps1`.

Things the tests rely on, which are easy to break:

- **Ctrl+C on Linux/macOS:** the script must not start with SIGINT ignored,
  as a plain `&` job does in a non-interactive shell. The tests use `set -m`
  (job control) and `kill -INT -- -PID` on the process group. A control run
  with the filter's `trap '' INT` removed must lose the statistics, or the
  test proves nothing.
- **Ctrl+C on Windows** needs a real console event, so
  `tests/ctrlc_harness.py` (Python) starts the script in a hidden console and
  raises `CTRL_C_EVENT` there. The expected output is the replies, exactly one
  blank line, then the full statistics ending in `Control-C`.
- **The PowerShell tests count an unexpected error as a failure** (a script
  `trap`). Without it, a broken test is skipped silently.

## Versioning and releases

SemVer, with every version tagged `vMAJOR.MINOR.PATCH`.

- `v0.0.x` is development and `v0.1.0` is the first beta. Anything below
  `v1.0.0` is a GitHub **pre-release** (`gh release create --prerelease`).
- `v1.0.0` is the first stable release, published as a normal release.

To publish, bump the version in all four places: `.VERSION` in the
`PSScriptInfo` block, `# Version:` and `VERSION=` in `pingstamp.sh`, and a
new `CHANGELOG.md` section (Keep a Changelog) with its compare links. Then
commit, tag (annotated), push, and attach both scripts to the GitHub
release.

Commit messages use Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`).
