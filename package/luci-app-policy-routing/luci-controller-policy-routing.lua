module("luci.controller.policy-routing", package.seeall)
function index()
	if not nixio.fs.access("/etc/config/policy-routing") then
		return
	end
	entry({"admin", "services", "policy-routing"}, cbi("policy-routing"), _("Policy Routing"), 99).dependent = false
end
