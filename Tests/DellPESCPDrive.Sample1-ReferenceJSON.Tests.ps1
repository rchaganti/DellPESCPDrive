[cmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [String]
    $referenceJsonPath,

    [Parameter(Mandatory = $true)]
    [String[]]
    $DRACIPAddress,

    [Parameter(Mandatory = $true)]
    [pscredential]
    $DRACCredential
)

#Load necesary modules
Import-Module SHiPS -Force
Import-Module D:\GitHub\DellPESCPDrive -Force

#Create PS Drive
New-PSDrive -Name scp -PSProvider SHiPS -Root DellPESCPDrive#DellPEServerRoot
Set-Location -Path scp:

#Add the reference JSON as a container
$referenceTag = Connect-PEServer -JsonPath $referenceJsonPath

#Add the DRAC as containers
$differenceTags = @()
foreach ($server in $DRACIPAddress)
{
    $differenceTags += Connect-PEServer -DRACIPAddress $server -DRACCredential $DRACCredential
}

#Start the Pester tests here
#We will use our reference tag and walk through its components in SystemConfiguration container and find matches in the difference tags
$componentsToValidate = Get-ChildItem -Path "scp:\${referenceTag}\SystemConfiguration" | Select-Object -ExpandProperty Name

foreach ($component in $componentsToValidate)
{
    foreach ($system in $differenceTags)
    {
        Describe "Validae $component on $system" {
            $attributeList = (Get-ChildItem -Path "scp:\${referenceTag}\SystemConfiguration\${component}").Name
            foreach ($attribute in $attributeList)
            {
                It "Validate ${component}\${attribute} on $system" {
                    (Get-Item -Path "scp:\${system}\SystemConfiguration\${component}\${attribute}").Value | Should Be (Get-Item -Path "scp:\${referenceTag}\SystemConfiguration\${component}\${attribute}").Value
                }
            }
        }
    }
}

$credential = Get-Credential

$testHash = @{
    Path =  'D:\Github\DellPESCPDrive\Tests\DellPESCPDrive.Sample.Tests.ps1'
    Parameters = @{
        referenceJsonPath = 'D:\gitHub\DellPESCPDrive\referenceSCP.json'
        DRACCredential    = $credential
        DRACIPAddress     = @('172.16.100.23','172.16.100.24')
    }
}