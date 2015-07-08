#include <amxmodx>
#include <shop_sms>

new const service_id[MAX_ID] = "vip";
#define PLUGIN "Sklep-SMS: Usluga VIP"

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

public ss_service_addingtolist(id) {
	// Wylaczamy mozliwosc zakupu, jezeli gracz juz ma odpowiedni zestaw flag
	if(get_user_flags(id)&read_flags(szFlags) == read_flags(szFlags))
		return ITEM_DISABLED;
		
	return ITEM_ENABLED;
}
