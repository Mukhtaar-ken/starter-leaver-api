# Loads every function file. Public functions are exported; Private ones stay internal.
$public  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1"  -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)

foreach ($file in @($public + $private)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
