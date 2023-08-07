##############################################
#
# New-AzureADUser to be replaced by New-MgUser
#

# Enter tenant native B2C admin credential in the popup
$B2CCred = Get-Credential

# Requires AzureAD Powershell Module (to be deprecated, but will continue to work)
Connect-AzureAD -Credential $B2CCred

# Create single B2C user

# Required parameters
$UserName  = ""
$DisplayName = ""
$EmailAddress = ""
# Does not have to be at least 15 characters with complexity, but for testing, why not?
$Password = "thePassphrase!23"

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

# Create B2C user (replace / empty any underscore in displayName)
New-AzureADUser `
    -DisplayName $DisplayName.Replace('_', ' ') `
    -CreationType "LocalAccount" `
    -AccountEnabled $true `
    -PasswordProfile $PasswordProfile `
    -SignInNames $SignInNames

# Create B2C user from CSV

# Set file path and import, expects colums for displayName, firstname, lastname, customerNumer, emailAddress
# Expects semicolon as delimiter, update CSV or this line according to data export
Import-Csv -Path "$(Get-Location)\testUsers.csv" -Delimiter ";" |
    # Loop through each line holding a user in CSV
    ForEach-Object {
        $SignInNames = @(
            (New-Object `
                Microsoft.Open.AzureAD.Model.SignInName `
                -Property @{Type = "customerNumber"; Value = $_.customerNumber}),
            (New-Object `
                Microsoft.Open.AzureAD.Model.SignInName `
                -Property @{Type = "emailAddress"; Value = $_.emailAddress})
        )

        # Create a random password by calling NewGuid()
        $PasswordProfile = New-Object `
            -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile `
            -Property @{ 
                'Password' = [guid]::NewGuid();
                'ForceChangePasswordNextLogin' = $true;
                'EnforceChangePasswordPolicy' = $false;
        }

        # Create B2C user
        New-AzureADUser `
            -DisplayName $($_.displayName) `
            -GivenName $($_.firstname) `
            -Surname $($_.lastname) `
            -CreationType "LocalAccount" `
            -AccountEnabled $true `
            -PasswordProfile $PasswordProfile `
            -SignInNames $SignInNames `
            -ErrorAction Stop

        # Output created user information
        Write-Host "Created user: `n 
            DisplayName $($_.displayName) `n
            GivenName $($_.firstname) `n
            Surname $($_.lastname) `n
            SignInNames $SignInNames"
    }