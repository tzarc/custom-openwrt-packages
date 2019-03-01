#!/bin/bash

export this_script=$(readlink -f "${BASH_SOURCE[0]}")
source common.bashinc.sh

# Overrides...
export target_dir="$script_dir/img"
export default_version="18.06.2"
declare -a supported_versions=( master 18.06.2 )

# No args => help
if [ "${#script_args[@]}" -eq "0" ] ; then
	script_args+=(--help)
fi

##########################################################################################

get_variants() {
    find "$script_dir/variants/" -mindepth 1 -maxdepth 1 -type f -name 'variant.*' | while read -r variant_file ; do
        echo "$(basename "$variant_file")" | sed -e 's@variant\.@@g'
    done | sort
}

load_variant_definition() {
	local variant="$1"
	pushd "$script_dir/variants/" >/dev/null
	source "$script_dir/variants/variant.$variant"
	popd >/dev/null
}

chain_build_one_variant() {
	local variant="$1"
	/bin/bash "$this_script" --version="$target_version" --variant="$variant"
}

build_one_variant() {
	local variant="$1"
	export build_variant="$variant"
	export device_directory="$script_dir/.temp/variant-$variant-$target_version"
	header "Building variant '$variant'..."
	load_variant_definition "$variant"

	get_imagebuilder
	setup_extra_repos
	deploy_extra_files

	pushd "$device_directory" >/dev/null
	rcmd make image PROFILE="$DEVICE_PROFILE" FILES=files/ PACKAGES="$BASE_PACKAGES $DEVICE_PACKAGES $CUSTOM_PACKAGES"
	popd >/dev/null

	# Collect the sysupgrade binaries, copy to output directory
	local build_version=$(<$(find "$device_directory"/build_dir/ -name openwrt_version | head -n1))
	[[ ! -d "$target_dir" ]] && mkdir -p "$target_dir" || true

	local file_prefix="${variant}-${target_version}_"

	find "$device_directory/bin/" -iname '*sysupgrade.bin' -print0 | while IFS= read -d '' -r img ; do
		BN=$(basename "$img")
		cp "$img" "$target_dir/${file_prefix}${build_version}_sysupgrade.bin"
	done

	find "$device_directory/bin/" -iname '*-zImage' -print0 | while IFS= read -d '' -r img ; do
		BN=$(basename "$img")
		cp "$img" "$target_dir/${file_prefix}${build_version}_zImage"
	done

	find "$device_directory/bin/" -iname '*root.squashfs.gz' -print0 | while IFS= read -d '' -r img ; do
		BN=$(basename "$img")
		gzip -dc "$img" > "$target_dir/${file_prefix}${build_version}_root.squashfs"
	done

	find "$device_directory/bin/" -iname '*-combined-squashfs.img' -print0 | while IFS= read -d '' -r img ; do
		BN=$(basename "$img")
		cp "$img" "$target_dir/${file_prefix}${build_version}_combined-squashfs.img"
	done

	find "$device_directory/bin/" -iname '*-combined-squashfs.img.gz' -print0 | while IFS= read -d '' -r img ; do
		BN=$(basename "$img")
		TN="$target_dir/${file_prefix}${build_version}_combined-squashfs.img"
		gzip -dc "$img" > "$TN"
	done

	if [[ ! -z "${ITB_PREFIX}" ]] ; then
		find "$device_directory/build_dir/" -iname "${ITB_PREFIX}*-uImage.itb" -print0 | while IFS= read -d '' -r img ; do
			BN=$(basename "$img")
			cp "$img" "$target_dir/${file_prefix}${build_version}_uImage.itb"
		done
	fi

	print_checksums
}

get_imagebuilder() {
	local url
	local file="$temp_dir/ImageBuilder-$target_version-$DEVICE_ARCH-$DEVICE_TYPE.tar"
	if [[ ! -z "$IMAGEBUILDER_URL" ]]; then
		url="$IMAGEBUILDER_URL"
	elif [[ "$target_version" == "master" ]]; then
		url="https://downloads.openwrt.org/snapshots/targets/$DEVICE_ARCH/$DEVICE_TYPE/openwrt-imagebuilder-$DEVICE_ARCH-$DEVICE_TYPE.Linux-x86_64.tar.xz"
	else
		url="https://downloads.openwrt.org/releases/$target_version/targets/$DEVICE_ARCH/$DEVICE_TYPE/openwrt-imagebuilder-$target_version-$DEVICE_ARCH-$DEVICE_TYPE.Linux-x86_64.tar.xz"
	fi

	download_to_file "$url" "$file"
	echo "Extracting '$(basename "$file")'..." >&2
	if [[ ! -f "$device_directory/Makefile" ]] ; then
		[[ ! -d "$device_directory" ]] && mkdir -p "$device_directory"
		rcmd tar -xf "$file" -C "$device_directory" --strip-components=1
	fi
	[[ -d "$device_directory/files" ]] && rm -rf --one-file-system "$device_directory/files"
	mkdir -p "$device_directory/files"
}

setup_extra_repos() {
	echo "Extra repos: ${EXTRA_REPOS[@]}" >&2
	[[ ! -d "$device_directory/files/etc/opkg/keys" ]] && mkdir -p "$device_directory/files/etc/opkg/keys" || true
	[[ -f "$device_directory/files/etc/opkg/customfeeds.conf" ]] && rm "$device_directory/files/etc/opkg/customfeeds.conf" || true
	if [[ ! -z "$EXTRA_REPOS" ]] && [[ "${#EXTRA_REPOS[@]}" -gt 0 ]] ; then
		for repo_def in ${EXTRA_REPOS[@]} ; do
			local repo_name=${repo_def%%=*}
			local repo_url=${repo_def##*=}
			cat "$device_directory/repositories.conf" | grep -v "$repo_name" > "$device_directory/repositories.conf.new"
			mv "$device_directory/repositories.conf.new" "$device_directory/repositories.conf"
			! grep -q "$repo_name" "$device_directory/repositories.conf" && sed -i "2 i\src/gz $repo_name $repo_url" "$device_directory/repositories.conf" || true
			echo "src/gz $repo_name $repo_url" >> "$device_directory/files/etc/opkg/customfeeds.conf"

			# Get the public key for the custom repo
			download "$repo_url/$repo_name.pub" "$device_directory/files/etc/opkg/keys/$repo_name.pub"
			local fingerprint=$("$device_directory/staging_dir/host/bin/usign" -F -p "$device_directory/files/etc/opkg/keys/$repo_name.pub")
			mv "$device_directory/files/etc/opkg/keys/$repo_name.pub" "$device_directory/files/etc/opkg/keys/$fingerprint"
		done
	fi

	if [[ "$build_variant" == "qemu" ]] ; then
		sed -i "2 i\src tzarc_local file://$script_dir/ipk" "$device_directory/repositories.conf" || true
	fi
}

# Create config files if not yet present...
create_default_files() {
	if [[ ! -e "$script_dir/authorized_keys" ]] ; then
		touch "$script_dir/authorized_keys"
	fi
	if [[ ! -e "$script_dir/root-pass" ]] ; then
		echo '# Generate the root password using: openssl passwd -1 -salt xyz mypassword > root-pass' > "$script_dir/root-pass"
	fi
	if [[ ! -e "$script_dir/extra-files" ]] ; then
		mkdir -p "$script_dir/extra-files"
	fi
}

# Copy across extra files from the deployment directory
deploy_extra_files() {
	create_default_files

	# deploy the extra files
	rcmd rsync -caP "$script_dir/extra-files"/* "$device_directory/files/" || true

	# Set default root password, using file 'root-pass' (openssl passwd -1 -salt xyz mypassword > root-pass)
	[[ ! -d "$device_directory/files/etc/" ]] && mkdir -p "$device_directory/files/etc/"
	cat << EOT > "$device_directory/files/etc/shadow"
root:$(cat "$script_dir/root-pass" 2>/dev/null | sed -e 's/#.*//g' | grep -vP '^$'):17195:0:99999:7:::
daemon:*:0:0:99999:7:::
ftp:*:0:0:99999:7:::
network:*:0:0:99999:7:::
nobody:*:0:0:99999:7:::
dnsmasq:x:0:0:99999:7:::
sshd:x:0:0:99999:7:::
EOT
	rcmd chmod 0640 "$device_directory/files/etc/shadow"

	# root's authorized_keys
	[[ ! -d "$device_directory/files/root/.ssh" ]] && mkdir -p "$device_directory/files/root/.ssh"
	[[ -f "$script_dir/authorized_keys" ]] && cat "$script_dir/authorized_keys" > "$device_directory/files/root/.ssh/authorized_keys"

	# reset permissions in deployed extra files
	rcmd find "$device_directory/files" -type d -exec chmod 0755 '{}' \; || true
	rcmd find "$device_directory/files" -type f -exec chmod 0644 '{}' \; || true
	rcmd find "$device_directory/files" -type f -name '*.sh' -exec chmod 0755 '{}' \; || true
	rcmd find "$device_directory/files/etc/uci-defaults" -type f -exec chmod 0755 '{}' \; || true
	# reset permissions in root's home directory
	rcmd find "$device_directory/files/root" -type d -exec chmod 0700 '{}' \; || true
	rcmd find "$device_directory/files/root" -type f -exec chmod 0600 '{}' \; || true
}

print_checksums() {
	header "Image information:"
	{
		echo "File: Size: MD5: SHA256:"
		find "$script_dir/img/" -maxdepth 1 -type f | sort | while read -r file ; do
			local f=$(basename "$file")
			local z=$(stat -c "%s" "$file")
			local s=$(sha256sum "$file" | cut -f1 -d' ')
			local m=$(md5sum "$file" | cut -f1 -d' ')
			echo "$f $z $m $s"
		done ;
	} | column -t >&2
}

##########################################################################################

script_command_is_optional_version=1
script_command_has_arg_version="ver"
script_command_args_version() { for ver in ${supported_versions[@]}; do echo $ver ; done ; }
script_command_desc_version() { echo "Allows selection of different build versions. Defaults to $default_version." ; }
script_command_exec_version() {
    export target_version="$1"
}

script_command_is_optional_all=1
script_command_desc_all() { echo "Builds all custom image variants." ; }
script_command_exec_all() {
	local -a all_variants=( $(get_variants) )
	for variant in ${all_variants[@]} ; do
		chain_build_one_variant "$variant"
	done
}

script_command_is_optional_variant=1
script_command_has_arg_variant="name"
script_command_args_variant() { get_variants ; }
script_command_desc_variant() { echo "Builds one custom image variant." ; }
script_command_exec_variant() {
	local variant="$1"
	if [[ -f "$script_dir/variants/variant.$variant" ]] ; then
		build_one_variant "$variant"
	else
		echo_fail "Invalid variant: $variant"
		usage
		exit 1
	fi
}

script_command_is_optional_clean=1
script_command_desc_clean() { echo "Cleans all downloaded/generated files." ; }
script_command_exec_clean() {
	[[ -d "$target_dir" ]] && rm -rf --one-file-system "$target_dir" || true
	[[ -d "$temp_dir" ]] && rm -rf --one-file-system "$temp_dir" || true
}

##########################################################################################

# Main entrypoint...
[[ -z "${target_version}" ]] && export target_version="${default_version}"
exec_command_args
export script_rc=0
