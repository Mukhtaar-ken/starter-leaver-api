<#
.SYNOPSIS
    Creates or updates the Azure resources and deploys the function code. Safe to re-run.

.DESCRIPTION
    1. Checks az is signed in to the tenant you named (same idea as the code's tenant guard).
    2. Creates the resource group and everything in infra\main.bicep.
    3. Builds the app: function folder + department config + the Provisioning module
       + the Microsoft.Graph.Authentication module (a pinned version).
    4. Uploads it as a zip.
    Doesn't grant Graph permissions; run grant-graph-permissions.ps1 for that (once).

.EXAMPLE
    .\deploy\deploy.ps1 -TenantId <tenant id> -UserDomain contoso.onmicrosoft.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$TenantId,
    [Parameter(Mandatory)] [string]$UserDomain,
    [string]$ResourceGroup = 'rg-starter-leaver-api',
    [string]$Location = 'uksouth',
    [string]$GraphModuleVersion = '2.25.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# Runs az and stops if it fails. Judged by az's exit code, not by what it prints:
# az writes harmless warnings to the error stream, which Windows PowerShell 5.1
# would otherwise treat as a failure (found on the first real deploy, 10 Oct 2026).
function Invoke-Az {
    $ErrorActionPreference = 'Continue'   # only inside this function; the exit code check below decides
    $output = & az @args --only-show-errors 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) { throw "az $($args[0]) $($args[1]) failed:`n$($output -join "`n")" }
    $output
}

$signedIn = Invoke-Az account show --query tenantId -o tsv
if ($signedIn -ne $TenantId) {
    throw "az is signed in to tenant $signedIn, not $TenantId. Run: az login --tenant $TenantId"
}

if ((Invoke-Az group exists --name $ResourceGroup) -eq 'true') {
    Write-Output "Using existing resource group $ResourceGroup."
}
else {
    Write-Output "Creating resource group $ResourceGroup in $Location..."
    Invoke-Az group create --name $ResourceGroup --location $Location --tags project=starter-leaver-api --output none
}

# The resources' region is passed separately: some subscriptions (e.g. free ones) have no
# Consumption-plan quota in some regions, so the app may need a different region from the group.
Write-Output "Deploying infra\main.bicep to $Location..."
$outputs = Invoke-Az deployment group create --resource-group $ResourceGroup --template-file "$root\infra\main.bicep" `
    --parameters userDomain=$UserDomain tenantId=$TenantId location=$Location --query properties.outputs | ConvertFrom-Json
$appName = $outputs.functionAppName.value

Write-Output 'Building the app package...'
$build = Join-Path ([IO.Path]::GetTempPath()) "sla-build-$(Get-Random)"
Copy-Item "$root\function" $build -Recurse
Copy-Item "$root\config\departments.json" $build
New-Item "$build\Modules" -ItemType Directory | Out-Null
Copy-Item "$root\src\Provisioning" "$build\Modules\Provisioning" -Recurse
Save-Module Microsoft.Graph.Authentication -RequiredVersion $GraphModuleVersion -Path "$build\Modules" -Repository PSGallery

$zip = "$build.zip"
Compress-Archive -Path "$build\*" -DestinationPath $zip -Force

Write-Output "Uploading to $appName..."
Invoke-Az functionapp deployment source config-zip --resource-group $ResourceGroup --name $appName --src $zip --output none
Remove-Item $build, $zip -Recurse -Force

Write-Output ''
Write-Output "Deployed: https://$($outputs.hostName.value)/api/starter  and  /api/leaver"
Write-Output "Managed identity (principalId): $($outputs.principalId.value)"
Write-Output 'If this is the first deployment, run: .\deploy\grant-graph-permissions.ps1 -PrincipalId <the ID above>'
