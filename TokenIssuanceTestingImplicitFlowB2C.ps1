Add-Type -AssemblyName System.Web

# Your Client ID and Client Secret obtained when registering your WebApp
$tenantName = '???.onmicrosoft.com'
$clientId = '???'
$apiClientId = '???'
$clientSecret = '???'  #  // NOTE: Only required for web apps
$b2cPolicyName = 'b2c_1a_v1_local_signupsignin'
$resource =  'https://{0}/{1}/write https://{0}/{1}/read' -f $tenantName, $apiClientId
$redirectUri = "https://localhost:8088"
$scope = 'openid profile offline_access ' + $resource


# UrlEncode the app ID redirect URI and scope parameter because it contains the resource URL
$redirectUriEncoded =  [System.Web.HttpUtility]::UrlEncode($redirectUri)
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


$BaseUri = "https://login.microsoftonline.com/{0}/oauth2/v2.0/authorize" -f $tenantName
$url = "$($BaseUri)?" + `
        "client_id=$($clientId)" + `
        "&response_mode=query" + `
        "&response_type=id_token+token" + `
        "&redirect_uri=$($redirectUriEncoded)" + `
        # The redirect_uri of your app, where authentication responses can be sent and received by your app. It must exactly match one of the redirect_uris you registered in the portal, 
        # except it must be url encoded. For native & mobile apps, you should use the default value of https://login.microsoftonline.com/common/oauth2/nativeclient
        "&scope=$($scopeEncoded)" + `
#        "&resource=$($resourceEncoded)" + ` &resource is included as a parameter in the &scope list
        "&p=$($b2cPolicyName)" + `
        "&state=myState" + `
        "&nonce=1234randomkr0234kfa14322" + `
        "&prompt=login"

$result = Get-AuthCode
Write-Output $result