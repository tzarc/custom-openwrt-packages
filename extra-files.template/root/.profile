export TERM=screen-256color-bce
alias l='ls -1al'
alias psx='ps w'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias lr="logread -l200 -f"

rst() {
	__count=0
	__services="dnsmasq unbound zerotier firewall vpn-policy-routing"
	for __svc in $__services ; do
		eval "export __var$__count=$__svc"
		__count=$(( $__count + 1 ))
	done
	for __i in $(seq 1 $__count) ; do
		eval "export __var=\$__var$(( $__i - 1 ))"
		echo "Stopping ${__var}..."
		/etc/init.d/$__var stop
	done
	echo "---"
	for __i in $(seq $__count -1 1) ; do
		eval "export __var=\$__var$(( $__i - 1 ))"
		eval "unset __var$(( $__i - 1 ))"
		echo "Starting ${__var}..."
		/etc/init.d/$__var start
	done
	unset __var __svc __services __count __i
}

hl() {
	local pattern="$1"
	local colour="${2:-31}"
	case "$colour" in
		red) colour=31;;
		green) colour=32;;
		yellow) colour=33;;
		blue) colour=34;;
		pink|magenta) colour=35;;
		cyan) colour=36;;
		white) colour=37;;
		*);;
	esac
	sed "s/${pattern}/$(echo -e "\e[1;${colour}m")\\0$(echo -e "\e[0m")/g"
}

##################
# tmux
tmux_wrapper() {
	if [[ -z $1 ]]; then
		echo "Specify session name as the first argument"
		exit
	fi

	local base_session=$1
	local num_sessions=$(echo $(tmux ls | grep "^$base_session" | wc -l))

	# If no sessions are active, create the base session and automatically detach
	if [[ "$num_sessions" == "0" ]]; then
		echo "Launching tmux base session $base_session..."
		tmux -u2 new-session -d -s $base_session
	fi

	# Create a connection-specific session
	local this_session="$1/$(date +%s)"
	exec tmux -u2 \
		new-session -d -t "$base_session" -s "$this_session" \; \
		set-option destroy-unattached on \; \
		attach-session -t "$this_session"
}

if [ ! -z "$SSH_CONNECTION" -a -z "$TMUX" -a -z "$NOTMUX" ] ; then
	which tmux >/dev/null 2>&1
	if [[ $? == 0 ]] ; then
		read -t 1 -n 1 -s -p "Press 'X' to skip loading tmux... "
		if [[ -z "$REPLY" ]] ; then
			tmux_wrapper "$USER@$(uci -q get system.@system[0].hostname)"
		else
			export NOTMUX=1
		fi
	fi
fi

[ ! -z "$TMUX" ] \
	&& eval $(tmux switch-client \; show-environment -s)
