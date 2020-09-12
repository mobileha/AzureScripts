# Dynamic IP for Azure VPN s2s connections.
## Short Description
This Azure runbook dynamically updates ARM Azure VPN Local Network Gateway IP addresses 
based on FQDN defined in it's Tags.

Script enumerates all Locan Network Gateways having defined TAG (LgwFqdn by default)
resolves FQDN name defined in tag, and updates Gateway IP address if necessary.

## Features
* Set-and-forget: No need to configure script in any way. All configurations are done 
in LNG tags script will enumerate all Localn Network Gateways having defined Tag Name,
and will update gateways if necessary
* It runs in Azure secure environment. No need to run script on Windows/Linux VM and
expose credentials to update Dynamic IP. Just use any Dynamic DNS service to bind
FQDN to IP.
* LNGs can be added and removed just by editing Tags
* Tries to recover LNG from *Failed* Provisioning state using Get/Set.
* Script can be run from Windows PowerShell, but intended to run from Azure Automation Account

## Constrains
* It uses newer Az modules, instead of AzureRM
* IP address not updated if FQDN not contain IPv4 address, contains 2 or more IPv4 addresses,
A name does not exist, or in case of any other inconsistency.

## Installation
* Use Azure automation account
* Install Modules: Az, Az.Network, Az.Resources
* Schedule to run script every now and then. Probably it also worth creating webhook to run apply changes whenever IP updated

