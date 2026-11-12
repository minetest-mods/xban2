
xban = { MP = minetest.get_modpath(minetest.get_current_modname()) }

dofile(xban.MP.."/serialize.lua")

local db = { }
local tempbans = { }

local DEF_SAVE_INTERVAL = 300 -- 5 minutes
local DEF_DB_FILENAME = minetest.get_worldpath().."/xban.db"

local DB_FILENAME = minetest.settings:get("xban.db_filename")
local SAVE_INTERVAL = tonumber(
  minetest.settings:get("xban.db_save_interval")) or DEF_SAVE_INTERVAL

if (not DB_FILENAME) or (DB_FILENAME == "") then
	DB_FILENAME = DEF_DB_FILENAME
end

local function make_logger(level)
	return function(text, ...)
		minetest.log(level, "[xban] "..text:format(...))
	end
end

local ACTION = make_logger("action")
local WARNING = make_logger("warning")
local ERROR = make_logger("error")

local unit_to_secs = {
	s = 1, m = 60, h = 3600,
	D = 86400, W = 604800, M = 2592000, Y = 31104000,
	[""] = 1,
}

local function parse_time(t) --> secs
	local secs = 0
	for num, unit in t:gmatch("(%d+)([smhDWMY]?)") do
		secs = secs + (tonumber(num) * (unit_to_secs[unit] or 1))
	end
	return secs
end

local function concat_keys(t, sep)
	local keys = {}
	for k, _ in pairs(t) do
		keys[#keys + 1] = k
	end
	return table.concat(keys, sep)
end

-- Hands out the next value of a counter stored in the database
-- (`next_entry_id` or `next_record_id`). IDs are never reused, not even
-- after `/xban_cleanup` removed the entry they belonged to.
local function next_id(counter)
	local id = db[counter] or 1
	db[counter] = id + 1
	return id
end

-- Appends a record to the history of an entry and gives it an ID.
local function add_record(e, rec)
	rec.id = next_id("next_record_id")
	table.insert(e.record, rec)
	return rec
end

-- Gives entries and records without an ID one, and records without an
-- `action` one (derived from the reason, as older versions did not store
-- it). This covers databases written before IDs existed as well as entries
-- and records created by the importers or by other mods. Record IDs are
-- handed out in chronological order. Returns the number of entries and
-- records that were changed.
local function assign_missing_ids()
	local max_entry, max_record = 0, 0
	for _, e in ipairs(db) do
		if e.id and e.id > max_entry then max_entry = e.id end
		for _, rec in ipairs(e.record or {}) do
			if rec.id and rec.id > max_record then max_record = rec.id end
		end
	end
	db.next_entry_id = math.max(db.next_entry_id or 1, max_entry + 1)
	db.next_record_id = math.max(db.next_record_id or 1, max_record + 1)

	local changed_entries, changed_records = 0, 0
	local pending = { }
	for i, e in ipairs(db) do
		if not e.id then
			e.id = next_id("next_entry_id")
			changed_entries = changed_entries + 1
		end
		for j, rec in ipairs(e.record or {}) do
			local changed = false
			if not rec.action then
				rec.action = (rec.reason == "Unbanned") and "unban" or "ban"
				changed = true
			end
			if not rec.id then
				table.insert(pending, { rec = rec, i = i, j = j })
				changed = true
			end
			if changed then
				changed_records = changed_records + 1
			end
		end
	end
	-- table.sort is not stable: entry and record position break ties
	table.sort(pending, function(a, b)
		local ta, tb = a.rec.time or 0, b.rec.time or 0
		if ta ~= tb then return ta < tb end
		if a.i ~= b.i then return a.i < b.i end
		return a.j < b.j
	end)
	for _, p in ipairs(pending) do
		p.rec.id = next_id("next_record_id")
	end
	return changed_entries, changed_records
end

-- supports wildcard IP pattern (both IPv4 and IPv6)
function xban.find_entry(key, create)
	-- exact match (player or IP)
	for i, e in ipairs(xban.db) do
		if e.names[key] then return e, i end
	end
	-- wildcard pattern match for IPs
	if key and key:find("[.:]") then
		for i, e in ipairs(xban.db) do
			for name in pairs(e.names) do
				local wildcard_prefix = name:match("(.+[.:])%*$")
				if wildcard_prefix and key:sub(1, #wildcard_prefix) == wildcard_prefix then
					return e, i
				end
			end
		end
	end
	if create then
		local e = {
			id = next_id("next_entry_id"),
			names = { [key]=true },
			banned = false,
			record = { },
		}
		table.insert(xban.db, e)
		return e, #xban.db
	end
	return nil
end

function xban.get_info(player) --> ip_name_list, banned, last_record
	local e = xban.find_entry(player)
	if not e then
		return nil, "No such entry"
	end
	return e.names, e.banned, e.record[#e.record]
end

function xban.ban_player(player, source, expires, reason) --> bool, err
	if xban.get_whitelist(player) then
		return nil, "Player is whitelisted; remove from whitelist first"
	end
	local e = xban.find_entry(player, true)
	if e.banned then
		return nil, "Already banned"
	end
	local rec = {
		action = "ban",
		target = player,
		source = source,
		time = os.time(),
		expires = expires,
		reason = reason,
	}
	e.names[player] = true
	local pl = minetest.get_player_by_name(player)
	if pl then
		local ip = minetest.get_player_ip(player)
		if ip then
			e.names[ip] = true
		end
		local pos = pl:get_pos()
		e.last_pos = pos
		-- plain table, so it is stored as {x, y, z} without the vector metatable
		local p = vector.round(pos)
		rec.pos = { x = p.x, y = p.y, z = p.z }
	end
	add_record(e, rec)
	e.reason = reason
	e.time = rec.time
	e.expires = expires
	e.banned = true
	local msg
	local date = (expires and os.date("%c", expires)
	  or "the end of time")
	if expires then
		table.insert(tempbans, e)
		msg = ("Banned: Expires: %s, Reason: %s"):format(date, reason)
	else
		msg = ("Banned: Reason: %s"):format(reason)
	end
	for nm in pairs(e.names) do
		minetest.kick_player(nm, msg)
	end
	ACTION("%s bans %s until %s for reason: %s", source, player,
	  date, reason)
	ACTION("Banned Names/IPs: %s", concat_keys(e.names, ", "))
	return true
end

function xban.unban_player(player, source) --> bool, err
	local e = xban.find_entry(player)
	if not e then
		return nil, "No such entry"
	end
	add_record(e, {
		action = "unban",
		target = player,
		source = source,
		time = os.time(),
		reason = "Unbanned",
	})
	e.banned = false
	e.reason = nil
	e.expires = nil
	e.time = nil
	ACTION("%s unbans %s", source, player)
	ACTION("Unbanned Names/IPs: %s", concat_keys(e.names, ", "))
	return true
end

function xban.get_whitelist(name_or_ip)
	return db.whitelist and db.whitelist[name_or_ip]
end

function xban.remove_whitelist(name_or_ip)
	if db.whitelist then
		db.whitelist[name_or_ip] = nil
	end
end

function xban.add_whitelist(name_or_ip, source)
	local wl = db.whitelist
	if not wl then
		wl = { }
		db.whitelist = wl
	end
	wl[name_or_ip] = {
		source=source,
	}
	return true
end

function xban.get_record(player)
	local e = xban.find_entry(player)
	if not e then
		return nil, ("No entry for `%s'"):format(player)
	elseif (not e.record) or (#e.record == 0) then
		return nil, ("`%s' has no ban records"):format(player)
	end
	local record = { }
	for _, rec in ipairs(e.record) do
		local msg = rec.reason or "No reason given."
		if rec.expires then
			msg = msg..(", Expires: %s"):format(os.date("%c", rec.expires))
		end
		if rec.source then
			msg = msg..", Source: "..rec.source
		end
		-- e.g. "#12 ban Peter" (records from before this version have no target)
		local head = ("#%s %s"):format(rec.id or "?", rec.action or "ban")
		if rec.target then
			head = head.." "..rec.target
		end
		table.insert(record, ("[%s] %s: %s"):format(
		  os.date("%c", rec.time), head, msg))
	end
	local last_pos
	if e.last_pos then
		last_pos = ("User was last seen at %s"):format(
		  minetest.pos_to_string(e.last_pos))
	end
	return record, last_pos
end

minetest.register_on_prejoinplayer(function(name, ip)
	local wl = db.whitelist or {}
	if wl[name] or wl[ip] then return end

	local e = xban.find_entry(name)
	if not e or not e.banned then
		e = ip and xban.find_entry(ip)
	end

	if e and e.banned then
		local date = e.expires and os.date("%c", e.expires) or "the end of time"
		local reason = e.reason or "No reason given"
		return ("Banned: Expires: %s, Reason: %s"):format(date, reason)
	end
end)

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local e = xban.find_entry(name)
	local ip = minetest.get_player_ip(name)
	if not e then
		if ip then
			e = xban.find_entry(ip, true)
		else
			return
		end
	end
	e.names[name] = true
	if ip then
		e.names[ip] = true
	end
	e.last_seen = os.time()
end)

minetest.register_chatcommand("xban", {
	description = "XBan a player",
	params = "<player> <reason>",
	privs = { ban=true },
	func = function(name, params)
		local plname, reason = params:match("(%S+)%s+(.+)")
		if not (plname and reason) then
			return false, "Usage: /xban <player> <reason>"
		end
		local ok, e = xban.ban_player(plname, name, nil, reason)
		return ok, ok and ("Banned %s."):format(plname) or e
	end,
})

minetest.register_chatcommand("xtempban", {
	description = "XBan a player temporarily",
	params = "<player> <time> <reason>",
	privs = { ban=true },
	func = function(name, params)
		local plname, time, reason = params:match("(%S+)%s+(%S+)%s+(.+)")
		if not (plname and time and reason) then
			return false, "Usage: /xtempban <player> <time> <reason>"
		end
		time = parse_time(time)
		if time < 60 then
			return false, "You must ban for at least 60 seconds."
		end
		local expires = os.time() + time
		local ok, e = xban.ban_player(plname, name, expires, reason)
		return ok, (ok and ("Banned %s until %s."):format(
				plname, os.date("%c", expires)) or e)
	end,
})

minetest.register_chatcommand("xunban", {
	description = "XUnBan a player",
	params = "<player_or_ip>",
	privs = { ban=true },
	func = function(name, params)
		local plname = params:match("%S+")
		if not plname then
			minetest.chat_send_player(name,
			  "Usage: /xunban <player_or_ip>")
			return
		end
		local ok, e = xban.unban_player(plname, name)
		return ok, ok and ("Unbanned %s."):format(plname) or e
	end,
})

minetest.register_chatcommand("xban_record", {
	description = "Show the ban records of a player",
	params = "<player_or_ip>",
	privs = { ban=true },
	func = function(name, params)
		local plname = params:match("%S+")
		if not plname then
			return false, "Usage: /xban_record <player_or_ip>"
		end
		local record, last_pos = xban.get_record(plname)
		if not record then
			local err = last_pos
			minetest.chat_send_player(name, "[xban] "..err)
			return
		end
		for _, e in ipairs(record) do
			minetest.chat_send_player(name, "[xban] "..e)
		end
		if last_pos then
			minetest.chat_send_player(name, "[xban] "..last_pos)
		end
		return true, "Record listed."
	end,
})

minetest.register_chatcommand("xban_wl", {
	description = "Manages the whitelist",
	params = "(add|del|get) <name_or_ip>",
	privs = { ban=true },
	func = function(name, params)
		local cmd, plname = params:match("%s*(%S+)%s*(%S+)")
		if cmd == "add" then
			xban.add_whitelist(plname, name)
			ACTION("%s adds %s to whitelist", name, plname)
			return true, "Added to whitelist: "..plname
		elseif cmd == "del" then
			xban.remove_whitelist(plname)
			ACTION("%s removes %s to whitelist", name, plname)
			return true, "Removed from whitelist: "..plname
		elseif cmd == "get" then
			local e = xban.get_whitelist(plname)
			if e then
				return true, "Source: "..(e.source or "Unknown")
			else
				return true, "No whitelist for: "..plname
			end
		end
	end,
})


local function check_temp_bans()
	minetest.after(60, check_temp_bans)
	local now = os.time()
	-- backwards, so table.remove does not skip the following element
	for i = #tempbans, 1, -1 do
		local e = tempbans[i]
		if not (e.banned and e.expires) then
			-- unbanned by hand or banned again permanently in the meantime
			table.remove(tempbans, i)
		elseif e.expires <= now then
			-- the time of the record is the actual expiry, even if the server
			-- was not running at that moment
			add_record(e, {
				action = "unban",
				source = "xban:expired",
				time = e.expires,
				reason = "Unbanned",
			})
			ACTION("Ban expired for Names/IPs: %s", concat_keys(e.names, ", "))
			e.banned = false
			e.expires = nil
			e.reason = nil
			e.time = nil
			table.remove(tempbans, i)
		end
	end
end

local function write_db()
	-- catches entries and records added by the importers or by other mods
	assign_missing_ids()
	db.timestamp = os.time()
	local contents = assert(xban.serialize_db(db))
	local ok = minetest.safe_file_write(DB_FILENAME, contents)
	if not ok then
		ERROR("Unable to save database")
	end
end

local function save_db()
	minetest.after(SAVE_INTERVAL, save_db)
	write_db()
end

local function load_db()
	local f, e = io.open(DB_FILENAME, "r")
	if not f then
		WARNING("Unable to load database: %s", e)
		return
	end
	local cont = f:read("*a")
	f:close()
	if not cont then
		WARNING("Unable to load database: %s", "Read failed")
		return
	end
	local t, e2 = xban.deserialize_db(cont)
	if not t then
		WARNING("Unable to load database: %s",
		  "Deserialization failed: "..(e2 or "unknown error"))
		return
	end
	db = t
	tempbans = { }
	for _, entry in ipairs(db) do
		if entry.banned and entry.expires then
			table.insert(tempbans, entry)
		end
	end

	local changed_entries, changed_records = assign_missing_ids()
	if changed_entries > 0 or changed_records > 0 then
		-- keep the database as it was before the first conversion
		local backup = DB_FILENAME..".before-ids"
		local bf = io.open(backup, "r")
		if bf then
			bf:close()
		elseif minetest.safe_file_write(backup, cont) then
			ACTION("Saved the unconverted database as %s", backup)
		else
			ERROR("Unable to save a backup of the database as %s", backup)
		end
		ACTION("Assigned IDs to %d entries and %d records",
		  changed_entries, changed_records)
		write_db()
	end
end

minetest.register_chatcommand("xban_cleanup", {
	description = "Removes all non-banned entries from the xban db",
	privs = { server=true },
	func = function(name, params)
		local old_count = #db

		local i = 1
		while i <= #db do
			if not db[i].banned then
				-- not banned, remove from db
				table.remove(db, i)
			else
				-- banned, hold entry back
				i = i + 1
			end
		end

		-- save immediately (save_db would start a second save loop)
		write_db()

		return true, "Removed " .. (old_count - #db) .. " entries, new db entry-count: " .. #db
	end,
})

minetest.register_on_shutdown(write_db)
minetest.after(SAVE_INTERVAL, save_db)
load_db()
xban.db = db

minetest.after(1, check_temp_bans)

dofile(xban.MP.."/dbimport.lua")
dofile(xban.MP.."/gui.lua")
