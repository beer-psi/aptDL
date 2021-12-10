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
    $repo.url = Format-Url $repo.url
    if ($repo.ContainsKey('suites') -and ![string]::IsNullOrWhiteSpace($repo.suites) -and $repo.suites -ne "./") {
        $disturl = Format-Url -url ($repo.url + 'dists/' + $repo.suites)
    }
    else {
        $disturl = $repo.url
    }
    return $disturl
}

function ConvertFrom-DebControl {
    param (
        [Parameter(Position=0, Mandatory)]
        [string]$pkgfs
    )
    $pkgfs = Resolve-Path $pkgfs
    Write-Verbose "Processing $pkgfs"
    ConvertTo-Unix $pkgfs # Sanitize stuff, who knows, maybe some bozo is hosting their apt repo on Windows

    # pkgcontent: contains content of the processed file
    $pkgc = [System.Collections.ArrayList]@()

    # pkgfile: contains content of the input file, split by paragraphs
    $pkgf = [regex]::Split((Get-Content -Raw $pkgfs), '(\n){2,}', [Text.RegularExpressions.RegexOptions]::ExplicitCapture) | `
                Where-Object {$_} # Removes empty items
    $length = $pkgf.Length
    for ($i = 0; $i -lt $length; $i++) {
        $indice = $pkgc.Add([ordered]@{})
        $lastFieldName = ""
        $pkgp = $pkgf[$indice] -split '\n' #pkgparagraph
        for ($j = 0; $j -lt $pkgp.Length; $j++) {
            if ($pkgp[$j].StartsWith('#')) {continue}

            # The current line that we are processing, split by the colon character, so $pkgl[0] would be the key
            # and $pkgl[1] the value
            $pkgl = $pkgp[$j] -split ':\s?',2

            # If there is a newline
            if ($pkgp[$j] -match '^\s+') {
                $pkgc[$indice][$lastFieldName] += (($pkgp[$j] -replace '^\s+') + "`n")
            }
            else {
                $pkgc[$indice][$pkgl[0]] = $pkgl[1] -replace '^\s*'
                $lastFieldName = $pkgl[0]
            }
        }
    }
    return $pkgc
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
        Invoke-WebRequest -UseBasicParsing ($disturl + 'Release') -OutFile Release -ErrorAction SilentlyContinue -Headers (Get-Header)
    }
    catch {
        throw ($disturl + " doesn't seem like a valid repo?!")
    }

    $filelist = @()

    $rlsc = (ConvertFrom-DebControl Release)
    $checksums = @("MD5Sum", "SHA1", "SHA256", "SHA512")
    foreach ($checksum in $checksums) {
        if (!$rlsc.Contains($checksum)) {
            continue
        }
        # Split the content of the checksum string by line,
        # Then split it by one or multiple whitespace, and select the 2nd index (filename)
        # Filter repeat items, then select only the Packages file
        $filelist = $rlsc[$checksum] -split '\n' | `
            ForEach-Object {($_ -split '\s+' -ne "Release")[2]} | `
            Select-Object -Unique | `
            Select-String -Pattern "Packages" -Raw
        break
    }

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
    Remove-Item -Path Packages,Packages* -ErrorAction SilentlyContinue
    foreach ($pkgf in $filelist) {
        Write-Host "==> Attempting to download $pkgf" -foregroundcolor Blue
        try {
            $ext = [System.IO.Path]::GetExtension($pkgf)
            Invoke-WebRequest -UseBasicParsing ($disturl + $pkgf) -OutFile ("Packages" + $ext) -Headers (Get-Header) -MaximumRedirection 0
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
    Wrapper function for ConvertFrom-DebControl to get only keys
    required for downloading:
    - Package -> name
    - Version -> version
    - Filename -> link
    - Tag -> tag

    On success, an array of hashtable with the aforementioned keys
    is returned.
.PARAMETER pkgf
    Location of the Packages file
#>
function ConvertFrom-DebPackage {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$pkgf
   )
    $output = [System.Collections.ArrayList]@()
    ConvertFrom-DebControl $pkgf | ForEach-Object {
        [void]$output.Add(@{
            name = $_.Package
            version = $_.Version
            link = $_.Filename
            tag = $_.Tag
        })
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
    $repo.url = Format-Url $repo.url
    try {
        $endpoint = (Invoke-WebRequest -UseBasicParsing ($repo.url + 'payment_endpoint')).Content
        if ($endpoint -is "Byte[]") {
            $endpoint = [System.Text.Encoding]::UTF8.GetString($endpoint) -replace "`t|`n|`r",""
        }
    }
    catch {
        $endpoint = $null
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