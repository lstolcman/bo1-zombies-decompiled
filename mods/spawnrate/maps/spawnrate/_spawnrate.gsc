#include maps\_utility;
#include common_scripts\utility;
#include maps\_zombiemode_utility;

// SPAWNRATE MOD - not part of the original game. Loaded only by mods (mods/spawnrate); the base game never calls it.
// Zombies spawn spawnrate_mult times faster. Everything else is the retail round logic: round number, zombie count,
// health, speed, the between-round pause, power-ups. Retail's round_spawning() (maps\_zombiemode) spawns one zombie, then
// waits level.zombie_vars["zombie_spawn_delay"] (2 s on round 1, x0.95 each round down to 0.08 s) plus wait_network_frame().
// Two parts, both read their dvar while playing:
//   1. the spawn delay is divided by spawnrate_mult. Retail's round_think still multiplies the value by 0.95 at the end of each
//      round, so this mod keeps its own copy of retail's delay (the retail formula, stepped once per round) and writes
//      copy / mult over it every 0.1 s.
//   2. the retail loop's own overhead per spawn (wait_network_frame) does not shrink with the delay, so from a delay of about
//      0.5 s down it cannot reach the asked rate. A second spawner (spawnrate_fill) adds the missing spawns, from different
//      spawners per frame (the engine refuses a second spawn from one spawner in a frame), and hands a refused spawn back.
// Dvars:
//   spawnrate_mult         spawn speed, 1 = retail, 3 = default, below 1 = slower (0.05 .. 50)
//   spawnrate_start_delay  seconds from the start of a round (its chalk number appears) until its zombies start to spawn.
//                          Default 0. Retail: about 2.5 s, 8 s on round 1 (the chalk animation runs first). -1 = retail.
//   spawnrate_round_gap    seconds from the end of a round (its last zombie spawned and died) until the next round begins.
//                          Default 3. Retail: 10 s (the chalk number pulses). Above 3 the pulse still plays, below it the number just waits. -1 = retail.
//   spawnrate_rush         1 (default): a zombie sprints from its spawn to its barrier (window), then goes back to the speed its
//                          round gave it. 0 = retail (it walks / runs at the round's speed all the way). 2 = also log each one.
//   spawnrate_max_zombies  zombies alive at once (level.zombie_ai_limit, retail 24), -1 (default) = retail. Clamped to the
//                          engine's actor limit (bo1_mod_maxactors, 32 unless set on the command line). With mods/horde, use
//                          horde_max_zombies instead (it sets the same limit).
// The two times are inside retail's round_think (maps\_zombiemode), which waits for chalk_one_up() before it starts the round's spawning
// and for chalk_round_over() after it. This mod runs level.round_think_func = spawnrate_round_think: retail's loop, line for line,
// with those two waits made configurable (the chalk animation itself is retail's, run beside the round).
// Logs "spawnrate: ..." lines to games_mp.log: one per round, "N zombies spawned in T s".
// Started by mods/spawnrate's hook: maps/_zombiemode_ffotd.gsc (fs_game mods/spawnrate) or maps/spawnrate/_hooks.gsc (fs_mods).

main()
{
	if ( GetDvar( #"spawnrate_mult" ) == "" )
	{
		SetDvar( "spawnrate_mult", "3" );
	}
	if ( GetDvar( #"spawnrate_max_zombies" ) == "" )
	{
		SetDvar( "spawnrate_max_zombies", "-1" );
	}
	if ( GetDvar( #"spawnrate_start_delay" ) == "" )
	{
		SetDvar( "spawnrate_start_delay", "0" );
	}
	if ( GetDvar( #"spawnrate_round_gap" ) == "" )
	{
		SetDvar( "spawnrate_round_gap", "3" );
	}
	if ( GetDvar( #"spawnrate_rush" ) == "" )
	{
		SetDvar( "spawnrate_rush", "1" );
	}
	if ( IsDefined( level.spawnrate_started ) )
	{
		return; // fs_game mods/spawnrate and fs_mods spawnrate together: once is enough
	}
	level.spawnrate_started = true;
	level.spawnrate_filled = 0;
	level.spawnrate_refused = 0;
	level.spawnrate_rushed = 0;
	level.spawnrate_chalk_busy = false;

	spawnrate_log( "mult " + spawnrate_mult() );
	level thread spawnrate_install();
	level thread spawnrate_delay_watch();
	level thread spawnrate_limit_watch();
	level thread spawnrate_round_log();
	level thread spawnrate_rush_watch();
}


spawnrate_log( msg )
{
	LogPrint( "spawnrate: " + msg + "\n" );
}


// the dvar, kept to a range that cannot stall or flood the loop
spawnrate_mult()
{
	m = GetDvarFloat( #"spawnrate_mult" );
	if ( m <= 0 )
	{
		m = 1;
	}
	if ( m < 0.05 )
	{
		m = 0.05;
	}
	if ( m > 50 )
	{
		m = 50;
	}
	return m;
}


// retail round_think, end of a round: the delay shrinks by 5 % until it reaches 0.08 s
spawnrate_next_delay( timer )
{
	if ( timer > 0.08 )
	{
		return timer * 0.95;
	}
	if ( timer < 0.08 )
	{
		return 0.08;
	}
	return timer;
}


// level.round_spawn_func is what retail's round_think runs to spawn a normal round (the dog, thief and crawler rounds swap it for
// their own and put it back). Wrap whatever is there once every mod's main_end has run (mods/horde sets it from Five's own
// hook, which can run after this mod's), so mods/horde's own wrapper still runs and nothing overwrites ours. Round 1 starts
// seconds after the level loads.
spawnrate_install()
{
	wait( 0.5 );
	level.spawnrate_orig_spawn_func = level.round_spawn_func;
	level.round_spawn_func = ::spawnrate_round_spawning;
	// retail's own between-round time, to give back at -1 (round_start() reads round_think_func after its 2 s pre-start wait)
	level.spawnrate_retail_round_time = level.zombie_vars["zombie_between_round_time"];
	level.round_think_func = ::spawnrate_round_think;
}


// level.round_spawn_func: the retail (or the next mod's) spawning, plus the second spawner
spawnrate_round_spawning()
{
	level thread spawnrate_fill();
	if ( IsDefined( level.spawnrate_orig_spawn_func ) )
	{
		[[ level.spawnrate_orig_spawn_func ]]();
	}
	else
	{
		maps\_zombiemode::round_spawning();
	}
}


// Part 1. Retail's delay for the current round is level.spawnrate_base; the value in zombie_vars is that divided by the mult.
spawnrate_delay_watch()
{
	// the intro runs for seconds before round 1 starts: take retail's starting delay (and round number, which
	// mods/horde's horde_start_round may have raised) once, before anything has used it
	wait( 0.5 );
	base = level.zombie_vars["zombie_spawn_delay"];
	seen = level.round_number;
	written = base;
	for ( ;; )
	{
		while ( seen < level.round_number )
		{
			// retail just did timer * 0.95 on the value this mod had written: that is what it should read now
			spawnrate_log( "round " + level.round_number + " retail delay " + level.zombie_vars["zombie_spawn_delay"] + ", expected " + spawnrate_next_delay( written ) );
			base = spawnrate_next_delay( base );
			seen++;
		}
		mult = spawnrate_mult();
		level.spawnrate_base = base;
		delay = base / mult;
		if ( delay < 0.01 )
		{
			delay = 0.01;
		}
		level.zombie_vars["zombie_spawn_delay"] = delay;
		written = delay;
		wait( 0.1 );
	}
}


// Part 2. Spawns per second the retail loop makes at a delay: one per delay + its own overhead (wait_network_frame, about 0.1 s)
spawnrate_loop_rate( delay )
{
	return 1.0 / ( delay + 0.1 );
}


// Spends zombie_total as retail does (spawn_zombie, zombie_total--, round_spawn_failsafe) at the spawns per second the mult
// asks for and the retail loop cannot make: asked rate (mult x the retail loop at retail's delay) minus what it makes now.
spawnrate_fill()
{
	level endon( "intermission" );
	level endon( "end_of_round" );
	level endon( "restart_round" );
	if ( !IsDefined( level.spawnrate_fill_pending ) )
	{
		level.spawnrate_fill_pending = 0;
	}
	budget = 0;
	for ( ;; )
	{
		wait( 0.05 );
		mult = spawnrate_mult();
		if ( mult <= 1 || !IsDefined( level.spawnrate_base ) || !flag( "spawn_zombies" ) || level.enemy_spawns.size < 1 )
		{
			budget = 0;
			continue;
		}
		rate = mult * spawnrate_loop_rate( level.spawnrate_base ) - spawnrate_loop_rate( level.zombie_vars["zombie_spawn_delay"] );
		if ( rate <= 0 )
		{
			budget = 0;
			continue;
		}
		budget += rate * 0.05;
		if ( budget > rate )
		{
			budget = rate; // at most one second of spawns saved up
		}
		tries = int( budget );
		room = level.zombie_ai_limit - spawnrate_alive() - level.spawnrate_fill_pending;
		left = level.zombie_total - level.spawnrate_fill_pending;
		if ( tries > 8 )
		{
			tries = 8;
		}
		if ( tries > room )
		{
			tries = room;
		}
		if ( tries > left )
		{
			tries = left;
		}
		if ( tries > level.enemy_spawns.size )
		{
			tries = level.enemy_spawns.size;
		}
		start = RandomInt( level.enemy_spawns.size );
		for ( i = 0; i < tries; i++ )
		{
			budget -= 1;
			level.spawnrate_fill_pending++;
			level thread spawnrate_fill_one( level.enemy_spawns[( start + i ) % level.enemy_spawns.size] );
		}
	}
}


spawnrate_fill_one( spawn_point )
{
	ai = maps\_zombiemode_utility::spawn_zombie( spawn_point );
	level.spawnrate_fill_pending--;
	if ( IsDefined( ai ) )
	{
		level.zombie_total--;
		level.spawnrate_filled++;
		ai thread maps\_zombiemode::round_spawn_failsafe();
	}
	else
	{
		level.spawnrate_refused++;
	}
}


spawnrate_alive()
{
	ai = GetAiSpeciesArray( "axis", "all" );
	return ai.size;
}


// spawnrate_max_zombies N: level.zombie_ai_limit is read by retail round_spawning() before every spawn; SetAILimit() is the engine cap
spawnrate_limit_watch()
{
	wait( 0.5 );
	retail_limit = level.zombie_ai_limit;
	last = -1;
	for ( ;; )
	{
		n = GetDvarInt( #"spawnrate_max_zombies" );
		if ( n > 0 )
		{
			engine_max = GetDvarInt( #"bo1_mod_maxactors" );
			if ( engine_max < 32 )
			{
				engine_max = 32;
			}
			if ( n > engine_max )
			{
				n = engine_max;
			}
			if ( n != last )
			{
				level.zombie_ai_limit = n;
				SetAILimit( n );
				spawnrate_log( "zombie limit " + n + " (engine actors " + engine_max + ")" );
				last = n;
			}
		}
		else if ( last != -1 )
		{
			level.zombie_ai_limit = retail_limit;
			SetAILimit( retail_limit );
			spawnrate_log( "zombie limit back to retail " + retail_limit );
			last = -1;
		}
		wait( 0.5 );
	}
}


// One line per normal round: how long the round's spawn total took to be used up (the measure of the spawn speed; a round
// with more zombies than the alive limit also waits for kills)
spawnrate_round_log()
{
	round = 0;
	logged = true;
	start = 0;
	total = 0;
	ticks = 0;
	for ( ;; )
	{
		wait( 0.1 );
		ticks++;
		if ( ticks >= 50 )
		{
			// every 5 s: what the second spawner did (zombies spawned, spawns the engine refused) while it ran
			ticks = 0;
			if ( level.spawnrate_rushed > 0 )
			{
				spawnrate_log( "rush: " + level.spawnrate_rushed + " zombies sprinted to a barrier and slowed down in 5 s" );
				level.spawnrate_rushed = 0;
			}
			if ( level.spawnrate_filled + level.spawnrate_refused > 0 )
			{
				spawnrate_log( "fill: " + level.spawnrate_filled + " spawned, " + level.spawnrate_refused + " refused in 5 s, alive " + spawnrate_alive() + " limit " + level.zombie_ai_limit );
				level.spawnrate_filled = 0;
				level.spawnrate_refused = 0;
			}
		}
		if ( round != level.round_number && level.zombie_total > 0 )
		{
			round = level.round_number;
			logged = false;
			start = GetTime();
			total = level.zombie_total;
		}
		else if ( !logged && round == level.round_number && level.zombie_total <= 0 )
		{
			logged = true;
			secs = ( GetTime() - start ) / 1000.0;
			spawnrate_log( "round " + round + ": " + total + " zombies spawned in " + secs + " s (mult " + spawnrate_mult() + ", delay " + level.zombie_vars["zombie_spawn_delay"] + ")" );
		}
	}
}


// spawnrate_rush: every new zombie gets spawnrate_rush_one. Looked for every 0.1 s (a zombie is picked up within a tenth of a second
// of its spawn); the AI array is the same one the alive count uses.
spawnrate_rush_watch()
{
	wait( 0.5 );
	for ( ;; )
	{
		wait( 0.1 );
		if ( GetDvarInt( #"spawnrate_rush" ) == 0 )
		{
			continue;
		}
		ai = GetAiSpeciesArray( "axis", "all" );
		for ( i = 0; i < ai.size; i++ )
		{
			z = ai[i];
			if ( IsDefined( z.spawnrate_rush_seen ) || !IsDefined( z.animname ) || z.animname != "zombie" )
			{
				continue;
			}
			z.spawnrate_rush_seen = true; // plain zombies only: dogs and the specials have their own animname
			z thread spawnrate_rush_one();
		}
	}
}


// Retail zombie_think (maps\_zombiemode_spawner) sets self.first_node when the zombie heads for a barrier and zombie_goto_entrance sets
// self.got_to_entrance when it stands in front of it. A zombie that rises from the ground (script_string "riser") first rises,
// and one that chases the player at once (find_flesh) never gets a first_node: neither is touched.
// In between the zombie gets retail's own "sprint" run cycle (set_zombie_run_cycle with a speed), then the speed its round rolled
// for it (set_zombie_run_cycle with the saved one) once it is at the barrier.
spawnrate_rush_one()
{
	self endon( "death" );
	for ( i = 0; i < 150 && !IsDefined( self.first_node ); i++ )
	{
		wait( 0.1 ); // still rising
	}
	if ( !IsDefined( self.first_node ) || !IsDefined( self.zombie_move_speed ) || self.zombie_move_speed == "sprint" )
	{
		return;
	}
	if ( IsDefined( self.got_to_entrance ) && self.got_to_entrance )
	{
		return;
	}
	normal = self.zombie_move_speed;
	self maps\_zombiemode_spawner::set_zombie_run_cycle( "sprint" );
	start = GetTime();
	// up to 30 s: a zombie that never gets there (blocked, a bad path) must not sprint for the rest of the round
	for ( i = 0; i < 300 && !( IsDefined( self.got_to_entrance ) && self.got_to_entrance ); i++ )
	{
		wait( 0.1 );
	}
	level.spawnrate_rushed++;
	if ( GetDvarInt( #"spawnrate_rush" ) == 2 )
	{
		spawnrate_log( "rush: zombie " + self GetEntityNumber() + " " + normal + " -> sprint for " + ( ( GetTime() - start ) / 1000.0 ) + " s, " + normal + " again at barrier, reached " + ( IsDefined( self.got_to_entrance ) && self.got_to_entrance ) );
	}
	self maps\_zombiemode_spawner::set_zombie_run_cycle( normal );
}


// maps\_zombiemode::round_think, as in the retail script, apart from: level endon( "end_game" ) (as mods/horde does: retail has none and
// the loop runs on after the chalk HUD is destroyed), the chalk number started as a thread so the round's spawning can start before
// the animation ends, and the pause after the round. Other mods' round_think_func is replaced by this one (mods/horde's only
// added the endon).
spawnrate_round_think()
{
	level endon( "end_game" );
	for ( ;; )
	{
		//////////////////////////////////////////
		//designed by prod DT#36173
		maxreward = 50 * level.round_number;
		if ( maxreward > 500 )
			maxreward = 500;
		level.zombie_vars["rebuild_barrier_cap_per_round"] = maxreward;
		//////////////////////////////////////////

		level.pro_tips_start_time = GetTime();
		level.zombie_last_run_time = GetTime();	// Resets the last time a zombie ran

		level thread maps\_zombiemode_audio::change_zombie_music( "round_start" );
		level thread spawnrate_chalk_up();
		delay = GetDvarFloat( #"spawnrate_start_delay" );
		if ( delay < 0 )
		{
			while ( level.spawnrate_chalk_busy )
			{
				wait( 0.05 ); // retail: the chalk animation ends first
			}
		}
		else if ( delay > 0 )
		{
			wait( delay );
		}

		maps\_zombiemode_powerups::powerup_round_start();

		players = get_players();
		array_thread( players, maps\_zombiemode_blockers::rebuild_barrier_reward_reset );

		level thread maps\_zombiemode::award_grenades_for_survivors();

		bbPrint( "zombie_rounds: round %d player_count %d", level.round_number, players.size );

		level.round_start_time = GetTime();
		if ( IsDefined( level.spawnrate_round_over_time ) )
		{
			spawnrate_log( "round " + level.round_number + " begins " + ( ( GetTime() - level.spawnrate_round_over_time ) / 1000.0 ) + " s after the last one ended, spawning " + ( ( GetTime() - level.spawnrate_chalk_time ) / 1000.0 ) + " s after its chalk number" );
		}
		level thread [[level.round_spawn_func]]();

		level notify( "start_of_round" );

		[[level.round_wait_func]]();

		level.first_round = false;
		level notify( "end_of_round" );

		level thread maps\_zombiemode_audio::change_zombie_music( "round_end" );

		UploadStats();

		if ( 1 != players.size )
		{
			level thread maps\_zombiemode::spectators_respawn();
		}

		while ( level.spawnrate_chalk_busy )
		{
			wait( 0.05 ); // a round shorter than its chalk animation: let it finish before the HUD is used again
		}
		level.spawnrate_round_over_time = GetTime();
		spawnrate_round_over();

		// here's the difficulty increase over time area
		timer = level.zombie_vars["zombie_spawn_delay"];
		if ( timer > 0.08 )
		{
			level.zombie_vars["zombie_spawn_delay"] = timer * 0.95;
		}
		else if ( timer < 0.08 )
		{
			level.zombie_vars["zombie_spawn_delay"] = 0.08;
		}

		// Increase the zombie move speed
		level.zombie_move_speed = level.round_number * level.zombie_vars["zombie_move_speed_multiplier"];

		level.round_number++;

		level notify( "between_round_over" );
	}
}


// retail chalk_one_up() (the round number appears), as a thread of its own; level.spawnrate_chalk_busy is true while it runs
spawnrate_chalk_up()
{
	level endon( "end_game" );
	level.spawnrate_chalk_busy = true;
	level.spawnrate_chalk_time = GetTime();
	maps\_zombiemode::chalk_one_up();
	level.spawnrate_chalk_busy = false;
}


// the pause after a round: retail chalk_round_over() takes zombie_between_round_time seconds (10); it pulses the number for
// ( time - 2 ) s when the time is above 3 and for the time plus 2 s at or below it, so above 3 the retail animation is used and
// at 3 or below the number just stays up for the gap
spawnrate_round_over()
{
	gap = GetDvarFloat( #"spawnrate_round_gap" );
	if ( gap < 0 )
	{
		level.zombie_vars["zombie_between_round_time"] = level.spawnrate_retail_round_time;
		level maps\_zombiemode::chalk_round_over();
	}
	else if ( gap > 3 )
	{
		level.zombie_vars["zombie_between_round_time"] = gap;
		level maps\_zombiemode::chalk_round_over();
	}
	else if ( gap > 0 )
	{
		wait( gap );
	}
}
