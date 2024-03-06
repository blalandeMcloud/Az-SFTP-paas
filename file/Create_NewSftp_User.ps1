<#
.Synopsis
Create SFTP User and store in Keyvault

.DESCRIPTION
This script do :
=> Create SFTP User
=> Store credential in KeyVault

.NOTES
Version: 2.0.0
First Release Date: 27th February, 2024
Author: Benjamin LALANDE
Company: Devoteam
#>

Param (

    [parameter (mandatory = $true)][ValidateNotNullorEmpty()]
    [String]$Mail,
    [parameter (mandatory = $false)][ValidateNotNullorEmpty()]
    [String]$ExpireDays = 7,
    [parameter (mandatory = $false)][ValidateNotNullorEmpty()]
    [String]$StorageAccountName = "sadmft01",
    [parameter (mandatory = $false)][ValidateNotNullorEmpty()]
    [String]$KvName = "kv-d-mft-01"
)

### Variable

$UserName = ""
$containerName = ""

$TempExpirationDate = (get-date).addDays($ExpireDays)
$ExpirationDate = Get-Date -Date $TempExpirationDate -Format "ddMMyyyy" # Format 26 fevrier 2024 = 26022024

### End Variable

### Function
function getAvailableUser {
     Param(
     [parameter(Mandatory)]
     [string]$Mail,
     [parameter(Mandatory)]
     $AllSaSftpUser
      )

    #Format UserName
    $UserName = $Mail.Split("@")[0].replace(".","").replace("-","").ToLower()
    $NewUsername = $UserName
    $CheckUser = $false
    $id = 1


    while ($CheckUser -eq $false){
        # Test si le nom d'utilisateur n'est pas existant alors on ajout un suffixe
        # Si non $checkUser = True

       if ($NewUsername -in $AllSaSftpUser.name){
          
          $NewUsername = $Username + $id.ToString()
          $id++
       
       }else {
        $CheckUser = $true
       }
    }

    return $NewUsername
}

### End Function


### MAIN 

#connexion au tenant Azure
$null = Connect-AzAccount
#Connect-AzAccount -Identity #Connection via managed identity du compte automation pour plus tard

#Recupère les informations du compte de stockage notamment la subscription
# Test si le compte existe
$SaInfos =""
$SaInfos = Search-AzGraph "resources| where type == 'microsoft.storage/storageaccounts' and name == '$StorageAccountName' "

If (!$SaInfos){
    Write-Host "Le compte de stockage $StorageAccountname n'existe pas !!!"
    Exit
}


#Se connect à la subscription où est présent le compte de stockage
Write-Host "Connect to subscription $($SaInfos.subscriptionid) ..."
$null = set-azcontext $SaInfos.subscriptionId


#Get all Users SFTP
$AllSaSftpUser = Get-AzStorageLocalUser -StorageAccountName $StorageAccountName -ResourceGroupName $SaInfos.resourceGroup

#Trouve un Username disponible
$UserName = GetAvailableUser -Mail $Mail -AllSaSftpUser $AllSaSftpUser
Write-host "=> User avalaible is $UserName" -ForegroundColor Yellow

#Create Container
$containerName = "$UserName-$ExpirationDate"

Write-Host "=> Create container $containerName in $StorageAccountName (RG : $($SaInfos.resourceGroup))" -ForegroundColor Yellow
$ctx = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $SaInfos.resourceGroup
$null = New-AzStorageContainer -Name $containerName -Context $ctx.Context

#Create Permission
Write-Host "=> Create permission for $containerName" -ForegroundColor Yellow
$UserPermission = ""
$UserPermission = New-AzStorageLocalUserPermissionScope -Permission rwdlc -Service blob -ResourceName $containerName

#Create user ##
Write-host "=> Create User $Username in Storage $StorageName/$ContainerName" -ForegroundColor Yellow
$null = Set-AzStorageLocalUser -StorageAccountName $StorageAccountName -ResourceGroupName $SaInfos.resourceGroup -UserName $UserName -PermissionScope $UserPermission -HomeDirectory $containerName -HasSshPassword $true
$sshPassword = New-AzStorageLocalUserSshPassword -ResourceGroupName $SaInfos.resourceGroup -AccountName $StorageAccountName -UserName $UserName


#Store Credential in KeyVault
$KvInfos = ""
$KvInfos = Search-AzGraph "resources | where type == 'microsoft.keyvault/vaults' and name == '$KvName' "

If (!$KvInfos){
    Write-Host "Le keyvault $KvName n'existe pas !!!"
    Exit
}

Write-Host "Connect to subscription $($KvInfos.subscriptionid) ..."
$null = set-azcontext $KvInfos.subscriptionId

#Le compte qui execute le script (utilisateur, SPN ou Managed idenity) doit avoir le droit "Key Vault Secrets Officer" sur le KeyVault
Write-host "=> Ajout des credentials dans le Keyvualt $KvName" -ForegroundColor Yellow
$secretvalue = ConvertTo-SecureString $sshPassword.SshPassword -AsPlainText -Force
$secret = Set-AzKeyVaultSecret -VaultName $KvName -Name $Username -SecretValue $secretvalue #-Expires 

Write-Host"`n`n"
$Output = "Host : $StorageAccountName.blob.core.windows.net `nUser : $StorageAccountName.$Username `nPassword : $($sshPassword.SshPassword) `nContainer : $ContainerName `nExpiration : $ExpirationDate"
return $Output