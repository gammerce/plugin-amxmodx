#include <amxmodx>
#include <shopsms>

#pragma semicolon 1

new const service_id[MAX_SERVICE_ID + 1] = "resnick";

public plugin_init()
{
	register_plugin("Shop SMS: Nick reservation", VERSION, "SeeK");
}

public plugin_cfg()
{
	ss_register_service(service_id);
}
