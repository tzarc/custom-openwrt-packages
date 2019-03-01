#!/bin/bash

export this_script=$(readlink -f "${BASH_SOURCE[0]}")
source common.bashinc.sh

# No args => test
if [ "${#script_args[@]}" -eq "0" ] ; then
	script_args+=(--test)
fi

##########################################################################################

script_command_is_optional_test=1
script_command_desc_test() { echo "Runs the test qemu target." ; }
script_command_exec_test() {
	local version="18.06.2"
#	local version="master"
	"$script_dir/build-image.sh" --version=${version} --variant=qemu

	echo "Access the luci webui by visiting:"
	echo "		http://$(hostname):40080/"
	echo "		https://$(hostname):40443/"
	echo "Access the SSH using the command:"
	echo "		ssh -p40022 -o \"UserKnownHostsFile /dev/null\" -o \"StrictHostKeyChecking no\" root@$(hostname)"
	echo "Wait for br-lan to enter promiscuous mode before attempting connection."

	test_kernel=$(find "$script_dir/img/" -maxdepth 1 -iname "qemu-${version}*_zImage" | sort | tail -n1)
	test_rootfs=$(find "$script_dir/img/" -maxdepth 1 -iname "qemu-${version}*_root.squashfs" | sort | tail -n1)

	if [[ ! -z "$test_kernel" ]] && [[ ! -z "$test_rootfs" ]] ; then
		rcmd xterm -fg white -bg black -geometry 144x40 -e \
			qemu-system-arm -M virt -m 128 -nographic \
				-netdev user,id=qemulan0,net=192.168.1.0/24,host=192.168.1.254,dhcpstart=192.168.1.1,hostfwd=tcp:0.0.0.0:40022-:22,hostfwd=tcp:0.0.0.0:40080-:80,hostfwd=tcp:0.0.0.0:40443-:443 \
				-netdev user,id=qemuwan0 \
				-device e1000,netdev=qemulan0,id=eth0,mac=10:10:10:10:10:10 \
				-device e1000,netdev=qemuwan0,id=eth1,mac=20:20:20:20:20:20 \
				-kernel "$test_kernel" \
				-drive file="$test_rootfs",format=raw,if=virtio \
				-append 'root=/dev/vda rootwait'
	fi
}

##########################################################################################

exec_command_args
export script_rc=0
