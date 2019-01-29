#!/bin/bash

export this_script=$(readlink -f "${BASH_SOURCE[0]}")
source common.bashinc.sh

# No args => clean
if [ "${#script_args[@]}" -eq "0" ] ; then
	script_args+=(--clean)
fi

check_dependencies() {
	if [[ "$(uname -s)" == "Linux" ]] ; then
		if havecmd apt-get ; then # Debian / Ubuntu etc.
			if ! havecmd parallel ; then $(nsudo) apt-get install parallel; fi
			if ! havecmd dos2unix ; then $(nsudo) apt-get install dos2unix; fi
			if ! havecmd luarocks ; then $(nsudo) apt-get install luarocks; fi
		fi

		export PATH="$PATH:$HOME/.luarocks/bin"
		if havecmd luarocks && ! havecmd luaformatter ; then
			luarocks install --local formatter
			luarocks install --local checks
		fi
	fi

	if ! havecmd dos2unix || ! havecmd parallel || ! havecmd luaformatter ; then
		echo_fail "Aborting cleanup, missing dependencies."
		exit 1
	fi
}

##########################################################################################

script_command_is_optional_clean=1
script_command_desc_clean() { echo "Fixes up permissions and reformats files." ; }
script_command_exec_clean() {
	check_dependencies

	# Make sure everything has Unix line endings
	pkgfind -type f | parallel "dos2unix '{1}' >/dev/null 2>&1"
	extrafind -type f | parallel "dos2unix '{1}' >/dev/null 2>&1"

	# Remove trailing whitespace
	pkgfind -iname '*.lua' -or -iname '*.sh' | parallel "sed -i 's/[ \t]*\$//' '{1}'"
	extrafind -iname '*.lua' -or -iname '*.sh' | parallel "sed -i 's/[ \t]*\$//' '{1}'"

	# Reformat lua files
	pkgfind -iname '*.lua' | parallel "echo \"Formatting '{1}'\" && luaformatter -a -t1 '{1}'"
	extrafind -iname '*.lua' | parallel "echo \"Formatting '{1}'\" && luaformatter -a -t1 '{1}'"

	# Fix permissions
	repofind -type d | parallel 'chmod 755 "{1}"'
	repofind -type f | parallel 'chmod 644 "{1}"'
	repofind -type f -name '*.sh' | parallel 'chmod 755 "{1}"'
	pkgfind -type f -and \( -path '*/init.d/*' -or -path '*/bin/*' \) | parallel 'chmod +x "{1}"'

	# Set up this script as a git precommit hook if git directory is present
	if [[ -d "$script_dir/.git" ]] ; then
		if [[ ! -L "$script_dir/.git/hooks/pre-commit" ]] ; then
			(cd "$script_dir/.git/hooks" && ln -sf ../../cleanup.sh pre-commit)
		fi

		# Drop out of "git commit" if there are any uncommitted changes after the cleanup.
		if [[ ! -z "$(echo "${BASH_SOURCE[@]}" | grep "pre-commit")" ]] ; then
			[[ -z "$(git diff)" ]] || { echo_fail "Aborting commit: 'git diff' says changes are still present."; exit 1; }
		fi
	fi
}

##########################################################################################

exec_command_args
export script_rc=0
