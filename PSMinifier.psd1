@{
    ModuleVersion = '1.1.4'
    PowerShellVersion = '3.0'
    RootModule = 'PSMinifier.psm1'
    Description = 'A Miniature Minifier For PowerShell'
    Guid = '534cd9d0-e4b4-4c96-ae0f-6f31224274b9'
    Author = 'Start-Automating'
    Copyright = '2020 Start-Automating'
    PrivateData = @{
        PSData = @{
            Tags = 'Minifier', 'PipeScript'
            ProjectURI = 'https://github.com/StartAutomating/PSMinifier'
            LicenseURI = 'https://github.com/StartAutomating/PSMinifier/blob/master/LICENSE'
            ReleaseNotes = @'
### v1.1.4
* Compress-ScriptBlock:  Aliasing PSMinify (#13)
* Adding support for Minify transpiler in PipeScript (#11)
* Compress-ScriptBlock:  Returning [ScriptBlock] if possible (#12)
---
### v1.1.3
---
Compress-ScriptBlock bugfix: now handling using statements (Issue #6).  Improvements to try/catch (Issue #7)

### v1.1.2
----
Compress-ScriptBlock bugfix: now handling [Hashtables] and [Ordered] (Issue #2)

### v1.1.1
----
Compress-ScriptBlock bugfix:  try/catch/finally blocks now appropriately handled (Issue #3)

### v1.1
----
Compress-ScriptBlock now has -OutputPath/-PassThru
Added Support for GitHub Action

### v1.0
----
Initial Version of Minifier
'@
        }
    }
}