# PingStamp

Two scripts that run the native `ping` and prefix each reply line with a
`YYYY-MM-DD HH:MM:SS:MS TZ` timestamp. Public repo:
https://github.com/kismetgerald/PingStamp (MIT).

- `Invoke-PingStamp.ps1`: Windows PowerShell 5.1 and PowerShell 7+
- `pingstamp.sh`: bash 3.2+ (Linux, macOS, Git Bash/MSYS2/Cygwin)

## Rules

- **Monolithic and self-contained.** Each script is one file with no
  dependencies. No modules, no dot-sourcing, no helper files.
- **Native passthrough.** Every argument goes to `ping` unchanged, in any
  order. Don't add options that could clash with a native switch on any
  platform. The scripts' own options are `-?` and `-Version` (PowerShell), and
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
  continuations and stay unstamped. Don't match English text; `ping` output
  is localized.
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

Nothing is automated yet. Before a release, check on both PowerShell 5.1
and 7, and on bash:

- Native switches before and after the target; the exit code; pipe and
  redirect to a file; `| Select-Object -First 3` on a `-t` ping.
- Constrained Language Mode:
  `powershell -Command "$ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'; & .\Invoke-PingStamp.ps1 -n 2 127.0.0.1"`
- Bash on Linux through WSL (`wsl -d Debian`). Simulate Ctrl+C with
  `setsid bash pingstamp.sh 127.0.0.1 & sleep 3; kill -INT -- -$!`.
- Ctrl+C on Windows needs a real console event, so piping output won't do.
  Use `python -I tests/ctrlc_harness.py 3.5 "pwsh -NoProfile -File
  Invoke-PingStamp.ps1 -t 127.0.0.1"` (and again with `powershell`). Expect
  the replies, exactly one blank line, then the full statistics ending in
  `Control-C`. Run it several times; the failure it guards against is a race.
- `shellcheck pingstamp.sh` and `Invoke-ScriptAnalyzer` must both be clean.

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
