<#
testing with azure-sf-export-arm-template.ps1 for function enum
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/draft-ast.ps1" -outFile "$pwd/draft-ast.ps1";./draft-ast.ps1
#>
param(
    $file = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-sf-export-arm-template.ps1"
)

# $localFile = "$pwd/$([io.path]::GetFileName($file))"
# if (!$psEditor) {
#     write-error "start ps debugger in vscode"
#     return
# }

# if (!(test-path $localFile)) {
#     Invoke-WebRequest $file -OutFile $localFile
# }

#$psEditor.Workspace.OpenFile($file)

function find-allAst([string]$filter) {
    $global:astList = [collections.arraylist]::new()
    $psEditor.GetEditorContext().CurrentFile.ast.FindAll(
        [System.Func[object, bool]] {
            param($x) 
            $x = [System.Management.Automation.Language.ast]$x
            #write-host ($x) -ForegroundColor DarkGreen
            #write-host ("$($x.gettype())") -ForegroundColor Green
            [void]$global:astList.add($x)
            return $true
        }, $true)
}

function find-allFunctions() {
    $global:functionList = [collections.arraylist]::new()
    $psEditor.GetEditorContext().CurrentFile.ast.FindAll(
        [System.Func[object, bool]] {
            param($x) 
            $x = [System.Management.Automation.Language.ast]$x
            #write-host ($x) -ForegroundColor DarkGreen
            #write-host ("$($x.gettype())") -ForegroundColor Green

            if ([System.Management.Automation.Language.FunctionDefinitionAst] -eq $x.gettype()) {
                #write-host $x.gettype()
                [void]$global:functionList.add($x)
                return $true
            }
            else { 
                return $false
            }
        }, $true)

}


function show-allFunctions() {
    if (!$global:functionList) {
        find-allFunctions
    }
    foreach ($func in $global:functionList) {
        $func = [System.Management.Automation.Language.ast]$func
        write-host "$($func.name) startline:$($func.extent.StartLineNumber) endline:$($func.extent.EndLineNumber)`r`n$($func.Parameters)" -ForegroundColor Green
    }
}

function get-currentTokenWord([object]$context) {
    $context = [Microsoft.PowerShell.EditorServices.Extensions.EditorContext]$context

    $startLine = $psEditor.GetEditorContext().SelectedRange.Start.Line - 1
    $startColumn = $psEditor.GetEditorContext().SelectedRange.Start.Column - 1
        
    $endLine = $psEditor.GetEditorContext().SelectedRange.End.Line - 1
    $endColumn = $psEditor.GetEditorContext().SelectedRange.End.Column - 1

    [string[]]$allLines = $psEditor.GetEditorContext().CurrentFile.GetTextLines()
    [string[]]$selectedLines = $allLines[$startLine .. $endLine]

    if ($startLine -eq $endLine) {
        # get whole line and look for current word
        $lineTokens = [regex]::Matches($selectedLines[0], "(\w+)")

        foreach ($lineToken in $lineTokens) {
            if ($lineToken.Groups[1].Index -le $context.CursorPosition.Column -and 
                ($lineToken.Groups[1].Index + $lineToken.Groups[1].Length) -ge $context.CursorPosition.Column) {
                $tokenWord = $lineToken.Groups[1].Value
                write-host "returning single line token:$tokenWord"
                return $tokenWord
            }
        }

        $selectedLines[0] = $selectedLines[0].Substring($startColumn, $endColumn)
    }
    else {

        $selectedLines[0] = $selectedLines[0].Substring($startColumn)
        $selectedLines[-1] = $selectedLines[0].Substring(0, $endColumn)
    }

    $tokenString = $selectedLines -join ';'
    $tokenWord = [regex]::Match($tokenString, "(\w+)").groups[1].value
    return $tokenWord
}

function find-allReferences([object]$context) {
    Write-Output "The user's cursor is on line $($context.CursorPosition.Line)!"
    if (!$global:functionList) {
        find-allFunctions
    }

    $tokenWord = get-currentTokenWord -context $context
    #$editor = $psEditor.GetEditorContext()
    #$ast = $editor.CurrentFile.ast
    # $tokens = $psEditor.GetEditorContext().CurrentFile.Tokens.Where({
    #     param($x) 
    #     write-host "checking token:$x"
    #     $x -imatch $tokenWord
    # })
    # foreach($token in $tokens){
    foreach($token in $psEditor.GetEditorContext().CurrentFile.Tokens){
        #write-verbose "checking token:$($token | Format-List * | out-string)"
         #write-host "found function reference:$tokenWord func:$($func | Format-List * | out-string)"
         if($token.Text -ieq $tokenWord){
            write-host "found token:$($token | Format-List * | out-string)" -ForegroundColor Green
         }
    }

}

function goto-functionDefinition([object]$context) {
    Write-Output "The user's cursor is on line $($context.CursorPosition.Line)!"
    if (!$global:functionList) {
        find-allFunctions
    }
    $context = [Microsoft.PowerShell.EditorServices.Extensions.EditorContext]$context

    $tokenWord = get-currentTokenWord -context $context

    foreach ($func in $global:functionList) {
        $func = [System.Management.Automation.Language.ast]$func
        write-host "checking for $tokenWord in function:$($func.name) startline:$($func.extent.StartLineNumber) endline:$($func.extent.EndLineNumber)`r`n$($func.Parameters)" -ForegroundColor DarkGray
        if ($func.name -ieq $tokenWord) {
            write-host "found function:$tokenWord func:$($func | Format-List * | out-string)"
            write-host "$($func.name) startline:$($func.extent.StartLineNumber) endline:$($func.extent.EndLineNumber)`r`n$($func.Parameters)" -ForegroundColor Green
            write-host "`$psEditor.GetEditorContext().SetSelection($($func.extent.StartLineNumber),$($func.extent.StartColumnNumber),$($func.extent.EndLineNumber),$($func.extent.EndColumnNumber))"
            $psEditor.GetEditorContext().SetSelection($func.extent.StartLineNumber, $func.extent.StartColumnNumber, $func.extent.EndLineNumber, $func.extent.EndColumnNumber)
            
            return
        }
    }
}
    

# setup commands

Unregister-EditorCommand -Name "PsClassModule._GotoFunctionDefinition"
Register-EditorCommand `
    -Name "PsClassModule._GotoFunctionDefinition" `
    -DisplayName "Goto function definition in powershell class" `
    -Function goto-functionDefinition

Unregister-EditorCommand -Name "PsClassModule._FindAllReferences"
    Register-EditorCommand `
        -Name "PsClassModule._FindAllReferences" `
        -DisplayName "Find all references in powershell class" `
        -Function find-allReferences

Unregister-EditorCommand -Name "PsClassModule.FindAllFunctions"
Register-EditorCommand `
    -Name "PsClassModule.FindAllFunctions" `
    -DisplayName "Load all functions in powershell class" `
    -Function find-allFunctions `
    -suppressoutput
    
Unregister-EditorCommand -Name "PsClassModule.ShowAllFunctions"
Register-EditorCommand `
    -Name "PsClassModule.ShowAllFunctions" `
    -DisplayName "Show all functions in powershell class" `
    -Function show-allFunctions
        

<#
az:
System.Management.Automation.Language.VariableExpressionAst
System.Management.Automation.Language.ArrayExpressionAst
System.Management.Automation.Language.AssignmentStatementAst
System.Management.Automation.Language.AttributeAst
System.Management.Automation.Language.BinaryExpressionAst
System.Management.Automation.Language.BreakStatementAst
System.Management.Automation.Language.CommandAst
System.Management.Automation.Language.CommandExpressionAst
System.Management.Automation.Language.CommandParameterAst
System.Management.Automation.Language.ConstantExpressionAst
System.Management.Automation.Language.ContinueStatementAst
System.Management.Automation.Language.ConvertExpressionAst
System.Management.Automation.Language.ExpandableStringExpressionAst
System.Management.Automation.Language.ForEachStatementAst
System.Management.Automation.Language.FunctionDefinitionAst
System.Management.Automation.Language.HashtableAst
System.Management.Automation.Language.IfStatementAst
System.Management.Automation.Language.IndexExpressionAst
System.Management.Automation.Language.InvokeMemberExpressionAst
System.Management.Automation.Language.MemberExpressionAst
System.Management.Automation.Language.NamedAttributeArgumentAst
System.Management.Automation.Language.NamedBlockAst
System.Management.Automation.Language.ParamBlockAst
System.Management.Automation.Language.ParameterAst
System.Management.Automation.Language.ParenExpressionAst
System.Management.Automation.Language.PipelineAst
System.Management.Automation.Language.ReturnStatementAst
System.Management.Automation.Language.ScriptBlockAst
System.Management.Automation.Language.ScriptBlockExpressionAst
System.Management.Automation.Language.StatementBlockAst
System.Management.Automation.Language.StringConstantExpressionAst
System.Management.Automation.Language.SubExpressionAst
System.Management.Automation.Language.TypeConstraintAst
System.Management.Automation.Language.TypeExpressionAst
System.Management.Automation.Language.UnaryExpressionAst
System.Management.Automation.Language.VariableExpressionAst


sf:
System.Management.Automation.Language.ArrayExpressionAst
System.Management.Automation.Language.AssignmentStatementAst
System.Management.Automation.Language.AttributeAst
System.Management.Automation.Language.BinaryExpressionAst
System.Management.Automation.Language.BreakStatementAst
System.Management.Automation.Language.CommandAst
System.Management.Automation.Language.CommandExpressionAst
System.Management.Automation.Language.CommandParameterAst
System.Management.Automation.Language.ConstantExpressionAst
System.Management.Automation.Language.ContinueStatementAst
System.Management.Automation.Language.ConvertExpressionAst
System.Management.Automation.Language.ExpandableStringExpressionAst
System.Management.Automation.Language.ForEachStatementAst
System.Management.Automation.Language.FunctionDefinitionAst
System.Management.Automation.Language.FunctionMemberAst
System.Management.Automation.Language.HashtableAst
System.Management.Automation.Language.IfStatementAst
System.Management.Automation.Language.IndexExpressionAst
System.Management.Automation.Language.InvokeMemberExpressionAst
System.Management.Automation.Language.MemberExpressionAst
System.Management.Automation.Language.NamedBlockAst
System.Management.Automation.Language.ParamBlockAst
System.Management.Automation.Language.ParameterAst
System.Management.Automation.Language.ParenExpressionAst
System.Management.Automation.Language.PipelineAst
System.Management.Automation.Language.PropertyMemberAst
System.Management.Automation.Language.ReturnStatementAst
System.Management.Automation.Language.ScriptBlockAst
System.Management.Automation.Language.ScriptBlockExpressionAst
System.Management.Automation.Language.StatementBlockAst
System.Management.Automation.Language.StringConstantExpressionAst
System.Management.Automation.Language.SubExpressionAst
System.Management.Automation.Language.TypeConstraintAst
System.Management.Automation.Language.TypeDefinitionAst
System.Management.Automation.Language.TypeExpressionAst
System.Management.Automation.Language.UnaryExpressionAst
System.Management.Automation.Language.VariableExpressionAst
#>

<#

PS C:\github\jagilber\powershellScripts> $psEditor.GetEditorContext()|fl *


CurrentFile    : Microsoft.PowerShell.EditorServices.Extensions.FileContext
SelectedRange  : Microsoft.PowerShell.EditorServices.Extensions.BufferFileRange
CursorPosition : Microsoft.PowerShell.EditorServices.Extensions.BufferFilePosition

PS C:\github\jagilber\powershellScripts> $psEditor.GetEditorContext().SelectedRange.Start


Line Column
---- ------
 170     18

PS C:\github\jagilber\powershellScripts> $psEditor.GetEditorContext().SelectedRange.end  


Line Column
---- ------
 170     27

  "WorkspacePath": "powershellScripts\\draft-ast.ps1"
  },
  "SelectedRange": {
    "Start": {
      "Line": 87,
      "Column": 27
    },
    "End": {
      "Line": 87,
      "Column": 42
    }
  },
  "CursorPosition": {
    "Line": 87,
    "Column": 42
  }


#>