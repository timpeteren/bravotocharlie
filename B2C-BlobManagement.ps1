<#
.SYNOPSIS
    Uploads or downloads files from a local folder to an Azure storage account blob container.
.DESCRIPTION
    The script was created for use in a release pipeline, for deployment of AAD B2C custom branding files to an Azure storage account container.
    Used in a pipeline, service principal credentials must be provided in context of the running pipeline.
    
    However, the script has been extended to also handle direct excecution.
    With direct execution the script runs in the context of a user account.
    When run in a shell the script can be configured either way:
        a) Provide variables as parameters when executing (as for pipeline execution)
        b) Fill out variables in '#region Manually configured variables'.
.NOTES
    22.07.22:
    Add more comments and output, remove unnecessary output, remove -TenantId(entifier) that was not used, add check for input params for variable mapping
    21.07.22:
    Script implements SupportsShouldProcess and can be used with -WhatIf and -Confirm.
.EXAMPLE
    .\B2C-BlobManagement.ps1 -EnvPrefix d/t/p -Upload $true -Download $false -Subscription sub -ResourcGroup rg -StorageAccountName sa -ClientId xxx -ClientSecret yyy

    Executed from a release pipeline, all variables will have to be assigned on the command line and principal must have requisite permissions to resources.
.EXAMPLE
    .\B2C-BlobManagement.ps1 -EnvPrefix d/t/p -Download:$true -Upload:$false -DestinationFolder C:\GIT\Destination (-WhatIf)

    If all required parameters have been set in 'Manually configured variables' the script can be executed with only -EnvPrefix parameter (add -WhatIf to see what will happen).
    It is recommended to excplicitly configure -Upload and -Download params on the command line (default setting is $Upload:$true and $Download:$false).
    If provided as an input param -DestinationFolder will superseed settings in 'Manually configured variables'.
    The script will prompt for user credentials.
.EXAMPLE
    .\B2C-BlobManagement.ps1 -EnvPrefix d/t/p -Username myUser@myDomain.com -Upload:$true -Download:$false -SourceFolder C:\GIT\Source (-WhatIf)

    As If all required parameters have been set in the script file it can be executed with only -EnvPrefix, add -Username to avoid account picker.
    Include -Username to directly select a specific user to sign in with, if script halts because user has no existing session look for a credentials prompt window.
    If provided as an input param -SourceFolder will superseed settings in 'Manually configured variables'.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param (
    # Account name to connect to Azure AD tenant
    [Parameter(Mandatory=$false)]
    [String] $Username,
    # Environment prefix for Azure AD tenant
    [Parameter(Mandatory=$false)]
    [String] $EnvPrefix,
    # If script should upload files to storage container
    [Parameter(Mandatory=$false)]
    [bool] $Upload = $true,
    # If script should upload files, where to fetch them
    [Parameter(Mandatory=$false)]
    [string] $SourceFolder,
    # If script should download blobs from storage container
    [Parameter(Mandatory=$false)]
    [bool] $Download = $false,
    # If script should download blobs, where to store them
    [Parameter(Mandatory=$false)]
    [string] $DestinationFolder,
    # Azure subscription holding resource group
    [Parameter(Mandatory=$false)]
    [String] $Subscription,
    # Resource group holding storage container
    [Parameter(Mandatory=$false)]
    [String] $ResourceGroup,
    # Storage container name
    [Parameter(Mandatory=$false)]
    [String] $StorageAccountName,
    # Storage container name
    [Parameter(Mandatory=$false)]
    [String] $ContainerName = "branding"
)

# Pre-requisites check and resolve missing packages
# Get-Module -Listavailable | Where-Object {$_.Name -eq "Az.Storage"}
# if not # Get-PackageProvider -ListAvailable | Where-Object {$_.Name -eq NuGet}
# Get-PackageProvider -Name Nuget
# Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force # -WhatIf
# Install-Module -Name Az.Storage -Scope CurrentUser -Force # -WhatIf

#region Manually configured variables
# Overrides for default values from param block
$ContainerOverride #= "branding"
$UploadOverride #= $true
$DownloadOverride #= $false

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
#endregion

# For local execution, REMEMBER to change these settings to reflect the environment to access D = dev / T = test / P = prod 
if (-not ($EnvPrefix -and ($EnvPrefix.ToLower() -eq "d" -or $EnvPrefix.ToLower() -eq "t" -or $EnvPrefix.ToLower() -eq "p")) ) {
    $EnvPrefix = Read-Host -Prompt "Specify environment: d / t / p"
    if (-not ($EnvPrefix.ToLower() -eq "d" -or $EnvPrefix.ToLower() -eq "t" -or $EnvPrefix.ToLower() -eq "p")) {
        Write-Host "Did you really enter d, t or p when prompted?!?!" -ForegroundColor Red; Read-Host
    }
}

# Set variables according to environment, check which input parameters have been provided at execution
if ($EnvPrefix -eq "d") { if (-not $Subscription) {$Subscription = $SubscriptionD }; if (-not $ResourceGroup) { $ResourceGroup = $ResourceGroupD }; if (-not $StorageAccountName) { $StorageAccountName = $StorageAccountNameD }; if (-not $SourceFolder) { $SourceFolder = $SourceFolderD }; if (-not $DestinationFolder) { $DestinationFolder = $DestinationFolderD } }
if ($EnvPrefix -eq "t") { if (-not $Subscription) {$Subscription = $SubscriptionT }; if (-not $ResourceGroup) { $ResourceGroup = $ResourceGroupT }; if (-not $StorageAccountName) { $StorageAccountName = $StorageAccountNameT }; if (-not $SourceFolder) { $SourceFolder = $SourceFolderT }; if (-not $DestinationFolder) { $DestinationFolder = $DestinationFolderT } }
if ($EnvPrefix -eq "p") { if (-not $Subscription) {$Subscription = $SubscriptionP }; if (-not $ResourceGroup) { $ResourceGroup = $ResourceGroupP }; if (-not $StorageAccountName) { $StorageAccountName = $StorageAccountNameP }; if (-not $SourceFolder) { $SourceFolder = $SourceFolderP }; if (-not $DestinationFolder) { $DestinationFolder = $DestinationFolderP } }
if ($ContainerOverride) { $ContainerName = $ContainerOverride }
if ($UploadOverride) { $Upload = $UploadOverride }
if ($DownloadOverride) {$Download = $DownloadOverride }

# Connect to Azure
try {
    if ($Username) {
        # Set warning preference to avoid output of other subscriptions, remove | Out-Null to see standard successful Connect-AzAccount output
        $WarnPrefPop = $WarningPreference
        $WarningPreference = "SilentlyContinue"
        Connect-AzAccount -Subscription $Subscription -AccountId $Username -ErrorAction Stop | Out-Null
        $WarningPreference = $WarnPrefPop
    } else {
        # Set warning preference to avoid output of other subscriptions, remove | Out-Null to see standard successful Connect-AzAccount output
        $WarnPrefPop = $WarningPreference
        $WarningPreference = "SilentlyContinue"
        Connect-AzAccount -Subscription $Subscription -ErrorAction Stop | Out-Null
        $WarningPreference = $WarnPrefPop
    }
}
catch {
    Write-Warning "Could not authenticate with supplied credentials. Aborting..."
    break;
}

# Contains operations required for both uploading and downloading
function Get-StorageAccountContext {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ResourceGroup,
        [Parameter(Mandatory=$true)]
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
    [Parameter(Mandatory=$true)]
    [string] $ContainerName,
    # Context, required for accessing container
    [Parameter(Mandatory=$true)]
    $Context
    )
    # List all blobs
    $Blobs = Get-AzStorageBlob -Container $ContainerName -Context $Context
    # Return blobs
    return $Blobs
}

function Set-ContentType {
    param (
        # List of blobs to set content type
        [Parameter(Mandatory=$true)]
        $Blobs,
        # Blob container
        [Parameter(Mandatory=$true)]
        $ContainerName,
        # Context, required for accessing container
        [Parameter(Mandatory=$true)]
        $Context
    )
    
    # Run through container blobs and set content type according to extension
    $Blobs = Get-AzStorageBlob -Container $ContainerName -Context $Context -Verbose
    foreach($Blob in $Blobs)
    {
        Write-Host "Processing Blob: $($Blob.Name)"    
        $Extension = [IO.Path]::GetExtension($Blob.Name)
        $ContentType = ""
        Switch ($Extension) {
            ".png" { $ContentType = "image/png" }
            ".WOFF" { $ContentType = "font/woff" }
            ".svg" { $ContentType = "image/svg+xml" }
            ".js" { $ContentType = "application/javascript" }
            ".html" { $ContentType = "text/html; charset=utf 8" }
            ".css" { $ContentType = "text/css; charset=utf 8" }
            ".xml" { $ContentType = "text/xml; charset=utf 8" }
            Default { $ContentType = "" }
        }
        
        if ($Blob.ContentType.ToString() -ne $ContentType) {
            Write-Host "Blob file extension is $Extension - content type will be set to $ContentType."
            $($Blob.ICloudBlob).Properties.ContentType = $ContentType
    
            $task = $($Blob.ICloudBlob).SetPropertiesAsync()
            $task.Wait()
            Write-Host "Task status: $($task.Status)."
        }
    }
}

function Set-CacheControl {
    param (
        # Blob to set cache control
        [Parameter(Mandatory=$true)]    
        $Blob,
        # Blob cache control max age (in seconds)
        [Parameter(Mandatory=$true)]
        $MaxAge
    )

    Write-Host "Cache control setting for $($Blob.Name) will be set to $($MaxAge) seconds."
    $($Blob.ICloudBlob).Properties.CacheControl = "max-age-$($MaxAge)"
    $task = $($Blob.ICloudBlob).SetPropertiesAsync()
    $task.Wait()
    Write-Host "Task status: $($task.Status)."
}

#region DOWNLOAD : Download blobs from storage container
#
if ($Download -eq $false) {
    Write-Host "`n`$Download set to `$false, skipping step..."
}
else {
    # Create local folder if it does not already exist
    if (($Download -eq $true) -and ($Upload -ne $true)) {

        # Script implements SupportsShouldProcess and can therefore be run with -WhatIf and -Confirm parameters
        if ($PSCmdlet.ShouldProcess($($StorageAccountName),'Downloading custom branding')) {
            try {
                Write-Host "`n`$Download is `$true - starting download procedure."
                $Context = Get-StorageAccountContext -ResourceGroup $ResourceGroup -StorageAccountName $StorageAccountName
                $Blobs = Get-BlobsUsingContext -ContainerName $ContainerName -Context $Context

                if (-not (Test-Path $DestinationFolder)) {
                    Write-Host "`nCreating folder $($DestinationFolder)..."
                    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
                }
                $Blobs | Get-AzStorageBlobContent -Destination $DestinationFolder -Context $Context -Force | Out-Null
                Write-Host "`nDownload complete!"
            }
            catch {
                Write-host "Failed to get blobs!" -ForegroundColor Red
                break;
            }
        }
        else {
            Write-Host "Would start downloading to local folder $($DestinationFolder) from $($StorageAccountName) and container $($ContainerName)"
        }
    }
    else {
        Write-Host "Did not take any action as both Download and Upload variables were set to `$true" -ForegroundColor Yellow
    }
}
#
#endregion DOWNLOAD : End

#region UPLOAD : Get files from local folder and upload to storage container
#
if ($Upload -eq $false) {
    Write-Host "`n`$Upload set to `$false, skipping step..."
}
else {
    if (($Upload -eq $true) -and ($Download -ne $true)) {
        
        # Script implements SupportsShouldProcess and can therefore be run with -WhatIf and -Confirm parameters
        if ($PSCmdlet.ShouldProcess($($StorageAccountName),'Uploading custom branding')) {
            try {
                Write-Host "`n`$Upload is `$true - starting upload procedure."
                # Get authentication context, required for accessing storage account container
                Write-Host "`nGetting context..."
                $Context = Get-StorageAccountContext -ResourceGroup $ResourceGroup -StorageAccountName $StorageAccountName
                
                # Upload files to storage account and container
                Write-Host "`nUploading files to container..."
                Get-ChildItem -Path $SourceFolder -File -Recurse | Set-AzStorageBlobContent -Container $ContainerName -Context $Context -Force | Out-Null
                $Blobs = Get-BlobsUsingContext -ContainerName $ContainerName -Context $Context
                Write-Host "`nSetting content type based on file extension..."
                Set-ContentType -Blobs $Blobs -ContainerName $ContainerName -Context $Context
                Write-Host "`nSetting cache control..."
                foreach ($b in $Blobs) {
                    if ($b.Name -match "JS/unified.js") {
                        Set-CacheControl -Blob $b -MaxAge 30
                    }
                }
                Write-Host "`nUpload complete!"
            }
            catch {
                Write-host "Failed when getting or setting (uploading / overwriting) blobs!" -ForegroundColor Red
                break;
            }
        }
        else {
            Write-Host "Would start uploading from local folder $($SourceFolder) to storage account $($StorageAccountName) and container $($ContainerName) and set content types"
        }
    }
    else {
        Write-Host "Did not take any action as both Upload and Download variables were set to `$true" -ForegroundColor Yellow
    }
}
#
#endregion UPLOAD : End

# Remove blobs
# ($blobs | Where-Object {$_.name -like "HTML/*"}) | Remove-AzStorageBlob -WhatIf