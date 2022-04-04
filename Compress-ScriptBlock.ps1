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
    param(
        # The ScriptBlock that will be compressed.
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName)]
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

        # If provided, will be used as the name of the first variable
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $FirstVariableName = 'a',

        # If provided with -OutputPath, will output the file written to disk.
        [Parameter(ValueFromPipelineByPropertyName)]
        [switch]
        $PassThru
    )

    begin
    {
        # First, we declare a number of quick variables to access AST types.
        foreach ($_ in 'BinaryExpression', 'Expression', 'ScriptBlockExpression', 'ParenExpression', 'ArrayExpression', 'ArrayLiteral',
            'SubExpression', 'Command', 'CommandExpression', 'IfStatement', 'LoopStatement', 'Hashtable', 'ConvertExpression',
            'FunctionDefinition', 'AssignmentStatement', 'Pipeline', 'Statement', 'TryStatement',  
            'VariableExpression', 'IndexExpression', 'InvokeMemberExpression', 'CommandParameter', 'ConstantExpression', 
            'StringConstantExpression', 'MemberExpression', 'ExpandableStringExpression')
        {
            $ExecutionContext.SessionState.PSVariable.Set($_, "Management.Automation.Language.${_}Ast" -as [Type])
        }
        $global:CompressedVariables = @{}
        $global:NextVariableName = $FirstVariableName
        # Next, we declare a bunch of ScriptBlocks that handle different scenarios for compressing the AST.
        # These will recursively call each other as needed.
        Function Compress-ScriptBlockAst
        {
            # The topmost compresses a given Script Block's AST.
            param($ast)

            if ($ast.Body) { $ast = $ast.Body } # If the AST had an inner body AST, use that instead

            $dps = $ast.DynamicParamBlock.Statements
            $bs = $ast.BeginBlock.Statements
            $ps = $ast.ProcessBlock.Statements
            $es = $ast.EndBlock.Statements

            @(
                if ($ast.UsingStatements)
                {
                    (@(foreach ($using in $ast.UsingStatements)
                            {
                                "$using"
                            }) -join ';') + ';'
                }
                if ($ast.ParamBlock)
                {
                    # Walk thru the param block.
                    $pb = $ast.ParamBlock
                    foreach ($a in $pb.Attributes)
                    {
                        $a # Declaration attributes are emitted unaltered
                    }
                    'param('
                    @(foreach ($p in $pb.Parameters)
                        {
                            @(foreach ($a in $p.Attributes)
                                {
                                    $a # Parameter attributes are emitted unaltered
                                }
                                $p.Name) -join '' # then we emit the name and all attributes in one statement
                        }) -join ','
                    ')'
                }
                # then, for dynamicParam, begin, process, and end, redeclare the blocks and minify the statements.
                if ($dps)
                {
                    'dynamicParam{'
                    @($dps | Compress-Statement) -join ';'
                    '}'
                }
                if ($bs)
                {
                    'begin{'
                    @($bs | Compress-Statement) -join ';'
                    '}'
                }
                if ($ps)
                {
                    'process{'
                    @($ps | Compress-Statement) -join ';'
                    '}'
                }
                if ($es)
                {
                    if ($bs -or $ps) { 'end{'}
                    @($es | Compress-Statement) -join ';'
                    if ($bs -or $ps) { '}'}
                }) -join ''
        }


        Function Compress-Statement
        {
            # Compressing statements is the tricky part.
            param(
                [Parameter(ValueFromPipeline=$true)]
                [Management.Automation.Language.StatementAst]$s)
            process
            {
                $CallStackDepth = (Get-PSCallStack | measure | select -Expand Count)    
                Write-Verbose "Line $($s.Extent.StartLineNumber) Depth: $($CallStackDepth) $($s.GetType().BaseType.Name).$($s.GetType().Name) $($s.Extent.Text)"
                $Type = $s.GetType().Name.Replace('Ast', '')
                switch($s)
                {
                    {$_ -is $IfStatement}
                    {
                        # If it's an if statement
                        $nc = 0
                        # Clauses is ReadOnlyCollection<Tuple<PipelineBaseAst,StatementBlockAst>>
                        @(foreach ($c in $s.Clauses)
                            {
                                # minify each clause
                                if( -not $nc)
                                {
                                    'if'
                                }
                                else
                                {
                                    'elseif'
                                }
                                '(' # by compressing the condition pipeline
                                # Item1 is first Item in the tuple, making Item1 a PipelineBaseAst
                                # PipelineElements is a property of PipelineAst which derives from PipelineBaseAst
                                # In practice, PipelineElement shows up sometimes as CommandExpressionAst
                                # They both inherit from StatementAst so we use Compress-Statement
                                $c.Item1 | Compress-Pipeline
                                ')'
                                '{' # and compressing the inner statements
                                @($c.Item2.Statements | Compress-Statement) -join ';'
                                $nc++
                                '}'
                            }
                            if ($s.ElseClause)
                            {
                                'else{'
                                @($s.ElseClause.Statements | Compress-Statement) -join ';'
                                '}'
                            }
                        ) -join ''
                    }
                    {$_ -is $AssignmentStatement}
                    {
                        # If it's an assignment,
                        $as = $s
                        $ThisVariable = $as.Left.ToString().Trim()
                        $global:CompressedVariables."$ThisVariable" = $global:NextVariableName
                        @(
                            '$' + $global:NextVariableName
                            $as.ErrorPosition.Text
                            if ($as.Right -is [Management.Automation.Language.StatementAst])
                            {
                                @($as.right | Compress-Statement) -join ';' # compress the right side
                            }
                            else
                            {
                                throw "Unexpected type $($as.Right.GetType().Name)"
                            }
                        ) -join ''
                        if($global:NextVariableName[-1] -eq 'z')
                        {
                            [string]$global:NextVariableName = (0..($global:NextVariableName.Length) | %{ 'a' }) -Join ''
                        }
                        else
                        {
                            $global:NextVariableName = $global:NextVariableName.Substring(0, $global:NextVariableName.Length - 1) + [char](([int][char]$global:NextVariableName[-1]) + 1)
                        }
                    }                        
                    {$_ -is $LoopStatement}
                    {
                        # If it's a loop
                        $loopType = $s.GetType().Name.Replace('StatementAst', '') # determine it's type
                        @(
                            if ($s.Label)
                            {
                                # add the loop label if it exists
                                ":$($s.Label) "
                            }
                            if ($loopType -eq 'foreach')
                            {
                                # and recreate each loop condition.
                                'foreach('
                                $s.Variable
                                ' in '
                                Compress-Pipeline $s.Condition
                                ')'
                            }
                            elseif ($loopType -eq 'for')
                            {
                                'for('
                                $s.Initializer
                                ';'
                                $s.Condition
                                ';'
                                $s.Iterator
                                ')'
                            }
                            elseif ($loopType -eq 'while')
                            {
                                'while('
                                $s.Condition
                                ')'
                            }
                            elseif ($loopType -eq 'dowhile')
                            {
                                'do'
                            }

                            '{'
                            @($s.Body.Statements | Compress-Statement) -join ';'
                            '}'
                            if ($loopType -eq 'dowhile')
                            {
                                'while('
                                $s.Condition
                                ')'
                            }
                        ) -join ''
                    }
                    {$_ -is $Pipeline}
                    {
                        # If it's a pipeline
                        # PipelineElements is ReadOnlyCollection<CommandBaseAst>
                        Compress-Pipeline $s # minify the pipeline and join by |
                    }
                    {$_ -is $TryStatement}
                    {
                        # If it's a type/catch
                        @(
                            'try{'
                            @($s.Body.statements | Compress-Statement) -join ';' # minify the try
                            '}'
                            foreach ($cc in $s.CatchClauses)
                            {
                                # then each of the catches
                                'catch'
                                if ($cc.CatchTypes)
                                {
                                    foreach ($ct in $cc.CatchTypes)
                                    {
                                        ' ['
                                        $ct.TypeName.FullName
                                        ']'
                                    }
                                }
                                '{'
                                @($cc.Body.statements | Compress-Statement) -join ';'
                                '}'
                            }
                            if ($s.Finally)
                            {
                                # then the finally (if it exists)
                                'finally{'
                                $($s.Finally.statements | Compress-Statement) -join ';'
                                '}'
                            }
                        ) -join ''
                    }
                    {$_ -is $CommandExpression}
                    {
                        # If it's a command expression
                        if ($s.Expression)
                        {
                            $s.Expression | Compress-Expression # minify the expression
                        }
                        else
                        {
                            $s.ToString()
                        }
                    }
                    {$_ -is $FunctionDefinition}
                    {
                        # If it's a function
                        $(if ($s.IsWorklow) { "workflow " }
                            elseif ($s.IsFilter) { "filter " }
                            else { "function " }) + $s.Name + "{$(Compress-ScriptBlockAst $s.Body)}" # redeclare it with a minified body.
                    }
                    default
                    {
                        $s.ToString()
                    }
                }
            }
        }
        Function Compress-Command
        {
            param(
                [Parameter(ValueFromPipeline=$true, Position=0)]
                [Management.Automation.Language.CommandBaseAst]$p)
            process
            {
                if ($p -is $CommandExpression)
                {
                    Compress-Expression $p.Expression # compress each expression
                }
                elseif($p -is $Command)
                {
                    if ($p.InvocationOperator -eq 'Ampersand')
                    {
                        '&'
                    }
                    elseif ($p.InvocationOperator -eq 'Dot')
                    {
                        '.'
                    }
                    @(foreach ($e in $p.CommandElements)
                        {
                            if ($e -is $Expression)
                            {
                                Compress-Expression $e
                                #"{$(Compress-ScriptBlockAst $e.ScriptBlock)}" # and compress any nested script blocks
                            } 
                            else
                            { 
                                # Should be CommandParameterAst                 
                                $e.Extent.Text
                            }
                        }) -Join ' '
                }
                else
                {
                    throw "$($p.GetType().Name) not expected!"
                }
            }
        }
        Function Compress-Pipeline 
        {
            # If we're compressing a pipeline
            param(
                [Parameter(ValueFromPipeline=$true)]
                [Management.Automation.Language.PipelineBaseAst]$p)
            <# PipelineBaseAst
                AssignmentStatementAst
                ChainableAst
                  PipelineAst
                  PIpelineChainAst
                ErrorStatementAst
            #>
            process
            {   
                if($p -is $Pipeline)
                {
                    @($p.PipelineElements | Compress-Command) -Join '|'
                }               
                elseif ($p)
                {
                    $p.ToString()
                }
                else
                {
                    $null = $null
                }
            }
        }

        Function Compress-Expression
        {
            # If we're compressing an expression,
            param(
                [Parameter(ValueFromPipeline=$true, Position=0)]
                [Management.Automation.Language.ExpressionAst]$e)
            process
            {
                Function Expand-Expression
                { 
                    param($e)
                    if ($e -is $BinaryExpression) # and it's a binary expression
                    {
                        if ($e.Left -is $Expression)
                        {
                            # compress the left
                            Compress-Expression $e.Left
                        }
                        else
                        {
                            $e.Left
                        }
                        $e.ErrorPosition
                        if ($e.Right -is $Expression)
                        {
                            # and the right.
                            Compress-Expression $e.Right
                        }
                        else
                        {
                            $e.Right
                        }
                    }
                    elseif($e -is $MemberExpression)
                    {
                        if($e -is $InvokeMemberExpression)
                        {
                            $Separator = "."
                            if($e.Static)
                            {
                                $Separator = "::"
                            }
                            
                            "$($e.Expression)$($Separator)$($e.Member)(" + `
                                "$(($e.Arguments | %{ 
                                    if($_ -isnot $MemberExpression)
                                    {
                                        Compress-Expression $_ 
                                    }
                                    else
                                    {
                                        $_
                                    }
                                }) -Join ','))"
                        }
                        else
                        {
                            $CompressedMemberExpression = $e.Expression
                            if($e.Expression -isnot $MemberExpression)
                            {
                                $CompressedMemberExpression = Compress-Expression $e.Expression
                            }
                            "$($CompressedMemberExpression).$($e.Member)"
                        }
                    }
                    elseif($e -is $ExpandableStringExpression)
                    {
                        if($e.Value)
                        {
                            $StringBuilder = New-Object System.Text.StringBuilder $e.Extent.Text
                            foreach($ne in ($e.NestedExpressions | sort @{E ={$_.Extent.EndOffset}} -Desc))
                            {
                                $CompressedNestedExpression = Compress-Expression $ne
                                if($CompressedNestedExpression -ne $ne.Extent.Text)
                                {
                                    Write-Verbose "Replacing $($ne.Extent.Text) with $CompressedNestedExpression"
                                    $RelativeStartIndex = $ne.Extent.StartScriptPosition.Offset - $ne.Parent.Extent.StartScriptPosition.Offset                                
                                    $RelativeStartIndex--
                                    $CharactersToRemove = $ne.Extent.Text.Length                                        
                                    $StringBuilder.Remove($RelativeStartIndex, $CharactersToRemove) | Out-Null
                                    $StringBuilder.Insert($RelativeStartIndex, $CompressedNestedExpression) | Out-Null
                                }
                            }
                            Write-Verbose "Outputting $($StringBuilder.ToString())"
                            $StringBuilder.ToString()
                        }
                        else
                        {
                            '""'
                        }
                    }
                    elseif($e -is $IndexExpression)
                    {
                        "$(Compress-Expression $e.Target)[$($e.Index)]"
                    }
                    elseif($e -is $VariableExpression)
                    {
                        Write-Verbose "Line $($e.Extent.StartLineNumber) Variable: $($e.Extent.Text)"
                        $CompressedVariableName = $global:CompressedVariables."$($e)"
                        if(!$CompressedVariableName)
                        {
                            $e.Extent.Text
                        }
                        else
                        {
                            '$' + $CompressedVariableName
                        }
                    }
                    elseif ($e -is $ScriptBlockExpression) # If it was a script expression
                    {
                        '{'
                        Compress-ScriptBlockAst $e.ScriptBlock # minify the script.
                        '}'
                    }
                    elseif ($e -is $ParenExpression)
                    {
                        # If it was a paren expresssion, arrayexpression, or subexpression
                        '('
                        Compress-Pipeline $e.Pipeline # we have to minify each part of the expression.
                        ')'
                    }
                    elseif ($e -is $ArrayExpression)
                    {
                        '@('
                        @($e.Subexpression.Statements | Compress-Statement) -join ';'                        
                        ')'
                    }
                    elseif ($e -is $SubExpression)
                    {
                        '$('
                        @($e.Subexpression.Statements | Compress-Statement) -join ';'   
                        ')'
                    }
                    elseif ($e -is $convertExpression)
                    {
                        "[$($e.Type.TypeName -replace '\s')]"
                        Compress-Expression $e.Child
                    }
                    elseif ($e -is $hashtable)
                    {
                        '@{' +
                        (@(foreach ($kvp in $e.KeyValuePairs)
                                {
                                    @(Compress-Expression $kvp.Item1
                                        '='
                                        Compress-Statement $kvp.Item2
                                    ) -join ''
                                })  -join ';')+ '}'
                    }
                    elseif($e -is $ConstantExpression)
                    {
                        if($e -is $StringConstantExpression)
                        {
                            if($e.StringConstantType -ne 'BareWord')
                            {
                                $e.Extent.Text
                            }
                            else
                            {
                                try
                                {
                                    if(!$global:AllCommands)
                                    {
                                        $global:AllCommands = Get-Command -ListAvailable
                                    }
                                    # If this is the full command name, this will get aliases
                                    $ResolvedCommand = $global:AllCommands | ?{$_.Name -eq $e.Value -or $_.Definition -eq $e.Value}
                                    if($ResolvedCommand)
                                    {
                                        if($ResolvedCommand.CommandType -eq 'Alias')
                                        {
                                            $ResolvedCommand = Get-Command $ResolvedCommand.ResolvedCommandName
                                        }
                                        $ShortestAlias = $e.Value
                                        if(!$global:AllAliases)
                                        {
                                            $global:AllAliases = Get-Alias
                                        }
                                        $Aliases = $AllAliases | ?{$_.Definition -eq $ResolvedCommand.Name}
                                        if($Aliases)
                                        {
                                            $ShortestAlias = $Aliases | Select-Object -Expand Name | Sort-Object @{E ={$_.Length}} | Select-Object -First 1                                        
                                        }
                                        $ShortestAlias
                                    }
                                    else
                                    {
                                        $e.Value
                                    }
                                }
                                catch
                                {
                                    # Write-Warning "Unable to resolve $($e.GetType().name) $e"
                                    # throw $_
                                }                                
                            }
                        }
                        else
                        {
                            $e.Value
                        }
                    }
                    elseif ($e -is $ArrayLiteral)
                    {
                        @(foreach ($_ in $e.Elements)
                            {
                                Compress-Expression $_
                            }) -join ','
                    }
                    else
                    {
                        "$e"
                    }
                }

                $ExpandedExpressions = Expand-Expression $e
                $MinifiedExpression = $ExpandedExpressions -join ' '
                Write-Verbose "Line $($e.Extent.StartLineNumber)`tExpression`t: $($e.Extent.Text) -> $MinifiedExpression"
                $MinifiedExpression
            }
        }
    }

    process
    {
        if ($_ -is [Management.Automation.CommandInfo]) { $name = '' }
        # Now, call our minifier with this script block's AST
        $compressedScriptBlock = Compress-ScriptBlockAst $ScriptBlock.Ast

        $compressedScriptBlock = # After that, resassign $CompressedScriptBlock as needed
        if (-not $GZip)
        {
            $compressedScriptBlock
        }
        else
        {
            # If we're GZIPing,
            $data = [Text.Encoding]::Unicode.GetBytes($compressedScriptBlock) # compress the content
            $ms = [IO.MemoryStream]::new()
            $cs = [IO.Compression.GZipStream]::new($ms, [Io.Compression.CompressionMode]"Compress")
            $cs.Write($Data, 0, $Data.Length)
            $cs.Close()
            $cs.Dispose()

            if ($NoBlock)
            {
                # If we're using -NoBlocks, emit it as a single line
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

        if ($DotSource)
        {
            # If we're dot sourcing,

            $compressedScriptBlock = # reassign $compressedScriptBlock again
            if ($GZip)
            {
                ". $compressedScriptBlock" # if we're GZipping, fine (since the return value of this will be a script block)
            }
            else
            {
                ". {$compressedScriptBlock}" # otherwise, wrap it in {}s.
            }
        }

        $minified =
        if ($Name -and -not $Anonymous)
        {
            # If we've provided a -Name and don't want to be -Anonymous, we're assigning to a variable.
            if (-not $GZip -and -not $DotSource)
            {
                # If it's not GZipped or dotted,
                $compressedScriptBlock = "{$compressedScriptBlock}" # we need to wrap it in {}s.
            }
            if ($Name -match '\W')
            {
                # If the name contained non-word characters,
                "`${$name} = $compressedScriptBlock" # we need to wrap it in {}s.
            }
            else
            {
                "`$$name = $compressedScriptBlock" # otherwise, it's just $name = $compressedScriptBlock
            }
        }
        else
        {
            $compressedScriptBlock
        }

        if ($OutputPath)
        {
            # If we've been provided an -OutputPath
            # figure out what it might be
            $unresolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
            [IO.File]::WriteAllText("$unresolvedOutputPath", $minified) # and then write content to disk.
            if ($PassThru -and [IO.File]::Exists("$unresolvedOutputPath"))
            {
                [IO.FileInfo]"$unresolvedOutputPath"
            }
        }
        else
        {
            $minified # Otherwise, output the minified content.
        }
    }
}