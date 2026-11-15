#include maps\_utility;
#include common_scripts\utility;

// HITMARKER MOD - not part of the original game. Loaded only by mods (mods/hitmarker); the base game never calls it.
// Retail zombies has the stock hit marker material ("damage_feedback", in common_zombie) and maps\_damagefeedback.gsc, but
// nothing calls them. This mod wraps level.overrideActorDamage (maps\_zombiemode::actor_damage_override, called with
// self = the zombie from maps\_callbackglobal::Callback_ActorDamage) and, when a player's damage gets through, flashes
// a client HUD element at that player's crosshair:
//   body hit  = white, short          headshot = orange           kill = red, longer
// Only the shooter sees it (a client hud element), so co-op works. Dvar hitmarker 0/1 turns it off/on while playing.
// Started by mods/hitmarker's hook: maps/_zombiemode_ffotd.gsc (fs_game mods/hitmarker) or maps/hitmarker/_hooks.gsc
// (fs_mods).

main( default_on )
{
	if ( GetDvar( #"hitmarker" ) == "" )
	{
		SetDvar( "hitmarker", default_on );
	}
	PrecacheShader( "damage_feedback" ); // before the first wait: the hook runs during level load, when precaching is allowed
	flag_wait( "all_players_connected" );

	if ( !IsDefined( level._hitmarker_orig ) && IsDefined( level.overrideActorDamage ) )
	{
		level._hitmarker_orig = level.overrideActorDamage;
		level.overrideActorDamage = ::actor_damage;
	}

	players = get_players();
	for ( i = 0; i < players.size; i++ )
	{
		players[i] thread player_init();
	}
	for ( ;; )
	{
		level waittill( "connecting", player ); // a player who joins later
		player thread player_init();
	}
}

player_init()
{
	self endon( "disconnect" );

	if ( IsDefined( self.hitmarker_hud ) )
	{
		return;
	}
	hud = NewClientHudElem( self );
	hud.horzAlign = "center";
	hud.vertAlign = "middle";
	// the material is a 1:2 sprite with the marker in its top half (maps\_damagefeedback.gsc draws it 24x48 at -12,-12 from
	// the screen centre); same layout here, a third bigger, so the marker is centred on the crosshair
	hud.x = -16;
	hud.y = -16;
	hud.alpha = 0;
	hud.archived = true;
	hud SetShader( "damage_feedback", 32, 64 );
	self.hitmarker_hud = hud;
}

// level.overrideActorDamage: runs the retail override, then flashes the marker. MUST return the damage.
actor_damage( inflictor, attacker, damage, flags, meansofdeath, weapon, vpoint, vdir, sHitLoc, modelIndex, psOffsetTime )
{
	health = self.health;
	final_damage = self [[ level._hitmarker_orig ]]( inflictor, attacker, damage, flags, meansofdeath, weapon, vpoint, vdir, sHitLoc, modelIndex, psOffsetTime );

	if ( IsDefined( attacker ) && IsPlayer( attacker ) && IsDefined( final_damage ) && final_damage > 0 )
	{
		kill = final_damage >= health;
		head = IsDefined( sHitLoc ) && ( sHitLoc == "head" || sHitLoc == "helmet" ) && meansofdeath != "MOD_MELEE" && meansofdeath != "MOD_IMPACT";
		attacker thread flash( kill, head );
	}
	return final_damage;
}

flash( kill, head )
{
	if ( GetDvarInt( #"hitmarker" ) == 0 || !IsDefined( self.hitmarker_hud ) )
	{
		return;
	}
	hud = self.hitmarker_hud;
	fade = 0.25;
	if ( kill )
	{
		hud.color = ( 1, 0.1, 0.1 );
		fade = 0.5;
	}
	else if ( head )
	{
		hud.color = ( 1, 0.55, 0.1 );
	}
	else
	{
		hud.color = ( 1, 1, 1 );
	}
	hud.alpha = 1;
	hud FadeOverTime( fade );
	hud.alpha = 0;
}
