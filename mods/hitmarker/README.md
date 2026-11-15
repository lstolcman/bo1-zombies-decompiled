# hitmarker - a hit marker for zombies (NOT part of the original game)

A mod folder, kept apart from the base game. Vanilla rules on every zombie map; the only addition: an X flashes at
your crosshair when you damage a zombie (dogs and specials included, anything that goes through the zombie damage
callback):

- **white**, short - a body hit
- **orange** - a headshot (not melee)
- **red**, longer - the hit that kills

Only the shooter sees it, so co-op works. `hitmarker 0` in the console hides it, `hitmarker 1` shows it again.

Start with `+set fs_game mods/hitmarker` or `+set fs_mods hitmarker` (stacks with other mods, e.g.
`fs_mods horde zinfo hitmarker`). `PlayMod.bat hitmarker` does the first, `PlayMod.bat horde zinfo hitmarker` the second.

How it works: retail zombies ships the material (`damage_feedback`, in common_zombie) and `maps\_damagefeedback.gsc`,
but nothing calls them. `maps/hitmarker/_hitmarker.gsc` wraps `level.overrideActorDamage` (the retail
`_zombiemode::actor_damage_override`, run with self = the zombie): it calls the retail function, and if a player's damage
gets through it flashes that player's client hud element. Kill = the damage returned is at least the zombie's health.
It starts from `maps/_zombiemode_ffotd.gsc` (fs_game) or `maps/hitmarker/_hooks.gsc` (fs_mods), after all players have
connected. No engine changes.

Not covered: the hit sound (`SP_hit_alert`, used by `_damagefeedback.gsc`, is not in the zombies sound banks), damage from
traps, and AI that set their own `overrideActorDamage` (they skip the level override).
