local ARGV=arg

local uci = require('uci')
local x = uci.cursor()
local fs = require('nixio.fs')
local nixio = require('nixio')
local sys = require('luci.sys')
local util = require('luci.util')

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Extensions
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Split function
function string:split(sep)
	local sep, fields = sep or ":", {}
	local pattern = string.format("([^%s]+)", sep)
	self:gsub(pattern, function(c) fields[#fields + 1] = c end)
	return fields
end

-- String interpolation: [[ "mystring $moo ${blah} ${chunder:7.2f}" % {moo=6, blah="blah", chunder=6.6} ]]
local function interp(s, tab)
	s = s:gsub('${(%a[%w_]*):([-0-9%.]*[cdeEfgGiouxXsq])}', function(k, fmt)
		return tab[k] and ("%"..fmt):format(tab[k]) or '${'..k..':'..fmt..'}'
	end)
	s = s:gsub('${(%a[%w_]*)}', function(k)
		return tab[k] and ("%s"):format(tostring(tab[k])) or '${'..k..'}'
	end)
	s = s:gsub('$(%a[%w_]*)', function(k)
		return tab[k] and ("%s"):format(tostring(tab[k])) or '${'..k..'}'
	end)
	return s
end
string.interp = interp
getmetatable("").__mod = interp

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local loglevel = tonumber(x:get('private-internet-access', 'config', 'loglevel') or '0')
local verbose = (loglevel >= 1) and true or false
local tracing = (loglevel >= 2) and true or false
local function TRACE(t) if tracing then print(t); end end
local function DBG(t) if verbose then print(t); end end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Command runners
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function read_file(f)
	TRACE('#READ# ${f}' % {f=f})
	return fs.readfile(f)
end

local function write_file(f, txt)
	TRACE('#WRITE# ${f}' % {f=f})
	fs.writefile(f, txt)
end

local function del_file(f)
	if fs.stat(f) then
		TRACE('#UNLINK# ${f}' % {f=f})
		fs.unlink(f)
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- UCI wrappers
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function get_bool(...)
	TRACE('#GET# ${path}' % {path=table.concat({...}, ' ')})
	local r = x:get(...)
	if type(r) == 'string' and (r == '1' or r:lower() == 'true' or r:lower() == 'y' or r:lower() == 'yes') then return true end
	if type(r) == 'boolean' and r == true then return true end
	if type(r) == 'number' and r ~= 0 then return true end
	return false
end

local function get_str(...)
	TRACE('#GET# ${path}' % {path=table.concat({...}, ' ')})
	local r = x:get(...)
	if type(r) == 'string' and r:len() > 0 then return r end
	return nil
end

local function get_int(...)
	TRACE('#GET# ${path}' % {path=table.concat({...}, ' ')})
	local r = x:get(...)
	if type(r) == 'string' and r:len() > 0 then return tonumber(r) end
	if type(r) == 'number' then return r end
	return nil
end

local function get_raw(...)
	TRACE('#GET# ${path}' % {path=table.concat({...}, ' ')})
	return x:get(...)
end

local function get_all_of_type(cfg, type)
	TRACE('#GETALL# ${cfg} ${type}' % {cfg=cfg,type=type})
	local r = {}
	x:foreach(cfg, type, function(s) r[1+#r] = s end)
	table.sort(r, function(a,b) return a['.index'] < b['.index'] end)
	return r
end

local modified_configs = {}
local function add_modified_config(cfg)
	modified_configs[cfg] = true
end

local function commit_modified_configs()
	for cfg in pairs(modified_configs) do
		TRACE('#COMMIT# ${cfg}' % {cfg=cfg})
		x:commit(cfg)
		modified_configs[cfg] = nil
	end
end

local function add_val(cfg, type)
	DBG('#ADD# ${cfg} ${type}' % {cfg=cfg,type=type})
	return x:add(cfg, type)
end

local function set_val(cfg, ...)
	local t = {...}
	for k,v in pairs(t) do t[k] = (type(v) == 'table') and ('['..tostring(v)..']') or tostring(v) end
	TRACE('#SET# ${cfg} ${path}' % {cfg=cfg,path=table.concat(t, ' ')})
	x:set(cfg, ...)
	add_modified_config(cfg)
end

local function set_tbl(...)
	local t = {...}
	local tbl = t[#t]
	table.remove(t, #t)
	for k,v in pairs(tbl) do
		local path = {unpack(t)}
		path[1+#path] = k
		path[1+#path] = v
		set_val(unpack(path))
	end
end

local function del_val(cfg, ...)
	TRACE('#DEL# ${cfg} ${path}' % {cfg=cfg,path=table.concat({...}, ' ')})
	x:delete(cfg, ...)
	add_modified_config(cfg)
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Command runners
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function run_cmd(cmd)
	TRACE('#CMD# ${cmd}' % {cmd=cmd})
	return util.exec(cmd)
end

local function run_cmdi(cmd)
	TRACE('#CMD# ${cmd}' % {cmd=cmd})
	return util.execi(cmd)
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local get_hostname_for_server
do
	local servers = {}
	local fd = nixio.open("/usr/share/pia/servers.list", "r")
	if fd then
		for ln in fd:linesource() do
			local n, s = ln:match("([^:]+):(.*)")
			servers[n] = s
		end
	end

	get_hostname_for_server = function(server)
		return servers[server]
	end
end


--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Config files
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function write_config_files(interfaceName, server, user, pass, tableName)
	-- get the hostname from the server list file
	local hostname = get_hostname_for_server(server)
	write_file('/tmp/pia/pia-${interfaceName}.conf' % {interfaceName=interfaceName}, [[
syslog openvpn(pia-${interfaceName})
writepid /tmp/pia/pia-${interfaceName}.pid
client
disable-occ
nobind
persist-key
persist-tun
tls-client
auth sha256
auth-user-pass /tmp/pia/pia-${interfaceName}.credentials
ca /usr/share/pia/ca.rsa.4096.crt
cd /etc/openvpn
cipher aes-256-cbc
comp-lzo yes
crl-verify /usr/share/pia/crl.rsa.4096.pem
dev ${interfaceName}
dev-type tun
keepalive 10 60
port 1197
proto udp
rcvbuf 0
remote ${hostname}
remote-cert-tls server
reneg-sec 0
resolv-retry infinite
sndbuf 0
verb 1
script-security 2
route-noexec
up "/bin/sh /tmp/pia/pia-${interfaceName}.sh"
route-up "/bin/sh /tmp/pia/pia-${interfaceName}.sh"
down "/bin/sh /tmp/pia/pia-${interfaceName}.sh"
]] % {interfaceName=interfaceName,hostname=hostname})

	write_file('/tmp/pia/pia-${interfaceName}.credentials' % {interfaceName=interfaceName}, [[
${user}
${pass}
]] % {user=user,pass=pass})

	local tableStr = tableName and ('table ${tableName}' % {tableName=tableName}) or ''
	write_file('/tmp/pia/pia-${interfaceName}.sh' % {interfaceName=interfaceName}, [[
#!/bin/sh
rcmd() { echo "$@"; "$@"; }
{ echo "Args:"; echo "$@"; echo "----"; echo "Env:"; env | sort; echo "----"; echo "Set:"; set; } > /tmp/pia/pia-${interfaceName}.env
if [ "${script_type}" = "route-up" ] ; then
	rcmd ip route add $(ip route get $trusted_ip 2>/dev/null | sed -e 's#cache##g' -e 's#uid 0##g') || kill ${daemon_pid}
	rcmd ip route add 0.0.0.0/1 via $ifconfig_remote dev $dev ${tableStr} || kill ${daemon_pid}
	rcmd ip route add 128.0.0.0/1 via $ifconfig_remote dev $dev ${tableStr} || kill ${daemon_pid}
	rcmd ip route add $route_network_1 via $route_gateway_1 dev $dev ${tableStr} || kill ${daemon_pid}
elif [ "${script_type}" = "down" ] ; then
	ip route show table all | grep "^${trusted_ip}" | while IFS= read -r route ; do rcmd ip route del $route ; done
fi
ubus call network reload 2>/dev/null || true
]] % {interfaceName=interfaceName,tableStr=tableStr})
end

local function add_networking(interfaceName, server)
	-- Check if the interface exists already
	local ifaceFound = false
	local interfaces = get_all_of_type('network', 'interface')
	for idx,iface in pairs(interfaces) do
		if iface.ifname == interfaceName then ifaceFound = true break end
	end

	-- Create the interface
	if not ifaceFound then
		set_val('network', interfaceName, 'interface')
		set_tbl('network', interfaceName, {
			proto = 'none',
			ifname = interfaceName,
		})
	end

	-- Check if the zone exists already
	local zoneFound = false
	local zones = get_all_of_type('firewall', 'zone')
	for idx,zone in pairs(zones) do
		if zone.name == interfaceName then zoneFound = true break end
	end

	-- Create the firewall zone
	if not zoneFound then
		local zone = add_val('firewall', 'zone')
		set_tbl('firewall', zone, {
			name = interfaceName,
			network = interfaceName,
			input = 'REJECT',
			output = 'ACCEPT',
			forward = 'REJECT',
			masq = 1,
			mtu_fix = 1,
		})
	end

	-- Check if the forwarding entry exists already
	local forwardingFound = false
	local forwardings = get_all_of_type('firewall', 'forwarding')
	for idx,forwarding in pairs(forwardings) do
		if forwarding.dest == interfaceName then forwardingFound = true break end
	end

	-- Create the firewall forwarding policies
	if not forwardingFound then
		local policy = add_val('firewall', 'forwarding')
		set_tbl('firewall', policy, {
			dest = interfaceName,
			src = 'lan',
		})
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function reconfigure()
	if not fs.stat('/tmp/pia') then fs.mkdir('/tmp/pia') end

	local connections = get_all_of_type('private-internet-access', 'connection')
	for idx,connection in pairs(connections) do
		if connection.enabled and tonumber(connection.enabled) == 1 then
			add_networking(connection.name, connection.server)
			write_config_files(connection.name, connection.server, connection.username, connection.password, connection.routing_table)
		end
	end

	-- Commit config
	commit_modified_configs()
	-- Reload configs so that dnsmasq etc. take up the new settings
	run_cmd('/sbin/reload_config') -- Should we be doing this? Needed for procd to invoke callbacks on config file reloads
end

local function spawn(cfg)
	reconfigure()
	DBG('Starting PIA configuration ${cfg}' % {cfg=cfg})
	local connections = get_all_of_type('private-internet-access', 'connection')
	local connection
	for k,v in pairs(connections) do
		if v['.name'] == cfg then
			connection = v
			break;
		end
	end

	if not connection then
		DBG('Failed to find connection for configuration ${cfg}' % {cfg=cfg})
		os.exit(1)
	end

	-- get the hostname from the server list file
	local hostname = get_hostname_for_server(connection.server)
	if not hostname then
		DBG('Failed to find hostname for configuration ${cfg}' % {cfg=cfg})
		os.exit(1)
	end

	local subdomain = hostname:match('(.-)%.')
	if subdomain and type(subdomain) == 'string' and subdomain:len() > 0 then
		DBG('Starting openvpn for configuration ${cfg} -- Name \'${name}\' -- Endpoint: \'${hostname}\'' % {cfg=cfg,name=connection.name,hostname=hostname})
		nixio.exec('/usr/sbin/openvpn', '--config', '/tmp/pia/pia-${name}.conf' % {name=connection.name})
	else
		DBG('Failed to determine subdomain for configuration ${cfg}' % {cfg=cfg})
		os.exit(1)
	end
end

if ARGV[1] == "reconfigure" then
	reconfigure()
elseif ARGV[1] == "spawn" then
	local cfg = ARGV[2]
	spawn(cfg)
else
	util.perror('Error, unknown argument: ${arg}' % {arg=ARGV[1]})
end
