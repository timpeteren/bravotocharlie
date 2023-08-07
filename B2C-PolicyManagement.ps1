<#
.SYNOPSIS
    Uploads policy files to Azure AD B2C, after replacing PLACHOLDER_ values.
    Policy files can be addressed with full path, else script looks for files in the current directory.
.DESCRIPTION
    Script has a $Placeholders hash table holding all required values.
    To verify that all settings are present a pre-check is run.
    The pre-check compares $Placeholders with $ValidPlaceholders in function Invoke-PlaceholderReplace.
    If pre-check is successful, the script replaces the PLACEHOLDER_ values and uploads the policy files.
.NOTES
    Connect-AzureAD must be run prior to script execution as a valid session is required.
    Assumes that account has AAD B2C tenant privilege 'Policy.ReadWrite.TrustFramework'.

    Written by Tim Peter Edstrøm, @timpeteren

    v1.6 - 07.08.23:
    - Removed variable TENANTID, added multiple APP, RESTAPI, SENDGRID configuration integrations
    v1.5 - 23.06.23:
    - Added values to Placeholder objects for dev / prod environments (supports updated generalized policy files)
    v1.3 - 16.01.23:
    - Esthetics, comments, example
    v1.2 - 10.10.22:
    - Add HELPERAPI placeholder
    v1.1 - 09.08.22:
    - Fix folder cleanup
    - Set default -DeployFolder value statically to ".\Deploy"
    - Fix .EXAMPLE for using -PolicyFiles with multiple policy files (must be comma separated)
    v1.0 - 09.08.22:
    - Test and bugfix
    - Add comment section
    v0.5 - 08.08.22:
    - Add PLACHOLDER verification and replacement and policy upload
.EXAMPLE
    B2C-PolicyManagement
    Looks for policy files in current folder, creates a temporary .\Deploy folder while processing.
.EXAMPLE
    B2C-PolicyManagement -PolicyFiles .\3-b2c_1a_v2_signupsignin.xml, .\4-b2c_1a_v2_passwordreset.xml -DeployFolder MyDeploy
    Specify a single, or multiple, policy file(s) to be processed.
    Use -DeployFolder to override default (.\Deploy).
.EXAMPLE
    B2C-PolicyManagement -DoNoDeletePolicyFiles:$true
    Use to leave policy files in the deploy folder.
#>

[CmdletBinding()]
param (
    $TenantIdentifier,
    [Parameter(Mandatory = $false)]
    $DeployFolder = ".\Deploy",
    [Parameter(Mandatory = $false)]
    [Array]$PolicyFiles,
    [Parameter(Mandatory = $false)]
    [Bool]$DoNoDeletePolicyFiles = $false,
    [Parameter(Mandatory = $false)]
    [String]$Environment
)

if (-not $Environment) {
    $Environment = "Dev"
    Write-Host "`$Environment not provided, using 'Dev' settings for placeholder values.`n" -ForegroundColor Green
}
elseif (($Environment) -and ($Environment -eq "Dev")) {
    $Environment = "Dev"
    Write-Host "`$Environment settings 'Dev' for placeholder values.`n" -ForegroundColor Green
}
elseif (($Environment) -and ($Environment -eq "Prod")) {
    $Environment = "Prod"
    Write-Host "`$Environment settings 'Prod' for placeholder values.`n" -ForegroundColor Green
}
else {
    Write-Host "Incorrect `$Environment provided, either 'Dev' or 'Prod' for required placeholder values." -ForegroundColor Yellow
    break;
}

if ($Environment -eq "Dev") {

    $Placeholders = @{
        "PLACEHOLDER_TENANTNAME"                            = "xxdevb2c.onmicrosoft.com"
        "PLACEHOLDER_BRANDINGBASEURL"                       = ""
        "BRANDING_CONTAINER_NAME"                           = "branding"
        "PLACEHOLDER_INSTRUMENTATIONKEY"                    = ""
        "PLACEHOLDER_DEPLOYMENTMODE"                        = "Development"
        "PLACEHOLDER_DEVELOPERMODE"                         = "true"
        "PLACEHOLDER_IEF_CLIENTID"                          = ""
        "PLACEHOLDER_IEFPROXY_CLIENTID"                     = ""
        "PLACEHOLDER_B2C_EXTENSIONS_APP_CLIENTID"           = ""
        "PLACEHOLDER_B2C_EXTENSIONS_APP_OBJECTID"           = ""

        "PLACEHOLDER_AAD_COMMON_APP_CLIENTID"               = ""
        "PLACEHOLDER_AAD_COMMON_APP_SCOPE"                  = "openid profile email"
        "PLACEHOLDER_AAD_USER_IMPERSONATION_APP_CLIENTID"   = ""
        "PLACEHOLDER_AAD_USER_IMPERSONATION_APP_SCOPE"      = "openid profile email"
        "PLACEHOLDER_RESTAPI_URL"                           = "xx.service.com"
        "PLACEHOLDER_RESTAPI_SCOPE"                         = "xxdevb2c.onmicrosoft.com/<GUID>"
        "PLACEHOLDER_GRAPHAPI_SCOPE"                        = "graph.onmicrosoft.com"
        "PLACEHOLDER_SENDGRID_URL"                          = "api.sendgrid.com"
        "PLACEHOLDER_SENDGRID_NB"                           = "noID123"
        "PLACEHOLDER_SENDGRID_EN"                           = "enID456"
        "PLACEHOLDER_SENDGRID_FROM"                         = "no-reply@myCompany.com"
        "PLACEHOLDER_SENDGRID_TEMPLATE_NB_ID"               = "<uniqueID>"
        "PLACEHOLDER_SENDGRID_TEMPLATE_EN_ID"               = "<uniqueID>"
        "PLACEHOLDER_HELPERAPI_URL"                         = ""
    }
}
if ($Environment -eq "Prod") {

    $Placeholders = @{
        "PLACEHOLDER_TENANTNAME"                            = "xxprodb2c.onmicrosoft.com"
        "PLACEHOLDER_BRANDINGBASEURL"                       = ""
        "BRANDING_CONTAINER_NAME"                           = "branding"
        "PLACEHOLDER_INSTRUMENTATIONKEY"                    = ""
        "PLACEHOLDER_DEPLOYMENTMODE"                        = "Production"
        "PLACEHOLDER_DEVELOPERMODE"                         = "false"
        "PLACEHOLDER_IEF_CLIENTID"                          = ""
        "PLACEHOLDER_IEFPROXY_CLIENTID"                     = ""
        "PLACEHOLDER_B2C_EXTENSIONS_APP_CLIENTID"           = ""
        "PLACEHOLDER_B2C_EXTENSIONS_APP_OBJECTID"           = ""

        "PLACEHOLDER_AAD_COMMON_APP_CLIENTID"               = ""
        "PLACEHOLDER_AAD_COMMON_APP_SCOPE"                  = "openid profile email"
        "PLACEHOLDER_AAD_USER_IMPERSONATION_APP_CLIENTID"   = ""
        "PLACEHOLDER_AAD_USER_IMPERSONATION_APP_SCOPE"      = "openid profile email"
        "PLACEHOLDER_RESTAPI_URL"                           = "xx.service.com"
        "PLACEHOLDER_RESTAPI_SCOPE"                         = "xxprodb2c.onmicrosoft.com/<GUID>"
        "PLACEHOLDER_GRAPHAPI_SCOPE"                        = "graph.onmicrosoft.com"
        "PLACEHOLDER_SENDGRID_URL"                          = "api.sendgrid.com"
        "PLACEHOLDER_SENDGRID_NB"                           = "noID123"
        "PLACEHOLDER_SENDGRID_EN"                           = "enID456"
        "PLACEHOLDER_SENDGRID_FROM"                         = "no-reply@myCompany.com"
        "PLACEHOLDER_SENDGRID_TEMPLATE_NB_ID"               = "<uniqueID>"
        "PLACEHOLDER_SENDGRID_TEMPLATE_EN_ID"               = "<uniqueID>"
        "PLACEHOLDER_HELPERAPI_URL"                         = ""
    }
}

function Invoke-PlaceholderReplace {
    param(
        # Parameter used to pass in placeholders
        [Parameter(Mandatory = $true)]
        $Placeholders,
        [Parameter(Mandatory = $false)]
        [Array]$PolicyFiles,
        [Parameter(Mandatory = $false)]
        $DeployFolder
    )

    $ValidPlaceholders = @(
        "PLACEHOLDER_TENANTNAME"
        "PLACEHOLDER_BRANDINGBASEURL"
        "BRANDING_CONTAINER_NAME"
        "PLACEHOLDER_INSTRUMENTATIONKEY"
        "PLACEHOLDER_DEPLOYMENTMODE"
        "PLACEHOLDER_DEVELOPERMODE"
        "PLACEHOLDER_IEF_CLIENTID"
        "PLACEHOLDER_IEFPROXY_CLIENTID"
        "PLACEHOLDER_B2C_EXTENSIONS_APP_CLIENTID"
        "PLACEHOLDER_B2C_EXTENSIONS_APP_OBJECTID"
        "PLACEHOLDER_AAD_COMMON_APP_CLIENTID"
        "PLACEHOLDER_AAD_COMMON_APP_SCOPE"
        "PLACEHOLDER_AAD_USER_IMPERSONATION_APP_CLIENTID"
        "PLACEHOLDER_AAD_USER_IMPERSONATION_APP_SCOPE"
        "PLACEHOLDER_RESTAPI_URL"
        "PLACEHOLDER_RESTAPI_SCOPE"
        "PLACEHOLDER_GRAPHAPI_SCOPE"
        "PLACEHOLDER_SENDGRID_URL"
        "PLACEHOLDER_SENDGRID_NB"
        "PLACEHOLDER_SENDGRID_EN"
        "PLACEHOLDER_SENDGRID_FROM"
        "PLACEHOLDER_SENDGRID_TEMPLATE_NB_ID"
        "PLACEHOLDER_SENDGRID_TEMPLATE_EN_ID"
        "PLACEHOLDER_HELPERAPI_URL"
    )

    $files = New-Object -TypeName "System.Collections.ArrayList"
    if (-not [System.String]::IsNullOrEmpty($PolicyFiles) ) {
        foreach ($file in $PolicyFiles) {
            $files.Add($(Get-ChildItem -Path $file)) | Out-Null
        }
    }
    else {
        $files = Get-ChildItem -Recurse | Where-Object Extension -in ".xml"
    }

    # Replace placeholders in all placeholder files
    $files | ForEach-Object {
        Write-Host "$($_.FullName)"
        $content = Get-Content $_.FullName -Raw

        [Regex]::Matches($content, "PLACEHOLDER_[A-Z0-9_]+") | 
        Where-Object Value -notin $ValidPlaceholders |
        ForEach-Object {
            Write-Host "$($_.FullName) - not a valid placeholder $($_.Value)"
            break;
        }

        $updated = $false
        $ValidPlaceholders | ForEach-Object {
            # If the variable exists, replace it
            if ( $($Placeholders.$_) ) {
                Write-Host "Replacing placeholder $($_) with the value $($Placeholders.$($_))"
                $content = $content.Replace($_, $($Placeholders.$($_)))
                $updated = $true
            }
            else {
                Write-Host "Missing variable for placeholder $($_)"
                break;
            }
        }
        if ($updated -eq $true) {
            Write-Host "Writing updated version of $(Join-Path $DeployFolder $($_.BaseName)).xml"
            # No need to encode XML, but make sure(!!!) policy file is in UTF-8 (*WITHOUT* BOM)
            Set-Content -Path "$(Join-Path $DeployFolder $($_.BaseName)).xml" -Value $content
        }
    }
}

function Invoke-PolicyUpload {
    param(
        # Parameter used to pass in one or more policy files (not all)
        [Parameter(Mandatory = $false)]
        [Array]$Policies
    )

    $polFiles = New-Object -TypeName "System.Collections.ArrayList"
    if (-not [System.String]::IsNullOrEmpty($Policies) ) {
        foreach ($pol in $Policies) {
            $polFiles.Add($(Get-ChildItem -Path (Join-Path $DeployFolder $pol) )) | Out-Null
        }
    }
    else {
        $polFiles = Get-ChildItem -Path $DeployFolder
    }
    
    foreach ($file in $polFiles) {
        [xml]$policyContent = Get-Content -Path $($file.FullName)
        $result = $null
        $result = Set-AzureADMSTrustFrameworkPolicy -Id $($policyContent.TrustFrameworkPolicy.PolicyId) -InputFilePath $file.FullName

        if ( [String]::IsNullOrWhiteSpace($result) ) {
            Write-Host "Upload of policy $($policyContent.TrustFrameworkPolicy.PolicyId) failed!"
            break;
        }
        Write-Host "Policy $($policyContent.TrustFrameworkPolicy.PolicyId) was successfully uploaded!"
    }
}

if (-not (Test-Path $DeployFolder)) { New-Item -ItemType Directory $DeployFolder | Out-Null }

if ((-not $PolicyFiles) -and (-not $DeployFolder)) {
    Invoke-PlaceholderReplace -Placeholders $Placeholders
}
elseif ((-not $PolicyFiles) -and $DeployFolder) {
    Invoke-PlaceholderReplace -Placeholders $Placeholders -DeployFolder $DeployFolder
}
elseif ((-not $DeployFolder) -and $PolicyFiles) {
    Invoke-PlaceholderReplace -Placeholders $Placeholders -PolicyFiles $PolicyFiles
}
else {
    Invoke-PlaceholderReplace -Placeholders $Placeholders -PolicyFiles $PolicyFiles -DeployFolder $DeployFolder
}
if (-not $PolicyFiles) {
    Invoke-PolicyUpload
}
else {
    Invoke-PolicyUpload -Policies $PolicyFiles
}

# Cleanup must run Get-ChildItem twice to make sure directory is empty
if (-not $DoNoDeletePolicyFiles -eq $true) {
    Get-ChildItem $DeployFolder | Remove-Item
    if ((Get-ChildItem $DeployFolder).Count -eq 0) {
        Remove-Item -Path $DeployFolder
    }
}
else {
    Write-Host "Leaving uploaded policy files in folder $($DeployFolder)"
}