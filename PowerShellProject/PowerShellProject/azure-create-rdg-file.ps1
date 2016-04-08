# script to generate rdcman rdg file from azure services
# for use with latest rdcman 2.7
# https://www.microsoft.com/en-us/download/confirmation.aspx?id=44989

# 150722 jagilber

$rdgFile = "c:\temp\azure-ms.rdg"
$subscriptionId = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

Select-AzureSubscription -SubscriptionId $subscriptionId 

# check if we need to sign on
try
{
    $ret = Get-AzureService
}
catch
{
    Add-AzureAccount
}

# Create a new XML File with config root node
[System.XML.XMLDocument]$doc=New-Object System.XML.XMLDocument
$xmlDec = $doc.CreateXmlDeclaration("1.0","utf-8","")

# set delaration
[System.XML.XMLElement]$root=$doc.DocumentElement
$doc.InsertBefore($xmlDec, $root)

# Append as child to an existing node
[System.XML.XMLElement]$element=$doc.CreateElement("RDCMan")
$doc.appendChild($element)

# Add Attributes
$element.SetAttribute("programVersion","2.7")
$element.SetAttribute("schemaVersion","3")


[System.XML.XMLElement]$fileElement=$element.appendChild($doc.CreateElement("file"))
[System.XML.XMLElement]$credElement=$fileElement.appendChild($doc.CreateElement("credentialsProfiles"))
[System.XML.XMLElement]$propertiesElement=$fileElement.appendChild($doc.CreateElement("properties"))
[System.XML.XMLElement]$expandedElement =$propertiesElement.appendChild($doc.CreateElement("expanded"))
$expandedElement.InnerText = "True"
[System.XML.XMLElement]$nameElement =$propertiesElement.appendChild($doc.CreateElement("name"))
$nameElement.InnerText = "Azure"

foreach($service in Get-AzureService)
{
    [System.XML.XMLElement]$groupElement=$fileElement.appendChild($doc.CreateElement("group"))
    [System.XML.XMLElement]$propertiesElement=$groupElement.appendChild($doc.CreateElement("properties"))
    [System.XML.XMLElement]$expandedElement =$propertiesElement.appendChild($doc.CreateElement("expanded"))
    $expandedElement.InnerText = "True"
    [System.XML.XMLElement]$nameElement =$propertiesElement.appendChild($doc.CreateElement("name"))
    $nameElement.InnerText = $service.ServiceName

    foreach($vm in Get-AzureVM -ServiceName $service.ServiceName)
    {
        
        $rdEndpoint = $vm.DNSName.Replace("http://","").Replace("/",":")
        $rdEndpoint += (Get-AzureEndpoint -VM $vm | ? Name -match 'Remote.*Desktop').Port

        [System.XML.XMLElement]$serverElement=$groupElement.appendChild($doc.CreateElement("server"))
        [System.XML.XMLElement]$propertiesElement=$serverElement.appendChild($doc.CreateElement("properties"))
        [System.XML.XMLElement]$displayNameElement=$propertiesElement.appendChild($doc.CreateElement("displayName"))
        $displayNameElement.InnerText = $vm.Name
        [System.XML.XMLElement]$nameElement=$propertiesElement.appendChild($doc.CreateElement("name"))
        $nameElement.InnerText = $rdEndpoint
    }
}

[System.XML.XMLElement]$connectedElement=$element.appendChild($doc.CreateElement("connected"))
[System.XML.XMLElement]$favoritesElement=$element.appendChild($doc.CreateElement("favorites"))
[System.XML.XMLElement]$recentlyUsedElement=$element.appendChild($doc.CreateElement("recentlyUsed"))
    
# Save File
if(!([IO.Directory]::Exists([IO.Path]::GetDirectoryName($rdgFile))))
{
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($rdgFile))
}

$doc.Save($rdgFile)

Invoke-Item $rdgFile

write-host "finished"
