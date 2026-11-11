<#
.SYNOPSIS
Sets a new random password for one lab user and makes them change it at the next sign-in.

.EXAMPLE
./Reset-LabPassword.ps1 -Username jordan.lee
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Username,
    [string]$OutDir = $script:DefaultOutDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LabCommon.ps1')

if (-not (Test-LabUser $Username)) { throw "No such user: $Username" }

$pw = New-LabPassword
$r = Invoke-Dc samba-tool user setpassword $Username "--newpassword=$pw" --must-change-at-next-login
if ($r.ExitCode -ne 0) { throw "Could not reset password for ${Username}: $($r.Output -join ' ')" }
$file = Save-LabPassword -OutDir $OutDir -Username $Username -Password $pw
Write-Host "Password reset for $Username. The new password is in $file"
