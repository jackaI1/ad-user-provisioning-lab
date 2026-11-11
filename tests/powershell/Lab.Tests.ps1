# Pester 5 tests for the PowerShell scripts. They run against the real Samba
# domain controller, so the lab must be running (see the README).
# Run: Invoke-Pester -Path tests/powershell

$script:Scripts = Join-Path $PSScriptRoot '..' '..' 'scripts' 'powershell'
. (Join-Path $script:Scripts 'LabCommon.ps1')
$script:Csv = Join-Path $PSScriptRoot '..' 'fixtures' 'ci-powershell.csv'
$script:OutDir = Join-Path ([System.IO.Path]::GetTempPath()) "lab-pester-$([guid]::NewGuid())"

AfterAll {
    if (Test-Path $script:OutDir) { Remove-Item -Recurse -Force $script:OutDir }
}

Describe 'Sync-LabUsers.ps1' {
    It 'creates the users and their group memberships' {
        & (Join-Path $script:Scripts 'Sync-LabUsers.ps1') -CsvPath $script:Csv -OutDir $script:OutDir
        Test-LabUser 'psci.alice' | Should -BeTrue
        Test-LabUser 'psci.carol' | Should -BeTrue
        (Invoke-Dc samba-tool group listmembers Finance).Output | Should -Contain 'psci.bob'
        (Invoke-Dc samba-tool group listmembers Printers).Output | Should -Contain 'psci.carol'
    }

    It 'writes one password line per new user and none on a second run' {
        $file = Join-Path $script:OutDir 'new-passwords.txt'
        (Get-Content $file).Count | Should -Be 3
        & (Join-Path $script:Scripts 'Sync-LabUsers.ps1') -CsvPath $script:Csv -OutDir $script:OutDir
        (Get-Content $file).Count | Should -Be 3
    }
}

Describe 'Reset-LabPassword.ps1' {
    It 'resets the password and writes the new one to the passwords file' {
        & (Join-Path $script:Scripts 'Reset-LabPassword.ps1') -Username 'psci.alice' -OutDir $script:OutDir
        $lines = Get-Content (Join-Path $script:OutDir 'new-passwords.txt')
        ($lines | Where-Object { $_ -like 'psci.alice*' }).Count | Should -Be 1
    }

    It 'refuses an unknown user' {
        { & (Join-Path $script:Scripts 'Reset-LabPassword.ps1') -Username 'psci.nobody' -OutDir $script:OutDir } |
            Should -Throw
    }
}

Describe 'Disable-LabUser.ps1' {
    It 'disables the account (userAccountControl bit 0x2 is set)' {
        & (Join-Path $script:Scripts 'Disable-LabUser.ps1') -Username 'psci.bob'
        $line = (Invoke-Dc samba-tool user show 'psci.bob').Output | Where-Object { $_ -match '^userAccountControl:' }
        ([int]($line -replace '\D', '') -band 2) | Should -Be 2
    }
}
