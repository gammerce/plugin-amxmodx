#include <amxmodx>
#include <shopsms>

// https://forums.alliedmods.net/showthread.php?t=72505?t=72505
native zp_get_user_ammo_packs(id);
native zp_set_user_ammo_packs(id, amount);

#pragma semicolon 1

#define PLUGIN "Shop SMS: ZP AP"
#define AUTHOR "SeeK"

new const service_id[MAX_SERVICE_ID + 1] = "zp_ap";

public plugin_natives()
{
	set_native_filter("native_filter");
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);
}

public plugin_cfg()
{
	ss_register_service(service_id);
}

public ss_service_bought(id, amount)
{
	zp_set_user_ammo_packs(id, zp_get_user_ammo_packs(id) + amount);
}

public native_filter(const native_name[], index, trap)
{
	if (trap == 0) {
		register_plugin(PLUGIN, VERSION, AUTHOR);
		pause_plugin();
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}
