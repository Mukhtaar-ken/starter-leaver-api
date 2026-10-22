function Invoke-GraphStep {
    <#
    .SYNOPSIS
        Runs one Graph request, allowing for Entra being a few seconds behind itself.

    .DESCRIPTION
        Entra keeps several copies of the directory, and they take a few seconds to agree
        after a change. So a request can fail only because it reached a copy that is behind
        (found in the live test, 22 Oct 2026). Two ways to handle that:
          -AlreadyDoneIf  error text meaning the step is already done, e.g. "already exist".
                          Counted as success, and nothing is returned.
          -RetryIf        error text meaning "not caught up yet", e.g. "does not exist".
                          Tried again after a short wait, up to -Attempts times.
        Any other error is thrown as normal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock]$Request,
        [string]$AlreadyDoneIf,
        [string]$RetryIf,
        [int]$Attempts = 5,
        [int]$DelaySeconds = 2
    )

    for ($try = 1; ; $try++) {
        try {
            return (& $Request)
        }
        catch {
            # Invoke-MgGraphRequest puts Graph's own message (the useful part) in ErrorDetails.
            $text = "$($_.ErrorDetails.Message) $($_.Exception.Message)"

            if ($AlreadyDoneIf -and $text -match $AlreadyDoneIf) {
                Write-Verbose "Already done: $text"
                return
            }
            if ($RetryIf -and $text -match $RetryIf -and $try -lt $Attempts) {
                Write-Verbose "Entra hasn't caught up yet (try $try of $Attempts). Waiting $DelaySeconds s."
                Start-Sleep -Seconds $DelaySeconds
                continue
            }
            throw
        }
    }
}
