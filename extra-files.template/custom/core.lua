do
	require('string_extra')
	local serpent = require('serpent')
	local function dump(t)
		print(serpent(t))
	end

	------------------------------------------------------------------------------------------------------------------------

	local function runcmd(cmd, raw, show_output)
		local f = assert(io.popen("{ $cmd; }\necho -n \"~@~@~@~($?)~@~@~@~\"" % {cmd = cmd}, 'r'))
		local s = assert(f:read('*a'))
		f:close()
		local rc = -1
		s = s:gsub('\n~@~@~@~%((%d+)%)~@~@~@~$', function(r) rc = r; return '' end)
		s = s:gsub('^~@~@~@~%((%d+)%)~@~@~@~$', function(r) rc = r; return '' end)
		rc = rc + 0
		if rc ~= 0 then error('Failed to execute command: { $cmd ; } [rc=$rc]' % {cmd = cmd, rc = rc}) end
		if show_output then
			local h = "---- { $cmd ; } [rc=$rc] " % {cmd=cmd, rc=rc}
			h = h .. string.rep("-", 120 - h:len())
			io.write(h, '\n')
		end
		if show_output then io.write(s, '\n') end
		if raw then return s, rc end
		s = s:gsub('^%s+', '')
		s = s:gsub('%s+$', '')
		s = s:gsub('[\n\r]+', '\n')
		return s, rc
	end

	------------------------------------------------------------------------------------------------------------------------

	local function orderedpairs(t, f)
		local a = {}
		for n in pairs(t) do table.insert(a, n) end
		table.sort(a, f)
		local i = 0
		local iter = function ()
			i = i + 1
			local k = a[i]
			if k == nil then return nil end
			return k, t[k]
		end
		return iter
	end

	------------------------------------------------------------------------------------------------------------------------

	local function writefile(filename, content, mode)
		local f = io.open(filename, mode or 'w')
		f:write(content)
		f:close()
	end

	local function appendfile(filename, content, mode)
		local f = io.open(filename, mode or 'a+')
		f:write(content)
		f:close()
	end

	local function fileexists(filename)
		local f = io.open(filename, mode or 'r')
		if f then
			f:close()
			return true
		end
		return false
	end

	------------------------------------------------------------------------------------------------------------------------

	local function parse_mac_addr(mac)
		if type(mac) == 'string' then
			mac = mac:match('%x%x:%x%x:%x%x:%x%x:%x%x:%x%x')
		end
		return (type(mac) == 'string') and mac:lower() or nil
	end

	local function get_mac_for_interface(netif)
		local mac, rc = runcmd("ifconfig $netif 2>&1 | awk '/HWaddr/{print $5}'" % {netif=netif})
		if rc ~= 0 then return nil end
		return parse_mac_addr(mac)
	end

	------------------------------------------------------------------------------------------------------------------------

	local uname = runcmd("uname")
	local function kecho(str)
		if uname == "Linux" then
			writefile('/dev/kmsg', '## Config: $str\n' % {str = str})
		end
		print('-- $str' % {str=str})
	end

	------------------------------------------------------------------------------------------------------------------------

	local function enable_service(svc)
		runcmd("if [ -x /etc/init.d/$svc ] ; then /etc/init.d/$svc enable; fi; true" % {svc=svc})
	end

	local function disable_service(svc)
		runcmd("if [ -x /etc/init.d/$svc ] ; then /etc/init.d/$svc disable; /etc/init.d/$svc stop; fi; true" % {svc=svc})
	end

	------------------------------------------------------------------------------------------------------------------------

	return {
		dump = dump,

		runcmd = runcmd,

		orderedpairs = orderedpairs,

		writefile = writefile,
		appendfile = appendfile,
		fileexists = fileexists,

		parse_mac_addr = parse_mac_addr,
		get_mac_for_interface = get_mac_for_interface,

		kecho = kecho,

		enable_service = enable_service,
		disable_service = disable_service,
	}
end
