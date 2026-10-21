function Get-EntraUserState {
    <#
    .SYNOPSIS
        Reads what already exists for a user, in the shape Get-StarterAction / Get-LeaverAction expect.

    .DESCRIPTION
        Looks the user up by sign-in address (for starters) or employee ID (for leavers).
        Returns $null if there's no such user. Only reads; changes nothing.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByUpn')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByUpn')]
        [string]$UserPrincipalName,

        [Parameter(Mandatory, ParameterSetName = 'ByEmployeeId')]
        [ValidatePattern('^[A-Za-z0-9-]{1,32}$')]
        [string]$EmployeeId
    )

    $select = 'id,userPrincipalName,employeeId,accountEnabled'

    if ($PSCmdlet.ParameterSetName -eq 'ByUpn') {
        # A plain filter reads the directory itself, so it sees a user created a second ago.
        # The 'eventual' mode below reads a search index that lags a few seconds; using it here
        # made a quick second starter request try to create the same user again (found 21 Oct 2026).
        $filter  = "userPrincipalName eq '$($UserPrincipalName -replace "'", "''")'"
        $uri     = "v1.0/users?`$filter=$filter&`$select=$select"
        $headers = @{}
    }
    else {
        $filter  = "employeeId eq '$EmployeeId'"
        $uri     = "v1.0/users?`$filter=$filter&`$select=$select&`$count=true"
        $headers = @{ ConsistencyLevel = 'eventual' }
    }

    $users = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject -Uri $uri -Headers $headers).value)

    if ($users.Count -eq 0) { return $null }
    if ($users.Count -gt 1) { throw "More than one user matches $filter. Fix the duplicate before going on." }

    $user   = $users[0]
    $groups = @((Invoke-MgGraphRequest -Method GET -OutputType PSObject `
        -Uri "v1.0/users/$($user.id)/memberOf/microsoft.graph.group?`$select=displayName").value).displayName

    [pscustomobject]@{
        Id                = $user.id
        UserPrincipalName = $user.userPrincipalName
        EmployeeId        = $user.employeeId
        AccountEnabled    = [bool]$user.accountEnabled
        Groups            = @($groups | Where-Object { $_ })
    }
}
