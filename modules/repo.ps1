<#
.SYNOPSIS
    Function to get payment endpoint for repositories that supports the 
    Payment Providers API
.DESCRIPTION
    https://developer.getsileo.app/payment-providers
    Creates a GET request to repo's /payment_endpoint which either returns
    a string or a byte array. In the case we get a byte array, convert it
    to a string before returning.

    This function returns the endpoint URL on success, and throws an 
    exception on failure.
.PARAMETER url
    The URL of the repo to get the payment endpoint from.
#>
function Get-PaymentEndpoint {
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]$url
    )
    $endpoint = (Invoke-WebRequest -UseBasicParsing ($url + 'payment_endpoint')).Content
    if ($endpoint -is "Byte[]") {
        $endpoint = [System.Text.Encoding]::UTF8.GetString($endpoint) -replace "`t|`n|`r",""
    }
    return $endpoint
}

<#
.SYNOPSIS
    Function to get dist repo's URL from url and suites
.DESCRIPTION
    If the -suites parameter is not specified, simply return the
    given URL. If it is specified, but "./", also return the given URL.
    If $suites doesn't match any of the above (actual dist repo), return 
    $url + 'dists/' + $suites
.PARAMETER url
    The URL of the repo
.PARAMETER suites
    The repo's suites
.PARAMETER components
    The repo's components (main, nonfree, etc.)
    Not used in this function.
#>
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
    if ($PSBoundParameters.ContainsKey('suites') -and ![string]::IsNullOrWhiteSpace($suites) -and $suites -ne "./") {
        $disturl = Format-Url -url ($url + 'dists/' + $suites)
    }
    else {
        $disturl = $url
    }
    return $disturl
}


<#
.SYNOPSIS
    Downloads a repo's "Packages" file, and extract if it is compressed.
.DESCRIPTION
    First, do a GET request for the repo's Release file (which sometimes
    inclue hashes and location of the Packages file that contains
    information for all packages). If hashes and locations are not
    available, fallback to a hardcoded set of locations.

    Each item from this list of locations is downloaded one-by-one until
    a file succeeds in downloading. The file is then extracted in the script's
    directory.

    This function doesn't return anything.
.PARAMETER url
    The URL of the repo
.PARAMETER suites
    The repo's suites
.PARAMETER components
    The repo's components (main, nonfree, etc.)
    Not used in this function.
#>
function Get-RepoPackageFile {
    param (
        [Parameter(Position=0, Mandatory=$true)]
        [string]$url,

        [Parameter(Position=1, Mandatory=$false)]
        [string]$suites,

        [Parameter(Position=2, Mandatory=$false)]
        [string]$components
    )
    $url = Format-Url -url $url
    $disturl = Get-DistUrl -url $url -suites $suites
    $7z = Get-7zExec

    $oldpp = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    Remove-Item Release -ErrorAction SilentlyContinue
    if ((Invoke-WebRequest -UseBasicParsing ($disturl + 'Release') -Method Head -ErrorAction SilentlyContinue).StatusCode -eq 200) {
        Invoke-WebRequest -UseBasicParsing ($disturl + 'Release') -OutFile Release -ErrorAction SilentlyContinue
    }
    else {
        throw ($disturl + " doesn't seem like a valid repo?!")
    }
    $ProgressPreference = $oldpp

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
    if (!$7z.zstd) {
        $filelist = $filelist | Select-String -Pattern "zst" -NotMatch -Raw
    }

    if ($null -eq $filelist) {
        $filelist = @("Packages.bz2", "Packages.gz", "Packages.lzma", "Packages.xz", "Packages")
        if ($7z.zstd) {
            $filelist += "Packages.zst"
        }
    }

    $output = @{
        compress = $false
        format = ""
    }
    $oldpp = $ProgressPreference
    $olderp = $ErrorActionPreference
    $ProgressPreference = "SilentlyContinue"
    $ErrorActionPreference = "SilentlyContinue"
    Remove-Item -Path Packages,Packages* -ErrorAction SilentlyContinue
    foreach ($pkgf in $filelist) {
        Write-Host "==> Attempting to download $pkgf" -foregroundcolor Blue
        if ((Invoke-WebRequest -UseBasicParsing ($disturl + $pkgf) -Headers (Get-Header) -Method Head).StatusCode -ne 200) {
            Write-Host " -> Couldn't download $pkgf" -foregroundcolor Red
            continue
        } else {
            $ext = [System.IO.Path]::GetExtension($pkgf)
            Invoke-WebRequest -UseBasicParsing ($disturl + $pkgf) -OutFile ("Packages" + $ext) -Headers (Get-Header)
            if ($ext -ne "") {
                $output.compress = $true
                $output.format = $ext
            }
            break
        }
    }
    $ProgressPreference = $oldpp
    $ErrorActionPreference = $olderp
    if (!(Test-Path Packages) -and !(Test-Path Packages.*)) {
        throw "Couldn't download the Packages file!"
    }
    if ($output.compress){
        & $7z.exec e ("Packages" + $output.format) -aoa
    }
}

function Get-AuthenticationData {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$endpoint,

        [Parameter(Mandatory, Position=1)]
        [string]$auth
    )
    if ([string]::IsNullOrWhiteSpace($auth) -or !(Test-Path $auth)) {
        Write-Verbose "No authentication data provided!"
        return @{
            authstatus = $false
            authtable = $null
            purchased = $null
        }
    }

    Write-Verbose "Writing authentication info to a hashtable..."
    $authtable = (Get-Content $auth | ConvertFrom-Json -AsHashtable)
    
    try {
        $userinfo = (Invoke-RestMethod -Method Post -Body $authtable -Uri ($endpoint + 'user_info'))
        $username = $userinfo.user.name
        $purchased = $userinfo.items
        Write-Host "==> Logged in as $username" -ForegroundColor Blue
        Write-Host "==> Purchased packages available for downloading:" -ForegroundColor Blue
        foreach ($i in $purchased) {
            Write-Host "      $i" 
        }
        $authstatus = $true
    }
    catch {
        $exc = $Error[0].Exception.Message
        Write-Error "==> Authentication failed for the following reason: $exc" 
        Write-Error "    Skipping all packages with tag cydia::commercial"
        $authstatus = $false
    }
    return @{
        authstatus = $authstatus
        authtable = $authtable
        purchased = $purchased
    }
}

<#
.SYNOPSIS
    Import data from a Debian's repo Packages file into ArrayLists
.DESCRIPTION
    Read through the uncompressed Packages file line-by-line and put 
    information in their respective arrays:
    - namesList contains package names
    - versList contains these packages' versions
    - linksList contains these packages' locations within the repo
    - tagsList contains these packages' tags

    On success, a hashtable containing the arrays is returned.
.PARAMETER pkgf
    Location of the Packages file
#>
function ConvertFrom-DebPackages {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$pkgf
    )
    Write-Color "==> Processing Packages file" -color Blue
    $count = 0
    $lastLineWasNotWhitespace = $true #Hacky hack to handle paragraphs that were separated by multiple newlines
    $output = @{
        namesList = [System.Collections.ArrayList]@()
        linksList = [System.Collections.ArrayList]@()
        versList = [System.Collections.ArrayList]@()
        tagsList = [System.Collections.ArrayList]@()
    }
    Get-Content Packages | ForEach-Object {
        if (![string]::IsNullOrWhiteSpace($_) -and !$lastLineWasNotWhitespace) {$lastLineWasNotWhitespace = $true}
        if ([string]::IsNullOrWhiteSpace($_) -and $lastLineWasNotWhitespace) {$count++; $lastLineWasNotWhitespace = $false}
        if ($_.StartsWith("Package: ")) {$output.namesList.Add($_ -replace '^Package: '); $output.tagsList.Add("")}
        if ($_.StartsWith("Version: ")) {$output.versList.Add($_ -replace '^Version: ')}
        if ($_.StartsWith("Filename: ")) {$output.linksList.Add($_ -replace '^Filename: ')}
        if ($_.StartsWith("Tag: ")) {$output.tagsList[$count] = $_ -replace '^Tag: '}
    }
    return $output
}

<#
.SYNOPSIS
    Download an entire Debian repository, or parts of it.
.PARAMETER repo
    A hashtable with 3 keys: url, suites and parameters.
    If downloading a flat repo, suites and parameters can be null/empty.
.PARAMETER output
    Folder to save the downloaded repo, can be absolute or relative paths.
.PARAMETER cooldown
    Time to wait between each request to the repo, avoiding rate limits.
.PARAMETER original
    Save files as their original name instead of renaming to 
    PACKAGENAME-VERSION.deb
.PARAMETER skipDownloaded
    Skip files that already exists in $output.
.PARAMETER dlpackage
    Download packages only from this list; all others are ignored.
#>
function Get-Repo($repo, $output = ".\output", $cooldown, $original = $false, $auth, $skipDownloaded = $true, $dlpackage) {
    $repo.url = Format-Url $repo.url

    $output = Resolve-PathForced $output
    $specific_package = $PSBoundParameters.ContainsKey('dlpackage') -and ($dlpackage.Count -gt 0)
    
    if ((![string]::IsNullOrWhiteSpace($auth)) -and (Test-Path $auth)) {
        $repo.endpoint = Get-PaymentEndpoint $repo.url
        $authinfo = Get-AuthenticationData $repo.endpoint $auth
    }
    

    try {
        Get-RepoPackageFile -url $repo.url -suites $repo.suites      
    }
    catch {
        $exc = $Error[0].Exception.Message
        Write-Error $exc
        exit
    }
    
    Write-Host "==> Starting downloads" -ForegroundColor Blue
    $pkgc = ConvertFrom-DebPackages Packages
    $length = $pkgc.linksList.length
    $mentioned_nondls = [System.Collections.ArrayList]@()
    for ($i = 0; $i -lt $length; $i++) {
        $curr = $i + 1
        $prepend = "($curr/$length)"
        $requestmade = $false

        if ($mentioned_nondls.Contains($pkgc.namesList[$i])) {
            continue
        }
        if ($specific_package -and !($dlpackage -contains $pkgc.namesList[$i])) {
            Write-Verbose ("Skipping unspecified package " + $pkgc.namesList[$i])
            [void]$mentioned_nondls.Add($pkgc.namesList[$i])
            continue
        }

        if ($original) {
            $filename = [System.IO.Path]::GetFileName($pkgc.linksList[$i])           
        }
        else {
            $filename = $pkgc.namesList[$i] + "-" + $pkgc.versList[$i] + ".deb"
        }
        $filename = Remove-InvalidFileNameChars $filename -Replacement "_"
        $destination = Join-Path $output $pkgc.namesList[$i] $filename

        if ($skipDownloaded -and (Test-Path $destination)) {
            Write-Verbose ("Skipping downloaded package {0}" -f $filename)
            continue
        }

        try {
            if ($pkgc.tagsList[$i] -Match "cydia::commercial") {
                if ($authinfo.authstatus) {
                    if ($authinfo.purchased -contains $pkgc.namesList[$i]) {
                        $authinfo.authtable.version = $pkgc.versList[$i]
                        $authinfo.authtable.repo = $repo.url
                        $dllink = (Invoke-RestMethod -Method Post -Body $authinfo.authtable -Uri ($repo.endpoint + 'package/' + $namesList[$i] + '/authorize_download')).url
                        $requestmade = $true
                    }
                    else {
                        [void]$mentioned_nondls.Add($pkgc.namesList[$i])
                        throw "Skipping unpurchased package."
                    }
                }
                else {
                    [void]$mentioned_nondls.Add($pkgc.namesList[$i])
                    throw 'Paid package but no authentication found.'
                }
            }
            else {
                $dllink = ($repo.url + $pkgc.linksList[$i])
            }

            if (!(Test-Path (Join-Path $output $pkgc.namesList[$i]))) {
                mkdir (Join-Path $output $pkgc.namesList[$i]) > $null
            }
            Write-Verbose "Download link: $dllink"
            Write-Verbose ("Saving to: {0}" -f $destination)
            dl $dllink $destination "" $true $prepend
        }
        catch {
            Write-Color ("$prepend Download for $filename failed: {0}" -f $Error[0].Exception.Message) -color Red
            if (!$requestmade) {continue}
        } 
        Start-Sleep -Seconds ([double]$cooldown)
    }
}