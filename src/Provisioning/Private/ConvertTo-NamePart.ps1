function ConvertTo-NamePart {
    <#
    .SYNOPSIS
        Turns a name into something safe for an email address, e.g. "O'Brien-Smith" -> "obriensmith".

    .DESCRIPTION
        Removes accents (an accented a becomes a plain a), then drops anything that
        isn't a plain letter (spaces, hyphens, apostrophes), and lower-cases the result.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # FormD splits an accented letter into the plain letter plus a separate accent mark,
    # so keeping only a-z drops the accent but keeps the letter.
    $decomposed = $Name.Normalize([Text.NormalizationForm]::FormD)
    $letters = foreach ($ch in $decomposed.ToCharArray()) {
        if ($ch -match '[a-zA-Z]') { $ch }
    }

    (-join $letters).ToLowerInvariant()
}
