<#
.SYNOPSIS
    aptDL - a tool to download apt (mostly Cydia) repos
.DESCRIPTION
    Downloads sources and/or dist repos for archival purposes.
.PARAMETER inputfile
    Pass parameters from an input file, instead of from the command line.
    Check inputfile.psd1 for more in-depth guidance.
    If a file is specified, all other parameters passed through the command
    line will be ignored, except -7z
.PARAMETER url
    The url of the repo to be downloaded
.PARAMETER suites
    (For dist repos only) The suite to download from.
    If unsure, check with /etc/apt/sources.list.d on your jailbroken iDevice.
.PARAMETER components
    Dist repo component.
.PARAMETER output
    Folder to save the downloaded repo, relative to the root of the script.
    Default value: ".\output"
.PARAMETER cooldown
    Seconds of cooldown between each download, intended to avoid rate limitng
    by repos.
    Default value: 5
.PARAMETER original
    Don't rename downloaded files to PACKAGENAME-VERSION.deb, keep them as-is.
.PARAMETER formatted
    Rename downloaded files to PACKAGENAME-VERSION.deb (default behavior)
.PARAMETER auth
    Pass an authentication file to the script to enable downloading of purchased
    packages. Read README.md for how to generate this authentication file.
.PARAMETER dlpackage
    Packages to download specifically. Separate multiple packages with a comma.
    Any package not in this list will be removed.
.EXAMPLE
    .\main.ps1 -url https://apt.procurs.us `
               -suites iphoneos-arm64/1700 `
               -output repo\procursus `
               -cooldown 3 `
               -dlpackage 2048,adv-cmds `
               -original
    Downloads the packages 2048 and adv-cmds from dist repo https://apt.procurs.us (suite iphoneos-arm64/1700)
    Between the downloads, there is a 3-second cooldown, and the files are saved in $PSScriptRoot\repo\procursus with their original names
.NOTES
    Author: beerpsi/extradummythicc
    Portions of the code was taken from Scoop (https://github.com/ScoopInstaller/Scoop/)
#>
#requires -version 5
[cmdletbinding()]
param (
    [Parameter(ParameterSetName="help", Mandatory)]
    [alias('h')]
    [switch]$help,

    [Parameter(Position=0, ParameterSetName="input", Mandatory)]
    [alias('i', 'input')]
    [string]$inputfile,

    [Parameter(Position=0, ParameterSetName="url", Mandatory)]
    [alias('s')]
    [string]$url,

    [Parameter(Position=1, ParameterSetName="url")]
    [string]$suites,

    [Parameter(Position=2, ParameterSetName="url")]
    [string]$components,

    [Parameter(ParameterSetName="url")]
    [alias('o')]
    [string]$output = ".\output",

    [Parameter(ParameterSetName="url")]
    [alias('af')]
    [string]$auth,

    [Parameter(ParameterSetName="url")]
    [alias('p')]
    [string[]]$dlpackage,

    [Parameter(ParameterSetName="url")]
    [alias('c','cd')]
    [double]$cooldown = 5,

    [Parameter(ParameterSetName="url")]
    [alias('orig','keep','co')]
    [switch]$original,

    [Parameter(ParameterSetName="url")]
    [alias('format','cr')]
    [switch]$formatted,

    [Parameter(ParameterSetName="url")]
    [alias('skip', 'sd')]
    [switch]$skipDownloaded
)
if ($help -or ($null -eq $PSBoundParameters.Keys)) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    break
}

. "$PSScriptRoot\modules\download.ps1"
. "$PSScriptRoot\modules\helper.ps1"
. "$PSScriptRoot\modules\plist.ps1"
. "$PSScriptRoot\modules\repo\debian.ps1"
. "$PSScriptRoot\modules\repo\installer.ps1"
. "$PSScriptRoot\modules\repo\repo.ps1"

if ($PSBoundParameters.ContainsKey('formatted')) {
    $original = !$formatted
}
elseif ($PSBoundParameters.ContainsKey('original')) {

}
else {
    $original = $false
}

$oldpp = $ProgressPreference
$ProgressPreference = "SilentlyContinue"

if ($PSBoundParameters.ContainsKey('inputfile')) {
    Write-Color "==> Reading input file" -color Blue
    $tasks = Format-InputData (Import-PowerShellDataFile $inputfile)
    foreach ($task in $tasks.All) {
        Write-Color ("==> " + $task.repo.url) -color Green
        try {
            Get-Repo $task.repo $task.output $task.cooldown $task.original $task.auth $task.skipDownloaded $task.dlpackage
        }
        catch {
            Write-Error ("==> Unhandled exception: {0}" -f $Error[0].Exception.Message)
            continue
        }
    }
}
else {
    $repo = @{
        url = $url
        suites = $suites
        components = $components
    }
    try {
        Get-Repo $repo $output $cooldown $original $auth $skipDownloaded $dlpackage
    }
    catch {
        Write-Error ("==> Unhandled exception: {0}" -f $Error[0].Exception.Message)
    }
}

$ProgressPreference = $oldpp