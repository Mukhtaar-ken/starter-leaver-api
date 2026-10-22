function Invoke-ProvisioningAction {
    <#
    .SYNOPSIS
        Carries out the steps from Get-StarterAction or Get-LeaverAction through Microsoft Graph.

    .DESCRIPTION
        Checks it's signed in to the right tenant first, then runs each step in order and
        stops at the first failure. Supports -WhatIf, which shows the steps without doing them.
        Returns each step with Done = $true as it completes.

        Entra can be a few seconds behind itself, so a step that Graph says is already done
        ("already exists", or a member that's already gone) counts as done, and a user that
        isn't visible yet is waited for briefly. See Invoke-GraphStep.

    .PARAMETER Action
        The steps to run, from Get-StarterAction or Get-LeaverAction.

    .PARAMETER Plan
        From Get-StarterPlan. Only needed when a step is CreateUser.

    .PARAMETER UserId
        The user's ID, if the caller already looked them up. Saves a second lookup, which
        could reach a copy of Entra that doesn't show the user yet.

    .PARAMETER TenantId
        The tenant this run is meant for. Nothing happens if Graph is signed in anywhere else.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]]$Action,
        [object]$Plan,
        [string]$UserId,
        [Parameter(Mandatory)] [string]$TenantId
    )

    Assert-ExpectedTenant -TenantId $TenantId

    # Error text from Graph when a user or member isn't there (or isn't visible yet).
    $notFound = 'does not exist|ResourceNotFound|NotFound'

    # The user's ID: passed in, looked up once, or set by CreateUser.
    $userId = $UserId

    foreach ($step in $Action) {
        $what = if ($step.Group) { "$($step.Action) '$($step.Group)'" } else { $step.Action }
        if (-not $PSCmdlet.ShouldProcess($step.Target, $what)) { continue }

        if ($step.Action -ne 'CreateUser' -and -not $userId) {
            $userId = (Wait-EntraUser -UserPrincipalName $step.Target).Id
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

                $created = Invoke-GraphStep -AlreadyDoneIf 'already exists' -Request {
                    Invoke-MgGraphRequest -Method POST -Uri 'v1.0/users' -Body $body -OutputType PSObject
                }

                if ($created) {
                    $userId = $created.id
                }
                else {
                    # The address is taken. Most likely by an earlier run that Entra hadn't shown us yet,
                    # but it could be someone else, so check it's the same employee before carrying on.
                    $found = Wait-EntraUser -UserPrincipalName $Plan.UserPrincipalName
                    if (-not $found) { throw "Graph says $($Plan.UserPrincipalName) exists, but it can't be found. Nothing more was changed." }
                    if ($found.EmployeeId -ne $Plan.EmployeeId) {
                        throw "$($Plan.UserPrincipalName) already belongs to employee '$($found.EmployeeId)', not '$($Plan.EmployeeId)'. Needs a person to choose a different address."
                    }
                    $userId = $found.Id
                }
                if (-not $userId) { throw "Creating $($step.Target) didn't return an ID. Stopping before any group changes." }
            }
            'EnableAccount' {
                $null = Invoke-GraphStep -RetryIf $notFound -Request {
                    Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$userId" -Body @{ accountEnabled = $true }
                }
            }
            'DisableAccount' {
                $null = Invoke-GraphStep -RetryIf $notFound -Request {
                    Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/users/$userId" -Body @{ accountEnabled = $false }
                }
            }
            'RevokeSessions' {
                $null = Invoke-GraphStep -RetryIf $notFound -Request {
                    Invoke-MgGraphRequest -Method POST -Uri "v1.0/users/$userId/revokeSignInSessions"
                }
            }
            'AddToGroup' {
                $groupId = Get-GraphGroupId -Name $step.Group
                $ref     = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId" }
                # "already exist" = they're already a member. Not found = a brand-new user not visible yet.
                $null = Invoke-GraphStep -AlreadyDoneIf 'already exist' -RetryIf $notFound -Request {
                    Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$groupId/members/`$ref" -Body $ref
                }
            }
            'RemoveFromGroup' {
                $groupId = Get-GraphGroupId -Name $step.Group
                # Not found = they're already out of the group.
                $null = Invoke-GraphStep -AlreadyDoneIf $notFound -Request {
                    Invoke-MgGraphRequest -Method DELETE -Uri "v1.0/groups/$groupId/members/$userId/`$ref"
                }
            }
            default { throw "Unknown action '$($step.Action)'." }
        }

        [pscustomobject]@{ Action = $step.Action; Target = $step.Target; Group = $step.Group; Done = $true }
    }
}
