#!/bin/bash

export this_script=$(readlink -f "${BASH_SOURCE[0]}")
source common.bashinc.sh

# Overrides...
export target_dir="$script_dir/ipk"

# No args => build
if [ "${#script_args[@]}" -eq "0" ] ; then
	script_args+=(--build)
fi

# Signing keys
signfile_key="$script_dir/pkg-signing.sec"
signfile_pub="$script_dir/pkg-signing.pub"
signfile_target="$target_dir/tzarc_custom.pub"
if [ ! -e "$signfile_key" ] || [ ! -e "$signfile_pub" ]; then
	echo_fail "Missing package signing keys."
	echo "Either place existing keys in the following locations:"
	echo "    Private key: $signfile_key"
	echo "     Public key: $signfile_pub"
	echo "Or generate new keys using:"
	echo "    signify-openbsd -G -s $signfile_key -p $signfile_pub -n"
	exit 1
fi

# SDK...
sdk_url="https://downloads.openwrt.org/releases/18.06.1/targets/x86/64/openwrt-sdk-18.06.1-x86-64_gcc-7.3.0_musl.Linux-x86_64.tar.xz"
sdk_file="$temp_dir/sdk.tar.xz"
sdk_dir="$temp_dir/sdk"
get_openwrt_sdk() {
	if [ ! -f "$sdk_dir/Makefile" ] ; then
		[ ! -f "$sdk_file" ] && download "$sdk_url" "$sdk_file"
		[ ! -d "$sdk_dir" ] && mkdir -p "$sdk_dir"
		tar -xf "$sdk_file" -C "$sdk_dir" --strip-components=1
	fi
	[ ! -L "$sdk_dir/key-build" ] && ln -sf "$signfile_key" "$sdk_dir/key-build" || true
}

# Misc...
remove_old_packages() {
	[[ -d "$target_dir" ]] && find "$target_dir" -type f -delete || true
}

# Packaging...
build_one_package() {
	local pkg=$1
	[[ ! -L "$sdk_dir/package/$pkg" ]] && ln -sf "$script_dir/package/$pkg" "$sdk_dir/package/$pkg"
	header "Building $pkg"
	pushd "$sdk_dir" >/dev/null 2>&1
	rcmd make defconfig >/dev/null 2>&1
	rcmd make "package/$pkg/clean" #V=99
	rcmd make "package/$pkg/compile" #V=99
	popd >/dev/null 2>&1
}

# Signing...
sign_packages() {
	header "Signing packages..."
	pushd "$sdk_dir" >/dev/null 2>&1
	rcmd make package/index
	popd >/dev/null 2>&1
}

# Copy packages to target directory...
copy_packages() {
	rcmd find "$sdk_dir/bin/packages/x86_64/base" -type f -print -exec cp '{}' "$target_dir" \;
}

# Verify packages given the supplied key...
verify_packages() {
	local target_file="$target_dir/Packages"
	[ ! -f "$signfile_target" ] && cat "$signfile_pub" > "$signfile_target" || true
	header "Verifying '$target_file'..."
	verify_result="$(signify-openbsd -V -p "$signfile_target" -m "$target_file" -x "$target_file.sig")"
	[ "$?" -ne "0" ] && { echo_fail "Failed to verify '$target_file'"; exit 1; } || echo "Verify ok."
}

##########################################################################################

# build function...
script_command_is_optional_build=1
script_command_desc_build() { echo "Builds all packages." ; }
script_command_exec_build() {
	[[ ! -d "$target_dir" ]] && mkdir -p "$target_dir" || true
	remove_old_packages
	get_openwrt_sdk

	for pkg in $(ls "$script_dir/package") ; do
		build_one_package "$pkg"
	done

	sign_packages
	copy_packages
	verify_packages

	[[ -e "$script_dir/deploy.sh" ]] \
		&& /usr/bin/env bash "$script_dir/deploy.sh"
}

# clean function...
script_command_is_optional_clean=1
script_command_desc_clean() { echo "Clears built ipk's, removes temporary directory." ; }
script_command_exec_clean() {
	[[ -d "$target_dir" ]] && rm -rf --one-file-system "$target_dir" || true
	[[ -d "$temp_dir" ]] && rm -rf --one-file-system "$temp_dir" || true
}

##########################################################################################

# Main entrypoint...
exec_command_args
export script_rc=0
