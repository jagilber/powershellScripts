<#
testing with azure-sf-export-arm-template.ps1 for function enum
invoke-webRequest "https://raw.githubusercontent.com/jagilber/powershellScripts/master/draft-ast.ps1" -outFile "$pwd/draft-ast.ps1";./draft-ast.ps1
#>
param(
    $file = "https://raw.githubusercontent.com/jagilber/powershellScripts/master/serviceFabric/azure-sf-export-arm-template.ps1"
)

#$localFile = "$pwd/$([io.path]::GetFileName($file))"
if (!$psEditor) {
    write-error "start ps debugger in vscode"
    return
}

#if(!(test-path $localFile)){
#    iwr $file -OutFile $localFile
#}

$psEditor.Workspace.OpenFile($file)

$global:astList = [collections.arraylist]::new()
$psEditor.GetEditorContext().CurrentFile.ast.FindAll(
    [System.Func[object, bool]] {
        param($x) 
        $x = [System.Management.Automation.Language.ast]$x
        #write-host ($x) -ForegroundColor DarkGreen
        write-host ("$($x.gettype())") -ForegroundColor Green

        if ([System.Management.Automation.Language.FunctionDefinitionAst] -eq $x.gettype()) {
            write-host $x.gettype()
            [void]$global:astList.add($x)
            return $true
        }
        else { 
            return $false
        }
    }, $true)

$global:astList.name

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