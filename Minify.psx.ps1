<#
.SYNOPSIS
    Minify PipeScript Transpiler
.DESCRIPTION
    Uses Compress-ScriptBlock to minify a section of PowerShell code
.EXAMPLE
    {
        [minify]{
            "a"
            "b"
            Get-Process -id $pid | Where-Object WorkingSet -gt 10mb
        }
    } | .>PipeScript
.LINK
    https://github.com/StartAutomating/PipeScript
#>
param(
[Parameter(Mandatory,ValueFromPipeline)]
[ScriptBlock]
$ScriptBlock    
)

Compress-ScriptBlock -ScriptBlock $ScriptBlock
