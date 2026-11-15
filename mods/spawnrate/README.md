# spawnrate - faster zombie spawns, shorter pauses between rounds (NOT part of the original game)

A mod folder, kept apart from the base game. Retail rules on every zombie map (round number, zombie count, health, speed,
the pause between rounds, power-ups); the only changes: zombies spawn `spawnrate_mult` times faster, they sprint to
their barrier, and the waits at the start and end of a round are shorter.

- `spawnrate_mult` (default 3) - spawn speed, 1 = retail, below 1 = slower (range 0.05 to 50). Read while playing: type
  `/spawnrate_mult 8` in the console (without the slash the console sends chat).
- `spawnrate_rush` (default 1) - a zombie sprints from its spawn point to its barrier (window), then goes back to the speed its
  round rolled for it (walk, run or sprint) once it stands in front of the barrier. 0 = retail. 2 = also logs each one.
- `spawnrate_start_delay` (default 0) - seconds from the start of a round (its chalk number appears) until its zombies start to
  spawn. Retail waits for the chalk animation first: about 2.5 s, and 8 s on round 1. -1 = retail.
- `spawnrate_round_gap` (default 3) - seconds from the end of a round (its last zombie spawned and killed) until the next round
  begins. Retail: 10 s. Above 3 the chalk number still pulses as in retail; at 3 or below it just stays up for the gap.
  0 = no pause. -1 = retail. So last kill to the next spawn: retail 12.5 s, default here about 3 s.
- `spawnrate_max_zombies N` (default -1 = retail, 24 alive at once) - how many zombies may be alive at once. Clamped to the
  engine's actor limit, 32 unless `+set bo1_mod_maxactors 64` (up to 1024) is on the command line. A faster spawn rate only
  shows while there is room, so with a large mult you may want this up. With `mods/horde` use `horde_max_zombies`.

Start with `+set fs_game mods/spawnrate` or `+set fs_mods spawnrate` (stacks with other mods). `PlayMod.bat spawnrate`
does the first; `PlayMod.bat spawnrate +set spawnrate_mult 6` sets the speed. In the launchers it is "Faster zombie spawns".
With `mods/horde`, list spawnrate after it (`fs_mods "horde zinfo spawnrate"`): spawnrate wraps horde's spawner.
Spawn speed is separate from horde's `horde_fill_rate` (horde's own refill; spawnrate adds to it).

## How it works

Retail's `maps\_zombiemode::round_spawning()` is one loop: spawn a zombie, wait `level.zombie_vars["zombie_spawn_delay"]`
(2 s on round 1, times 0.95 every round down to 0.08 s), wait `wait_network_frame()` (about 0.1 s), repeat. It stops at
`level.zombie_ai_limit` zombies alive. `maps/spawnrate/_spawnrate.gsc` does two things:

1. **Delay / mult.** `round_think` still multiplies the delay by 0.95 at the end of each round, so the mod keeps its own copy
   of retail's delay (the same formula, stepped once per round) and writes copy / mult over it every 0.1 s. It logs
   `round N retail delay X, expected Y` at each round to show the two agree.
2. **A second spawner.** The loop's 0.1 s overhead per spawn does not shrink with the delay, so from round ~10 retail's loop
   cannot go faster than about 5 per second. `spawnrate_fill` makes up the difference between that and what the mult asks
   for (spawns per second = mult x what retail makes at that round's delay), from different spawners each frame, and
   spends `level.zombie_total` the way retail does (`spawn_zombie`, `zombie_total--`, `round_spawn_failsafe`). It is
   installed by wrapping `level.round_spawn_func`, so dog, thief and crawler rounds (which swap that pointer) keep their own
   spawning. Off at mult 1 or below.

No engine changes.

## Round start and round pause

Retail's `round_think` runs `chalk_one_up()` (the round number fades in, ~2.5 s; round 1 has an 8 s intro) and only then starts the
round's spawning, and after the round runs `chalk_round_over()` for `zombie_between_round_time` (10 s). Both waits are
hard-coded in `_zombiemode.gsc`, so the mod sets `level.round_think_func` to `spawnrate_round_think`: retail's loop line for line
(the difficulty step, move speed, power-up and barrier-reward resets, music, `UploadStats`), with the chalk number started as a
thread of its own (retail's `chalk_one_up`, so the HUD looks the same) and the two waits read from the dvars. Like mods/horde's it
stops at game over (`end_game`), which retail's does not. A round shorter than its chalk animation waits for the animation before
the end-of-round pause. The mod replaces `round_think_func`, so with `mods/horde` (whose only change to it was that same
`end_game` stop) the two work together. Not changed: `round_start()`'s 2 s wait before round 1 (it runs before the chalk number),
the dog round's own pauses, and `zombie_intermission_time` (the game-over screen).

Measured (Five, with horde so rounds advance without kills): retail rounds begin 12.55 s after the last one ended and spawn 2.55 s
after their chalk number; with the defaults 3 s and 0 s (log line `spawnrate: round N begins ...`).

## Sprint to the barriers

Retail picks a zombie's speed once, when it spawns (`set_run_speed`: round-based walk / run / sprint, in
`_zombiemode_spawner`). `spawnrate_rush_watch` finds every new plain zombie (animname `zombie`: dogs and the thief / napalm /
shrieker modules are skipped) and `spawnrate_rush_one` waits until retail's `zombie_think` has given it a `first_node` (it is
heading for a barrier; a riser rising from the ground first waits for that; a zombie that chases the player at once never gets
one and is left alone). Then it calls retail's own `set_zombie_run_cycle( "sprint" )`, and when `zombie_goto_entrance` sets
`got_to_entrance` it calls it again with the speed the zombie had. A zombie that has not arrived after 30 s is slowed down
anyway. On Five at round 1, zombies sprinted 2.7 to 5.6 s from spawn to window. The tearing and climbing animations do not
depend on the run speed, and the zombie's speed after the barrier is exactly what retail gave it.

## Measured (Five, headless, round 1, 5 zombies)

| mult | time to spawn the round's total |
|---|---|
| 1 | 10.5 s |
| 3 | 3.7 s |
| 10 | 1.2 s |

Round 70 (with `mods/horde`, `horde_start_round 70`, limit 64, horde's own refill off): at mult 1 the horde needs about 15 s
to fill to 64; at mult 5, about 5 s (`fill: 50 spawned, 0 refused in 5 s`).

## Log

`games_mp.log` in the mod's folder (`build\Release\mods\spawnrate\`, or horde's with fs_game horde):

- `spawnrate: round N: M zombies spawned in T s (mult m, delay d)` - one per round: the spawn total used up
- `spawnrate: fill: A spawned, R refused in 5 s, alive X limit L` - what the second spawner did
- `spawnrate: round N begins X s after the last one ended, spawning Y s after its chalk number` - the two times above
- `spawnrate: rush: N zombies sprinted to a barrier and slowed down in 5 s` (and one line per zombie with `spawnrate_rush 2`)
- `spawnrate: zombie limit N (engine actors E)` - `spawnrate_max_zombies` took effect

## Not covered

- Specials with their own spawning (the dog round, the thief, napalm / shrieker modules) keep their own pace.
- A round with more zombies than the alive limit still waits for kills: the mod spawns faster, it does not make the
  zombies die faster. Raise `spawnrate_max_zombies` to let more of them be alive.
- The mod takes retail's start delay about half a second after the level loads. A mod that changes the delay later than
  that (before round 1 starts) is not seen.
