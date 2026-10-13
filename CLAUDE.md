# PingStamp

The design rules, how the scripts work, testing and publishing are all in
CONTRIBUTING.md, imported here so there is one copy to maintain:

@CONTRIBUTING.md

## Notes for Claude

- Keep README.md for people using the scripts. Anything about internals,
  testing or releasing goes in CONTRIBUTING.md.
- Every script change needs a test, and both test suites must pass locally
  before pushing: the Bash suite in WSL (`wsl -d Debian`) and in Git Bash,
  and the PowerShell suite under both `pwsh` and `powershell`. PowerShell 7
  on Linux and macOS is only available in CI.
- When calling `wsl.exe` from Git Bash, set `MSYS_NO_PATHCONV=1`, and put
  anything non-trivial in a script file: `$` and quotes get mangled on the
  way through `wsl.exe ... bash -c`.
- A Ctrl+C test started with plain `&` is invalid: the job starts with SIGINT
  ignored. Use the tests' `set -m` approach or `tests/ctrlc_harness.py`.
- The planned work is in TODO.md; tick items off there as they are done.
