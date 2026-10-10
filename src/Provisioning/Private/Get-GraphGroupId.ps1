function Get-GraphGroupId {
    <#
    .SYNOPSIS
        Finds a group's ID from its exact name. Stops if there is none, or more than one.

    .DESCRIPTION
        Groups are never created here. A missing group usually means a typo in
        config\departments.json, and quietly creating it would hide that.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $escaped = $Name -replace "'", "''"
    $found = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `
        -Uri "v1.0/groups?`$filter=displayName eq '$escaped'&`$select=id,displayName").value)

    if ($found.Count -eq 0) { throw "Group '$Name' doesn't exist in the tenant. Create it, or fix config\departments.json." }
    if ($found.Count -gt 1) { throw "More than one group is called '$Name'. Rename one so the name is unique." }

    $found[0].id
}
