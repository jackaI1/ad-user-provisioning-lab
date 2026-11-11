<#
.SYNOPSIS
Disables the accounts of people who have left. Disabled accounts cannot sign in.
Nothing is deleted, so an account can be enabled again later.

.EXAMPLE
./Disable-LabUser.ps1 -Username jordan.lee, sam.patel
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Username
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LabCommon.ps1')

foreach ($name in $Username) {
    if (-not (Test-LabUser $name)) { throw "No such user: $name (nothing was changed)" }
}
foreach ($name in $Username) {
    $r = Invoke-Dc samba-tool user disable $name
    if ($r.ExitCode -ne 0) { throw "Could not disable ${name}: $($r.Output -join ' ')" }
    Write-Host "disabled: $name"
}
