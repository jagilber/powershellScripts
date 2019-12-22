#using namespace system.collections
# -allversions is broken in nuget.exe

class NugetObj {
    [hashtable]$sources = @{}
    [hashtable]$locals = @{}
    [hashtable]$packages = @{}
    [string]$packageName = $null
    [string]$packageSource = $null
    [string]$globalPackages = "$($env:USERPROFILE)\.nuget\packages"
    [bool]$allVersions = $false
    [string]$verbose = "normal" # detailed, quiet

    NugetObj() {
        $nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        if (!($env:path.contains(";$pwd;$env:temp"))) { 
            $env:path += ";$pwd;$env:temp" 
            
            if($PSScriptRoot -and !($env:path.contains(";$psscriptroot"))) {
                $env:path += ";$psscriptroot" 
            }
        } 

        if (!(test-path nuget)) {
            (new-object net.webclient).downloadFile($nugetDownloadUrl, "$pwd\nuget.exe")
        }

        $this.EnumSources()
        $this.EnumLocals()
    }

    [string[]] AddSource([string]$nugetSourceName,[string]$nugetSource,[string]$username,[string]$password) {
        [void]$this.EnumSources()
        write-host "nuget sources add -name $nugetSourceName -source $nugetSource -username $userName -password $password"
        write-host (nuget sources add -name $nugetSourceName -source $nugetSource -username $userName -password $password)
        return $this.EnumSources()
    }

    [string[]] AddSource([string]$nugetSourceName,[string]$nugetSource) {
        [void]$this.EnumSources()
        write-host "nuget sources add -name $nugetSourceName -source $nugetSource"
        write-host (nuget sources add -name $nugetSourceName -source $nugetSource)
        return $this.EnumSources()
    }

    [string[]] DisableSource([string]$nugetSourceName) {
        write-host "nuget sources disable -name $nugetSourceName"
        write-host (nuget sources disable -name $nugetSourceName)
        return $this.EnumSources()
    }

    [string[]] EnableSource([string]$nugetSourceName) {
        write-host "nuget sources enable -name $nugetSourceName"
        write-host (nuget sources enable -name $nugetSourceName)
        return $this.EnumSources()
    }

    [hashtable] EnumLocals() {
        write-host "nuget locals all -List"
        $this.locals = @{}

        foreach($source in (nuget locals all -List)) {
            [string[]]$sourceProperties = $source -split ": "
            $this.locals.Add($sourceProperties[0],$sourceProperties[1])
        }
        write-host "$($this.locals | out-string)"
        return $this.locals
    }

    [hashtable] EnumPackagesTag ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "tag:")
    }

    [hashtable] EnumPackagesAny ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "id:")
    }

    [hashtable] EnumPackages ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "packageid:")
    }

    [hashtable] EnumPackages ([string]$packageName,[string]$packageSource) {
        return $this.EnumPackages($packageName, $packageSource, "packageid:")
    }

    [hashtable] EnumPackages ([string]$packageName,[string]$packageSource,[string]$searchFilter) {
        $this.packagesource = $packageSource
        #if(!$searchFilter) { $searchFilter = "packageid:" }

        if($this.locals.Contains($packageSource)) {
            write-host "converting local package source $packageSource to $($this.locals[$packageSource])" -ForegroundColor cyan
            $this.packageSource = $this.locals[$packageSource].trimend('\')
        }
        elseif($this.sources.Contains($packageSource)) {
            write-host "converting source package source $packageSource to $($this.sources[$packageSource].sourcePath)" -ForegroundColor cyan
            $this.packageSource = $this.sources[$packageSource].sourcePath.trimend('\')
        }

        $this.packages = @{}
        $sourcePackages = $null
        [string]$all = ""

        if($this.allVersions)
        {
            $all = " -allVersions"
        }

        if($this.packageSource) { 
            write-host "nuget list $searchFilter$packageName -verbosity $($this.verbose)$all -prerelease -Source $($this.packageSource)"
            $sourcePackages = nuget list "$searchFilter$packageName" -verbosity $($this.verbose)$($all) -prerelease -Source $($this.packageSource)
        }
        else {
            write-host "nuget list $searchFilter$packageName -verbosity $($this.verbose)$all -prerelease"
            $sourcePackages = nuget list "$searchFilter$packageName" -verbosity $($this.verbose)$($all) -prerelease 
        }

        foreach($package in $sourcePackages) {
            write-host "checking package: $package"
            if($package -ilike 'No Packages found.' -and $searchFilter) {
                write-warning "$package, trying without searchfilter $searchFilter"
                return $this.EnumPackages($packageName, $packageSource, $null)
            } 
            elseif ($package -ilike 'No Packages found.') {
                write-error $package
                return $this.packages
            }

            [string[]]$packageProperties = $package -split " "
            try {
                $this.packages.Add($packageProperties[0], $packageProperties[1])
                write-host "$($packageProperties[0]) $($packageProperties[1])"

                if($this.allVersions) {
                    $matches = [regex]::Matches((iwr "https://www.nuget.org/packages/$($packageProperties[0])/").Content, "/packages/$($packageProperties[0])/([\d\.-]*?)`"")
                    foreach($match in $matches) {
                        write-host "`t$($match.Groups[1].Value)"
                    }
                }
            }
            catch {
                write-host "$($packageProperties[0]) $($packageProperties[1]) already added"
            }
        }
        return $this.packages
    }

    [hashtable] EnumSources() {
        write-host "nuget sources List"
        $this.sources = @{}
        $results = (nuget sources List)
        $source = @{}

        foreach($result in $results) {
            $result = $result.trim()
            if(!$result) { continue }
            $pattern = "(?<sourceNumber>\d+?)\.\s+?(?<sourceName>[^\s].+?)\s+?\[(?<sourceEnabled>.+?)\]"
            $match = [regex]::match($result, $pattern)

            if($match.success) {
                $source = @{}
                $source.sourceNumber = ($match.groups['sourceNumber'].value)
                $source.sourceName = ($match.groups['sourceName'].value)
                $source.sourceEnabled = ($match.groups['sourceEnabled'].value)
            }
            else {
                try {
                    new-object uri($result) | out-null
                    $source.sourcePath = $result
                    [void]$this.sources.Add($source.sourceName, $source)
                }
                catch {
                    $error.clear()
                    write-verbose $result
                    $source = @{}
                }
            }
        }

        #write-host "$($this.sources | out-string)"
        write-host ($this.sources.values | select sourceNumber, sourceName, sourcePath, sourceEnabled| sort sourceNumber | out-string)
        return $this.sources
    }

    [string[]] InstallPackage([string]$packageName) {
        return $this.InstallPackage($packageName, $null, $null, $null)
    }

    [string[]] InstallPackage([string]$packageName, [string]$packagesDirectory, [string]$packageSource, [switch]$prerelease) {
        $pre = $null
        $source = $null
        if(!$packagesDirectory) { $packagesDirectory = $this.globalPackages}
        if($prerelease) { $pre = " -prerelease"}
        if($packageSource) {$source = " -source $packageSource" }

        write-host "nuget install $packageName$source -outputdirectory $packagesDirectory -verbosity ($this.verbose)$pre"
        write-host (nuget install $packageName$source -outputdirectory $packagesDirectory -verbosity ($this.verbose)$pre)
        return $this.EnumPackages($packageName, $packageSource)
    }

    [string[]] RemoveSource([string]$nugetSourceName) {
        [void]$this.EnumSources()
        write-host "nuget sources remove -name $nugetSourceName"
        write-host (nuget sources remove -name $nugetSourceName)
        return $this.EnumSources()
    }

    [void] Restore() {
        $this.Restore($null,$null)
    }

    [void] Restore([string]$configurationFile,[string]$packagesDirectory) {
        [string]$outputDirectory = $null
        if(!$packagesDirectory) { $outputDirectory = "-packagesDirectory $($this.globalPackages)" }
        if($configurationFile) {
            write-host (nuget restore $configurationFile -verbosity ($this.verbose)$outputDirectory)
        }
        else {
            write-host (nuget restore $configurationFile -verbosity ($this.verbose)$outputDirectory)
        }
    }
}

#if(!$global:nuget)
#{
    $global:nuget = [NugetObj]::new()
#}
$nuget | Get-Member
write-host "use `$nuget object to set properties and run methods. example: `$nuget.Sources" -ForegroundColor Green
