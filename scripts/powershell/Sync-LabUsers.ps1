<#
.SYNOPSIS
Creates OUs, groups, users and group memberships in the Samba lab from a CSV file.

.DESCRIPTION
CSV columns: username, given_name, surname, ou, groups
  ou      OU (folder) to put the user in. Blank = the default Users folder.
  groups  Group names separated by ";". Missing groups are created.
Existing objects are left alone, so running it again is safe. New passwords are
written to out/new-passwords.txt (readable by you only).

.EXAMPLE
./Sync-LabUsers.ps1 -CsvPath ../../examples/users.example.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$OutDir = $script:DefaultOutDir
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'LabCommon.ps1')

function Ensure-LabOu {
    param([string]$Name)
    if (Test-LabDn "OU=$Name,$script:BaseDn") { return }
    $r = Invoke-Dc samba-tool ou create "OU=$Name,$script:BaseDn"
    if ($r.ExitCode -ne 0) { throw "Could not create OU ${Name}: $($r.Output -join ' ')" }
    Write-Host "created OU: $Name"
}

function Ensure-LabGroup {
    param([string]$Name)
    if (Test-LabGroup $Name) { return }
    $r = Invoke-Dc samba-tool group add $Name
    if ($r.ExitCode -ne 0) { throw "Could not create group ${Name}: $($r.Output -join ' ')" }
    Write-Host "created group: $Name"
}

function Add-LabMember {
    param([string]$Group, [string]$Username)
    $members = (Invoke-Dc samba-tool group listmembers $Group).Output
    if ($members -contains $Username) { return }
    $r = Invoke-Dc samba-tool group addmembers $Group $Username
    if ($r.ExitCode -ne 0) { Write-Warning "Could not add ${Username} to ${Group}: $($r.Output -join ' ')" }
    else { Write-Host "  $Username added to $Group" }
}

$rows = Import-Csv -Path $CsvPath
foreach ($row in $rows) {
    $username = "$($row.username)".Trim()
    if ($username -notmatch '^[a-z][a-z0-9._-]{1,19}$') { throw "Bad username in CSV: '$username'" }
    $ou = "$($row.ou)".Trim()

    if ($ou) { Ensure-LabOu $ou }

    if (Test-LabUser $username) {
        Write-Host "exists: $username"
    }
    else {
        $pw = New-LabPassword
        $extra = @("--given-name=$($row.given_name)", "--surname=$($row.surname)", '--must-change-at-next-login')
        if ($ou) { $extra += "--userou=OU=$ou" }
        $cmd = @('samba-tool', 'user', 'create', $username, $pw) + $extra
        $r = Invoke-Dc @cmd
        if ($r.ExitCode -ne 0) { throw "Could not create ${username}: $($r.Output -join ' ')" }
        Save-LabPassword -OutDir $OutDir -Username $username -Password $pw | Out-Null
        Write-Host "created user: $username"
    }

    $groups = "$($row.groups)".Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($group in $groups) {
        Ensure-LabGroup $group
        Add-LabMember -Group $group -Username $username
    }
}

Write-Host "Done. New passwords (if any) are in $(Join-Path $OutDir 'new-passwords.txt')"
