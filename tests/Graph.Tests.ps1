# Run with:  Invoke-Pester .\tests -Output Detailed   (needs Pester 5)
# Never talks to a real tenant. Microsoft Graph is replaced with mocks that record what would have been sent.

BeforeAll {
    Import-Module "$PSScriptRoot\..\src\Provisioning\Provisioning.psd1" -Force

    # Pester can only mock a command that exists. If the Graph module isn't installed
    # (as on the CI machine), create stand-ins with the same parameter names.
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        function global:Invoke-MgGraphRequest { [CmdletBinding()] param($Method, $Uri, $Body, $OutputType, $Headers) }
        function global:Get-MgContext { [CmdletBinding()] param() }
    }

    $tenant = '11111111-1111-1111-1111-111111111111'
    $groups = Get-Content "$PSScriptRoot\..\config\departments.json" -Raw | ConvertFrom-Json
    $starter = @{
        FirstName = 'Jane'; LastName = 'Doe'; EmployeeId = 'E1001'; Department = 'Sales'
        Domain = 'contoso.example'; DepartmentGroups = $groups; TenantId = $tenant
    }

    # Any request that would change something.
    $isWrite = { $Method -ne 'GET' }

    # An error shaped like Invoke-MgGraphRequest's: a general message, with Graph's own text in ErrorDetails.
    function New-GraphError ([string]$GraphMessage) {
        $record = [System.Management.Automation.ErrorRecord]::new(
            [Exception]::new('Response status code does not indicate success: BadRequest (Bad Request).'),
            'GraphError', 'InvalidOperation', $null)
        $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($GraphMessage)
        $record
    }

    # The retry waits are real seconds. Skip them in tests (the count of waits is still checked).
    Mock Start-Sleep -ModuleName Provisioning { }
}

Describe 'Tenant guard' {

    It 'changes nothing when signed in to a different tenant' {
        Mock Get-MgContext -ModuleName Provisioning { [pscustomobject]@{ TenantId = '99999999-9999-9999-9999-999999999999' } }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning { }

        $step = [pscustomobject]@{ Action = 'DisableAccount'; Target = 'jane.doe@contoso.example'; Group = $null }
        { Invoke-ProvisioningAction -Action $step -TenantId $tenant -Confirm:$false } | Should -Throw '*Nothing was changed*'

        Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0
    }

    It 'stops instead of sending a request with a blank user ID' {
        Mock Get-MgContext -ModuleName Provisioning { [pscustomobject]@{ TenantId = $tenant } }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter $isWrite { }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' } { [pscustomobject]@{ value = @() } }

        $step = [pscustomobject]@{ Action = 'DisableAccount'; Target = 'nobody@contoso.example'; Group = $null }
        { Invoke-ProvisioningAction -Action $step -TenantId $tenant -Confirm:$false } | Should -Throw "*Can't find*"
        Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter $isWrite
    }

    It 'stops with sign-in instructions when not signed in at all' {
        Mock Get-MgContext -ModuleName Provisioning { $null }
        { Invoke-StarterRequest @starter -Confirm:$false } | Should -Throw '*Connect-MgGraph*'
    }
}

Describe 'Invoke-StarterRequest' {

    BeforeEach {
        Mock Get-MgContext -ModuleName Provisioning { [pscustomobject]@{ TenantId = $tenant } }

        # Pester uses the LAST matching mock, so the catch-all for writes goes first.
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter $isWrite { }

        # Each group "exists" with the ID id-<name>.
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/groups?*' } {
            $name = [regex]::Match($Uri, "displayName eq '([^']+)'").Groups[1].Value
            [pscustomobject]@{ value = @([pscustomobject]@{ id = "id-$name"; displayName = $name }) }
        }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/users' } {
            [pscustomobject]@{ id = 'new-user-id' }
        }
    }

    Context 'for someone new' {
        BeforeEach {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                [pscustomobject]@{ value = @() }
            }
        }

        It 'creates the account with a one-time password they must change' {
            $null = Invoke-StarterRequest @starter -Confirm:$false

            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/users' -and
                $Body.userPrincipalName -eq 'jane.doe@contoso.example' -and $Body.employeeId -eq 'E1001' -and
                $Body.passwordProfile.forceChangePasswordNextSignIn -and $Body.passwordProfile.password.Length -ge 16
            }
        }

        It 'adds the new account to each department group' {
            $null = Invoke-StarterRequest @starter -Confirm:$false

            foreach ($g in 'All Staff', 'Sales Team') {
                Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Uri -eq "v1.0/groups/id-$g/members/`$ref" -and
                    $Body.'@odata.id' -like '*/directoryObjects/new-user-id'
                }
            }
        }

        It 'looks the user up with a plain filter, not the search index' {
            $null = Invoke-StarterRequest @starter -Confirm:$false

            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like 'v1.0/users?*userPrincipalName*' -and
                ($Headers.ConsistencyLevel -eq 'eventual' -or $Uri -like '*$count=true*')
            }
        }

        It 'never returns the password' {
            $done = Invoke-StarterRequest @starter -Confirm:$false
            ($done | ConvertTo-Json -Depth 5) | Should -Not -Match 'password'
        }

        It 'changes nothing with -WhatIf' {
            Invoke-StarterRequest @starter -WhatIf
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter $isWrite
        }
    }

    Context 'for someone already set up' {
        BeforeEach {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{
                    id = 'u1'; userPrincipalName = 'jane.doe@contoso.example'; employeeId = 'E1001'; accountEnabled = $true }) }
            }
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users/u1/memberOf*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{ displayName = 'All Staff' }, [pscustomobject]@{ displayName = 'Sales Team' }) }
            }
        }

        It 'changes nothing when the same request is sent again' {
            Invoke-StarterRequest @starter -Confirm:$false | Should -BeNullOrEmpty
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter $isWrite
        }
    }
}

Describe 'Invoke-LeaverRequest' {

    BeforeEach {
        Mock Get-MgContext -ModuleName Provisioning { [pscustomobject]@{ TenantId = $tenant } }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/groups?*' } {
            [pscustomobject]@{ value = @([pscustomobject]@{ id = 'id-All Staff'; displayName = 'All Staff' }) }
        }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter $isWrite { }
    }

    Context 'for an active employee' {
        BeforeEach {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{
                    id = 'u1'; userPrincipalName = 'jane.doe@contoso.example'; employeeId = 'E1001'; accountEnabled = $true }) }
            }
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users/u1/memberOf*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{ displayName = 'All Staff' }) }
            }

            $null = Invoke-LeaverRequest -EmployeeId 'E1001' -TenantId $tenant -Confirm:$false
        }

        It 'blocks sign-in' {
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -eq 'v1.0/users/u1' -and $Body.accountEnabled -eq $false
            }
        }

        It 'ends open sessions' {
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/users/u1/revokeSignInSessions'
            }
        }

        It 'removes group memberships but never deletes the account' {
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/id-All Staff/members/u1/$ref'
            }
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -like 'v1.0/users/*'
            }
        }
    }

    It 'changes nothing for an unknown employee ID' {
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
            [pscustomobject]@{ value = @() }
        }

        { Invoke-LeaverRequest -EmployeeId 'E4040' -TenantId $tenant -Confirm:$false } | Should -Throw '*No account found*'
        Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter $isWrite
    }
}

Describe 'Allowing for Entra being a few seconds behind' {
    # Found in the live test, 22 Oct 2026: a request sent a second after another can reach
    # a copy of Entra that doesn't show the first one's changes yet.

    BeforeEach {
        Mock Get-MgContext -ModuleName Provisioning { [pscustomobject]@{ TenantId = $tenant } }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter $isWrite { }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/groups?*' } {
            $name = [regex]::Match($Uri, "displayName eq '([^']+)'").Groups[1].Value
            [pscustomobject]@{ value = @([pscustomobject]@{ id = "id-$name"; displayName = $name }) }
        }
        Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users/*/memberOf*' } {
            [pscustomobject]@{ value = @() }
        }
    }

    Context 'a starter sent again before Entra shows the first run' {
        BeforeEach {
            # The first lookup misses the user (lagging copy); the next one finds them.
            $script:lookups = 0
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                $script:lookups++
                if ($script:lookups -eq 1) { return [pscustomobject]@{ value = @() } }
                [pscustomobject]@{ value = @([pscustomobject]@{
                    id = 'u1'; userPrincipalName = 'jane.doe@contoso.example'; employeeId = $script:owner; accountEnabled = $true }) }
            }
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/users' } {
                throw (New-GraphError 'Another object with the same value for property userPrincipalName already exists.')
            }
        }

        It 'carries on with the existing user when they are the same employee' {
            $script:owner = 'E1001'
            { Invoke-StarterRequest @starter -Confirm:$false } | Should -Not -Throw

            foreach ($g in 'All Staff', 'Sales Team') {
                Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Uri -eq "v1.0/groups/id-$g/members/`$ref" -and $Body.'@odata.id' -like '*/directoryObjects/u1'
                }
            }
        }

        It 'stops, changing nothing more, when the address belongs to someone else' {
            $script:owner = 'E9999'
            { Invoke-StarterRequest @starter -Confirm:$false } | Should -Throw '*already belongs to*'

            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like 'v1.0/groups/*'
            }
        }
    }

    Context 'a starter who already exists' {
        BeforeEach {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{
                    id = 'u1'; userPrincipalName = 'jane.doe@contoso.example'; employeeId = 'E1001'; accountEnabled = $true }) }
            }
        }

        It 'counts "already a member" as done' {
            # memberOf showed no groups (lagging), but Graph says they're already in.
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -like 'v1.0/groups/*' } {
                throw (New-GraphError "One or more added object references already exist for the following modified properties: 'members'.")
            }
            { Invoke-StarterRequest @starter -Confirm:$false } | Should -Not -Throw
        }

        It 'still stops on any other Graph error' {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -like 'v1.0/groups/*' } {
                throw (New-GraphError 'Insufficient privileges to complete the operation.')
            }
            { Invoke-StarterRequest @starter -Confirm:$false } | Should -Throw
        }
    }

    Context 'a brand-new user not visible yet when adding groups' {
        BeforeEach {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                [pscustomobject]@{ value = @() }
            }
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -eq 'v1.0/users' } {
                [pscustomobject]@{ id = 'new-user-id' }
            }
        }

        It 'waits and tries again' {
            $script:adds = 0
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -like 'v1.0/groups/*' } {
                $script:adds++
                if ($script:adds -eq 1) { throw (New-GraphError "Resource 'new-user-id' does not exist or one of its queried reference-property objects are not present.") }
            }

            { Invoke-StarterRequest @starter -Confirm:$false } | Should -Not -Throw
            Should -Invoke Start-Sleep -ModuleName Provisioning -Times 1 -Exactly
            $script:adds | Should -Be 3   # All Staff twice (miss, then hit), Sales Team once
        }

        It 'gives up after 5 tries' {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'POST' -and $Uri -like 'v1.0/groups/*' } {
                throw (New-GraphError "Resource 'new-user-id' does not exist or one of its queried reference-property objects are not present.")
            }

            { Invoke-StarterRequest @starter -Confirm:$false } | Should -Throw
            Should -Invoke Start-Sleep -ModuleName Provisioning -Times 4 -Exactly   # 5 tries = 4 waits
        }
    }

    Context 'a leaver' {
        BeforeEach {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users?*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{
                    id = 'u1'; userPrincipalName = 'jane.doe@contoso.example'; employeeId = 'E1001'; accountEnabled = $true }) }
            }
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'GET' -and $Uri -like 'v1.0/users/u1/memberOf*' } {
                [pscustomobject]@{ value = @([pscustomobject]@{ displayName = 'All Staff' }) }
            }
        }

        It 'uses the ID it already found, with no second lookup' {
            $null = Invoke-LeaverRequest -EmployeeId 'E1001' -TenantId $tenant -Confirm:$false

            # `? because a bare ? in -like means "any one character", which would also match users/u1/memberOf.
            Should -Invoke Invoke-MgGraphRequest -ModuleName Provisioning -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and $Uri -like 'v1.0/users`?*'
            }
        }

        It 'counts "already out of the group" as done' {
            Mock Invoke-MgGraphRequest -ModuleName Provisioning -ParameterFilter { $Method -eq 'DELETE' } {
                throw (New-GraphError "Resource 'u1' does not exist or one of its queried reference-property objects are not present.")
            }
            { Invoke-LeaverRequest -EmployeeId 'E1001' -TenantId $tenant -Confirm:$false } | Should -Not -Throw
        }
    }
}

Describe 'Get-RandomPassword' {

    It 'is 24 characters with upper, lower, digit and symbol' {
        $p = InModuleScope Provisioning { Get-RandomPassword }
        $p.Length | Should -Be 24
        $p | Should -MatchExactly '[A-Z]'
        $p | Should -MatchExactly '[a-z]'
        $p | Should -Match '[0-9]'
        $p | Should -Match '[^A-Za-z0-9]'
    }

    It 'is different every time' {
        $a, $b = InModuleScope Provisioning { Get-RandomPassword; Get-RandomPassword }
        $a | Should -Not -Be $b
    }
}
