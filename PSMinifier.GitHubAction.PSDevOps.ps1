#requires -Module PSMinifier
#requires -Module PSDevOps
Import-BuildStep -ModuleName PSMinifier
New-GitHubAction -Name "PSMinifier" -Description 'A Miniature Minifier For PowerShell' -Action PSMinifier -Icon minimize -ActionOutput ([Ordered]@{
    OriginalSize = [Ordered]@{
        description = "The Original Size of all files"
        value = '${{steps.PSMinifier.outputs.OriginalSize}}'
    }
    MinifiedSize = [Ordered]@{
        description = "The Total Size of all minified files"
        value = '${{steps.PSMinifier.outputs.MinifiedSize}}'
    }
    MinifiedPercent= [Ordered]@{
        description = "The Percentage Saved by minifying"
        value = '${{steps.PSMinifier.outputs.MinifiedPercent}}'
    }
})|
    Set-Content .\action.yml -Encoding UTF8 -PassThru
