function Rename-InvalidFileNameChar {
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [String[]]$Name,

        [Parameter(Position=1)]
        [String]$Replacement=''
    )
    $arrInvalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $invalidChars = [RegEx]::Escape(-join $arrInvalidChars)

    [RegEx]::Replace($Name, "[$invalidChars]", $Replacement)
}

function Resolve-PathForced {
    param (
        [Parameter(Position=0, Mandatory)]
        [string]$FileName
    )

    $FileName = Resolve-Path $FileName -ErrorAction SilentlyContinue `
                                       -ErrorVariable _frperror
    if (-not($FileName)) {
        $FileName = $_frperror[0].TargetObject
    }

    return $FileName
}

function Resolve-SileoQueryString {
    param (
        [Parameter(Position=0, Mandatory)]
        [string]$url
    )
    $iqs = $url.IndexOf("?")
    if ($iqs -lt $url.Length - 1) {
        $querystring = $url.Substring($iqs + 1)
    }
    else {
        $querystring = ""
    }
    $query = [System.Web.HttpUtility]::ParseQueryString($querystring)
    $output = @{
        token = $query.GetValues("token")
        payment_secret = $query.GetValues("payment_secret")
    }
    return $output
}

function Write-Color {
    param (
        [string][Parameter(Mandatory=$true, Position=0)]$str,
        [string][Parameter(Mandatory=$true, Position=1)]$color
    )
    $t = $host.ui.RawUI.ForegroundColor
    if ($color -in [enum]::GetValues([System.ConsoleColor])) {
        $host.ui.RawUI.ForegroundColor = $color
    }
    else {
        throw 'Invalid color.'
    }
    Write-Output $str
    $host.ui.RawUI.ForegroundColor = $t
}

function Format-Url {
    param (
        [string][Parameter(Mandatory=$true, Position=0)]$url
    )
    if (!($url.StartsWith("http://") -or $url.StartsWith("https://"))){
        $url = 'https://' + $url
    }
    if (!$url.EndsWith("/")){
        $url = $url + "/"
    }
    return $url
}

function Format-InputData {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Hashtable]$inputfile
    )
    $outputs = $inputfile
    $globalValues = @("cooldown", "original", "output", "skipDownloaded")
    foreach ($globalValue in $globalValues) {
        if ($outputs.ContainsKey($globalValue)) {
            foreach ($output in $outputs.All) {
                if ($output.ContainsKey($globalValue)) {
                    continue
                }
                else {
                    $output[$globalValue] = $outputs[$globalValue]
                }
            }
        }
    }
    return $outputs
}

function Get-7zExec {
    $7z = (Get-Command 7z -ErrorAction SilentlyContinue).Source
    if ($null -eq $7z) {
        switch ($PSVersionTable.Platform) {
            "Win32NT" {
                $files = @("$PSScriptRoot\..\7za.exe", "$PSScriptRoot\..\7za.dll", "$PSScriptRoot\..\7zxa.dll")
                foreach ($file in $files){
                    if (-not (Test-Path $file)){
                        throw "Could not find required 7zip files. Download from https://www.7-zip.org/a/7z1900-extra.7z and put them in the script's directory`nIf you already have 7zip installed, add it to your PATH."
                        exit
                    }
                }
                $7z = (Resolve-Path "$PSScriptRoot\..\7za.exe")
            }
            "Unix" {
               throw "7z is either not installed, or not available in PATH. Install it from your package manager, or add it to your PATH."
               exit
            }
        }
    }
    return @{
        exec = $7z
        zstd = $null -ne (& $7z i | Select-String zstd)
    }
}

function ConvertTo-Unix ($path) {
    $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
    $x = [System.IO.File]::ReadAllText($path)
    $content = $x -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBomEncoding)
}