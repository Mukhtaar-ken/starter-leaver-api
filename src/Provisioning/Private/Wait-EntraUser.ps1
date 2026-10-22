function Wait-EntraUser {
    <#
    .SYNOPSIS
        Looks a user up by sign-in address, trying again for a few seconds if they're not found.

    .DESCRIPTION
        For a user that should exist (we just created them, or Graph says the address is taken)
        but that the copy of Entra we reached doesn't show yet. Returns $null if they still
        aren't there after the last try.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$UserPrincipalName,
        [int]$Attempts = 5,
        [int]$DelaySeconds = 2
    )

    for ($try = 1; $try -le $Attempts; $try++) {
        $user = Get-EntraUserState -UserPrincipalName $UserPrincipalName
        if ($user) { return $user }

        if ($try -lt $Attempts) {
            Write-Verbose "$UserPrincipalName not visible yet (try $try of $Attempts). Waiting $DelaySeconds s."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}
