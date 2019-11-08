#using namespace system.collections
# -allversions is broken in nuget.exe

class NugetObj {
    [hashtable]$sources = @{}
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
    }

    [hashtable] EnumPackagesTag ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "tag:")
    }

    [hashtable] EnumPackagesAny ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "id:")
    }

    [hashtable] EnumPackages ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, $null)
    }

    [hashtable] EnumPackages ([string]$packageName,[string]$packageSource) {
        return $this.EnumPackages($packageName, $packageSource, $null)
    }

    [hashtable] EnumPackages ([string]$packageName,[string]$packageSource,[string]$searchFilter) {
        $this.packagesource = $packageSource
        if(!$searchFilter) { $searchFilter = "packageid:" }

        if($this.sources.Contains($packageSource)) {
            write-host "converting $packageSource to $($this.sources[$packageSource])" -ForegroundColor cyan
            $this.packageSource = $this.sources[$packageSource].trimend('\')
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
        write-host "nuget locals all -List"
        $this.sources = @{}

        foreach($source in (nuget locals all -List)) {
            [string[]]$sourceProperties = $source -split ": "
            $this.sources.Add($sourceProperties[0],$sourceProperties[1])
        }
        write-host "$($this.sources | out-string)"
        return $this.sources
    }

    [string[]] AddSource([string]$nugetSourceName,[string]$nugetSource) {
        write-host "nuget sources add -name $nugetSourceName -source $nugetSource"
        write-host (nuget sources add -name $nugetSourceName -source $nugetSource)
        return $this.EnumSources()
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

    [string[]] RemoveSource([string]$nugetSourceName,[string]$nugetSource) {
        write-host "nuget sources remove -name $nugetSourceName -source $nugetSource"
        write-host (nuget sources remove -name $nugetSourceName -source $nugetSource)
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
