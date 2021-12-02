function Test-InstallerRepo {
    param (
        [Parameter(Position=0, Mandatory)]
        [Hashtable]$repo
    )
    $repo.url = Format-Url $repo.url
    if ($repo.ContainsKey('suites') -and ![string]::IsNullOrWhiteSpace($repo.suites)) {
        return $false
    }

    try {
        Invoke-WebRequest ($repo.url + 'Release') -Headers (Get-Header) -ErrorAction SilentlyContinue > $null
        return $false
    }
    catch {
        return $true
    }
}

function Get-InstallerRepoPackage {
    param (
        [Parameter(Position=0, Mandatory)]
        [hashtable]$repo
    )
    Invoke-WebRequest $repo.url -OutFile Packages
}

function ConvertFrom-InstallerPackage {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$pkgf
    )
    $pkgxml = [xml](Get-Content $pkgf) | ConvertFrom-Plist
    return @{
        namesList = $pkgxml.packages.bundleIdentifier
        linksList = $pkgxml.packages.location
        versList = $pkgxml.packages.version
    }
}