function Get-LeaverAction {
    <#
    .SYNOPSIS
        Lists the steps still needed to close down a leaver's access. Changes nothing.

    .DESCRIPTION
        Blocks sign-in, ends any open sessions, and removes the account from its groups.
        The account itself is kept (not deleted) so mail and files can be handed over.
        Steps already done are skipped, so running it twice is safe.

    .PARAMETER ExistingUser
        The leaver's account. Needs UserPrincipalName, AccountEnabled and Groups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$ExistingUser
    )

    # A leaver who can't be found is probably a typo. Say so rather than report success.
    if (-not $ExistingUser) {
        throw 'No account found for this leaver. Check the employee ID.'
    }

    $upn = $ExistingUser.UserPrincipalName

    # Block sign-in first, so nothing else can happen on the account while it's being closed.
    if ($ExistingUser.AccountEnabled) {
        [pscustomobject]@{ Action = 'DisableAccount'; Target = $upn; Group = $null }
        [pscustomobject]@{ Action = 'RevokeSessions'; Target = $upn; Group = $null }
    }

    foreach ($g in @($ExistingUser.Groups)) {
        [pscustomobject]@{ Action = 'RemoveFromGroup'; Target = $upn; Group = $g }
    }
}
