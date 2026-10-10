# Run with:  Invoke-Pester .\tests -Output Detailed   (needs Pester 5)

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Provisioning\Provisioning.psd1" -Force
    $groups = Get-Content "$PSScriptRoot\..\config\departments.json" -Raw | ConvertFrom-Json

    # Builds a plan with sensible defaults; tests override only what they care about.
    function New-TestPlan {
        param($FirstName = 'Jane', $LastName = 'Doe', $EmployeeId = 'E1001', $Department = 'Sales')
        Get-StarterPlan -FirstName $FirstName -LastName $LastName -EmployeeId $EmployeeId `
            -Department $Department -Domain 'contoso.example' -DepartmentGroups $groups
    }
}

Describe 'Get-StarterPlan' {

    It 'builds the sign-in address as first.last@domain' {
        (New-TestPlan).UserPrincipalName | Should -Be 'jane.doe@contoso.example'
    }

    It 'gives the groups for the department' {
        (New-TestPlan -Department 'Finance').Groups | Should -Be @('All Staff', 'Finance Team')
    }

    It 'removes spaces, hyphens and apostrophes from the address' {
        (New-TestPlan -FirstName 'Mary Ann' -LastName "O'Brien-Smith").UserPrincipalName |
            Should -Be 'maryann.obriensmith@contoso.example'
    }

    It 'removes accents from the address but keeps them in the display name' {
        # Built from character codes so the test file itself stays plain ASCII.
        $sian = 'Si' + [char]0x00E2 + 'n'   # Sian with a circumflex on the a
        $plan = New-TestPlan -FirstName $sian -LastName 'Jones'

        $plan.UserPrincipalName | Should -Be 'sian.jones@contoso.example'
        $plan.DisplayName       | Should -Be "$sian Jones"
    }

    It 'trims stray spaces from the names' {
        (New-TestPlan -FirstName '  Jane ' -LastName ' Doe  ').DisplayName | Should -Be 'Jane Doe'
    }

    It 'refuses an unknown department' {
        { New-TestPlan -Department 'Marketing' } | Should -Throw "*Unknown department 'Marketing'*"
    }

    It 'refuses a name with no usable letters' {
        { New-TestPlan -FirstName '123' } | Should -Throw "*Can't build a sign-in name*"
    }

    It 'refuses an employee ID with odd characters' {
        { New-TestPlan -EmployeeId 'E1001; drop' } | Should -Throw
    }
}
