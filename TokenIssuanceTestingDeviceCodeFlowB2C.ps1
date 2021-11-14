#############################################################
# Get devide_code from B2C app
#############################################################

# The client ID for the app registration, app must be Public client for tokens to be issued
$tenantName = 'xxx'
$clientId = 'xxx'
# API client ID not necessary as the device code flow gathers all scopes available to the application used
# $apiClientId = 'xxx'
# $resource =  'https://{0}/{1}/write ' -f $tenantName, $apiClientId # https://{0}/{1}/write
$scope = 'openid ' + $resource

# $Uri = "https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode"
$Uri = "https://login.microsoftonline.com/{0}/oauth2/v2.0/devicecode" -f $tenantName
$Body = @{
    "client_id" = $clientId
    "scope" = $scope
}

$result = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body

Write-Output $result.message

###############################################
# Poll the /token endpoint for tokens
# REMEMBER that the client_id of the app must be configured as a Public client
###############################################

$grantType = "device_code"
# $Uri = "https://login.microsoftonline.com/organizations/oauth2/v2.0/token"
$Uri = "https://login.microsoftonline.com/{0}/oauth2/v2.0/token" -f $tenantName

$Body = @{
    "grant_type" = $grantType
    "client_id" = $clientId
    "code" = $result.device_code
}

$token = Invoke-RestMethod -Uri $Uri -Method Post -Body $Body
Write-Output $token