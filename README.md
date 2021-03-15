# imgurAU
**macOS one-stop shop solution for anonymous uploads to imgur with support for local files, pasteboard contents, screenshots & web images**

## Impetus
**Snappy** was once arguably the best screenshot utility for macOS, and it also included anonymous uploads to imgur. That application is now discontinued, which luckily is not a loss anymore, because Apple have stepped up, and the built-in macOS **Screen Shot** utility now has basically the same functionality as Snappy had, and then some. However, there is no upload functionality available.

Something similar happened with the macOS sharing extension **ImageShareUr**, which could be used for anonymous imgur uploads: it was abandoned a long time ago. There is a similar sharing extension for macOS, **imGuru**, but it only works if you have an imgur account, and the software's automatic log-in functionality tends to be very buggy.

In terms of web browser extensions, there is one for anonymous imgur uploads, namely **imgur Uploader** for Firefox, but that one stopped working as well.

But for years now, there has been **imguru**, a command-line program for anonymous imgur uploads, and it is also officially endorsed by imgur. This still seems to be the best option to upload image files to imgur anonymously.

The **imgurAU** shell script uses **imguru** for anonymous uploads, while using imguru's OAuth key for direct cURL uploads of online web images. The script also uses extended macOS pasteboard functionality, available through the **pbv** program, to detect if an image has been copied into the macOS pasteboard. When using the software **EventScripts**, imgurAU can also be used to easily upload a new screenshot to imgur.

## Requisites
### Command-line programs
* **[`exiftool`](https://exiftool.org/)** (install e.g. with **[Homebrew](https://brew.sh/)**)
* **[`imguru`](https://github.com/FigBug/imguru)**
* **[`pbv`](https://github.com/chbrown/macos-pasteboard)**
* **[`trash`](https://github.com/sindresorhus/macos-trash)** (install e.g. with **Homebrew**)

Note: the requisites `imguru` and `pbv` can be downloaded from the respective `./bin` directories in this repository; only the Universal 2 binary builds for macOS 11.1 and later have been tested.

### Firefox
* **[Open With](https://addons.mozilla.org/en-US/firefox/addon/open-with/)** – browser extension

### Applications (optional)
* **[EventScripts](https://www.mousedown.net/software/EventScripts.html)** – download & install from the **[Mac App Store](https://apps.apple.com/gb/app/eventscripts/id525319418?mt=12)**

## Installation
* option #1: clone this repository and symlink `imgur-au.sh`, `imguru` and `pbv` into one of your bin directories
* option #2: download the repository and copy `imgur-au.sh`, `imguru` and `pbv` into one of your bin directories
* if necessary, set the executable bits with `chmod +x`
* install the `trash` program
* install the `exiftool` program

### EventScripts setup
* copy `imgur-au.sh` into `~/Library/Application Scripts/net.mousedown.EventScripts`
* if necessary, set the executable bit with `chmod +x`
* in EventScripts' preferences under "EventScripts" choose the application script `imgur-au.sh` and map it to the event "Screenshot Taken"

Note: if you haven't installed **EventScripts**, or if the application is not running, you can still have `imgur-au.sh` detect a newly created screenshot: the underlying macOS application **Screen Shot** will not exit immediately, so if you hit your imgurAU keyboard shortcut (or tap your imgurAU Touch Bar button) quickly enough, it will still work. Alternatively, you can always create a user **Launch Agent** that watches your local screenshot folder for changes (e.g. with `watchman`, `fswatch` etc.) and calls `imgur-au.sh` when a new file has been created.

### File managers & other applications
* if you use a file manager with direct shell script support like **[Nimble Commander](https://magnumbytes.com)**, you can just set up `imgur-au.sh` as a file management tool complete with keyboard shortcut
* you can map that keyboard shortcut to a macOS Touch Bar button with **[BetterTouchTool](https://folivora.ai)**
* you can also map `imgur-au.sh` to a general macOS Touch Bar button for execution without arguments
* in macOS **Finder** you need to create a Finder Quick Action (see the template script in this repository's subfolder)
* in **Firefox** you will need the **[Open With](https://addons.mozilla.org/en-US/firefox/addon/open-with/)** browser extension, which is also available on **[GitHub](https://github.com/darktrojan/openwith)**
* in **Safari** `imgur-au.sh` might work as a macOS Service workflow (please create it yourself)

## Functionality
* upload local file(s)
* auto-detect newly created screenshots & upload (option: delete after upload)
* upload frontmost image of the frontmost application
* upload image from pasteboard
* upload web image in the web browser
* upload web images from a list of URLs
* upload local files from a list of filepaths
* select file(s) for upload (only if imgurAU was launched without arguments)

Note: to prevent accidental uploads, imgurAU will always ask before uploading local files; since AppleScript can display images only at icon size, you have the option to inspect the image further before upload, and imgurAU will then open the file in a macOS **QuickLook** floating window.

Note: after a successful upload, imgurAU will return the direct sharing URL of the image and copy it to the macOS pasteboard. If several images are uploaded at once, imgurAU will also create a dated plaintext file in `~/Pictures/imgurAU` containing the filenames and the imgur URLs.

Note: since imgurAU doesn't come with a sharing extension, which would let you upload directly from an image editing software, you have to select your image in the editor and copy it (CMD-C) to your macOS pasteboard, and then run imgurAU without input; imgurAU will then extract the image from the pasteboard for upload.

## Uninstall imgurAU
* repository clone
* all instances of `imgur-au.sh`
* `~/Pictures/imgurAU`

## To-do
* find a way to execute a shell script from the macOS Share menu

## Screenshots

![sg01](https://raw.githubusercontent.com/JayBrown/imgurAU/main/img/01_main.png)

![sg02](https://raw.githubusercontent.com/JayBrown/imgurAU/main/img/02_trash.png)
