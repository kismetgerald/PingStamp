#Requires -Version 5.1

<#PSScriptInfo

.VERSION 0.0.3

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
    ping as-is, so every native ping option works: -t, -n, -l, -f, -a and the
    rest on Windows, and -c, -i, -s and the rest under PowerShell 7 on Linux
    or macOS. Windows and Linux ping accept options before or after the
    target; macOS ping needs them first. Run "ping /?" (Windows) or "ping -h"
    (Linux) to list them.

    Lost replies: Windows and macOS ping report each one ("Request timed
    out.", "Request timeout for icmp_seq N"), and those lines get a timestamp
    like any other. Linux ping prints nothing for a lost reply, so on Linux
    the script adds -O, which prints "no answer yet for icmp_seq=N" instead.
    Use -HideDrops to turn that off; it has no effect elsewhere.

    Outages: when replies come back after being lost, a line such as
        ... *** Outage: 3 replies lost over 9.0 s, from 05:35:40
    follows. If replies are still being lost at the end, the line comes just
    before the statistics, ending in "(no reply since)". Use -NoOutages to
    turn these lines off.

    Timestamps use local time. Use -Utc for UTC instead.

    To keep a log, use -LogFile <path>. Every line, timestamped as on screen,
    is appended to that file as it arrives, including ping's statistics after
    Ctrl+C. -LogFile is the script's own option and may appear anywhere in the
    arguments; "-LogFile:<path>" also works. The file is created if needed. If
    it can't be written, the script stops with exit code 2 before pinging.

    Every line also goes to the pipeline, so the output can be piped or
    redirected. The exception is Ctrl+C during a continuous ping: PowerShell
    has already stopped the pipeline by then, so ping's closing statistics
    go to the console (and to -LogFile) instead. That is why -LogFile is the
    better way to keep a log than Tee-Object or ">".

    With -AsObject, the pipeline gets one object per line instead of text,
    with these properties:
        Timestamp  [datetime] when the line arrived (UTC with -Utc)
        Type       Header, Probe, Outage or Summary
        Line       ping's own text, without the timestamp
    -LogFile still gets the timestamped text, and after Ctrl+C the closing
    statistics still go to the console as text.

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
    .\Invoke-PingStamp.ps1 -t 192.168.1.10 -LogFile .\ping.log

    Pings until Ctrl+C, showing the output and appending it to ping.log,
    statistics included.

.EXAMPLE
    .\Invoke-PingStamp.ps1 -Utc -n 10 192.168.1.10

    Sends ten echo requests, with timestamps in UTC.

.EXAMPLE
    .\Invoke-PingStamp.ps1 -AsObject -n 100 192.168.1.10 |
        Where-Object Type -eq 'Probe' | Export-Csv -Path .\ping.csv -NoTypeInformation

    Saves each reply and lost reply, with its timestamp, to a CSV file.

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
    System.Management.Automation.PSCustomObject. With -AsObject, one object
    per line, with Timestamp, Type and Line.

.NOTES
    This script declares no PowerShell parameters on purpose. Declared
    parameters, and the common parameters that [CmdletBinding()] adds
    (-Verbose, -WarningAction, ...), would capture native ping switches such
    as -t, -v, -w and -i.

    The script's own options are -LogFile, -AsObject, -Utc, -NoOutages,
    -HideDrops and -Version. Exact names like these can't clash with ping's
    single-letter switches.

    Exit code is ping's own exit code; 2 for a usage error or a log file that
    can't be written.

.LINK
    https://github.com/kismetgerald/PingStamp
#>

Set-StrictMode -Version Latest

$script:OnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$script:Section = 'Header'
$script:ZoneAbbreviations = @{}
$script:Utc = $false
$script:AsObject = $false
$script:ShowOutages = $true
$script:Lost = 0             # lost replies in the current outage
$script:LostSince = $null    # [datetime] of the first of them
$script:SeenReply = $false

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
        # Linux and macOS know the real abbreviation. (Not "$date": variable
        # names ignore case, so that would be the [datetime] $Date parameter.)
        $dateCommand = Get-Command -Name date -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($dateCommand) { $abbreviation = (& $dateCommand.Source '+%Z' 2>$null) -join '' }
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

function Get-Now {
    if ($script:Utc) { [datetime]::UtcNow } else { [datetime]::Now }
}

function Format-Timestamp {
    param([datetime] $Date)
    $zone = if ($script:Utc) { 'UTC' } else { Get-ZoneAbbreviation -Date $Date }
    # Invariant culture: ':' in a format string is the culture's time separator.
    '{0} {1}' -f $Date.ToString('yyyy-MM-dd HH:mm:ss:fff', [cultureinfo]::InvariantCulture), $zone
}

function ConvertTo-PingRecord {
    # One line of output: when it arrived, what kind of line it is (Header,
    # Probe, Outage or Summary), ping's own text, and the text to show, which
    # carries the timestamp for Probe and Outage lines. A hashtable, because
    # Constrained Language Mode doesn't allow [pscustomobject].
    param([datetime] $Timestamp, [string] $Type, [string] $Line, [string] $Text = $Line)
    @{ Timestamp = $Timestamp; Type = $Type; Line = $Line; Text = $Text }
}

function Get-OutageRecord {
    # "*** Outage: 3 replies lost over 9.0 s, from 05:35:40"
    param([datetime] $Now, [string] $Suffix)
    $noun = if ($script:Lost -eq 1) { 'reply' } else { 'replies' }
    $culture = [cultureinfo]::InvariantCulture
    $outage = '*** Outage: {0} {1} lost over {2} s, from {3}{4}' -f $script:Lost, $noun,
        ($Now - $script:LostSince).TotalSeconds.ToString('0.0', $culture),
        $script:LostSince.ToString('HH:mm:ss', $culture), $Suffix
    ConvertTo-PingRecord -Timestamp $Now -Type 'Outage' -Line $outage `
        -Text ('{0} {1}' -f (Format-Timestamp -Date $Now), $outage)
}

function Trace-Outage {
    # Tracks lost replies; returns an outage record when replies come back.
    # A probe line with a round-trip time or a TTL is a reply; any other
    # probe line ("Request timed out.", "no answer yet ...", "Destination
    # host unreachable.") is a lost reply. That means reading ping's text,
    # which is localized, so an outage is reported only once a reply has
    # been recognized: output this can't read never produces a false outage.
    # TTL= is the same in every language Windows ping speaks.
    param([string] $Line, [datetime] $Now)

    if ($Line -match 'ttl=|time[=<]') {
        if ($script:Lost -gt 0) {
            Get-OutageRecord -Now $Now -Suffix ''
            $script:Lost = 0
        }
        $script:SeenReply = $true
    }
    else {
        if ($script:Lost -eq 0) { $script:LostSince = $Now }
        $script:Lost++
    }
}

function Format-PingLine {
    # Returns a record (see ConvertTo-PingRecord) for the line, followed by
    # an outage record when one is due.
    #
    # Native ping output has three parts: a header line, one line per probe,
    # and a summary that starts after a blank line. Only probe lines get a
    # timestamp. Left alone inside the probe section: indented lines, which
    # continue the line above (e.g. the route from -r/-R), and a "PING ..."
    # line, which is the real header when Linux ping -v prints a line before
    # it. Splitting on the blank line instead of matching text keeps this
    # working with localized ping output.
    param([string] $Line)

    $now = Get-Now
    $blank = [string]::IsNullOrWhiteSpace($Line)
    switch ($script:Section) {
        'Header' {
            if (-not $blank) { $script:Section = 'Probes' }
            ConvertTo-PingRecord -Timestamp $now -Type 'Header' -Line $Line
        }
        'Probes' {
            if ($blank) {
                # Replies were still being lost when the statistics began.
                if ($script:ShowOutages -and $script:SeenReply -and $script:Lost -gt 0) {
                    Get-OutageRecord -Now $now -Suffix ' (no reply since)'
                }
                $script:Section = 'Summary'
                ConvertTo-PingRecord -Timestamp $now -Type 'Summary' -Line $Line
            }
            elseif ($Line -clike 'PING *') {
                ConvertTo-PingRecord -Timestamp $now -Type 'Header' -Line $Line
            }
            elseif ($Line -match '^\s') {
                ConvertTo-PingRecord -Timestamp $now -Type 'Probe' -Line $Line
            }
            else {
                ConvertTo-PingRecord -Timestamp $now -Type 'Probe' -Line $Line `
                    -Text ('{0} {1}' -f (Format-Timestamp -Date $now), $Line)
                if ($script:ShowOutages) { Trace-Outage -Line $Line -Now $now }
            }
        }
        'Summary' {
            # Windows ping -t prints interim statistics on Ctrl+Break, then
            # carries on pinging.
            if ($Line -like 'Control-Break*') { $script:Section = 'Probes' }
            ConvertTo-PingRecord -Timestamp $now -Type 'Summary' -Line $Line
        }
    }
}

function ConvertTo-PingOutput {
    # What goes down the pipeline: the text, or with -AsObject an object per
    # record, without the display text. New-Object rather than a
    # [pscustomobject] cast, which Constrained Language Mode doesn't allow.
    param([object[]] $Record)
    foreach ($item in $Record) {
        if ($script:AsObject) {
            New-Object -TypeName PSObject -Property ([ordered]@{
                Timestamp = $item.Timestamp; Type = $item.Type; Line = $item.Line })
        }
        else {
            $item.Text
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

function Write-LogLine {
    # Appends the records' text to the -LogFile log, if there is one.
    param([object[]] $Record)
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -ErrorAction Stop `
            -Value @(foreach ($item in $Record) { $item.Text })
    }
}

# --- Arguments ---------------------------------------------------------------

if ($args.Count -eq 1 -and "$($args[0])" -eq '-Version') {
    # -LiteralPath: with -Path, brackets in a folder name act as wildcards.
    $match = Select-String -LiteralPath $PSCommandPath -Pattern '^\.VERSION\s+(\S+)' |
        Select-Object -First 1
    'Invoke-PingStamp {0}' -f $match.Matches[0].Groups[1].Value
    exit 0
}

# -LogFile, -AsObject, -Utc, -NoOutages and -HideDrops are this script's own
# options: take them out of the arguments, which are otherwise all for ping.
# They may appear anywhere. "-LogFile:path" arrives as "-LogFile:" followed
# by the path.
$script:LogPath = $null
$hideDrops = $false
$remaining = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ("$($args[$i])" -eq '-AsObject') {
        $script:AsObject = $true
    }
    elseif ("$($args[$i])" -eq '-Utc') {
        $script:Utc = $true
    }
    elseif ("$($args[$i])" -eq '-NoOutages') {
        $script:ShowOutages = $false
    }
    elseif ("$($args[$i])" -eq '-HideDrops') {
        $hideDrops = $true
    }
    elseif ("$($args[$i])" -in '-LogFile', '-LogFile:') {
        if ($i + 1 -ge $args.Count) {
            $Host.UI.WriteErrorLine('-LogFile needs a file path.')
            exit 2
        }
        $i++
        $script:LogPath = "$($args[$i])"
    }
    else {
        $remaining += , $args[$i]
    }
}

if ($remaining.Count -eq 0) {
    $Host.UI.WriteErrorLine('Usage: Invoke-PingStamp.ps1 [-LogFile <path>] [-AsObject] [-Utc] [-NoOutages]')
    $Host.UI.WriteErrorLine('                            [-HideDrops] [ping options] <hostname | IPv4 address>')
    $Host.UI.WriteErrorLine('All other arguments are passed to ping. For details, run:')
    $Host.UI.WriteErrorLine("  Get-Help '$PSCommandPath' -Full")
    exit 2
}

if ($script:LogPath) {
    # Fail now, before pinging, if the log can't be written. Appending
    # nothing creates the file if needed and leaves an existing one as it is.
    try {
        Add-Content -LiteralPath $script:LogPath -Value @() -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        $Host.UI.WriteErrorLine("Cannot write to log file '$($script:LogPath)': $($_.Exception.Message)")
        exit 2
    }
}

# PowerShell has already parsed the arguments: "-n" arrives as a string, but
# "10" as an int, "0.2" as a double and "a,b" as an array. Turn them back into
# text without the current culture's decimal separator.
$pingArguments = foreach ($arg in $remaining) {
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

    # Linux ping (iputils) prints nothing for a lost reply, so timestamps
    # couldn't show when a drop happened. -O makes it print "no answer yet
    # for icmp_seq=N". It arrived in iputils s20121221; other pings fail
    # "ping -V" or don't mention iputils. A second -O, if the user passed
    # one too, is harmless. Windows and macOS ping report lost replies
    # anyway.
    if (-not $hideDrops) {
        $pingVersion = (& $pingPath -V 2>&1) -join ' '
        if ($pingVersion -match 'iputils' -and $pingVersion -match '(\d{8})' -and
            [int]$Matches[1] -ge 20121221) {
            $pingArguments = @('-O') + $pingArguments
        }
    }
}

# --- Run ping and stamp its output -------------------------------------------

if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    # Constrained Language Mode (AppLocker/WDAC) blocks the Process class used
    # below. A plain pipeline gives the same output, except that Ctrl+C
    # discards ping's closing statistics.
    & $pingPath @pingArguments | ForEach-Object {
        $records = @(Format-PingLine -Line $_)
        Write-LogLine -Record $records
        ConvertTo-PingOutput -Record $records
    }
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
$formatted = $null  # the records for $pending, once formatted
$logged = $false    # $formatted has gone to the log
$sectionBefore = $script:Section
$completed = $false
$exitCode = 1       # replaced by ping's exit code; stays 1 if this script fails
try {
    while ($true) {
        $sectionBefore = $script:Section
        $formatted = $null
        $logged = $false
        $pending = $process.StandardOutput.ReadLine()
        if ($null -eq $pending) { break }
        $formatted = @(Format-PingLine -Line $pending)
        if ($sectionBefore -eq 'Probes' -and $script:Section -eq 'Summary') {
            # This blank line is the first thing ping prints after Ctrl+C.
            # PowerShell's own Ctrl+C handling lags slightly behind; pausing
            # lets its stop land here instead of part-way through the write
            # below, where the line may or may not have reached the screen.
            Start-Sleep -Milliseconds 100
        }
        Write-LogLine -Record $formatted
        $logged = $true
        ConvertTo-PingOutput -Record $formatted
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
            # pass the remaining lines to the host and the log, as text even
            # with -AsObject. Write-Output would silently end this block.
            if ($null -ne $pending) {
                # Stopped part-way through this line. If it wasn't formatted
                # yet, format it from the start.
                if ($null -eq $formatted) {
                    $script:Section = $sectionBefore
                    $formatted = @(Format-PingLine -Line $pending)
                }
                foreach ($record in $formatted) { $Host.UI.WriteLine($record.Text) }
                if (-not $logged) { Write-LogLine -Record $formatted }
            }
            while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
                $formatted = @(Format-PingLine -Line $line)
                foreach ($record in $formatted) { $Host.UI.WriteLine($record.Text) }
                Write-LogLine -Record $formatted
            }
        }
    }
    $process.Dispose()
}

exit $exitCode
