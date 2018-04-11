using namespace Microsoft.PowerShell.SHiPS

Import-Module "$PSScriptRoot\DellPEServer.psm1" -Force

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
                if ($_.DRACIPAddress)
                {
                    $DRACIPAddress = $_.DRACIPAddress
                    $secpasswd = ConvertTo-SecureString $_.Password -AsPlainText -Force
                    $DRACCredential = New-Object System.Management.Automation.PSCredential ($_.UserName, $secpasswd)
                }
                else
                {
                    $DRACIPAddress = $null
                    $DRACCredential = $null
                }
                $obj += [DellPEServer]::new($_.SystemConfiguration.ServiceTag, $_, $DRACIPAddress, $DRACCredential)
            }
        }
        return $obj
    }
}

[SHiPSProvider()]
class DellPEServer : SHiPSDirectory
{
    hidden [object] $serverCP
    hidden [string] $DRACIPAddress
    hidden [pscredential] $DRACCredential
    [string] $Model 
    [string] $Type  = 'Server'

    #Default contructor
    DellPEServer([string]$name, [object]$serverCP, [string]$DRACIPAddress, [psCredential]$DRACCredential) : base($name)
    {
        $this.serverCP = $serverCP
        $this.Model = $serverCP.SystemConfiguration.Model
        $this.DRACIPAddress = $DRACIPAddress
        $this.DRACCredential = $DRACCredential
    }   

    [Object[]] GetChildItem()
    {
        $obj = @()
        $obj += [DellPEServerConfiguration]::new('SystemConfiguration', $this.serverCP, $this.DRACIPAddress, $this.DRACCredential)
        if ($this.serverCP.FirmwareInventory)
        {
            $obj += [DellPEFirmwareInventory]::new('FirmwareInventory', $this.serverCP, $this.DRACIPAddress, $this.DRACCredential)
        }
        return $obj
    }    
}

[SHiPSProvider()]
class DellPEServerConfiguration : SHiPSDirectory
{
    hidden [object] $serverCP
    hidden [string] $DRACIPAddress
    hidden [pscredential] $DRACCredential

    #Default Constructor
    DellPEServerConfiguration([string] $name, [object]$serverCP, [string]$DRACIPAddress, [psCredential]$DRACCredential) : base($name)
    {
        $this.serverCP = $serverCP
        $this.DRACIPAddress = $DRACIPAddress
        $this.DRACCredential = $DRACCredential
    }

    [Object[]] GetChildItem()
    {
        $obj = @()
        foreach ($FQDD in $this.serverCP.SystemConfiguration.Components.FQDD)
        {
            $obj += [DellPEServerComponent]::new($FQDD, $this.serverCP, $this.DRACIPAddress, $this.DRACCredential)
        }
        return $obj
    }
}

[SHiPSProvider()]
class DellPEFirmwareInventory : SHiPSDirectory
{
    hidden [object] $serverCP
    hidden [string] $DRACIPAddress
    hidden [pscredential] $DRACCredential

    #Default Constructor
    DellPEFirmwareInventory([string] $name, [object]$serverCP, [string]$DRACIPAddress, [psCredential]$DRACCredential) : base($name)
    {
        $this.serverCP = $serverCP
        $this.DRACIPAddress = $DRACIPAddress
        $this.DRACCredential = $DRACCredential
    }

    [Object[]] GetChildItem()
    {
        $obj = @()
        foreach ($object in $this.serverCP.FirmwareInventory)
        {
            $obj += [DellPEServerFirmwareInventoryInformation]::new($object.Name, $object, $this.DRACIPAddress, $this.DRACCredential) 
        }
        return $obj
    }
}

[SHiPSProvider()]
class DellPEServerComponent : SHiPSDirectory
{
    hidden [Object] $serverCP
    [String] $type = 'Component'
    hidden [string] $DRACIPAddress
    hidden [pscredential] $DRACCredential

    #Default contructor
    DellPEServerComponent([string]$name, [object]$serverCP, [string]$DRACIPAddress, [psCredential]$DRACCredential) : base($name)
    {
        $this.serverCP   = $serverCP
        $this.DRACIPAddress = $DRACIPAddress
        $this.DRACCredential = $DRACCredential
    }

    [Object[]] GetChildItem()
    {
        $obj = @()
        $attributes = Get-ComponentAttribute -serverCP $this.serverCP -ComponentFQDD $this.Name

        foreach($attribute in $attributes)
        {
            $obj += [DellPEServerComponentAttribute]::new($attribute.Name, $attribute, $this.DRACIPAddress, $this.DRACCredential)
        }
        return $obj
    }  
}

[SHiPSProvider()]
class DellPEServerComponentAttribute : SHiPSLeaf
{
    hidden [Object] $attributeData
    [string] $Value
    [bool] $SetOnImport
    [string] $comment
    [String] $type = 'Attribute'
    hidden [string] $DRACIPAddress
    hidden [pscredential] $DRACCredential

    #Default contructor
    DellPEServerComponentAttribute([string]$name, [object]$attributeData, [string]$DRACIPAddress, [psCredential]$DRACCredential) : base($name)
    {
        $this.attributeData   = $attributeData
        $this.Value      = $attributeData.Value
        $this.SetOnImport = $attributeData.'Set On Import'
        $this.Comment = $attributeData.Comment
        $this.DRACIPAddress = $DRACIPAddress
        $this.DRACCredential = $DRACCredential
    }
}

[SHiPSProvider()]
class DellPEServerFirmwareInventoryInformation : SHiPSLeaf
{
    hidden [Object] $InventoryData
    [string] $State
    [bool] $Updateable
    [string] $Health
    [string] $Version
    [String] $InstallState
    hidden [string] $DRACIPAddress
    hidden [pscredential] $DRACCredential

    #Default contructor
    DellPEServerFirmwareInventoryInformation([string]$name, [object]$InventoryData, [string]$DRACIPAddress, [psCredential]$DRACCredential) : base($name)
    {
        $this.InventoryData   = $InventoryData
        $this.State      = $InventoryData.State
        $this.Updateable = $InventoryData.Updateable
        $this.Health = $InventoryData.Health
        $this.Version = $InventoryData.Version
        $this.InstallState = $inventoryData.InstallState
        $this.DRACIPAddress = $DRACIPAddress
        $this.DRACCredential = $DRACCredential
    }
}

