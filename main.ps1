param (
    [string][Parameter(Mandatory=$true)][alias('s')]$link,
    [switch][alias('orig','keep')]$original,
    [switch][alias('format')]$formatted,
    [string][alias('o')]$output = ".\output",
    [double][alias('c','cd')]$cooldown = 5
)
if (-not ($original_filenames -or $formatted_filenames)){
    $formatted_filenames = $true
}


$files = @(".\7za.exe", ".\7za.dll", ".\7zxa.dll")
foreach ($file in $files){
    if (-not (Test-Path $file)){
        throw "Could not find required 7zip files. Download from https://www.7-zip.org/a/7z1900-extra.7z and put them in the script's directory"
    }
}
if (-not (Test-Path $output)) {
    mkdir $output
}

function Format-Urls{
    param (
        [string][Parameter(Mandatory=$true)]$url
    )
    #if (!$url.StartsWith("http://") || !$url.StartsWith("https://")){
    #    $url = 'https://' + $url
    #}
    if (!$url.EndsWith("/")){
        $url = $url + "/"
    }
    return $url
}

function Get-Headers {
    headers = @{
        "X-Machine" = "iPod4,1"
        "X-Unique-ID" = "0000000000000000000000000000000000000000"
        "X-Firmware" = "6.1"
        "User-Agent" = "Telesphoreo APT-HTTP/1.0.999"
    }
    return $headers
}

Function Get-Repo {
    param (
        [string][Parameter(Mandatory=$true)]$url,
        [switch]$keep,
        [string]$output,
        [string]$cooldown
    )
    $url = Format-Urls -url $url
    $exts = @(".bz2", "", ".xz", ".gz", ".lzma")
    $compressed = @{
        status = $false
        format = ""
    }
    foreach ($ext in $exts){
        Write-Output "Attempting to download Packages$ext"
        ($url + "Packages" + $ext)
        $package = Invoke-WebRequest ($url + "Packages" + $ext)
        if ($package.StatusCode -ne 200) {
            Write-Output "Couldn't download Packages$ext"
            continue
        } else {
            Out-File "Packages$ext"
            Invoke-WebRequest ($url + "Packages" + $ext) -OutFile ("Packages" + $ext)
            if ($ext -ne "") {
                $compressed.status = $true
                $compressed.format = $ext
            }
            break
        }
    }
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
    Clear-Host
    for ($i = 1; $i -le $linksList.length; $i++) {
        $percentage = $i / $length * 100
        if (!$keep) {
            $filename = $namesList[$i] + "-" + $versList[$i] + ".deb"
            Write-Host "($i/$length) Downloading $filename" -ForegroundColor DarkCyan
            aria2c --continue --no-conf --async-dns=false --console-log-level=warn -j1 -x1 -s1 -o (Join-Path $output $filename) ($url + $linksList[$i]) 
        }
        else {
            Write-Output "($i/$length) Downloading $linksList[$i]"
            aria2c --continue --no-conf --async-dns=false --console-log-level=warn -j1 -x1 -s1 --dir $output ($url + $linksList[$i]) 
        }
        Start-Sleep -Seconds ([double]$cooldown)
    }
}

if ($original_filenames){
    Get-Repo -url $link -keep -output $output -cooldown $cooldown
} else {
    Get-Repo -url $link -output $output -cooldown $cooldown
}

