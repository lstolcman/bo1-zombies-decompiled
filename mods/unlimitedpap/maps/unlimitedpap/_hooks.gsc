// UNLIMITEDPAP MOD - not part of the original game. With +set fs_mods "... unlimitedpap" (mods/_stack/maps/_modstack.gsc):
// unlimited Pack-a-Punch, as mods/unlimitedpap/maps/_zombiemode_ffotd.gsc does with +set fs_game mods/unlimitedpap.

register()
{
	maps\_modstack::add( "_zombiemode_ffotd::main_end", ::main_end );
}

main_end()
{
	maps\unlimitedpap\_unlimitedpap::main();
}
