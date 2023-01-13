# Role to assign to the app
$directoryRole = 'Exchange Service Administrator'

# Find the ObjectID of the 'Exchange Service Administrator' role
$roleId = (Get-AzureADDirectoryRole | Where-Object {$_.displayname -eq $directoryRole}).ObjectID

# Add the service principal to the directory role
Add-AzureADDirectoryRoleMember -ObjectId $roleId -RefObjectId $mySP.ObjectID -Verbose
