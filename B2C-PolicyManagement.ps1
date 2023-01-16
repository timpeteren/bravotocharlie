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
    [bool]$DoNoDeletePolicyFiles = $false
)

$Placeholders = @{
    "PLACEHOLDER_TENANTNAME"                  = ""
    "PLACEHOLDER_TENANTID"                    = ""
    "PLACEHOLDER_BRANDINGBASEURL"             = ""
    "PLACEHOLDER_INSTRUMENTATIONKEY"          = ""
    "PLACEHOLDER_IEF_CLIENTID"                = ""
    "PLACEHOLDER_IEFPROXY_CLIENTID"           = ""
    "PLACEHOLDER_B2C_EXTENSIONS_APP_CLIENTID" = ""
    "PLACEHOLDER_B2C_EXTENSIONS_APP_OBJECTID" = ""
    "PLACEHOLDER_AAD_COMMON_APP_CLIENTID"     = ""
    "PLACEHOLDER_IDPORTEN_CLIENTID"           = ""
    "PLACEHOLDER_HELPERAPI_URL"               = ""
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
        "PLACEHOLDER_TENANTID"
        "PLACEHOLDER_BRANDINGBASEURL"
        "PLACEHOLDER_INSTRUMENTATIONKEY"
        "PLACEHOLDER_IEF_CLIENTID"
        "PLACEHOLDER_IEFPROXY_CLIENTID"
        "PLACEHOLDER_B2C_EXTENSIONS_APP_CLIENTID"
        "PLACEHOLDER_B2C_EXTENSIONS_APP_OBJECTID"
        "PLACEHOLDER_AAD_COMMON_APP_CLIENTID"
        "PLACEHOLDER_IDPORTEN_CLIENTID"
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
            Set-Content -Path "$(Join-Path $DeployFolder $($_.BaseName)).xml" -Value $content -Encoding UTF8
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