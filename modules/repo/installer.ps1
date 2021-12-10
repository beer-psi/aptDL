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

        # This command will only be reached if iwr was successful, which means the repo has a Release file
        # so we can somewhat confidently state that this is not an installer one
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
    $output = [System.Collections.ArrayList]@()
    ([xml](Get-Content $pkgf) | ConvertFrom-Plist).packages | ForEach-Object {
        [void]$output.Add(@{
            name = $_.bundleIdentifier
            version = $_.version
            link = $_.location
        })
    }
    return $output
}