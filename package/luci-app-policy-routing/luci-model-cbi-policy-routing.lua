m = Map("policy-routing", translate("Policy Routing"))

c = m:section(NamedSection, "config", "config", translate("Configuration"))
do
	en = c:option(Flag, "enabled", translate("Enabled"))
	en.datatype = "bool"

	ll = c:option(ListValue, "loglevel", translate("Log Level"))
	ll:value(0, translate('Off'))
	ll:value(1, translate('Normal'))
	ll:value(2, translate('Debug'))
end

g = m:section(TypedSection, "interface", translate("Gateways"))
g.addremove = true
g.anonymous = true
do
	interface = g:option(Value, "interface", translate("Interface Name"))
	interface.datatype = "and(uciname,maxlength(15))"
	interface.rmempty = true
	interface.placeholder = 'eth1'

	strict = g:option(Flag, "strict", translate("Disallow non-policy traffic"))
	strict.datatype = "bool"
end

p = m:section(TypedSection, "policy", translate("Policies"))
p.addremove = true
p.anonymous = true
do
	comment = p:option(Value, "comment", translate("Comment"))
	comment.datatype = "string"
	comment.rmempty = true

	interface = p:option(Value, "interface", translate("Gateway"))
	interface.datatype = "and(uciname,maxlength(15))"
	interface.rmempty = true
	interface.placeholder = 'eth1'

	policy_type = p:option(ListValue, "type", translate("Type"))
	policy_type:value('local_nets', translate('Local Networks'))
	policy_type:value('local_ports', translate('Local Ports'))
	policy_type:value('remote_nets', translate('Remote Networks'))
	policy_type:value('remote_ports', translate('Remote Ports'))
	policy_type:value('domains', translate('Domains'))
	policy_type:value('catch-all', translate('Catch-All'))
	policy_type:value('advanced', translate('Advanced'))

	local_nets = p:option(DynamicList, "local_nets", translate("Local Networks"))
	local_nets:depends('type', 'local_nets')
	local_nets:depends('type', 'advanced')
	local_nets.datatype = 'ipaddr'

	local_ports = p:option(DynamicList, "local_ports", translate("Local Ports"))
	local_ports:depends('type', 'local_ports')
	local_ports:depends('type', 'advanced')
	local_ports.datatype = 'portrange'

	remote_nets = p:option(DynamicList, "remote_nets", translate("Remote Networks"))
	remote_nets:depends('type', 'remote_nets')
	remote_nets:depends('type', 'advanced')
	remote_nets.datatype = 'ipaddr'

	remote_ports = p:option(DynamicList, "remote_ports", translate("Remote Ports"))
	remote_ports:depends('type', 'remote_ports')
	remote_ports:depends('type', 'advanced')
	local_ports.datatype = 'portrange'

	domains = p:option(DynamicList, "domains", translate("Domains"))
	domains:depends('type', 'domains')
	domains:depends('type', 'advanced')
	local_ports.datatype = 'hostname'
end

return m
