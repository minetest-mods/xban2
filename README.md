# Extended Ban Mod for Minetest
This mod attempts to be an improvement to Minetest's ban system.
* It supports normal bans and temporary bans (from 60 seconds up to the end of
  time, with 1 second granularity).
* Records and joins all accounts using the same IP address and several IP
  addresses using the same name into a single record, and can ban/unban them as
  a single user.
* Can ban offline players if you know their IP or username.
* Holds a record of bans for each user, so moderators and administrators can
  consult it to know if a player is a repeat offender.
* Does not modify the default ban database in any way (`ipban.txt').
* Has an API to ban and check the ban database to allows other mods to manage
  users (for example, anticheat mods).

## Wildcard/Subnet Ban Feature

The mod now supports wildcard (subnet) bans for IP addresses using trailing `*` notation. This allows you to ban entire IP ranges or subnets with a single command.

### How It Works

* **IPv4 Wildcard Bans**: Use a trailing `*` to match any IP address that starts with the specified prefix.
  * Example: `192.168.1.*` will match all IPs from `192.168.1.0` to `192.168.1.255`
  * Example: `10.0.*` will match all IPs from `10.0.0.0` to `10.0.255.255`
  * Example: `172.*` will match all IPs from `172.0.0.0` to `172.255.255.255`

* **IPv6 Wildcard Bans**: Use a trailing `*` to match any IPv6 address that starts with the specified prefix.
  * Example: `2001:db8:*` will match all IPv6 addresses starting with `2001:db8:`
  * Example: `fe80:*` will match all link-local IPv6 addresses

### Usage Examples

**Ban an entire IPv4 subnet:**
```
/xban 192.168.1.* Banning entire subnet due to spam
```

**Temporarily ban an IPv4 range:**
```
/xtempban 10.0.* 24h Temporary subnet ban for suspected bot activity
```

**Ban an IPv6 prefix:**
```
/xban 2001:db8:* Banning IPv6 prefix
```

**Unban a wildcard entry:**
```
/xunban 192.168.1.*
```

### Notes

* Wildcard bans are checked when a player attempts to connect.
* Individual IP addresses can still be whitelisted even if they match a wildcard ban.
* The wildcard character `*` must be at the end of the IP address.
* For IPv4, you can use wildcards at any octet boundary (e.g., `192.*`, `192.168.*`, `192.168.1.*`).
* For IPv6, the wildcard matches the remaining part of the address after the specified prefix.

## Chat commands
The mod provides the following chat commands. All commands require the `ban`
privilege.

### `xban`
Bans a player permanently.

**Usage:** `/xban <player_or_ip> <reason>`

**Example:** `/xban 127.0.0.1 Some reason.`

**Wildcard Example:** `/xban 192.168.1.* Subnet ban`

### `xtempban`
Bans a player temporarily.

**Usage:** `/xtempban <player_or_ip> <time> <reason>`

The `time` parameter is a string in the format `<number><unit>` where `<unit>`
is one of `s` for seconds, `m` for minutes, `h` for hours, `D` for days, `W`
for weeks, `M` for months, or `Y` for years. If the unit is omitted, it is
assumed to mean seconds. For example, `42s` means 42 seconds, `1337m` 1337
minutes, and so on. You can chain more than one such group and they will add
up. For example, `1Y3M3D7h` will ban for 1 year, 3 months, 3 days and 7 hours.

**Example:** `/xtempban Joe 3600 Some reason.`

**Wildcard Example:** `/xtempban 10.0.* 7D Temporary subnet ban`

### `xunban`
Unbans a player.

**Usage:** `/xunban <player_or_ip>`

**Example:** `/xunban Joe`

**Wildcard Example:** `/xunban 192.168.1.*`

### `xban_record`
Shows the ban record on chat.

**Usage:** `/xban_record <player_or_ip>`

### `xban_wl`
Manages the whitelist.

**Usage:** `/xban_wl (add|del|get) <player_or_ip>`

Whitelisted players are allowed on the server even if it's otherwise marked
as banned. This is useful to only allow certain users from shared computers,
for example.

The `add` subcommand adds the player to the whitelist. The `del` subcommand
removes the player from the whitelist. The `get` subcommand checks if the
player is in the whitelist, and prints the status to chat.

**Example:** `/xban_record add Jane`

### `xban_gui`
Shows a form to consult the database interactively.

### `xban_ipbl`
Manages the IP blacklist.

**Usage:** `/xban_ipbl add <ip> [note] | del <ip> | check <ip> | list`

Connections from a blacklisted IP are refused before the password is checked,
for every account, including whitelisted ones. Connected players with a
matching IP are kicked when the IP is added. Patterns with a trailing `*` work
as for wildcard bans, and `::ffff:1.2.3.4` counts as `1.2.3.4`. The blacklist
is stored in the mod storage, separately from the ban entries.

By default the IP is told that the password was wrong, so the person behind it
does not think of switching to another IP. See `settingtypes.txt`
(`xban.ip_blacklist_message`, `xban.wrong_password_text`).

**Example:** `/xban_ipbl add 203.0.113.42 Brute force`

### `xban_purge_ip`
Removes an IP (or pattern) from the names of all entries, for example an IP
that linked unrelated players. Without `confirm` it only lists the entries
that contain the IP.

**Usage:** `/xban_purge_ip <ip> [confirm]`

### `xban_split`
Moves a player name out of its entry into a new entry of its own, together
with the records whose target is that name. If the current ban of the entry
targets that name, the ban moves along and the old entry is no longer banned.

**Usage:** `/xban_split <player>`

### `xban_authblock`
Lists or lifts the IP blocks of the login rate limit. After 5 failed logins
from one IP within 10 minutes, the IP is blocked for an hour (see
`settingtypes.txt`). Blocks are kept in memory and end with a restart.

**Usage:** `/xban_authblock list | clear <ip>`

**Usage:** `/xban_gui`

## Administrator commands
The following commands require the `server` privilege, so they are only
available to server administrators.

### `xban_dbi`
Imports ban entries from other database formats.

**Usage:** `/xban_dbi <importer>`

The `importer` argument specifies from which database to import. These are
the supported import plugins at the time of writing:

* `minetest`: Import entries from Minetest's ban list (`ipban.txt`).
* `v1`: Old format used by xban (`players.iplist`).
* `v2`: Old format used by xban (`players.iplist.v2`).

**Example:** `/xban_dbi minetest`

### `xban_cleanup`
Removes all non-banned entries from the xban db.

**Usage:** `/xban_cleanup`
