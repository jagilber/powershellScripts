<#
.SYNOPSIS
nuget.exe ps wrapper

.DESCRIPTION
checks for nuget.exe and downloads if needed. 
creates $nuget ps object with functions an properties to manage nuget packages

.NOTES
v1.2
# -allversions is broken in nuget.exe

.EXAMPLE
[net.servicePointManager]::Expect100Continue = $true;[net.servicePointManager]::SecurityProtocol = [net.SecurityProtocolType]::Tls12;
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
    [string]$nugetFallbackFolder = "$($env:userprofile)\.dotnet\NuGetFallbackFolder"
    [bool]$allVersions = $false
    [ValidateSet('normal','detailed','quiet')]
    [string]$verbose = "normal" #"normal" # detailed, quiet
    [string]$nuget = "nuget.exe"

    NugetObj() {
        write-host "nugetobj init"
        $nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
        if (!(test-path $this.nuget)) {
            write-host "nuget does not exist"
            $this.nuget = "$env:temp\nuget.exe"
            if (!(($env:path -split ';') -contains $env:temp)) {
                $env:path += ";$($env:temp)"
                write-host "adding temp path"
            }

            if (!(test-path $this.nuget)) {
                write-host "downloading nuget"
                [net.webclient]::new().DownloadFile($nugetDownloadUrl, $this.nuget)
            }
        }
        else {
            $this.nuget = "$pwd\nuget.exe"
            if (!($env:path -split ';') -contains $pwd) {
                $env:path += ";$($pwd)"
                write-host "adding $pwd path"
            }
        }
        $this.EnumSources()
        $this.EnumLocals()
    }

    <#
        AddPackage adds a package to a local store on disk and expands files
        $packageName is name of package
        $nugetPackagePath is source path of package (.nupkg) to add
        $targetDirectory is the destination path or 'locals' name
    #>
    [string[]] AddPackage([string]$packageName, [string]$nugetPackagePath, [string]$targetDirectory) {
        if (!(test-path $targetDirectory)) {
            write-host "checking: $targetDirectory"
            $outputDirectory = $this.EnumLocalsPath($targetDirectory)
            if (!$outputDirectory) {
                write-host "creating path: $targetDirectory"
                mkdir $targetDirectory
            }
        }

        $outputDirectory = " -source $targetDirectory" 

        write-host "nuget add $nugetPackagePath$outputDirectory -expand -verbosity $($this.verbose)" -ForegroundColor magenta
        $this.ExecuteNuget("add $nugetPackagePath$outputDirectory -expand -verbosity $($this.verbose)")

        write-host "add finished. checking $targetDirectory for $packageName" -ForegroundColor darkmagenta
        return $this.GetDirectories("$targetDirectory/$packageName",'*')

        write-host "add finished. checking cache." -ForegroundColor darkmagenta
        return $this.EnumPackages($packageName, $nugetPackagePath)
    }

    [string[]] AddSourceNugetOrg() {
        [void]$this.EnumSources()
        return $this.AddSource('nuget.org', 'https://www.nuget.org/api/v2/')
    }

    [string[]] AddSource([string]$nugetSourceName, [string]$nugetSource, [string]$username, [string]$password) {
        [void]$this.EnumSources()
        write-host "nuget sources add -name $nugetSourceName -source $nugetSource -username $userName -password $password"
        write-host (nuget sources add -name $nugetSourceName -source $nugetSource -username $userName -password $password)
        return $this.EnumSources()
    }

    [string[]] AddSource([string]$nugetSourceName, [string]$nugetSource) {
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

        foreach ($source in (nuget locals all -List)) {
            [string[]]$sourceProperties = $source -split ": "
            $packageDirectoryName = $sourceProperties[0]
            $packageDirectory = $sourceProperties[1]

            if (!(test-path $packageDirectory)) {
                mkdir $packageDirectory
            }

            if (!($this.locals.Contains($packageDirectoryName))) {
                $this.locals.Add($packageDirectoryName, $packageDirectory)
            }
        }

        if ((test-path $this.nugetFallbackFolder)) {
            $this.locals.Add("nugetFallbackFolder", $this.nugetFallbackFolder)
        }
        write-host "$($this.locals | out-string)"
        return $this.locals
    }

    [string] EnumLocalsPath([string]$localName) {
        if (!$this.locals) { $this.EnumLocals() }
        $outputDirectory = ($this.locals.GetEnumerator() | Where-Object Name -ieq $localName).Value
        return $outputDirectory
    }

    [hashtable] EnumLocalPackages ([string]$packageName) {
        [hashtable]$results = @{}
        foreach ($localSource in $this.locals.GetEnumerator()) {
            foreach ($result in $this.EnumPackages($packageName, $localSource.Key, $null).GetEnumerator()) {
                if (!$results.ContainsKey($result.Key)) {
                    $results.Add($result.Key, $result.Value)
                } 
                else {
                    write-warning "$($result.key) already added"
                }
            }
        }
        return $results
    }

    [hashtable] EnumPackagesTag ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "tag:")
    }

    [hashtable] EnumPackagesAny ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "id:")
    }

    [hashtable] EnumPackages ([string]$packageName) {
        return $this.EnumPackages($packageName, $null, "")
    }

    [hashtable] EnumPackages ([string]$packageName, [string]$packageSource) {
        return $this.EnumPackages($packageName, $packageSource, "")
    }

    [hashtable] EnumPackages ([string]$packageName, [string]$packageSource, [string]$searchFilter) {
        $this.packagesource = $packageSource
        $this.packages = @{}
        $sourcePackages = $null
        [string]$all = ""
        [string]$sourcePackage = ""
        [string]$packageId = "packageid:"

        if ($searchFilter) {
            $packageId = ""
        }

        if ($this.locals.Contains($packageSource)) {
            write-host "converting local package source $packageSource to $($this.locals[$packageSource])" -ForegroundColor cyan
            $this.packageSource = $this.locals[$packageSource].trimend('\')
        }
        elseif ($this.sources.Contains($packageSource)) {
            write-host "converting source package source $packageSource to $($this.sources[$packageSource].sourcePath)" -ForegroundColor cyan
            $this.packageSource = $this.sources[$packageSource].sourcePath.trimend('\')
        }

        if ($this.allVersions) {
            $all = " -allVersions"
        }

        if ($this.packageSource) {
            $sourcePackage = " -Source $($this.packageSource)"
        }

        write-host "nuget list $($packageId)$packageName$($searchFilter) -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease"
        $sourcePackages = nuget list "$($packageId)$($packageName)$($searchFilter)" -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease

        if ($sourcePackages.Length -lt 1 -or ($sourcePackages.Contains('No Packages found.') -and $searchFilter)) {
            write-warning "no packages found, trying with searchfilter first $searchFilter"
            write-host "nuget list $($searchFilter)$packageName -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease"
            $sourcePackages = nuget list "$($searchFilter)$($packageName)" -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease
        }

        if ($sourcePackages.Length -lt 1 -or ($sourcePackages.Contains('No Packages found.') -and $searchFilter)) {
            write-warning "no packages found, trying without searchfilter $searchFilter"
            write-host "nuget list $packageName -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease"
            $sourcePackages = nuget list "$($packageName)" -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease
        }

        if ($sourcePackages.Length -lt 1 -or $sourcePackages.Contains('No Packages found.')) {
            $searchFilter = '*'
            write-warning "no packages found, trying with filter $searchFilter"
            write-host "nuget list $packageName$searchFilter -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease"
            $sourcePackages = nuget list "$($packageName)$($searchFilter)" -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease
        }

        if ($sourcePackages.Length -lt 1 -or $sourcePackages.Contains('No Packages found.')) {
            $searchFilter = '*'
            write-warning "no packages found, trying with filter $searchFilter"
            write-host "nuget list $searchFilter$packageName -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease"
            $sourcePackages = nuget list "$($searchFilter)$($packageName)" -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease
        }

        if ($sourcePackages.Length -lt 1 -or $sourcePackages.Contains('No Packages found.')) {
            $searchFilter = '*'
            write-warning "no packages found, trying with filter $searchFilter"
            write-host "nuget list $searchFilter$packageName$searchFilter -verbosity $($this.verbose)$all -prerelease$sourcePackage"
            $sourcePackages = nuget list "$($searchFilter)$($packageName)$($searchFilter)" -verbosity $($this.verbose)$($all)$($sourcePackage) -prerelease
        }

        foreach ($package in $sourcePackages) {
            write-host "checking package: $package"
            if ($package -ilike 'No Packages found.') {
                write-error $package
                return $this.packages
            }

            [string[]]$packageProperties = $package -split " "
            [string]$resultName = $null
            [string]$resultVersion = $null

            try {
                $resultName = $packageProperties[0]
                $resultVersion = $packageProperties[1]

                if ($resultName -inotmatch $packageName) {
                    write-host "$resultName does not match packagename:$packageName, skipping."
                    continue
                }

                if ($searchFilter -and $searchFilter -ne '*') {
                    if ($resultName -inotmatch $searchFilter) {
                        write-host "$resultName does not match searchfilter:$searchFilter, skipping."
                        continue
                    }
                }

                $this.packages.Add($resultName, $resultVersion)
                write-host "$resultName $resultVersion"

                if ($this.allVersions) {
                    $matches = [regex]::Matches((Invoke-WebRequest "https://www.nuget.org/packages/$resultName/").Content, "/packages/$resultName/([\d\.-]*?)`"")
                    foreach ($match in $matches) {
                        write-host "`t$($match.Groups[1].Value)"
                    }
                }
            }
            catch {
                write-host "$resultName $resultVersion already added"
            }
        }
        return $this.packages
    }

    [hashtable] EnumSources() {
        write-host "nuget sources List"
        $this.sources = @{}
        $results = (nuget sources List)
        $source = @{}

        foreach ($result in $results) {
            $result = $result.trim()
            if (!$result) { continue }
            $pattern = "(?<sourceNumber>\d+?)\.\s+?(?<sourceName>[^\s].+?)\s+?\[(?<sourceEnabled>.+?)\]"
            $match = [regex]::match($result, $pattern)

            if ($match.success) {
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
        write-host ($this.sources.values | Select-Object sourceNumber, sourceName, sourcePath, sourceEnabled | Sort-Object sourceNumber | out-string)
        return $this.sources
    }

    [string[]] GetDirectories([string]$sourcePattern) {
        return $this.GetDirectories($this.globalPackages, $sourcePattern)
    }

    [string[]] GetDirectories([string]$sourcePath, [string]$sourcePattern) {
        write-host "getdirectories: $sourcePath\$sourcePattern"
        if (!(test-path $sourcePath)) {
            $sourcePath = $this.EnumLocalsPath($sourcePath)
        }
        if(!$sourcePath) { return @() }
        $results = @([io.directory]::GetDirectories("$sourcePath", $sourcePattern, [io.searchOption]::AllDirectories))
        write-host "returning directory list: $($results | out-string)"
        return $results
    }

    [string[]] GetFiles([string]$sourcePattern) {
        return $this.GetFiles($this.globalPackages, $sourcePattern)
    }

    [string[]] GetFiles([string]$sourcePath, [string]$sourcePattern) {
        write-host "getfiles: $sourcePath $sourcePattern"
        if (!(test-path $sourcePath)) {
            $sourcePath = $this.EnumLocalsPath($sourcePath)
        }

        write-host "[io.directory]::GetFiles(`"$sourcePath`", $sourcePattern, [io.searchOption]::AllDirectories)"
        return @([io.directory]::GetFiles("$sourcePath", $sourcePattern, [io.searchOption]::AllDirectories))
    }

    <#
        InstallPackage installs a package to a project and installs any dependencies from nuget.org
        $packageName is name of package
    #>
    [string[]] InstallPackage([string]$packageName) {
        if (!$this.EnumSources().GetEnumerator().name -contains 'nuget.org') {
            $this.AddSourceNugetOrg()
        }
        return $this.InstallPackage($packageName, 'nuget.org', $this.globalPackages, $null)
    }

    <#
        InstallPackage installs a package to a project and installs any dependencies
        $packageName is name of package
        $packageSource is nuget package source example nuget.org
    #>
    [string[]] InstallPackage([string]$packageName, [string]$packageSource = $null) {
        return $this.InstallPackage($packageName, $packageSource, $null, $null)
    }

    <#
        InstallPackage installs a package to a project and installs any dependencies
        $packageName is name of package
        $packageSource is nuget package source example nuget.org
        $packagesDirectory is destination path for package install
        $prerelease is whether to install prerelease versions of package
    #>
    [string[]] InstallPackage([string]$packageName, [string]$packageSource, [string]$packagesDirectory = $null, [bool]$prerelease) {
        $pre = $null
        $source = $null
        $outputDirectory = $null
        if ($packagesDirectory) { 
            if (!(test-path $packagesDirectory)) {
                write-host "checking: $packagesDirectory"
                $outputDirectory = $this.EnumLocalsPath($packagesDirectory)
                if (!$outputDirectory) {
                    write-host "creating path: $packagesDirectory"
                    mkdir $packagesDirectory
                }    
            }
            $outputDirectory = " -directdownload -outputdirectory $packagesDirectory" 
        }
        if ($prerelease) { $pre = " -prerelease" }
        if ($packageSource) { $source = " -source $packageSource" }

        write-host "nuget install $packageName$source$outputDirectory -noHttpCache -verbosity $($this.verbose)$pre" -ForegroundColor magenta
        $this.ExecuteNuget("install $packageName$source$outputDirectory -noHttpCache -verbosity $($this.verbose)$pre")

        if ($packagesDirectory) {
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
        if ($error) {
            write-warning ($error | out-string)
            $error.clear()
        }
    }

    [bool] RemoveLocalPackage([string]$packageName, [string]$packageVersion = $null, [string]$packageSource = $null) {
        if (!$packageSource) { $this.packageSource = $this.globalPackages }
        $folders = @()
        $versionFolders = @()

        if ($this.locals.contains($packageSource)) {
            $folders = $this.GetDirectories($this.locals[$packageSource], $packageName)

            if ($packageVersion) {
                foreach ($folder in $folders) {
                    $versionFolders += $this.GetDirectories($folder, $packageVersion)
                }

                $folders = $versionFolders
            }

            foreach ($folder in $folders) {
                write-warning "deleting folder $folder"
                #[io.directory]::Delete($folder, $true)
            }

            return $true
        }

        write-warning "locals does not contain $packageSource cache name"
        return $false
    }

    [bool] RemoveLocalPackagesCache([string]$packageSource) {
        if ($this.locals.contains($packageSource)) {
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
        $this.Restore($null, $null)
    }

    [void] Restore([string]$configurationFile, [string]$packagesDirectory) {
        [string]$outputDirectory = $null
        if (!$packagesDirectory) { $outputDirectory = "-packagesDirectory $($this.globalPackages)" }
        if ($configurationFile) {
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
