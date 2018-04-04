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
function Connect-PEServer
{
    [CmdletBinding()]
    param 
    (
        [Parameter(Mandatory = $true)]
        [String]
        $JsonPath
    )

    if (Test-Path -Path $JsonPath)
    {
        $json = Get-Content -Path $JsonPath -Raw | ConvertFrom-Json
        [DellPEServerRoot]::availableServers += $json
    }
    else
    {
        throw "$JsonPath not found."
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
#endregion
