# Run with:  Invoke-Pester .\tests -Output Detailed   (needs Pester 5)
# The web layer: right status code for each outcome, and no internal details leaked to the caller.

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Provisioning\Provisioning.psd1" -Force
    $groups = Get-Content "$PSScriptRoot\..\config\departments.json" -Raw | ConvertFrom-Json
    $tenant = '11111111-1111-1111-1111-111111111111'
    $jane   = @{ firstName = 'Jane'; lastName = 'Doe'; employeeId = 'E1001'; department = 'Sales' }

    function Send ($Kind, $Body) {
        Invoke-ProvisioningHttpRequest -Kind $Kind -Body $Body -TenantId $tenant -Domain 'contoso.example' `
            -DepartmentGroups $groups -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-ProvisioningHttpRequest' {

    It 'returns 400 for a body that is not JSON' {
        (Send Starter '{not json').StatusCode | Should -Be 400
    }

    It 'returns 400 and names the missing fields' {
        $r = Send Starter @{ firstName = 'Jane' }
        $r.StatusCode | Should -Be 400
        $r.Body.error | Should -Be 'Missing: lastName, employeeId, department.'
    }

    It 'accepts the body as JSON text, as well as an object' {
        Mock Invoke-StarterRequest -ModuleName Provisioning { }
        (Send Starter ($jane | ConvertTo-Json)).StatusCode | Should -Be 200
    }

    It 'returns 200 with the steps taken' {
        Mock Invoke-StarterRequest -ModuleName Provisioning {
            [pscustomobject]@{ Action = 'CreateUser'; Group = $null }
            [pscustomobject]@{ Action = 'AddToGroup'; Group = 'Sales Team' }
        }
        $r = Send Starter $jane
        $r.StatusCode  | Should -Be 200
        $r.Body.status | Should -Be 'done'
        $r.Body.steps  | Should -Be @('CreateUser', "AddToGroup 'Sales Team'")
    }

    It 'returns 200 "nothing to do" when it was already done' {
        Mock Invoke-StarterRequest -ModuleName Provisioning { }
        (Send Starter $jane).Body.status | Should -Be 'nothing to do'
    }

    It 'returns 400 for an unknown department' {
        Mock Invoke-StarterRequest -ModuleName Provisioning { throw "Unknown department 'Marketing'." }
        (Send Starter $jane).StatusCode | Should -Be 400
    }

    It 'returns 409 when the address belongs to someone else' {
        Mock Invoke-StarterRequest -ModuleName Provisioning { throw "jane.doe@contoso.example already belongs to employee 'E9999'." }
        (Send Starter $jane).StatusCode | Should -Be 409
    }

    It 'returns 404 for an unknown leaver' {
        Mock Invoke-LeaverRequest -ModuleName Provisioning { throw 'No account found for this leaver.' }
        (Send Leaver @{ employeeId = 'E4040' }).StatusCode | Should -Be 404
    }

    It 'returns 500 without leaking the internal error' {
        Mock Invoke-LeaverRequest -ModuleName Provisioning { throw 'Graph said: token for tenant 1234 expired at line 42' }
        $r = Send Leaver @{ employeeId = 'E1001' }
        $r.StatusCode | Should -Be 500
        $r.Body.error | Should -Not -Match 'token|tenant|line'
    }
}
