#include <amxmodx>
#include <shopsms>
#include <custom_color_chat>

native cod_get_classes_num();
native cod_get_class_name(perk, Return[], len);
native cod_get_user_class(id);
native cod_get_user_xp(id);
native cod_set_user_xp(id, wartosc);
native cod_set_user_class(id, klasa, zmien=0);

#pragma semicolon 1

#define PLUGIN "Shop SMS: COD TE"
#define AUTHOR "SeeK"

#define TASK_CHECK_FIRST 1000
#define TASK_CHECK_SECOND 2000

new const service_id[MAX_SERVICE_ID + 1] = "cod_exp_transfer";

new fromClass[33], toClass[33], currentClass[33], fromClassExp[33];

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

public ss_service_addingtolist(id)
{
	return cod_get_classes_num() >= 2 ? ITEM_ENABLED : ITEM_OFF;
}

public ss_service_chosen(id)
{
	fromClass[id] = toClass[id] = currentClass[id] = fromClassExp[id] = 0;

	new menu = menu_create("Z jakiej klasy?", "fromClassMenu_handle");
	for (new i = 1; i <= cod_get_classes_num(); ++i) {
		new name[64+1];
		cod_get_class_name(i, name, charsmax(name));
		menu_additem(menu, name);
	}
	
	menu_setprop(menu, MPROP_BACKNAME, "Poprzednia");
	menu_setprop(menu, MPROP_NEXTNAME, "Nastepna");
	menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
	
	menu_display(id, menu);
	
	return SS_STOP;
}

public fromClassMenu_handle(id, menu, item)
{
	if (item < 0) {
		menu_destroy(menu);
		return;
	}
	
	// +1 poniewaz klasy zaczynaja sie od id: 1
	fromClass[id] = item+1;
		
	new menu2 = menu_create("Na jaka klase?", "toClassMenu_handle");
	new menu_callback = menu_makecallback("toClassMenu_callback");
	
	for (new i = 1; i <= cod_get_classes_num(); ++i) {
		new name[64+1];
		cod_get_class_name(i, name, charsmax(name));
		menu_additem(menu2, name, "", 0, menu_callback);
	}
		
	menu_setprop(menu2, MPROP_BACKNAME, "Poprzednia");
	menu_setprop(menu2, MPROP_NEXTNAME, "Nastepna");
	menu_setprop(menu2, MPROP_EXITNAME, "Wyjdz");
	
	menu_destroy(menu);
	menu_display(id, menu2);
}

public toClassMenu_callback(id, menu, item)
{
	return fromClass[id] == item+1 ? ITEM_DISABLED : ITEM_ENABLED;
}

public toClassMenu_handle(id, menu, item)
{
	if ( item < 0 ) {
		menu_destroy(menu);
		return;
	}
	
	// +1 poniewaz klasy zaczynaja sie od id: 1
	toClass[id] = item+1;
		
	menu_destroy(menu);
	
	// Zapisujemy obecna klase
	currentClass[id] = cod_get_user_class(id);
	
	// Sprawdzamy czy pierwsza klasa jest dostepna ( nie jest np. klasa VIP )
	cod_set_user_class(id, fromClass[id], 1);
	chosen_checkFirstClass(TASK_CHECK_FIRST+id);
}

public chosen_checkFirstClass(id)
{
	id -= TASK_CHECK_FIRST;
	if( cod_get_user_class(id) == fromClass[id] ) { // Prawidlowo ustawilo klase
		cod_set_user_class(id, toClass[id], 1);
		chosen_checkSecondClass(TASK_CHECK_SECOND+id);
	}
	else if ( cod_get_user_class(id) == currentClass[id] ) { // Wciaz nie zmienilo z poprzedniej klasy
		set_task(0.2, "chosen_checkFirstClass", TASK_CHECK_FIRST+id);
	}
	else if( !cod_get_user_class(id) ) {
		client_print_color(id, Red, "^4[%s] ^1Nie masz uprawnien, aby skorzystac z klasy z ktorej chcesz przeniesc EXP.", PREFIX);
	}
}

public chosen_checkSecondClass(id)
{
	id -= TASK_CHECK_SECOND;
	if( cod_get_user_class(id) == toClass[id] ) { // Prawidlowo ustawilo klase
		// Ustawiamy klase ktora mial gracz przed zakupem
		cod_set_user_class(id, currentClass[id], 1);
		ss_open_payment_method_menu(id);
	}
	else if ( cod_get_user_class(id) == fromClass[id] ) { // Wciaz nie zmienilo z poprzedniej klasy
		set_task(0.2, "chosen_checkSecondClass", TASK_CHECK_SECOND+id);
	}
	else if ( !cod_get_user_class(id) ) {
		client_print_color(id, Red, "^4[%s] ^1Nie masz uprawnien, aby skorzystac z klasy na ktora chcesz przeniesc EXP.", PREFIX);
	}
}

public ss_service_bought(id, amount)
{
	// Ustawiamy pierwsza klase
	cod_set_user_class(id, fromClass[id], 1);
	
	// Sprawdzamy czy pierwsza klasa sie prawidlowo zaladowala
	bought_checkFirstClass(TASK_CHECK_FIRST+id);
}

public bought_checkFirstClass(id)
{
	id -= TASK_CHECK_FIRST;
	if ( cod_get_user_class(id) == fromClass[id] ) { // Prawidlowo ustawilo klase
		// Zapisujemy EXP pierwszej klasy
		fromClassExp[id] = cod_get_user_xp(id);
		
		// Zerujemy EXP pierwszej klasy
		cod_set_user_xp(id, 0);
		
		new name[32+1]; get_user_name(id, name, charsmax(name));
		new class1[64+1]; cod_get_class_name(fromClass[id], class1, charsmax(class1));
		ss_log("Zabrano graczowi %s %d EXPa z klasy %s", name, fromClassExp[id], class1);
		
		// Ustawiamy druga klase
		cod_set_user_class(id, toClass[id], 1);
		bought_checkSecondClass(TASK_CHECK_SECOND+id);
	}
	else if ( cod_get_user_class(id) == currentClass[id] ) { // Wciaz nie zmienilo z poprzedniej klasy
		set_task(0.2, "bought_checkFirstClass", TASK_CHECK_FIRST+id);
	}
}

public bought_checkSecondClass(id)
{
	id -= TASK_CHECK_SECOND;
	if ( cod_get_user_class(id) == toClass[id] ) { // Prawidlowo ustawilo klase
		// Ustawiamy EXP na drugiej klasie
		cod_set_user_xp(id, cod_get_user_xp(id)+fromClassExp[id]);
		
		// Ustawiamy klase ktora mial gracz przed zakupem
		cod_set_user_class(id, currentClass[id], 1);
		
		new name[32+1]; get_user_name(id, name, charsmax(name));
		new class1[64+1]; cod_get_class_name(fromClass[id], class1, charsmax(class1));
		new class2[64+1]; cod_get_class_name(toClass[id], class2, charsmax(class2));
		ss_log("Przeniesiono graczowi %s %d EXPa z klasy %s na klase %s", name, fromClassExp[id], class1, class2);
	}
	else if ( cod_get_user_class(id) == fromClass[id] ) { // Wciaz nie zmienilo z poprzedniej klasy
		set_task(0.2, "bought_checkSecondClass", TASK_CHECK_SECOND+id);
	}
}

public native_filter(const native_name[], index, trap)
{
	if (trap == 0) {
		register_plugin(PLUGIN, VERSION, AUTHOR);
		pause_plugin();
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}
