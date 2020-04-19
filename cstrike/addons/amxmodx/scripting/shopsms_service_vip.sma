#include <amxmodx>
#include <shopsms>

#pragma semicolon 1

new const service_id[MAX_SERVICE_ID + 1] = "vip";

new szFlags[32 + 1];

public plugin_init()
{
	register_plugin("Shop SMS: VIP", VERSION, "SeeK");
}

public plugin_cfg()
{
	ss_register_service(service_id);
}

public ss_service_data(name[], flags[])
{
	copy(szFlags, charsmax(szFlags), flags);
}

public ss_service_addingtolist(id)
{
	// Disable purchasing if the user already has a flag set
	if (get_user_flags(id) & read_flags(szFlags) == read_flags(szFlags)) {
		return ITEM_DISABLED;
	}
		
	return ITEM_ENABLED;
}
