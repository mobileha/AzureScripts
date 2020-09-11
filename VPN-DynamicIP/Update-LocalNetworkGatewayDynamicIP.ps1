<#
.SYNOPSIS
Dynamically updates Azure VPN s2s Local Network Gateway IP addresses 
based on FQDN defined in it's Tags.

.DESCRIPTION
This Azure runbook dynamically updates Azure VPN Local Network Gateway IP addresses 
based on FQDN defined in it's Tags.

Script enumerates all Locan Network Gateways having defined TAG (LgwFqdn by default)
resolves FQDN name defined in tag, and updates Gateway IP address if necessary.

IP address not updated if FQDN not contain IPv4 address, contains 2 or more IPv4 addresses,
name A name does not exist, or in case of any other inconsistency.

.PARAMETER TagName
Redefine default Tag name (LgwFqdn) if necesary

.PARAMETER RecoverFailedGateways
Try to Get/Set Gateways that are in 'Failed' Provisioning state.
They can be in failed state if same IP address assigned to different LGWs of the same VPN GW.

.LINK
https://github.com/mobileha/AzureScripts/VPN-DynamicIP/
#>

<#
    #.IDEAS

    ##ARM
    ##no need to edit script to add/update local network gateways
    ##graceful fail - no effect on other gateways if one of them failed.

    ##keyworkds VPN s2s dynamic ip dynamicip LocalNetworkGateway VirtualNetworkGateway

    ##may use script without client-side coding.
    # cisco ip sla or linux cron curl is can be used to update any dynamic dns service
    # script does all other.

    #uses AZ modules

    #update (get/set) failed gateways
    #which permissions neded?

    Installation: install modules Az, Az.Network

    #modifying SLA tags - show example
#>

<# 
    Tests
    # check for no record/no answer
    # check for multiple records
    # resolves to IPv6
    # trash in LgwFqdn
    # check for resource locked
    # same IPs for 2 GWs - checked by Azure
    # gw is updating
    # gw being deleted
#>

param
(
    [string] $TagName = 'LgwFqdn',
    [bool] $RecoverFailedGateways = $true
)

Set-StrictMode -Version 3.0

Write-Output "Start"
Write-Output "Recover Failed Gateways: $RecoverFailedGateways"

#Check if running in Azure Automation -> Login then
#if not - skip login, and run as is
if ($env:AUTOMATION_ASSET_ACCOUNTID) {

    $connectionName = "AzureRunAsConnection";

    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName        

        "Logging in to Azure..."
        Add-AzAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
            | Out-Null
    }
    catch {

        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

} else {
    Write-Output "Running outside of Azure Automation"
}

$allGateways = Get-AzResource -Tagname $TagName -ResourceType "Microsoft.Network/localNetworkGateways"
Write-Output "Found $(@($allGateways).Count) Local Network Gateways having Tag '$TagName'"

#used to show current number of GW processed, for visibility
$intCurrentGw = 0

foreach ($localGateway in $allGateways) {
    $intCurrentGw++

    Write-Output "$intCurrentGw. Checking Local Network Gateway '$($localGateway.Name)'"

    $localGatewayNewIp = $null   #ip addresses array
    $localGatewayNewIpStr = ""   #ip address converted to string
    $lng = $null        

    $localGatewayFqdn = $localGateway.Tags[$TagName]

    #getting "LocalNetworkGateway" object from "Resource" object
    $lng = Get-AzLocalNetworkGateway -ResourceGroupName $localGateway.ResourceGroupName -ResourceName $localGateway.ResourceName

    #obtaining IP address, 
    #only IPv4 address ("InterNetwork")
    try 
    {
        $localGatewayNewIp = ([System.Net.DNS]::GetHostAddresses($localGatewayFqdn)) | Where-Object {$_.AddressFamily -eq "InterNetwork"}
    }
    catch
    {
        #if something goes wrong: no dns record, no ipv4 address, some trash in dns Lgw FQDN name
        Write-Error "Failed to resolve: FQDN: '$localGatewayFqdn' Message: '$($_.Exception.Message)'"
    }

    #converting IP address to string
    #if more than one IP address exists, raise error
    if ($localGatewayNewIp) #if new ip exists
    {
        if (@($localGatewayNewIp).Count -gt 1)
        {
            #Write-Warning "FQDN has more IP addresses than allowed"
            Write-Error "FQDN: '$localGatewayFqdn' has $(@($localGatewayNewIp).Count) IP addresses. It is allowed to have 1 IPv4 Address"
        } else {
            [string]$localGatewayNewIpStr = $localGatewayNewIp.IPAddressToString
        }
    }

    #check that $localGatewayNewIpStr not empty, and that old and new ip addresses differ
    #assign new IP
    if (($localGatewayNewIpStr) -and ($lng.GatewayIpAddress -ne $localGatewayNewIpStr)) {
        try {
            Write-Output "Updating Gateway '$($localGateway.Name)'. Current IP: $($lng.GatewayIpAddress), New IP: $localGatewayNewIpStr"
            $lng.GatewayIpAddress = $localGatewayNewIpStr
            Set-AzLocalNetworkGateway -LocalNetworkGateway $lng | Out-Null
        }
        catch {
            Write-Error "Error Assigning IP address '$localGatewayNewIpStr' to gw '$($lng.Name)' Message: '$($_.Exception.Message)'"
        }
    } else {
        Write-Output "Won't update Gateway '$($localGateway.Name)'. Current IP: $($lng.GatewayIpAddress), New IP: $localGatewayNewIpStr"

        #if gateway is in Failed State, trying to "set" it with the same set of parameters
        if ($RecoverFailedGateways -and ($lng.ProvisioningState -eq 'Failed')) {
            Write-Output "Gateway '$($localGateway.Name)' is in Failed Provisioning state. Trying to recover"

            Set-AzLocalNetworkGateway -LocalNetworkGateway $lng | Out-Null
            $lng = $lng | Get-AzLocalNetworkGateway
            Write-Output "New state: $($lng.ProvisioningState)"
        }
    }
}

Write-Output "Finish"