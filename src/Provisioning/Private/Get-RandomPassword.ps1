function Get-RandomPassword {
    <#
    .SYNOPSIS
        Makes a strong one-time password for a new account. It is never shown or saved.

    .DESCRIPTION
        The account is created with "change password at next sign-in", and the person is
        given access another way (e.g. a password reset by IT, or a Temporary Access Pass).
        Uses a cryptographic random generator, not Get-Random, which is predictable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateRange(16, 64)]
        [int]$Length = 24
    )

    $rng   = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 1

    # Picks one character fairly. A byte is 0-255; if the set has, say, 70 characters,
    # 256 % 70 would favour the first few. Throwing away the top "leftover" bytes avoids that.
    $pick = {
        param([string]$chars)
        $limit = 256 - (256 % $chars.Length)
        do { $rng.GetBytes($bytes) } while ($bytes[0] -ge $limit)
        $chars[$bytes[0] % $chars.Length]
    }

    # One of each character type first, so Entra's complexity rules are always met.
    $sets  = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!@#$%*-_=+?'
    $all   = -join $sets
    $chars = @(foreach ($set in $sets) { & $pick $set })
    $chars += 1..($Length - $sets.Count) | ForEach-Object { & $pick $all }

    # Shuffle so the guaranteed characters aren't always at the front.
    -join ($chars | Sort-Object { $rng.GetBytes($bytes); $bytes[0] })
}
