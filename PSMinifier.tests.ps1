#requires -Module Pester
. .\Compress-ScriptBlock.ps1

Function Test-Syntax
{
    param([string]$ScriptString)
    $ex = $null
    try
    {
        [ScriptBlock]::Create($ScriptString) 
    }
    catch
    {
        $ex = $_
    }
    $null -eq $ex
}
Describe 'PSMinifier' {
    It 'Makes scripts smaller and without syntax errors' {
        #$VerbosePreference = 'Continue'
        $compressScriptBlock = Get-Command Compress-ScriptBlock | select -Expand Definition
        $compressed = Compress-ScriptBlock -ScriptBlock ([ScriptBlock]::Create($compressScriptBlock))
        $compressed.Length | Should -BeLessThan $compressScriptBlock.Length
        Write-Host "Reduced $($compressScriptBlock.Length) to $($compressed.Length)"
        Write-Host "Compression Ratio: $(((1-($compressed.Length / $compressScriptBlock.Length)) * 100).ToString('0'))%"
        Test-Syntax $CompressedScriptBlock | Should -BeTrue
        #$VerbosePreference = 'SilentlyContinue'
    }
    It 'Minify Initialized Variables' {
        Compress-ScriptBlock { $InitializedVariable = 0 } | Should -Be '$a=0'
    }
    It 'Leave Uninitialized Variables' {
        Compress-ScriptBlock { $MyVar } | Should -Be '$MyVar'
    }
    It 'Shorten Variables in ExpandableStrings' {
        $Compressed = Compress-ScriptBlock -ScriptBlock {
            $InitializedVariable = "$UninitializedVariable some text"
        } 
        $Compressed.ToString() | Should -Be '$a="$UninitializedVariable some text"'
    }
    It 'Variable z should rollover' {
        Compress-ScriptBlock -FirstVariableName 'z' { 
            $MyVar = 0
            $YourVar = 0
        } | Should -Be '$z=0;$aa=0'
    }
    It 'Use Shortest Alias' {
        
        Compress-ScriptBlock -ScriptBlock {
            Write-Output "Hello"
        } | Should -Be "echo `"Hello`""
    }

    It 'Script Should have Valid Syntax' {
        
        $CompressedScriptBlock = Compress-ScriptBlock -ScriptBlock {
            Write-Output "Hello"
        } 
        
        Test-Syntax $CompressedScriptBlock | Should -BeTrue
    }
    

    It 'Can -GZip them to make them even smaller' {
        $compressScriptBlock = Get-Command Compress-ScriptBlock
        $compressed = $compressScriptBlock |
            Compress-ScriptBlock -Anonymous
        $gzipped = $compressScriptBlock |
            Compress-ScriptBlock -GZip -Anonymous
        if ($gzipped.Length -gt $compressScriptBlock.ScriptBlock.ToString().Length)
        {
            throw "GZipped length $($gzipped.Length) exceeds input length $($compressScriptBlock.ScriptBlock.ToString().Length)"
        }

        if ($gzipped.Length -gt $compressed.Length)
        {
            throw "GZipped length $($gzipped.Length) exceeds minified length $($compressed.Length)"
        }
    }

    It 'Can shrink try catch blocks' {

        $originalScript = {
            try
            {
                thisMightThrowBecauseThereIsNoCommand | # this commend should go away.
                    thispipeline also uses a lot of whitespace
            }
            catch [System.SystemException]
            {
                "Oh No! An Exception Occured" |
                    Out-String
            }
            finally
            {
                "FinallyGotSomethingDone" | Out-String
            }
        }
        $compresedScript = [Scriptblock]::Create((Compress-ScriptBlock -ScriptBlock $originalScript))
        "$compressedScript".Length |
            Should -BeLessThan "$originalScript".Length
        @(& $compresedScript) -join '' |
            Should -BeLike "*Oh*No!*An*Exception*Occured*FinallyGotSomethingDone*"
    }

    It 'Can compress a [hashtable]' {
        Compress-ScriptBlock -ScriptBlock {
            @{
                a = "b"
                c = "d"
                e = @{
                    f = "h"
                }
            }
        } | Should -Not -Match "\n"
    }

    It 'Can compress an ordered [hashtable]' {
        Compress-ScriptBlock -ScriptBlock {
            [Ordered]@{
                a = "b"
                c = "d"
                e = @{
                    f = "h"
                }
            }
        } | Should -Not -Match "\n"
    }

    It 'Can compress a using statement' {
        $compressed = Compress-ScriptBlock -ScriptBlock ([ScriptBlock]::Create(@"
using namespace System.Security.Cryptography
using namespace System.Windows.Forms
echo 1
echo 2
"@))
        $compressed | Should -Match "using"
        $compressed | Should -Not -Match "\n"

        Invoke-Expression $compressed | Select-Object -First 1 | Should -Be 1
    }
}