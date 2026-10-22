function Invoke-StarterRequest {
    <#
    .SYNOPSIS
        Sets up a new starter end to end: plan, check what exists, do only what's missing.

    .DESCRIPTION
        Safe to run twice: the second run finds everything done and changes nothing.
        Use -WhatIf to see the steps without making them.

    .EXAMPLE
        Connect-MgGraph -TenantId $tenant -Scopes User.ReadWrite.All, Group.ReadWrite.All
        $groups = Get-Content .\config\departments.json -Raw | ConvertFrom-Json
        Invoke-StarterRequest -FirstName Jane -LastName Doe -EmployeeId E1001 -Department Sales `
            -Domain contoso.example -DepartmentGroups $groups -TenantId $tenant -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$FirstName,
        [Parameter(Mandatory)] [string]$LastName,
        [Parameter(Mandatory)] [string]$EmployeeId,
        [Parameter(Mandatory)] [string]$Department,
        [string]$JobTitle,
        [Parameter(Mandatory)] [string]$Domain,
        [Parameter(Mandatory)] [object]$DepartmentGroups,
        [Parameter(Mandatory)] [string]$TenantId
    )

    # Check the tenant before even reading, so the "what exists" view is from the right place.
    Assert-ExpectedTenant -TenantId $TenantId

    $plan     = Get-StarterPlan -FirstName $FirstName -LastName $LastName -EmployeeId $EmployeeId `
        -Department $Department -JobTitle $JobTitle -Domain $Domain -DepartmentGroups $DepartmentGroups
    $existing = Get-EntraUserState -UserPrincipalName $plan.UserPrincipalName
    $actions  = @(Get-StarterAction -Plan $plan -ExistingUser $existing)

    if ($actions.Count -eq 0) {
        Write-Verbose "$($plan.UserPrincipalName) is already set up. Nothing to do."
        return
    }

    # One confirmation for the whole request, listing every step (or just the list, with -WhatIf).
    $steps = ($actions | ForEach-Object { if ($_.Group) { "$($_.Action) '$($_.Group)'" } else { $_.Action } }) -join ', '
    if ($PSCmdlet.ShouldProcess($plan.UserPrincipalName, $steps)) {
        Invoke-ProvisioningAction -Action $actions -Plan $plan -UserId $existing.Id -TenantId $TenantId -Confirm:$false
    }
}
