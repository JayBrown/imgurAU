# imgurAU
**macOS one-stop shop solution for anonymous uploads to imgur with support for local files, files opened in image editors, pasteboard contents, new screenshots & web images**

## Impetus
**Snappy** was once arguably the best screenshot utility for macOS, and it also included anonymous uploads to imgur. That application is now discontinued, which luckily is not a loss anymore, because Apple have stepped up, and the built-in macOS **Screen Shot** utility now has basically the same functionality as Snappy had, and then some. However, there is no upload functionality available.

Something similar happened with the macOS sharing extension **ImageShareUr**, which could be used for anonymous imgur uploads: it was abandoned a long time ago. There is a similar sharing extension for macOS, **imGuru**, but it only works if you have an imgur account, and the software's automatic log-in functionality tends to be very buggy.

In terms of web browser extensions, there is one for anonymous imgur uploads, namely **imgur Uploader** for Firefox, but that one stopped working as well.

But for years now, there has been a public imgur API for anonymous uploads with cURL on the command-line, and many scripted solutions have been created, some of them officially endorsed by imgur. This still seems to be the best option to upload image files to imgur anonymously.

The **imgurAU** shell script originally used the **imguru** command-line program for anonymous uploads, and its builds (including one for macOS Big Sur and later) are still included in this repository. But that program stopped working properly, too, so imgurAU is now only using that program's client ID for direct cURL uploads. However, it is recommended that you get your own imgur client ID, and add it to the imgurAU configuration file.

The imgurAU script also uses extended macOS pasteboard functionality, available through the **pbv** program, to detect if an image has been copied into the macOS pasteboard. When using the software **EventScripts**, imgurAU can also be used to easily upload a new screenshot to imgur.

## Requisites
* **[`exiftool`](https://exiftool.org/)** (install e.g. with **[Homebrew](https://brew.sh/)**)
* **[`jq`](https://stedolan.github.io/jq/)** (install e.g. with Homebrew)
* **[`pbv`](https://github.com/chbrown/macos-pasteboard)**
* **[`trash`](https://github.com/sindresorhus/macos-trash)** (install e.g. with Homebrew)

Note: the requisite `pbv` can be downloaded from the respective `./bin` directories in this repository; only the Universal 2 binary builds for macOS 11.1 and later have been tested.

## Installation
* option #1: clone this repository and symlink `imgur-au.sh`, `imguru` (if you're not using an individual build) and `pbv` into one of your bin directories
* option #2: download the repository and copy `imgur-au.sh`, `imguru` (if you're not using an individual build) and `pbv` into one of your bin directories
* if necessary, set the executable bits with `chmod +x`
* install the programs `exiftool` `jq` `trash`

## Setup options
### imgur client ID (optional, recommended)
* get an **imgur client ID** and add it to the configuration file `~/.config/imgurAU/imgur_client_id.txt`
* you will need an imgur account to receive a client ID, but once you have one, you can upload anonymously

### Web browsers
* **[Open With](https://addons.mozilla.org/en-US/firefox/addon/open-with/)** – browser extension for **Firefox**
* in **Safari** `imgur-au.sh` might work as a macOS Service workflow (please create it yourself)

### EventScripts
* **[EventScripts](https://www.mousedown.net/software/EventScripts.html)** can be downloaded & installed from the **[Mac App Store](https://apps.apple.com/gb/app/eventscripts/id525319418?mt=12)**
* copy `imgur-au.sh` into `~/Library/Application Scripts/net.mousedown.EventScripts`
* if necessary, set the executable bit with `chmod +x`
* in EventScripts' preferences under "EventScripts" choose the application script `imgur-au.sh` and map it to the event "Screenshot Taken"

Note: if you haven't installed **EventScripts**, or if the application is not running, you can still have `imgur-au.sh` detect a newly created screenshot: the underlying macOS application **Screen Shot** will not exit immediately, so if you hit your imgurAU keyboard shortcut (or tap your imgurAU Touch Bar button) quickly enough, it will still work. Alternatively, you can always create a user **Launch Agent** that watches your local screenshot folder for changes (e.g. with `watchman`, `fswatch` etc.) and calls `imgur-au.sh` when a new file has been created.

### File managers
* if you use a file manager with direct shell script support like **[Nimble Commander](https://magnumbytes.com)**, you can just set up `imgur-au.sh` as a file management tool complete with keyboard shortcut
* for macOS **Finder** you need to create a Finder Quick Action (see the template script in this repository's subfolder)

### BetterTouchTool
* you can map your file manager's keyboard shortcut for imgurAU to a macOS Touch Bar button with **[BetterTouchTool](https://folivora.ai)**
* you can also map `imgur-au.sh` to a general macOS Touch Bar button for execution without arguments

## Functionality
* upload local image file(s)
* auto-detect newly created screenshots & upload (option: delete after upload)
* upload frontmost image of the frontmost application
* upload image from pasteboard
* upload web image in the web browser
* upload web images from a list of URLs
* upload local files from a list of filepaths
* select file(s) for upload (only if imgurAU was launched without arguments)

Note: to prevent accidental uploads, imgurAU will always ask before uploading local files; since AppleScript can display images only at icon size, you have the option to inspect the image further before upload, and imgurAU will then open the file in a macOS **QuickLook** floating window.

Note: after a successful upload, imgurAU will return the direct sharing URL of the image and copy it to the macOS pasteboard. If several images are uploaded at once, imgurAU will also create a dated plaintext file in `~/Pictures/imgurAU` containing the filenames and the imgur URLs.

Note: imgurAU doesn't come with a sharing extension, which would let you upload directly from an image editing software via the "Share" menu, but you have two alternative solutions:

* execute imgurAU without input while the relevant image file is opened as the frontmost document of the frontmost image viewer or editor
* select the relevant image in the image viewer or editor and copy it (CMD-C) to your macOS pasteboard, then execute imgurAU without input

## Uninstall imgurAU
* repository clone
* all instances of `imgur-au.sh`
* `~/Pictures/imgurAU`
* `~/.config/imgurAU`

## To-do
* find a way to execute a shell script from the macOS Share menu

## Screenshots

![sg01](https://raw.githubusercontent.com/JayBrown/imgurAU/main/img/01_main.png)

![sg02](https://raw.githubusercontent.com/JayBrown/imgurAU/main/img/02_trash.png)
