#!/bin/sh
PATH=/usr/bin:/usr/sbin:/bin:/sbin
export PATH
cd /custom
lua post_boot.lua
rc=$?
exit $rc
