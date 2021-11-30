function Get-Header {
    $headers = @{
        "X-Machine" = "iPhone10,5"
        "X-Unique-ID" = "0000000000000000000000000000000000000000"
        "X-Firmware" = "14.8"
        "User-Agent" = "Telesphoreo APT-HTTP/1.0.999"
    }
    return $headers
}

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