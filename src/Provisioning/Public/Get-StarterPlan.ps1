function Get-StarterPlan {
    <#
    .SYNOPSIS
        Works out what a new starter's account should look like. Changes nothing.

    .DESCRIPTION
        Takes a starter request and returns the account to create: names, sign-in
        address and the groups for their department. It never talks to Entra, so it
        can be tested with fake data. Get-StarterAction then compares this plan with
        what already exists.

    .PARAMETER EmployeeId
        The HR employee number. This, not the name, identifies the person, so two
        people with the same name are never mixed up, and re-sending a request is safe.

    .PARAMETER DepartmentGroups
        Which groups each department gets, e.g. from config\departments.json.

    .EXAMPLE
        $groups = Get-Content .\config\departments.json -Raw | ConvertFrom-Json
        Get-StarterPlan -FirstName 'Jane' -LastName 'Doe' -EmployeeId 'E1001' -Department 'Sales' `
            -Domain 'contoso.example' -DepartmentGroups $groups
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$FirstName,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string]$LastName,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9-]{1,32}$')]
        [string]$EmployeeId,

        [Parameter(Mandatory)] [string]$Department,
        [string]$JobTitle,

        [Parameter(Mandatory)] [string]$Domain,
        [Parameter(Mandatory)] [object]$DepartmentGroups
    )

    # Fail on an unknown department rather than creating someone with no groups.
    $groups = $DepartmentGroups.$Department
    if (-not $groups) {
        throw "Unknown department '$Department'. Known departments: $(@($DepartmentGroups.PSObject.Properties.Name) -join ', ')."
    }

    $first = ConvertTo-NamePart $FirstName
    $last  = ConvertTo-NamePart $LastName
    if (-not $first -or -not $last) {
        throw "Can't build a sign-in name from '$FirstName $LastName'."
    }

    [pscustomobject]@{
        EmployeeId        = $EmployeeId
        DisplayName       = "$($FirstName.Trim()) $($LastName.Trim())"
        GivenName         = $FirstName.Trim()
        Surname           = $LastName.Trim()
        UserPrincipalName = "$first.$last@$Domain"
        MailNickname      = "$first.$last"
        Department        = $Department
        JobTitle          = $JobTitle
        Groups            = @($groups | Sort-Object -Unique)
    }
}
