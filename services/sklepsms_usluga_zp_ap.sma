#include <amxmodx>
#include <shop_sms>
native zp_get_user_ammo_packs(id);
native zp_set_user_ammo_packs(id, amount);

new const service_id[MAX_ID] = "zp_ap";
#define PLUGIN "Sklep-SMS: Usluga ZP AP"
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
	zp_set_user_ammo_packs(id,zp_get_user_ammo_packs(id)+amount);
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
