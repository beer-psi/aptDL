[cmdletbinding()]
param (
    [Parameter(Position=0, Mandatory=$true)]
    [alias('s')]
    [string]$url,

    [string]$suites,

    [string]$components,

    [alias('o')]
    [string]$output = ".\output",

    [alias('af')]
    [string]$auth,

    [alias('7zf', '7zc')]
    [string]$7zfile = (Get-Command 7z),

    [alias('c','cd')]
    [double]$cooldown = 5,

    [Parameter(ParameterSetName="original", Mandatory=$true)]
    [alias('orig','keep','co')]
    [switch]$original,

    [Parameter(ParameterSetName="formatted", Mandatory=$true)]
    [alias('format','cr')]
    [switch]$formatted
)
if (-not ($original -or $formatted)){
    $original = $false
}
elseif ($formatted -eq $true) {
    $original = $false
}

Import-Module $PSScriptRoot\modules\download
Import-Module $PSScriptRoot\modules\helper

$7z = (Get-Command 7z)
if ($null -eq $7z) {
    switch ($PSVersionTable.Platform) {
        "Win32NT" {
            $files = @("$PSScriptRoot\7za.exe", "$PSScriptRoot\7za.dll", "$PSScriptRoot\7zxa.dll")
            foreach ($file in $files){
                if (-not (Test-Path $file)){
                    throw "Could not find required 7zip files. Download from https://www.7-zip.org/a/7z1900-extra.7z and put them in the script's directory"
                    exit
                }
            }
            $7z = "$PSScriptRoot\7za.exe"
        }
        "Unix" {
           throw "7z is either not installed, or not available in PATH. Install it from your package manager.`nIf you know where the 7z executable is, use the -7zf flag to specify its location."
           exit
        }
    }
}

$output = Join-Path $PSScriptRoot $output
if (-not (Test-Path $output)) {
    mkdir $output
}
$url = Format-Url -url $url
if (![string]::IsNullOrWhiteSpace($auth)) {
    $endpoint = Get-PaymentEndpoint -url $url

    Write-Verbose "Writing authentication info to a hashtable..."
    $authtable = (Get-Content $auth | ConvertFrom-Json -AsHashtable)

    try {
        $userinfo = (Invoke-RestMethod -Method Post -Body $authtable -Uri ($endpoint + 'user_info'))
        $username = $userinfo.user.name
        $purchased = $userinfo.items
        Write-Color "==> Logged in as $username" -color Blue
        Write-Color "==> Purchased packages available for downloading:" -color Blue
        foreach ($i in $purchased) {
            Write-Output "      $i" 
        }
    }
    catch {
        $exc = $Error[0].Exception.Message
        Write-Color "==> Authentication failed for the following reason: $exc" -color Red
        Write-Color "    Skipping all packages with tag cydia::commercial"
        $auth = ""
    }
}

$disturl = Get-DistUrl -url $url -suites $suites
$pkgfs = Get-RepoPackageFile -url $url -suites $suites
$compressed = @{
    status = $false
    format = ""
}
$oldpp = $ProgressPreference
$olderp = $ErrorActionPreference
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
foreach ($pkgf in $pkgfs){
    Write-Color "==> Attempting to download $pkgf" -color Blue
    $package = Invoke-WebRequest -UseBasicParsing ($disturl + $pkgf) -Headers (Get-Header) -Method Head
    if ($package.StatusCode -ne 200) {
        Write-Color " -> Couldn't download $pkgf" -color Red
        continue
    } else {
        $ext = [System.IO.Path]::GetExtension($pkgf)
        Invoke-WebRequest -UseBasicParsing ($disturl + $pkgf) -OutFile ("Packages" + $ext) -Headers (Get-Header)
        if ($ext -ne "") {
            $compressed.status = $true
            $compressed.format = $ext
        }
        break
    }
}
$ProgressPreference = $oldpp
$ErrorActionPreference = $olderp

if ($compressed.status){
    & $7z e ("Packages" + $compressed.format) -aoa
}

Write-Color "==> Processing Packages file" -color Blue
$linksList = @()
$namesList = @()
$versList = @()
$tagsList = @()
Get-Content Packages | ForEach-Object {
    if ($_.StartsWith("Package: ")) {$namesList += $_ -replace '^Package: '; $tagsList += ""}
    if ($_.StartsWith("Version: ")) {$versList += $_ -replace '^Version: '}
    if ($_.StartsWith("Filename: ")) {$linksList += $_ -replace '^Filename: '}
}
$count = 0
$lastLineWasNotWhitespace = $true #Hacky hack to handle paragraphs that were separated by multiple newlines
Get-Content Packages | ForEach-Object {
    if(![string]::IsNullOrWhiteSpace($_) -and !$lastLineWasNotWhitespace) {$lastLineWasNotWhitespace = $true}
    if ($_.StartsWith("Tag: ")) {$tagsList[$count] = $_ -replace '^Tag: '}
    if ([string]::IsNullOrWhiteSpace($_) -and $lastLineWasNotWhitespace) {$count++; $lastLineWasNotWhitespace = $false}
}

Write-Color "==> Starting downloads" -color Blue
$length = $linksList.length
$mentioned_nonpurchases = @()
for ($i = 0; $i -lt $length; $i++) {
    $curr = $i + 1
    $prepend = "($curr/$length)"
    if ($original) {
        $filename = [System.IO.Path]::GetFileName($linksList[$i])           
    }
    else {
        $filename = $namesList[$i] + "-" + $versList[$i] + ".deb"
    }
    $filename = Remove-InvalidFileNameChars $filename -Replacement "_"

    try {
        if ($tagsList[$i] -Match "cydia::commercial") {
            if (![string]::IsNullOrWhiteSpace($auth)) {
                if ($purchased -contains $namesList[$i]) {
                    $authtable.version = $versList[$i]
                    $authtable.repo = $url
                    $dllink = (Invoke-RestMethod -Method Post -Body $authtable -Uri ($endpoint + 'package/' + $namesList[$i] + '/authorize_download')).url
                }
                else {
                    if ($mentioned_nonpurchases -contains $namesList[$i]) {
                        continue
                    }
                    $mentioned_nonpurchases += $namesList[$i]
                    throw "Skipping unpurchased package."
                }
            }
            else {
                throw 'Paid package but no authentication found.'
            }
        }
        else {
            Write-Verbose ($url + $linksList[$i])
            $dllink = ($url + $linksList[$i])
        }

        if (!(Test-Path (Join-Path $output $namesList[$i]))) {
            mkdir (Join-Path $output $namesList[$i]) > $null
        }
        dl $dllink (Join-Path $output $namesList[$i] $filename) "" $true $prepend
    }
    catch {
        $exc = $Error[0].Exception.Message
        Write-Color "$prepend Download for $filename failed: $exc" -color Red
    } 
    Start-Sleep -Seconds ([double]$cooldown)
}


