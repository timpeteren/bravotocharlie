<#
.SYNOPSIS
Get and or delete B2C users from Azure Active Directory Tenant

.DESCRIPTION
The script contains three modules, Get-Token, Get-B2CUsers and Delete-B2CUsers.
By dot-sourcing the file these modules can be run seperately.
Running the script requires the -UserObjects and -CredInput parameters to be provided.
To delete B2C users the -WhatIf parameter must be provided and set to -WhatIf:$false.

.NOTES
Written by Tim Peter Edstrøm, @timpeteren

.PARAMETER UserObjects
Optional parameter to allow the script to be dot-sourced to run the modules independently

.PARAMETER CredInput
Optional parameter to allow the script to be dot-source to run the modules independently

.PARAMETER TenantId
Optional parameter. If not provided parses the username of the $CredInput credential 

.PARAMETER WhatIf
Optional parameter. If not provided Delete-B2CUser uses the default setting $true

.EXAMPLE
Dot-source to get access to the cmdlets:
. .\B2CAuthOps.ps1

Run Get-B2CUserObjects to find existing users:
Get-B2CUserObjects -UserObjects "eik.dol@frag.com", "seki.sol@outlook.com" -CredInput $Cred

Run Delete-B2CUser to see what action will be taken by disabling WhatIf:
Get-B2CUserObjects -UserObjects "eik.dol@frag.com", "seki.sol@outlook.com" -CredInput $Cred | Delete-B2CUser -CredInput $Cred

Run Delete-B2CUser and disable Whatf to delete users:
Get-B2CUserObjects -UserObjects "eik.dol@frag.com", "seki.sol@outlook.com" -CredInput $Cred | Delete-B2CUser -CredInput $Cred -WhatIf:$false


Invoke script with existing credential object $Cred, with WhatIf enabled, to verify action to be taken by script:
.\B2CAuthOps.ps1 -UserObjects "eik.dol@frag.com", "seki.sol@outlook.com" -CredInput $Cred | Delete-B2CUser -CredInput $Cred

Invoke script with existing credential object $Cred and DELETE users:
\.B2CAuthOps.ps1 -UserObjects "eik.dol@frag.com", "seki.sol@outlook.com" -CredInput $Cred | Delete-B2CUser -CredInput $Cred -WhatIf:$false

.NOTES
Get-Token requires a public client app registration in the destination tenant. The application must be configured to delegate permissions.
The user must have the User.Read or Directory.AccessAsUser.All permission.
#>

Param (
    [Parameter(Mandatory = $false, Position = 0)]
    $UserObjects,
    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$CredInput,
    [Parameter(Mandatory = $false)]
    $TenantId,
    [Parameter(Mandatory = $false)]
    $WhatIf = $true
)


function Get-Token {
    Param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$CredInput,
        [Parameter(Mandatory = $true)]
        $TenantId
    )

    Begin {
        $ClientId = "a907e1e6-b546-4aef-8f27-ad5da7a85f56" # GraphAPI-B2C-CRUD-App
        $Username = $CredInput.UserName
        $Password = $CredInput.GetNetworkCredential().Password
    }

    Process {
        $Token = $null
        $GrantType = "password"
        $Uri = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token"
        
        
        $Body = @{
            "grant_type" = $GrantType
            "client_id"  = $ClientId
            "scope"      = "https://graph.windows.net/.default"
            "username"   = $Username
            "password"   = $Password
        }
        
        $Token = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded"
        return $Token.access_token
    }

    End
    {}
}

function Get-B2CUserObjects {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        $UserObjects,
        [Parameter(Mandatory = $true, Position = 1)]
        [System.Management.Automation.PSCredential]$CredInput,
        [Parameter(Mandatory = $false, Position = 2)]
        $TenantId
    )

    Begin {
        if ($TenantId -eq $null) { $TenantId = ($CredInput.UserName).Split("@")[1] }
    }

    Process {
        $Token = Get-Token -credInput $CredInput -tenantId $TenantId
        $AuthHeader = @{ Authorization = "Bearer $($Token)" }

        foreach ($user in $UserObjects) {
            
            $Uri = "https://graph.windows.net/$($TenantId)/users?api-version=1.6&`$filter=signInNames/any(x:x/value eq '$($user)')&`$sort=createdDateTime&`$select=objectId, displayName"
            $Subject = (Invoke-RestMethod -Method Get -Uri $Uri -Headers $AuthHeader).value
            
            $ReturnList += @($Subject | ForEach-Object {
                    [PSCustomObject]@{
                        ObjectId    = $_.objectId
                        DisplayName = $_.displayName
                    }
                })
        }
        return $ReturnList
    }

    End
    {}
}

function Delete-B2CUser {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        $UserObjects,
        [Parameter(Mandatory = $true, Position = 1)]
        [System.Management.Automation.PSCredential]$CredInput,
        [Parameter(Mandatory = $false, Position = 2)]
        $TenantId,
        [Parameter(Mandatory = $false, Position = 3)]
        [bool] $WhatIf = $true
    )

    Begin {
        if ($null -eq $TenantId) { $TenantId = ($CredInput.UserName).Split("@")[1] }        
    }

    Process {
        $Token = Get-Token -credInput $CredInput -tenantId $TenantId
        $AuthHeader = @{ Authorization = "Bearer $($Token)" }

        foreach ($user in $UserObjects) {
            
            if ($WhatIf) {
                $Message = "Script ran with 'whatIf' flag set to true. Would delete user with displayName: '$($user.displayName)' and objectId: '$($user.ObjectId)'"
                Write-Verbose -Message $Message -Verbose
            } 
            else {
                $Uri = "https://graph.windows.net/$($TenantId)/users/$($user.ObjectId)?api-version=1.6"
                $Response = Invoke-WebRequest -Method Delete -Uri $Uri -Headers $AuthHeader
                
                if ($Response.StatusCode -ge 200 -and $Response.StatusCode -le 299) {
                    $Message = "Successfully deleted user with displayName: '$($user.displayName)' and objectId: '$($user.ObjectId)'"
                    Write-Verbose -Message $Message -Verbose
                }
                else {
                    $Message = "Something went wrong during deletion of user with displayName: '$($user.displayName)' and objectId: '$($user.ObjectId)'"
                    Write-Error -Message $Message
                }
            }
        } 
    }
    
    End 
    {}
}

if ($UserObjects) { Get-B2CUserObjects -UserObjects $UserObjects -CredInput $CredInput -TenantId $TenantId | Delete-B2CUser -CredInput $CredInput -WhatIf:$WhatIf }