module("luci.controller.private-internet-access", package.seeall)
function index()
	if not nixio.fs.access("/etc/config/private-internet-access") then
		return
	end
	entry({"admin", "services", "private-internet-access"}, cbi("private-internet-access"), _("Private Internet Access"), 99).dependent = false
end
