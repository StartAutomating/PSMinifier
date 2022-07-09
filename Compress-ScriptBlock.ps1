#requires -Version 3.0
function Compress-ScriptBlock
{
    <#
    .Synopsis
        Compresss a script block
    .Description
        Compresss a script block into a minified version of itself.

        Minified scripts remove documentation and minimize the spacing between statements.

        This makes scripts significantly smaller and less readable, and also makes them more embeddable.

        Additionally, Compress-ScriptBlock can -GZip the content to further compress the output.
        If -NoBlock is passed, the minified and compressed output will be returned in a single line.

        ScriptBlocks can be given a -Name, which will declare them as a variable.
        This will happen automatically when piping in a command.
        This can be avoided by passing -Anonymous.
    .Example
        $compressedSelf = Get-Command Compress-ScriptBlock | Compress-ScriptBlock
    .Example
        Get-Module PSMinifier | # Get the minifier module's
            Split-Path | # root path
            Join-Path -ChildPath Compress-ScriptBlock.ps1 | # join it with Compress-ScriptBlock.ps1
            Get-Command | # get the command
            Compress-ScriptBlock -GZip -DotSource | # Compress it, anonymized, and dot-sourced
            Set-Content -Path ( # And put it back into
                Get-Module PSMinifier |
                    Split-Path |
                    Join-Path -ChildPath Compress-ScriptBlock.min.gzip.ps1 # Compress-ScriptBlock.min.gzip.ps1
            )
    .Example
        Get-Module PSMinifier | # Get the minifier module's
            Split-Path | # root path
            Join-Path -ChildPath Compress-ScriptBlock.ps1 | # join it with Compress-ScriptBlock.ps1
            Get-Command | # get the command
            Compress-ScriptBlock | # Compress it, anonymized
            Set-Content -Path ( # And put it back into
                Get-Module PSMinifier |
                    Split-Path |
                    Join-Path -ChildPath Compress-ScriptBlock.min.ps1 # Compress-ScriptBlock.min.gzip.ps1
            )
    #>
    [OutputType([string])]
    [Alias('PSMinify')]
    param(
    # The ScriptBlock that will be compressed.
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)]
    [ScriptBlock]
    $ScriptBlock,

    # If provided, will assign the script block to a named variable.
    [Parameter(ValueFromPipelineByPropertyName)]
    [string]
    $Name,

    # If set, will ignore any provided name.
    [Parameter(ValueFromPipelineByPropertyName)]
    [switch]
    $Anonymous,

    # If set, the minified content will be encoded as GZip, further reducing it's size.
    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Zip', 'Compress')]
    [switch]
    $GZip,

    # If set, will dot source the compressed content.
    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Dot', '.')]
    [switch]
    $DotSource,

    # If set, zipped minified content will be encoded without blocks, making it a very long single line.
    # This parameter is only valid with -GZip.
    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('NoBlocks')]
    [switch]
    $NoBlock,

    # If provided, will write the minified content to the specified path, instead of outputting it.
    [Parameter(ValueFromPipelineByPropertyName)]
    [string]
    $OutputPath,

    # If provided with -OutputPath, will output the file written to disk.
    [Parameter(ValueFromPipelineByPropertyName)]
    [switch]
    $PassThru
    )

    begin {
        # First, we declare a number of quick variables to access AST types.
        foreach ($_ in 'BinaryExpression','Expression','ScriptBlockExpression','ParenExpression','ArrayExpression',
            'SubExpression', 'Command','CommandExpression', 'IfStatement', 'LoopStatement', 'Hashtable', 'ConvertExpression',
            'FunctionDefinition','AssignmentStatement','Pipeline','Statement','TryStatement','CommandExpression') {
            $ExecutionContext.SessionState.PSVariable.Set($_, "Management.Automation.Language.${_}Ast" -as [Type])
        }

        # Next, we declare a bunch of ScriptBlocks that handle different scenarios for compressing the AST.
        # These will recursively call each other as needed.

        $CompressScriptBlockAst = { # The topmost compresses a given Script Block's AST.
            param($ast)

            if ($ast.Body) { $ast = $ast.Body } # If the AST had an inner body AST, use that instead

            $dps = $ast.DynamicParamBlock.Statements
            $bs = $ast.BeginBlock.Statements
            $ps = $ast.ProcessBlock.Statements
            $es = $ast.EndBlock.Statements

            @(
            if ($ast.UsingStatements) {
                (@(foreach ($using in $ast.UsingStatements) {
                    "$using"
                }) -join ';') + ';'
            }
            if ($ast.ParamBlock) { # Walk thru the param block.
                $pb = $ast.ParamBlock
                foreach ($a in $pb.Attributes) {
                    $a # Declaration attributes are emitted unaltered
                }
                'param('
                    @(foreach ($p in $pb.Parameters) {
                        @(foreach ($a in $p.Attributes) {
                            $a # Parameter attributes are emitted unaltered
                        }
                        $p.Name) -join '' # then we emit the name and all attributes in one statement
                    }) -join ','
                ')'
            }
            # then, for dynamicParam, begin, process, and end, redeclare the blocks and minify the statements.
            if ($dps) {
                'dynamicParam{'
                @($dps | & $CompressStatement) -join ';'
                '}'
            }
            if ($bs) {
                'begin{'
                @($bs | & $CompressStatement) -join ';'
                '}'
            }
            if ($ps) {
                'process{'
                @($ps | & $CompressStatement) -join ';'
                '}'
            }
            if ($es) {
                if ($bs -or $ps) { 'end{'}
                @($es | & $CompressStatement) -join ';'
                if ($bs -or $ps) { '}'}
            }) -join ''
        }


        $CompressStatement = { # Compressing statements is the tricky part.
            param(
            [Parameter(ValueFromPipeline=$true)]
            [Management.Automation.Language.StatementAst]$s)
            process {
                if ($s -is $IfStatement) { # If it's an if statement
                    $nc = 0
                    @(foreach ($c in $s.Clauses) { # minify each clause
                        if( -not $nc){
                            'if'
                        } else {
                            'elseif'
                        }
                        '(' # by compressing the condition pipeline
                            @($c.Item1.PipelineElements | & $CompressPipeline) -join '|'
                        ')'
                        '{' # and compressing the inner statements
                        @($c.Item2.Statements | & $CompressStatement) -join ';'
                        $nc++
                        '}'
                    }
                    if ($s.ElseClause) {
                        'else{'
                            @($s.ElseClause.Statements | & $CompressStatement) -join ';'
                        '}'
                    }
                    ) -join ''
                }
                elseif ($s -is $LoopStatement) { # If it's a loop
                    $loopType = $s.GetType().Name.Replace('StatementAst','') # determine it's type
                    @(
                    if ($s.Label) { # add the loop label if it exists
                        ":$($s.Label) "
                    }
                    if ($loopType -eq 'foreach') { # and recreate each loop condition.
                        'foreach('
                        $s.Variable
                        ' in '
                        & $compressPart $s.Condition
                        ')'
                    } elseif ($loopType -eq 'for') {
                        'for('
                        $s.Initializer
                        ';'
                        $s.Condition
                        ';'
                        $s.Iterator
                        ')'
                    } elseif ($loopType -eq 'while') {
                        'while('
                        $s.Condition
                        ')'
                    } elseif ($loopType -eq 'dowhile') {
                        'do'
                    }

                    '{'
                    @($s.Body.Statements | & $CompressStatement) -join ';'
                    '}'
                    if ($loopType -eq 'dowhile') {
                        'while('
                        $s.Condition
                        ')'
                    }
                    ) -join ''
                }
                elseif ($s -is $AssignmentStatement) { # If it's an assignment,
                    $as = $s
                    @(
                    $as.Left.ToString().Trim()
                    $as.ErrorPosition.Text
                    if ($as.Right -is [Management.Automation.Language.StatementAst]) {
                        @($as.right | & $CompressStatement) -join ';' # compress the right side
                    }) -join ''
                }
                elseif ($s -is $Pipeline) { # If it's a pipeline
                    @($s.PipelineElements | & $CompressPipeline) -join '|' # minify the pipeline and join by |
                }
                elseif ($s -is $TryStatement) { # If it's a type/catch
                    @(
                    'try{'
                        @($s.Body.statements | & $CompressStatement) -join ';' # minify the try
                    '}'
                    foreach ($cc in $s.CatchClauses) { # then each of the catches
                        'catch'
                        if ($cc.CatchTypes) {
                            foreach ($ct in $cc.CatchTypes) {
                                ' ['
                                $ct.TypeName.FullName
                                ']'
                            }
                        }
                        '{'
                            @($cc.Body.statements | & $CompressStatement) -join ';'
                        '}'
                    }
                    if ($s.Finally) { # then the finally (if it exists)
                        'finally{'
                            $($s.Finally.statements | & $CompressStatement) -join ';'
                        '}'
                    }
                    ) -join ''
                }
                elseif ($s -is $CommandExpression) { # If it's a command expression
                    if ($s.Expression) {
                        $s.Expression | & $CompressExpression # minify the expression
                    } else {
                        $s.ToString()
                    }
                }
                elseif ($s -is $FunctionDefinition) { # If it's a function
                    $(if ($s.IsWorklow) { "workflow " }
                    elseif ($s.IsFilter) { "filter " }
                    else { "function " }) + $s.Name + "{$(& $CompressScriptBlockAst $s.Body)}" # redeclare it with a minified body.
                }
                else {
                    $s.ToString()
                }
            }
        }

        $CompressPipeline = { # If we're compressing a pipeline
            param(
            [Parameter(ValueFromPipeline=$true)]
            [Management.Automation.Language.CommandBaseAst]$p)

            process {
                if ($p -is $CommandExpression) {
                    & $CompressExpression $p.Expression # compress each expression
                } elseif ($p -is $Command) {
                    @(
                    if ($p.InvocationOperator -eq 'Ampersand') {
                        '&'
                    } elseif ($p.InvocationOperator -eq 'Dot') {
                        '.'
                    }
                    foreach ($e in $p.CommandElements) {
                        if ($e.ScriptBlock) {
                            "{$(& $CompressScriptBlockAst $e.ScriptBlock)}" # and compress any nested script blocks
                        } else { $e }
                    }) -join ' '
                } elseif ($p) {
                    $p.ToString()
                } else {
                    $null = $null
                }
            }
        }

        $CompressExpression = { # If we're compressing an expression,
            param(
            [Parameter(ValueFromPipeline=$true,Position=0)]
            [Management.Automation.Language.ExpressionAst]$e)
            process {
                @(
                if ($e -is $BinaryExpression) # and it's a binary expression
                {
                    if ($e.Left -is $Expression) { # compress the left
                        & $CompressExpression $e.Left
                    } else {
                        $e.Left
                    }
                    $e.ErrorPosition
                    if ($e.Right -is $Expression) { # and the right.
                        & $CompressExpression $e.Right
                    } else {
                        $e.Right
                    }
                }
                elseif ($e -is $ScriptBlockExpression) # If it was a script expression
                {
                    '{'
                    & $CompressScriptBlockAst $e.ScriptBlock # minify the script.
                    '}'
                }
                elseif ($e -is $ParenExpression) { # If it was a paren expresssion, arrayexpression, or subexpression
                    '('
                    . $compressPart $e # we have to minify each part of the expression.
                    ')'
                }
                elseif ($e -is $ArrayExpression) {
                    '@('
                    . $compressPart $e
                    ')'
                }
                elseif ($e -is $SubExpression) {
                    '$('
                    . $compressPart $e
                    ')'
                }
                elseif ($e -is $convertExpression) {
                    "[$($e.Type.TypeName -replace '\s')]"
                    . $CompressExpression $e.Child
                }
                elseif ($e -is $hashtable) {
                    '@{' +
                    (@(foreach ($kvp in $e.KeyValuePairs) {
                        @(. $compressPart $kvp.Item1
                        '='
                        . $compressPart $kvp.Item2
                        ) -join ''
                    })  -join ';')+ '}'
                }
                elseif ($e.Elements) {
                    @(foreach ($_ in $e.Elements) {
                        . $CompressPart $_
                    }) -join ','
                }
                else {
                    $e.ToString()
                }) -join ''

            }
        }


        $CompressPart = { # If we're minifying pars of an expression
            param([Parameter(ValueFromPipeline=$true,Position=0)]$p)
            process {
                if ($p.SubExpression) { @($p.Subexpression.Statements | & $CompressStatement) -join ';' } # join minified subexpression statements by ;,
                elseif ($p.Pipeline) { @($p.Pipeline.PipelineElements | & $CompressPipeline) -join '|' } # pipeline elements by |,
                elseif ($p -is $FunctionDefinition) { # redeclare any functions, minified
                    $(if ($p.IsWorklow) { "workflow " }
                    elseif ($p.IsFilter) { "filter " }
                    else { "function " }) + $p.Name + "{$(& $CompressScriptBlockAst $p.Body)}"
                }
                elseif ($p.ScriptBlock) { "{$(& $CompressScriptBlockAst $p.ScriptBlock)}" } # minify any script blocks
                elseif ($p -is $Pipeline) {
                    @($p.PipelineElements | & $CompressPipeline) -join '|'
                }
                else { $p } # any emit anything we don't know about.
            }
        }
    }

    process {
        if ($_ -is [Management.Automation.CommandInfo]) { $name = '' }
        # Now, call our minifier with this script block's AST
        $compressedScriptBlock = & $CompressScriptBlockAst $ScriptBlock.Ast

        $compressedScriptBlock = # After that, resassign $CompressedScriptBlock as needed
            if (-not $GZip) {
                $compressedScriptBlock
            }
            else { # If we're GZIPing,
                $data = [Text.Encoding]::Unicode.GetBytes($compressedScriptBlock) # compress the content
                $ms = [IO.MemoryStream]::new()
                $cs = [IO.Compression.GZipStream]::new($ms, [Io.Compression.CompressionMode]"Compress")
                $cs.Write($Data, 0, $Data.Length)
                $cs.Close()
                $cs.Dispose()

                if ($NoBlock) { # If we're using -NoBlocks, emit it as a single line
                    "`$([ScriptBlock]::Create(([IO.StreamReader]::new(([IO.Compression.GZipStream]::new([IO.MemoryStream]::new([Convert]::FromBase64String('$([Convert]::ToBase64String($ms.ToArray()))')),[IO.Compression.CompressionMode]'Decompress')),[Text.Encoding]::unicode)).ReadToEnd()))"
                }
                else
                {
                    # Otherwise, add _some_ whitespace.
                    "`$([ScriptBlock]::Create(([IO.StreamReader]::new((
    [IO.Compression.GZipStream]::new([IO.MemoryStream]::new(
        [Convert]::FromBase64String('
$([Convert]::ToBase64String($ms.ToArray(), 'InsertLineBreaks'))
        ')),
        [IO.Compression.CompressionMode]'Decompress')),
    [Text.Encoding]::unicode)).ReadToEnd()
))"
                }

                $ms.Close()
                $ms.Dispose()
            }

        if ($DotSource) { # If we're dot sourcing,

            $compressedScriptBlock = # reassign $compressedScriptBlock again
                if ($GZip) {
                    ". $compressedScriptBlock" # if we're GZipping, fine (since the return value of this will be a script block)
                } else {
                     ". {$compressedScriptBlock}" # otherwise, wrap it in {}s.
                }
        }

        $minified =
            if ($Name -and -not $Anonymous) { # If we've provided a -Name and don't want to be -Anonymous, we're assigning to a variable.
                if (-not $GZip -and -not $DotSource) {  # If it's not GZipped or dotted,
                    $compressedScriptBlock = "{$compressedScriptBlock}" # we need to wrap it in {}s.
                }
                if ($Name -match '\W') { # If the name contained non-word characters,
                    "`${$name} = $compressedScriptBlock" # we need to wrap it in {}s.
                } else {
                    "`$$name = $compressedScriptBlock" # otherwise, it's just $name = $compressedScriptBlock
                }
            } else {
                $compressedScriptBlock
            }

        if ($OutputPath) { # If we've been provided an -OutputPath
            # figure out what it might be
            $unresolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
            [IO.File]::WriteAllText("$unresolvedOutputPath", $minified) # and then write content to disk.
            if ($PassThru -and [IO.File]::Exists("$unresolvedOutputPath")) {
                [IO.FileInfo]"$unresolvedOutputPath"
            }
        } elseif ($(
            $minifiedScriptBlock = [ScriptBlock]::Create($minified) 
            $minifiedScriptBlock
        )) {            
            $minifiedScriptBlock # Otherwise, output the minified content.
        } else {
            $minified
        }
    }
}