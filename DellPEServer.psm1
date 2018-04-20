add-type @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
public bool CheckValidationResult(
    ServicePoint srvPoint, X509Certificate certificate,
    WebRequest request, int certificateProblem) {
        return true;
    }
}
'@
if (([System.Net.ServicePointManager]::CertificatePolicy).ToString() -ne 'TrustAllCertsPolicy')
{
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy -ErrorAction Stop
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12
}

function Get-PEServerFirmwareInventory
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [String]
        $DRACIPAddress,

        [Parameter(Mandatory)]
        [pscredential]
        $DRACCredential
    )

    $softwareInventory = @()

    $uri = "https://$DRACIPAddress/redfish/v1/UpdateService/FirmwareInventory"
    $response = (Invoke-WebRequest -Uri $uri -UseBasicParsing -Credential $DRACCredential).Content | ConvertFrom-Json

    foreach ($member in $response.members)
    {
        $memberUri = "https://$DRACIPAddress$($member.'@odata.id')"
        $memberResponse = (Invoke-WebRequest -Uri $memberUri -UseBasicParsing -Credential $DRACCredential).Content | ConvertFrom-Json
        $memberInventory = @{
            Name = $memberResponse.Name
            State = $memberResponse.Status.State
            Health = $memberResponse.Status.Health
            Updateable = $memberResponse.Updateable
            Version = $memberResponse.Version
            InstallState = ($memberResponse.Id).Split('-')[0]
        }

        $softwareInventory += $memberInventory
    }
    
    return $softwareInventory
}

Function Get-PEServerSCP
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $DRACIPAddress,

        [Parameter(Mandatory = $true)]
        [pscredential]
        $DRACCredential
    )

    $headerObject = @{
        'ExportFormat'    = 'JSON'
        'ShareParameters' = @{'Target'='All'}
    }

    $headerJson = $headerObject | ConvertTo-Json

    $url = "https://$DRACIPAddress/redfish/v1/Managers/iDRAC.Embedded.1/Actions/Oem/EID_674_Manager.ExportSystemConfiguration"
    $response = Invoke-WebRequest -Uri $url -Credential $DRACCredential -Method Post -Body $headerJson -ContentType 'application/json' -ErrorVariable scpError

    $responseJson = $response.RawContent | ConvertTo-Json
    $jobID = ([regex]::Match($responseJson,'JID_.+?r').captures.groups[0].value).replace('\r','')

    $url = "https://$DRACIPAddress/redfish/v1/TaskService/Tasks/$jobID"
    $response = Invoke-WebRequest -Uri $url -Credential $DRACCredential -Method Get -UseBasicParsing -ContentType 'application/json'

    $responseObject = $response.Content | ConvertFrom-Json

    While($responseObject.TaskState -eq 'Running')
    {
        Start-Sleep -Seconds 5
        $response = Invoke-WebRequest -Uri $url -Credential $DRACCredential -Method Get -UseBasicParsing -ContentType 'application/json'
        $responseObject = $response.Content | ConvertFrom-Json
    }

    if ($response.StatusCode -eq 200 -and ($response.RawContent.Contains('SystemConfiguration')))
    {
        return ($response.Content | ConvertFrom-Json)
    }
    else
    {
        throw 'Error in exporting SCP'
    }
}

function Get-PEServer
{
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $ServiceTag
    )

    [DellPEServerRoot]::availableServers | Where-Object {$_.SystemConfiguration.ServiceTag -eq $ServiceTag}
}

function Connect-PEServer
{
    [CmdletBinding()]
    param 
    (
        [Parameter()]
        [String]
        $JsonPath,

        [Parameter()]
        [String]
        $DRACIPAddress,

        [Parameter()]
        [pscredential]
        $DRACCredential
    )

    if ($JsonPath)
    {
        if (Test-Path -Path $JsonPath)
        {
            $json = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json
            $serviceTag = $json.SystemConfiguration.ServiceTag
            if ($json -and (-not $serviceTag))
            {
                $serviceTag = (-join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})).ToUpper()
                $json.SystemConfiguration | Add-Member -MemberType NoteProperty -Name ServiceTag -Value $serviceTag
            }
        }
        else
        {
            throw "$JsonPath not found."
        }
    }
    else
    {
        $json = Get-PEServerSCP -DRACIPAddress $DRACIPAddress -DRACCredential $DRACCredential

        $serviceTag = $json.SystemConfiguration.ServiceTag

        $json | Add-Member -MemberType NoteProperty 'DRACIPAddress' -Value $DRACIPAddress
        $json | Add-Member -MemberType NoteProperty 'UserName' -Value $DRACCredential.UserName
        $json | Add-Member -MemberType NoteProperty 'Password' -Value $DRACCredential.GetNetworkCredential().Password

        $firmwareInventory = Get-PEServerFirmwareInventory -DRACIPAddress $DRACIPAddress -DRACCredential $DRACCredential
        $json | Add-Member -MemberType NoteProperty 'FirmwareInventory' -Value $firmwareInventory
    }

    if (-not (Get-PEServer -ServiceTag $serviceTag))
    {
        [DellPEServerRoot]::availableServers += $json
    }

    return $serviceTag
}

function Get-ComponentAttribute
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [Object]
        $serverCP,

        [Parameter(Mandatory = $true)]
        [String]
        $ComponentFQDD
    )

    $attributeObject = $serverCP.SystemConfiguration.Components.Where({$_.FQDD -eq $ComponentFQDD}).Attributes
    return $attributeObject
}

Export-ModuleMember -Function *
