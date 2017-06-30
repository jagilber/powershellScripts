# script to populate textFilter rvf filter file from etw inf.txt file

param(
    $infFile
)

$script:xmlFileTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
    <filterinfo>
        <filterversion></filterversion>
        <filternotes />
        <filters>
        </filters>
    </filterinfo>
'@

# ----------------------------------------------------------------------------------------------------------------
function main()
{
    $infFile = [IO.Path]::GetFullPath($infFile)

    populate-textFilterFile -filterFile "$($infFile).rvf" -infFile $infFile
}

# ----------------------------------------------------------------------------------------------------------------
function populate-textFilterFile([string] $filterFile, $infFile)
{

    #<?xml version="1.0" encoding="utf-8"?>
    #<filterinfo>
    #  <filterversion>17040443</filterversion>
    #  <filternotes />
    #  <filters>
    #    <filter>
    #      <filterpattern>test</filterpattern>
    #      <backgroundcolor>Black</backgroundcolor>
    #      <foregroundcolor>PapayaWhip</foregroundcolor>
    #      <casesensitive>False</casesensitive>
    #      <index>0</index>
    #      <enabled>True</enabled>
    #      <exclude>False</exclude>
    #      <regex>False</regex>
    #      <notes />
    #    </filter>
    #  </filters>
    #</filterinfo>

    
    if([IO.File]::Exists($infFile))
    {
        $infFileContent = [IO.File]::ReadAllText($infFile)
    }
    else
    {
        write-error "infFile doesnt exist. returning $($infFile)"
        return
    }

    [xml.xmldocument] $xmlDoc = xml-reader $filterFile
 
 
    $xmlDoc.DocumentElement.filterversion = [DateTime]::Now.ToString("yyMMddhh")
    $xmlDoc.DocumentElement.filternotes = $infFileContent

    $regexPattern = "\|\W+?(?<eventCount>[0-9]+?)\W+?(?<module>\w+?)\W+?(?<eventType>\w+?)\W+?(?<tmf>[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12})\|\W+?(?<source>\w+)"
    $count = 0
    $xmlFiltersNode = $xmlDoc.DocumentElement.SelectSingleNode("filters")

        foreach($match in [regex]::Matches($infFileContent,  $regexPattern))
        {
            $eventCount = $match.Groups["eventCount"].Value
            $eventModule = $match.Groups["module"].Value
            $eventType = $match.Groups["eventType"].Value
            $eventTmf = $match.Groups["tmf"].Value
            $eventSource = $match.Groups["source"].Value
            $notes = "source:$($eventSource) eventCount: $($eventCount) eventModule: $($eventModule) eventTmf: $($eventTmf)"

            [Xml.XmlElement] $xmlFilter = $xmlDoc.CreateElement("filter")
            
            $element = $xmldoc.CreateElement("filterpattern")
            $element.InnerText = $eventSource
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("casesensitive")
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("backgroundcolor")
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("foregroundcolor")
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("enabled")
            $element.InnerText = $true
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("exclude")
            $element.InnerText = $false
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("regex")
            $element.InnerText = $false
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("index")
            $element.InnerText = $count
            $xmlFilter.AppendChild($element)

            $element = $xmldoc.CreateElement("notes")
            $element.InnerText = $notes
            $xmlFilter.AppendChild($element)
            
            $xmlFiltersNode.AppendChild($xmlFilter)

            $count++
        }
 
        xml-writer -file $filterFile -xdoc $xmlDoc
}
# ----------------------------------------------------------------------------------------------------------------
function xml-reader([string] $file)
{
    if($showDetail) 
    {
        log-info "Reading xml config file:$($file)"
    }
 
    try
    {
        [Xml.XmlDocument] $xdoc = New-Object System.Xml.XmlDocument
        if([IO.File]::Exists($file))
        {
            $xdoc.Load($file)
        }
        else
        {
            $xdoc.LoadXml($script:xmlFileTemplate)
        }

        return $xdoc
    }
    catch
    {
        Write-Error "exception:$($error)"
        $error.Clear()
    }
}
 
# ----------------------------------------------------------------------------------------------------------------
function xml-writer([string] $file, [Xml.XmlDocument] $xdoc)
{
    # write xml
    # if xml is not formatted, this will fix it for example when generating config file with logman export
    [IO.StringWriter] $sw = new-object IO.StringWriter
    [Xml.XmlTextWriter] $xmlTextWriter = new-object Xml.XmlTextWriter ($sw)
    $xmlTextWriter.Formatting = [Xml.Formatting]::Indented

    $xdoc.WriteTo($xmlTextWriter)
    $xdoc.PreserveWhitespace = $true
    $xdoc.LoadXml($sw.ToString())
    

    if($showDetail)
    {
        log-info "Writing xml config file:$($file)"
    }
    
    $xdoc.Save($file)
}
 
# ----------------------------------------------------------------------------------------------------------------

main