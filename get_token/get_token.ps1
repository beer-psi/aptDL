#!/usr/bin/env pwsh
param (
    [Parameter(Mandatory=$false, Position=0)]
    [string]$url
)
Add-Type -AssemblyName System.Web

Function Get-PSScriptPath {
    if ([System.IO.Path]::GetExtension($PSCommandPath) -eq '.ps1') {
        $psScriptPath = $PSCommandPath
    } else {
    # This enables the script to be compiles and get the directory of it.
        $psScriptPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    return (Split-Path -Path $psScriptPath)
}
$PSScriptPath = Get-PSScriptPath
. "$PSScriptPath\..\modules\helper.ps1"
. "$PSScriptPath\..\modules\repo\debian.ps1"

if ($PSBoundParameters.ContainsKey('url')) {
    $output = Resolve-SileoQueryString $url

    Write-Output (ConvertTo-Json $output)

    $authentication = @{}
    (Get-Content $PSScriptPath\..\authentication.json | ConvertFrom-Json).psobject.properties | ForEach-Object { $authentication[$_.Name] = $_.Value }
    $authentication.token = $output.token
    ConvertTo-Json $authentication | Out-File -Encoding UTF8 $PSScriptPath\..\authentication.json

    [Console]::ReadKey() > $null
}
else {
    $repo = Read-Host "Repo to download"
    $udid = Read-Host "Your device's UDID (use idevice_id from libimobiledevice to get)"
    $device_id = Read-Host "Your device identifier (example: iPhone10,5)"

    $authentication = @{
        udid = $udid
        device = $device_id
    }

    ConvertTo-Json $authentication | Out-File -Encoding UTF8 $PSScriptPath\..\authentication.json

    $endpoint = Get-PaymentEndpoint -url (Format-Url -url $repo)
    Start-Process ($endpoint + "authenticate?udid=$udid&model=$device_id")
}