function Get-StarterAction {
    <#
    .SYNOPSIS
        Compares a starter plan with what already exists and lists only the steps still needed.

    .DESCRIPTION
        This is what makes the service safe to run twice (idempotent): if the account
        already exists and is set up, the list comes back empty and nothing happens.
        It changes nothing itself.

    .PARAMETER Plan
        From Get-StarterPlan.

    .PARAMETER ExistingUser
        The account currently at the plan's sign-in address, or $null if there isn't one.
        Needs EmployeeId, AccountEnabled and Groups (group names).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Plan,
        [AllowNull()] [object]$ExistingUser
    )

    $upn = $Plan.UserPrincipalName

    if (-not $ExistingUser) {
        [pscustomobject]@{ Action = 'CreateUser'; Target = $upn; Group = $null }
        foreach ($g in $Plan.Groups) {
            [pscustomobject]@{ Action = 'AddToGroup'; Target = $upn; Group = $g }
        }
        return
    }

    # Same address, different person (e.g. two Jane Does). Stop rather than guess.
    if ($ExistingUser.EmployeeId -ne $Plan.EmployeeId) {
        throw "$upn already belongs to employee '$($ExistingUser.EmployeeId)', not '$($Plan.EmployeeId)'. Needs a person to choose a different address."
    }

    # Same person already exists, e.g. a request sent twice, or a returning employee.
    if (-not $ExistingUser.AccountEnabled) {
        [pscustomobject]@{ Action = 'EnableAccount'; Target = $upn; Group = $null }
    }

    foreach ($g in $Plan.Groups) {
        if ($g -notin @($ExistingUser.Groups)) {
            [pscustomobject]@{ Action = 'AddToGroup'; Target = $upn; Group = $g }
        }
    }
}
