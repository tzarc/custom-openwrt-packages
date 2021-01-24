do
	local routers = {
		['my.lan'] = {
			{ host = 'router', iface = 'eth0', mac = '10:10:10:10:10:10', wan_if = "eth1", role = 'router' },
			{ host = 'wifi2', iface = 'eth0', mac = '20:20:20:20:20:20' },
			{ host = 'wifi3', iface = 'eth0', mac = '30:30:30:30:30:30' },
		},
	}

	local https_dns_proxy_configs = {
		['nextdns_a'] = {
			listen_addr = '127.0.0.1',
			listen_port = 5053,
			bootstrap = '1.1.1.1,1.0.0.1',
			resolver_url = 'https://dns.nextdns.io/c9999999/${hostname}'
		},
		['nextdns_b'] = {
			listen_addr = '127.0.0.1',
			listen_port = 5054,
			bootstrap = '1.1.1.1,1.0.0.1',
			resolver_url = 'https://dns.nextdns.io/c9999999/${hostname}'
		}
	}

	local stubby_configs = {
		nextdns = {
			{ auth_name = '${hostname}-c9999999.dns.nextdns.io', addresses = { '45.90.28.555', '45.90.30.555', '2a07:a8c0::c999:9999', '2a07:a8c1::c999:9999' } }
		}
	}

	local unbound_configs = {
		nextdns = {
			{ auth_name = '${hostname}-c9999999.dns.nextdns.io', addresses = { '45.90.28.555', '45.90.30.555', '2a07:a8c0::c999:9999', '2a07:a8c1::c999:9999' }, port = 853 }
		}
	}

	local mullvad_configs = {
		vpn_aus = {
			name = 'vpn_aus',
			private_key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
			public_key = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
			addresses = { '999.999.999.999/32', 'fc00:bbbb:bbbb::bbbb/128' }, --local
			endpoint_host = '999.999.999.999', --remote
			endpoint_port = 51820,
			default_route = true
		},
		vpn_swiss = {
			name = 'vpn_swiss',
			private_key = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=',
			public_key = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=',
			addresses = { '999.999.999.999/32', 'fc00:bbbb:bbbb::bbbb/128' }, --local
			endpoint_host = '999.999.999.999', --remote
			endpoint_port = 51820
		},
	}

	local pushover_configs = {
		pushover = {
			user = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
			app = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
		}
	}

	local standard_routing_policies = {
		{ gateway = 'eth1', name = 'Bitbucket/GitHub', remote_domains = { 'bitbucket.org', 'github.com', 'githubusercontent.com', 'github.io' } },
		{ gateway = 'eth1', name = 'OpenWrt', remote_domains = { 'openwrt.org' } },
		{ gateway = 'eth1', name = 'Getflix', remote_domains = { 'getflix.com.au' }, remote_networks = { '54.252.183.4', '54.252.183.5', '168.1.79.229', '202.59.96.140' } },
		{ gateway = 'eth1', name = 'Netflix', remote_domains = { 'netflix.com', 'nflxvideo.net', 'nflximg.net', 'nflxext.com', 'fast.com' } },
		{ gateway = 'eth1', name = 'AceStream', remote_ports = { '8621' } },
		{ gateway = 'eth1', name = 'Direct IP Check', remote_domains = { 'whatismyip.com' } },
	}

	local networks = {
		['my.lan'] = {
			ipv4_prefix = '192.168.1',
			ipv6_prefix = 'fdb9:7531',
			stubby = stubby_configs.nextdns,
			unbound = unbound_configs.nextdns,
			https_dns_proxy = { https_dns_proxy_configs.nextdns_a, https_dns_proxy_configs.nextdns_b },
			--external_logger = { target_host = '999.999.999.999', target_port = 99999 },
			mullvad = { mullvad_configs.vpn_aus, mullvad_configs.vpn_swiss },
			pushover = pushover_configs.pushover,
			devices = {
				['router'] = {
					hostname = 'test-wifi1',
					lastoctet = 1,
					aliases = { 'test-wifi', 'test-router', 'test-modem', 'wifi', 'router', 'modem' },
					forwards = {
						{ name = 'Internal SSH', ext = 10022, int = 22 },
						{ name = 'Internal Web', ext = 10080, int = 80 }
					}
				},
				['wifi2'] = { hostname = 'test-wifi2', lastoctet = 2 },
				['wifi3'] = { hostname = 'test-wifi3', lastoctet = 3 },
				['ab:cd:ef:01:23:45'] = { hostname = 'inner-host', lastoctet = 10 },
			},
			routing_policies = {},
			--additional_dns_suffixes = { 'not.my.lan', 'your.lan' },
			--dns_suffix_forwardings = { '/not.my.lan/192.168.2.1', '/your.lan/192.168.3.1' },
			--zerotier = {
			--	['zt1'] = {
			--		interface = 'zzzzzzzzzzz',
			--		network = 'aaaaaaaaaaaa',
			--		secret = 'asdlfkjsad;flkasdjf;lkasjdf;lkasjf;aslkfjas;lkfjas;lkfjas;lfkjas;lfkjasf;lkasjf;laskjf;laskjfas;ldkfjasd;lkfjas;lfkjasd;lfkjsad;lfkjsad;lfkjasj;lfdkj'
			--	}
			--},
		},
	}

	-- Ensure all standard routing policies are added
	for network, netdata in pairs(networks) do
		for _,policy in pairs(standard_routing_policies) do
			local rp = netdata.routing_policies
			rp[1+#rp] = policy
		end
	end

	local network_defs = {
		routers = routers,
		networks = networks,
	}

	local fixup_netdefs = require('fixup_netdefs')
	return fixup_netdefs(network_defs)
end
