﻿#requires -Module Pester
describe 'PSMinifier' {
    it 'Makes scripts smaller' {
        $compressScriptBlock = Get-Command Compress-ScriptBlock
        $compressed = $compressScriptBlock |
            Compress-ScriptBlock -Anonymous
        if ($compressed.Length -gt $compressScriptBlock.ScriptBlock.ToString().Length) {
            throw "Minified length $($compressed.Length) exceeds input length $($compressScriptBlock.ScriptBlock.ToString().Length)"
        }
    }

    it 'Can -GZip them to make them even smaller' {
        $compressScriptBlock = Get-Command Compress-ScriptBlock
        $compressed = $compressScriptBlock |
            Compress-ScriptBlock -Anonymous
        $gzipped = $compressScriptBlock |
            Compress-ScriptBlock -GZip -Anonymous
        if ($gzipped.Length -gt $compressScriptBlock.ScriptBlock.ToString().Length) {
            throw "GZipped length $($gzipped.Length) exceeds input length $($compressScriptBlock.ScriptBlock.ToString().Length)"
        }

        if ($gzipped.Length -gt $compressed.Length) {
            throw "GZipped length $($gzipped.Length) exceeds minified length $($compressed.Length)"
        }
    }
}