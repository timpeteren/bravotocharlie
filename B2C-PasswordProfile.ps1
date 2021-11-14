#########################

$newUser = Get-AzureADUser -ObjectId ""

# Alternative 1
$pwdProf = @{
        "password" = "123456"
        "ForceChangePasswordNextLogin" = $false
        "EnforceChangePasswordPolicy" = $false
}

# Alternative 2
# $pwdProf = [Microsoft.Open.AzureAD.Model.PasswordProfile]::new()

# $pwdProf.Password = "123456"
# $pwdProf.ForceChangePasswordNextLogin = $false
# $pwdProf.EnforceChangePasswordPolicy = $false

Set-AzureADUser -ObjectId $newUser.ObjectId -PasswordProfile $pwdProf -PasswordPolicies "DisableStrongPassword, DisablePasswordExpiration"

#########################