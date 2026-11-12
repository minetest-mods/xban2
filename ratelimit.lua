-- Rate limit for failed logins: after `xban.auth_fail_max` wrong passwords
-- from one IP within `xban.auth_fail_window` seconds, connections from that
-- IP are refused for `xban.auth_block_time` seconds. Protects accounts with
-- weak passwords against guessing. The state is kept in memory only, a
-- restart lifts all blocks.

local settings = minetest.settings
local FAIL_MAX = tonumber(settings:get("xban.auth_fail_max")) or 5
local FAIL_WINDOW = tonumber(settings:get("xban.auth_fail_window")) or 600
local BLOCK_TIME = tonumber(settings:get("xban.auth_block_time")) or 3600
local CLEANUP_INTERVAL = 600

local failures = { }  -- [ip] = { { t = time, name = name }, ... }
local blocked = { }   -- [ip] = { till = time, names = "a, b, c" }

local function ACTION(text, ...)
	minetest.log("action", "[xban] "..text:format(...))
end

local function recent(list, now)
	local kept = { }
	for _, f in ipairs(list or { }) do
		if now - f.t < FAIL_WINDOW then
			table.insert(kept, f)
		end
	end
	return kept
end

local function distinct_names(list)
	local seen, names = { }, { }
	for _, f in ipairs(list) do
		if not seen[f.name] then
			seen[f.name] = true
			table.insert(names, f.name)
		end
	end
	return table.concat(names, ", ")
end

if FAIL_MAX > 0 then
	if minetest.register_on_authplayer then
		minetest.register_on_authplayer(function(name, ip, is_success)
			if not ip then
				return
			end
			local key = xban.normalize_ip(ip)
			if is_success then
				failures[key] = nil
				return
			end
			local now = os.time()
			local list = recent(failures[key], now)
			table.insert(list, { t = now, name = name })
			if #list >= FAIL_MAX then
				failures[key] = nil
				blocked[key] = { till = now + BLOCK_TIME, names = distinct_names(list) }
				ACTION("Rate limit: blocked IP %s for %d s after %d failed logins within %d s (names: %s)",
				  key, BLOCK_TIME, #list, FAIL_WINDOW, blocked[key].names)
			else
				failures[key] = list
			end
		end)
	else
		minetest.log("warning", "[xban] register_on_authplayer is not "
		  .."available, the login rate limit is disabled")
	end
end

-- Returns the time until which `ip` is blocked, or nil
function xban.get_auth_block(ip)
	local key = xban.normalize_ip(ip)
	local b = blocked[key]
	if b and b.till <= os.time() then
		blocked[key] = nil
		return nil
	end
	return b and b.till
end

-- Message for refusing a connection from `ip`, or nil if it is not blocked
function xban.auth_block_denial(ip, name)
	local till = xban.get_auth_block(ip)
	if till then
		ACTION("Refused %s from rate limited IP %s", name or "?", ip)
		return ("Too many failed login attempts. Please try again in %d minutes.")
		  :format(math.ceil((till - os.time()) / 60))
	end
end

local function cleanup()
	minetest.after(CLEANUP_INTERVAL, cleanup)
	local now = os.time()
	for ip, list in pairs(failures) do
		local kept = recent(list, now)
		failures[ip] = #kept > 0 and kept or nil
	end
	for ip, b in pairs(blocked) do
		if b.till <= now then
			blocked[ip] = nil
		end
	end
end
minetest.after(CLEANUP_INTERVAL, cleanup)

minetest.register_chatcommand("xban_authblock", {
	description = "Lists or lifts IP blocks of the login rate limit",
	params = "list | clear <ip>",
	privs = { ban=true },
	func = function(name, params)
		local cmd, ip = params:match("^%s*(%S+)%s*(%S*)")
		if cmd == "clear" and ip ~= "" then
			local key = xban.normalize_ip(ip)
			if not blocked[key] then
				return false, key.." is not blocked."
			end
			blocked[key] = nil
			failures[key] = nil
			ACTION("%s lifts the rate limit block of %s", name, key)
			return true, "Lifted the block of "..key.."."
		elseif cmd == "list" then
			local now, count = os.time(), 0
			for key, b in pairs(blocked) do
				if b.till > now then
					count = count + 1
					minetest.chat_send_player(name, ("[xban] %s until %s (names: %s)")
					  :format(key, os.date("%c", b.till), b.names))
				end
			end
			return true, count.." IPs blocked by the rate limit."
		end
		return false, "Usage: /xban_authblock list | clear <ip>"
	end,
})
