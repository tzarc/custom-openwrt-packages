m = Map("private-internet-access", translate("Private Internet Access"))

local servers = {''}
local fd = nixio.open("/usr/share/pia/servers.list", "r")
if fd then
	for ln in fd:linesource() do
		local name, server = ln:match("([^:]+):(.*)")
		servers[1+#servers] = name
	end
end

c = m:section(NamedSection, "config", "config", translate("Configuration"))
ll = c:option(ListValue, "loglevel", translate("Log Level"))
ll:value(0, translate('Off'))
ll:value(1, translate('Normal'))
ll:value(2, translate('Debug'))

btn = c:option(Button, "update", translate("Servers"))
btn.inputtitle = translate("Update to latest PIA server definitions")
btn.inputstyle = "apply"
btn.disabled = false
function btn.write() luci.sys.call("/usr/bin/update-pia-servers /usr/share/pia >/dev/null 2>&1") end

s = m:section(TypedSection, "connection", translate("Connections"))
s.addremove = true
s.anonymous = true
s.template = "cbi/tblsection"

en = s:option(Flag, "enabled", translate("Enabled"))
en.datatype = "bool"

nm = s:option(Value, "name", translate("Interface Name"))
nm.datatype = "and(uciname,maxlength(15))"
nm.rmempty = true
nm.placeholder = 'pia0'
nm.default = 'pia0'

un = s:option(Value, "username", translate("Username"))
un.datatype = "string"
un.rmempty = true
un.placeholder = 'p1234567'

pw = s:option(Value, "password", translate("Password"))
pw.datatype = "string"
pw.password = true
pw.rmempty = true

sv = s:option(ListValue, "server", translate("Server"))
for k,v in pairs(servers) do sv:value(v) end

tb = s:option(Value, "routing_table", translate("Routing Table Index"))
tb.datatype = "and(uinteger,max(32765))"

return m
