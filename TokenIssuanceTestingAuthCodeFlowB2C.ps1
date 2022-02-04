#############################################################
# Get OIDC Code from B2C using custom policies
# App referenced must be a B2C application (not Azure AD)
#############################################################

Add-Type -AssemblyName System.Web

# Your Client ID and Client Secret obtained when registering your WebApp
$tenantName = 'tenant-name.onmicrosoft.com'
$clientId = 'xxxxx'
$apiClientId = 'xxxxx'
$clientSecret = ''  #  // NOTE: Only required for web apps
$b2cPolicyName = 'b2c_1_signupsignin'
$resource =  'https://{0}/{1}/user_impersonation' -f $tenantName, $apiClientId # https://{0}/{1}/write
$redirectUri = 'https://jwt.ms/'
$scope = 'openid offline_access ' + $resource

# UrlEncode the scope parameter because it contains the resource URL
$scopeEncoded = [System.Web.HttpUtility]::UrlEncode($scope)
# No longer required to encode redirect URI
# $redirectUriEncoded =  [System.Web.HttpUtility]::UrlEncode($redirectUri)  

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
$url = "$($BaseUri)?" + `
        "client_id=$($clientId)" + `
        "&response_mode=query" + `
        "&response_type=code" + `
        "&redirect_uri=$($redirectUri)" + `
        # The redirect_uri of your app, where authentication responses can be sent and received by your app. It must exactly match one of the redirect_uris you registered in the portal, 
        # except it must be url encoded. For native & mobile apps, you should use the default value of https://login.microsoftonline.com/common/oauth2/nativeclient
        # no longer required to encode redirect_uri         "&redirect_uri=$($redirectUriEncoded)" + `
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

$Uri = "https://$($tenantName.Split('.')[0]).b2clogin.com/{0}/$($b2cPolicyName)/oauth2/v2.0/token" -f $tenantName
$GrantType = "refresh_token"

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