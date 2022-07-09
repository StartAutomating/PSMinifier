<#
.Synopsis
    PSMinifier Action
.Description
    Runs PSMinifier on code in the workspace, and creates .min.ps1 files.
#>
param(
# One or more wildcards of files to include.
# If not provided, all .ps1 in a workspace will be included.
[string[]]
$Include,

# One or more wildcards of files to exclude.
[string[]]
$Exclude = "*.*.ps1",

# If set, the minified content will be encoded as GZip, further reducing it's size.
[switch]
$GZip,

# If set, zipped minified content will be encoded without blocks, making it a very long single line.
# This parameter is only valid with -GZip.
[switch]
$NoBlock,

# If provided, will commit changes made to the workspace with this commit message.
[string]
$CommitMessage,

# The user email associated with a git commit.
[string]
$UserEmail,

# The user name associated with a git commit.
[string]
$UserName
)

"::group::Parameters" | Out-Host
[PSCustomObject]$PSBoundParameters | Format-List | Out-Host
"::endgroup::" | Out-Host

@"
::group::GitHubEvent
$($gitHubEvent | ConvertTo-Json -Depth 100)
::endgroup::
"@ | Out-Host

$PSD1Found = Get-ChildItem -Recurse -Filter "*.psd1" | Where-Object Name -eq 'PSMinifier.psd1' | Select-Object -First 1

if ($PSD1Found) {
    $psMinifierPath = $PSD1Found
    Import-Module $PSD1Found -Force -PassThru | Out-Host
}
elseif ($env:GITHUB_ACTION_PATH) {
    $psMinifierPath = Join-Path $env:GITHUB_ACTION_PATH 'PSMinifier.psd1'
    if (Test-path $psMinifierPath) {
        Import-Module $psMinifierPath -Force -PassThru | Out-String
    } else {
        throw "PSMinifier not found"
    }
} elseif (-not (Get-Module PSMinifier)) {
    Get-ChildItem env: | Out-String
    throw "Action Path not found"
}

"::debug::PSMinifier Loaded from Path - $($psMinifierPath)" | Out-Host

if (-not $env:GITHUB_WORKSPACE) { throw "No GitHub workspace" }
if (-not $CommitMessage -and $gitHubEvent.head_commit.message) {
    $CommitMessage = $gitHubEvent.head_commit.message
}

$compressSplat = @{} + $PSBoundParameters
$compressSplat.Remove('Include')
$compressSplat.Remove('Exclude')
$compressSplat.Remove('CommitMessage')
$compressSplat.Remove('UserEmail')
$compressSplat.Remove('UserName')
if ($GZip) { $compressSplat.DotSource = $true }

"EXCLUDING $Exclude" | Out-Host

$commandsToMinify =
    @(Get-ChildItem -LiteralPath $env:GITHUB_WORKSPACE -Filter *.ps1 |
        Where-Object {
            $fileInfo = $_ 
            if ($fileInfo.Name -like '*.min.*ps1') { return } # Don't overminify
            if ($Include) {
                foreach ($inc in $Include) {
                    if ($fileInfo.Name -like $inc) { return $true }
                }
            } else { return $true }
        } |
        Where-Object {
            $fileInfo = $_ 
            if ($Exclude) {
                foreach ($ex in $Exclude) {
                    if ($fileInfo.Name -like $ex) { return $false }
                }
                return $true
            } else {
                return $true
            }
        } |
        Get-Command { $_.FullName })


$minifiedCommands =
    @($commandsToMinify |
        Compress-ScriptBlock @compressSplat -OutputPath {
            if ($GZip) {
                $_.Source -replace '\.ps1$', '.min.gzip.ps1'
            } else {
                $_.Source -replace '\.ps1$', '.min.ps1'
            }
        } -PassThru)
"::group::Minified Commands" | Out-Host
$minifiedCommands | Out-Host
"::endgroup::" | Out-Host

"::group::Summary" | Out-Host
$totalOriginal = 0 
$totalMinified = 0 
for ($n =0 ; $n -lt $commandsToMinify.Length; $n++) {
    $safeName = $commandsToMinify[$n].Name -replace '\W'
    $originalSize = ([IO.FileInfo]$($commandsToMinify[$n].Source)).Length
    $totalOriginal+=$originalSize
    $minifiedSize = $minifiedCommands[$n].Length
    $totalMinified = $minifiedSize
    $minifiedPercent = $minifiedCommands[$n].Length / $originalSize
    "$($commandsToMinify[$n].name) -> $($minifiedCommands[$n].Name) - $([Math]::Round($minifiedPercent * 100, 2))%" | Out-Host
    "::set-output name=$($safeName)_MinifiedSize::$minifiedSize"       | Out-Host
    "::set-output name=$($safeName)_MinifiedPercent::$minifiedPercent" | Out-Host
}
"Total Original Size: $([Math]::Round(($totalOriginal /1kb),2))kb"     | Out-Host
"::set-output name=OriginalSize::$totalOriginal"                       | Out-Host
"::set-output name=MinifiedSize::$totalMinified"                       | Out-Host
"::set-output name=MinifiedPercent::$($totalOriginal / $totalMinified)"| Out-Host
"Total Minified Size: $([Math]::Round(($totalMinified /1kb),2))kb"     | Out-Host

"::endgroup::" | Out-Host

if ($CommitMessage -and $minifiedCommands) {
    if (-not $UserName) { $UserName = $env:GITHUB_ACTOR }
    if (-not $UserEmail) { $UserEmail = "$UserName@github.com" }
    git config --global user.email $UserEmail
    git config --global user.name  $UserName

    $filesUpdated = 0
    $minifiedCommands |
        ForEach-Object {
            $gitStatusOutput = git status $_.Fullname -s
            if ($gitStatusOutput) {
                git add $_.Fullname
                $filesUpdated++
            } else {
                "No need to Commit $($_.FullName)" | Out-Host
            }
        }

    if ($filesUpdated) {
        $ErrorActionPreference = 'continue'
        $gitPushed =  git push 2>&1
        "Git Push Output: $($gitPushed  | Out-String)"
        $LASTEXITCODE = 0
        exit 0        
    } else {
        "Nothing to Push" | Out-Host
    }
}