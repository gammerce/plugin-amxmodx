#include <amxmodx>
#include <shop_sms>

new const service_id[MAX_SERVICE_ID + 1] = "resslot";
#define PLUGIN "Sklep-SMS: Usluga Rezerwacja Slota"

new szFlags[32 + 1];

public plugin_init() {
	register_plugin(PLUGIN, VERSION, "SeeK")
}

public plugin_cfg() {
	ss_register_service(service_id);
}

public ss_service_data(name[], flags[]) {
	copy(szFlags, charsmax(szFlags), flags);
}

public ss_service_addingtolist(id) {
	// Wylaczamy mozliwosc zakupu, jezeli gracz juz ma odpowiedni zestaw flag
	if(get_user_flags(id) & read_flags(szFlags) == read_flags(szFlags)) {
		return ITEM_DISABLED;
	}
		
	return ITEM_ENABLED;
}
