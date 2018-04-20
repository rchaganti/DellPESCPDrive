# Dell PowerEdge System Configuration Profile as a PowerShell Drive
The `DellPESCPDrive` module helps mount PowerEdge System configuration as a PowerShell drive. You can then use Pester to validate the mounted system configuration against another system or a reference JSON.

```
## Example - Mount the System configuration as a drive
Import-Module -Name SHiPS
Import-Module -Name DellPESCPDrive

New-PSDrive -Name scp -PSProvider SHiPS -Root DellPESCPDrive#DellPEServerRoot
Set-Location -Path SCP:

#Connect a local SCP JSON as drive
Connect-PEServer -JsonPath .\Sample.json

#Connect to a live bare-metal System
Connect-PEServer -DRACIPAddress 172.16.100.23 -DRACCredential (Get-Credential)
```
