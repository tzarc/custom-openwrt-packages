do
	local core = require('core')

	return function(network_defs)
		local routers = network_defs.routers
		local networks = network_defs.networks

		------------------------------------------------------------------------------------------------------------------------
		-- Force routers table to all be in lowercase hosts etc.
		for domain,data in core.orderedpairs(routers) do
			routers[domain] = nil
			domain = domain:lower()
			routers[domain] = data

			for k,v in pairs(data) do
				local d = data[k]
				data[k] = nil
				if type(k) == 'string' then k = k:lower() end
				if type(v) == 'string' then v = v:lower() end
				data[k] = v
			end
		end

		------------------------------------------------------------------------------------------------------------------------
		-- Update device entries with full set of hostnames and IPs
		for suffix,netdata in core.orderedpairs(networks) do
			networks[suffix] = nil
			suffix = suffix:lower()
			networks[suffix] = netdata

			-- Add the suffix to the inner table
			netdata.suffix = suffix
			-- Add the gateway to the inner table
			netdata.gateway = '$prefix.1' % {prefix=netdata.ipv4_prefix}

			-- Ensure that the mac addresses are lowercase
			for mac,devdata in core.orderedpairs(netdata.devices or {}) do
				netdata.devices[mac] = nil
				mac = mac:lower()
				netdata.devices[mac] = devdata

				-- Client mode by default
				devdata.is_router = false
				-- Add the mac to the inner table
				devdata.mac = mac
				-- Work out the full IPv4/6 addressese
				devdata.ipv4 = '$ipv4_prefix.$lastoctet' % {ipv4_prefix=netdata.ipv4_prefix, lastoctet=devdata.lastoctet}
				devdata.ipv6 = '$ipv6_prefix::$lastoctet' % {ipv6_prefix=netdata.ipv6_prefix, lastoctet=devdata.lastoctet}
				-- Determine the hostnames
				devdata.all_hostnames = { devdata.hostname:lower() }
				-- Cater for any aliases
				for _,alias in pairs(devdata.aliases or {}) do
					table.insert(devdata.all_hostnames, alias:lower())
				end
			end
		end

		return network_defs
	end
end
