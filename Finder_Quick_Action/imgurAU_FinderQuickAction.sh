# Automator | "Run Shell Script" | Shell: /bin/zsh | pass input as arguments

# imgurAU
# macOS Finder Quick Action

export LANG=en_US.UTF-8
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/local/bin:/opt/homebrew/bin:/opt/sw/bin:"$HOME"/.local/bin:"$HOME"/bin:"$HOME"/local/bin

if ! [[ $* ]] ; then
	imgur-au.sh &
else
	imgur-au.sh "$@" &
fi
exit
