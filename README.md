
PSMinifier [1.1.3]
================
A Miniature Minifier For PowerShell

----------------


### Using the PSMinifier GitHub Action:


The PSMinifier action is easy to use.  By default, it will minify all .ps1 files not named *.*.ps1 within your GitHub Workspace.

~~~Yaml
- name: PSMinifier
  uses: StartAutomating/PSMinifier@v1.1.3
~~~

This will generate a .min.ps1 for every PowerShell in your workspace.

#### Commiting Minified Code


If you would like to check in the minified code, simply provide a commit message

~~~yaml
- name: PSMinifier
  uses: StartAutomating/PSMinifier@v1.1.3
  with:
    CommitMessage: "Minifying $($_.Name)"
~~~


#### Including and Excluding Paths

The parameters of the GitHub action largely map to the parameters of Compress-ScriptBlock, with a couple of notable exceptions:
* Include
* Exclude
~~~yaml
- name: PSMinifier
  uses: StartAutomating/PSMinifier@v1.1
  with:
    Include: "*.ps1"
    Exclude: "*.tests.ps1"
    CommitMessage: "Minifying $($_.Name)"
~~~

#### GZipping Minified Code

For even more space savings and obfuscation, you can GZip minified code:
~~~yaml
- name: PSMinifier
  uses: StartAutomating/PSMinifier@v1.1
  with:
    CommitMessage: "Minifying and GZipping $($_.Name)"
    GZip: true
~~~


### PSMinifier Action Output

The PSMinifier action includes some output parameters, such as:
* MinifiedPercent
* MinifiedSize
* OriginalSize

~~~yaml
- name: Use PSMinifier Action
  uses: StartAutomating/PSMinifier@v1.1
  id: Minify
  with: 
    CommitMessage: Minifying $($_.Name)
- name: OutputMinifier
  run: |    
    echo Original Size ${{ steps.Minify.outputs.OriginalSize }} 
    echo Minified Size ${{ steps.Minify.outputs.MinifiedSize }} 
    echo Minified Percent ${{ steps.Minify.outputs.MinifiedPercent }}
~~~



----------------
### Module Commands
-----------------------
|    Verb|Noun        |
|-------:|:-----------|
|Compress|-ScriptBlock|
-----------------------
---
PSMinifier is a minature minifier for PowerShell.

Minification makes your scripts smaller and much harder to read.  Thus it is helpful when trying to reduce filesize, and not 
helpful when trying to make readable code.

PSMinifier can minify itself with:
    
~~~
# This returns the minified contents of the definition of Compress-ScriptBlock
Compress-ScriptBlock -ScriptBlock (Get-Command Compress-ScriptBlock).ScriptBlock
~~~

Or more elegantly, with:

~~~
# This returns the minified contents of Compress-ScriptBlock, assigned to a variable ${Compressed-ScriptBlock}
Get-Command Compress-ScriptBlock | Compress-ScriptBlock
~~~


If that isn't compact or opaque enough, you can also -GZip the contents of a ScriptBlock

~~~
Get-Command Compress-ScriptBlock | Compress-ScriptBlock -GZip
~~~

If that isn't minified enough, you can pass both -GZip and -NoBlock to recreate the script block in one long line.
~~~
Get-Command Compress-ScriptBlock | Compress-ScriptBlock -GZip -NoBlock
~~~


Both of the preceeding examples minified a function into an anonymous Script Block.  This can be useful for embedding single 
commands.
You can also minify a .ps1 file to include directly within a module.
~~~
Get-Command Compress-ScriptBlock | # Get Compress-ScriptBlock
    Foreach-Object {$_.ScriptBlock.File }| # Get the file it is declared in
    Get-Command | # get the command (if you were in the directory, this would be Get-Command .\Compress-ScriptBlock.ps1)
    Compress-ScriptBlock -Anonymous # compress the script, but don't assign it to a variable.
~~~


If you want to GZip a ScriptBlock and declare the functions within it, you have to pass -DotSource:

~~~
Get-Command Compress-ScriptBlock | # Get Compress-ScriptBlock
    Foreach-Object {$_.ScriptBlock.File }| # Get the file it is declared in
    Get-Command | # get the command 
    Compress-ScriptBlock -Anonymous -GZip -DotSource # compress and dot-source the script.
~~~


PSMinifier works by walking the PowerShell Abstract Syntax Tree and recreating a minimal version of your script.  As such, any 
inline help will be lost.
PSMinifier will not minify strings, as to do so would change functionality.

Importantly, _PSMinifier is not an optimizer_.  It does not change the content of your scripts, attempt to improve their 
performance, or rename your variables.

If PSMinifier fails to minify your script, please open an issue on GitHub.
