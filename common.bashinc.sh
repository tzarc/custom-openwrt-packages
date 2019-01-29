# Errors and permissions...
set -e
umask 022

# Useful parameters...
export script_dir=$(readlink -f "$(dirname "$this_script")")
export temp_dir="$script_dir/.temp"

# Re-exec with a clean environment...
[ -z "$INVOKE_INTERNAL" ] \
	&& cd "$script_dir" \
	&& exec env -i HOME="$HOME" PATH="/usr/local/bin:/usr/bin:/bin" USER="$USER" TERM="linux" INVOKE_INTERNAL=1 LC_ALL=C DISPLAY="$DISPLAY" /bin/bash "$this_script" "$@"
unset INVOKE_INTERNAL

# Argument parsing
declare -a script_args=()
while [[ "$#" -gt "0" ]] ; do
	script_args+=($1)
	shift
done

# Helpers
echo_fail() { echo -e "\e[0;37m[\e[1;31mFAIL\e[0;37m]\e[0m $@" 1>&2; return 0; }
nsudo() { [[ "$EUID" -ne "0" ]] && echo "sudo" ; true ; }
havecmd()  { command command type "$1" >/dev/null 2>&1 || return 1 ; }

pkgfind() {
	find "$script_dir/package" \( "$@" \) -print | sort
}

extrafind() {
	find "$script_dir/extra-files/" \( "$@" \) -print | sort
}

repofind() {
	find "$script_dir" -mindepth 1 -not -path '*/.git/*' -and -not -path '*/.temp/*' \( "$@" \) -print | sort
}

header() {
	echo >&2
	echo -e "\e[1;30m##----------------------------------------------------------------------------------------\e[0m" >&2
	echo -e "\e[1;30m##\e[0m \e[1;36m$@\e[0m" >&2
}

rcmd() {
	header "Executing:"
	echo -e "\e[1;30m##\e[0m	\e[0;36m$@\e[0m" >&2
	"$@"
}

download() {
	local url=$1
	local filename=$2
	[ ! -d "$(dirname "$filename")" ] && mkdir -p "$(dirname "$filename")"
	if havecmd aria2c ; then
		rcmd aria2c -d "$(dirname "$filename")" -o "$(basename "$filename")" -j5 -x5 -s5 "$url"
	elif havecmd curl ; then
		rcmd curl -L "$url" > "$filename"
	elif havcmd wget ; then
		rcmd wget -O "$filename" "$url"
	else
		echo_fail "Could not find appropriate application for downloading URLs. Exiting." >&2
		exit 1
	fi
}

download_to_file() {
	local url=$1
	local outfile=$2

	echo "Getting '${url}'..." >&2
	if [[ ! -f "${outfile}" ]] ; then
		download "${url}" "${outfile}"
	fi
	if [[ ! -f "${outfile}" ]] ; then
		echo "Could not find '${outfile}'. Exiting." >&2
		exit 1
	fi
}

download_extract_zip() {
	local url=$1
	local outfile=$2
	local outdir=$3

	download_to_file "${url}" "${outfile}"
	echo "Extracting files..." >&2
	[[ ! -d "${outdir}" ]] && mkdir -p "${outdir}"
	rcmd unzip -o "${outfile}" -d "${outdir}" >/dev/null
}

# Usage screen builder
usage() {
	local width=20
	local -a command_list=( $(set | awk '/^script_command_exec.* \(\)/ {print $1}' | sed -e 's#script_command_exec_##' | sort) )
	local -a short_list
	for cmd in ${command_list[@]} ; do
		local this_cmd="--$cmd"
		local short_cmd="$this_cmd"
		local argvar="script_command_has_arg_$cmd"
		[[ ! -z "${!argvar}" ]] && short_cmd="$short_cmd=<${!argvar}>"
		local optvar="script_command_is_optional_$cmd"
		[[ ! -z "${!optvar}" ]] && short_cmd="[$short_cmd]"
		short_list+="$short_cmd "
	done

	echo "Usage:" >&2
	echo "	$(basename "$this_script")" "${short_list[@]}" >&2
	echo >&2
	for cmd in ${command_list[@]} ; do
		local this_cmd="--$cmd"
		local cmd_flags=""
		local argvar="script_command_has_arg_$cmd"
		local -a possible_args
		if [[ ! -z "${!argvar}" ]] ; then
			this_cmd="$this_cmd=<${!argvar}>"
			possible_args=( $(script_command_args_$cmd 2>/dev/null) )
		fi
		printf -- "%${width}s: %s\n" "$this_cmd" "$(script_command_desc_$cmd 2>/dev/null)"
		if [[ ${#possible_args[@]} -gt 0 ]] ; then
			printf -- "%${width}s  %s\n" "" "Allowed ${!argvar}:"
			for arg in ${possible_args[@]} ; do
				printf -- "%${width}s %s\n" "" "        $arg"
			done
		fi
	done
}

# Command executor
exec_command_arg() {
	case "$1" in
		(--*=*)
			N=${1%%=*}
			N=${N##--}
			V=${1##*=}
			"script_command_exec_$N" "$V"
			;;
		(--*)
			N=${1##--}
			"script_command_exec_$N"
			;;
		(-*)
			echo_fail "ERROR: unrecognised option $1"
			exit 1
			;;
		(*)
			break
			;;
	esac
}
exec_command_args() {
	for cmd in ${script_args[@]} ; do
		exec_command_arg "$cmd"
	done
}

# Exit code handling
export script_rc=1
_internal_cleanup() {
	if [ "$(type -t cleanup)" == "function" ] ; then
		{ cleanup; }
	fi
	exit $script_rc
}
trap _internal_cleanup EXIT HUP INT

##########################################################################################

script_command_is_optional_help=1
script_command_desc_help() { echo "Shows help screen." ; }
script_command_exec_help() {
	usage
}
