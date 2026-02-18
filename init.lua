-- xban - ban management logic with wildcard matching optimization

local xban = {}
local bans = {}

-- Function to add a ban
function xban.add(name, ip)
    if not bans[name] then
        bans[name] = {}
    end
    table.insert(bans[name], ip)
end

-- Function to check if a name is banned
function xban.is_banned(name)
    for banned_name, ips in pairs(bans) do
        if xban.matches(name, banned_name) then
            return true
        end
    end
    return false
end

-- Function to perform wildcard matching
function xban.matches(name, pattern)
    if pattern == "*" then
        return true
    end
    local regex = pattern:gsub("%.", "%%."):gsub("%*", ".*")
    return string.match(name, "^" .. regex .. "$") ~= nil
end

-- Function to ban management logic
dunction xban.manage_bans()
    for name, ips in pairs(bans) do
        for _, ip in ipairs(ips) do
            -- Logic to enforce bans. Placeholder for actual enforcement mechanics.
            print(name .. " is banned due to IP: " .. ip)
        end
    end
end

return xban
