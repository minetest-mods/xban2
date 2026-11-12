-- IP blacklist, kept apart from the ban entries.
--
-- Connections from a blacklisted IP are refused before the password is
-- checked, for every account, whitelisted or not. Blacklisted IPs therefore
-- never join and never end up in the names of an entry. The list is stored in
-- the mod storage, not in xban.db.
--
-- Patterns are exact addresses or prefixes with a trailing "*" (as for
-- wildcard bans), e.g. "203.0.113.42", "203.0.113.*" or "2001:db8:*".
-- IPv4-mapped IPv6 addresses ("::ffff:1.2.3.4") count as the IPv4 address.

local storage = minetest.get_mod_storage()
local STORAGE_KEY = "ip_blacklist"

-- "wrong_password": pretend the password was wrong, so the person behind the
-- IP does not think of switching to another one. "banned": say so.
local MESSAGE_MODE = minetest.settings:get("xban.ip_blacklist_message")
	or "wrong_password"
-- Clients show this as "Access denied. Reason: <text>". The real message is
-- translated by the client ("Zugriff verweigert. Grund: Falsches Passwort" on
-- German clients), this one is not: use the language of most players.
local WRONG_PASSWORD_TEXT = minetest.settings:get("xban.wrong_password_text")
	or "Invalid password"
local BANNED_TEXT = "Banned: Your IP address is blocked."
-- Players who are online when their IP is added. A wrong password cannot
-- happen in the middle of a game, so they get what a real shutdown shows
-- ("Access denied. Reason: Server shutting down."), without the "Kicked: "
-- that kick_player puts in front.
local KICK_TEXT = minetest.settings:get("xban.ip_blacklist_kick_text")
	or "Server shutting down."

local function ACTION(text, ...)
	minetest.log("action", "[xban] "..text:format(...))
end

function xban.normalize_ip(ip)
	return (ip:lower():gsub("^::ffff:", ""))
end

-- Accepts exact IPv4/IPv6 addresses and prefixes ending in ".*" or ":*".
-- Expects a normalized pattern.
function xban.valid_ip_pattern(p)
	if #p > 64 or not p:find("[.:]") then
		return false
	end
	local body, star = p:match("^([%x.:]+)(%*?)$")
	if not body then
		return false
	end
	if star == "*" then
		if not body:find("[.:]$") then
			return false
		end
	elseif body:find("%.$") or (body:find(":$") and not body:find("::$")) then
		return false
	end
	if not body:find(":") then
		local parts = 0
		for part in body:gmatch("[^.]+") do
			parts = parts + 1
			if not part:match("^%d+$") or tonumber(part) > 255 then
				return false
			end
		end
		if body:find("%.%.") or body:find("^%.") or parts > 4
				or (star == "" and parts ~= 4) then
			return false
		end
	end
	return true
end

-- Whether `ip` (or a name that is an IP) is matched by `pattern`
function xban.ip_matches(pattern, ip)
	pattern, ip = xban.normalize_ip(pattern), xban.normalize_ip(ip)
	if pattern == ip then
		return true
	end
	local prefix = pattern:match("^(.+[.:])%*$")
	return prefix ~= nil and ip:sub(1, #prefix) == prefix
end

local function load_list()
	local raw = storage:get_string(STORAGE_KEY)
	local list = raw ~= "" and minetest.parse_json(raw) or nil
	return type(list) == "table" and list or { }
end

local blacklist = load_list()

local function save_list()
	if next(blacklist) == nil then
		storage:set_string(STORAGE_KEY, "")
	else
		storage:set_string(STORAGE_KEY, minetest.write_json(blacklist))
	end
end

-- { [pattern] = { source = ..., time = ..., reason = ... } }. Read only.
function xban.get_ip_blacklist()
	return blacklist
end

-- Returns pattern, entry of the first pattern matching `ip`, or nil.
function xban.find_ip_blacklist(ip)
	local exact = xban.normalize_ip(ip)
	if blacklist[exact] then
		return exact, blacklist[exact]
	end
	for pattern, entry in pairs(blacklist) do
		if xban.ip_matches(pattern, ip) then
			return pattern, entry
		end
	end
end

local function denial_text()
	if MESSAGE_MODE == "banned" then
		return BANNED_TEXT
	end
	return WRONG_PASSWORD_TEXT
end

-- Message for refusing a connection from `ip`, or nil if it is not
-- blacklisted
function xban.ip_blacklist_denial(ip, name)
	local pattern = xban.find_ip_blacklist(ip)
	if pattern then
		ACTION("Refused %s from blacklisted IP %s (%s)", name or "?", ip,
		  pattern)
		return denial_text()
	end
end

-- Adds a pattern and kicks connected players whose IP it matches.
-- Returns pattern, number of kicked players or nil, error.
function xban.add_ip_blacklist(pattern, source, reason)
	pattern = xban.normalize_ip(pattern or "")
	if not xban.valid_ip_pattern(pattern) then
		return nil, "Invalid IP address or pattern: "..pattern
	end
	if blacklist[pattern] then
		return nil, pattern.." is already on the blacklist"
	end
	blacklist[pattern] = {
		source = source,
		time = os.time(),
		reason = (reason and reason ~= "") and reason or nil,
	}
	save_list()
	ACTION("%s adds %s to the IP blacklist%s", source or "?", pattern,
	  reason and reason ~= "" and (": "..reason) or "")
	local kicked = 0
	for _, player in ipairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local ip = minetest.get_player_ip(name)
		if ip and xban.ip_matches(pattern, ip) then
			if MESSAGE_MODE == "banned" or not minetest.disconnect_player then
				minetest.kick_player(name, denial_text())
			else
				minetest.disconnect_player(name, KICK_TEXT)
			end
			kicked = kicked + 1
			ACTION("Kicked %s, IP %s is now blacklisted", name, ip)
		end
	end
	return pattern, kicked
end

-- Returns pattern or nil, error
function xban.remove_ip_blacklist(pattern, source)
	pattern = xban.normalize_ip(pattern or "")
	if not blacklist[pattern] then
		return nil, pattern.." is not on the blacklist"
	end
	blacklist[pattern] = nil
	save_list()
	ACTION("%s removes %s from the IP blacklist", source or "?", pattern)
	return pattern
end

minetest.register_chatcommand("xban_ipbl", {
	description = "Manages the IP blacklist (blocks all connections)",
	params = "add <ip> [note] | del <ip> | check <ip> | list",
	privs = { ban=true },
	func = function(name, params)
		local cmd, ip, note = params:match("^%s*(%S+)%s*(%S*)%s*(.-)%s*$")
		if cmd == "list" then
			local patterns = { }
			for pattern in pairs(blacklist) do
				table.insert(patterns, pattern)
			end
			if #patterns == 0 then
				return true, "The IP blacklist is empty."
			end
			table.sort(patterns)
			for _, pattern in ipairs(patterns) do
				local e = blacklist[pattern]
				minetest.chat_send_player(name, ("[xban] %s (by %s, %s)%s"):format(
				  pattern, e.source or "?", e.time and os.date("%c", e.time) or "?",
				  e.reason and (": "..e.reason) or ""))
			end
			return true, #patterns.." blacklisted IPs/patterns."
		elseif ip == "" then
			return false, "Usage: /xban_ipbl add <ip> [note] | del <ip> | check <ip> | list"
		elseif cmd == "add" then
			local pattern, kicked = xban.add_ip_blacklist(ip, name, note)
			if not pattern then
				return false, kicked
			end
			return true, ("Added %s to the IP blacklist%s."):format(pattern,
			  kicked > 0 and (", kicked "..kicked.." players") or "")
		elseif cmd == "del" then
			local pattern, err = xban.remove_ip_blacklist(ip, name)
			if not pattern then
				return false, err
			end
			return true, "Removed "..pattern.." from the IP blacklist."
		elseif cmd == "check" then
			local pattern = xban.find_ip_blacklist(ip)
			if pattern then
				return true, ip.." is blacklisted by "..pattern
			end
			return true, ip.." is not blacklisted."
		end
		return false, "Usage: /xban_ipbl add <ip> [note] | del <ip> | check <ip> | list"
	end,
})
