##############################################
#
# New-AzureADUser to be replaced by New-MgUser
#

$AzureAdCred = Get-Credential
#enter local B2C admin credential in the popup

Connect-AzureAD -Credential $AzureAdCred

$UserName=""
$DisplayName = ""
$EmailAddress = ""
$Password = "whatAPassword!23"



$SignInNames = @(
    (New-Object `
        Microsoft.Open.AzureAD.Model.SignInName `
        -Property @{Type = "userName"; Value = $UserName}),
    (New-Object `
        Microsoft.Open.AzureAD.Model.SignInName `
        -Property @{Type = "emailAddress"; Value = $EmailAddress})
)

$PasswordProfile = New-Object `
    -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile `
    -Property @{ 
        'Password' = $Password;
        'ForceChangePasswordNextLogin' = $false;
        'EnforceChangePasswordPolicy' = $false;
}

New-AzureADUser `
    -DisplayName $DisplayName.Replace('_', ' ') `
    -CreationType "LocalAccount" `
    -AccountEnabled $true `
    -PasswordProfile $PasswordProfile `
    -SignInNames $SignInNames