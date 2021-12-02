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
        [hashtable]$repo
    )
    if ($repo.ContainsKey('suites') -and ![string]::IsNullOrWhiteSpace($repo.suites) -and $repo.suites -ne "./") {
        $disturl = Format-Url -url ($repo.url + 'dists/' + $repo.suites)
    }
    else {
        $disturl = $repo.url
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
function Get-DebRepoPackage {
    param (
        [Parameter(Position=0, Mandatory=$true)]
        [hashtable]$repo
    )
    $repo.url = Format-Url -url $repo.url
    $disturl = Get-DistUrl $repo
    $7z = Get-7zExec

    Remove-Item Release -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -UseBasicParsing ($disturl + 'Release') -OutFile Release -ErrorAction SilentlyContinue
    }
    catch {
        throw ($disturl + " doesn't seem like a valid repo?!")
    }

    $parse = $false
    $filelist = @()
    if ($repo.url -eq "http://apt.thebigboss.org/repofiles/cydia") { # Fucking BigBoss man
        $filelist += "main/binary-iphoneos-arm/Packages.bz2"
    }
    else {
        Get-Content Release | ForEach-Object {
            if ($_ -Match "(MD5Sum)|(SHA1)|(SHA256)|(SHA512)") {$parse = $true}
            if ($parse -and !($_.StartsWith(" "))) {$parse = $false}
            if (!$parse -and $_.StartsWith(" ")) {$filelist += $_ -replace "^ ", ""}
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
    }

    $output = @{
        compress = $false
        format = ""
    }
    Remove-Item -Path Packages,Packages* -ErrorAction SilentlyContinue
    foreach ($pkgf in $filelist) {
        Write-Host "==> Attempting to download $pkgf" -foregroundcolor Blue
        try {
            $ext = [System.IO.Path]::GetExtension($pkgf)
            Invoke-WebRequest -UseBasicParsing ($disturl + $pkgf) -OutFile ("Packages" + $ext) -Headers (Get-Header)
            if ($ext -ne "") {
                $output.compress = $true
                $output.format = $ext
            }
            break
        }
        catch {
            Write-Host " -> Couldn't download $pkgf" -foregroundcolor Red
            continue
        }
    }
    if (!(Test-Path Packages) -and !(Test-Path Packages.*)) {
        throw "Couldn't download the Packages file!"
    }
    if ($output.compress){
        & $7z.exec e ("Packages" + $output.format) -aoa
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
function ConvertFrom-DebPackage {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$pkgf
    )
    $count = 0
    $lastLineWasNotWhitespace = $true #Hacky hack to handle paragraphs that were separated by multiple newlines
    $output = @{
        namesList = [System.Collections.ArrayList]@()
        linksList = [System.Collections.ArrayList]@()
        versList = [System.Collections.ArrayList]@()
        tagsList = [System.Collections.ArrayList]@()
    }
    Get-Content $pkgf | ForEach-Object {
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
        [Hashtable]$repo
    )
    $endpoint = (Invoke-WebRequest -UseBasicParsing ($repo.url + 'payment_endpoint')).Content
    if ($endpoint -is "Byte[]") {
        $endpoint = [System.Text.Encoding]::UTF8.GetString($endpoint) -replace "`t|`n|`r",""
    }
    return $endpoint
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