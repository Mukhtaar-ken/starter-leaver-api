function Invoke-ProvisioningAction {
    <#
    .SYNOPSIS
        Carries out the steps from Get-StarterAction or Get-LeaverAction through Microsoft Graph.

    .DESCRIPTION
        Checks it's signed in to the right tenant first, then runs each step in order and
        stops at the first failure. Supports -WhatIf, which shows the steps without doing them.
        Returns each step with Done = $true as it completes.

    .PARAMETER Action
        The steps to run, from Get-StarterAction or Get-LeaverAction.

    .PARAMETER Plan
        From Get-StarterPlan. Only needed when a step is CreateUser.

    .PARAMETER TenantId
        The tenant this run is meant for. Nothing happens if Graph is signed in anywhere else.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Action,
        [object]$Plan,
        [Parameter(Mandatory)] [string]$TenantId
    )

    Assert-ExpectedTenant -TenantId $TenantId

    # The user's ID, looked up once and reused (or set by CreateUser).
    $userId = $null

    foreach ($step in $Action) {
        $what = if ($step.Group) { "$($step.Action) '$($step.Group)'" } else { $step.Action }
        if (-not $PSCmdlet.ShouldProcess($step.Target, $what)) { continue }

        if ($step.Action -ne 'CreateUser' -and -not $userId) {
            $userId = (Get-EntraUserState -UserPrincipalName $step.Target).Id
            # Without an ID, the requests below would go to the wrong address. Stop instead.
            if (-not $userId) { throw "Can't find $($step.Target) in the tenant. Nothing more was changed." }
        }

        switch ($step.Action) {
            'CreateUser' {
                if (-not $Plan) { throw 'CreateUser needs -Plan.' }
                $body = @{
                    accountEnabled    = $true
                    displayName       = $Plan.DisplayName
                    givenName         = $Plan.GivenName
                    surname           = $Plan.Surname
                    userPrincipalName = $Plan.UserPrincipalName
                    mailNickname      = $Plan.MailNickname
                    employeeId        = $Plan.EmployeeId
                    department        = $Plan.Department
                    passwordProfile   = @{ forceChangePasswordNextSignIn = $true; password = Get-RandomPassword }
                }
                if ($Plan.JobTitle) { $body.jobTitle = $Plan.JobTitle }

                $userId = (Invoke-MgGraphRequest -Method POST -Uri 'v1.0/users' -Body $body -OutputType PSObject).id
                if (-not $userId) { throw "Creating $($step.Target) didn't return an ID. Stopping before any group changes." }
            }
            'EnableAccount'  { Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$userId" -Body @{ accountEnabled = $true } | Out-Null }
            'DisableAccount' { Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$userId" -Body @{ accountEnabled = $false } | Out-Null }
            'RevokeSessions' { Invoke-MgGraphRequest -Method POST  -Uri "v1.0/users/$userId/revokeSignInSessions" | Out-Null }
            'AddToGroup' {
                $groupId = Get-GraphGroupId -Name $step.Group
                $ref     = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId" }
                Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$groupId/members/`$ref" -Body $ref | Out-Null
            }
            'RemoveFromGroup' {
                $groupId = Get-GraphGroupId -Name $step.Group
                Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/groups/$groupId/members/$userId/`$ref" | Out-Null
            }
            default { throw "Unknown action '$($step.Action)'." }
        }

        [pscustomobject]@{ Action = $step.Action; Target = $step.Target; Group = $step.Group; Done = $true }
    }
}
