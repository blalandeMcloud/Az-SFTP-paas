<#
.Synopsis
Clean SFTP User

.DESCRIPTION
This script clean :
=> Delete blob container
=> Delete Sftp User
=> Delete credential in KeyVault

.NOTES
Version: 2.0.0
First Release Date: 27th February, 2024
Author: Benjamin LALANDE
Company: Devoteam
#>

Param (
    [parameter (mandatory = $false)][ValidateNotNullorEmpty()]
    [String]$StorageAccountName = "sadmft01",
    [parameter (mandatory = $false)][ValidateNotNullorEmpty()]
    [String]$KvName = "kv-d-mft-01"
)


### Variable
$TodayDate = get-date -Format "dd/MM/yyyy"

### End Variable


### MAIN
#connexion au tenant Azure
Write-host "Connexion to Azure"
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

#Recupère les informations du KeyVault
$KvInfos = Search-AzGraph "resources | where type == 'microsoft.keyvault/vaults' and name == '$KvName' "

If (!$KvInfos){
    Write-Host "Le keyvault $KvName n'existe pas !!!"
    Exit
}


#Se connect à la subscription où est présent le compte de stockage
Write-Host "Connect to subscription $($SaInfos.subscriptionid) ..."
$null = set-azcontext $SaInfos.subscriptionId


#Get all Users SFTP
Write-host "Recuperation du storage $StorageAccountName"
$ctx = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $SaInfos.resourceGroup
$AllContainer = Get-AzStorageContainer -Context $ctx.context


ForEach ($container in $AllContainer){
    
    #Container Name = "NomUser-DateExpiration", ex benjaminLalande-01032024
    Write-host "=> Check du container $($container.name)"
    #Recupère le nom d'utilisateur
    $UserName =""
    $UserName = ($container.name).split("-")[0]

    #Récupère la date dans le nom du container : 27022024
    #format ExpireDate de 27022024 en 27/02/2024 pour faire une comparaison
    $ExpireDate = ""
    $ExpireDate = ($container.name).split("-")[1]
    $ExpireDate = $ExpireDate.Insert(2,"/").Insert(5,"/")



    #Si la date d'expiration est plus petite ou egale a la date d'aujourd'hui alors
    # On supprime le container, l'utilisateur et le credential dans le Kevyault
    if ((get-date $ExpireDate) -le (get-date $TodayDate)){
        Write-host "==> Date Expirée pour l'utilisateur $Username et le container $($container.name)" -ForegroundColor Yellow

        If ((get-azcontext).subscription.id -ne $SaInfos.subscriptionId){
            $null = set-azcontext $SaInfos.subscriptionId
        }
        
        #Suppression du container et User
        Write-host "==> Suppession du container $($container.name)" -ForegroundColor Yellow
        Remove-AzStorageContainer -Name $container.name -Context $ctx.Context -Force
        Write-host "==> Suppression de l'utilisateur $Username" -ForegroundColor Yellow
        Remove-AzStorageLocalUser -StorageAccountName $StorageAccountName -ResourceGroupName $SaInfos.resourceGroup -UserName $UserName
        
        #On teste si la sub du Keyvault est identique à celle actuelle
        If ((get-azcontext).subscription.id -ne $KvInfos.subscriptionId ){
            $null = set-azcontext $KvInfos.subscriptionId
        }

        #Remove Secret
        Write-Host "Remove secret name $UserName in KeyVault $KvName" -ForegroundColor Yellow
        Remove-AzKeyVaultSecret -VaultName $KvName -Name $UserName -InRemovedState -force #Purge delete avec -InRemovedState
    }


}