#include <amxmodx>
#include <shop_sms>

new const service_id[MAX_ID] = "resnick";
#define PLUGIN "Sklep-SMS: Usluga Rezerwacja Nicku"

new szFlags[25];

public plugin_init() {
	register_plugin(PLUGIN, VERSION, "SeeK")
}

public plugin_cfg() {
	ss_register_service(service_id);
}

public ss_service_data(name[],flags[]) {
	copy(szFlags,sizeof szFlags,flags);
}
