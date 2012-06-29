# Author:  		Harin Sandhoo
# Company: 		Applied Information Sciences
# Purpose:		This script is an example of how to provision a physical environment for a medium SharePoint 2010 farm on Window's Azure IaaS offering.  It's based off of a teched talk given by Paul Stubbs.
#
# Disclaimer: 	
# 				This script is for reference only.  Use this script at your own risk / discretion.  Hopefully it'll save you some time.
#				It provisions a lot of VMs (6 vms -> 12 cores), virtual disks (14 disks -> 6 OS + 7 100 GB for data and logs + 1 15 GB for AD), which you WILL be charged for.  
#				I / we are NOT responsible for any charges you may incur.
#				It's your responsibility to clean up anything you don't want to be charged for.
#
# Prereqs:		
#				Windows Azure SDK 1.7:		https://www.windowsazure.com/en-us/develop/net/
#				Windows Azure Commandlets:  https://www.windowsazure.com/en-us/manage/windows/
#				Windows Azure Subscription
#				Enable the Virtual Machines & Virtual Networks feature in https://account.windowsazure.com/PreviewFeatures.
#				Windows Azure Powershell configured using Import-AzurePublishSettingsFile with your subscription info
#
#
# References:
#
# Paul Stubbs has a great Tech Ed talk walking through showing and explaing this.
#
# This script recreates what I think he showed in his tech ed talk.
# http://blogs.msdn.com/b/pstubbs/
# http://channel9.msdn.com/Events/TechEd/NorthAmerica/2012/AZR327
#
# Hand on github:
# https://github.com/WindowsAzure-TrainingKit/HOL-DeployingSQLServerForSharePoint
# https://github.com/WindowsAzure-TrainingKit/HOL-DeploySharePointVMs
#
#
#
# Notes:
#
# This script is run in two parts.  It should be run using the Windows Azure Powershell with your publish settings imported. 
#
# The first part creates a virtual network and provisions a single VM to be used as a domain controller.  
# The user must manually rdp into the box, and dcpromo the vm instance once it has been provision.
# The script assumes a domain name of contoso.com.  If you would like to use another domain, modify the settings below and manually configure the domain controller using the alternate domain name.
# If you'd like to change the virtual network settings, there is a file located at Config/vnet.netcfg.  
# If you make virtual network changes, ensure virtual network names, subnet names, affinity groups correspond to what's in this file or it won't work.
#
# The second part of the script configures the VMs for a medium SharePoint farm.  2 WFEs, 1 App server, 2 SQL (2012 which is why you need SP2010 SP1).
# You still need to run the SharePoint install bits and configure the farm manually.  
# As an alternative, you may want to create a sysprepped virtual machine OS disk with the SharePoint bits installed.
# Another option is to upload a VHD, with the SP2010 SP1 install bits, to the disk repository and attach it to the WFEs and App VMs and run through the install and farm configuration, but it's up to you.
# I'd also recommend configuring SSL with basic auth, alternate access URIs (to match the service name you specify below), and all the other standard SharePoint config needed.
#
# I hope you find this script useful / it saves you some time.
#
# Please be sure to replace the settings below in <> with your own account values


# Subscription Info
$subscriptionName = '<enter you subscription name>'

# Storage Account Settings
$storageAccountName = '<enter a storage account, it will create one if it does not exist.  Make sure it is not used by someone else>'
$storageAccountLabel = 'SP2010 Storage'

# Domain Controller Service Settings
$dcServiceName = '<enter an unused service name for the domain controller>'
$dcServiceLabel = '<enter a label for this service>'
$dcServiceDescription = 'This is a service for the domain controller.'

# SharePoint Service Settings (your site will be navigable at <spServiceName>.cloudapp.net.
$spServiceName = '<enter an unused service name for the sharepoint service>'
$spServiceLabel = '<enter a label for this service>'
$spServiceDescription = 'This is a service for the sharepoint environment.'

# Affinity Group Settings
$affinityGroupName = 'SP2010AffinityGroup'
$affinityGroupLocation = 'East US'
$affinityGroupLabel = 'SP2010 Affinity Group'
$affinityGroupDescription = 'Affinity group for SharePoint 2010 farm'

# Domain Controller 01 Settings
$dc01VMConfigName = 'AZURE-DC01'
$dc01VMPassword = '<enter a password for the domain controller box>'
$dc01DataDiskLabel = 'datadisk1'
$dc01DataDiskGBSize = 15

# Settings of the machine (Assumes domain is manually set up as contoso.com) and is assigned an IP of 10.10.1.4.
$domainName = 'contoso.com'
$domainAdminDomain = 'contoso'
$dnsName = 'AZURE-DC01.contoso.com'
$dnsIPAddress  = '10.10.1.4'

# SP2010 Machine Settings
$spDomainUserName = 'Administrator'
$spDomainPassword = '<enter a password you intend to use for a valid domain account, this can be the same as the $dc01VMPassword above>'

# Size of the roles used for SharePoint machines
$sqlImageInstanceSize = 'Large'
$appImageInstanceSize = 'Small'
$wfeImageInstanceSize = 'Small'

# Names of the VMs as they appear in the portal
$sql01VMConfigName = 'SP-SQL01'
$sql02VMConfigName = 'SP-SQL02'
$app01VMConfigName = 'SP-APP01'
$wfe01VMConfigName = 'SP-WFE01'
$wfe02VMConfigName = 'SP-WFE02'

# Virtual Network Settings (these settings should correspond to what's in the vnet.netcfg file in the Config directory relative to this script)
$vnetConfigurationPath = Get-Location | Join-Path -Path {$_.Path} 'Config\vnet.netcfg'
$vnetName = 'SP2010VN'
$vnetDCSubnetName = 'DCNET'
$vnetSPSubnetName = 'SPNET'

# Availability Set Settings
$asDCName = 'DC-AvSet'
$asSPName = 'SP-AVSet'

# Virtual Machine Image Names
$win2008SP1ImageName = 'MSFT__Win2K8R2SP1-120514-1520-141205-01-en-us-30GB.vhd'
$win2012RCImageName = 'MSFT__Windows-Server-2012-RC-June2012-en-us-30GB.vhd'
$sql2012RCImageName = 'MSFT__Sql-Server-11EVAL-11.0.2215.0-05152012-en-us-30GB.vhd'



# START EXECUTION OF THE SCRIPT GIVEN THE SETTINGS ABOVE

Set-AzureSubscription -DefaultSubscription $subscriptionName

# Create the Affinity Group
New-AzureAffinityGroup -Name $affinityGroupName -Description $affinityGroupDescription -Location $affinityGroupLocation -Label $affinityGroupLabel

# Create the Storage Account for VMs to use
New-AzureStorageAccount -StorageAccountName $storageAccountName -Label $storageAccountLabel -AffinityGroup $affinityGroupName

# Configure the subscription to use the storage account
Set-AzureSubscription -SubscriptionName $subscriptionName -CurrentStorageAccount $storageAccountName

# Setup the Virtual Network 
Set-AzureVNetConfig -ConfigurationPath $vnetConfigurationPath

# Create DC 01 Box Configuration
$dc01VMConfig = New-AzureVMConfig -Name $dc01VMConfigName -AvailabilitySetName $asDCName -ImageName $win2008SP1ImageName -InstanceSize 'Small' |
	Add-AzureProvisioningConfig -Windows -Password $dc01VMPassword |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB $dc01DataDiskGBSize -DiskLabel dc01DataDiskLabel -LUN 0 |
	Set-AzureSubnet $vnetDCSubnetName
	
# Provision the actual domain controller machine
New-AzureVM –ServiceName $dcServiceName -ServiceLabel $dcServiceLabel -ServiceDescription $dcServiceDescription -AffinityGroup $affinityGroupName -VNetName $vnetName -VMs $dc01VMConfig

Echo 'This is where you remote desktop into the DC vm and run dcpromo to configure it as a domain controller.' 
Read-Host 'Press <enter> to continue once the domain controller is configured and the script will continue...'


# Create SQL 01 Box Configuration
$sql01VMConfig = New-AzureVMConfig -Name $sql01VMConfigName -AvailabilitySetName $asSPName -ImageName $sql2012RCImageName -InstanceSize $sqlImageInstanceSize |
	Add-AzureProvisioningConfig -WindowsDomain -Password $spDomainPassword -JoinDomain $domainName -Domain $domainAdminDomain -DomainUserName $spDomainUserName -DomainPassword $spDomainPassword |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'data' -LUN 0 |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'logs' -LUN 1 |
	Set-AzureSubnet $vnetSPSubnetName
		
# Create SQL 02 Box Configuration
$sql02VMConfig = New-AzureVMConfig -Name $sql02VMConfigName -AvailabilitySetName $asSPName -ImageName $sql2012RCImageName -InstanceSize $sqlImageInstanceSize |
	Add-AzureProvisioningConfig -WindowsDomain -Password $spDomainPassword -JoinDomain $domainName -Domain $domainAdminDomain -DomainUserName $spDomainUserName -DomainPassword $spDomainPassword |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'data' -LUN 0 |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'logs' -LUN 1 |
	Set-AzureSubnet $vnetSPSubnetName
	
# Create App Tier Box Configuration
$app01VMConfig = New-AzureVMConfig -Name $app01VMConfigName -AvailabilitySetName $asSPName -ImageName $win2008SP1ImageName -InstanceSize $appImageInstanceSize |
	Add-AzureProvisioningConfig -WindowsDomain -Password $spDomainPassword -JoinDomain $domainName -Domain $domainAdminDomain -DomainUserName $spDomainUserName -DomainPassword $spDomainPassword |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'apps' -LUN 0 |
	Set-AzureSubnet $vnetSPSubnetName

# Create WFE 01 Box Configuration
$wfe01VMConfig = New-AzureVMConfig -Name $wfe01VMConfigName -AvailabilitySetName $asSPName -ImageName $win2008SP1ImageName -InstanceSize $wfeImageInstanceSize |
	Add-AzureProvisioningConfig -WindowsDomain -Password $spDomainPassword -JoinDomain $domainName -Domain $domainAdminDomain -DomainUserName $spDomainUserName -DomainPassword $spDomainPassword  |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'apps' -LUN 0 |
	Add-AzureEndpoint -Name 'HttpIn' -LBSetName 'lbHttpIn' -LocalPort 80 -PublicPort 80 -Protocol 'tcp' -ProbePort 80 -ProbeProtocol 'http' -ProbePath '/' |
	Add-AzureEndpoint -Name 'HttpsIn' -LBSetName 'lbHttpsIn' -LocalPort 443 -PublicPort 443 -Protocol 'tcp' -ProbePort 443 -ProbeProtocol 'tcp' |
	Set-AzureSubnet $vnetSPSubnetName

# Create WFE 02 Box Configuration
$wfe02VMConfig = New-AzureVMConfig -Name $wfe02VMConfigName -AvailabilitySetName $asSPName -ImageName $win2008SP1ImageName -InstanceSize $wfeImageInstanceSize |
	Add-AzureProvisioningConfig -WindowsDomain -Password $spDomainPassword -JoinDomain $domainName -Domain $domainAdminDomain -DomainUserName $spDomainUserName -DomainPassword $spDomainPassword  |
	Add-AzureDataDisk -CreateNew -DiskSizeInGB 100 -DiskLabel 'apps' -LUN 0 |
	Add-AzureEndpoint -Name 'HttpIn' -LBSetName 'lbHttpIn' -LocalPort 80 -PublicPort 80 -Protocol 'tcp' -ProbePort 80 -ProbeProtocol 'http' -ProbePath '/' |
	Add-AzureEndpoint -Name 'HttpsIn' -LBSetName 'lbHttpsIn' -LocalPort 443 -PublicPort 443 -Protocol 'tcp' -ProbePort 443 -ProbeProtocol 'tcp' |
	Set-AzureSubnet $vnetSPSubnetName
	
# Create DNS settings object	
$dns1 = New-AzureDns -Name $dnsName -IPAddress $dnsIPAddress

New-AzureVM -ServiceName $spServiceName -ServiceLabel $spServiceLabel -ServiceDescription $spServiceDescription -AffinityGroup $affinityGroupName -VNetName $vnetName -DnsSettings $dns1 -VMs $sql01VMConfig, $sql02VMConfig, $app01VMConfig, $wfe01VMConfig, $wfe02VMConfig



