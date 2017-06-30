#script to scan other scripts for azure commands to list needed azure modules
# 170518

param(
[string]$scriptDir
)

function main()
{
    
    if(!$scriptDir)
    {
        $scriptDir = [IO.Path]::GetDirectoryName($MyInvocation.ScriptName)
    }
   $files = [Io.Directory]::GetFiles($scriptDir,"*.ps1",[Io.SearchOption]::TopDirectoryOnly)
   $neededAzureModules = new-object Collections.ArrayList
   $availableModules = (get-module azurerm.* -ListAvailable)

   foreach($file in $files)
   {
        $scriptSource = Get-Content -Raw -Path $file

        foreach($match in ([regex]::Matches($scriptSource, "\W`([a-z]+?-azurerm[a-z]+?`)\W",[Text.RegularExpressions.RegexOptions]::IgnoreCase)))
        {
            $matchedValue = $match.Captures[0].Groups[1].Value
            
            foreach($availableModule in $availableModules)
            {
                if($availableModule.ExportedCommands.Keys -imatch $matchedValue)
                {
                    $module = $availableModule.Name

                    if($module)
                    {
                        if(!$neededAzureModules.Contains($module))
                        {
                            [void]$neededAzureModules.Add($module)
                            continue
                        }
                    }
                }
            }
        }

        write-host "needed modules for file: $($file)`r`n$($neededAzureModules | format-list * | out-string)"
        $neededAzureModules.Clear()
        write-host "-----------------------------------------"
    }

    $neededAzureModules
}
    
main
