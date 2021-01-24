local cfg = require('uci_extra')
cfg.verbose = false
local core = require('core')
local network_defs = require('network_defs')

local serpent = require('serpent')
local dump = function(t) print(serpent(t)) end

local routers = network_defs.routers
local networks = network_defs.networks

------------------------------------------------------------------------------------------------------------------------
-- Work out which network we're dealing with based off the MAC address
function get_this_network()
	for suffix,routerlist in pairs(routers) do
		for _,router in pairs(routerlist) do
			local test_mac = core.get_mac_for_interface(router.iface)
			--print('test host: $host, interface: $iface, expected mac: $emac, actual mac: $amac' % {host=router.host, iface=router.iface, emac=router.mac, amac=test_mac})
			if router.mac == test_mac then
				local netdata = networks[suffix]
				-- Update all the devices to match the hosts/mac addresses
				for _,r in pairs(routerlist) do
					local devdata = netdata.devices[r.host]
					netdata.devices[r.host] = nil
					netdata.devices[r.mac] = devdata
					devdata.is_router = r.role and r.role == 'router' and true or false
				end
				return suffix, netdata, netdata.devices[router.mac], router.wan_if
			end
		end
	end
end

local conf = {}
conf.suffix, conf.netdata, conf.this_device, conf.wan_if = get_this_network()
conf.is_router = conf.this_device.is_router
core.dump(conf)

local function apply_base_system_config()
	core.kecho('Configuring base system configuration...')
	cfg:set('system.@system[0]', {
		hostname = conf.this_device.hostname,
		zonename = 'Australia/Sydney',
		timezone = 'AEST-10AEDT,M10.1.0,M4.1.0/3',
		zram_size_mb = 30
	})
	cfg:set('uhttpd.main.redirect_https', 0)

	if conf.netdata.external_logger then
		cfg:set('system.@system[0]', {
			log_ip = conf.netdata.external_logger.target_host,
			log_port = conf.netdata.external_logger.target_port,
		})
	end

	core.kecho('Configuring NTP...')
	cfg:del('system.ntp')
	cfg:set('system.ntp', 'timeserver')
	cfg:set('system.ntp', {
		enabled = 1,
		enable_server = 0,
		server = { '0.pool.ntp.org', '1.pool.ntp.org', '2.pool.ntp.org', '3.pool.ntp.org' }
	})

	core.kecho('Configuring base networking...')
	cfg:set('network.lan', {
		ipaddr = conf.this_device.ipv4,
		netmask = '255.255.255.0',
		ip6ifaceid = "::$lastoctet" % {lastoctet=conf.this_device.lastoctet}
	})
	cfg:set('network.globals', {
		ula_prefix = '$ula_prefix::/48' % {ula_prefix=conf.netdata.ipv6_prefix}
	})

	core.appendfile('/etc/rc.local', [[
echo '0' > /sys/devices/virtual/net/br-lan/bridge/multicast_snooping
]])

	core.writefile('/etc/firewall.user', [[
# This file is interpreted as shell script.
# Put your custom iptables rules here, they will
# be executed with each firewall (re-)start.

# Internal uci firewall chains are flushed and recreated on reload, so
# put custom rules into the root chains e.g. INPUT or FORWARD or into the
# special user chains, e.g. input_wan_rule or postrouting_lan_rule.
]])

	if conf.is_router then
		core.enable_service('firewall')
	else
		core.disable_service('firewall')
		cfg:set('network.lan', {
			broadcast = '255.255.255.0',
			dns = conf.netdata.gateway,
			gateway = conf.netdata.gateway,
		})
	end
end

local function apply_dhcp_server_config()
	if not core.fileexists('/etc/config/dhcp') then return end
	if not core.fileexists('/etc/config/https-dns-proxy') and not core.fileexists('/etc/config/stubby') then return end

	core.kecho('Configuring DHCP common parameters...')

	if conf.is_router then
		core.kecho('Configuring DHCP server...')
		local dns_forwardings = { '/ntp.org/208.67.222.222' }
		if conf.netdata.dns_suffix_forwardings then
			for k,v in pairs(conf.netdata.dns_suffix_forwardings) do
				dns_forwardings[1+#dns_forwardings] = v
			end
		end
		cfg:set('dhcp.lan', {
			start = 110,
			limit = 80,
			ignore = 0,
			dhcpv6 = 'server',
			ra = 'server',
			ra_default = 1,
			ra_management = 2,
			dns = '$ula_prefix::1' % {ula_prefix=conf.netdata.ipv6_prefix},
			domain = conf.suffix,
		})
		cfg:set('dhcp.@dnsmasq[0]', {
			domain = conf.suffix,
			['local'] = "/$suffix/" % {suffix=conf.suffix},
			noresolv = 1,
			nonegcache = 1,
			cachesize = 10000,
			rebind_protection = 0,
			allservers = 1,
		})

		-- Allow for local IP DNS responses for specific domains
		if conf.netdata.additional_dns_suffixes then
			local domain_search = { conf.suffix }
			for k,v in pairs(conf.netdata.additional_dns_suffixes) do
				domain_search[1+#domain_search] = v
			end
			cfg:set('dhcp.@dnsmasq[0]', {
				rebind_domain = conf.netdata.additional_dns_suffixes,
				dhcp_option = {
					'option:domain-search,${suffixes}' % {suffixes=table.concat(domain_search,',')},
					'option:dns-server,${ipv4}' % {ipv4=conf.this_device.ipv4},
				},
			})
		end

		core.enable_service('dnsmasq')

		-- Disable using DNS over WAN
		cfg:set('network.wan', {
			peerdns = 0,
			dns = '127.0.0.1'
		})
		cfg:set('network.wan6', {
			peerdns = 0,
			dns = '0::1'
		})

		if core.fileexists('/etc/config/unbound') then
			core.kecho('Configuring unbound DNS server...')
			cfg:set('unbound.@unbound[0]', {
				protocol = 'ip4_only',
				add_local_fqdn = 0,
				add_wan_fqdn = 0,
				dhcp_link = 'none',
				domain = conf.suffix,
				domain_type = 'refuse',
				listen_port = 5153
			})

			cfg:wipe_all('unbound', 'zone')
			if conf.netdata.unbound then
				for k,v in pairs(conf.netdata.unbound) do
					local e = cfg:add('unbound', 'zone')
					cfg:set(e, {
						enabled = 1,
						fallback = 0,
						tls_index = v.auth_name % {hostname=conf.this_device.hostname},
						tls_port = v.port,
						tls_upstream = 1,
						zone_name = { '.' },
						zone_type = 'forward_zone',
						server = v.addresses
					})
				end
			end

			dns_forwardings[1+#dns_forwardings] = '127.0.0.1#5153'
			dns_forwardings[1+#dns_forwardings] = '::1#5153'
			core.enable_service('unbound')
		end

		if core.fileexists('/etc/config/stubby') then
			core.kecho('Configuring stubby DNS server...')
			cfg:wipe_all('stubby', 'resolver')
			if conf.netdata.stubby then
				for k,v in pairs(conf.netdata.stubby) do
					for k2,v2 in pairs(v.addresses) do
						local e = cfg:add('stubby', 'resolver')
						cfg:set(e, {
							address = v2,
							tls_auth_name = v.auth_name % {hostname=conf.this_device.hostname}
						})
					end
				end
			end
			dns_forwardings[1+#dns_forwardings] = '127.0.0.1#5453'
			dns_forwardings[1+#dns_forwardings] = '::1#5453'
			core.enable_service('stubby')
		end

		if core.fileexists('/etc/config/https-dns-proxy') then
			core.kecho('Configuring https-dns-proxy DNS server...')
			if conf.netdata.https_dns_proxy then
				cfg:wipe_all('https-dns-proxy', 'https-dns-proxy')
				for k,v in pairs(conf.netdata.https_dns_proxy) do
					local dns = cfg:add('https-dns-proxy', 'https-dns-proxy')
					cfg:set(dns, {
						bootstrap_dns = v.bootstrap,
						resolver_url = v.resolver_url % {hostname=conf.this_device.hostname},
						listen_addr = v.listen_addr,
						listen_port = v.listen_port,
						user = 'nobody',
						group = 'nogroup'
					})
					dns_forwardings[1+#dns_forwardings] = '127.0.0.1#${port}' % {port=v.listen_port}
					dns_forwardings[1+#dns_forwardings] = '::1#${port}' % {port=v.listen_port}
				end
			end

			cfg:set('https-dns-proxy.config', {
				update_dnsmasq_config = '-'
			})

			core.enable_service('https-dns-proxy')
		end

		-- Set the DNS forwarders
		cfg:set('dhcp.@dnsmasq[0]', {
			server = dns_forwardings
		})
	else
		core.kecho('Disabling DHCP server...')
		core.disable_service('dnsmasq')
		cfg:wipe_all('dhcp', 'dnsmasq')
		cfg:set('dhcp.lan.ignore', 1)
		cfg:del('dhcp.lan.ra')

		core.kecho('Disabling DNS server...')
		if core.fileexists('/etc/config/stubby') then
			core.disable_service('stubby')
		end
		if core.fileexists('/etc/config/https-dns-proxy') then
			core.disable_service('https-dns-proxy')
		end
	end
end

local function apply_dns_resolver_config()
	core.kecho('Clearing existing DNS redirection...')
	-- Remove default resolv.conf
	core.runcmd("rm -f /etc/resolv.conf")

	local suffixes = { conf.suffix }
	if(conf.netdata.additional_dns_suffixes) then
		for k,v in pairs(conf.netdata.additional_dns_suffixes) do
			suffixes[1+#suffixes] = v
		end
	end

	if conf.is_router then
		-- Use localhost for DNS resolution instead of servers handed to us over DHCP (we have hard-coded servers instead)
		core.writefile('/etc/resolv.conf', 'search $suffix\nnameserver 127.0.0.1\n' % {suffix=table.concat(suffixes, ' ')})
	else
		-- Use the gateway for DNS resolution
		core.writefile('/etc/resolv.conf', 'search $suffix\nnameserver $gateway\n' % {suffix=table.concat(suffixes, ' '), gateway=conf.netdata.gateway})
	end
end

local function apply_hosts_config()
	if not core.fileexists('/etc/config/dhcp') then return end
	if not core.fileexists('/etc/config/firewall') then return end

	cfg:wipe_all('dhcp', 'host')
	cfg:wipe_all('dhcp', 'domain')
	cfg:wipe_all('firewall', 'redirect')

	if conf.is_router then
		core.kecho('Configuring hosts...')

		local lastoctetcomparator = function(a,b) return conf.netdata.devices[a].lastoctet < conf.netdata.devices[b].lastoctet end
		for mac,devdata in core.orderedpairs(conf.netdata.devices, lastoctetcomparator) do
			local alias_str = devdata.aliases and #devdata.aliases > 0
				and " (aliases: $aliases)" % {host=devdata.hostname, ip=devdata.ipv4, aliases=table.concat(devdata.aliases, ', ')} or ''

			local fwds = {}
			for _,forward in pairs(devdata.forwards or {}) do
				local e = cfg:add('firewall', 'redirect')
				if e then
					cfg:set(e, {
						target = 'DNAT',
						src = 'wan',
						dest = 'lan',
						proto = 'tcp udp',
						src_dport = forward.ext,
						dest_port = forward.int,
						dest_ip = devdata.ipv4,
						name = forward.name,
					})
					fwds[1+#fwds] = "$ext->$int" % {ext=forward.ext, int=forward.int}
				end
			end

			local forwards_str = (#fwds > 0) and " (port forwards: $forwards)" % {forwards=table.concat(fwds, ', ')} or ''

			core.kecho("${host:20s} -> ${ip:-15s} $alias_str$forwards_str" % {host=devdata.hostname, ip=devdata.ipv4, alias_str=alias_str, forwards_str=forwards_str})
			local e = cfg:add('dhcp', 'host')
			if e then
				cfg:set(e, {
					name = devdata.hostname,
					mac = mac,
					ip = devdata.ipv4,
					hostid = devdata.lastoctet,
				})
			end
			for _,host in pairs(devdata.all_hostnames) do
				local e = cfg:add('dhcp', 'domain')
				if e then
					cfg:set(e, {
						name = host,
						ip = devdata.ipv4,
					})
				end
				e = cfg:add('dhcp', 'domain')
				if e then
					cfg:set(e, {
						name = host,
						ip = devdata.ipv6,
					})
				end
			end
		end
	end
end

local function apply_stats_config()
	if not core.fileexists('/etc/config/nlbwmon') then return end

	if conf.is_router then
		core.kecho('Configuring nlbwmon...')
		cfg:set('nlbwmon.@nlbwmon[0]',
			{
				database_limit = 100000,
				local_network = {
					"${ipv4_prefix}.0/24" % {ipv4_prefix=conf.netdata.ipv4_prefix},
					"lan"
				}
			})
		core.enable_service('nlbwmon')
	else
		core.kecho('Disabling nlbwmon...')
		core.disable_service('nlbwmon')
	end
end

local function apply_mullvad_config()
	if conf.is_router and conf.netdata.mullvad then
		core.kecho('Configuring Mullvad VPN...')

		for _,v in pairs(conf.netdata.mullvad) do
			cfg:set('network.${iface_name}' % {iface_name=v.name}, 'interface')
			cfg:set('network.${iface_name}' % {iface_name=v.name}, {
				proto = 'wireguard',
				private_key = v.private_key,
				addresses = v.addresses
			})

			while cfg:get('network.@wireguard_${iface_name}[0]' % {iface_name=v.name}) ~= nil do
				cfg:del('network.@wireguard_${iface_name}[0]' % {iface_name=v.name})
			end

			local conn = cfg:add('network', 'wireguard_${iface_name}' % {iface_name=v.name})
			cfg:set(conn, {
				public_key = v.public_key,
				persistent_keepalive = 25,
				endpoint_host = v.endpoint_host,
				endpoint_port = v.endpoint_port,
				allowed_ips = { '0.0.0.0/0', '::0/0' },
				route_allowed_ips = v.default_route and 1 or 0
			})

			for _,entry in cfg:foreach('firewall', 'zone') do
				if cfg:get("${entry}.name") == v.name then
					cfg:del(entry)
				end
			end

			for _,entry in cfg:foreach('firewall', 'forwarding') do
				if cfg:get("${entry}.dest") == v.name and cfg:get("${entry}.src") == 'lan' then
					cfg:del(entry)
				end
			end

			local zone = cfg:add('firewall', 'zone')
			cfg:set(zone, {
				name = v.name,
				network = v.name,
				masq = 1,
				input = 'REJECT',
				output = 'ACCEPT',
				forward = 'REJECT'
			})

			local fwd = cfg:add('firewall', 'forwarding')
			cfg:set(fwd, {
				src = 'lan',
				dest = v.name
			})
		end
	end
end

local function apply_pushover_config()
	if not core.fileexists('/etc/config/pushover-notify') then return end

	cfg:wipe_all('pushover-notify', 'conf')

	if conf.netdata.pushover then
		core.kecho('Configuring Pushover notifications...')
		cfg:set('pushover-notify.conf', 'conf')
		cfg:set('pushover-notify.conf', {
			user = conf.netdata.pushover.user,
			app = conf.netdata.pushover.app,
			enabled = 1,
		})
	else
		core.kecho('Disabling Pushover notifications...')
	end
end

local function apply_getflix_config()
	if conf.is_router and conf.netdata.use_getflix then
		core.kecho('Configuring use of Getflix for Netflix...')
		cfg:set('dhcp.@dnsmasq[0].serversfile', '/custom/getflix-override.conf')

		core.appendfile('/etc/firewall.user', [[

# Netflix blocking
iptables -I FORWARD -d 108.175.32.0/255.255.240.0 -j REJECT
iptables -I FORWARD -d 198.38.96.0/255.255.224.0 -j REJECT
iptables -I FORWARD -d 198.45.48.0/255.255.240.0 -j REJECT
iptables -I FORWARD -d 185.2.220.0/255.255.252.0 -j REJECT
iptables -I FORWARD -d 23.246.0.0/255.255.192.0 -j REJECT
iptables -I FORWARD -d 37.77.184.0/255.255.248.0 -j REJECT
iptables -I FORWARD -d 45.57.0.0/255.255.128.0 -j REJECT
]])
	end
end

local function apply_wifi_config()
	core.kecho('Configuring WiFi...')
	cfg:wipe_all('wireless', 'wifi-iface')

	iface_idx = 0

	for i=0,5 do
		local radio = 'wireless.@wifi-device[$i]' % {i=i}

		local r
		pcall(function() r = cfg:get(radio) end)

		if r then
			local device_name = 'radio$i' % {i=i}
			cfg:set(radio, {
				type = 'mac80211',
				country = 'AU',
				disabled = 0,
			})

			local channel_2p4_GHz = 8
			local channel_5p8_GHz = 157

			local is5GHz = false
			local disable_radio = false

			local path = cfg:get('$radio.path' % {radio=radio})
			if path == "pci0000:00/0000:00:1c.3/0000:03:00.0" then -- Fanless MiniPC, Atheros card
				disable_radio = true
				is5GHz = true
				cfg:set(radio, {
					txpower = 20,
					channel = channel_5p8_GHz,
					htmode = 'HT40',
					hwmode = '11a',
					disabled = disable_radio and 1 or 0,
				})
			elseif path == "platform/soc/a000000.wifi" then -- GL-iNet B1300 / Asus RT-AC58U, 11bgn
				cfg:set(radio, {
					txpower = 30,
					channel = channel_2p4_GHz,
					htmode = 'HT40',
					hwmode = '11g'
				})
			elseif path == "platform/soc/a800000.wifi" then -- GL-iNet B1300 /Asus RT-AC58U, 11nac
				is5GHz = true
				cfg:set(radio, {
					txpower = 30,
					channel = channel_5p8_GHz,
					htmode = 'VHT80',
					hwmode = '11a'
				})
			elseif path == "platform/ar934x_wmac" then -- WDR-4300, 11bgn
				cfg:set(radio, {
					txpower = 20,
					channel = channel_2p4_GHz,
					htmode = 'HT40',
					hwmode = '11g'
				})
			elseif path == "pci0000:00/0000:00:00.0" then -- WDR-4300, 11an
				is5GHz = true
				cfg:set(radio, {
					txpower = 20,
					channel = channel_5p8_GHz,
					htmode = 'HT40',
					hwmode = '11a'
				})
			elseif path == "pci0000:00/0000:00:11.0" then -- WNDR3700v2, 11bgn
				cfg:set(radio, {
					txpower = 26,
					channel = channel_2p4_GHz,
					htmode = 'HT40',
					hwmode = '11g'
				})
			elseif path == "pci0000:00/0000:00:12.0" then -- WNDR3700v2, 11an
				is5GHz = true
				cfg:set(radio, {
					txpower = 23,
					channel = channel_5p8_GHz,
					htmode = 'HT40',
					hwmode = '11a'
				})
			elseif path == "platform/10180000.wmac" then -- MiWiFi Mini, 11bgn
				disassoc_low_ack = 0
				cfg:set(radio, {
					txpower = 17,
					channel = channel_2p4_GHz,
					htmode = 'HT20',
					hwmode = '11g'
				})
			elseif path == "pci0000:00/0000:00:00.0/0000:01:00.0" then -- MiWiFi Mini, 11nac
				disassoc_low_ack = 0
				is5GHz = true
				cfg:set(radio, {
					txpower = 17,
					channel = channel_5p8_GHz,
					htmode = 'VHT80',
					hwmode = '11a'
				})
			elseif path == "platform/ahb/18100000.wmac" then -- AC1750 Archer C7, 11bgn
				disassoc_low_ack = 0
				cfg:set(radio, {
					txpower = 24,
					channel = channel_2p4_GHz,
					htmode = 'HT20',
					hwmode = '11g'
				})
			elseif path == "pci0000:00/0000:00:00.0" then -- AC1750 Archer C7, 11nac
				disassoc_low_ack = 0
				is5GHz = true
				cfg:set(radio, {
					txpower = 23,
					channel = channel_5p8_GHz,
					htmode = 'VHT80',
					hwmode = '11a'
				})
			end

			local ssid = is5GHz and conf.netdata.ssid..' 5' or conf.netdata.ssid
			local ap_name =  'wireless.wifinet$idx' % {idx=iface_idx}
			iface_idx = iface_idx + 1
			local ap_iface = cfg:set(ap_name, 'wifi-iface')
			cfg:set(ap_name, {
				device = device_name,
				ssid = ssid,
				key = conf.netdata.password,
				mode = 'ap',
				encryption = 'sae-mixed',
				network = 'lan',
				ieee80211w = 1,
				disabled = disable_radio and 1 or 0,
				wpa_disable_eapol_key_retries = 1, -- KRACK attack mitigation
			})

			-- Helper for adding mesh interface for this radio
			local function add_mesh_interface(ifname)
				local mesh_name =  'wireless.wifinet$idx' % {idx=iface_idx}
				iface_idx = iface_idx + 1
				local mesh_iface = cfg:set(mesh_name, 'wifi-iface')
				cfg:set(mesh_name, {
					device = device_name,
					ifname = ifname,
					network = 'lan',
					mode = 'mesh',
					mesh_id = "$ssid Mesh" % {ssid = ssid},
					mesh_fwding = 1,
					encryption = 'sae',
					key = conf.netdata.password,
					sae_password = conf.netdata.password,
					disabled = disable_radio and 1 or 0,
					mesh_rssi_threshold = 0,
				})
			end

			if is5GHz and conf.netdata.mesh_5GHz then
				-- Add a 5GHz mesh interface if required
				add_mesh_interface('mesh5')
			elseif (not is5GHz) and conf.netdata.mesh_2GHz then
				-- Add a 2.4GHz mesh interface if required
				add_mesh_interface('mesh2')
			end
		end
	end
end

local function apply_vpn_policy_routing_config()
	if not core.fileexists('/etc/config/vpn-policy-routing') then return end

	cfg:wipe_all('vpn-policy-routing', 'policy')

	if conf.is_router then
		core.kecho('Configuring VPN Policy Routing...')

		local function translate_gateway(gateway)
			if gateway == 'br-lan' then
				return 'lan'
			end
			if gateway == conf.wan_if then
				return 'wan'
			end
			for k,v in pairs(conf.netdata.zerotier) do
				if v.interface == gateway then
					return k
				end
			end
			return gateway
		end

		local function create_policy(gateway, name, field, type, array)
			if gateway == 'br-lan' then return end
			if not array then return end
			local e = cfg:add('vpn-policy-routing', 'policy')
			cfg:set(e, {
				enabled = 1,
				name = '${name} ${type}' % {name=name,type=type},
				interface = translate_gateway(gateway),
				[field] = table.concat(array, ' ')
			})
		end

		for _,entry in pairs(conf.netdata.routing_policies) do
			if entry.catch_all then
				create_policy(entry.gateway, entry.name, 'dest_addr', 'Catch All', { '0.0.0.0/1', '128.0.0.0/1' })
			elseif not entry.advanced then
				create_policy(entry.gateway, entry.name, 'dest_addr', 'Domains', entry.remote_domains)
				create_policy(entry.gateway, entry.name, 'dest_addr', 'Remote Networks', entry.remote_networks)
				create_policy(entry.gateway, entry.name, 'dest_port', 'Remote Ports', entry.remote_ports)
				create_policy(entry.gateway, entry.name, 'src_addr', 'Local Networks', entry.local_networks)
				create_policy(entry.gateway, entry.name, 'src_port', 'Local Ports', entry.local_ports)
			else
				local e = cfg:add('policy-routing', 'policy')
				cfg:set(e, {
					name = '${name} ${type}' % {name=entry.name,type="Advanced"},
					interface = translate_gateway(gateway),
					dest_addr = (entry.remote_domains and (table.concat(entry.remote_domains, ' ') .. ' ') or '') .. (entry.remote_networks and table.concat(entry.remote_networks, ' ') or ''),
					dest_port = entry.remote_ports and table.concat(entry.remote_ports, ' ') or '',
					src_addr = entry.local_networks and table.concat(entry.local_networks, ' ') or '',
					src_port = entry.local_ports and table.concat(entry.local_ports, ' ') or '',
				})
			end
		end

		cfg:set('vpn-policy-routing.config.enabled', 1)

		core.enable_service('vpn-policy-routing')
	else
		core.kecho('Disabling VPN Policy Routing...')
		core.disable_service('vpn-policy-routing')
	end
end

local function apply_zerotier_config()
	if not core.fileexists('/etc/config/zerotier') then return end

	cfg:wipe_all('zerotier', 'zerotier')

	if conf.is_router and conf.netdata.zerotier then
		core.kecho('Configuring ZeroTier-One...')

		for name,data in pairs(conf.netdata.zerotier) do
			local entry = 'zerotier.${name}' % {name=name}
			cfg:set(entry, 'zerotier')
			cfg:set(entry, {
				join = { data.network },
				secret = data.secret,
				enabled = 1,
				interface = 'wan'
			})

			local network = 'network.${name}' % {name=name}
			cfg:set(network, 'interface')
			cfg:set(network, {
				proto = 'none',
				ifname = data.interface
			})

			local e = cfg:add('firewall', 'zone')
			cfg:set(e, {
				input = 'ACCEPT',
				output = 'ACCEPT',
				forward = 'ACCEPT',
				name = name,
				network = name
			})

			e = cfg:add('firewall', 'forwarding')
			cfg:set(e, {
				src = 'lan',
				dest = name
			})

			e = cfg:add('firewall', 'forwarding')
			cfg:set(e, {
				src = name,
				dest = 'lan'
			})

		end

		local r = cfg:add('firewall', 'rule')
		cfg:set(r, {
			dest_port = 9993,
			enabled = 1,
			name = 'ZeroTier-One',
			proto = 'tcp udp',
			src = 'wan',
			target = 'ACCEPT',
		})

		core.enable_service('zerotier')
	else
		core.kecho('Disabling ZeroTier-One...')
		core.disable_service('zerotier')
	end
end

core.writefile('/etc/rc.local', '')
core.writefile('/etc/crontabs/root', '')

apply_base_system_config()
apply_dhcp_server_config()
apply_dns_resolver_config()
apply_hosts_config()
apply_stats_config()
apply_mullvad_config()
apply_vpn_policy_routing_config()
apply_pushover_config()
apply_getflix_config()
apply_wifi_config()
apply_zerotier_config()

core.appendfile('/etc/rc.local', [[

# Fix factory reset -- rpcd is nullified for some reason
[ "$(cat /rom/etc/config/rpcd)" == "$(cat /etc/config/rpcd)" ] || cat /rom/etc/config/rpcd > /etc/config/rpcd

exit 0
]])

core.appendfile('/etc/crontabs/root', [[
42          3 * * *    /etc/init.d/dnsmasq restart
0,15,30,45  * * * *    /etc/init.d/unbound restart
5,20,35,50  * * * *    /etc/init.d/stubby restart
10,25,40,55 * * * *    /etc/init.d/https-dns-proxy restart
52          3 * * *    /sbin/wifi
]])

cfg:commit()
core.kecho('Configuring complete.')
