module("luci.controller.pushover-notify", package.seeall)
function index()
	if not nixio.fs.access("/etc/config/pushover-notify") then
		return
	end
	entry({"admin", "services", "pushover-notify"}, cbi("pushover-notify"), _("Pushover Notifications"))
end
