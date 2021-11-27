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