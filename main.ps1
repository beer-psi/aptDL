param (
    [string][Parameter(Position=0)][alias('s')]$link,
    [string][alias('f')]$file,
    [switch][alias('orig','keep','co')]$original,
    [switch][alias('format','cr')]$formatted,
    [string][Parameter(Position=1)][alias('o')]$output = ".\output",
    [double][alias('c','cd')]$cooldown = 5
)
$original = $false

. "$PSScriptRoot/download.ps1"
$files = @(".\7za.exe", ".\7za.dll", ".\7zxa.dll")
foreach ($file in $files){
    if (-not (Test-Path $file)){
        throw "Could not find required 7zip files. Download from https://www.7-zip.org/a/7z1900-extra.7z and put them in the script's directory"
    }
}

function Get-Repo($url, $output, $cooldown, $keep = $false) {
    $output = Join-Path $PSScriptRoot $output
    if (-not (Test-Path $output)) {
        mkdir $output
    }
    $url = Format-Url -url $url

    $exts = @(".bz2", "", ".xz", ".gz", ".lzma")
    $compressed = @{
        status = $false
        format = ""
    }
    $old = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    foreach ($ext in $exts){
        Write-Color "==> Attempting to download Packages$ext" -color Blue
        $package = Invoke-WebRequest ($url + "Packages" + $ext) -Headers (Get-Header) -Method Head
        if ($package.StatusCode -ne 200) {
            Write-Color " -> Couldn't download Packages$ext" -color Red
            continue
        } else {
            Invoke-WebRequest ($url + "Packages" + $ext) -OutFile ("Packages" + $ext) -Headers (Get-Header)
            if ($ext -ne "") {
                $compressed.status = $true
                $compressed.format = $ext
            }
            break
        }
    }
    $ProgressPreference = $old
    if ($compressed.status){
        .\7za.exe e ("Packages" + $compressed.format) -aoa
    }

    $linksList = @()
    $namesList = @()
    $versList = @()
    Get-Content Packages | ForEach-Object {
        if ($_.StartsWith("Package: ")) {$namesList += $_ -replace '^Package: '}
        if ($_.StartsWith("Version: ")) {$versList += $_ -replace '^Version: '}
        if ($_.StartsWith("Filename: ")) {$linksList += $_ -replace '^Filename: '}
    }
    $length = $linksList.length
    for ($i = 0; $i -lt $length; $i++) {
        $curr = $i + 1
        $prepend = "($curr/$length)"
        if ($keep) {
            $filename = [System.IO.Path]::GetFileName($linksList[$i])           
        }
        else {
            $filename = $namesList[$i] + "-" + $versList[$i] + ".deb"
        }

        if (!(Test-Path (Join-Path $output $namesList[$i]))) {
            mkdir (Join-Path $output $namesList[$i]) > $null
        }

        try {
            dl ($url + $linksList[$i]) (Join-Path $output $namesList[$i] $filename) "" $true $prepend
        }
        catch {
            try { 
                $exc = (($Error[0].Exception | Select-String ":(?:.*):(.*)").Matches.groups[1].value | Select-String "^(.*?)[.?!]\s").Matches.groups[0].value
            }
            catch {
                $exc = $Error[0].Exception
            }
            Write-Color "$prepend Download for $filename failed:$exc" -color Red
        } 
        Start-Sleep -Seconds ([double]$cooldown)
    }
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
        [string][Parameter(Mandatory=$true)]$url
    )
    if (!($url.StartsWith("http://") -or $url.StartsWith("https://"))){
        $url = 'https://' + $url
    }
    if (!$url.EndsWith("/")){
        $url = $url + "/"
    }
    return $url
}

Get-Repo $link $output $cooldown $original

