#include maps\_utility;
#include common_scripts\utility;

// UNLIMITEDPAP MOD - not part of the original game. Loaded only by mods (mods/unlimitedpap); the base game never calls it.
// Pack-a-Punch the same weapon any number of times. Each pack doubles the price and the damage:
//
//   pack      cost (base 5000)   damage vs. the first pack
//   1st       5000               x1   (the retail upgrade)
//   2nd       10000              x2
//   3rd       20000              x4        ... cost 5000 * 2^(n-1), damage 2^(n-1)
//
// The tier is kept per player and per upgraded weapon name (self.upap_tier[weapon]); the weapon file is the retail
// *_upgraded_zm one, so no new weapon assets exist. The machine itself is the retail loop, patched in this mod's own
// maps/_zombiemode_perks.gsc (every changed line is marked UNLIMITEDPAP). Damage goes through level.overrideActorDamage.
// Reserve ammo is NOT doubled yet: script cannot raise a weapon above its maxAmmo (see README).

main()
{
	flag_wait( "all_players_connected" );

	if ( !IsDefined( level._upap_orig ) && IsDefined( level.overrideActorDamage ) )
	{
		level._upap_orig = level.overrideActorDamage;
		level.overrideActorDamage = ::actor_damage;
		LogPrint( "unlimitedpap: damage hook installed\n" );
	}

	if ( GetDvarInt( #"upap_selftest" ) )
	{
		level thread selftest();
	}
}

// +set upap_selftest 1 (headless, with a client): packs an AK74u three times through the real machine loop (the trigger
// notifies are what a player's use does) and logs "unlimitedpap selftest:" lines: weapon, tier, price paid, damage scale.
selftest()
{
	wait( 6 );
	player = get_players()[0];
	trig = GetEnt( "zombie_vending_upgrade", "targetname" );
	if ( !IsDefined( trig ) )
	{
		LogPrint( "unlimitedpap selftest: FAIL no zombie_vending_upgrade trigger on this map\n" );
		return;
	}
	level notify( "Pack_A_Punch_on" ); // the power switch
	wait( 2 );
	player.score = 1000000;
	player GiveWeapon( "ak74u_zm" );
	player SwitchToWeapon( "ak74u_zm" );
	wait( 3 );
	for ( n = 1; n <= 3; n++ )
	{
		weapon = player GetCurrentWeapon();
		before = player.score;
		expect = pap_cost( player, weapon, trig.cost );
		trig notify( "trigger", player ); // insert the weapon
		wait( 9 );
		trig notify( "trigger", player ); // take it back
		wait( 4 );
		weapon = player GetCurrentWeapon();
		LogPrint( "unlimitedpap selftest: pack " + n + " weapon " + weapon + " tier " + player get_tier( weapon ) + " paid " + ( before - player.score ) + " expected " + expect + " damage x" + damage_scale( player get_tier( weapon ) ) + "\n" );
	}
	LogPrint( "unlimitedpap selftest: done\n" );
}

// The upgraded weapon the machine hands back for this weapon, or undefined if it has none. An upgraded weapon
// upgrades to itself (retail has no level.zombie_weapons entry for it).
upgrade_of( weapon )
{
	if ( !IsDefined( weapon ) || weapon == "" )
	{
		return undefined;
	}
	if ( IsDefined( level.zombie_weapons[weapon] ) && IsDefined( level.zombie_weapons[weapon].upgrade_name ) )
	{
		return level.zombie_weapons[weapon].upgrade_name;
	}
	if ( maps\_zombiemode_weapons::is_weapon_upgraded( weapon ) )
	{
		return weapon;
	}
	return undefined;
}

// self = player. 0 = not upgraded, 1 = packed once (retail), 2 = twice, ...
get_tier( weapon )
{
	if ( !maps\_zombiemode_weapons::is_weapon_upgraded( weapon ) )
	{
		return 0;
	}
	if ( IsDefined( self.upap_tier ) && IsDefined( self.upap_tier[weapon] ) )
	{
		return self.upap_tier[weapon];
	}
	return 1; // upgraded by something other than this machine
}

// self = player; called when the player takes the weapon out of the machine
count_pack( weapon, upgrade_weapon )
{
	if ( !IsDefined( self.upap_tier ) )
	{
		self.upap_tier = [];
	}
	if ( weapon == upgrade_weapon )
	{
		self.upap_tier[upgrade_weapon] = self get_tier( weapon ) + 1;
	}
	else
	{
		self.upap_tier[upgrade_weapon] = 1; // a fresh upgrade, also after the old upgraded gun was lost
	}
	LogPrint( "unlimitedpap: " + self.playername + " " + upgrade_weapon + " tier " + self.upap_tier[upgrade_weapon] + "\n" );
}

// price of the next pack for this weapon; base = the machine's own cost (5000, 1000 in a bonfire sale)
pap_cost( player, weapon, base )
{
	n = player get_tier( weapon );
	if ( n > 16 )
	{
		n = 16; // 5000 * 2^16 still fits an int
	}
	cost = base;
	for ( i = 0; i < n; i++ )
	{
		cost = cost * 2;
	}
	return cost;
}

damage_scale( tier )
{
	if ( tier > 21 )
	{
		tier = 21;
	}
	scale = 1;
	for ( i = 1; i < tier; i++ )
	{
		scale = scale * 2;
	}
	return scale;
}

// self = the machine's trigger. The hint is one string for everyone, so it shows the price for the first player standing at it.
hint_think()
{
	self endon( "death" );

	last = -1;
	for ( ;; )
	{
		wait( 0.2 );
		if ( flag( "pack_machine_in_use" ) )
		{
			last = -1;
			continue;
		}
		players = get_players();
		for ( i = 0; i < players.size; i++ )
		{
			if ( DistanceSquared( players[i].origin, self.origin ) > 10000 )
			{
				continue;
			}
			weapon = players[i] GetCurrentWeapon();
			if ( !IsDefined( upgrade_of( weapon ) ) )
			{
				continue;
			}
			cost = pap_cost( players[i], weapon, self.cost );
			if ( cost != last )
			{
				self SetHintString( &"ZOMBIE_PERK_PACKAPUNCH", cost );
				last = cost;
			}
			break;
		}
	}
}

// level.overrideActorDamage: runs the retail override, then scales the damage of a repacked weapon. MUST return the damage.
actor_damage( inflictor, attacker, damage, flags, meansofdeath, weapon, vpoint, vdir, sHitLoc, modelIndex, psOffsetTime )
{
	final_damage = self [[ level._upap_orig ]]( inflictor, attacker, damage, flags, meansofdeath, weapon, vpoint, vdir, sHitLoc, modelIndex, psOffsetTime );

	if ( IsDefined( final_damage ) && final_damage > 0 && IsDefined( attacker ) && IsPlayer( attacker ) && IsDefined( weapon ) )
	{
		tier = attacker get_tier( weapon );
		if ( tier > 1 )
		{
			final_damage = final_damage * damage_scale( tier );
			if ( final_damage > 1000000000 )
			{
				final_damage = 1000000000;
			}
			final_damage = int( final_damage );
		}
	}
	return final_damage;
}
