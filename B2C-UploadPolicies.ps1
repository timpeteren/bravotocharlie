## Add error handling
### May crash if no files are found, or should at least spit out some sensible (and consolidated) error messages

[CmdletBinding()]
param (
    # Account name to connect to Azure AD B2C tenant with
    [Parameter(Mandatory = $true)]
    [String]$Username,

    # Tenant identifier of Azure AD B2C tenant
    [Parameter(Mandatory = $true)]
    [String]$TenantIdentifier
)

Connect-AzureAD -AccountId $Username -TenantId $TenantIdentifier

function Upload-B2CPolicies {
    param(
        # Parameter used to pass in one or more policy files (not all)
        [Parameter(Mandatory = $false)]
        [Array]$Policies
    )
    $policyFiles = New-Object -TypeName "System.Collections.ArrayList"
    if (-not [System.String]::IsNullOrEmpty($Policies) ) {
        foreach ($pol in $Policies) {
            $policyFiles.Add($(Get-ChildItem -Path $pol)) | Out-Null
        }
    }
    else {
        $policyFiles = Get-ChildItem
    }

    foreach ($file in $policyFiles) {
        [xml]$policyContent = Get-Content -Path $($file.FullName)
        $Result = $null
        $Result = Set-AzureADMSTrustFrameworkPolicy -Id $($policyContent.TrustFrameworkPolicy.PolicyId) -InputFilePath $file.FullName

        if ( [String]::IsNullOrWhiteSpace($Result) ) {
            Write-Host "Upload of policy $($policyContent.TrustFrameworkPolicy.PolicyId) failed!"
            exit 1;
        }
        Write-Host "Policy $($policyContent.TrustFrameworkPolicy.PolicyId) was successfully uploaded!"
    }
}