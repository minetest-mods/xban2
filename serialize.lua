
local function repr(x)
	if type(x) == "string" then
		return ("%q"):format(x)
	else
		return tostring(x)
	end
end

local function my_serialize_2(t, level)
	level = level or 0
	local lines = { }
	local indent = ("\t"):rep(level)
	for k, v in pairs(t) do
		local typ = type(v)
		if typ == "table" then
			table.insert(lines,
			  indent..("[%s] = {\n"):format(repr(k))
			  ..my_serialize_2(v, level + 1).."\n"
			  ..indent.."},")
		else
			table.insert(lines,
			  indent..("[%s] = %s,"):format(repr(k), repr(v)))
		end
	end
	return table.concat(lines, "\n")
end

function xban.serialize(t)
	minetest.log("warning", "[xban2] xban.serialize() is deprecated")
	return "return {\n"..my_serialize_2(t, 1).."\n}"
end

-- JSON doesn't allow combined string+number keys, this function moves any
-- number keys into an "entries" table
function xban.serialize_db(t)
	local res = {}
	local entries = {}
	for k, v in pairs(t) do
		if type(k) == "number" then
			entries[k] = v
		else
			res[k] = v
		end
	end
	res.entries = entries
	return minetest.write_json(res, true)
end

function xban.deserialize_db(s)
	if s:sub(1, 1) ~= "{" then
		-- Load legacy databases
		return minetest.deserialize(s)
	end

	local res, err = minetest.parse_json(s)
	if not res then
		return nil, err
	end

	-- Remove all "null"s added by empty tables
	for i, entry in ipairs(res.entries or {}) do
		entry.names = entry.names or {}
		entry.record = entry.record or {}
		res[i] = entry
	end
	res.entries = nil

	return res
end
