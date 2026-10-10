# POST /api/leaver   { "employeeId": "E1001" }
# All the logic is in the Provisioning module, where it's tested. This file only connects it to HTTP.
using namespace System.Net
param($Request)

$result = Invoke-ProvisioningHttpRequest -Kind Leaver -Body $Request.Body -TenantId $env:TENANT_ID

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode  = [HttpStatusCode]$result.StatusCode
    ContentType = 'application/json'
    Body        = $result.Body | ConvertTo-Json -Depth 5
})
