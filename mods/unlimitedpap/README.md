# unlimitedpap - repeatable Pack-a-Punch for zombies (NOT part of the original game)

A mod folder, kept apart from the base game. Vanilla rules on every zombie map; the only change: the Pack-a-Punch
machine accepts a weapon that is already upgraded, and every further pack doubles the price and the damage.

| pack | cost (5000 base, 1000 in a bonfire sale) | damage |
|---|---|---|
| 1st (retail) | 5000 | x1 |
| 2nd | 10000 | x2 |
| 3rd | 20000 | x4 |
| n-th | 5000 * 2^(n-1) | 2^(n-1) |

The machine's hint shows the price for the first player standing at it (the hint string is one per machine, so in
co-op the second player can pay a different price than shown). Costs stop doubling at the 17th pack, damage at the 22nd,
so nothing overflows.

Start with `+set fs_game mods/unlimitedpap` or `+set fs_mods unlimitedpap` (stacks with other mods).
`PlayMod.bat unlimitedpap` does the first.

## How it works

- Weapons are flat records (`weaponDefFields`, 748 fields in `src/bgame/bg_weapons_load_obj.cpp`), and the upgraded gun is
  a separate weapon, `<name>_upgraded_zm`. Nothing is derived by formula, so the mod adds no weapon files: the tier is
  script state, `player.upap_tier[upgraded_weapon]`, set when the player takes the gun back from the machine.
- `maps/_zombiemode_perks.gsc` is the retail file with 13 lines changed (each marked `UNLIMITEDPAP`): the machine no longer
  refuses an upgraded gun, `upgrade_of()` maps an upgraded gun to itself, and the price comes from `pap_cost()`.
  A mod that ships its own `_zombiemode_perks.gsc` replaces this one.
- `maps/unlimitedpap/_unlimitedpap.gsc` wraps `level.overrideActorDamage` (as hitmarker does) and multiplies the damage of a
  repacked weapon. Damage that does not go through that callback (traps, AI with their own override) is not scaled.

## Not done: reserve ammo

Doubling the reserve ammo needs an engine change. Script cannot put more stock on a weapon than its `maxAmmo`:
`BG_GetAmmoPlayerMax` (`src/bgame/bg_weapons_ammo.cpp`) caps `SetWeaponAmmoStock`, `GiveMaxAmmo` and ammo pickups, and the
weapon file is shared by every player.

## Self-test

`+set upap_selftest 1` with a headless client (`tools/headless.ps1 -Zombies -Client`) packs an AK74u three times through
the real machine loop and logs `unlimitedpap selftest:` lines to `mods/unlimitedpap/games_mp.log`. On Five:
`pack 1 ... paid 5000 expected 5000 damage x1`, `pack 2 ... paid 10000 ... x2`, `pack 3 ... paid 20000 ... x4`.
The damage multiplier is checked as a number, not against a real zombie hit.
