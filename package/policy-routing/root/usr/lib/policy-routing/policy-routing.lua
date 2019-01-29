local ARGV=arg

local uci = require('uci')
local x = uci.cursor()
local ip = require('luci.ip')
local nixio = require('nixio')
local sys = require('luci.sys')
local util = require('luci.util')
local bit = nixio.bit

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
-- Cached data
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local cache = {
	interfaces = {}
}

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Generic Helpers
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local enabled = (tonumber(x:get('policy-routing', 'config', 'enabled') or '0') ~= 0) and true or false
local loglevel = tonumber(x:get('policy-routing', 'config', 'loglevel') or '0')
local verbose = (loglevel >= 1) and true or false
local tracing = (loglevel >= 2) and true or false
local function TRACE(t) if tracing then nixio.syslog('debug', t) end end
local function DBG(t) if verbose then nixio.syslog('info', t) end end

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
-- Single-instance locking
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local proc_lock, proc_unlock
do
	local lockFile = nixio.open('/tmp/policy-routing-lock', 'w+')
	proc_lock = function()
		TRACE('#LOCK#')
		lockFile:lock('lock')
	end
	proc_unlock = function()
		TRACE('#UNLOCK#')
		lockFile:lock('ulock')
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Config parameters
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local firstTableID = get_int('policy-routing', 'config', 'first_table') or 11320 -- Allow for changing via config, in case other tables just happen to match the default
local leftShiftAmount = get_int('policy-routing', 'config', 'mark_offset') or 8 -- Allow for changing via config, in case other marks are in-use on the router
local dnsEntryTimeout = get_int('policy-routing', 'config', 'dns_entry_timeout') or 0 -- Allow for setting a global time expiry on dnsmasq-resolved ipset entries

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- dnsmasq instance detection
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Get the first dnsmasq instance from the dhcp config
local dnsmasqEntries = get_all_of_type('dhcp', 'dnsmasq')
local dnsmasqInstance
for k,v in pairs(dnsmasqEntries) do dnsmasqInstance = v['.name'] break end
if not dnsmasqInstance then
	DBG('No dnsmasq instances found, not doing domain mappings.')
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Mark and table number calculations
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local maxNumEgressInterfaces = 8
local tablesPerEgressInterface = 1
local firstMark = bit.lshift(1, leftShiftAmount)
local lastMark = bit.lshift(bit.lshift(1, maxNumEgressInterfaces-1), leftShiftAmount)
local totalMask = firstMark; while totalMask < lastMark do totalMask = bit.bor(bit.lshift(totalMask, 1), firstMark) end
TRACE("#INFO# First mark: 0x${firstMark:08X}, last mark: 0x${lastMark:08X}, Mask: 0x${totalMask:08X}" % {firstMark=firstMark,lastMark=lastMark,totalMask=totalMask})

local function get_table_index(ifaceIdx, fourOrSix)
	if ifaceIdx < 1 or ifaceIdx > maxNumEgressInterfaces then error("Invalid table index.") end
	return (firstTableID + (ifaceIdx-1)) + ((fourOrSix == 6) and maxNumEgressInterfaces or 0)
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Networking helpers
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function ip_decompose(addr)
	local f = ip.new(addr)
	return {
		ipv4 = (f:is4() and f:string()), --or (f:is6mapped4() and f:mapped4()),
		ipv6 = (f:is6() and f:string()) --or (f:is4() and ('::ffff:'..f:string()))
	}
end

local function interface_is_up(iface, pingTargetAddr)
	iface = iface:gsub('"','')
	pingTargetAddr = (pingTargetAddr or '8.8.8.8'):gsub('"','')
	local rc = sys.call('ping -c1 -I "${iface}" "${pingTargetAddr}" >/dev/null 2>&1' % {iface=iface,pingTargetAddr=pingTargetAddr})
	return (rc == 0) and true or false
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function clear_dnsmasq_ipsets()
	-- Get all the dnsmasq ipsets already configured for that instance
	local allSets = get_raw('dhcp', dnsmasqInstance, 'ipset') or {}

	-- Get a list of all other _other_ ipsets that we don't control, so we can just remove ours and leave existing ones alone.
	local otherSets = {}
	for k,v in pairs(allSets) do
		if not v:match('/poro_') then otherSets[1+#otherSets] = v end
	end

	-- Update the config, can't set the value with an empty table, so delete it if there's no other ipsets present.
	if #otherSets == 0 then
		del_val('dhcp', dnsmasqInstance, 'ipset')
	else
		set_val('dhcp', dnsmasqInstance, 'ipset', otherSets)
	end
end

local function clear_routing_tables()
	-- Work out the first and last tables, so we know what we're looping against
	local firstTbl = get_table_index(1, 4)
	local lastTbl = get_table_index(maxNumEgressInterfaces, 6)

	-- Loop through all of our tables...
	for tbl=firstTbl,lastTbl do
		-- Keep track of if we're done with each inet family
		local done4, done6 = false, false

		-- Bruteforce removal, loop a few times and drop out early if nothing is present.
		for i=1,3 do
			-- Delete the ipv4 routes if there are any present
			if not done4 then
				local test = run_cmd("ip -4 route list table ${tbl}; ip -4 rule list table ${tbl}" % {tbl=tbl})
				if test and type(test) == "string" and test:len() > 0 then
					-- Bruteforce removal.
					run_cmd("ip -4 rule del from all table ${tbl}" % {tbl=tbl})
					run_cmd("ip -4 route flush table ${tbl}" % {tbl=tbl})
				else
					done4 = true
				end
			end

			-- Delete the ipv6 routes if there are any present
			if not done6 then
				local test = run_cmd("ip -6 route list table ${tbl}; ip -6 rule list table ${tbl}" % {tbl=tbl})
				if test and type(test) == "string" and test:len() > 0 then
					-- Bruteforce removal.
					run_cmd("ip -6 rule del from all table ${tbl}" % {tbl=tbl})
					run_cmd("ip -6 route flush table ${tbl}" % {tbl=tbl})
				else
					done6 = true
				end
			end

			-- If both are done... drop out.
			if done4 and done6 then break end
		end
	end
end

local function clear_firewall_rules(iptables)
	-- If unspecified, assume we want to clear both ipv4 and ipv6 versions of our rules.
	if not iptables then
		clear_firewall_rules('iptables')
		clear_firewall_rules('ip6tables')
		return
	end

	-- Delete any rule which has '!poro:' in it in the PREROUTING table, so that we can delete any secondary chains
	local ruleNums = {}
	for ruleNum in run_cmdi('${ipt} -t mangle -nvL PREROUTING --line-numbers | awk \'/!poro:/ {print $1}\'' % {ipt=iptables}) do ruleNums[1+#ruleNums] = tonumber(ruleNum) end
	table.sort(ruleNums)
	for i=#ruleNums,1,-1 do run_cmd('${ipt} -t mangle -D PREROUTING ${rule}' % {ipt=iptables, rule=ruleNums[i]}) end

	-- Delete any rule which has '!poro:' in it in the FORWARD table, so that we can delete any secondary chains
	ruleNums = {}
	for ruleNum in run_cmdi('${ipt} -t filter -nvL forwarding_rule --line-numbers | awk \'/!poro:/ {print $1}\'' % {ipt=iptables}) do ruleNums[1+#ruleNums] = tonumber(ruleNum) end
	table.sort(ruleNums)
	for i=#ruleNums,1,-1 do run_cmd('${ipt} -t filter -D forwarding_rule ${rule}' % {ipt=iptables, rule=ruleNums[i]}) end

	-- Flush and delete any policy routing chains
	for chain in run_cmdi('${ipt} -t mangle -nvL --line-numbers | awk \'/Chain poro_/ {print $2}\'' % {ipt=iptables}) do
		run_cmd('${ipt} -t mangle -F ${chain}' % {ipt=iptables, chain=chain})
		run_cmd('${ipt} -t mangle -X ${chain}' % {ipt=iptables, chain=chain})
	end
	for chain in run_cmdi('${ipt} -t filter -nvL --line-numbers | awk \'/Chain poro_/ {print $2}\'' % {ipt=iptables}) do
		run_cmd('${ipt} -t filter -F ${chain}' % {ipt=iptables, chain=chain})
		run_cmd('${ipt} -t filter -X ${chain}' % {ipt=iptables, chain=chain})
	end
end

local function clear_ipsets(isReloading)
	-- Work out the list of ipsets
	local ipsets = {}
	isReloading = isReloading or false
	local collectorCmd = isReloading
		and 'ipset list | awk \'/Name: poro_/ {print $2}\' | grep -v dnsmasq'
		or 'ipset list | awk \'/Name: poro_/ {print $2}\''
	for ipset in run_cmdi(collectorCmd) do
		ipsets[1+#ipsets] = ipset
	end

	-- Sort, then flush and delete so that they're destroyed in the correct order
	table.sort(ipsets)
	for i=1,#ipsets do
		run_cmd('ipset flush ${ipset}' % {ipset=ipsets[i]})
		run_cmd('ipset destroy ${ipset}' % {ipset=ipsets[i]})
	end
end

local function clear_policies(isReloading)
	clear_firewall_rules()
	clear_dnsmasq_ipsets()
	clear_routing_tables()
	clear_ipsets(isReloading)

	-- Commit config
	commit_modified_configs()
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Base rule/routing setup
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function add_firewall_base_chains(iptables, fourOrSix)
	-- If unspecified, assume we want to set up both ipv4 and ipv6 versions of our rules.
	if not iptables or not fourOrSix then
		add_firewall_base_chains('iptables', 4)
		add_firewall_base_chains('ip6tables', 6)
		return
	end

	-- Create the base PREROUTING chain
	local fmtTbl = {ipt=iptables,fourOrSix=fourOrSix,totalMask=totalMask}
	run_cmd('${ipt} -t mangle -N poro_prerouting' % fmtTbl)
	run_cmd('${ipt} -t mangle -I PREROUTING 1 -i br-lan -m comment --comment "!poro: PREROUTING Chain" -m mark --mark 0x0/0x${totalMask:X} -j poro_prerouting' % fmtTbl)

	-- Create the base FORWARD chain
	run_cmd('${ipt} -t filter -N poro_forward' % fmtTbl)
	run_cmd('${ipt} -t filter -I forwarding_rule 1 -i br-lan -m comment --comment "!poro: FORWARD Chain" -j poro_forward' % fmtTbl)
end

local function add_interface_routes_and_rules(iface, fourOrSix)
	if not fourOrSix then
		add_interface_routes_and_rules(iface, 4)
		add_interface_routes_and_rules(iface, 6)
		return
	end

	local ifaceData = cache.interfaces[iface]
	local ipt = (fourOrSix == 6) and 'ip6tables' or 'iptables'

	-- Add the routes from the normal routing table for this interface
	local tbl = get_table_index(ifaceData.idx, fourOrSix)
	ifaceData.routeTable[fourOrSix] = tbl
	run_cmd('ip -${fourOrSix} rule add fwmark 0x${mark:04X} table ${tbl} prio ${tbl}' % {mark=ifaceData.mark,tbl=tbl,fourOrSix=fourOrSix})

	local routesFound = false
	for route in run_cmdi('ip -${fourOrSix} route show table all | grep " dev ${iface} "' % {iface=ifaceData.interface,fourOrSix=fourOrSix}) do
		route = route:gsub('table ([%w_]+)', ''):match("^%s*(.*)"):match("(.-)%s*$")
		if route:len() > 0 then
			routesFound = true
			run_cmd('ip -${fourOrSix} route add ${route} table ${tbl}' % {route=route,tbl=tbl,fourOrSix=fourOrSix})
		end
	end

	-- If the interface is marked as strict, then set up a reject if the appropriate mark wasn't found
	if ifaceData.strict then
		run_cmd('${ipt} -t filter -A poro_forward -o ${iface} -m comment --comment "!poro: ${iface} - Strict enforcement" -m mark ! --mark 0x${mark:X}/0x${totalMask:X} -j REJECT' % {ipt=ipt,iface=ifaceData.interface,mark=ifaceData.mark,totalMask=totalMask})

		-- If no routes were present, add an unreachable route as a fallback
		if not routesFound then
			run_cmd('ip -${fourOrSix} route add unreachable default table ${tbl}' % {tbl=tbl,fourOrSix=fourOrSix})
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Policy application
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function add_remote_nets(idx, policy)
	if policy.remote_nets then
		local entry = policy.remote_nets
		DBG('[rule${idx}] Adding remote networks { ${nets} } => ${iface} (${comment})' % {idx=idx,iface=policy.interface,comment=policy.comment,nets=table.concat(entry, ', ')})

		-- Create ipset rules with all the network entries
		local iface = policy.interface:gsub('%W','_')
		local set4 = 'poro_${iface}_rn4_${idx}' % {iface=iface,idx=idx}
		local set6 = 'poro_${iface}_rn6_${idx}' % {iface=iface,idx=idx}
		local set4exists, set6exists = false, false

		for _,e in pairs(entry) do
			local f = ip_decompose(e)
			if f.ipv4 then
				if not set4exists then run_cmd('ipset create ${set4} hash:net family inet' % {set4=set4}) set4exists = true end
				run_cmd('ipset add ${set4} ${e}' % {set4=set4,e=f.ipv4})
			end
			if f.ipv6 then
				if not set6exists then run_cmd('ipset create ${set6} hash:net family inet6' % {set6=set6}) set6exists = true end
				run_cmd('ipset add ${set6} ${e}' % {set6=set6,e=f.ipv6})
			end
		end

		return (set4exists and set4), (set6exists and set6)
	end
end

local function add_remote_ports(idx, policy)
	if policy.remote_ports then
		local entry = policy.remote_ports
		DBG('[rule${idx}] Adding remote ports { ${ports} } => ${iface} (${comment})' % {idx=idx,iface=policy.interface,comment=policy.comment,ports=table.concat(entry, ', ')})

		-- Create ipset rules with all the network entries
		local iface = policy.interface:gsub('%W','_')
		local set = 'poro_${iface}_rp_${idx}' % {iface=iface,idx=idx}
		local setexists = false

		for _,e in pairs(entry) do
			if not setexists then run_cmd('ipset create ${set} bitmap:port range 0-65535' % {set=set}) setexists = true end
			run_cmd('ipset add ${set} ${e}' % {set=set,e=e})
		end

		return setexists and set
	end
end

local function add_local_nets(idx, policy)
	if policy.local_nets then
		local entry = policy.local_nets
		DBG('[rule${idx}] Adding local networks { ${nets} } => ${iface} (${comment})' % {idx=idx,iface=policy.interface,comment=policy.comment,nets=table.concat(entry, ', ')})

		-- Create ipset rules with all the network entries
		local iface = policy.interface:gsub('%W','_')
		local set4 = 'poro_${iface}_ln4_${idx}' % {iface=iface,idx=idx}
		local set6 = 'poro_${iface}_ln6_${idx}' % {iface=iface,idx=idx}
		local set4exists, set6exists = false, false

		for _,e in pairs(entry) do
			local f = ip_decompose(e)
			if f.ipv4 then
				if not set4exists then run_cmd('ipset create ${set4} hash:net family inet' % {set4=set4}) set4exists = true end
				run_cmd('ipset add ${set4} ${e}' % {set4=set4,e=f.ipv4})
			end
			if f.ipv6 then
				if not set6exists then run_cmd('ipset create ${set6} hash:net family inet6' % {set6=set6}) set6exists = true end
				run_cmd('ipset add ${set6} ${e}' % {set6=set6,e=f.ipv6})
			end
		end

		return (set4exists and set4), (set6exists and set6)
	end
end

local function add_local_ports(idx, policy)
	if policy.local_ports then
		local entry = policy.local_ports
		DBG('[rule${idx}] Adding local ports { ${ports} } => ${iface} (${comment})' % {idx=idx,iface=policy.interface,comment=policy.comment,ports=table.concat(entry, ', ')})

		-- Create ipset rules with all the network entries
		local iface = policy.interface:gsub('%W','_')
		local set = 'poro_${iface}_lp_${idx}' % {iface=iface,idx=idx}
		local setexists = false

		for _,e in pairs(entry) do
			if not setexists then run_cmd('ipset create ${set} bitmap:port range 0-65535' % {set=set}) setexists = true end
			run_cmd('ipset add ${set} ${e}' % {set=set,e=e})
		end

		return setexists and set
	end
end

local function add_domains(idx, policy)
	if policy.domains then
		local entry = policy.domains
		DBG('[rule${idx}] Adding domain mappings { ${dn} } => ${iface} (${comment})' % {idx=idx,iface=policy.interface,comment=policy.comment,dn=table.concat(entry, ', ')})

		-- Create ipset rules with all the network entries
		local iface = policy.interface:gsub('%W','_')
		local set4 = 'poro_${iface}_dnsmasq4_${idx}' % {iface=iface,idx=idx}
		local set6 = 'poro_${iface}_dnsmasq6_${idx}' % {iface=iface,idx=idx}
		local set4exists, set6exists = false, false
		local set4test = run_cmd('ipset list ${set4} 2>/dev/null' % {set4=set4}):match("^%s*(.*)"):match("(.-)%s*$")
		local set6test = run_cmd('ipset list ${set6} 2>/dev/null' % {set6=set6}):match("^%s*(.*)"):match("(.-)%s*$")
		if set4test and type(set4test) == 'string' and set4test:len() > 0 then set4exists = true end
		if set6test and type(set6test) == 'string' and set6test:len() > 0 then set6exists = true end

		local timeout = (policy.timeout and tonumber(policy.timeout)) or dnsEntryTimeout
		local existingSets = get_raw('dhcp', dnsmasqInstance, 'ipset') or {}
		if #entry > 0 then
			if not set4exists then run_cmd('ipset create ${set4} hash:net family inet timeout ${timeout}' % {set4=set4,timeout=timeout}) set4exists = true end
			if not set6exists then run_cmd('ipset create ${set6} hash:net family inet6 timeout ${timeout}' % {set6=set6,timeout=timeout}) set6exists = true end
		end
		existingSets[1+#existingSets] = '/' .. table.concat(entry, '/') .. '/${set4},${set6}' % {set4=set4,set6=set6}
		set_val('dhcp', dnsmasqInstance, 'ipset', existingSets)

		return (set4exists and set4), (set6exists and set6)
	end
end

local function apply_policy(idx, policy)
	local v4match, v6match = {}, {}
	if policy.interface and cache.interfaces[policy.interface] then
		if policy.type == 'remote_nets' or policy.type == 'advanced' then
			local rn4, rn6 = add_remote_nets(idx, policy)
			if rn4 then v4match[1+#v4match] = '-m set --match-set ${rn4} dst' % {rn4=rn4} end
			if rn6 then v6match[1+#v6match] = '-m set --match-set ${rn6} dst' % {rn6=rn6} end
		end

		if policy.type == 'remote_ports' or policy.type == 'advanced' then
			local rp = add_remote_ports(idx, policy)
			if rp then v4match[1+#v4match] = '-m set --match-set ${rp} dst' % {rp=rp} end
			if rp then v6match[1+#v6match] = '-m set --match-set ${rp} dst' % {rp=rp} end
		end

		if policy.type == 'local_nets' or policy.type == 'advanced' then
			local ln4, ln6 = add_local_nets(idx, policy)
			if ln4 then v4match[1+#v4match] = '-m set --match-set ${ln4} src' % {ln4=ln4} end
			if ln6 then v6match[1+#v6match] = '-m set --match-set ${ln6} src' % {ln6=ln6} end
		end

		if policy.type == 'local_ports' or policy.type == 'advanced' then
			local lp = add_local_ports(idx, policy)
			if lp then v4match[1+#v4match] = '-m set --match-set ${lp} src' % {lp=lp} end
			if lp then v6match[1+#v6match] = '-m set --match-set ${lp} src' % {lp=lp} end
		end

		if policy.type == 'domains' or policy.type == 'advanced' then
			local dns4, dns6 = add_domains(idx, policy)
			if dns4 then v4match[1+#v4match] = '-m set --match-set ${dns4} dst' % {dns4=dns4} end
			if dns6 then v6match[1+#v6match] = '-m set --match-set ${dns6} dst' % {dns6=dns6} end
		end

		if policy.type == 'catch-all' then
			policy.remote_nets = { '0.0.0.0/1', '128.0.0.0/1', '::/1', '8000::/1' }
			local rn4, rn6 = add_remote_nets(idx, policy)
			if rn4 then v4match[1+#v4match] = '-m set --match-set ${rn4} dst' % {rn4=rn4} end
			if rn6 then v6match[1+#v6match] = '-m set --match-set ${rn6} dst' % {rn6=rn6} end
		end

		local fmt4 = {idx=idx, iface=policy.interface, comment=policy.comment, totalMask=totalMask, mark=cache.interfaces[policy.interface].mark, conditions=table.concat(v4match, ' ')}
		if #v4match > 0 then
			run_cmd('iptables -t mangle -A poro_prerouting -m comment --comment "!poro: [rule${idx}] ${iface} - ${comment}" -m mark --mark 0x0/0x${totalMask:X} ${conditions} -j MARK --set-mark 0x${mark:X}/0x${totalMask:X}' % fmt4)
		end

		local fmt6 = {idx=idx, iface=policy.interface, comment=policy.comment, totalMask=totalMask, mark=cache.interfaces[policy.interface].mark, conditions=table.concat(v6match, ' ')}
		if #v6match > 0 then
			run_cmd('ip6tables -t mangle -A poro_prerouting -m comment --comment "!poro: [rule${idx}] ${iface} - ${comment}" -m mark --mark 0x0/0x${totalMask:X} ${conditions} -j MARK --set-mark 0x${mark:X}/0x${totalMask:X}' % fmt6)
		end

		if #v4match == 0 and #v6match == 0 then
			DBG("[rule${idx}] Invalid policy, no conditions specified." % {idx=idx})
		end
	else
		DBG("[rule${idx}] Invalid interface name for policy: '${iface}'" % {idx=idx,iface=tostring(policy.interface)})
	end
end

local function apply_policies()
	-- Add the base set of iptables chains
	add_firewall_base_chains()

	-- TODO: Make this dynamic from both interface detection and config file (if interfaces exist we add them, and if they're in config but don't exist yet, add them but we make the routes unreachable)
	local configuredInterfaces = get_all_of_type('policy-routing', 'interface')
	local mark = firstMark
	for idx,iface in pairs(configuredInterfaces) do
		if mark > lastMark then error('Too many interfaces.') end

		cache.interfaces[iface.interface] = {
			idx = idx,
			interface = iface.interface,
			strict = ((iface.strict == '1') and true or false),
			mark = mark,
			routeTable = {},
		}

		TRACE("#IFACE# idx=${idx} iface=${iface} strict=${strict} mark=0x${mark:08X}" % {idx=idx,iface=iface.interface,strict=iface.strict,mark=mark})

		mark = bit.lshift(mark, 1)
	end

	for iface in pairs(cache.interfaces) do
		-- Copy across the routes for this interface
		add_interface_routes_and_rules(iface)
	end

	local policies = get_all_of_type('policy-routing', 'policy')
	for idx,policy in pairs(policies) do
		apply_policy(idx, policy)
	end

	-- Commit config
	commit_modified_configs()
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main Entrypoint
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local arg_handlers = {
	boot = function()
		clear_policies(false)
		if enabled then
			apply_policies()
		end
	end,
	start = function()
		clear_policies(false)
		if enabled then
			apply_policies()
		end
	end,
	stop = function()
		clear_policies(false)
	end,
	restart = function()
		clear_policies(false)
		if enabled then
			apply_policies()
		end
	end,
	reload = function()
		clear_policies(true)
		if enabled then
			apply_policies()
		end
	end,
}

nixio.openlog('policy-routing', 'pid');

local arg = ARGV[1]
local arg_handler = arg_handlers[arg]
if arg_handler then
	proc_lock()
	local ok,err = pcall(arg_handler)
	if not ok then util.perror(err) end
	proc_unlock()
	commit_modified_configs()
else
	util.perror('Error, unknown argument: ${arg}' % {arg=ARGV[1]})
end

nixio.closelog();

-- Reload configs so that dnsmasq etc. take up the new settings
run_cmd('/sbin/reload_config')
