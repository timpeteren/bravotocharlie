# Written by Lars-Jo Røsberg, TietoEvry
# Modified by Tim Peter Edstrøm, TietoEvry
#
# Script snippet, using PowerShell Graph SDK to search for users
#
# Script runs through objects in $ObjectsToCompare list using Foreach-Object.
# (This script does currently not contain code to populate $ObjectsToCompare variable)
# The ForEach-Object makes a filtered MS Graph API search of the 'identities' array to look for matches to $identifier
#
# Output is added to $FullDetails ArrayList, which consists of multiple PSCustomObject objects
#
# Finally, $FullDetails is converted to a CSV and output to file

$extAttrAppId       = "" # b2cprod.onmicrosoft.com
$extAttrName        = "yId"
$extensionAttribute = "extension_$($extAttrAppId)_$($extAttrName)"
$identifier         = "xId" # xId

$FullDetails = New-Object System.Collections.ArrayList

$ObjectsToCompare.$($identifier) | ForEach-Object {
    $Result = Get-MgUser -Filter "identities/any(c:c/issuerAssignedId eq '$($_)' and c/issuer eq 'something.no')" -Property *
    Write-Verbose "Email: $($Result | Select-Object -ExpandProperty identities | Where-Object { $_.SignInType -eq 'emailAddress' } | Select-Object -ExpandProperty IssuerAssignedId), `
                    VyId: $($_), `
                    EnturId: $($Result | ForEach-Object { $_.AdditionalProperties["$extensionAttribute"] } | Select-Object -First 1), `
                    B2CObjectId: $($Result.Id)" `
                    -Verbose

    if ($Result) {
        $FullDetails.Add( [PSCustomObject] @{
            Email = $Result | Select-Object -ExpandProperty identities | Where-Object { $_.SignInType -eq 'emailAddress' } | Select-Object -ExpandProperty IssuerAssignedId
            VyId = $_
            EnturId = $Result | ForEach-Object { $_.AdditionalProperties["$extensionAttribute"] } | Select-Object -First 1
            B2CObjectId = $Result.Id
        }) | Out-Null
        Write-Verbose "$($_) was added" -Verbose
    }
}

# Output to csv using semicolon as delimited
# $FullDetails | ConvertTo-Csv -Delimiter "," | Out-File -Encoding utf8 -FilePath "C:\temp\dump\UsersWithÆØÅNotSignedIn.csv" 