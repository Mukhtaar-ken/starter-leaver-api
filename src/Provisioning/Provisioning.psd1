@{
    RootModule           = 'Provisioning.psm1'
    ModuleVersion        = '0.4.1'
    GUID                 = 'aa2b21d6-2f03-4c7b-9c61-8ec44f655188'
    Author               = 'Mukhtaar Sugule'
    Description          = 'Works out the steps to set up a new starter or close down a leaver in Microsoft Entra ID, safely and repeatably.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = 'Desktop', 'Core'

    # Keep in step with the Public folder; tests\Module.Tests.ps1 checks this.
    FunctionsToExport    = 'Get-EntraUserState', 'Get-LeaverAction', 'Get-StarterAction', 'Get-StarterPlan',
                           'Invoke-LeaverRequest', 'Invoke-ProvisioningAction', 'Invoke-ProvisioningHttpRequest',
                           'Invoke-StarterRequest'
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData = @{
        PSData = @{
            Tags       = 'Entra', 'MicrosoftGraph', 'Provisioning', 'Onboarding'
            ProjectUri = 'https://github.com/Mukhtaar-ken/starter-leaver-api'
        }
    }
}
