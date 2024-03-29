<#
.SYNOPSIS
    Uploads or downloads files from a local folder to an Azure storage account blob container.
.DESCRIPTION
    The script is intented for execution in a release pipeline, for deployment of AAD B2C custom branding files to an Azure storage account container.
    Used in a pipeline, service principal credentials must be provided in context of the running pipeline.

    However, the script also supports running in user context for direct excecution.
    The authenticated user account must have the required privileges for blob management.
    When run in a shell the script can be configured either way:
        a) Provide variables as parameters when executing (as for pipeline execution)
        b) Fill out variables in '#region Manually configured variables'.
.NOTES
    Written by Tim Peter Edstrøm, @timpeteren

    11.01.23:
    - Add context of PIPELINE or USER execution to EXAMPLEs
    - Verify that script functionality remains intact.
        ContentType and CacheControl remains to be sorted under ICloudBlob.Properties.
    
        "WARNING: Upcoming breaking changes in the cmdlet 'Get-AzStorageBlob' :
        The returned blob properties will be moved from ICloudBlob.Properties to BlobProperties in a future release.

        Note : Go to https://aka.ms/azps-changewarnings for steps to suppress this breaking change warning, and other information on
        breaking changes in Azure PowerShell."
    19.10.22:
    - Add Set-BlobProperties
    - Restructure upload section to avoid potentionally calling SetPropertiesAsync() twice
    12.09.22:
    - Add logic to pipeline to support multi-environment deployment (check for existance of $ENV:ISBRANDING) (assumes "Development" as branding $environmentFolder)
    18.08.22:
    - Replace Write-Warning with Write-Host "##vso[task.logissue type=warning]" for improved logging when running in ADO pipeline.
    31.07.22:
    - Remove $EnvPrefix as required parameter for running script in a pipeline (only for local user context excecution of script).
    30.07.22:
    - Add check of $ContainerName variable to verify the existance of the container.
    - Update -Delete method for more efficient execution.
    25.07.22:
    - Improve output for running in pipeline.
    - Expand -EnvPrefix support to recognize following parameters: d + dev + development, t + test + test, p + prod + production
    - Add -Delete param with additional optional params -DeleteExtensions, -DeleteFolders, -DeleteFiles
    22.07.22:
    - Script can be run in context of an app principal by providing a client id and client secret.
    - Add more comments and output, remove unnecessary output, add check for input params for variable mapping.
    - Remove -TenantId for running in context of user account (keep for service principal as it's required for access_token issuance).
    21.07.22:
    - Script must be run in context of an authenticated user.
    - Script implements SupportsShouldProcess and can be used with -WhatIf and -Confirm.
.EXAMPLE
    PIPELINE execution:

    .\B2C-BlobManagement.ps1 -TenantId tid -Subscription sub -ClientId id -ClientSecret secret -Subscription sub -ResourceGroup rg -StorageAccountName sa -ContainerName container -SourceFolder pathToFolder

    Executed from a release pipeline, all variables will have to be assigned on the command line and principal must have requisite permissions to resources.
    Files in source directory will be uploaded, -Upload $true -Download $false doesn't have to be provided as upload is the default script behaviour.
.EXAMPLE
    PIPELINE execution:

    .\B2C-BlobManagement.ps1 -Upload $true -Download $false -Subscription sub -ResourceGroup rg -StorageAccountName sa

    TenantId, ClientId and ClientSecret can be read from $ENV: (environment) variables by matching param() default values.
.EXAMPLE
    USER exection:

    .\B2C-BlobManagement.ps1 -EnvPrefix d/t/p -Download:$true -Upload:$false -DestinationFolder C:\GIT\Destination (-WhatIf)

.EXAMPLE
    USER execution:

    .\B2C-BlobManagement.ps1 -EnvPrefix d/t/p -Download:$true -Upload:$false -DestinationFolder C:\GIT\Destination (-WhatIf)

    If all required parameters have been set in 'Manually configured variables' the script can be executed with only -EnvPrefix parameter (add -WhatIf to see what will happen).
    It is recommended to excplicitly configure -Upload and -Download params on the command line (default setting are $Upload:$true and $Download:$false).
    If provided as an input param -DestinationFolder will superseed settings in 'Manually configured variables'.
    The script will prompt for user credentials.
.EXAMPLE
    USER execution:

    .\B2C-BlobManagement.ps1 -EnvPrefix d/t/p -Username myUser@myDomain.com -Upload:$true -Download:$false -SourceFolder C:\GIT\Source (-WhatIf)

    As If all required parameters have been set in the script file it can be executed with only -EnvPrefix, add -Username to avoid account picker.
    Include -Username to directly select a specific user to sign in with, if script halts because user has no existing session look for a credentials prompt window.
    If provided as an input param -SourceFolder will superseed settings in 'Manually configured variables'.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    # Name of Azure tenant
    [Parameter(Mandatory = $false)]
    [string]$TenantId = $ENV:BRANDING_STORAGE_ACCOUNT_TENANTID,
    # App registration identifier    
    [Parameter(Mandatory = $false)]
    [string]$ClientId = $ENV:CONTENT_DEPLOYMENT_APP_REGISTRATION_CLIENTID,
    # App registration secret
    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $ENV:CONTENT_DEPLOYMENT_APP_REGISTRATION_CLIENTSECRET,
    # Account name to connect to Azure AD
    [Parameter(Mandatory = $false)]
    [String] $Username,
    # Environment prefix for Azure AD (only used when running script in user context)
    [Parameter(Mandatory = $false)]
    [String] $EnvPrefix,
    # If script should upload files to storage container
    [Parameter(Mandatory = $false)]
    [bool] $Upload = $true,
    # If script should upload files, where to fetch them
    [Parameter(Mandatory = $false)]
    [string] $SourceFolder,
    # If script should download blobs from storage container
    [Parameter(Mandatory = $false)]
    [bool] $Download = $false,
    # If script should download blobs, where to store them
    [Parameter(Mandatory = $false)]
    [string] $DestinationFolder,
    # If script should delete blobs from storage container
    [Parameter(Mandatory = $false)]
    [bool] $Delete = $false,
    [Parameter(Mandatory = $false)]
    [bool] $NoTestPreReqs = $false,
    [Parameter(Mandatory = $false)]
    $DeleteExtensions,
    [Parameter(Mandatory = $false)]
    $DeleteFolders,
    [Parameter(Mandatory = $false)]
    $DeleteFiles,
    # Azure subscription holding resource group
    [Parameter(Mandatory = $false)]
    [String] $Subscription,
    # Resource group holding storage container
    [Parameter(Mandatory = $false)]
    [String] $ResourceGroup,
    # Storage container name
    [Parameter(Mandatory = $false)]
    [String] $StorageAccountName,
    # Storage container name
    [Parameter(Mandatory = $false)]
    [String] $ContainerName = "branding"
)

#region Manually configured variables
# Overrides for default values from param block
$ContainerOverride #= "branding"
$UploadOverride #= $true
$DownloadOverride #= $false
$NoTestPreReqsOverride #= $true

# Container name, folder names and storage account names for various B2C environments
$DestinationFolderD = "C:\GIT\ProjectX\branding dev"
$SourceFolderD = "C:\GIT\ProjectX\branding dev"
$StorageAccountNameD = "storageAccountDev"
$ResourceGroupD = "resourceGroupTest"
$SubscriptionD = "d"

$DestinationFolderT = "C:\GIT\ProjectX\branding test"
$SourceFolderT = "C:\GIT\ProjectX\branding test"
$StorageAccountNameT = "storageAccountTest"
$ResourceGroupT = "resourceGroupTest"
$SubscriptionT = "t"

$DestinationFolderP = "C:\GIT\ProjectX\branding prod"
$SourceFolderP = "C:\GIT\ProjectX\branding prod"
$StorageAccountNameP = "storageAccountProd"
$ResourceGroupP = "resourceGroupProd"
$SubscriptionP = "p"

# Omit setting variables based $EnvPrefix if run in pipeline (assuming $ClientId and $ClientSecret only will be used for running in pipeline)
if (-not ($ClientId -and $ClientSecret)) {
    $EnvPrefix = $EnvPrefix.ToLower()
    # For local execution, REMEMBER to change these settings to reflect the environment to access D = dev / T = test / P = prod 
    if (-not ($EnvPrefix -and ($EnvPrefix -eq "d" -or $EnvPrefix -eq "dev" -or $EnvPrefix -eq "development" -or $EnvPrefix -eq "t" -or $EnvPrefix -eq "test" -or $EnvPrefix -eq "p" -or $EnvPrefix -eq "prod" -or $EnvPrefix -eq "production")) ) {
        $EnvPrefix = Read-Host -Prompt "Specify environment: d / t / p"
        if (-not ($EnvPrefix -eq "d" -or $EnvPrefix -eq "t" -or $EnvPrefix -eq "p")) {
            Write-Host "Did you really enter d, t or p when prompted?!?!" -ForegroundColor Red; Read-Host
        }
    }
    # Set variables according to environment, check which input parameters have been provided at execution
    if ($EnvPrefix -eq "d" -or $EnvPrefix -eq "dev" -or $EnvPrefix -eq "development") { if (-not $Subscription) { $Subscription = $SubscriptionD }; if (-not $ResourceGroup) { $ResourceGroup = $ResourceGroupD }; if (-not $StorageAccountName) { $StorageAccountName = $StorageAccountNameD }; if (-not $SourceFolder) { $SourceFolder = $SourceFolderD }; if (-not $DestinationFolder) { $DestinationFolder = $DestinationFolderD } }
    if ($EnvPrefix -eq "t" -or $EnvPrefix -eq "test") { if (-not $Subscription) { $Subscription = $SubscriptionT }; if (-not $ResourceGroup) { $ResourceGroup = $ResourceGroupT }; if (-not $StorageAccountName) { $StorageAccountName = $StorageAccountNameT }; if (-not $SourceFolder) { $SourceFolder = $SourceFolderT }; if (-not $DestinationFolder) { $DestinationFolder = $DestinationFolderT } }
    if ($EnvPrefix -eq "p" -or $EnvPrefix -eq "prod" -or $EnvPrefix -eq "production") { if (-not $Subscription) { $Subscription = $SubscriptionP }; if (-not $ResourceGroup) { $ResourceGroup = $ResourceGroupP }; if (-not $StorageAccountName) { $StorageAccountName = $StorageAccountNameP }; if (-not $SourceFolder) { $SourceFolder = $SourceFolderP }; if (-not $DestinationFolder) { $DestinationFolder = $DestinationFolderP } }
    if ($ContainerOverride) { $ContainerName = $ContainerOverride }
    if ($UploadOverride) { $Upload = $UploadOverride }
    if ($DownloadOverride) { $Download = $DownloadOverride }
}
#endregion

# Check for pre-requisite modules (and Nuget package manager) for running script
function Test-RequiredModules {
    param (
        [Parameter(Mandatory = $true)]
        $Modules,
        [Parameter(Mandatory = $false)]
        $WhatIf = $false
    )
    # Implemented to avoid SupportsShouldProcess to WhatIf pre-requisites check and crashing the script
    $WhatIfPreference = $WhatIf
        
    # Pre-requisite modules check and installation of missing packages
    if ($Modules) {
        Write-Host "[group]Checking for pre-requisite module(s)..."
        # Checking for Nuget package manager required for package installation
        if (-not (Get-PackageProvider -Name "Nuget")) {
            Write-Host "First, installing package provider Nuget..."
            Install-PackageProvider -Name NuGet -MinimumVersion 3.0.0.1 -Scope CurrentUser -Force | Out-Null
        }
        foreach ($mod in $Modules) {
            Write-Host $mod
        }
        $mods = (Get-Module -ListAvailable).Name | Get-Unique
        foreach ($item in $Modules) {
            if ($item -notin $mods) {
                Write-Host "Installing $item..."
                Install-Module -Name $item -Scope CurrentUser -Force -WhatIf:$WhatIfPreference | Out-Null
            }
        }
        Write-Host "[endgroup]"
    }
}

# Test for existance of required modules and install if missing
if ($NoTestPreReqs -ne $true -and $NoTestPreReqsOverride -ne $true) {
    Test-RequiredModules -Modules "Az.Accounts", "Az.Storage" -WhatIf:$false
}

# If app principal id and secret is provided, use access_token to connect to ARM
if ($ClientId -and $ClientSecret) {
    try {
        # Connect to Azure with service principal
        Write-Host "Getting an access_token to Azure resource manager..."
        $uri = "https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $TenantId
        $body = "scope=https://management.core.windows.net/.default&client_id=$($ClientId)&grant_type=client_credentials&client_secret={0}" -f [System.Net.WebUtility]::UrlEncode($ClientSecret)
        $token = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        
        Write-Host "Connecting to Azure..."
        Connect-AzAccount -AccountId $ClientId -Subscription $Subscription -AccessToken $($token.access_token) -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "##vso[task.logissue type=warning]Could not authenticate with service principal. Aborting..."
        break;
    }
}
# If app principal id and secret is NOT provided, initiate user context to connect to ARM
else {
    # Connect to Azure with user account
    try {
        $WarnPrefPop = $WarningPreference
        $WarningPreference = "SilentlyContinue"
        if ($Username) {
            # Set warning preference to avoid output of other subscriptions, add | Out-Null to remove standard successful Connect-AzAccount output
            Write-Host "Connecting to Azure with user account..."
            Connect-AzAccount -Subscription $Subscription -AccountId $Username | Out-Null
        }
        else {
            Connect-AzAccount -Subscription $Subscription | Out-Null
        }
        $WarningPreference = $WarnPrefPop
    }
    catch {
        Write-Warning "Could not authenticate with signed in account. Aborting..."
        break;
    }
}

# Contains operations required for both uploading and downloading
function Get-StorageAccountContext {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string] $StorageAccountName
    )
    # Get storage account key
    $StorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroup -AccountName $StorageAccountName).Value[-1]

    # COMMON : Must be run prior to downloading or uploading blobs from / to storage container

    # Set storage account context
    $Context = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

    # Return context
    return $Context

    # COMMON: End
}

function Get-BlobsUsingContext {
    param (
        # Container with blobs
        [Parameter(Mandatory = $true)]
        [string] $ContainerName,
        # Context, required for accessing container
        [Parameter(Mandatory = $true)]
        $Context
    )
    # List all blobs
    $Blobs = Get-AzStorageBlob -Container $ContainerName -Context $Context
    # Return blobs
    return $Blobs
}

function Set-ContentType {
    param (
        # Blob to set cache control
        [Parameter(Mandatory = $true)]
        $Blob
    )
    
    # Set content type according to extension
    $contentType = ""
    $extension = [IO.Path]::GetExtension($Blob.Name)
    Switch ($extension) {
        ".png" { $contentType = "image/png" }
        ".WOFF" { $contentType = "font/woff" }
        ".svg" { $contentType = "image/svg+xml" }
        ".js" { $contentType = "text/javascript" }
        ".html" { $contentType = "text/html; charset=utf 8" }
        ".css" { $contentType = "text/css; charset=utf 8" }
        ".xml" { $contentType = "text/xml; charset=utf 8" }
        Default { $contentType = "" }
    }
        
    if ($Blob.contentType.ToString() -ne $contentType) {
        Write-Host "Blob extension is $extension - content type will be set to $contentType."
        $($Blob.ICloudBlob).Properties.contentType = $contentType
    }
}

function Set-CacheControl {
    param (
        # Blob to set cache control
        [Parameter(Mandatory = $true)]    
        $Blob,
        # Blob cache control max age (in seconds)
        [Parameter(Mandatory = $true)]
        $MaxAge
    )

    Write-Host "Cache control setting for $($Blob.Name) will be set to $($MaxAge) seconds."
    $($Blob.ICloudBlob).Properties.CacheControl = "max-age-$($MaxAge)"
}

function Set-BlobProperties {
    param (
        # Blob to be updated
        [Parameter(Mandatory = $true)]
        $Blob
    )

    $task = $($Blob.ICloudBlob).SetPropertiesAsync()
    $task.Wait()
    Write-Host "Task status: $($task.Status)."
}

#region DOWNLOAD : Download blobs from storage container
#
if ($Download -eq $false) {
    Write-Host "`$Download set to `$false, skipping step..."
}
else {
    # Create local folder if it does not already exist
    if (($Download -eq $true) -and ($Upload -ne $true)) {

        # Script implements SupportsShouldProcess and can therefore be run with -WhatIf and -Confirm parameters
        if ($PSCmdlet.ShouldProcess($($StorageAccountName), 'Downloading custom branding')) {
            try {
                Write-Host "`$Download is `$true - starting download procedure."
                $Context = Get-StorageAccountContext -ResourceGroup $ResourceGroup -StorageAccountName $StorageAccountName

                # Check for existance of branding container $ContainerName
                if (-not (Get-AzStorageContainer -Name $ContainerName -Context $Context -ErrorAction SilentlyContinue)) {
                    Write-Host "##vso[task.logissue type=warning]Variable `$ContainerName $($ContainerName) points to a non-existing container on storage account $($StorageAccountName)"
                    break;
                }

                Write-Host "Gathering files in container $($ContainerName)..."
                $Blobs = Get-BlobsUsingContext -ContainerName $ContainerName -Context $Context

                if (-not (Test-Path $DestinationFolder)) {
                    Write-Host "Creating folder $($DestinationFolder)..."
                    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
                }

                # Download files from container to local folder
                Write-Host "[group]Downloading files to (local) folder..."
                $Blobs | Get-AzStorageBlobContent -Destination $DestinationFolder -Context $Context -Force
                Write-Host "[endgroup]"
                Write-Host "Download complete!"
            }
            catch {
                Write-Error "Failed to get blobs!"
                break;
            }
        }
        else {
            Write-Host "Would start downloading to local folder $($DestinationFolder) from $($StorageAccountName) and container $($ContainerName)"
        }
    }
    else {
        Write-Host "##vso[task.logissue type=warning]Did not take any action as both Download and Upload variables were set to `$true"
    }
}
#
#endregion DOWNLOAD : End

#region UPLOAD : Get files from local folder and upload to storage container
#
if ($Upload -eq $false) {
    Write-Host "`$Upload set to `$false, skipping step..."
}
else {
    if (($Upload -eq $true) -and ($Download -ne $true)) {
        
        #region For pipeline execution of multiple environments
        # Outside of ShouldSupportsProcess to output correct path when -WhatIf:`$true
        if ($ENV:ISBRANDING -eq $true) {
            # Set $environmentFolder to "Development"
            $environmentFolder = "Development"
            # See if environment_folder matches "Dev"
            if (-not ($ENV:ENVIRONMENT_FOLDER -match "Dev")) {
                # Check if environment_folder exists
                if (Test-Path "$PSScriptRoot/../Environments/$($ENV:ENVIRONMENT_FOLDER)") {
                    Write-Host "##vso[task.logissue type=warning]Setting path to $environmentFolder..." -ErrorAction Continue
                    $environmentFolder = $ENV:ENVIRONMENT_FOLDER
                }
            }
            # Set $environmentPath for verifying path of custom branding content and policy files
            $environmentPath = Join-Path "$PSScriptRoot/../Environments" $environmentFolder
            $SourceFolder = Join-Path $environmentPath $ContainerName
        }
        #endregion

        # Script implements SupportsShouldProcess and can therefore be run with -WhatIf and -Confirm parameters
        if ($PSCmdlet.ShouldProcess($($StorageAccountName), 'Uploading custom branding')) {
            try {
                Write-Host "`$Upload is `$true - starting upload procedure."
                # Get authentication context, required for accessing storage account container
                Write-Host "Getting context..."
                $Context = Get-StorageAccountContext -ResourceGroup $ResourceGroup -StorageAccountName $StorageAccountName

                # Check for existance of local folder $SourceFolder
                if (-not (Test-Path $SourceFolder)) {
                    Write-Host "##vso[task.logissue type=warning]Variable `$SourceFolder $($SourceFolder) points to a non-existing folder"
                    break;
                }

                # Check for existance of branding container $ContainerName
                if (-not (Get-AzStorageContainer -Name $ContainerName -Context $Context -ErrorAction SilentlyContinue)) {
                    Write-Host "##vso[task.logissue type=warning]Variable `$ContainerName $($ContainerName) points to a non-existing container on storage account $($StorageAccountName)"
                    break;
                }

                # Upload files to storage account and container
                Write-Host "Gathering files in $($SourceFolder)..."
                Write-Host "[group]Uploading files to container..."
                Get-ChildItem -Path $SourceFolder -File -Recurse | Set-AzStorageBlobContent -Container $ContainerName -Context $Context -Force
                Write-Host "[endgroup]"

                #region Process blobs
                # Create list of blobs from container content
                $Blobs = Get-BlobsUsingContext -ContainerName $ContainerName -Context $Context

                Write-Host "Setting blob properties..."
                # Run through list of blobs and update content type, cache control properties
                foreach ($b in $Blobs) {
                    Write-Host "[group]Processing blob: $($b.Name)"
                    
                    Write-Host "Setting content type based on .extension..."
                    # Set blob content type based on .extension
                    Set-ContentType -Blob $b
                    
                    Write-Host "Setting cache control..."
                    # Check if any of the blobs match the regular expression
                    if ($b.Name -match "JS/unified.js") {
                        # Set blob cache property in seconds
                        $cacheAgeInSeconds = 30
                        Set-CacheControl -Blob $b -MaxAge $cacheAgeInSeconds
                    }

                    Write-Host "Updating blob..."
                    Set-BlobProperties -Blob $b

                    Write-Host "[endgroup]"
                }
                Write-Host "[endgroup]Uploading blobs complete, properties applied!"
                #endregion
            }
            catch {
                Write-Error "Failed when getting or setting (uploading / overwriting) blobs!"
                break;
            }
        }
        else {
            Write-Host "Would start uploading from local folder $($SourceFolder) to storage account $($StorageAccountName) and container $($ContainerName) and set content types"
        }
    }
    else {
        Write-Host "##vso[task.logissue type=warning]Did not take any action as both Upload and Download variables were set to `$true"
    }
}
#
#endregion UPLOAD : End

#region DELETE
#
if ($Upload -eq $false -and $Download -eq $false -and $Delete -eq $true) {
    Write-Host "`$Upload set to `$false, download set to `$false, delete set to `$true. Executing step..."

    # Script implements SupportsShouldProcess and can therefore be run with -WhatIf and -Confirm parameters
    if ($PSCmdlet.ShouldProcess($($ContainerName), 'Delete content in container')) {
        try {
            Write-Host "`$Delete is `$true - starting cleanup process."
            # Get authentication context, required for accessing storage account container
            Write-Host "Getting context..."
            $Context = Get-StorageAccountContext -ResourceGroup $ResourceGroup -StorageAccountName $StorageAccountName
            # Get files from storage account and container
            Write-Host "Gathering files in container $($ContainerName)..."
            $Blobs = Get-BlobsUsingContext -ContainerName $ContainerName -Context $Context
            if ($DeleteExtensions) {
                Write-Host "[group]Deleting file(s) (and folder(s)) matching provided extension(s)..."
                foreach ($ext in $DeleteExtensions) {
                    ($Blobs | Where-Object { $_.name -like "*.$ext" }) | Remove-AzStorageBlob -Verbose -ErrorAction Continue
                }
            }
            elseif ($DeleteFolders) {
                Write-Host "[group]Deleting matching folder(s) and all content..."
                foreach ($folder in $DeleteFolders) {
                    ($Blobs | Where-Object { $_.name -like "*$folder/*" }) | Remove-AzStorageBlob -Verbose -ErrorAction Continue
                }
            }
            elseif ($DeleteFiles) {
                Write-Host "[group]Deleting file(s) matching name(s)..."
                foreach ($file in $DeleteFiles) {
                    ($Blobs | Where-Object { $_.name -match $file }) | Remove-AzStorageBlob -Verbose -ErrorAction Continue
                }
            }
            else {
                Write-Host "[group]Deleting files..."
                $Blobs | Remove-AzStorageBlob -Verbose -ErrorAction Continue
            }
            Write-Host "[endgroup]"
            Write-Host "Cleanup complete!"
        }
        catch {
            Write-Error "Failed while deleting blobs!"
            break;
        }
    }
}
#
#endregion DELETE : End