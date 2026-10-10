<#
.SYNOPSIS
    Gives the function app's managed identity the Microsoft Graph permissions it needs. Safe to re-run.

.DESCRIPTION
    Least privilege: it can manage users and change group membership, but it can't create,
    delete or rename groups, or touch anything else in the tenant.
      User.ReadWrite.All         create users, enable/disable them, end their sessions
      GroupMember.ReadWrite.All  find groups by name, add and remove members

    Needs: az login as an admin of the tenant (e.g. Global Administrator or Privileged Role Administrator).

.EXAMPLE
    .\deploy\grant-graph-permissions.ps1 -PrincipalId <output from deploy.ps1>
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$PrincipalId
)

$ErrorActionPreference = 'Stop'
$graphAppId  = '00000003-0000-0000-c000-000000000000'   # Microsoft Graph's fixed app ID, the same in every tenant
$permissions = 'User.ReadWrite.All', 'GroupMember.ReadWrite.All'

$graph = (az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$graphAppId'&`$select=id,appRoles" |
    ConvertFrom-Json).value[0]

$existing = (az rest --method get --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" |
    ConvertFrom-Json).value.appRoleId

foreach ($name in $permissions) {
    $role = $graph.appRoles | Where-Object { $_.value -eq $name -and $_.allowedMemberTypes -contains 'Application' }
    if (-not $role) { throw "Graph has no application permission called $name." }

    if ($role.id -in $existing) {
        Write-Output "Already granted: $name"
        continue
    }

    if ($PSCmdlet.ShouldProcess($PrincipalId, "Grant Graph permission $name")) {
        # az rest needs the body in a file on Windows to keep the JSON quotes intact.
        $bodyFile = New-TemporaryFile
        @{ principalId = $PrincipalId; resourceId = $graph.id; appRoleId = $role.id } | ConvertTo-Json | Set-Content $bodyFile
        az rest --method post --url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
            --body "@$bodyFile" --headers 'Content-Type=application/json' | Out-Null
        Remove-Item $bodyFile
        Write-Output "Granted: $name"
    }
}
