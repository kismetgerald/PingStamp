# PingStamp to-do

Work through these in order. Tick an item when it is merged, and record
user-visible changes in [CHANGELOG.md](CHANGELOG.md).

## v0.0.2: fix what real use would hit, and close the testing gaps

- [x] **1. Automated tests and CI.** Add test scripts for both scripts
  (`tests/`) and a GitHub Actions workflow. It runs them on Windows
  (PowerShell 5.1 and 7), Ubuntu and macOS, plus ShellCheck and
  PSScriptAnalyzer. This covers the untested platforms (PowerShell 7 on
  Linux/macOS, macOS bash 3.2) and checks whether macOS ping buffers its
  output when piped. Done first, so every later item gets tests as it lands.
  *Done. It found and fixed two bugs: PowerShell 7 on Linux/macOS failed at
  the first reply, and `ping -v` got its header stamped. macOS ping does not
  buffer, and Ctrl+C keeps the statistics on every platform.*
- [x] **2. Built-in log file:** `--log FILE` (bash) and `-LogFile FILE`
  (PowerShell). Today Ctrl+C loses the statistics from logs: in bash, `tee`
  is killed too (`tee -i` survives); in PowerShell, they go to the console
  instead of `Tee-Object` or a redirect. *Done: appends, may appear
  anywhere, fails before pinging if the log can't be written. Tested,
  including Ctrl+C on every platform and Constrained Language Mode.*
- [x] **3. Show dropped replies on Linux.** iputils ping prints nothing for a
  lost reply, so timestamps can't show when a drop happened. Add `-O` (it
  prints `no answer yet for icmp_seq=N`) on iputils unless the user already
  passed it. *Done: added automatically on iputils ≥ s20121221 (detected
  with `ping -V`); `--hide-drops` / `-HideDrops` turns it off. A duplicate
  `-O` is harmless, so the user's own `-O` needs no special handling.*
- [x] **4. Ctrl+C under Git Bash.** Its terminal (mintty) usually kills
  native Windows programs outright, which probably loses the statistics.
  Test it, then fix or document. *Done: no fix needed. With Git for Windows
  2.55, Ctrl+C keeps the statistics, screen and log, in mintty (checked by
  hand) and in a Windows console (now tested in CI on every push). The exit
  code afterwards is 130; documented.*
- [ ] **5. Release v0.0.2** (pre-release).

## v0.0.3: optional features

- [ ] **6. UTC timestamps:** `--utc` / `-Utc`, for matching logs across
  sites and time zones.
- [ ] **7. Outage summary.** When replies return after failures, print one
  line such as `outage 05:35:40 -> 05:35:52 (12 s, 12 lost)`. This needs to
  recognize reply text, so it works with English output only.
- [ ] **8. PowerShell objects:** `-AsObject` emits `Timestamp` (`[datetime]`)
  and `Line`, for `Where-Object` time filters and `Export-Csv`.
- [ ] **9. Release v0.0.3** (pre-release).

## Before v0.1.0 (first beta)

- [ ] **10. Authenticode-sign the PowerShell script** on each release with a
  certificate from the internal PKI. A signed script runs under the
  AllSigned policy and, where WDAC/AppLocker trusts the signer, in
  FullLanguage mode, which keeps the Ctrl+C statistics. Changing the line
  endings breaks the signature, so ship the signed copy as the release
  download.
- [ ] **11. PowerShell Gallery** (optional): `Publish-Script`, so
  `Install-Script Invoke-PingStamp` works. Not useful on air-gapped
  networks.
