-- String splitting
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
--[[
print( "${key} is ${val:7.2f}%" % {key = "concentration", val = 56.2795} )
print( ("${key} is ${val:7.2f}%"):interp({key = "concentration", val = 56.2795}) )
print( interp("${key} is ${val:7.2f}%", {key = "concentration", val = 56.2795}) )
--]]
