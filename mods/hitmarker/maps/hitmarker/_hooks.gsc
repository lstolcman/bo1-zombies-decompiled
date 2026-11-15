// HITMARKER MOD - not part of the original game. With +set fs_mods "... hitmarker" (mods/_stack/maps/_modstack.gsc):
// a hit marker at the crosshair when you damage a zombie, as mods/hitmarker/maps/_zombiemode_ffotd.gsc does with
// +set fs_game mods/hitmarker.

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", ::main_end );
}

main_end()
{
	maps\hitmarker\_hitmarker::main( "1" ); // dvar hitmarker 0/1, default on
}
