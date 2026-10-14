#Requires -Version 5.1
<#
.SYNOPSIS
    Smoke tests for Invoke-PingStamp.ps1. Pings 127.0.0.1 only.

.DESCRIPTION
    Runs Invoke-PingStamp.ps1 in child processes of the same PowerShell that
    runs this script, so run it once with Windows PowerShell 5.1 and once with
    PowerShell 7. Works on Windows, Linux and macOS.

    The Windows Ctrl+C test needs Python (tests/ctrlc_harness.py) and is
    skipped without it.

    Exits 1 if any test fails.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-InvokePingStamp.ps1

.EXAMPLE
    pwsh -NoProfile -File tests/Test-InvokePingStamp.ps1
#>

Set-StrictMode -Version Latest

# GitHub Actions runs PowerShell with 'Stop'. Under Windows PowerShell 5.1,
# a child's stderr captured with 2>&1 would then become a terminating error.
$ErrorActionPreference = 'Continue'

# An error inside a test is a failed test, not something to skip past.
trap {
    Write-Host "FAIL (error) $_"
    $script:failures++
    continue
}

$root = Split-Path -Path $PSScriptRoot -Parent
$script = Join-Path -Path $root -ChildPath 'Invoke-PingStamp.ps1'
$shell = (Get-Process -Id $PID).Path
$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$onMac = -not $onWindows -and (uname -s) -eq 'Darwin'
$stampPattern = '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d:\d{3} [A-Za-z0-9+-]+ '
$tempDir = [IO.Path]::GetTempPath()
$script:failures = 0

if ($onWindows) {
    $pingPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\PING.EXE'
    $count = '-n'
    $size = '-l'
    $continuous = '-t'
}
else {
    $pingPath = (Get-Command -Name ping -CommandType Application | Select-Object -First 1).Source
    $count = '-c'
    $size = '-s'
    $continuous = $null     # continuous is the default
}

$script:lastOutput = @()   # output of the latest run, shown when a test fails

function Test-That {
    param([string] $Name, [bool] $Condition)
    if ($Condition) { Write-Host "ok   $Name"; return }
    Write-Host "FAIL $Name"
    $script:failures++
    foreach ($line in $script:lastOutput) { Write-Host "     | $line" }
}

function Invoke-Child {
    # Runs this same PowerShell with the given arguments. Returns the output
    # lines (stdout and stderr) and the exit code.
    param([string[]] $ArgumentList)
    $base = @('-NoProfile', '-NonInteractive')
    if ($onWindows) { $base += '-ExecutionPolicy', 'Bypass' }
    $lines = @(& $shell @base @ArgumentList 2>&1 | ForEach-Object { "$_" })
    $script:lastOutput = @($lines) + "(exit code $LASTEXITCODE)"
    [pscustomobject]@{ Lines = $lines; ExitCode = $LASTEXITCODE }
}

function Get-StampedLine {
    param([string[]] $Lines)
    # The leading comma keeps a one-line result an array for the caller.
    , @($Lines | Where-Object { $_ -match $stampPattern })
}

function Get-MinimumGap {
    # Smallest gap in milliseconds between consecutive stamped lines.
    param([string[]] $Lines)
    $times = foreach ($line in (Get-StampedLine -Lines $Lines)) {
        [datetime]::ParseExact($line.Substring(0, 23), 'yyyy-MM-dd HH:mm:ss:fff',
            [cultureinfo]::InvariantCulture)
    }
    $gaps = for ($i = 1; $i -lt @($times).Count; $i++) {
        ($times[$i] - $times[$i - 1]).TotalMilliseconds
    }
    if ($gaps) { ($gaps | Measure-Object -Minimum).Minimum } else { 0 }
}

function Test-CtrlCOutput {
    # Ctrl+C output: replies, exactly one blank line, then ping's statistics.
    param([string[]] $Lines, [string] $Label)
    $script:lastOutput = $Lines
    $stats = @(for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match 'statistics') { $i }
    })
    Test-That "${Label}: statistics are shown once" ($stats.Count -eq 1)
    if ($stats.Count -eq 1 -and $stats[0] -ge 2) {
        $i = $stats[0]
        Test-That "${Label}: one blank line before the statistics" (
            [string]::IsNullOrWhiteSpace($Lines[$i - 1]) -and
            $Lines[$i - 2] -match $stampPattern)
    }
    Test-That "${Label}: replies before it are stamped" ((Get-StampedLine -Lines $Lines).Count -ge 2)
}

Write-Host ("Invoke-PingStamp tests: PowerShell {0} ({1}) on {2}" -f
    $PSVersionTable.PSVersion, $PSVersionTable.PSEdition, [Environment]::OSVersion.VersionString)

# --- Version and usage --------------------------------------------------------

$version = (Select-String -Path $script -Pattern '^\.VERSION\s+(\S+)').Matches[0].Groups[1].Value
$r = Invoke-Child -ArgumentList '-File', $script, '-Version'
Test-That "-Version prints $version" ($r.Lines -contains "Invoke-PingStamp $version")

# Brackets in a folder name are wildcards to -Path parameters.
$bracketDir = [IO.Path]::Combine($tempDir, "pingstamp [test] $PID")
$null = [IO.Directory]::CreateDirectory($bracketDir)
$bracketCopy = [IO.Path]::Combine($bracketDir, 'Invoke-PingStamp.ps1')
[IO.File]::Copy($script, $bracketCopy, $true)
$r = Invoke-Child -ArgumentList '-File', $bracketCopy, '-Version'
Test-That '-Version works from a folder with [brackets] in its name' (
    $r.Lines -contains "Invoke-PingStamp $version")
$r = Invoke-Child -ArgumentList '-File', $bracketCopy, $count, '1', '127.0.0.1'
Test-That 'pinging works from a folder with [brackets] in its name' (
    $r.ExitCode -eq 0 -and (Get-StampedLine -Lines $r.Lines).Count -eq 1)
[IO.Directory]::Delete($bracketDir, $true)

$r = Invoke-Child -ArgumentList '-File', $script
Test-That 'no arguments exits 2' ($r.ExitCode -eq 2)
Test-That 'no arguments prints usage' (@($r.Lines -match '^Usage:').Count -eq 1)

# --- A short run --------------------------------------------------------------

$r = Invoke-Child -ArgumentList '-File', $script, $count, '3', '127.0.0.1'
$stamped = Get-StampedLine -Lines $r.Lines
$header = $r.Lines | Where-Object { $_.Trim() } | Select-Object -First 1
Test-That "$count 3 exits 0" ($r.ExitCode -eq 0)
Test-That 'no PowerShell errors in the output' (@($r.Lines -match 'Error:|Exception').Count -eq 0)
Test-That '3 reply lines are stamped' ($stamped.Count -eq 3)
Test-That 'header line is not stamped' ($header -match '^PING' -and $header -notmatch $stampPattern)
Test-That 'statistics are not stamped' (
    @($r.Lines -match 'statistics').Count -eq 1 -and @($stamped -match 'statistics').Count -eq 0)
$gap = Get-MinimumGap -Lines $r.Lines
Test-That "lines are stamped as they arrive (smallest gap $gap ms >= 500)" ($gap -ge 500)

# --- Native ping behavior -----------------------------------------------------

& $pingPath $count 1 no-such-host.invalid *> $null
$nativeExit = $LASTEXITCODE
$r = Invoke-Child -ArgumentList '-File', $script, $count, '1', 'no-such-host.invalid'
Test-That "exit code matches ping's for an unknown host ($nativeExit)" ($r.ExitCode -eq $nativeExit)
Test-That "ping's exit code for an unknown host is non-zero" ($nativeExit -ne 0)

# Options after the target work with Windows and Linux ping; macOS ping
# needs them first.
if ($onMac) { $pingArgs = $count, '2', $size, '100', '127.0.0.1' }
else { $pingArgs = '127.0.0.1', $count, '2', $size, '100' }
$r = Invoke-Child -ArgumentList (@('-File', $script) + $pingArgs)
Test-That "native options pass through ($($pingArgs -join ' '))" (
    $r.ExitCode -eq 0 -and (Get-StampedLine -Lines $r.Lines).Count -eq 2 -and
    @($r.Lines -match '\b100\b').Count -ge 1)

# Switches that would collide with PowerShell's common parameters if the
# script declared any (-Verbose, -WarningAction, -InformationAction, ...).
# On Linux, -v also prints a line before the "PING ..." header.
if ($onWindows) { $pingArgs = '-n', '1', '-w', '1000', '-i', '64', '-v', '0', '127.0.0.1' }
else { $pingArgs = '-c', '1', '-v', '-i', '1', '127.0.0.1' }
$r = Invoke-Child -ArgumentList (@('-File', $script) + $pingArgs)
$stamped = Get-StampedLine -Lines $r.Lines
Test-That "switches named like common parameters pass through ($($pingArgs -join ' '))" (
    $r.ExitCode -eq 0 -and $stamped.Count -eq 1 -and @($stamped -match 'PING').Count -eq 0)

# --- Lost replies -------------------------------------------------------------
# 192.0.2.1 (TEST-NET-1) is reserved for documentation and never answers.

if ($onWindows) { $dropArgs = '-n', '2', '-w', '500', '192.0.2.1' }
else { $dropArgs = '-c', '3', '-W', '1', '192.0.2.1' }
$r = Invoke-Child -ArgumentList (@('-File', $script) + $dropArgs)
Test-That 'lost replies get stamped lines' ((Get-StampedLine -Lines $r.Lines).Count -ge 1)
if (-not $onWindows -and -not $onMac) {
    Test-That "Linux: lost replies show as 'no answer yet' (-O added)" (
        @($r.Lines -match "$stampPattern.*no answer yet").Count -ge 1)
    $r = Invoke-Child -ArgumentList (@('-File', $script, '-HideDrops') + $dropArgs)
    Test-That 'Linux: -HideDrops leaves -O out' (@($r.Lines -match 'no answer yet').Count -eq 0)
}

$r = Invoke-Child -ArgumentList '-File', $script, '-HideDrops', $count, '1', '127.0.0.1'
Test-That '-HideDrops is accepted and not passed to ping' (
    $r.ExitCode -eq 0 -and (Get-StampedLine -Lines $r.Lines).Count -eq 1)

# --- Outages ------------------------------------------------------------------
# Lost replies can't be produced on demand. tests/fake-ping.sh holds scripted
# ping output; its lines are fed to the script's own functions here on every
# platform (tests/feed-lines.ps1). On Linux and macOS, the whole script also
# runs against fake-ping.sh, put first in PATH. Windows always uses
# System32\PING.EXE, so that can't be faked.

$outagePattern = "$stampPattern\*\*\* Outage: "

function Get-FakePingLine {
    # The lines tests/fake-ping.sh prints for a scenario.
    param([string] $Scenario)
    $text = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath 'fake-ping.sh')
    $block = [regex]::Match($text, '(?ms)^\s+' + $Scenario + '\)\s*$(.*?)^\s+;;').Groups[1].Value
    , @([regex]::Matches($block, 'say "(.*)"') | ForEach-Object { $_.Groups[1].Value })
}

function Invoke-Feed {
    # Feeds a fake-ping.sh scenario to the script's functions; returns the output.
    param([string] $Scenario, [string[]] $Option = @())
    $linesFile = Join-Path -Path $tempDir -ChildPath "pingstamp-feed-$PID.txt"
    Set-Content -Path $linesFile -Value (Get-FakePingLine -Scenario $Scenario)
    $feeder = Join-Path -Path $PSScriptRoot -ChildPath 'feed-lines.ps1'
    $result = Invoke-Child -ArgumentList (@('-File', $feeder, '-ScriptPath', $script,
        '-LinesFile', $linesFile) + $Option)
    Remove-Item -Path $linesFile -ErrorAction SilentlyContinue
    $result
}

function Get-LineAfter {
    # The line after the first line matching $Pattern.
    param([string[]] $Lines, [string] $Pattern)
    for ($i = 0; $i -lt $Lines.Count - 1; $i++) {
        if ($Lines[$i] -match $Pattern) { return $Lines[$i + 1] }
    }
}

$r = Invoke-Feed -Scenario 'recovery'
$outages = @($r.Lines -match $outagePattern)
$firstLost = @($r.Lines -match "${stampPattern}no answer yet")[0].Substring(11, 8)
Test-That 'outage: one line once replies come back' ($outages.Count -eq 1)
Test-That 'outage: it follows the reply that ended it' (
    $outages.Count -eq 1 -and (Get-LineAfter -Lines $r.Lines -Pattern 'icmp_seq=5 ') -eq $outages[0])
Test-That "outage: '3 replies lost over N.N s, from HH:MM:SS'" (
    $outages.Count -eq 1 -and $outages[0] -match "${outagePattern}3 replies lost over \d+\.\d s, from \d\d:\d\d:\d\d$")
Test-That "outage: 'from' is when the first lost reply was reported" (
    $outages.Count -eq 1 -and $outages[0].EndsWith("from $firstLost"))
if ($outages.Count -eq 1 -and $outages[0] -match ' over ([\d.]+) s') {
    $seconds = [double]::Parse($Matches[1], [cultureinfo]::InvariantCulture)
    Test-That "outage: duration is plausible ($seconds s)" ($seconds -ge 0.3 -and $seconds -le 3.0)
}

$r = Invoke-Feed -Scenario 'ongoing'
Test-That "outage still going at the end: '(no reply since)' line" (
    @($r.Lines -match "${outagePattern}2 replies lost over \d+\.\d s, from [\d:]{8} \(no reply since\)$").Count -eq 1)
Test-That 'outage still going at the end: just before the statistics' (
    [string]::IsNullOrEmpty((Get-LineAfter -Lines $r.Lines -Pattern $outagePattern)))

$r = Invoke-Feed -Scenario 'windows'
Test-That "outage: Windows style, down from the start ('Reply from ...: unreachable' is lost)" (
    @($r.Lines -match "${outagePattern}2 replies lost over ").Count -eq 1)

$r = Invoke-Feed -Scenario 'unreadable'
Test-That 'outage: none when no reply can be recognized (localized output)' (
    @($r.Lines -match $outagePattern).Count -eq 0)

$r = Invoke-Feed -Scenario 'recovery' -Option '-Records'
Test-That '-AsObject records: the outage has Type Outage, without a timestamp in Line' (
    @($r.Lines -match "^Outage`t\*\*\* Outage: 3 replies lost").Count -eq 1)

$r = Invoke-Feed -Scenario 'recovery' -Option '-NoOutages'
Test-That '-NoOutages: no outage line' (@($r.Lines -match $outagePattern).Count -eq 0)

$r = Invoke-Child -ArgumentList '-File', $script, '-NoOutages', $count, '1', '127.0.0.1'
Test-That '-NoOutages is not passed to the real ping' (
    $r.ExitCode -eq 0 -and (Get-StampedLine -Lines $r.Lines).Count -eq 1)

if (-not $onWindows) {
    $fakeDir = Join-Path -Path $tempDir -ChildPath "pingstamp-fakebin-$PID"
    $null = New-Item -ItemType Directory -Path $fakeDir -Force
    $fakePing = Join-Path -Path $fakeDir -ChildPath 'ping'
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'fake-ping.sh') -Destination $fakePing
    chmod +x $fakePing
    $log = Join-Path -Path $tempDir -ChildPath "pingstamp-outage-$PID.log"
    Remove-Item -Path $log -ErrorAction SilentlyContinue

    $savedPath = $env:PATH
    $env:PATH = $fakeDir + [IO.Path]::PathSeparator + $env:PATH
    $env:FAKE_PING_SCENARIO = 'recovery'
    $r = Invoke-Child -ArgumentList '-File', $script, '-LogFile', $log, '192.0.2.1'
    $env:PATH = $savedPath
    Remove-Item -Path Env:FAKE_PING_SCENARIO

    $outages = @($r.Lines -match $outagePattern)
    Test-That 'outage, whole script on a fake ping: line after the reply that ended it' (
        $outages.Count -eq 1 -and (Get-LineAfter -Lines $r.Lines -Pattern 'icmp_seq=5 ') -eq $outages[0])
    $logLines = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
    Test-That 'outage, whole script on a fake ping: the log matches the output' (
        ($logLines -join "`n") -eq ($r.Lines -join "`n"))
    Remove-Item -Path $log, $fakeDir -Recurse -ErrorAction SilentlyContinue
}

# --- -AsObject ----------------------------------------------------------------
# Objects can't cross the process boundary as objects, so the child describes
# each one on a line: <Timestamp's type>|<its Kind>|<Type>|<Line>.

$describe = "ForEach-Object { '{0}|{1}|{2}|{3}' -f `$_.Timestamp.GetType().Name, " +
    "`$_.Timestamp.Kind, `$_.Type, `$_.Line }"
$log = Join-Path -Path $tempDir -ChildPath "pingstamp-asobject-$PID.log"
Remove-Item -Path $log -ErrorAction SilentlyContinue
$r = Invoke-Child -ArgumentList '-Command', (
    "& '$script' -AsObject $count 2 127.0.0.1 -LogFile '$log' | $describe; exit `$LASTEXITCODE")
$rows = @($r.Lines | Where-Object { $_ -like '*|*|*|*' } | ForEach-Object {
    $fields = $_ -split '\|', 4
    [pscustomobject]@{ TimeType = $fields[0]; Kind = $fields[1]; Type = $fields[2]; Line = $fields[3] }
})
$probes = @($rows | Where-Object { $_.Type -eq 'Probe' })
Test-That '-AsObject: exits 0' ($r.ExitCode -eq 0)
Test-That '-AsObject: one object per line, each with a [datetime] Timestamp' (
    $rows.Count -ge 6 -and @($rows | Where-Object { $_.TimeType -ne 'DateTime' }).Count -eq 0)
Test-That '-AsObject: local time by default' (@($rows | Where-Object { $_.Kind -ne 'Local' }).Count -eq 0)
Test-That '-AsObject: 2 Probe objects, Line without a timestamp' (
    $probes.Count -eq 2 -and @($probes | Where-Object { $_.Line -match $stampPattern }).Count -eq 0)
Test-That '-AsObject: Header first, statistics are Summary' (
    $rows.Count -gt 0 -and $rows[0].Type -eq 'Header' -and
    @($rows | Where-Object { $_.Line -match 'statistics' -and $_.Type -eq 'Summary' }).Count -eq 1)
$script:lastOutput = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
Test-That '-AsObject: -LogFile still gets timestamped text' (
    (Get-StampedLine -Lines $script:lastOutput).Count -eq 2)
Remove-Item -Path $log -ErrorAction SilentlyContinue

$r = Invoke-Child -ArgumentList '-Command', (
    "& '$script' -AsObject -Utc $count 1 127.0.0.1 | $describe; exit `$LASTEXITCODE")
Test-That '-AsObject -Utc: Timestamps are UTC' (
    @($r.Lines -like '*|*|*|*').Count -gt 0 -and @($r.Lines -like 'DateTime|Utc|*').Count -eq @($r.Lines -like '*|*|*|*').Count)

# --- -Utc ---------------------------------------------------------------------

$r = Invoke-Child -ArgumentList '-File', $script, '-Utc', $count, '1', '127.0.0.1'
$utcNow = [datetime]::UtcNow
$stamped = Get-StampedLine -Lines $r.Lines
Test-That '-Utc is not passed to ping (1 stamped line)' ($r.ExitCode -eq 0 -and $stamped.Count -eq 1)
if ($stamped.Count -eq 1) {
    $parts = $stamped[0].Split(' ')
    $time = [datetime]::ParseExact("$($parts[0]) $($parts[1])", 'yyyy-MM-dd HH:mm:ss:fff',
        [cultureinfo]::InvariantCulture)
    Test-That '-Utc: the zone is UTC' ($parts[2] -eq 'UTC')
    Test-That '-Utc: the time is UTC (within 2 minutes)' (
        [math]::Abs(($utcNow - $time).TotalSeconds) -le 120)
}

# --- Pipeline -----------------------------------------------------------------

$log = Join-Path -Path $tempDir -ChildPath "pingstamp-test-$PID.log"
$r = Invoke-Child -ArgumentList '-Command', "& '$script' $count 2 127.0.0.1 > '$log'; exit `$LASTEXITCODE"
Test-That 'redirected to a file: exits 0' ($r.ExitCode -eq 0)
$script:lastOutput = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
Test-That 'redirected to a file: 2 stamped lines' ((Get-StampedLine -Lines $script:lastOutput).Count -eq 2)
Remove-Item -Path $log -ErrorAction SilentlyContinue

$pingsBefore = @(Get-Process -Name ping -ErrorAction SilentlyContinue).Count
$watch = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-Child -ArgumentList '-Command', "& '$script' $continuous 127.0.0.1 | Select-Object -First 4"
$watch.Stop()
Start-Sleep -Milliseconds 500
Test-That 'Select-Object -First 4: exactly 4 lines' ($r.Lines.Count -eq 4)
Test-That "Select-Object -First 4: stops promptly ($([int]$watch.Elapsed.TotalSeconds) s)" (
    $watch.Elapsed.TotalSeconds -lt 15)
Test-That 'Select-Object -First 4: ping is not left running' (
    @(Get-Process -Name ping -ErrorAction SilentlyContinue).Count -le $pingsBefore)

# --- -LogFile -----------------------------------------------------------------

$log = Join-Path -Path $tempDir -ChildPath "pingstamp-logfile-$PID.log"
Remove-Item -Path $log -ErrorAction SilentlyContinue
$r = Invoke-Child -ArgumentList '-File', $script, '-LogFile', $log, $count, '2', '127.0.0.1'
$logLines = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
Test-That '-LogFile: exits 0' ($r.ExitCode -eq 0)
Test-That '-LogFile: the log matches the output' (($logLines -join "`n") -eq ($r.Lines -join "`n"))
$script:lastOutput = $logLines
Test-That '-LogFile: the log has 2 stamped lines and the statistics' (
    (Get-StampedLine -Lines $logLines).Count -eq 2 -and @($logLines -match 'statistics').Count -eq 1)

$r = Invoke-Child -ArgumentList '-Command', "& '$script' $count 1 127.0.0.1 -LogFile:'$log'; exit `$LASTEXITCODE"
$script:lastOutput = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
Test-That '-LogFile:<path> after the target appends (now 3 stamped lines)' (
    (Get-StampedLine -Lines $script:lastOutput).Count -eq 3)
Remove-Item -Path $log -ErrorAction SilentlyContinue

$r = Invoke-Child -ArgumentList '-File', $script, $count, '1', '127.0.0.1', '-LogFile'
Test-That '-LogFile without a path exits 2' ($r.ExitCode -eq 2)

$badLog = Join-Path -Path $tempDir -ChildPath "no-such-dir-$PID/ping.log"
$r = Invoke-Child -ArgumentList '-File', $script, '-LogFile', $badLog, $count, '1', '127.0.0.1'
Test-That '-LogFile to an unwritable path exits 2 without pinging' (
    $r.ExitCode -eq 2 -and (Get-StampedLine -Lines $r.Lines).Count -eq 0)

# --- Constrained Language Mode ------------------------------------------------

$log = Join-Path -Path $tempDir -ChildPath "pingstamp-clm-$PID.log"
Remove-Item -Path $log -ErrorAction SilentlyContinue
$r = Invoke-Child -ArgumentList '-Command', (
    "`$ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'; " +
    "& '$script' $count 2 127.0.0.1 -LogFile '$log'; exit `$LASTEXITCODE")
Test-That 'Constrained Language Mode: exits 0' ($r.ExitCode -eq 0)
Test-That 'Constrained Language Mode: 2 stamped lines' ((Get-StampedLine -Lines $r.Lines).Count -eq 2)
$script:lastOutput = @(Get-Content -Path $log -ErrorAction SilentlyContinue)
Test-That 'Constrained Language Mode: -LogFile works' ((Get-StampedLine -Lines $script:lastOutput).Count -eq 2)
Remove-Item -Path $log -ErrorAction SilentlyContinue

# --- Ctrl+C -------------------------------------------------------------------

function Invoke-CtrlC {
    # Runs the script with the given options on a continuous ping of
    # 127.0.0.1, sends Ctrl+C after a few seconds, and returns what it
    # printed. Returns nothing on Windows without Python.
    param([string[]] $Option)
    if ($onWindows) {
        $python = Get-Command -Name python, py -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $python) { return }
        $harness = Join-Path -Path $PSScriptRoot -ChildPath 'ctrlc_harness.py'
        return @(& $python.Source -I $harness 3.5 $shell -NoProfile -ExecutionPolicy Bypass `
            -File $script -t 127.0.0.1 @Option)
    }
    # Job control gives the child its own process group with SIGINT at its
    # default, so the signal reaches pwsh and ping as a terminal's Ctrl+C would.
    $out = Join-Path -Path $tempDir -ChildPath "pingstamp-ctrlc-$PID.txt"
    bash -c 'set -m; "$0" -NoProfile -File "$1" 127.0.0.1 "${@:3}" > "$2" 2>&1 & pid=$!; set +m; sleep 4; kill -INT -- -$pid; wait $pid' `
        $shell $script $out @Option
    @(Get-Content -Path $out)
    Remove-Item -Path $out -ErrorAction SilentlyContinue
}

$ctrlLog = Join-Path -Path $tempDir -ChildPath "pingstamp-ctrlc-$PID.log"
Remove-Item -Path $ctrlLog -ErrorAction SilentlyContinue
$lines = Invoke-CtrlC -Option '-LogFile', $ctrlLog
if ($null -eq $lines) {
    Write-Host 'skip Ctrl+C: Python not found (needed for tests/ctrlc_harness.py)'
}
else {
    $lines = @($lines)
    $logLines = @(Get-Content -Path $ctrlLog -ErrorAction SilentlyContinue)
    Remove-Item -Path $ctrlLog -ErrorAction SilentlyContinue
    Test-CtrlCOutput -Lines $lines -Label 'Ctrl+C'
    Test-CtrlCOutput -Lines $logLines -Label 'Ctrl+C, -LogFile'
    if ($onWindows) {
        foreach ($pair in @(@('Ctrl+C', $lines), @('Ctrl+C, -LogFile', $logLines))) {
            $script:lastOutput = $pair[1]
            Test-That "$($pair[0]): ends with Control-C" (
                ($pair[1] | Where-Object { $_.Trim() } | Select-Object -Last 1) -eq 'Control-C')
        }
    }

    # With -AsObject the pipeline shows objects, but after Ctrl+C the
    # statistics still reach the console as text.
    $script:lastOutput = @(Invoke-CtrlC -Option '-AsObject')
    Test-That 'Ctrl+C with -AsObject: statistics are shown once' (
        @($script:lastOutput -match 'statistics').Count -eq 1)
}

# ------------------------------------------------------------------------------

if ($script:failures -gt 0) {
    Write-Host "$script:failures test(s) failed"
    exit 1
}
Write-Host 'All tests passed'
