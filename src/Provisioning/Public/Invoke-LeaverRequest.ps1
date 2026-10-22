function Invoke-LeaverRequest {
    <#
    .SYNOPSIS
        Closes down a leaver end to end: find them by employee ID, do only what's still needed.

    .DESCRIPTION
        Blocks sign-in, ends sessions and removes groups. Never deletes the account.
        Safe to run twice. Use -WhatIf to see the steps without making them.

    .EXAMPLE
        Invoke-LeaverRequest -EmployeeId E1001 -TenantId $tenant -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$EmployeeId,
        [Parameter(Mandatory)] [string]$TenantId
    )

    Assert-ExpectedTenant -TenantId $TenantId

    $existing = Get-EntraUserState -EmployeeId $EmployeeId
    $actions  = @(Get-LeaverAction -ExistingUser $existing)

    if ($actions.Count -eq 0) {
        Write-Verbose "$($existing.UserPrincipalName) is already closed down. Nothing to do."
        return
    }

    # One confirmation for the whole request, listing every step (or just the list, with -WhatIf).
    $steps = ($actions | ForEach-Object { if ($_.Group) { "$($_.Action) '$($_.Group)'" } else { $_.Action } }) -join ', '
    if ($PSCmdlet.ShouldProcess($existing.UserPrincipalName, $steps)) {
        Invoke-ProvisioningAction -Action $actions -UserId $existing.Id -TenantId $TenantId -Confirm:$false
    }
}
