#!/bin/zsh
# shellcheck shell=bash

# imgur-au.sh
# v0.9.14 beta
#
# imgurAU
# imgur Anonymous Uploader
#
# Copyright (c) 2021 Joss Brown (pseud.)
# License: MIT
# Place of jurisdiction: Berlin / German laws apply
#
# requisites:
# exiftool - https://exiftool.org
# imguru - https://github.com/FigBug/imguru (also available in the imgurAU repository)
# pbv - https://github.com/chbrown/macos-pasteboard (also available in the imgurAU repository)
# trash - https://github.com/sindresorhus/macos-trash (available via Homebrew)
#
# optional:
# EventScripts - https://www.mousedown.net/software/EventScripts.html (available via the Mac App Store)
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
client_id="51f229880e3ea84" # imguru ID: fallback for cURL (imguru does not support web upload)

# logging
logloc="/tmp/$procid.log"
currentdate=$(date)
if ! [[ -f $logloc ]] ; then
	echo "++++++++ $currentdate ++++++++" > "$logloc"
else
	echo -e "\n++++++++ $currentdate ++++++++" >> "$logloc"
fi
exec > >(tee -a "$logloc") 2>&1

snapshots=false
# check for macOS app Snap Shot
if pgrep -x "screencaptureui" &>/dev/null ; then
	echo "macOS Snap Shot is running"
	snapshots=true
	# check for EventScripts app
	if pgrep -x "EventScripts" &>/dev/null ; then
		echo "EventScripts is running: overriding Snap Shot"
		snapshots=false
	fi
fi

# read screenshot location
sg_def=true
sg_loc=$(/usr/libexec/PlistBuddy -c "Print:location" "$HOME/Library/Preferences/com.apple.screencapture.plist" 2>/dev/null)
! [[ $sg_loc ]] && sg_loc=$(defaults read "com.apple.screencapture" location 2>/dev/null)
if ! [[ $sg_loc ]] ; then
	echo "WARNING: no screenshot directory defined"
	sg_def=false
else
	echo "Screenshot location: $sg_loc"
	if $snapshots ; then
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
	imguru
	pbv
	trash
EOR

# check for requisites
reqerror=false
while read -r req
do
	if ! command -v "$req" &>/dev/null ; then
		echo "ERROR: $req not installed"
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
		echo -n "$frontmost"
	fi
}

# check & arrange input first
if [[ $* ]] ; then # input arguments
	echo "Input (raw): $*"
	if [[ $1 == "internal-snapshot" ]] ; then
		img_newest=$(find "$sg_loc" -mindepth 1 -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.jpeg' -o -name '*.tif' -o -name '*.tiff' -o -name '*.apng' -o -name '*.gif' \) -print0 2>/dev/null | xargs -r -0 ls -1 -t | head -1 | grep -v "^$")
		if [[ $img_newest ]] ; then # screenshot file found
			shift $#
			set -- "$@" "$img_newest"
		else # no screenshot file found
			echo "ERROR: screenshot directory empty - asking user..."
			shift $#
			set -- "$@" "internal-select screenshots"
		fi
	else
		if echo "$*" | grep -q "net\.mousedown\.EventScripts" &>/dev/null ; then # EventScripts event
			echo "Detected EventScripts input"
			if $sg_def ; then # screenshot folder is known
				checkname=$(echo "$*" | sed 's/^Screenshot taken *//' | awk -F" /" '{print $1}')
				if ! [[ $checkname ]] ; then # parse error (filename)
					echo "ERROR: couldn't parse for screenshot filename'"
					shift $#
					set -- "$@" "internal-select screenshots"
				else # name OK
					echo "Screenshot filename: $checkname"
					if ! [[ -f "$sg_loc/$checkname" ]] ; then # false alarm by EventScripts
						echo "ERROR: screenshot removed - exiting..."
						exit
					else # new screenshot created
						shift $#
						set -- "$@" "$sg_loc/$checkname"
					fi
				fi
			else # screenshot folder is unknown
				echo "ERROR: no screenshot directory specified - asking user..."
				shift $#
				set -- "$@" "internal-select"
			fi
		else # normal input
			echo "Generic input: filepath(s) or URL"
		fi
	fi
else # no input arguments
	echo "No input: checking frontmost document..."
	frontdoc=$(_frontmost 2>/dev/null)
	if [[ $frontdoc ]] ; then
		echo -e "Detected Document: $frontdoc\nAppending to input..."
		shift $#
		set -- "$@" "$frontdoc"
	else
		echo "No document: checking pasteboard..."
		pasteboard=$(pbpaste 2>/dev/null) # check for URLs first
		if [[ $pasteboard == "http://"* ]] || [[ $pasteboard == "https://"* ]] ; then # URL detected (check later)
			echo "Detected URL: appending to input..."
			shift $#
			set -- "$@" "$pasteboard"
		else # no URLs
			posixdate=$(date +%s)
			pbfile="$tmpdir/$posixdate-pasteboard.tif"
			rm -f "$pbfile" 2>/dev/null
			if ! pbv public.tiff > "$pbfile" &>/dev/null ; then # no image file in pasteboard
				rm -f "$pbfile" 2>/dev/null
				echo "NOTE: no valid pasteboard content"
			else # image file in pasteboard & exported
				echo -e "Image data exported to temp TIFF: $posixdate-pasteboard.tif\nAppending to input..."
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

# prompt with image: ask user for upload without "select other" option
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
		osascript -e 'tell application "qlmanage" to quit' &>/dev/null
	fi
	echo -n "$uploadchoice"
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
	echo -n "$exifchoice"
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
		of type {"png", "jpg", "jpeg", "gif", "tif", "tiff", "apng", "webm", "mp4", "m4v", "avi"} ¬
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
		of type {"png", "jpg", "jpeg", "gif", "tif", "tiff", "apng", "webm", "mp4", "m4v", "avi"} ¬
		default location theDefaultPath)
end tell
theUploadImage
EOS
		)
	fi
	echo -n "$imgpathchoice"
}

# file checks & conversions (size/format)
_check-file () {
	checkpath="$1"
	checkname=$(basename "$checkpath")
	fsize=$(stat -f%z "$checkpath" 2>/dev/null) # general file size check
	echo "File size: $fsize" >&2
	if ! [[ $fsize ]] || [[ $fsize -eq 0 ]] ; then
		_beep &
		_notify "⚠️ Error: no file content!" "$checkname"
		echo "ERROR: no file content" >&2
		echo -n "error"
		return
	fi
	suffix="${checkname##*.}"
	echo "Extension: $suffix" >&2
	abort=false
	# check file sizes relative to formats for imgur support
	if [[ $suffix =~ ^(gif|GIF)$ ]] ; then
		[[ $fsize -gt "$gifmax" ]] && abort=true
	else
		[[ $fsize -gt "$othermax" ]] && abort=true
	fi
	if $abort ; then
		_beep &
		_notify "⚠️ Error: file too large!" "$checkname"
		echo "ERROR: file too large" >&2
		echo -n "error"
		return
	fi
	# potential format conversion (into temp dir)
	if [[ $suffix =~ ^(png|PNG)$ ]] && [[ $fsize -gt "$pngmax" ]] ; then
		echo "Converting PNG to JPEG..." >&2
		shortcheckname="${checkname%.*}"
		tempcheckname="$posixdate-$shortcheckname.jpg"
		if sips -s format jpeg "$checkpath" --out "$tmpdir/$tempcheckname" &>/dev/null ; then
			echo -n "$tmpdir/$tempcheckname"
		else
			_beep &
			_notify "⚠️ Error: conversion failed!" "$checkname"
			rm -f "$tmpdir/$tempcheckname" 2>/dev/null
			echo "ERROR: conversion failed" >&2
			echo -n "error"
		fi
	fi
}

_upload () {
	fuploadpath="$1"
	converted=false
	cleaned=false
	
	if $pasted || [[ $(dirname "$fuploadpath") != "$tmpdir"* ]] ; then
		uchoice=$(_ask-upload "$fuploadpath" 2>/dev/null)
		if ! [[ $uchoice ]] || [[ $uchoice == "false" ]] ; then
			echo "User canceled" >&2
			echo "canceled"
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
			echo "User canceled" >&2
			$converted && rm -f "$imgcheck" 2>/dev/null
			rm -f "$exifpath" 2>/dev/null
			echo "canceled"
			return
		fi
	fi
	
	imgur_url=$(imguru "$fuploadpath" 2>/dev/null | grep -v "^$")
	if [[ $imgur_url == "https://i.imgur.com/"* ]] ; then
		echo -n "$imgur_url"
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
			echo "ERROR: couldn't move screenshot to Trash - removing instead"
			rm -f "$trashfile" 2>/dev/null
		else
			echo "Screenshot moved to the Trash"
		fi
	else
		echo "User chose to keep the screenshot"
	fi
}

# auxiliary routine without input arguments
if ! [[ $* ]] ; then
	echo "No final input: asking user..."
	uploadpaths=$(_select-image multi "$HOME/Pictures" 2>/dev/null)
	if ! [[ $uploadpaths ]] ; then
		echo "User canceled."
		exit
	fi
	if [[ $(echo "$uploadpaths" | wc -l) -gt 1 ]] ; then # multiple files selected: upload right here
		uploadinfo=""
		errors=false
		while read -r uploadpath
		do
			echo "Accessing: $uploadpath"
			uploadname=$(basename "$uploadpath")
			shareurl=$(_upload "$uploadpath" 2>/dev/null)
			if [[ $shareurl == "https://i.imgur.com/"* ]] ; then
				echo "Success: $shareurl ($uploadname)"
				uploadinfo="$uploadinfo\n$shareurl:$uploadname"
				_notify "✅ Upload successful" "$shareurl ($uploadname)"
			else
				if ! [[ $shareurl ]] ; then
					echo "ERROR: upload: $uploadname"
					uploadinfo="$uploadinfo\nERROR:$uploadname"
					_notify "❌ Upload failed!" "$uploadname"
					errors=true
				elif [[ $shareurl == "canceled" ]] ; then
					echo "User canceled"
				else
					echo "Unknown condition: $shareurl"
				fi
			fi
		done < <(echo "$uploadpaths")
		if $errors ; then
			_beep &
		else
			_success &
		fi
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
		echo "User canceled"
		exit
	fi
	shift $#
	set -- "$@" "$selection"
fi

# main routines with input or re-organized input
echo "Final input (raw): $*"

errors=false
allfiles=""
allurls=""
for input in "$@"
do
	! [[ $input ]] && continue
	
	# check extension first
	if ! echo "$input" | grep -q -i -e "\.png$" -e "\.jpg$" -e "\.jpeg" -e "\.tif$" -e "\.tiff$" -e "\.gif$" -e "\.apng" -e "\.webm" -e "\.mp4" -e "\.m4v" -e "\.avi" &>/dev/null ; then # not a proper file type
		inputname=$(basename "$input")
		echo "ERROR: wrong file format"
		_beep &
		_notify "❌ Wrong file format!" "Not supported by imgur: $inputname"
		continue
	fi

	# check for proper input
	if [[ $input == "/"* ]] ; then
		inputname=$(basename "$input")
		if ! [[ -f "$input" ]] ; then
			echo "ERROR: file missing ($inputname)"
			_beep &
			_notify "❓ File missing" "$inputname"
		else
			allfiles="$allfiles\n$input"
		fi
	elif [[ $input == "http://"* ]] || [[ $input == "https://"* ]] ; then
		if [[ $input == "https://i.imgur.com/"* ]] || [[ $input == "http://i.imgur.com/"* ]] ; then
			echo "INFO: image already on imugr"
			_beep &
			_notify "ℹ️ Image already on imgur" "$input"
		else
			allurls="$allurls\n$input"
		fi
	else
		inputpath="$PWD/$input"
		if [[ -f "$inputpath" ]] ; then
			allfiles="$allfiles\n$inputpath"
		else
			echo "ERROR: file missing or false input ($inputname)"
			inputname=$(basename "$inputpath")
			_beep &
			_notify "❓ File missing or false input" "$inputname"
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
	while read -r url
	do
		echo "URL: $url" ### cleanup URL? needs testing
		urlname=$(basename "$url")
		# imguru doesn't support URL input: upload to imgur directly with cURL and imguru's OAuth key
		echo "Uploading to imgur directly..."
		imgur_raw=$(curl -k -L -s --connect-timeout 10 -H "Authorization: Client-ID $client_id" -H "Expect: " -F "image=$url" "https://api.imgur.com/3/image.xml" 2>/dev/null)
		shareurl=$(echo "$imgur_raw" | tail -n +2 | awk -F"<link>" '{print $NF}' | awk -F"</link>" '{print $1}' 2>/dev/null)
		if [[ $shareurl != "https://i.imgur.com/"* ]] ; then # cURL error: download first, then upload with imguru
			echo "ERROR: direct upload with cURL"
			uploadname="$posixdate-$urlname"
			uploadpath="$tmpdir/$uploadname"
			rm -f "$uploadpath" 2>/dev/null
			echo "Caching at: $uploadpath"
			# download first
			if ! curl -o "$uploadpath" -k -L -s --connect-timeout 10 "$url" &>/dev/null ; then
				errors=true
				echo "ERROR: cURL exited with error"
				_beep &
				_notify "⚠️ cURL: cache error!" "$urlname"
				rm -f "$uploadpath" 2>/dev/null
				if $webmulti || $allmulti ; then
					uploadinfo="$uploadinfo\nERROR:$urlname"
				fi
			else # upload from cache
				shareurl=$(_upload "$uploadpath" 2>/dev/null)
				if [[ $shareurl == "https://i.imgur.com/"* ]] ; then
					echo -n "$shareurl" | pbcopy
					_success &
					if $webmulti || $allmulti ; then
						_notify "✅ Uploaded" "$shareurl"
						uploadinfo="$uploadinfo\n$shareurl:$urlname"
					else
						_notify "✅ Uploaded & URL copied" "$shareurl"
					fi
				else
					if ! [[ $shareurl ]] ; then
						errors=true
						_beep &
						_notify "❌ Upload failed!" "$uploadname"
						if $webmulti || $allmulti ; then
							uploadinfo="$uploadinfo\nERROR:$urlname"
						fi
					elif [[ $shareurl == "canceled" ]] ; then
						echo "User canceled"
					else
						echo "Unknown condition: $shareurl"
					fi
				fi
			fi
		else
			echo "Success: $shareurl"
			echo -n "$shareurl" | pbcopy
			_success &
			if $webmulti || $allmulti ; then
				_notify "✅ Uploaded" "$shareurl"
				uploadinfo="$uploadinfo\n$shareurl:$urlname"
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
		echo "Accessing: $uploadpath"
		uploadname=$(basename "$uploadpath")
		if [[ $uploadname == *"-pasteboard.tif" ]] ; then # convert TIF pasteboard exports to JPEG
			echo "Converting to JPEG..."
			shortname="${uploadname%.*}"
			if ! sips -s format jpeg "$uploadpath" --out "$tmpdir/$shortname.jpg" &>/dev/null ; then
				errors=true
				echo "ERROR: conversion failed"
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
		fi
		# upload
		shareurl=$(_upload "$uploadpath" 2>/dev/null)
		if [[ $shareurl == "https://i.imgur.com/"* ]] ; then
			echo "Success: $shareurl ($uploadname)"
			echo -n "$shareurl" | pbcopy
			_success &
			if $localmulti || $allmulti ; then
				_notify "✅ Uploaded" "$shareurl"
				uploadinfo="$uploadinfo\n$shareurl:$uploadname"
			else
				_notify "✅ Uploaded & URL copied" "$shareurl"
			fi
			if [[ $(dirname "$uploadpath") == "$tmpdir" ]] ; then
				echo "Removing temp "
				rm -f "$uploadpath" 2>/dev/null
			fi
			if $sg_def && [[ $(dirname "$uploadpath") == "$sg_loc" ]] ; then
				echo "Asking user to move snapshot to trash"
				_trash "$uploadpath"
			fi
		else
			$pasted && rm -f "$uploadpath"
			if ! [[ $shareurl ]] ; then
				echo "ERROR: upload failed ($uploadname)"
				errors=true
				_beep &
				_notify "❌ Upload failed!" "$uploadname"
				if $localmulti || $allmulti ; then
					uploadinfo="$uploadinfo\nERROR:$uploadname"
				fi
			elif [[ $shareurl == "canceled" ]] ; then
				echo "User canceled"
			else
				echo "Unknown condition: $shareurl"
			fi
		fi
	done < <(echo "$allfiles")
fi

if $webmulti || $localmulti || $allmulti ; then
	if $errors ; then
		_notify "⚠️ There were errors!"
	fi
	uploadinfo=$(echo -e "$uploadinfo" | grep -v "^$")
	if [[ $uploadinfo ]] ; then
		echo "Writing results to info file: $links_loc"
		echo "$uploadinfo" > "$links_loc"
		sleep .5
		open "$links_loc"
	fi
fi

exit
