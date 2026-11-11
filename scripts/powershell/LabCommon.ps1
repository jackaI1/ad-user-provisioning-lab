# Shared helpers for the PowerShell lab scripts. Dot-sourced by the other scripts.
# PowerShell 7 runs on Windows, macOS and Linux. Samba commands run in the "dc"
# container through docker compose.

$script:LabRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:ComposeFile = Join-Path $script:LabRoot 'lab' 'docker-compose.yml'
$script:EnvFile = Join-Path $script:LabRoot 'lab' '.env'
$script:DefaultOutDir = Join-Path $script:LabRoot 'out'

function Get-LabSetting {
    param([string]$Name, [string]$Default = '')
    if (Test-Path $script:EnvFile) {
        foreach ($line in Get-Content $script:EnvFile) {
            if ($line -match "^\s*$Name=(.*)$") { return $Matches[1].Trim() }
        }
    }
    return $Default
}

$script:Realm = Get-LabSetting 'SAMBA_REALM' 'LAB.EXAMPLE'
$script:BaseDn = 'dc=' + ($script:Realm.ToLower() -replace '\.', ',dc=')
$script:AdminDn = "CN=Administrator,CN=Users,$script:BaseDn"
$script:AdminPassword = Get-LabSetting 'SAMBA_ADMIN_PASSWORD'

function Invoke-Dc {
    # Runs a command in the dc container. Returns ExitCode and Output (trimmed lines).
    param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Command)
    $raw = & docker compose -f $script:ComposeFile exec -T dc @Command 2>&1
    $lines = @($raw | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $lines }
}

function Test-LabUser {
    param([Parameter(Mandatory)][string]$Name)
    return (Invoke-Dc samba-tool user list).Output -contains $Name
}

function Test-LabGroup {
    param([Parameter(Mandatory)][string]$Name)
    return (Invoke-Dc samba-tool group list).Output -contains $Name
}

function Test-LabDn {
    # True when the object exists in the directory.
    param([Parameter(Mandatory)][string]$Dn)
    # Pass the arguments as an array. Bare "-w" and "-D" are read by PowerShell as its own
    # parameters (-w is ambiguous, -D is taken as -Debug), so the bind DN was silently dropped.
    $cmd = @('ldapsearch', '-x', '-LLL', '-H', 'ldap://127.0.0.1', '-D', $script:AdminDn,
        '-w', $script:AdminPassword, '-b', $Dn, '-s', 'base', 'dn')
    $r = Invoke-Dc @cmd
    return $r.ExitCode -eq 0
}

function New-LabPassword {
    # Random password that meets the default Samba complexity rules.
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(10)
    return 'Lab' + (-join ($bytes | ForEach-Object { $_.ToString('x2') })) + '!9'
}

function Save-LabPassword {
    # Appends "username<TAB>password" to the owner-only passwords file.
    param([string]$OutDir, [string]$Username, [string]$Password)
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $file = Join-Path $OutDir 'new-passwords.txt'
    if (-not (Test-Path $file)) {
        New-Item -ItemType File -Path $file | Out-Null
        if (-not $IsWindows) { & chmod 600 $file }
    }
    Add-Content -Path $file -Value "$Username`t$Password"
    return $file
}
