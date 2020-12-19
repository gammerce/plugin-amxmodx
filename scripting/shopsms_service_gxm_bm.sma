#include <amxmodx>
#include <shopsms>

native get_user_bm(id);
native set_user_bm(id, ilosc);

#pragma semicolon 1

#define PLUGIN "Shop SMS: GXM BM"
#define AUTHOR "SeeK"

new const service_id[MAX_SERVICE_ID + 1] = "gxm_bm";

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
	set_user_bm(id, get_user_bm(id)+amount);
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
