#script to scan other scripts for azure az commands to list needed azure modules

[CMDLETBINDING()]
param(
    [string]$scriptFile,
    [string]$scriptDir
)

$PSModuleAutoLoadingPreference = 2
$module = "az"
function main()
{
    if(!(get-module Az -ListAvailable)){
        if((get-module AzureRm)){
            write-error "azurerm installed. remove azurerm and then install azure az"
            return
        }

        install-module Az -Force -AllowClobber
    }

    Import-Module Az

    if(!$scriptDir -and !$scriptFile)
    {
        $scriptDir = [IO.Path]::GetDirectoryName($MyInvocation.ScriptName)
    }

    if($scriptFile)
    {
        $files = @($scriptFile)
    }
    else
    {
        $files = [Io.Directory]::GetFiles($scriptDir,"*.ps1",[Io.SearchOption]::TopDirectoryOnly)
    }

    $neededAzureModules = new-object Collections.ArrayList
    $availableModules = (get-module "$module.*" -ListAvailable) | Sort-Object -Property Name,Version -Descending | Get-Unique 

    foreach($file in $files)
    {
        write-host "checking file: $($file)"
        $scriptSource = Get-Content -Raw -Path $file
        
        if([regex]::IsMatch($scriptSource, "-azurerm", [Text.RegularExpressions.RegexOptions]::IgnoreCase))
        {
            Write-Warning("$file contains -azurerm commands! use script-azure-rm-module-enumerator.ps1")
        }

        $matched = ([regex]::Matches($scriptSource, "\W([a-z]+-$module[a-z]+)\W",[Text.RegularExpressions.RegexOptions]::IgnoreCase))
        
        foreach($match in ($matched | Sort-Object -Unique))
        {
            $matchedValue = $match.Captures[0].Groups[1].Value 
            
            write-host "`t`t$module command: $($matchedValue)"
            $foundModule = $null
            foreach($availableModule in $availableModules)
            {
                write-verbose "`t`t`tavailable module: $($availableModule)"

                if($availableModule.ExportedCmdlets.Keys -imatch $matchedValue `
                    -or $availableModule.ExportedAliases.Keys -imatch $matchedValue)
                {
                    $foundModule = $availableModule.Name

                    if($foundModule)
                    {
                        write-verbose "`t`t`t`tchecking if module in list: $($foundModule)"
                        if(!$neededAzureModules.Contains($foundModule))
                        {
                            write-host "`t`t`t`t`tadding module to list: $($foundModule)" -ForegroundColor Green
                            [void]$neededAzureModules.Add($foundModule)
                            continue
                        }
                        else
                        {
                            write-host "`t`t`t`t`tmodule already in list: $($foundModule)" -ForegroundColor DarkGray
                        }

                    }
                }
            }

            if(!$foundModule)
            {
                Write-Warning "unable to find module for command $($matchedValue)"
            }
        }

        if($neededAzureModules.Count -gt 0)
        {
            write-host "needed modules for file: $($file)"
            write-host "$($neededAzureModules | format-list * | out-string)" -ForegroundColor Magenta
        }
        else
        {
            write-host "NO azure modules needed for file: $($file)" -ForegroundColor Gray
        }

        $neededAzureModules.Clear()
        write-host "-----------------------------------------"
    }

    $neededAzureModules
}
    
main

