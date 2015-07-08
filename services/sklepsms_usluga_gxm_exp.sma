#include <amxmodx>
#include <shop_sms>
native get_user_xp(id);
native set_user_xp(id, ilosc);

new const service_id[MAX_ID] = "gxm_exp";
#define PLUGIN "Sklep-SMS: Usluga GXM EXP"
#define AUTHOR "SeeK"

public plugin_natives() {
	set_native_filter("native_filter");
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR)
}

public plugin_cfg() {
	ss_register_service(service_id)
}

public ss_service_bought(id,amount) {
	set_user_xp(id,get_user_xp(id)+amount);
}

// Zabezpieczenie, jezeli plugin jest odpalony na serwerze bez odpowiednich funkcji
public native_filter(const native_name[], index, trap) {
	if(trap == 0) {
		register_plugin(PLUGIN, VERSION, AUTHOR); // Rejestrujemy plugin, aby nie bylo na liscie unknown
		pause_plugin();
		return PLUGIN_HANDLED;
	}
	return PLUGIN_CONTINUE;
}
