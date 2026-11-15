// SPAWNRATE MOD - not part of the original game. With +set fs_mods "... spawnrate" (mods/_stack/maps/_modstack.gsc):
// faster zombie spawns, as mods/spawnrate/maps/_zombiemode_ffotd.gsc does with +set fs_game mods/spawnrate.
// With mods/horde, list spawnrate after it (fs_mods "horde zinfo spawnrate"): its spawn function wraps horde's.

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", ::main_end );
}

main_end()
{
	maps\spawnrate\_spawnrate::main();
}
