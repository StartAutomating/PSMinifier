﻿@{
    ModuleVersion = '1.1'
    PowerShellVersion = '3.0'
    RootModule = 'PSMinifier.psm1'
    Description = 'A Miniature Minifier For PowerShell'
    Guid = '534cd9d0-e4b4-4c96-ae0f-6f31224274b9'
    Author = 'Start-Automating'
    Copyright = '2020 Start-Automating'
    PrivateData = @{
        PSData = @{
            Tags = 'Minifier'
            ProjectURI = 'https://github.com/StartAutomating/PSMinifier'
            LicenseURI = 'https://github.com/StartAutomating/PSMinifier/blob/master/LICENSE'
            ReleaseNotes = @'
v1.1
----
Compress-ScriptBlock now has -OutputPath/-PassThru
Added Support for GitHub Action

v1.0
----
Initial Version of Minifier
'@
        }
    }
}