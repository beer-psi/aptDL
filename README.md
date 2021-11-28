# aptDL
Downloads Cydia repositories (paid packages not included)

~~Dist repos are also not supported for now.~~ Dist repos are now working! (mostly)

# Usage
```
.\main.ps1 <-s REPO_URL> <-cr | -co> [-suites DIST_SUITES] [-p PACKAGE] [-o OUTPUT_DIR] [-cd COOLDOWN_SECONDS] [-auth AUTHENTICATION_JSON] [-7z PATH]

Required arguments:
  -s: Repo to download
  -cr: Rename downloaded files to PACKAGENAME-VERSION.deb
  -co: Don't rename downloaded files
-cr and -co are mutually exclusive.
  
Optional arguments:
  -suites: Specify the suite you want to download from, required for dist repos. 
  -p: Specify package to download, if omitted download all packages.
  -o: Output directory (relative to the script's directory, default is .\output)
  -cd: Time to wait between downloads (default 5 seconds, so as not to hit rate limit)
  -auth: Location of JSON file containing authentication (token, udid and device), which will be sent when downloading paid packages 
         Refer to https://developer.getsileo.app/payment-providers at the Downloads section.
  -7z: Manually specify the path to 7z executable, in case the script can't find it itself.
```

# Paid packages
Edit the accompanied authentication.json with your own details, then invoke the script with `-auth .\authentication.json`

Example `authentication.json`:
```
{
    "token": "f2ca1bb6c7e907d06dafe4687e579fce76b37e4e93b7605022da52e6ccc26fd2",
    "udid": "4e1243bd22c66e76c2ba9eddc1f91394e57f9f83",
    "device": "iPhone7,2"
}
```
## Building authentication.json
Register the sileo:// protocol and point it to `get_token.exe` (Windows) or `get_token.ps1` (Linux).
- [Registering a URL protocol on Windows](https://stackoverflow.com/questions/80650/how-do-i-register-a-custom-url-protocol-in-windows)
- [Registering a URL protocol on Linux](https://unix.stackexchange.com/questions/497146/create-a-custom-url-protocol-handler)
- I've never really used macOS so I don't know how to register a URL protocol there /shrug

Then, run the `get_token.ps1` script and fill in the information. After that, a browser window will open, allowing you to login with your repo. After you've linked your "device" with the repo, a console app will appear showing your token. Verify that the token showed matches the one in `authentication.json`.

Once you've finished, just call the download script with `-auth authentication.json`. Reminder that each authentication will only work with one repo.

# TODO
- [x] Support for dist repos
- [ ] Input file
