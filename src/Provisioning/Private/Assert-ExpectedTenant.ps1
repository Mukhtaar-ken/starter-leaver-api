function Assert-ExpectedTenant {
    <#
    .SYNOPSIS
        Stops unless the Graph session is signed in to the tenant the caller named.

    .DESCRIPTION
        The same admin may be signed in to more than one tenant (e.g. a work tenant and a
        practice one). Every function that changes anything calls this first, so a change
        can never land in the wrong tenant by accident.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $context = Get-MgContext
    if (-not $context) {
        throw "Not signed in to Microsoft Graph. Run: Connect-MgGraph -TenantId $TenantId -Scopes User.ReadWrite.All, Group.ReadWrite.All"
    }
    if ($context.TenantId -ne $TenantId) {
        throw "Signed in to tenant $($context.TenantId), but this run is for tenant $TenantId. Nothing was changed."
    }
}
