#include <amxmodx>
#include <shopsms>
#include <custom_color_chat>

native cod_get_user_class(id);
native cod_get_user_xp(id);
native cod_set_user_xp(id, wartosc);

#pragma semicolon 1

#define PLUGIN "Shop SMS: COD EXP"
#define AUTHOR "SeeK"

new const service_id[MAX_SERVICE_ID + 1] = "cod_exp";

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

public ss_service_chosen(id)
{
	if (!cod_get_user_class(id) ) {
		client_print_color(id, Red, "^4[%s] ^1Musisz ^3wybrac klase^1, aby moc zakupic EXP.", PREFIX);
		return SS_STOP;
	}
	
	return SS_OK;
}

public ss_service_bought(id, amount)
{
	cod_set_user_xp(id, cod_get_user_xp(id) + amount);
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
