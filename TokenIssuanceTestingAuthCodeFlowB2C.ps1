#############################################################
# Authorization code grant AAD B2C using custom policies
# App registration must be a B2C application (not Azure AD)
#############################################################

############################################################################
# Authorization code grant with Proof Key for Code Exchange snippets below
############################################################################

Add-Type -AssemblyName System.Web

# Your Client ID and Client Secret obtained when registering your WebApp
$tenantName = 'xxx.onmicrosoft.com'
$clientId = ''
# $apiClientId = 'xxxxx'
$clientSecret = ''  #  // NOTE: Only required for web apps bus NOT needed for single-page apps and PKCE 
$b2cPolicyName = 'b2c_1a_'
# $resource =  'https://{0}/{1}/user_impersonation' -f $tenantName, $apiClientId # https://{0}/{1}/write
$redirectUri = 'https://jwt.ms/'
$scope = 'openid profile offline_access ' + $resource

# UrlEncode the scope parameter because it contains the resource URL
$scopeEncoded = [System.Web.HttpUtility]::UrlEncode($scope)

Function Get-AuthCode {
    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object -TypeName System.Windows.Forms.Form -Property @{Width=512;Height=1024}
    $web  = New-Object -TypeName System.Windows.Forms.WebBrowser -Property @{Width=512;Height=1024;Url=($url -f ($scope -join "%20")) }

    $DocComp  = {
        $Global:uri = $web.Url.AbsoluteUri        
        if ($Global:uri -match "error=[^&]*|code=[^&]*") {$form.Close() }
    }
    $web.ScriptErrorsSuppressed = $true
    $web.Add_DocumentCompleted($DocComp)
    $form.Controls.Add($web)
    $form.Add_Shown({$form.Activate()})
    $form.ShowDialog() | Out-Null

    $queryOutput = [System.Web.HttpUtility]::ParseQueryString($web.Url.Query)
    $output = @{}
    foreach($key in $queryOutput.Keys){
        $output["$key"] = $queryOutput[$key]
    }

    $output
}

$BaseUri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/oauth2/v2.0/authorize" -f $tenantName
$result = $null
$url = "$($BaseUri)?" + `
        "client_id=$($clientId)" + `
        "&response_mode=query" + `
        "&response_type=code" + `
        "&redirect_uri=$($redirectUri)" + `
        "&scope=$($scopeEncoded)" + `
        "&p=$($b2cPolicyName)" + `
        "&state=myState" + `
        "&nonce=1234randomkr0234kfa12"

$result = Get-AuthCode
Write-Output $result

####################################################
# Now that you've acquired an authorization_code and have been granted permission by the user, you can redeem the code for an access_token to the desired resource.
# https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-v2-protocols-oauth-code
###################################################

###############################################
# Exchange Code with ID_Token and refresh_token
###############################################

$GrantType = "authorization_code"
$Uri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/$($b2cPolicyName)/oauth2/v2.0/token" -f $tenantName
$token = $null
$Body = @{
    "grant_type" = $GrantType
    "client_id" = $clientid
    "client_secret" = $clientSecret
    "code" = $result.code
    "scope" = $scope
    "redirect_uri" = $redirectUri
}

$token = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body
Write-Output $token

#######################
#### refresh_token ####
#######################
$GrantType = "refresh_token"
$Uri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/$($b2cPolicyName)/oauth2/v2.0/token" -f $tenantName
$refreshtoken = $null
$Body = @{
    "grant_type" = $GrantType
    "client_id" = $clientid
    "client_secret" = $clientSecret
    "refresh_token" = $token.refresh_token
    "scope" = $scope
    "redirect_uri" = $redirectUri
}

$refreshtoken = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body
Write-Output $refreshtoken

################
#### Logout ####
################

$LogoutUri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/$($b2cPolicyName)/oauth2/v2.0/logout" -f $tenantName
$logoutUrl =
"$($LogoutUri)?" + `
"client_id=$($clientid)" + `
"&post_logout_redirect_uri=$($redirectUri)"

Invoke-WebRequest -Uri $logoutUrl -Method Get


#############################################################
# Authorization code grant with Proof Key for Code Exchange
# Currently *only* employs 'plain' code_challenge_method
# Helper methods included to properly format code_challenge
#############################################################

# Helper methods
function Get-Base64UrlEncode {
    Param (
        [Parameter(Mandatory=$true)]
        [byte[]]
        $Bytes
    )

    [System.Convert]::ToBase64String($bytes).TrimEnd("=").Replace('+', '-').Replace('/', '_')
}

function Get-SHA256 {
    Param (
        [Parameter(Mandatory=$true)]
        [string]
        $String
    )

    $hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256')
    $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))

    #$hashString = [System.BitConverter]::ToString($hash)
    #$hashString.Replace('-', '')
}

# Generate code challenge
$code_challenge_original = (New-Guid).ToString()
$code_challenge = Get-Base64UrlEncode (Get-SHA256 $code_challenge_original)

$BaseUri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/oauth2/v2.0/authorize" -f $tenantName
$result = $null
$url = "$($BaseUri)?" + `
        "client_id=$($clientId)" + `
        "&response_mode=query" + `
        "&response_type=code" + `
        "&redirect_uri=$($redirectUri)" + `
        "&scope=$($scopeEncoded)" + `
        "&p=$($b2cPolicyName)" + `
        "&state=myState" + `
        "&code_challenge=$code_challenge" + `
        "&code_challenge_method=plain" + `
        "&nonce=1234randomkr0234kfa12"

$result = Get-AuthCode
Write-Output $result

###############################################
# Exchange Code for id_token and refresh_token
###############################################

$GrantType = "authorization_code"
$Uri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/$($b2cPolicyName)/oauth2/v2.0/token" -f $tenantName
$token = $null
$Body = @{
    "grant_type" = $GrantType
    "client_id" = $clientid
    "code" = $result.code
    "scope" = $scope
    "redirect_uri" = $redirectUri
    "code_verifier" = $code_challenge
}

$token = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body
Write-Output $token

#######################
#### refresh_token ####
#######################

$GrantType = "refresh_token"
$Uri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/$($b2cPolicyName)/oauth2/v2.0/token" -f $tenantName
$refreshtoken = $null
$Body = @{
    "grant_type" = $GrantType
    "client_id" = $clientid
    "refresh_token" = $token.refresh_token
    "scope" = $scope
    "redirect_uri" = $redirectUri
}

$refreshtoken = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body
Write-Output $refreshtoken
