# aptDL
A PowerShell Core script to download Cydia repos.

~~Dist repos are also not supported for now.~~ Dist repos are now working! (mostly)

# Usage
```
❯ Get-Help ./main.ps1
NAME
    E:\Documents\git\aptDL\main.ps1
SYNOPSIS
    aptDL - a tool to download apt (mostly Cydia) repos
SYNTAX
    E:\Documents\git\aptDL\main.ps1 -help [<CommonParameters>]

    E:\Documents\git\aptDL\main.ps1 [-inputfile] <String> [<CommonParameters>]

    E:\Documents\git\aptDL\main.ps1 [-url] <String> [[-suites] <String>] [[-components] <String>] [-output <String>] [-auth <String>] [-dlpackage
    <String[]>] [-cooldown <Double>] [-original] [-formatted] [-skipDownloaded] [<CommonParameters>]
DESCRIPTION
    Downloads sources and/or dist repos for archival purposes.
REMARKS
    To see the examples, type: "Get-Help E:\Documents\git\aptDL\main.ps1 -Examples"
    For more information, type: "Get-Help E:\Documents\git\aptDL\main.ps1 -Detailed"
    For technical information, type: "Get-Help E:\Documents\git\aptDL\main.ps1 -Full"

```

# Paid packages
## Payment Providers API
Edit authentication.json with your own details, then invoke the script with `-auth .\authentication.json`. If you have passed the right token but the repo isn't authorizing downloads, you may need to also [change the headers.](#old-repos-without-the-api-bigboss-etc)

<details>
  <summary>Example authentication.json</summary>

  ```json
  {
      "token": "f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2",
      "udid": "4e1243bd22c66e76c2ba9eddc1f91394e57f9f83",
      "device": "iPhone7,2"
  }
  ```
</details>

You can name `authentication.json` whatever you like, as long as it is a valid JSON with the token, udid and device (like the example above.)
### Building authentication.json
<details>
  <summary>Method 1: Capture the callback URL (works on any repo with the Payment Providers API implemented)</summary>

  Register the sileo:// protocol and point it to `get_token.exe` (Windows) or `get_token.ps1` (Linux).
  - [Registering a URL protocol on Windows](https://stackoverflow.com/questions/80650/how-do-i-register-a-custom-url-protocol-in-windows)
  - [Registering a URL protocol on Linux](https://unix.stackexchange.com/questions/497146/create-a-custom-url-protocol-handler)
  - I've never really used macOS so I don't know how to register a URL protocol there /shrug

  Then, run the `get_token.ps1` script and fill in the information. After that, a browser window will open, allowing you to login with your repo. After you've linked your "device" with the repo, a console app will appear showing your token. Verify that the token showed matches the one in `authentication.json`.

  Once you've finished, just call the download script with `-auth authentication.json`. Reminder that each authentication will only work with one repo.
</details>

<details>
  <summary>Method 2: Helper script (if you can't register sileo:// for method 1)</summary>

  - Use the extension cookies.txt to dump cookies of the repo's website
  - Run `get_token/Get-TokenNoSileo.ps1` and fill in the required information. You can change where it saves the json with the flag `-output <LOCATION>`.

  Tested to work on Chariz, Packix and Twickd by default. Other repos may need more work, as detailed [here.](https://github.com/extradummythicc/aptDL/wiki/Custom-workarounds-to-get-the-token-if-you-cannot-register-the-Sileo-URL-protocol#exceptions)
</details>

<details>
  <summary>Method 3: Manually requesting the API for the token</summary>

  [Refer to this wiki page to get the token.](https://github.com/extradummythicc/aptDL/wiki/Custom-workarounds-to-get-the-token-if-you-cannot-register-the-Sileo-URL-protocol)

  After you finish, build `authentication.json` [according to the example.](#example-authenticationjson)
</details>

## Old repos without the API (BigBoss etc.)
Edit `modules/download.ps1`, function Get-Headers with your own information:
```powershell
function Get-Header {
    $headers = @{
        "X-Machine" = "YOUR_DEVICE_IDENTIFIER"
        "X-Unique-ID" = "YOUR_DEVICE_UDID"
        "X-Firmware" = "YOUR_DEVICE_VERSION"
        "User-Agent" = "Sileo/2.2.6 CoreFoundation/1775.118 Darwin/20.4.0"
    }
    return $headers
}
```

# TODO
- [x] Support for dist repos
- [x] Input file
