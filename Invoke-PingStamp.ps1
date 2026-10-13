#Requires -Version 5.1

<#PSScriptInfo

.VERSION 0.0.1

.GUID d7e3f2b7-13b9-4852-93de-41036e295ae9

.AUTHOR Kismet Agbasi

.COPYRIGHT Copyright (c) 2026 Kismet Agbasi. Released under the MIT License.

.TAGS ping network timestamp troubleshooting

.LICENSEURI https://github.com/kismetgerald/PingStamp/blob/main/LICENSE.txt

.PROJECTURI https://github.com/kismetgerald/PingStamp

.RELEASENOTES
https://github.com/kismetgerald/PingStamp/blob/main/CHANGELOG.md

#>

<#
.SYNOPSIS
    Runs the system ping command and prefixes each reply line with a timestamp.

.DESCRIPTION
    Invoke-PingStamp runs the operating system's own ping command and writes
    its output with each reply line prefixed by a timestamp in the format
    "YYYY-MM-DD HH:MM:SS:MS TZ", for example "2026-10-13 05:35:40:020 EDT".
    Header and summary lines are written unchanged.

    The target is a hostname or IPv4 address. All arguments are passed to
    ping as-is, in any order, so every native ping option works: -t, -n, -l,
    -f, -a and the rest on Windows, and -c, -i, -s and the rest under
    PowerShell 7 on Linux or macOS. Run "ping /?" (Windows) or "ping -h"
    (Linux) to list them.

    Every line goes to the pipeline, so the output can be piped or redirected
    to a log file. The exception is Ctrl+C during a continuous ping:
    PowerShell has already stopped the pipeline by then, so ping's closing
    statistics are written to the console instead.

    Under Constrained Language Mode (AppLocker/WDAC), the script falls back
    to a plain pipeline. The output is the same, but Ctrl+C discards ping's
    closing statistics.

    Run with -Version as the only argument to show the script version.

    Runs on Windows PowerShell 5.1 and PowerShell 7+ (Windows, Linux, macOS).

.EXAMPLE
    .\Invoke-PingStamp.ps1 192.168.1.10

    Sends four echo requests, the Windows default.

.EXAMPLE
    .\Invoke-PingStamp.ps1 -t server01.example.com

    Pings until Ctrl+C is pressed, then shows the statistics.

.EXAMPLE
    .\Invoke-PingStamp.ps1 -n 100 192.168.1.10 | Tee-Object -FilePath .\ping.log

    Sends 100 echo requests, showing the output and saving it to ping.log.

.EXAMPLE
    .\Invoke-PingStamp.ps1 192.168.1.10 -n 3 -l 1472 -f

    Sends three 1472-byte packets with Don't Fragment set. Options may come
    before or after the target, just as with ping itself.

.EXAMPLE
    ./Invoke-PingStamp.ps1 -c 5 -i 0.2 192.168.1.10

    PowerShell 7 on Linux: five echo requests, 0.2 seconds apart.

.INPUTS
    None.

.OUTPUTS
    System.String. One string per line of ping output.

.NOTES
    This script declares no PowerShell parameters on purpose. Declared
    parameters, and the common parameters that [CmdletBinding()] adds
    (-Verbose, -WarningAction, ...), would capture native ping switches such
    as -t, -v, -w and -i.

    Exit code is ping's own exit code; 2 when run with no arguments.

.LINK
    https://github.com/kismetgerald/PingStamp
#>

Set-StrictMode -Version Latest

$script:OnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:Section = 'Header'
$script:ZoneAbbreviations = @{}

function Get-ZoneAbbreviation {
    # Returns the local time zone abbreviation (e.g. EDT) in effect at $Date.
    param([datetime] $Date)

    $zone = [TimeZoneInfo]::Local
    $isDst = $Date.IsDaylightSavingTime()
    if ($script:ZoneAbbreviations.ContainsKey($isDst)) {
        return $script:ZoneAbbreviations[$isDst]
    }

    $abbreviation = $null
    if ($script:OnWindows) {
        # Windows only has long names such as "Eastern Daylight Time". Most
        # abbreviate to their initials; these are the common exceptions.
        $exceptions = @{
            'UTC'                            = 'UTC',  'UTC'
            'GMT Standard Time'              = 'GMT',  'BST'
            'Greenwich Standard Time'        = 'GMT',  'GMT'
            'W. Europe Standard Time'        = 'CET',  'CEST'
            'Central Europe Standard Time'   = 'CET',  'CEST'
            'Central European Standard Time' = 'CET',  'CEST'
            'Romance Standard Time'          = 'CET',  'CEST'
            'E. Europe Standard Time'        = 'EET',  'EEST'
            'FLE Standard Time'              = 'EET',  'EEST'
            'GTB Standard Time'              = 'EET',  'EEST'
            'Russian Standard Time'          = 'MSK',  'MSK'
            'Alaskan Standard Time'          = 'AKST', 'AKDT'
            'Aleutian Standard Time'         = 'HST',  'HDT'
            'US Eastern Standard Time'       = 'EST',  'EDT'
            'US Mountain Standard Time'      = 'MST',  'MST'
            'AUS Eastern Standard Time'      = 'AEST', 'AEDT'
            'E. Australia Standard Time'     = 'AEST', 'AEST'
            'Cen. Australia Standard Time'   = 'ACST', 'ACDT'
            'AUS Central Standard Time'      = 'ACST', 'ACST'
            'W. Australia Standard Time'     = 'AWST', 'AWST'
            'Tokyo Standard Time'            = 'JST',  'JST'
            'Singapore Standard Time'        = 'SGT',  'SGT'
            'Arabian Standard Time'          = 'GST',  'GST'
        }
        if ($exceptions.ContainsKey($zone.Id)) {
            $abbreviation = $exceptions[$zone.Id][[int]$isDst]
        }
    }
    else {
        # Linux and macOS know the real abbreviation.
        $date = Get-Command -Name date -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($date) { $abbreviation = (& $date.Source '+%Z' 2>$null) -join '' }
    }

    if (-not $abbreviation) {
        $name = if ($isDst) { $zone.DaylightName } else { $zone.StandardName }
        if ($name -match '^\S+$') {
            $abbreviation = $name                   # already short, e.g. "UTC-11"
        }
        else {
            $abbreviation = (-join ($name -split '\s+' | Where-Object { $_ } |
                ForEach-Object { $_[0] })).ToUpperInvariant()
        }
    }

    $script:ZoneAbbreviations[$isDst] = $abbreviation
    $abbreviation
}

function Get-Timestamp {
    $now = [datetime]::Now
    # Invariant culture: ':' in a format string is the culture's time separator.
    '{0} {1}' -f $now.ToString('yyyy-MM-dd HH:mm:ss:fff', [cultureinfo]::InvariantCulture),
        (Get-ZoneAbbreviation -Date $now)
}

function Format-PingLine {
    # Native ping output has three parts: a header line, one line per probe,
    # and a summary that starts after a blank line. Only probe lines get a
    # timestamp; indented lines inside the probe section continue the line
    # above (e.g. the route from -r/-R) and are left alone. Splitting on the
    # blank line instead of matching text keeps this working with localized
    # ping output.
    param([string] $Line)

    $blank = [string]::IsNullOrWhiteSpace($Line)
    switch ($script:Section) {
        'Header' {
            if (-not $blank) { $script:Section = 'Probes' }
            $Line
        }
        'Probes' {
            if ($blank) { $script:Section = 'Summary'; $Line }
            elseif ($Line -match '^\s') { $Line }
            else { '{0} {1}' -f (Get-Timestamp), $Line }
        }
        'Summary' {
            # Windows ping -t prints interim statistics on Ctrl+Break, then
            # carries on pinging.
            if ($Line -like 'Control-Break*') { $script:Section = 'Probes' }
            $Line
        }
    }
}

function ConvertTo-ArgumentString {
    # Quotes arguments the way the Microsoft C runtime splits them back up.
    # ProcessStartInfo.ArgumentList would do this, but Windows PowerShell 5.1
    # (.NET Framework) does not have it.
    param([string[]] $Argument)

    $quoted = foreach ($arg in $Argument) {
        if ($arg -and $arg -notmatch '[\s"]') { $arg }
        else { '"{0}"' -f ($arg -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') }
    }
    $quoted -join ' '
}

# --- Arguments ---------------------------------------------------------------

if ($args.Count -eq 0) {
    $Host.UI.WriteErrorLine('Usage: Invoke-PingStamp.ps1 [ping options] <hostname | IPv4 address>')
    $Host.UI.WriteErrorLine('All arguments are passed to ping. For details, run:')
    $Host.UI.WriteErrorLine("  Get-Help '$PSCommandPath' -Full")
    exit 2
}
if ($args.Count -eq 1 -and "$($args[0])" -eq '-Version') {
    $match = Select-String -Path $PSCommandPath -Pattern '^\.VERSION\s+(\S+)' |
        Select-Object -First 1
    'Invoke-PingStamp {0}' -f $match.Matches[0].Groups[1].Value
    exit 0
}

# PowerShell has already parsed the arguments: "-n" arrives as a string, but
# "10" as an int, "0.2" as a double and "a,b" as an array. Turn them back into
# text without the current culture's decimal separator.
$pingArguments = foreach ($arg in $args) {
    $parts = foreach ($item in @($arg)) {
        [Convert]::ToString($item, [cultureinfo]::InvariantCulture)
    }
    $parts -join ','
}

if ($script:OnWindows) {
    # Full path, so a ping alias, function or stray ping.exe cannot stand in.
    $pingPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\PING.EXE'
}
else {
    $pingPath = (Get-Command -Name ping -CommandType Application -ErrorAction Stop |
        Select-Object -First 1).Source
}

# --- Run ping and stamp its output -------------------------------------------

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    # Constrained Language Mode (AppLocker/WDAC) blocks the Process class used
    # below. A plain pipeline gives the same output, except that Ctrl+C
    # discards ping's closing statistics.
    & $pingPath @pingArguments | ForEach-Object { Format-PingLine -Line $_ }
    exit $LASTEXITCODE
}

# Ping is started directly instead of piping "& ping" into ForEach-Object.
# On Ctrl+C, PowerShell would stop that pipeline and throw away ping's
# statistics; reading the process output ourselves lets the finally block
# show them.
$startInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $pingPath
$startInfo.Arguments = ConvertTo-ArgumentString -Argument $pingArguments
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.StandardOutputEncoding = [Console]::OutputEncoding

$process = [System.Diagnostics.Process]::Start($startInfo)
$pending = $null    # line read from ping but not yet written
$sectionBefore = $script:Section
$completed = $false
try {
    while ($true) {
        $sectionBefore = $script:Section
        $pending = $process.StandardOutput.ReadLine()
        if ($null -eq $pending) { break }
        $formatted = Format-PingLine -Line $pending
        if ($sectionBefore -eq 'Probes' -and $script:Section -eq 'Summary') {
            # This blank line is the first thing ping prints after Ctrl+C.
            # PowerShell's own Ctrl+C handling lags slightly behind; pausing
            # lets its stop land here instead of part-way through the write
            # below, where the line may or may not have reached the screen.
            Start-Sleep -Milliseconds 100
        }
        $formatted
        $pending = $null
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $completed = $true
}
finally {
    if (-not $completed) {
        # Stopped early: by Ctrl+C, by a downstream command such as
        # "Select-Object -First 5", or by an error. Only Ctrl+C reaches ping
        # too. Windows ping then exits with STATUS_CONTROL_C_EXIT; elsewhere,
        # ping exiting this promptly is taken to mean it got Ctrl+C (SIGINT).
        $ctrlC = $false
        if ($process.WaitForExit(500)) {
            $ctrlC = -not $script:OnWindows -or $process.ExitCode -eq -1073741510
        }
        else {
            try { $process.Kill() }
            catch [System.InvalidOperationException] {
                Write-Verbose -Message 'ping exited before it could be stopped.'
            }
        }

        if ($ctrlC) {
            # Ping has printed its statistics. The pipeline is stopped, so
            # pass the remaining lines to the host. Write-Output would
            # silently end this block.
            if ($null -ne $pending) {
                # Stopped part-way through this line: format it again.
                $script:Section = $sectionBefore
                $Host.UI.WriteLine((Format-PingLine -Line $pending))
            }
            while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
                $Host.UI.WriteLine((Format-PingLine -Line $line))
            }
        }
    }
    $process.Dispose()
}

exit $exitCode
