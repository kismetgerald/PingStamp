#Requires -Version 5.1
<#
.SYNOPSIS
    Formats scripted ping output with Invoke-PingStamp.ps1's own functions.

.DESCRIPTION
    Used by Test-InvokePingStamp.ps1 to test outage lines on every platform.
    Windows always runs System32\PING.EXE, so a fake ping can't stand in
    there; instead this loads the script's functions and script-scope
    settings, then passes each line of LinesFile through Format-PingLine as
    if ping had printed it, 0.2 s apart. It prints each record's text, or
    with -Records its Type and Line, separated by a tab.
#>
param(
    [string] $ScriptPath,
    [string] $LinesFile,
    [switch] $NoOutages,
    [switch] $Records
)

Set-StrictMode -Version Latest

$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
foreach ($statement in $ast.EndBlock.Statements) {
    $isFunction = $statement -is [System.Management.Automation.Language.FunctionDefinitionAst]
    $isSetting = $statement -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $statement.Left.Extent.Text -like '$script:*'
    if ($isFunction -or $isSetting) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
if ($NoOutages) { $script:ShowOutages = $false }

foreach ($line in @(Get-Content -Path $LinesFile)) {
    Start-Sleep -Milliseconds 200
    foreach ($record in @(Format-PingLine -Line $line)) {
        if ($Records) { "$($record.Type)`t$($record.Line)" } else { $record.Text }
    }
}
