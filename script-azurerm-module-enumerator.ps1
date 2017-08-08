#script to scan other scripts for azure commands to list needed azure modules
# 170518

[CMDLETBINDING()]
param(
[string]$scriptFile,
[string]$scriptDir
)

function main()
{

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
    $availableModules = (get-module azurerm.* -ListAvailable) | Sort-Object -Unique

    foreach($file in $files)
    {
        write-host "checking file: $($file)"
        $scriptSource = Get-Content -Raw -Path $file
        $matches = ([regex]::Matches($scriptSource, "\W`([a-z]+?-azurerm[a-z]+?`)\W",[Text.RegularExpressions.RegexOptions]::IgnoreCase))
        
        foreach($match in ($matches| Sort-Object -Unique))
        {
            $matchedValue = $match.Captures[0].Groups[1].Value 
            
            write-host "`t`tazure command: $($matchedValue)"
            $module = $null
            foreach($availableModule in $availableModules)
            {
                write-verbose "`t`t`tavailable module: $($availableModule)"

                #if($availableModule.ExportedCommands.Keys -imatch $matchedValue)
                if($availableModule.ExportedCmdlets.Keys -imatch $matchedValue)
                {
                    $module = $availableModule.Name

                    if($module)
                    {
                        write-verbose "`t`t`t`tchecking if module in list: $($module)"
                        if(!$neededAzureModules.Contains($module))
                        {
                            write-host "`t`t`t`t`tadding module to list: $($module)" -ForegroundColor Green
                            [void]$neededAzureModules.Add($module)
                            continue
                        }
                        else
                        {
                            write-host "`t`t`t`t`tmodule already in list: $($module)" -ForegroundColor DarkGray
                        }

                    }
                }
            }

            if(!$module)
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
