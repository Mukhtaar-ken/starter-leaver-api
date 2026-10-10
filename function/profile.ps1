# Runs once when the function app starts (a "cold start").
# Signs in to Microsoft Graph as the app's managed identity: no password or secret anywhere.
# The permissions it has come from deploy\grant-graph-permissions.ps1.

if ($env:MSI_SECRET -or $env:IDENTITY_ENDPOINT) {
    Connect-MgGraph -Identity -NoWelcome
}
