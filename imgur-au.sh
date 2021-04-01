#!/bin/zsh
# shellcheck shell=bash

# imgur-au.sh
# v0.11.2 beta
#
# imgurAU
# imgur Anonymous Uploader
#
# Copyright (c) 2021 Joss Brown (pseud.)
# License: MIT
# Place of jurisdiction: Berlin / German laws apply
#
# requisites:
# exiftool - https://exiftool.org (available via Homebrew)
# file-icon - https://github.com/sindresorhus/file-icon-cli (install with npm/node; node available via Homebrew)
# imagemagick - https://www.imagemagick.org/ (available via Homebrew)
# jq - https://stedolan.github.io/jq/ (available via Homebrew)
# pbv - https://github.com/chbrown/macos-pasteboard (also available in the imgurAU repository)
# trash - https://github.com/sindresorhus/macos-trash (available via Homebrew)
#
# imgur formats & maximum file sizes
# https://help.imgur.com/hc/en-us/articles/115000083326-What-files-can-I-upload-What-is-the-size-limit-
# GIF: 200 MB max
# other: 20 MB max
# PNG > 5 MB - convert to JPEG

export LANG=en_US.UTF-8
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/local/bin:/opt/homebrew/bin:/opt/sw/bin:"$HOME"/.local/bin:"$HOME"/bin:"$HOME"/local/bin

procid="local.lcars.imgurAU"
uiprocess="imgurAU"
account=$(id -u)

# logging
logloc="/tmp/$procid.log"
currentdate=$(date)
if ! [[ -f $logloc ]] ; then
	echo "++++++++ $currentdate ++++++++" > "$logloc"
else
	echo -e "\n++++++++ $currentdate ++++++++" >> "$logloc"
fi
exec > >(tee -a "$logloc") 2>&1

# check for macOS app Snap Shot
snapshots=false
if pgrep -x "screencaptureui" &>/dev/null ; then
	echo "macOS Snap Shot is running" >&2
	snapshots=true
	# check for EventScripts app
	if pgrep -x "EventScripts" &>/dev/null ; then
		echo "EventScripts is running: overriding Snap Shot" >&2
		snapshots=false
	fi
fi

# check for BBCode formatting
bbcode=false
if [[ $1 =~ ^(-b|--bbcode)$ ]] ; then
	shift
	bbcode=true
	echo "BBCode mode enabled" >&2
fi

# read screenshot location
sg_def=true
sg_loc=$(/usr/libexec/PlistBuddy -c "Print:location" "$HOME/Library/Preferences/com.apple.screencapture.plist" 2>/dev/null)
! [[ $sg_loc ]] && sg_loc=$(defaults read "com.apple.screencapture" location 2>/dev/null)
if ! [[ $sg_loc ]] ; then
	echo "WARNING: no screenshot directory defined" >&2
	sg_def=false
else
	sg_loc=$(echo "$sg_loc" | sed 's-/*$--')
	echo "Screenshot location: $sg_loc" >&2
	if $snapshots && ! [[ $* ]] ; then
		shift $#
		set -- "$@" "internal-snapshot"
	fi
fi

# function: error beep
_beep () {
	osascript -e 'beep' -e 'delay 0.5' &>/dev/null
}

# function: success sound
_success () {
	afplay "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/burn complete.aif" &>/dev/null
}

# function: notify user
_notify () {
	osascript &>/dev/null << EOT
tell application "System Events"
	display notification "$2" with title "$uiprocess [" & "$account" & "]" subtitle "$1"
end tell
EOT
}

read -d '' reqs <<"EOR"
	exiftool
	file-icon
	jq
	magick
	pbv
	trash
EOR

# check for requisites
reqerror=false
while read -r req
do
	if ! command -v "$req" &>/dev/null ; then
		echo "ERROR: $req not installed" >&2
		_notify "❌ Error: requisites!" "$req is not installed"
	fi
done < <(echo "$reqs")
if $reqerror ; then
	_beep &
	exit
fi

# imgurAU locations: backup temp
savedir="$HOME/Pictures/imgurAU"
! [[ -d "$savedir" ]] && mkdir "$savedir"
links_loc="$savedir/$currentdate.txt"
tmpdir="/tmp/$procid"
! [[ -d "$tmpdir" ]] && mkdir "$tmpdir"
uldir="$tmpdir/ul"
! [[ -d "$uldir" ]] && mkdir "$uldir"
configdir="$HOME/.config/imgurAU"
! [[ -d "$configdir" ]] && mkdir "$configdir"

# imgur client ID
oauthloc="$configdir/imgur_client_id.txt"
! [[ -f "$oauthloc" ]] && touch "$oauthloc"
client_id=$(head -1 < "$oauthloc" 2>/dev/null)
if ! [[ $client_id ]] ; then
	client_id="51f229880e3ea84" # imguru program ID (works better with cURL)
	id_info="default"
else
	id_info="user"
fi
echo "Client ID: $client_id ($id_info)" >&2

_frontmost () {
	frontmost=$(osascript 2>/dev/null << EOF
use framework "Foundation"
use scripting additions
try
	tell application "System Events"
		set theFrontProcess to first process whose frontmost is true
		set theProcessName to name of theFrontProcess
		tell theFrontProcess
			tell front window
				tell attribute "AXDocument"
					set theFileURL to its value
				end tell
			end tell
		end tell
	end tell
on error
	set theFileURL to missing value
end try
if theFileURL ≠ missing value and theFileURL ≠ "file:///Irrelevant" and theFileURL ≠ "file:///Irrelevent" then
	set thePOSIXPath to (current application's class "NSURL"'s URLWithString:theFileURL)'s |path|() as text
	return thePOSIXPath
else
	return "none"
end if
EOF
	)
	if [[ $frontmost != "none" ]] ; then
		frontname=$(basename "$frontmost")
		if echo "$frontname" | grep -q -i -e "\.png$" -e "\.jpg$" -e "\.jpeg$" -e "\.tif$" -e "\.tiff$" -e "\.gif$" -e "\.webp$" -e "\.apng$" -e "\.webm$" -e "\.mp4$" -e "\.m4v$" -e "\.avi$" &>/dev/null ; then
			echo -n "$frontmost" #
		fi
	fi
}

# check & arrange input first
if [[ $* ]] ; then # input arguments
	echo "Input (raw): $*" >&2
	if [[ $1 == "internal-snapshot" ]] ; then
		img_newest=$(find "$sg_loc" -mindepth 1 -maxdepth 1 -type f \( -name '*.jpg$' -o -name '*.png$' -o -name '*.jpeg$' -o -name '*.tif$' -o -name '*.tiff$' -o -name '*.gif$' \) -print0 2>/dev/null | xargs -r -0 ls -1 -t | head -1 | grep -v "^$")
		if [[ $img_newest ]] ; then # screenshot file found
			shift $#
			set -- "$@" "$img_newest"
		else # no screenshot file found
			echo "ERROR: screenshot directory empty - asking user..." >&2
			shift $#
			set -- "$@" "internal-select screenshots"
		fi
	else
		if echo "$*" | grep -q "net\.mousedown\.EventScripts" &>/dev/null ; then # EventScripts event
			echo "Detected EventScripts input" >&2
			if $sg_def ; then # screenshot folder is known
				checkname=$(echo "$*" | sed 's/^Screenshot taken *//' | awk -F" /" '{print $1}')
				if ! [[ $checkname ]] ; then # parse error (filename)
					echo "ERROR: couldn't parse for screenshot filename'" >&2
					shift $#
					set -- "$@" "internal-select screenshots"
				else # name OK
					echo "Screenshot filename: $checkname" >&2
					if ! [[ -f "$sg_loc/$checkname" ]] ; then # false alarm by EventScripts
						echo "ERROR: screenshot removed - exiting..." >&2
						exit
					else # new screenshot created
						shift $#
						set -- "$@" "$sg_loc/$checkname"
					fi
				fi
			else # screenshot folder is unknown
				echo "ERROR: no screenshot directory specified - asking user..." >&2
				shift $#
				set -- "$@" "internal-select"
			fi
		else # normal input
			echo "Generic input: filepath(s) or URL" >&2
		fi
	fi
else # no input arguments
	echo "No input: checking frontmost document..." >&2
	frontdoc=$(_frontmost 2>/dev/null)
	if [[ $frontdoc ]] ; then
		echo -e "Detected Document: $frontdoc\nAppending to input..." >&2
		shift $#
		set -- "$@" "$frontdoc"
	else
		echo "No document: checking pasteboard..." >&2
		pasteboard=$(pbpaste 2>/dev/null) # check for URLs first
		if [[ $pasteboard == "http://"* ]] || [[ $pasteboard == "https://"* ]] ; then # URL detected (check later)
			echo "Detected URL: appending to input..." >&2
			shift $#
			set -- "$@" "$pasteboard"
		else # no URLs
			posixdate=$(date +%s)
			pbfile="$tmpdir/$posixdate-pasteboard.tif"
			rm -f "$pbfile" 2>/dev/null
			if ! pbv public.tiff > "$pbfile" &>/dev/null ; then # no image file in pasteboard
				rm -f "$pbfile" 2>/dev/null
				echo "NOTE: no valid pasteboard content" >&2
			else # image file in pasteboard & exported
				echo -e "Image data exported to temp TIFF: $posixdate-pasteboard.tif\nAppending to input..." >&2
				shift $#
				set -- "$@" "$pbfile"
			fi
		fi
	fi
fi

# imgur file size settings
gifmax=209715200
othermax=20971520
pngmax=5242880

# prompt with image: ask user for upload
_ask-upload () {
	askimgpath="$1"
	askname=$(basename "$askimgpath")
	uploadchoice=$(osascript 2>/dev/null << EOG
tell application "System Events"
	activate
	set theLogoPath to POSIX file "$askimgpath"
	set theButton to button returned of (display dialog "Do you want to upload the image '$askname' to imgur?" ¬
		buttons {"Cancel", "Inspect", "Upload"} ¬
		cancel button 1 ¬
		with title "imgurAU" ¬
		with icon file theLogoPath ¬
		giving up after 180)
end tell
EOG
	)
	if [[ $uploadchoice == "Inspect" ]] ; then
		uploadchoice=""
		qlmanage -p "$askimgpath" &>/dev/null &
		uploadchoice=$(osascript 2>/dev/null << EOG
tell application "System Events"
	activate
	set theLogoPath to POSIX file "$askimgpath"
	set theButton to button returned of (display dialog "Do you want to upload the image '$askname' to imgur?" ¬
		buttons {"Cancel", "Upload"} ¬
		cancel button 1 ¬
		with title "imgurAU" ¬
		with icon file theLogoPath ¬
		giving up after 180)
end tell
EOG
		)
	fi
	echo -n "$uploadchoice" #
}

_ask-exif () {
	askexifpath="$1"
	exifchoice=$(osascript 2>/dev/null << EOX
tell application "System Events"
	activate
	set theLogoPath to POSIX file "$askexifpath"
	set theButton to button returned of (display dialog "imgurAU was unable to remove the selected image's metadata. Do you still want to continue?" ¬
		buttons {"Cancel", "Continue"} ¬
		cancel button 1 ¬
		default button 2 ¬
		with title "imgurAU" ¬
		with icon file theLogoPath ¬
		giving up after 180)
end tell
EOX
	)
	echo -n "$exifchoice" #
}

# open file dialog with macOS previews: ask user to select for upload
_select-image () {
	if [[ $1 == "multi" ]] ; then # no general input arguments: user can select multiple
		shift
		selectpath="$1"
		imgpathchoice=$(osascript 2>/dev/null << EOS
tell application "System Events"
	activate
	set theDefaultPath to "$selectpath" as string
	set theUploadImages to choose file with prompt ¬
		"Please select one or more image files for upload to imgur…" ¬
		of type {"png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "apng", "webm", "mp4", "m4v", "avi"} ¬
		with multiple selections allowed ¬
		default location theDefaultPath
	repeat with anUploadImage in theUploadImages
		set contents of anUploadImage to POSIX path of (contents of anUploadImage)
	end repeat
	set AppleScript's text item delimiters to linefeed
	theUploadImages as text
end tell
EOS
		)
	else # alternative selection: user can select only one file
		selectpath="$1"
		imgpathchoice=$(osascript 2>/dev/null << EOS
tell application "System Events"
	activate
	set theDefaultPath to "$selectpath" as string
	set theUploadImage to POSIX path of (choose file with prompt "Please select an image file for upload to imgur…" ¬
		of type {"png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "apng", "webm", "mp4", "m4v", "avi"} ¬
		default location theDefaultPath)
end tell
theUploadImage
EOS
		)
	fi
	echo -n "$imgpathchoice" #
}

# file checks & conversions (size/format)
_check-file () {
	checkpath="$1"
	checkname=$(basename "$checkpath")
	suffix="${checkname##*.}"
	# echo "Extension: $suffix" >&2
	webpconv=false
	jpegconv=false
	if [[ $(magick identify -format '%[channels]' "$checkpath" 2>/dev/null) == "srgba" ]] ; then
		hasalpha=true
	fi
	if [[ $suffix =~ ^(webp|WEBP)$ ]] ; then
		if ! $hasalpha ; then
			# echo "Converting unsupported format to JPEG..." >&2
			shortcheckname="${checkname%.*}"
			tempcheckname="$posixdate-$shortcheckname.jpg"
			if sips -s format jpeg "$checkpath" --out "$tmpdir/$tempcheckname" &>/dev/null ; then
				checkpath="$tmpdir/$tempcheckname"
				checkname="$tempcheckname"
				suffix="jpg"
				webpconv=true
			else
				_beep &
				_notify "⚠️ Error: conversion failed!" "$checkname"
				rm -f "$tmpdir/$tempcheckname" 2>/dev/null
				# echo "ERROR: conversion failed" >&2
				echo -n "error" #
				return
			fi
		else
			# echo "Converting unsupported format to PNG..." >&2
			shortcheckname="${checkname%.*}"
			tempcheckname="$posixdate-$shortcheckname.png"
			if sips -s format png "$checkpath" --out "$tmpdir/$tempcheckname" &>/dev/null ; then
				checkpath="$tmpdir/$tempcheckname"
				checkname="$tempcheckname"
				suffix="png"
				webpconv=true
			else
				_beep &
				_notify "⚠️ Error: conversion failed!" "$checkname"
				rm -f "$tmpdir/$tempcheckname" 2>/dev/null
				# echo "ERROR: conversion failed" >&2
				echo -n "error" #
				return
			fi
		fi
	fi
	# if no transparency, convert to JPEG (except for GIF): other formats can be buggy
	if ! $hasalpha ; then
		if ! [[ $suffix =~ ^(jpg|JPG|jpeg|JPEG|gif|GIF)$ ]] ; then
			# echo "Converting to JPEG for best compatibility..." >&2
			shortcheckname="${checkname%.*}"
			tempcheckname="$posixdate-$shortcheckname.jpg"
			if sips -s format jpeg "$checkpath" --out "$tmpdir/$tempcheckname" &>/dev/null ; then
				checkpath="$tmpdir/$tempcheckname"
				checkname="$tempcheckname"
				suffix="jpg"
				jpegconv=true
			# else
			# echo "Conversion failed: trying original format..." >&2
			fi # do not exit on error: try uploading with the original format first
		fi
	fi
	fsize=$(stat -f%z "$checkpath" 2>/dev/null) # general file size check
	# echo "File size: $fsize" >&2
	if ! [[ $fsize ]] || [[ $fsize -eq 0 ]] ; then
		_beep &
		_notify "⚠️ Error: no file content!" "$checkname"
		# echo "ERROR: no file content" >&2
		echo -n "error" #
		return
	fi
	# check file sizes relative to formats for imgur support
	abort=false
	if [[ $suffix =~ ^(gif|GIF)$ ]] ; then
		[[ $fsize -gt "$gifmax" ]] && abort=true
	else
		[[ $fsize -gt "$othermax" ]] && abort=true
	fi
	if $abort ; then
		_beep &
		_notify "⚠️ Error: file too large!" "$checkname"
		# echo "ERROR: file too large" >&2
		echo -n "error" #
		return
	fi
	# potential format conversion (into temp dir)
	if [[ $suffix =~ ^(png|PNG)$ ]] && [[ $fsize -gt "$pngmax" ]] ; then
		# echo "Converting PNG to JPEG..." >&2
		shortcheckname="${checkname%.*}"
		tempcheckname="$posixdate-$shortcheckname.jpg"
		if sips -s format jpeg "$checkpath" --out "$tmpdir/$tempcheckname" &>/dev/null ; then
			echo -n "$tmpdir/$tempcheckname" #
		else
			_beep &
			_notify "⚠️ Error: conversion failed!" "$checkname"
			rm -f "$tmpdir/$tempcheckname" 2>/dev/null
			# echo "ERROR: conversion failed" >&2
			echo -n "error" #
		fi
	fi
	if $jpegconv || $webpconv ; then
		echo -n "$checkpath" #
	fi
}

_upload () {
	fuploadpath="$1"
	
	converted=false
	cleaned=false
	
	uask=false
	[[ $fuploadpath != "$tmpdir/"* ]] && uask=true
	$pasted && uask=true
	
	if $uask ; then
		uchoice=$(_ask-upload "$fuploadpath" 2>/dev/null)
		if ! [[ $uchoice ]] || [[ $uchoice == "false" ]] ; then
			# echo "User canceled" >&2
			echo "canceled" #
			return
		fi
	fi
	imgcheck=$(_check-file "$fuploadpath" 2>/dev/null)
	[[ $imgcheck == "error" ]] && return
	if [[ $imgcheck == "$tmpdir/"* ]] ; then
		converted=true
		fuploadpath="$imgcheck"
	fi
	
	exifname=$(basename "$fuploadpath")
	exifpath="$uldir/$exifname"
	rm -f "$exifpath" 2>/dev/null
	if exiftool -all= -tagsfromfile @ "-all:*resolution*" -filename="$exifpath" "$fuploadpath" &>/dev/null ; then
		cleaned=true
		fuploadpath="$exifpath"
	else
		xchoice=$(_ask-exif "$uploadpath" 2>/dev/null)
		if ! [[ $xchoice ]] || [[ $xchoice == "false" ]] ; then
			# echo "User canceled" >&2
			$converted && rm -f "$imgcheck" 2>/dev/null
			rm -f "$exifpath" 2>/dev/null
			echo "canceled" #
			return
		fi
	fi
	
	# imgur_url=$(imguru "$fuploadpath" 2>/dev/null | grep -v "^$")
	imgur_raw=$(curl -k -L -s --connect-timeout 10 -H "Authorization: Client-ID $client_id" -H "Expect: " -F "image=@$fuploadpath" "https://api.imgur.com/3/image.xml" 2>/dev/null)
	imgur_url=$(echo "$imgur_raw" | tail -n +2 | awk -F"<link>" '{print $NF}' | awk -F"</link>" '{print $1}' 2>/dev/null)
	if [[ $imgur_url == "https://i.imgur.com/"* ]] ; then
		echo -n "$imgur_url" #
	else
		fuploadname=$(basename "$fuploadpath")
		_notify "⚠️ Error: image file upload" "Trying base64 upload: $fuploadname"
		imgbase=$(base64 -i "$fuploadpath" 2>/dev/null)
		if [[ $imgbase ]] ; then
			imgur_data=$(curl -k -L -s --connect-timeout 10 --request POST "https://api.imgur.com/3/image" -H "Authorization: Client-ID $client_id" -H "Expect: " -F "image=$imgbase" 2>/dev/null)
			if [[ $imgur_data ]] ; then
				imgur_url=$(echo "$imgur_data" | jq -r '.data.link')
				if [[ $imgur_url == "https://i.imgur.com/"* ]] ; then
					echo -n "$imgur_url" #
				fi
			fi
		fi
	fi
	
	$converted && rm -f "$imgcheck" 2>/dev/null
	$cleaned && rm -f "$exifpath" 2>/dev/null
}

# ask user for file deletion
_trash () {
	trashfile="$1"
	delete=$(osascript 2>/dev/null << EOD
tell application "System Events"
	activate
	set theLogoPath to POSIX file "$trashfile"
	set theButton to button returned of (display dialog "Do you want to delete or keep the screenshot you just uploaded?" ¬
		buttons {"Delete", "Keep"} ¬
		cancel button 2 ¬
		with title "imgurAU" ¬
		with icon file theLogoPath ¬
		giving up after 180)
end tell
EOD
	)
	if [[ $delete == "Delete" ]] ; then # try to move to trash first
		if ! trash "$trashfile" &>/dev/null ; then # remove completely on error
			echo "ERROR: couldn't move screenshot to Trash - removing instead" >&2
			rm -f "$trashfile" 2>/dev/null
		else
			echo "Screenshot moved to the Trash" >&2
		fi
	else
		echo "User chose to keep the screenshot" >&2
	fi
}

# auxiliary routine without input arguments
if ! [[ $* ]] ; then
	echo "No final input: asking user..." >&2
	uploadpaths=$(_select-image multi "$HOME/Pictures" 2>/dev/null)
	if ! [[ $uploadpaths ]] ; then
		echo "User canceled." >&2
		exit
	fi
	if [[ $(echo "$uploadpaths" | wc -l) -gt 1 ]] ; then # multiple files selected: upload right here
		uploadinfo=""
		errors=false
		while read -r uploadpath
		do
			echo "Accessing: $uploadpath" >&2
			uploadname=$(basename "$uploadpath")
			shareurl=$(_upload "$uploadpath" 2>/dev/null)
			if [[ $shareurl == "https://i.imgur.com/"* ]] ; then
				echo "Success: $shareurl ($uploadname)" >&2
				if ! $bbcode ; then
					uploadinfo="$uploadinfo\n$shareurl|$uploadname"
				else
					uploadinfo="$uploadinfo\n"'[img]'"$shareurl"'[/img]'"|$uploadname"
				fi
				_notify "✅ Upload successful" "$shareurl ($uploadname)"
			else
				if ! [[ $shareurl ]] ; then
					echo "ERROR: upload: $uploadname" >&2
					uploadinfo="$uploadinfo\nERROR|$uploadname"
					_notify "❌ Upload failed!" "$uploadname"
					errors=true
				elif [[ $shareurl == "canceled" ]] ; then
					echo "User canceled" >&2
				else
					echo "Unknown condition: $shareurl" >&2
				fi
			fi
			osascript -e 'tell application "qlmanage" to quit' &>/dev/null
		done < <(echo "$uploadpaths")
		if $errors ; then
			_beep &
		else
			_success &
		fi
		echo "Writing results to info file: $links_loc" >&2
		echo -e "$uploadinfo" | grep -v "^$" > "$links_loc"
		sleep .5
		open "$links_loc"
		exit
	else # one file selected: access in main routines via $@
		set -- "$@" "$uploadpaths"
	fi
fi

# asking user (single selection)
if [[ $1 == "internal-select" ]] ; then
	if [[ $2 == "screenshots" ]] ; then
		selection=$(_select-image "$sg_loc" 2>/dev/null)
	else
		selection=$(_select-image "$HOME/Pictures" 2>/dev/null)
	fi
	if ! [[ $selection ]] ; then
		echo "User canceled" >&2
		exit
	fi
	shift $#
	set -- "$@" "$selection"
fi

# main routines with input or re-organized input
echo "Final input (raw): $*" >&2

errors=false
allfiles=""
allurls=""
for input in "$@"
do
	! [[ $input ]] && continue
	
	inputname=$(basename "$input")
	posixdate=$(date +%s)
	
	# check for proper input
	if [[ $input == "/"* ]] ; then
		if ! [[ -e "$input" ]] ; then
			echo "ERROR: file missing ($inputname)" >&2
			_beep &
			_notify "❓ File missing" "$inputname"
			continue
		fi
		if ! echo "$inputname" | grep -q -i -e "\.png$" -e "\.jpg$" -e "\.jpeg$" -e "\.tif$" -e "\.tiff$" -e "\.gif$" -e "\.webp$" -e "\.apng$" -e "\.webm$" -e "\.mp4$" -e "\.m4v$" -e "\.avi$" &>/dev/null ; then # not a proper file type
			cfileicon="$tmpdir/$posixdate-$inputname-icon256.png"
			if file-icon "$input" --size 256 > "$cfileicon" &>/dev/null ; then
				allfiles="$allfiles\n$cfileicon"
			else
				echo "ERROR: wrong file format" >&2
				_beep &
				_notify "❌ Wrong file format!" "Not supported by imgur: $inputname"
				rm -f "$cfileicon" 2>/dev/null
			fi
			continue
		else
			allfiles="$allfiles\n$input"
		fi
	elif [[ $input == "http://"* ]] || [[ $input == "https://"* ]] ; then
		if [[ $input == "https://i.imgur.com/"* ]] || [[ $input == "http://i.imgur.com/"* ]] ; then
			echo "INFO: image already on imugr" >&2
			_beep &
			_notify "ℹ️ Image already on imgur" "$input"
		else
			allurls="$allurls\n$input"
		fi
	else
		inputpath="$PWD/$input"
		if ! [[ -e "$inputpath" ]] ; then
			echo "ERROR: file missing or false input ($inputname)" >&2
			_beep &
			_notify "❓ File missing or false input" "$inputname"
			continue
		fi
		if ! echo "$inputname" | grep -q -i -e "\.png$" -e "\.jpg$" -e "\.jpeg$" -e "\.tif$" -e "\.tiff$" -e "\.gif$" -e "\.webp$" -e "\.apng$" -e "\.webm$" -e "\.mp4$" -e "\.m4v$" -e "\.avi$" &>/dev/null ; then # not a proper file type
			cfileicon="$tmpdir/$posixdate-$inputname-icon256.png"
			if file-icon "$input" --size 256 > "$cfileicon" &>/dev/null ; then
				allfiles="$allfiles\n$cfileicon"
			else
				echo "ERROR: wrong file format" >&2
				_beep &
				_notify "❌ Wrong file format!" "Not supported by imgur: $inputname"
				rm -f "$cfileicon" 2>/dev/null
			fi
		else
			allfiles="$allfiles\n$inputpath"
		fi
	fi

done

localimg=false
allfiles=$(echo -e "$allfiles" | grep -v "^$")
[[ $allfiles ]] && localimg=true
webimg=false
allurls=$(echo -e "$allurls" | grep -v "^$")
[[ $allurls ]] && webimg=true
allmulti=false
if $localimg && $webimg ; then
	allmulti=true
fi

uploadinfo=""

# upload web image(s)
webmulti=false
if $webimg ; then
	[[ $(echo "$allurls" | wc -l) -gt 1 ]] && webmulti=true
	while read -r url_raw
	do
		echo "URL (raw): $url_raw" >&2
		urlparent=$(dirname "$url_raw")
		urlname=$(basename "$url_raw")
		urlname=$(echo "$urlname" | sed -e 's/\.png\?.*$/\.png/' -e 's/\.jpg\?.*$/\.jpg/' -e 's/\.jpeg\?.*$/\.jpeg/' -e 's/\.apng\?.*$/\.apng/' -e 's/\.gif\?.*$/\.gif/' -e 's/\.tif\?.*$/\.tif/' -e 's/\.tiff\?.*$/\.tiff/' -e 's/\.webp\?.*$/\.webp/' -e 's/\.webm\?.*$/\.webm/' -e 's/\.m4v\?.*$/\.m4v/' -e 's/\.mp4\?.*$/\.mp4/' -e 's/\.avi\?.*$/\.avi/')
		url="$urlparent/$urlname"
		echo "URL: $url" >&2
		if ! echo "$urlname" | grep -q -i -e "\.png$" -e "\.jpg$" -e "\.jpeg$" -e "\.tif$" -e "\.tiff$" -e "\.gif$" -e "\.webp$" -e "\.apng$" -e "\.webm$" -e "\.mp4$" -e "\.m4v$" -e "\.avi$" &>/dev/null ; then # not a proper file type
			echo "ERROR: wrong file format" >&2
			_beep &
			_notify "❌ Wrong file format!" "Not supported by imgur: $inputname"
			continue
		fi
		# upload to imgur directly with cURL (only client ID needed for anonymous upload)
		webpimg=false
		pasted=false
		hasalpha=false
		if ! echo "$urlname" | grep -q -i "\.webp$" &>/dev/null ; then
			echo "Uploading to imgur directly..." >&2
			imgur_data=$(curl -k -L -s --connect-timeout 10 --request POST "https://api.imgur.com/3/image" -H "Authorization: Client-ID $client_id" -H "Expect: " -F "image=$url" 2>/dev/null)
			shareurl=$(echo "$imgur_data" | jq -r '.data.link')
		else
			webpimg=true
			echo "Downloading webp image for conversion..." >&2
			shareurl=""
		fi
		if [[ $shareurl != "https://i.imgur.com/"* ]] ; then # cURL error: download first, then again with cURL
			! $webpimg && echo "ERROR: direct upload with cURL" >&2
			uploadname="$posixdate-$urlname"
			uploadpath="$tmpdir/$uploadname"
			rm -f "$uploadpath" 2>/dev/null
			echo "Caching at: $uploadpath" >&2
			# download first
			if ! curl -o "$uploadpath" -k -L -s --connect-timeout 10 "$url" &>/dev/null ; then
				errors=true
				echo "ERROR: cURL exited with error" >&2
				_beep &
				_notify "⚠️ cURL: cache error!" "$urlname"
				rm -f "$uploadpath" 2>/dev/null
				if $webmulti || $allmulti ; then
					uploadinfo="$uploadinfo\nERROR|$urlname"
				fi
			else # upload from cache
				shareurl=$(_upload "$uploadpath" 2>/dev/null)
				if [[ $shareurl == "https://i.imgur.com/"* ]] ; then
					$bbcode && shareurl='[img]'"$shareurl"'[/img]'
					echo -n "$shareurl" | pbcopy
					_success &
					if $webmulti || $allmulti ; then
						_notify "✅ Uploaded" "$shareurl"
						if ! $bbcode ; then
							uploadinfo="$uploadinfo\n$shareurl|$urlname"
						else
							uploadinfo="$uploadinfo\n"'[img]'"$shareurl"'[/img]'"|$urlname"
						fi
					else
						_notify "✅ Uploaded & URL copied" "$shareurl"
					fi
					rm -f "$uploadpath" 2>/dev/null
				else
					if ! [[ $shareurl ]] ; then
						echo "ERROR: upload failed ($uploadname)" >&2
						errors=true
						_beep &
						_notify "❌ Upload failed!" "$uploadname"
						if $webmulti || $allmulti ; then
							uploadinfo="$uploadinfo\nERROR|$urlname"
						fi
						mv "$uploadpath" "$savedir/$uploadname" 2>/dev/null
					elif [[ $shareurl == "canceled" ]] ; then
						echo "User canceled" >&2
						rm -f "$uploadpath" 2>/dev/null
					else
						echo "Unknown condition: $shareurl" >&2
						mv "$uploadpath" "$savedir/$uploadname" 2>/dev/null
					fi
				fi
				osascript -e 'tell application "qlmanage" to quit' &>/dev/null
			fi
		else
			echo "Success: $shareurl" >&2
			$bbcode && shareurl='[img]'"$shareurl"'[/img]'
			echo -n "$shareurl" | pbcopy
			_success &
			if $webmulti || $allmulti ; then
				_notify "✅ Uploaded" "$shareurl"
				if ! $bbcode ; then
					uploadinfo="$uploadinfo\n$shareurl|$urlname"
				else
					uploadinfo="$uploadinfo\n"'[img]'"$shareurl"'[/img]'"|$urlname"
				fi
			else
				_notify "✅ Uploaded & URL copied" "$shareurl"
			fi
		fi
	done < <(echo "$allurls")
fi

# upload local image(s)
localmulti=false
if $localimg ; then
	[[ $(echo "$allfiles" | wc -l) -gt 1 ]] && localmulti=true
	while read -r uploadpath
	do
		pasted=false
		hasalpha=false
		echo "Accessing: $uploadpath" >&2
		uploadname=$(basename "$uploadpath")
		if [[ $uploadname == *"-pasteboard.tif" ]] ; then # convert TIF pasteboard exports to JPEG or PNG (if transparency)
			if [[ $(magick identify -format '%[channels]' "$uploadpath" 2>/dev/null ) == "srgba" ]] ; then
				echo "Converting to PNG..." >&2
				hasalpha=true
			else
				echo "Converting to JPEG..." >&2
			fi
			shortname="${uploadname%.*}"
			if ! $hasalpha ; then
				if ! sips -s format jpeg "$uploadpath" --out "$tmpdir/$shortname.jpg" &>/dev/null ; then
					errors=true
					echo "ERROR: conversion failed" >&2
					_beep &
					_notify "⚠️ Conversion error!" "Original saved to ~/Pictures/imgurAU"
					mv "$uploadpath" "$savedir/$uploadname"
					continue
				else
					pasted=true
					rm -f "$uploadpath" 2>/dev/null
					uploadname="$shortname.jpg"
					uploadpath="$tmpdir/$uploadname"
				fi
			else
				if ! sips -s format png "$uploadpath" --out "$tmpdir/$shortname.png" &>/dev/null ; then
					errors=true
					echo "ERROR: conversion failed" >&2
					_beep &
					_notify "⚠️ Conversion error!" "Original saved to ~/Pictures/imgurAU"
					mv "$uploadpath" "$savedir/$uploadname"
					continue
				else
					pasted=true
					rm -f "$uploadpath" 2>/dev/null
					uploadname="$shortname.png"
					uploadpath="$tmpdir/$uploadname"
				fi
			fi
		elif [[ $uploadname == *"-icon256.png" ]] ; then
			pasted=true
		fi
		# upload
		shareurl=$(_upload "$uploadpath" 2>/dev/null)
		if [[ $shareurl == "https://i.imgur.com/"* ]] ; then
			echo "Success: $shareurl ($uploadname)" >&2
			$bbcode && shareurl='[img]'"$shareurl"'[/img]'
			echo -n "$shareurl" | pbcopy
			_success &
			if $localmulti || $allmulti ; then
				_notify "✅ Uploaded" "$shareurl"
				if ! $bbcode ; then
					uploadinfo="$uploadinfo\n$shareurl|$uploadname"
				else
					uploadinfo="$uploadinfo\n"'[img]'"$shareurl"'[/img]'"|$uploadname"
				fi
			else
				_notify "✅ Uploaded & URL copied" "$shareurl"
			fi
			if [[ $(dirname "$uploadpath") == "$tmpdir" ]] ; then
				echo "Removing temporary file" >&2
				rm -f "$uploadpath" 2>/dev/null
			fi
			if $sg_def && [[ $(dirname "$uploadpath") == "$sg_loc" ]] ; then
				echo "Asking user to move snapshot to trash" >&2
				_trash "$uploadpath"
			fi
		else
			$pasted && rm -f "$uploadpath"
			if ! [[ $shareurl ]] ; then
				echo "ERROR: upload failed ($uploadname)" >&2
				errors=true
				_beep &
				_notify "❌ Upload failed!" "$uploadname"
				if $localmulti || $allmulti ; then
					uploadinfo="$uploadinfo\nERROR|$uploadname"
				fi
			elif [[ $shareurl == "canceled" ]] ; then
				echo "User canceled" >&2
			else
				echo "Unknown condition: $shareurl" >&2
			fi
		fi
		osascript -e 'tell application "qlmanage" to quit' &>/dev/null
	done < <(echo "$allfiles")
fi

if $webmulti || $localmulti || $allmulti ; then
	if $errors ; then
		_notify "⚠️ There were errors!"
	fi
	uploadinfo=$(echo -e "$uploadinfo" | grep -v "^$")
	if [[ $uploadinfo ]] ; then
		echo "Writing results to info file: $links_loc" >&2
		echo "$uploadinfo" > "$links_loc"
		sleep .5
		open "$links_loc"
	fi
fi

osascript -e 'tell application "qlmanage" to quit' &>/dev/null

exit
