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

$signedIn = az account show --query tenantId -o tsv
if ($signedIn -ne $TenantId) {
    throw "az is signed in to tenant $signedIn, not $TenantId. Run: az login --tenant $TenantId"
}

Write-Output "Creating/updating resource group $ResourceGroup in $Location..."
az group create --name $ResourceGroup --location $Location --tags project=starter-leaver-api --output none

Write-Output 'Deploying infra\main.bicep...'
$outputs = az deployment group create --resource-group $ResourceGroup --template-file "$root\infra\main.bicep" `
    --parameters userDomain=$UserDomain tenantId=$TenantId --query properties.outputs | ConvertFrom-Json
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
az functionapp deployment source config-zip --resource-group $ResourceGroup --name $appName --src $zip --output none
Remove-Item $build, $zip -Recurse -Force

Write-Output ''
Write-Output "Deployed: https://$($outputs.hostName.value)/api/starter  and  /api/leaver"
Write-Output "Managed identity (principalId): $($outputs.principalId.value)"
Write-Output 'If this is the first deployment, run: .\deploy\grant-graph-permissions.ps1 -PrincipalId <the ID above>'
