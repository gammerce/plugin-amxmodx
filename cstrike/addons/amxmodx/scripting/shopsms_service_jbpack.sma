#include <amxmodx>
#include <shopsms>

// https://amxx.pl/topic/127942-jailbreak-pack-shop/
native get_user_jbpack(id);
native set_user_jbpack(id, wartosc);

#pragma semicolon 1

#define PLUGIN "Shop SMS: JB Pack"
#define AUTHOR "SeeK"

new const service_id[MAX_SERVICE_ID + 1] = "jb_pack";

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
	set_user_jbpack(id, get_user_jbpack(id) + amount);
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
