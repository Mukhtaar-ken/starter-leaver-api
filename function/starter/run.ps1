# POST /api/starter   { "firstName": "Jane", "lastName": "Doe", "employeeId": "E1001", "department": "Sales" }
# All the logic is in the Provisioning module, where it's tested. This file only connects it to HTTP.
using namespace System.Net
param($Request)

$groups = Get-Content "$PSScriptRoot\..\departments.json" -Raw | ConvertFrom-Json
$result = Invoke-ProvisioningHttpRequest -Kind Starter -Body $Request.Body `
    -TenantId $env:TENANT_ID -Domain $env:USER_DOMAIN -DepartmentGroups $groups

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode  = [HttpStatusCode]$result.StatusCode
    ContentType = 'application/json'
    Body        = $result.Body | ConvertTo-Json -Depth 5
})
