require("luci.ip")
require("luci.model.uci")

local baseParams = {
	-- Widget, ConfigEntry, Title, Default(s), Description
	{ Flag, "enabled", translate("Enable Pushover Notifications"), '', '' },
	{ Value, "app", translate("Application Token"), '', '' },
	{ Value, "user", translate("User Token"), '', '' },
}

local toggleParams = {
	-- Widget, ConfigEntry, Title, Default(s), Description
	{ Flag, "on_unconfigured_dhcp", translate('Unconfigured host DHCP leases'), '', translate("Sends a notification when a device requests a DHCP lease, which doesn't have a static lease configured.") },
}

local function addToSection(section, params)
	for _, option in ipairs(params) do
		local o = section:option(option[1], option[2], option[3], option[5])

		if option[1] == DummyValue then
			o.value = option[4]
		else
			if option[1] == DynamicList then
				function o.cfgvalue(...)
					local val = AbstractValue.cfgvalue(...)
					return (val and type(val) ~= "table") and { val } or val
				end
			end

			if type(option[4]) == "table" then
				for _, v in ipairs(option[4]) do
					v = tostring(v)
					o:value(v)
				end
				o.default = tostring(option[4][1])
			else
				o.default = tostring(option[4])
			end
		end

		for i = 5, #option do
			if type(option[i]) == "table" then
				o:depends(option[i])
			end
		end

		if type(option[6]) == 'function' then option[6](o) end
	end
end

local m = Map("pushover-notify")
local p1 = m:section(NamedSection, 'conf', 'conf', translate("Pushover Configuration"))
addToSection(p1, baseParams)
local p2 = m:section(NamedSection, 'conf', 'conf', translate("Notifications"))
addToSection(p2, toggleParams)

return m
