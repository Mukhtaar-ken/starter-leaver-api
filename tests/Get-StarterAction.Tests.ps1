# Run with:  Invoke-Pester .\tests -Output Detailed   (needs Pester 5)
# The key idea: running the same request twice must not do anything twice (idempotency).

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Provisioning\Provisioning.psd1" -Force
    $groups = Get-Content "$PSScriptRoot\..\config\departments.json" -Raw | ConvertFrom-Json
    $plan   = Get-StarterPlan -FirstName 'Jane' -LastName 'Doe' -EmployeeId 'E1001' -Department 'Sales' `
        -Domain 'contoso.example' -DepartmentGroups $groups

    # A fake "what's already in Entra" account.
    function New-ExistingUser ($EmployeeId = 'E1001', $Enabled = $true, $Groups = @()) {
        [pscustomobject]@{
            UserPrincipalName = 'jane.doe@contoso.example'
            EmployeeId        = $EmployeeId
            AccountEnabled    = $Enabled
            Groups            = $Groups
        }
    }
}

Describe 'Get-StarterAction' {

    It 'creates the account and adds every group when nothing exists yet' {
        $actions = Get-StarterAction -Plan $plan -ExistingUser $null

        ($actions.Action -join ',') | Should -Be 'CreateUser,AddToGroup,AddToGroup'
        ($actions.Group | Where-Object { $_ }) | Should -Be @('All Staff', 'Sales Team')
    }

    It 'does nothing when the same request is sent again' {
        $existing = New-ExistingUser -Groups @('All Staff', 'Sales Team')
        Get-StarterAction -Plan $plan -ExistingUser $existing | Should -BeNullOrEmpty
    }

    It 'only adds the groups that are missing' {
        $existing = New-ExistingUser -Groups @('All Staff')
        $actions  = Get-StarterAction -Plan $plan -ExistingUser $existing

        $actions.Action | Should -Be 'AddToGroup'
        $actions.Group  | Should -Be 'Sales Team'
    }

    It 'turns a returning employee back on' {
        $existing = New-ExistingUser -Enabled $false -Groups @('All Staff', 'Sales Team')
        (Get-StarterAction -Plan $plan -ExistingUser $existing).Action | Should -Be 'EnableAccount'
    }

    It 'stops when the address already belongs to a different person' {
        $someoneElse = New-ExistingUser -EmployeeId 'E9999'
        { Get-StarterAction -Plan $plan -ExistingUser $someoneElse } | Should -Throw "*already belongs to employee 'E9999'*"
    }
}
