<#
.SYNOPSIS
nuget.exe ps wrapper

.DESCRIPTION
checks for nuget.exe and downloads if needed. 
creates $nuget ps object with functions an properties to manage nuget packages

.NOTES
# -allversions is broken in nuget.exe

.EXAMPLE
invoke-webRequest "https://raw.githubusercontent.com/microsoft/CollectServiceFabricData/master/scripts/nuget-functions.ps1" -outFile "$pwd/nuget-functions.ps1";
.\nuget-functions.ps1;
$nuget

.LINK
https://raw.githubusercontent.com/microsoft/CollectServiceFabricData/master/scripts/nuget-functions.ps1
#>

class NugetObj {
    [hashtable]$sources = @{}
    [hashtable]$locals = @{}
    [hashtable]$packages = @{}
    [string]$packageName = $null
    [string]$packageSource = $null
    [string]$globalPackages = "$($env:USERPROFILE)\.nuget\packages"
    [bool]$allVersions = $false
    [string]$verbose = "detailed" #"normal" # detailed, quiet
    [string]$nuget = "nuget.exe"

    NugetObj() {
        write-host "nugetobj init"
        $nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        if (!(test-path $this.nuget)) {
            write-host "nuget does not exist"
            $this.nuget = "$env:temp\nuget.exe"
            if(!(($env:path -split ';') -contains $env:temp)) {
                $env:path += ";$($env:temp)"
                write-host "adding temp path"
            }

            if (!(test-path $this.nuget)) {
                write-host "downloading nuget"
                invoke-webRequest $nugetDownloadUrl -outFile  $this.nuget
            }
        }
        else {
            $this.nuget = "$pwd\nuget.exe"
            if(!($env:path -split ';') -contains $pwd) {
                $env:path += ";$($pwd)"
                write-host "adding $pwd path"
            }
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

    [string[]] GetDirectories([string]$sourcePath, [string]$sourcePattern) {
        write-host "getdirectories: $sourcePath $sourcePattern"
         return @([io.directory]::GetDirectories("$sourcePath", $sourcePattern + "*", [io.searchOption]::TopDirectoryOnly))
    }

    [string[]] InstallPackage([string]$packageName) {
        return $this.InstallPackage($packageName, 'nuget.org', $null, $null)
    }

    [string[]] InstallPackage([string]$packageName, [string]$packageSource = $null) {
        return $this.InstallPackage($packageName, $packageSource, $null, $null)
    }

    [string[]] InstallPackage([string]$packageName, [string]$packageSource, [string]$packagesDirectory = $null, [bool]$prerelease) {
        $pre = $null
        $source = $null
        $outputDirectory = $null
        if($packagesDirectory) { $outputDirectory = " -directdownload -outputdirectory $packagesDirectory"}
        if($prerelease) { $pre = " -prerelease"}
        if($packageSource) {$source = " -source $packageSource" }

        write-host "nuget install $packageName$source$outputDirectory -nocache -verbosity $($this.verbose)$pre" -ForegroundColor magenta
        $this.ExecuteNuget("install $packageName$source$outputDirectory -nocache -verbosity $($this.verbose)$pre")

        if($packagesDirectory) {
            write-host "install finished. checking $packagesDirectory" -ForegroundColor darkmagenta    
            return $this.GetDirectories($packagesDirectory, $packageName)
        }
        else {
            write-host "install finished. checking working dir $pwd" -ForegroundColor darkmagenta
            return $this.GetDirectories($pwd, $packageName)
        }

        write-host "install finished. checking cache." -ForegroundColor darkmagenta
        return $this.EnumPackages($packageName, $this.globalPackages)
    }

    [void] hidden ExecuteNuget([string]$arguments) {
        # issues when trying to convert some nuget calls in script to this function
        $error.clear()
        write-host "executing:nuget.exe $arguments" -ForegroundColor Green
        start-process -filepath nuget -argumentlist $arguments -wait -nonewwindow
        if($error) {
            write-warning ($error | out-string)
            $error.clear()
        }
    }

    [bool] RemoveLocalPackage([string]$packageName, [string]$packageVersion = $null, [string]$packageSource = $null) {
        if(!$packageSource) { $this.packageSource = $this.globalPackages }
        $folders = @()
        $versionFolders = @()

        if($this.locals.contains($packageSource)) {
            $folders = $this.GetDirectories($this.locals[$packageSource], $packageName)

            if($packageVersion) {
                foreach($folder in $folders) {
                    $versionFolders += $this.GetDirectories($folder, $packageVersion)
                }

                $folders = $versionFolders
            }

            foreach($folder in $folders) {
                write-warning "deleting folder $folder"
                #[io.directory]::Delete($folder, $true)
            }

            return $true
        }

        write-warning "locals does not contain $packageSource cache name"
        return $false
    }

    [bool] RemoveLocalPackagesCache([string]$packageSource) {
        if($this.locals.contains($packageSource)) {
            write-host "nuget locals $packageSource -clear -verbosity $($this.verbose)"
            write-host (nuget locals $packageSource -clear -verbosity ($this.verbose))
            return $true
        }

        write-warning "locals does not contain $packageSource cache name"
        return $false
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

