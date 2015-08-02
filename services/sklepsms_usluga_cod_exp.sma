#include <amxmodx>
#include <shop_sms>
#include <colorchat>
native cod_get_user_class(id);
native cod_get_user_xp(id);
native cod_set_user_xp(id, wartosc);

new const service_id[MAX_ID] = "cod_exp";
#define PLUGIN "Sklep-SMS: Usluga COD EXP"
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

public ss_service_chosen(id) {
	if( !cod_get_user_class(id) ) {
		client_print_color(id, Red, "^4[%s] ^1Musisz ^3wybrac klase^1, aby moc zakupic EXP.", PREFIX);
		return SS_STOP;
	}
	
	return SS_OK;
}

public ss_service_bought(id, amount) {
	cod_set_user_xp(id, cod_get_user_xp(id)+amount);
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
