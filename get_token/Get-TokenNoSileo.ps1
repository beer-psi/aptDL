<#
.SYNOPSIS
    A helper script to get the authentication token for commercial repos.
.PARAMETER url
    The url of the repo to be authenticated with
.PARAMETER output
    Where to write the complete authentication.json
.PARAMETER udid
    Your device's UDID
.PARAMETER model
    Your device's identifier (e.g. iPhone10,5)
.PARAMETER cookies
    Location of dumped cookies.txt
.PARAMETER skip
    Skip warnings about further actions required
.PARAMETER curl
    Location of curl
.PARAMETER grep
    Location of grep
.NOTES
    Author: beerpsi/extradummythicc
    Portions of the code was taken from Scoop (https://github.com/ScoopInstaller/Scoop/)
#>
param (
    [Parameter(Position=0, Mandatory,
        HelpMessage="Repo to authenticate with")]
    [string]$url,

    [Parameter(Position=1, Mandatory,
        HelpMessage="UDID of the device")]
    [string]$udid,

    [Parameter(Position=2, Mandatory,
        HelpMessage="Device identifier (e.g: iPhone10,5)")]
    [string]$model,

    [Parameter(Position=3, Mandatory,
         HelpMessage="Location of dumped cookies.txt")]
    [string]$cookies,

    [Parameter(Position=4,
        HelpMessage="Where to write the authentication file (default ./authentication.json)")]
    [string]$output = "authentication.json",

    [switch]$skip,

    [string]$curl = (Get-Command curl).Source
)
. "$PSScriptRoot\..\modules\download.ps1"
. "$PSScriptRoot\..\modules\helper.ps1"
. "$PSScriptRoot\..\modules\repo\debian.ps1"

$url = Format-Url $url
$endpoint = (Get-PaymentEndpoint @{url = $url}).TrimEnd('/')
$cookies = Resolve-Path $cookies -ErrorAction Stop
$callback = ""

$weird_repos = @("https://repo.dynastic.co/")
if (!$skip -and ($weird_repos -contains $url)){
    Write-Warning "This repo needs further action. Refer to the wiki:`nhttps://github.com/extradummythicc/aptDL/wiki/Custom-workarounds-to-get-the-token-if-you-cannot-register-the-Sileo-URL-protocol`nTo avoid this warning, pass the flag -skip"
}

switch ($url) {
    "https://repo.chariz.com/" {
        $callback = curl -X POST -b $cookies -d "udid=$udid" -d "model=$model" "https://chariz.com/api/sileo/authenticate?udid=$udid&model=$model"
        break
    }
    default {
        $callback = & $curl -v -A (Get-Header)["User-Agent"] -b $cookies "$endpoint/authenticate?udid=$udid&model=$model" 2>&1
        break
    }
}
$callback = ($callback | Select-String -Pattern "(sileo:\/\/[a-zA-Z0-9.\/?=_%:|&;-]*)").Matches[0].Value
$sileoqs = Resolve-SileoQueryString $callback

$authentication = @{
    udid = $udid
    device = $model
    token = $sileoqs.token[0]
}
ConvertTo-Json $authentication | Out-File -Encoding utf8NoBOM (Resolve-PathForced $output)




