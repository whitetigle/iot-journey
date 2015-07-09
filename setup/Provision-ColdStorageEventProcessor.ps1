<#
.SYNOPSIS
  

.DESCRIPTION
  

.PARAMETER SubscriptionName
    Name of the Azure Subscription.

.PARAMETER StorageAccountName
    Name of the storage account name.

.PARAMETER ServiceBusNamespace
    Name of the Namespace tha will contain the EventHub instance.

.PARAMETER EventHubName
    Name of the EventHub that will receive events from the simulator.

.PARAMETER ConsumerGroupName
    Event Hub consumer group for blob storage.

.PARAMETER EventHubSharedAccessPolicyName
    Shared Access Policy

.PARAMETER ContainerName
    Name of the container use to store output from Event Hub.

.PARAMETER Location
    Location

     
.EXAMPLE
  .\Provision-ColdStorageEventProcessor.ps1 -SubscriptionName [YourAzureSubscriptionName] -StorageAccountName [YourStorageAccountName]
#>
[CmdletBinding()]
Param
(
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $True)][string]$SubscriptionName,
    [ValidateNotNullOrEmpty()][Parameter (Mandatory = $True)][String]$StorageAccountName,
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $False)][String]$ServiceBusNamespace = "fabrikam-iot",                                                
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $False)][String]$EventHubName = "eventhub-iot",                  
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $False)][String]$ConsumerGroupName  = "cg-blobs", 
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $False)][String]$EventHubSharedAccessPolicyName = "ManagePolicy",
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $False)][String]$ContainerName = "blobs-processor",
	[ValidateNotNullOrEmpty()][Parameter (Mandatory = $False)][String]$Location = "Central US"
)
PROCESS
{
    .\Init.ps1

    Load-Module -ModuleName Validation -ModuleLocation .\modules

    # Validate input.
    Test-OnlyLettersAndNumbers "StorageAccountName" $StorageAccountName
    Test-OnlyLettersNumbersAndHyphens "ConsumerGroupName" $ConsumerGroupName
    Test-OnlyLettersNumbersHyphensPeriodsAndUnderscores "EventHubName" $EventHubName
    Test-OnlyLettersNumbersAndHyphens "ServiceBusNamespace" $ServiceBusNamespace
    Test-OnlyLettersNumbersAndHyphens "ContainerName" $ContainerName

    # Load modules.
    Load-Module -ModuleName Config -ModuleLocation .\modules
    Load-Module -ModuleName Utility -ModuleLocation .\modules
    Load-Module -ModuleName AzureARM -ModuleLocation .\modules
    Load-Module -ModuleName AzureStorage -ModuleLocation .\modules
    Load-Module -ModuleName AzureServiceBus -ModuleLocation .\modules


    Add-AzureAccount

    $StorageAccountInfo = Provision-StorageAccount -StorageAccountName $StorageAccountName `
                                                -ContainerName $ContainerName `
                                                -Location $Location

    $EventHubInfo = Provision-EventHub -SubscriptionName $SubscriptionName `
                                    -ServiceBusNamespace $ServiceBusNamespace `
                                    -EventHubName $EventHubName `
                                    -ConsumerGroupName $ConsumerGroupName `
                                    -EventHubSharedAccessPolicyName $EventHubSharedAccessPolicyName `
                                    -Location $Location `
                                    -PartitionCount 16 `
                                    -MessageRetentionInDays 7 `
    
    # Update settings

    $simulatorSettings = @{
        'Simulator.EventHubNamespace'= $EventHubInfo.EventHubNamespace;
        'Simulator.EventHubName' = $EventHubInfo.EventHubName;
        'Simulator.EventHubSasKeyName' = $EventHubInfo.EventHubSasKeyName;
        'Simulator.EventHubSasPrimaryKey' = $EventHubInfo.EventHubPrimaryKey;
        'Simulator.EventHubTokenLifetimeDays' = ($EventHubInfo.EventHubTokenLifetimeDays -as [string]);
    }

    Write-SettingsFile -configurationTemplateFile (Join-Path $PSScriptRoot -ChildPath "\config\simulator-template.config") `
                       -configurationFile (Join-Path $PSScriptRoot -ChildPath "\config\simulator-local.config") `
                       -appSettings $simulatorSettings
    
    
    $EventHubConnectionString = $EventHubInfo.ConnectionString + ";TransportType=Amqp"
    $StorageAccountConnectionString = "DefaultEndpointsProtocol=https;AccountName={0};AccountKey={1}" -f $StorageAccountInfo.AccountName, $StorageAccountInfo.AccountKey

    $settings = @{
        'Coldstorage.CheckpointStorageAccount' = $StorageAccountConnectionString;
        'Coldstorage.EventHubConnectionString' = $EventHubConnectionString;
        'Coldstorage.EventHubName' = $EventHubInfo.EventHubName;
        'Coldstorage.BlobWriterStorageAccount' = $StorageAccountConnectionString;
        'Coldstorage.ContainerName' = $ContainerName;
        'Coldstorage.ConsumerGroupName' = $ConsumerGroupName;
    }

    Write-SettingsFile -configurationTemplateFile (Join-Path $PSScriptRoot -ChildPath "\config\coldstorageeventprocessor-template.config") `
                       -configurationFile (Join-Path $PSScriptRoot -ChildPath "\config\coldstorageeventprocessor-local.config") `
                       -appSettings $settings

    
    Write-Output "Provision Finished OK"
}