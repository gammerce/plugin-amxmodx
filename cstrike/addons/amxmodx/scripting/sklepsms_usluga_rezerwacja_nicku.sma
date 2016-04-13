#include <amxmodx>
#include <shop_sms>

new const service_id[MAX_SERVICE_ID + 1] = "resnick";
#define PLUGIN "Sklep-SMS: Usluga Rezerwacja Nicku"

public plugin_init() {
	register_plugin(PLUGIN, VERSION, "SeeK")
}

public plugin_cfg() {
	ss_register_service(service_id);
}
