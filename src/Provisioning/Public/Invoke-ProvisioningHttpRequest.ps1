function Invoke-ProvisioningHttpRequest {
    <#
    .SYNOPSIS
        Turns a web request into a starter or leaver run, and the result into a web response.

    .DESCRIPTION
        Kept in the module (not in the Azure Function's run.ps1) so it can be tested with
        Pester. Returns @{ StatusCode; Body }:
          200  done, with the steps taken (an empty list means it was already done)
          400  the request was missing something or invalid
          404  leaver not found
          409  the sign-in address belongs to a different employee
          500  anything else (details go to the log, not the caller)

    .PARAMETER Kind
        'Starter' or 'Leaver'.

    .PARAMETER Body
        The request body: an object, or JSON text.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [ValidateSet('Starter', 'Leaver')] [string]$Kind,
        [AllowNull()] [object]$Body,
        [Parameter(Mandatory)] [string]$TenantId,
        [string]$Domain,
        [object]$DepartmentGroups
    )

    function Reply ($code, $content) { @{ StatusCode = $code; Body = $content } }

    try {
        if ($Body -is [string]) { $Body = $Body | ConvertFrom-Json }
    }
    catch {
        return Reply 400 @{ error = 'The request body is not valid JSON.' }
    }

    $required = if ($Kind -eq 'Starter') { 'firstName', 'lastName', 'employeeId', 'department' } else { 'employeeId' }
    $missing  = @($required | Where-Object { -not $Body -or -not $Body.$_ })
    if ($missing) {
        return Reply 400 @{ error = "Missing: $($missing -join ', ')." }
    }

    try {
        if ($Kind -eq 'Starter') {
            $done = @(Invoke-StarterRequest -FirstName $Body.firstName -LastName $Body.lastName -EmployeeId $Body.employeeId `
                -Department $Body.department -JobTitle $Body.jobTitle -Domain $Domain -DepartmentGroups $DepartmentGroups `
                -TenantId $TenantId -Confirm:$false -ErrorAction Stop)
        }
        else {
            $done = @(Invoke-LeaverRequest -EmployeeId $Body.employeeId -TenantId $TenantId -Confirm:$false -ErrorAction Stop)
        }

        Reply 200 @{
            status = if ($done.Count) { 'done' } else { 'nothing to do' }
            steps  = @($done | ForEach-Object { if ($_.Group) { "$($_.Action) '$($_.Group)'" } else { $_.Action } })
        }
    }
    catch {
        $message = $_.Exception.Message
        switch -Wildcard ($message) {
            '*Unknown department*'    { return Reply 400 @{ error = $message } }
            "*Can't build a sign-in*" { return Reply 400 @{ error = $message } }
            '*Cannot validate*'       { return Reply 400 @{ error = 'employeeId must be 1-32 letters, digits or hyphens.' } }
            '*No account found*'      { return Reply 404 @{ error = $message } }
            '*already belongs to*'    { return Reply 409 @{ error = $message } }
        }
        # For a Graph failure the message only says "BadRequest"; Graph's own explanation is in
        # ErrorDetails (found 22 Oct 2026). It goes to the log only, never to the caller.
        $detail = if ($_.ErrorDetails.Message) { " Graph said: $($_.ErrorDetails.Message)" }
        Write-Error -Message "$Kind request failed: $message$detail" -ErrorAction Continue
        Reply 500 @{ error = 'Something went wrong. Check the function logs.' }
    }
}
