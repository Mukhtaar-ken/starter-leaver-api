# Run with:  Invoke-Pester .\tests -Output Detailed   (needs Pester 5)

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Provisioning\Provisioning.psd1" -Force

    function New-ExistingUser ($Enabled = $true, $Groups = @('All Staff', 'Sales Team')) {
        [pscustomobject]@{
            UserPrincipalName = 'jane.doe@contoso.example'
            EmployeeId        = 'E1001'
            AccountEnabled    = $Enabled
            Groups            = $Groups
        }
    }
}

Describe 'Get-LeaverAction' {

    It 'blocks sign-in first, then ends sessions, then removes groups' {
        $actions = Get-LeaverAction -ExistingUser (New-ExistingUser)
        ($actions.Action -join ',') | Should -Be 'DisableAccount,RevokeSessions,RemoveFromGroup,RemoveFromGroup'
    }

    It 'never deletes the account' {
        (Get-LeaverAction -ExistingUser (New-ExistingUser)).Action | Should -Not -Contain 'DeleteUser'
    }

    It 'does nothing when the leaver is already fully closed down' {
        Get-LeaverAction -ExistingUser (New-ExistingUser -Enabled $false -Groups @()) | Should -BeNullOrEmpty
    }

    It 'only removes groups when the account is already disabled' {
        $actions = Get-LeaverAction -ExistingUser (New-ExistingUser -Enabled $false -Groups @('All Staff'))
        $actions.Action | Should -Be 'RemoveFromGroup'
    }

    It 'stops when the leaver cannot be found' {
        { Get-LeaverAction -ExistingUser $null } | Should -Throw '*No account found*'
    }
}
