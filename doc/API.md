
## Extended Ban Mod API

### ban_player

`xban.ban_player(player_or_ip, source, expires, reason)`

Ban a player and all of his/her alternative names and IPs.

#### Arguments:

* `player_or_ip` - Player to search for and ban. See note 1 below.
* `source` - Source of the ban. See note 2 below.
* `expires` - Time at which the ban expires. If nil, ban is permanent.
* `reason` - Reason for ban.

### unban_player

`xban.unban_player(player_or_ip, source)`

Unban a player and all of his/her alternative names and IPs.

#### Arguments:

* `player_or_ip` - Player to search for and unban.
* `source` - Source of the ban. See note 2 below.

### Notes

* 1: If player is currently online, all his accounts are kicked.
* 2: Mods using the xban API are advised to use the `"modname:source"`
format for `source` (for example: `"anticheat:main"`).

### IP blacklist

* `xban.get_ip_blacklist()` - Table `{ [pattern] = { source, time, reason } }`.
  Read only.
* `xban.find_ip_blacklist(ip)` - Returns `pattern, entry` of the first
  matching pattern, or nil.
* `xban.add_ip_blacklist(pattern, source, reason)` - Adds a pattern and kicks
  connected players with a matching IP. Returns `pattern, kicked_count` or
  `nil, err`.
* `xban.remove_ip_blacklist(pattern, source)` - Returns `pattern` or
  `nil, err`.

### Login rate limit

* `xban.get_auth_block(ip)` - Time until which the IP is blocked, or nil.

### Cleaning up entries

* `xban.purge_ip(pattern, source, dry_run)` - Removes every IP matching
  `pattern` from all entries (nothing is changed with `dry_run`). Returns a
  list of `{ entry = e, removed = { ip, ... } }` or `nil, err`.
* `xban.split_entry(name, source)` - Moves a player name into a new entry
  with the records targeting it, and the current ban if it targets the name.
  Returns `new_entry, ban_moved` or `nil, err`.

### IP helpers

* `xban.normalize_ip(ip)` - Lower case, without a leading `::ffff:`.
* `xban.valid_ip_pattern(pattern)` - Whether a normalized pattern is an IPv4
  or IPv6 address or a prefix ending in `.*` or `:*`.
* `xban.ip_matches(pattern, ip)` - Whether the pattern matches the IP.
