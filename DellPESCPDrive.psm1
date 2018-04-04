using namespace Microsoft.PowerShell.SHiPS

[SHiPSProvider()]
class DellPEServerRoot : SHiPSDirectory
{
    static [System.Collections.Generic.List``1[Object]] $availableServers

    #Default contructor
    DellPEServerRoot([string]$name) : base($name)
    {
    }

    [Object[]] GetChildItem()
    {
        $obj = @()

        if ([DellPEServerRoot]::availableServers)
        {
            [DellPEServerRoot]::availableServers | ForEach-Object {
                $obj += [DellPEServer]::new($_.SystemConfiguration.ServiceTag, $_)
            }
        }
        return $obj
    }
}

[SHiPSProvider()]
class DellPEServer : SHiPSDirectory
{
    hidden [object] $serverCP
    [string] $Model 
    [string] $Type  = 'Server'

    #Default contructor
    DellPEServer([string]$name, [object]$serverCP) : base($name)
    {
        $this.serverCP = $serverCP
        $this.Model = $serverCP.SystemConfiguration.Model
    }   

    [Object[]] GetChildItem()
    {
        $obj = @()
        foreach ($FQDD in $this.serverCP.SystemConfiguration.Components.FQDD)
        {
            $obj += [DellPEServerComponent]::new($FQDD, $this.serverCP)
        }
        return $obj
    }    
}

[SHiPSProvider()]
class DellPEServerComponent : SHiPSDirectory
{
    hidden [Object] $serverCP
    [String] $type = 'Component' 

    #Default contructor
    DellPEServerComponent([string]$name, [object]$serverCP) : base($name)
    {
        $this.serverCP   = $serverCP
    }

    [Object[]] GetChildItem()
    {
        $obj = @()
        $attributes = Get-ComponentAttribute -serverCP $this.serverCP -ComponentFQDD $this.Name

        foreach($attribute in $attributes)
        {
            $obj += [DellPEServerComponentAttribute]::new($attribute.Name, $attribute)
        }
        return $obj
    }  
}

[SHiPSProvider()]
class DellPEServerComponentAttribute : SHiPSDirectory
{
    hidden [Object] $attributeData
    [string] $Value
    [bool] $SetOnImport
    [string] $comment
    [String] $type = 'Attribute' 

    #Default contructor
    DellPEServerComponentAttribute([string]$name, [object]$attributeData) : base($name)
    {
        $this.attributeData   = $attributeData
        $this.Value      = $attributeData.Value
        $this.SetOnImport = $attributeData.'Set On Import'
        $this.Comment = $attributeData.Comment`
    }
}

#region support functions
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
        }
        else
        {
            throw "$JsonPath not found."
        }
    }
    else
    {
        $json = Get-PEServerSCP -DRACIPAddress $DRACIPAddress -DRACCredential $DRACCredential        
    }

    if (-not (Get-PEServer -ServiceTag $json.SystemConfiguration.ServiceTag))
    {
        [DellPEServerRoot]::availableServers += $json
    }
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

#endregion
