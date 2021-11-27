function Remove-InvalidFileNameChars {
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String[]]$Name,

        [Parameter(Position=1)]
        [String]$Replacement=''
    )
    $arrInvalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $invalidChars = [RegEx]::Escape(-join $arrInvalidChars)

    [RegEx]::Replace($Name, "[$invalidChars]", $Replacement)
}

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
        [string]$components
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
    return $filelist
}