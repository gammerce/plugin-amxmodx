#include <amxmodx>
#include <shopsms>

native bf2_get_maxbadges();
native bf2_get_badge_name(badge_id, badge_level, name[], len);
native bf2_get_user_badge(index, badge_id);
native bf2_set_user_badge(index, badge_id, level);

#pragma semicolon 1

#define PLUGIN "Shop SMS: BF2 badge"
#define AUTHOR "SeeK"
#define TASK_MENU1 1000

new const service_id[MAX_SERVICE_ID + 1] = "bf2_badge";

new stronaP[33], bool:wybranoP[33];
new dane[33];

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

public ss_service_chosen(id, amount)
{
	new menu = menu_create("Wybierz odznake:", "menuHandler");
	new menu_callback = menu_makecallback("menuCallback");
	new nazwa[64];
	
	for(new i = 0; i < bf2_get_maxbadges(); ++i) {
		bf2_get_badge_name(i, amount, nazwa, charsmax(nazwa));
		new data[2];
		data[0] = i+1;
		data[1] = bf2_get_user_badge(id, i) >= amount ? 0 : 1;
		
		menu_additem(menu, nazwa, data, 0, menu_callback);
	}
	
	menu_setprop(menu, MPROP_BACKNAME, "Poprzednia strona");
	menu_setprop(menu, MPROP_NEXTNAME, "Nastepna strona");
	menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
	
	// Reset
	wybranoP[id] = false;
	stronaP[id] = 0;
	
	// Task data
	new data[2];
	data[0] = id;
	data[1] = menu;

	wyswietlMenu(data);
	
	return SS_STOP;
}

public menuCallback(id, menu, item)
{
	new data[3], iName[2];
	new zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, charsmax(data), iName, charsmax(iName), callback);
	
	return data[1] ? ITEM_ENABLED : ITEM_DISABLED;
}

public wyswietlMenu(data[])
{
	new id = data[0];
	
	if (!is_user_connected(id)) {
		menu_destroy(data[1]);
		return;
	}
	
	if (!wybranoP[id]) {
		new menu, newmenu, page;
		player_menu_info(id, menu, newmenu, page);

		if (newmenu != data[1]) {
			menu_display(id, data[1], stronaP[id]);
		}
		else {
			stronaP[id] = page;
		}
			
		set_task(0.1, "wyswietlMenu", TASK_MENU1+id, data, 2);
	}
}

public menuHandler(id, menu, item)
{
	if (item == MENU_EXIT) {
		wybranoP[id] = true;
		menu_destroy(menu);
		return;
	}
	
	if (item >= 0) {
		// Badge has been selected
		wybranoP[id] = true;
		
		new data[2], iName[2];
		new zaccess, callback;
		menu_item_getinfo(menu, item, zaccess, data, charsmax(data), iName, charsmax(iName), callback);
		
		dane[id] = data[0] - 1;

		menu_destroy(menu);

		ss_open_payment_method_menu(id);
	}
}

public ss_service_bought(id, amount)
{
	new badge_id = dane[id];
	new badge_level = amount;
	
	if (bf2_set_user_badge(id, badge_id, badge_level) == -1) {
		return SS_ERROR;
	}
	
	new szText[512];
	bf2_get_badge_name(badge_id, badge_level, szText, charsmax(szText));
	format(szText, charsmax(szText), "<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
						<h1>Kupiles/as odznake: <span style=^"color: red^">%s</span><br /><br />\
						W razie problemow skontaktuj sie z nami.\
						</center></body></html>", szText);
	show_motd(id, szText, "Informacje dotyczace uslugi");
		
	return SS_OK;
}

public native_filter(const native_name[], index, trap)
{
	if(trap == 0) {
		register_plugin(PLUGIN, VERSION, AUTHOR);
		pause_plugin();
		return PLUGIN_HANDLED;
	}
	return PLUGIN_CONTINUE;
}
