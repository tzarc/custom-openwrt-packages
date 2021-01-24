do
	local uci = require('uci')
	require('string_extra')

	------------------------------------------------------------------------------------------------------------------------

	local function is_array(t)
		local i = 0
		for _ in pairs(t) do
			i = i + 1
			if t[i] == nil then return false end
		end
		return true
	end

	------------------------------------------------------------------------------------------------------------------------

	local cfg = uci.cursor()
	local modified_configs = {}

	local function cfg_get_entry(config, typename, index)
		local all = {}
		cfg:foreach(config, typename, function(s)
			all[1+#all] = s['.name']
		end)
		if type(index) ~= 'number' then
			if type(index) == 'string' and index == '*' then
				return unpack(all)
			else
				return nil
			end
		elseif index >= 0 then
			return all[1+index]
		else
			return all[1+index+#all]
		end
	end

	local function cfg_recompose(hasValue, entries)
		local p = { unpack(entries) }
		if hasValue then
			local v = p[#p]
			p[#p] = nil
			return table.concat(p, '.') .. ' = ' .. (type(v) == 'table' and ('{ \''..table.concat(v, '\', \'')..'\' }') or ('\''..tostring(v)..'\''))
		else
			return table.concat(p, '.')
		end
	end

	local function cfg_decompose(path)
		local total = {}
		local e = path:split('.')
		for k, v in pairs(e) do
			local t, i = v:match('@([^%[]+)%[(%-?%d+)%]') -- @type[idx] -> cfgXXXXXX
			if t and i then
				local n = cfg_get_entry(unpack(total), t, tonumber(i))
				if not n then error("Could not find equivalent decomposed path: '$path'" % {path=path}) end
				total[1 + #total] = n
			else
				total[1 + #total] = v
			end
		end
		return unpack(total)
	end

	local function cfg_log(self, oper, originalPath, decomposedPath, hasValue)
		if self.verbose then
			if originalPath:find('@') then
				print('$operation: $actualPath      # $path' % {operation=oper, path=originalPath, actualPath=cfg_recompose(hasValue, decomposedPath)})
			else
				print('$operation: $path' % {operation=oper, path=cfg_recompose(hasValue, decomposedPath)})
			end
		end
	end

	local function cfg_set(self, path, value)
		if type(value) == 'table' and not is_array(value) then
			for k, v in pairs(value) do
				local a = { cfg_decompose(path) }
				a[1 + #a] = k
				a[1 + #a] = v
				cfg_log(self, 'setting', path, a, true)
				cfg:set(unpack(a))
				modified_configs[a[1]] = true
			end
		else
			local a = { cfg_decompose(path) }
			a[1 + #a] = value
			cfg_log(self, 'setting', path, a, true)
			cfg:set(unpack(a))
			modified_configs[a[1]] = true
		end
	end

	local function cfg_get(self, path)
		local ok, ret = pcall(function()
			local a = { cfg_decompose(path) }
			cfg_log(self, 'getting', path, a, false)
			for k,v in pairs(a) do print(tostring(k), tostring(v)) end
			return cfg:get(unpack(a))
		end)
		if ok then return ret else return nil end
	end

	local function cfg_foreach(self, config, typename)
		local all = { cfg_get_entry(config, typename, '*') }
		for k,v in pairs(all) do all[k] = '$config.$entry' % {config=config, entry=v} end
		local function cfg_foreach_it(all, i)
			i = i + 1
			local v = all[i]
			if v ~= nil then return i, v end
			return nil
		end
		return cfg_foreach_it, all, 0
	end

	local function cfg_add(self, config, typename)
		modified_configs[config] = true
		return '$config.$name' % {config=config, name=cfg:add(config, typename)}
	end

	local function cfg_del(self, path)
		if type(value) == 'table' then
			for k, v in pairs(value) do
				local a = { cfg_decompose(path) }
				cfg_log(self, 'deleting', path, a, false)
				cfg:delete(unpack(a))
				modified_configs[a[1]] = true
			end
		else
			local a = { cfg_decompose(path) }
			cfg_log(self, 'deleting', path, a, false)
			cfg:delete(unpack(a))
			modified_configs[a[1]] = true
		end
	end

	local function cfg_wipe_all(self, config, typename)
		for _,entry in cfg_foreach(self, config, typename) do
			cfg_del(self, entry)
		end
	end

	local function cfg_commit(self, config)
		if type(config) == 'nil' then
			for k,v in pairs(modified_configs) do
				cfg_commit(self, k)
			end
		else
			cfg_log(self, 'committing', config, {config}, false)
			cfg:commit(config)
			modified_configs[config] = nil
		end
	end

	------------------------------------------------------------------------------------------------------------------------

	return {
		verbose = false,
		set = cfg_set,
		get = cfg_get,
		foreach = cfg_foreach,
		wipe_all = cfg_wipe_all,
		add = cfg_add,
		del = cfg_del,
		commit = cfg_commit,
	}
end
