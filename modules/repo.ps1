function Get-PaymentEndpoint {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$url
    )
    Write-Verbose "Found authentication file, looking for payment endpoint..."
    $endpoint = (Invoke-WebRequest -UseBasicParsing ($url + 'payment_endpoint')).Content
    if ($endpoint -is "Byte[]") {
        $endpoint = [System.Text.Encoding]::UTF8.GetString($endpoint) -replace "`t|`n|`r",""
    }
    return $endpoint
}

function Get-DistUrl {
    param (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$url,

        [Parameter(Position=1, Mandatory=$false)]
        [string]$suites,

        [Parameter(Position=2, Mandatory=$false)]
        [string]$components
    )
    $url = Format-Url -url $url
    if ($PSBoundParameters.ContainsKey('suites') -and ![String]::IsNullOrWhiteSpace($suites)) {
        $disturl = Format-Url -url ($url + 'dists/' + $suites)
    }
    else {
        $disturl = $url
    }
    return $disturl
}

function Get-RepoPackageFile {
    param (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$url,

        [Parameter(Position=1, Mandatory=$false)]
        [string]$suites,

        [Parameter(Position=2, Mandatory=$false)]
        [string]$components,

        [boolean]$zstd
    )
    $url = Format-Url -url $url
    $disturl = Get-DistUrl -url $url -suites $suites

    $oldpp = $ProgressPreference
    $olderp = $ErrorActionPreference
    $ProgressPreference = "SilentlyContinue"
    $ErrorActionPreference = "SilentlyContinue"
    if ((Invoke-WebRequest -UseBasicParsing ($disturl + 'Release') -Method Head).StatusCode -eq 200) {
        Invoke-WebRequest -UseBasicParsing ($disturl + 'Release') -OutFile Release
    }
    else {
        throw ($disturl + " doesn't seem like a valid repo?!")
    }
    $ProgressPreference = $oldpp
    $ErrorActionPreference = $olderp

    $parse = $false
    $filelist = @()
    Get-Content Release | ForEach-Object {
        if ($_ -Match "(MD5Sum)|(SHA1)|(SHA256)|(SHA512)") {
            $parse = $true
        }
        if ($parse -and !($_.StartsWith(" "))) {
            $parse = $false
        } 
        if (!$parse -and $_.StartsWith(" ")) {
            $filelist += $_ -replace "^ ", "" 
        }
    }
    $filelist = $filelist | ForEach-Object {($_ -split '\s+' -ne "Release")[2]}
    $filelist = $filelist | Select-Object -Unique | Select-String -Pattern "Packages" -Raw
    if (!$zstd) {
        $filelist = $filelist | Select-String -Pattern "zst" -NotMatch -Raw
    }

    return $filelist
}

function Get-Repo($url, $suites, $components, $output = ".\output", $cooldown, $7z, $original = $false, $auth, $skipDownloaded = $true, $dlpackage) {
    $url = Format-Url -url $url
    $zstd = $null -ne (& $7z i | Select-String zstd)
    $output = Resolve-PathForced $output
    $specific_package = $PSBoundParameters.ContainsKey('dlpackage') -and ($dlpackage.Count -gt 0)
    if (![string]::IsNullOrWhiteSpace($auth) -and (Test-Path $auth)) {
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
            Write-Color "    Skipping all packages with tag cydia::commercial" -color Red
            $auth = ""
        }
    }

    $disturl = Get-DistUrl -url $url -suites $suites
    $pkgfs = Get-RepoPackageFile -url $url -suites $suites -zstd $zstd
    if ($null -eq $pkgfs) { # Fallback handling for repos that don't put where their Packages file is in Release
        $pkgfs = @("Packages.bz2", "Packages.gz", "Packages.lzma", "Packages.xz", "Packages")
        if ($zstd) {
            $pkgfs += "Packages.zst"
        }
    }
    $compressed = @{
        status = $false
        format = ""
    }
    $oldpp = $ProgressPreference
    $olderp = $ErrorActionPreference
    $ProgressPreference = "SilentlyContinue"
    $ErrorActionPreference = "SilentlyContinue"
    Remove-Item Packages
    Remove-Item Pacakges.*
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
    if (!(Test-Path Packages) -and !(Test-Path Packages.*)) {
        throw "Couldn't download the Packages file!"
        exit
    }

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

    if ($specific_package) {
        Write-Color "==> Starting downloads for specific packages" -color Blue
    }
    else {
        Write-Color "==> Starting downloads" -color Blue
    }
    $length = $linksList.length
    $mentioned_nondls = @()
    for ($i = 0; $i -lt $length; $i++) {
        if ($mentioned_nondls -contains $namesList[$i]) {
            continue
        }
        if ($specific_package -and !($dlpackage -contains $namesList[$i])) {
            Write-Verbose ("Skipping unspecified package " + $namesList[$i])
            $mentioned_nondls += $namesList[$i]
            continue
        }

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
            if ($skipDownloaded -and (Test-Path (Join-Path $output $namesList[$i] $filename))) {
                throw 'Pass -skipDownloaded:$false to prevent skipping downloaded packages.'
            }
            if ($tagsList[$i] -Match "cydia::commercial") {
                if (![string]::IsNullOrWhiteSpace($auth)) {
                    if ($purchased -contains $namesList[$i]) {
                        $authtable.version = $versList[$i]
                        $authtable.repo = $url
                        $dllink = (Invoke-RestMethod -Method Post -Body $authtable -Uri ($endpoint + 'package/' + $namesList[$i] + '/authorize_download')).url
                    }
                    else {
                        $mentioned_nondls += $namesList[$i]
                        throw "Skipping unpurchased package."
                    }
                }
                else {
                    $mentioned_nondls += $namesList[$i]
                    throw 'Paid package but no authentication found.'
                }
            }
            else {
                $dllink = ($url + $linksList[$i])
            }

            if (!(Test-Path (Join-Path $output $namesList[$i]))) {
                mkdir (Join-Path $output $namesList[$i]) > $null
            }
            Write-Verbose $dllink
            Write-Verbose (Join-Path $output $namesList[$i] $filename)
            dl $dllink (Join-Path $output $namesList[$i] $filename) "" $true $prepend
        }
        catch {
            Write-Color ("$prepend Download for $filename failed: {0}" -f $Error[0].Exception.Message) -color Red
            continue 
        } 
        Start-Sleep -Seconds ([double]$cooldown)
    }
}