#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <sockets>
#include <shop_sms_const>
#if AMXX_VERSION_NUM < 183
#include <colorchat>
#else
#define Red print_team_red
#define Blue print_team_blue
#endif

#pragma semicolon 1

forward amxbans_sql_initialized(Handle:sqlTuple, dbPrefix[]);

#define DOSTEP ADMIN_CFG
#define FLAG_NICK (1<<5)

// ID zadan
#define TASK_WYSWIETL 2000
#define TASK_CHECK_USER 5000
#define TASK_SHOW_MENU_SERVICE_TYPES 8000

// Sockets
#define TASK_CHECK_SOCKET 6000
#define TASK_TIME_OUT 7000

// Klawisze ktore mozna uzyc w menu
#define KEYS (1<<0)|(1<<9) // Keys: 10
#define KEYS2 (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<8)|(1<<9) // Keys: 1234567890

// Logowanie danych
#define LOGING
#define DEBUG "sklep_sms_debug.log"
#define CFG_FILE "sklep_sms.cfg"
#define LOG_FILE "sklep_sms.log"
//#define TRACE_FILE "sklep_sms_trace.log"

// Stale
const MAX_KOMENDA = 32;
const MAX_KONTAKT = 64;

//Rejestracja uslug
enum e_Service {
	sID[MAX_ID+1], 
	PLUGIN, 
	sNAME[MAX_NAME+1], 
	DESCRIPTION[MAX_DESCRIPTION+1], 
	TAG[MAX_SERVICE_TAG+1], 
	GROUPS[33], 
	FLAGS[27], 
	TYPES
};

new 	Array:service_plugins, 
	Array:service_ids, 
	Array:services;
	
// Modul platnosci
enum e_TransactionService {
	tsID[MAX_ID+1], 
	tsNAME[MAX_NAME+1], 
	SMS_TEXT[MAX_SMS_TEXT+1], 
};
new transaction_service[e_TransactionService];
	
// Numery i taryfy SMS
enum e_SMS {
	NUMBER[MAX_NUMBER+1], 
	sTARIFF, 
};
new Array:smses;

// Lista cen ( taryf ) dla usług
enum e_Price {
	pSERVICE[MAX_ID+1], 
	pTARIFF, 
	AMOUNT, 
};
new Array:pricelist;

//Dodatkowe zmienne
new 	which_service[33], 
	which_price[33], 
	b_passwords[33][MAX_PASSWORD+1], 
	b_types[33];

//CVARy
new cvar_on, cvar_show_info, cvar_sklep, cvar_przeladuj, cvar_uslugi, cvar_host, cvar_user, cvar_pass, cvar_db, cvar_server_ip;
new sklep_komenda[MAX_KOMENDA+1], przeladuj_komenda[MAX_KOMENDA+1], uslugi_komenda[MAX_KOMENDA+1], show_info;

// Sciezka do pliku konfiguracyjnego
new config_path[128];

//Licencja
new license[32], license_password[33];
new bool:footer = true;
new server_ip[32];
new server_name[128];
new bool:blocked = false;

// MySQL
new const TABLE_PREFIX[] = "ss_";
new Handle:SqlTuple;
new bool:sql_connected = false;
new sql_host[64], sql_user[32], sql_pass[32], sql_db[32];
new server_id;
new const all_flags[] = "abcdefghijklmnopqrstuyvwxz";
new szTemp[4096];

// Flagi graczy
enum e_PlayerFlags {
	pfPLAYER[33], 
	pfFLAGS, 
	pfPASSWORD[MAX_PASSWORD+2], 
	pfTYPE
};
new Array:players_flags;
new bool:players_loaded = false;
new ostatnie_przeladowanie;

// Sockets
new sockets[33];

// Settings
new st_currency[16], 
	st_shop_url[128], 
	st_signature[128], 
	st_sms_service[65], 
	st_contact[MAX_KONTAKT+1], 
	st_random_key[33], 
	st_random_key_md5[34], 
	Float:st_vat;
	
new shop_url[128], shop_url_add[128];

new bool:shop_registered = false;
new bool:is_amxbans = false;

public plugin_natives() {
	register_library("shop_sms");
	register_native("ss_register_service", "registerService");
	register_native("ss_show_sms_info", "native_infoSMS");
	register_native("ss_add_code", "native_addCode");
	register_native("ss_log", "dodajLog");
	register_native("ss_is_steam", "native_is_steam");
}

public plugin_precache() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: plugin_precache");
	#endif
	get_configsdir(config_path, charsmax(config_path));
	
	// Tworzenie pliku sklep_sms.cfg
	format(config_path, charsmax(config_path), "%s/%s", config_path, CFG_FILE);
	if(!file_exists(config_path)) {
		new szText[1024], iLen=0, iMax=charsmax(szText);
		iLen += formatex(szText[iLen], iMax-iLen, "// ----------------------------------^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// SKLEP SMS: - Plik Konfiguracyjny^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// ----------------------------------^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Wlacza / Wylacza sklepik^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// 1 - wlaczony^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// 0 - wylaczony^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_on ^"1^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Komenda, ktora nalezy wpisac na chacie w celu wyswietlenia menu sklepiku^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_sklep_komenda ^"/sklepsms^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Komenda, ktora nalezy wpisac na chacie w celu przeladowania flag wykupionych w sklepiku^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_przeladuj_komenda ^"/przeladuj^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Komenda, ktora nalezy wpisac na chacie, aby zobaczyc swoje aktywne uslugi^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_uslugi_komenda ^"/uslugi^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Wyswietlac informacje o sklepie na chacie?^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_info ^"1^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// #########################^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// ###  Dane Bazy MySQL  ###^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// #########################^n^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Adres IP^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_host ^"^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Uzytkownik^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_user ^"^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Haslo^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_pass ^"^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Nazwa bazy danych");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_db ^"^"");
		write_file(config_path, szText);
	}
	
	//Rejestrowanie cvarow
	cvar_on 	= register_cvar("sklepsms_on", "1");
	cvar_sklep 	= register_cvar("sklepsms_sklep_komenda", "/sklepsms");
	cvar_przeladuj 	= register_cvar("sklepsms_przeladuj_komenda", "/przeladuj");
	cvar_uslugi 	= register_cvar("sklepsms_uslugi_komenda", "/uslugi");
	cvar_show_info 	= register_cvar("sklepsms_info", "1");
	cvar_host 	= register_cvar("sklepsms_host", "localhost");
	cvar_user 	= register_cvar("sklepsms_user", "root");
	cvar_pass 	= register_cvar("sklepsms_pass", "");
	cvar_db 	= register_cvar("sklepsms_db", "");
	cvar_server_ip	= register_cvar("sklepsms_server_ip", "");
	
	// Wczytywanie confingu
	if(file_exists(config_path)) {
		server_cmd("exec %s", config_path);
	}
	
	service_plugins = ArrayCreate();
	service_ids = ArrayCreate(MAX_NAME);
	
	players_flags = ArrayCreate(e_PlayerFlags);
	smses = ArrayCreate(e_SMS);
	services = ArrayCreate(e_Service);
	pricelist = ArrayCreate(e_Price);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: plugin_precache");
	#endif
}

public plugin_init() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: plugin_init");
	#endif
	
	register_plugin("Sklep SMS", VERSION, "SeeK");
	
	register_menucmd(register_menuid("SMS_Info"), KEYS, "infoSMS_handler");
	register_concmd("Podaj_Kod_Zwrotny", "kodZwrotny");
	register_concmd("ssnick_Podaj_Haslo", "menuServiceType_nick");
	register_concmd("ssip_Podaj_Haslo", "menuServiceType_ip");
	register_concmd("sklepsms_reloaddata", "usersReloadData");
	register_concmd("sklepsms_reloadusers", "pre_usersReload");
	
	register_clcmd("say", "sayHook");
	register_clcmd("say_team", "sayHook");
	
	if( show_info )
		set_task(137.0, "reklama", _, _, _, "b");
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: plugin_init");
	#endif
}

public loadCvars() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: loadCvar");
	#endif

	//Pobieranie wartosci cvarow
	get_pcvar_string(cvar_sklep, sklep_komenda, charsmax(sklep_komenda));
	get_pcvar_string(cvar_przeladuj, przeladuj_komenda, charsmax(przeladuj_komenda));
	get_pcvar_string(cvar_uslugi, uslugi_komenda, charsmax(uslugi_komenda));
	show_info = get_pcvar_num(cvar_show_info);
	
	get_pcvar_string(cvar_host, sql_host, charsmax(sql_host));
	get_pcvar_string(cvar_user, sql_user, charsmax(sql_user));
	get_pcvar_string(cvar_pass, sql_pass, charsmax(sql_pass));
	get_pcvar_string(cvar_db, sql_db, charsmax(sql_db));
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: loadCvar");
	#endif
}

public plugin_end() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: plugin_end");
	#endif
	
	if( SqlTuple )
		SqlTuple = Empty_Handle;
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: plugin_end");
	#endif
}

public plugin_cfg() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: plugin_cfg");
	#endif
	
	// Blad przy tworzeniu ( brak uprawnien )
	if( !file_exists(config_path) )
		brakSciezki(0, config_path);
		
	// Ponowne wczytywanie confingu
	if( file_exists(config_path) ) {
		server_cmd("exec %s", config_path);
		server_exec();
	}
	
	// Pobieranie ip serwera
	get_pcvar_string(cvar_server_ip, server_ip, charsmax(server_ip));
	if( !strlen(server_ip) ) // Brak ip w cvarach
		get_user_ip(0, server_ip, charsmax(server_ip));
	
	// Ladownaie cvarow
	loadCvars();
	
	// Łaczenie z baza
	SqlTuple = SQL_MakeDbTuple(sql_host, sql_user, sql_pass, sql_db);
	if( !SqlTuple ) _error42("plugin_cfg");
	
	// Zaladuj flagi
	_usersLoad(false);
	
	new ip[22], port[10];
	split(server_ip, ip, charsmax(ip), port, charsmax(port), ":");
	
	formatex(szTemp, charsmax(szTemp),
		"SELECT s.id, s.name, s.sms_service, CONCAT(' ', GROUP_CONCAT( ss.service_id SEPARATOR ' ' ), ' ') AS `services` \
		FROM `%sservers` AS s \
		LEFT JOIN `%sservers_services` AS ss ON ss.server_id = s.id \
		WHERE s.ip = '%s' AND s.port = '%s' \
		GROUP BY s.id",
		TABLE_PREFIX, TABLE_PREFIX, ip, port
	);
	//log_to_file(LOG_FILE, szTemp);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getServerData", szTemp);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: plugin_cfg");
	#endif
}

public checkLoadedServices() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: checkLoadedServices");
	#endif
	
	if( !ArraySize(services) ) {
		log_amx("Nie zaladowano zadnych uslug.");
	} else {
		log_amx("Zaladowano %d uslug.", ArraySize(services));
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: checkLoadedServices");
	#endif
}

public client_authorized(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: client_authorized");
	#endif
	
	_usersCheckUser(id);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: client_authorized");
	#endif
}

public client_putinserver(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: client_putinserver");
	#endif
	
	_usersCheckUser(id);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: client_putinserver");
	#endif
}

public sayHook(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: sayHook");
	#endif
	
	new tekst[32];
	read_argv(1, tekst, charsmax(tekst));
	
	if(equali(tekst, sklep_komenda)) {
		if(blocked)
			client_print_color(id, Red, "^4[%s] ^1Nie mozna otworzyc sklepiku z powodu bledow ze sklepem.", PREFIX);
		else
			sklepMenu(id);
	}
	else if(equali(tekst, przeladuj_komenda)) {
		pre_usersReload(id);
	}
	else if(equali(tekst, uslugi_komenda)) {
		_showPlayerServices(id);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: sayHook");
	#endif
}

/* Menu sklepu */
public sklepMenu(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: sklepMenu");
	#endif
	
	if( !is_user_connected(id) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: sklepMenu");
		#endif
		return;
	}
	if(!get_pcvar_num(cvar_on)) {
		client_print_color(id, Red, "^4[%s] ^1Sklep jest obecnie ^3wylaczony^1.", PREFIX);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: sklepMenu");
		#endif
		return;
	}
	if( !sql_connected ) {
		client_print_color(id, Red, "^4[%s] ^1Nie polaczono z baza danych.", PREFIX);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end4: sklepMenu");
		#endif
		return;
	}
	if(!ArraySize(services)) {
		client_print_color(id, Red, "^4[%s] ^1Brak dostepnych uslug do kupienia.", PREFIX);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end3: sklepMenu");
		#endif
		return;
	}
	if( !shop_registered ) {
		client_print_color(id, Red, "^4[%s] ^1Nie udalo sie przeprowadzic walidacji licencji lub wystapil blad w zapytaniu do bazy danych.", PREFIX);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end5: sklepMenu");
		#endif
		return;
	}
	
	new menu;
	if(footer)
		menu = menu_create("\rSklep SMS\d napedzany przez\w sklep-sms.pl^n\yWybierz usluge:", "sklepMenu_handler");
	else
		menu = menu_create("\rSklep SMS^n\yWybierz usluge:", "sklepMenu_handler");		
		
	new menu_callback = menu_makecallback("sklepMenu_callback");
	
	new szText[64], service[e_Service];
	for(new i = 0; i < ArraySize(services); ++i) {
		new data[4];
		data[0] = i+1;
		// Pobierz dane o usludze
		ArrayGetArray(services, i, service);
		
		// Usluga wymaga posiadania grupy, TODO zakodzic to
		/*if( strlen(service[GROUPS]) )
			continue;*/
		
		// Sforamtuj punkt w menu
		if( service[DESCRIPTION] )
			formatex(szText, charsmax(szText), "Kup %s \d(%s)", service[sNAME], service[DESCRIPTION]);
		else
			formatex(szText, charsmax(szText), "Kup %s", service[sNAME]);
		
		new ret;
		new forward_handle = CreateOneForward(service[PLUGIN], "ss_service_addingtolist", FP_CELL);
		ExecuteForward(forward_handle, ret, id);
		DestroyForward(forward_handle);
		
		data[1] = ret;
		
		if(data[1] != ITEM_OFF)
			menu_additem(menu, szText, data, 0, menu_callback);
	}
	
	//Wyjdz zamiast Exit
	menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
	menu_display(id, menu);
	
	client_print_color(id, Red, "^4[%s] ^1W razie problemow mozesz sie z nami skontaktowac", PREFIX);
	client_print_color(id, Red, "^4[%s] ^1poprzez: ^3%s", PREFIX, st_contact);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end6: sklepMenu");
	#endif
}

public sklepMenu_callback(id, menu, item) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: sklepMenu_callback");
	#endif
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: sklepMenu_callback");
	#endif
	return data[1] == ITEM_DISABLED ? ITEM_DISABLED : ITEM_ENABLED;
}

public sklepMenu_handler(id, menu, item) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: sklepMenu_handler");
	#endif
	
	if( !is_user_connected(id) || item == MENU_EXIT ) {
		menu_destroy(menu);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: sklepMenu_handler");
		#endif
		return;
	}
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	wyborMenu(id, data[0]-1);
	menu_destroy(menu);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: sklepMenu_handler");
	#endif
}
/* Konie menu sklepu */

/* Menu wyboru */
public wyborMenu(id, service_id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: wyborMenu");
	#endif
	
	if( !is_user_connected(id) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "start: wyborMenu");
		#endif
		return;
	}
		
	new service[e_Service];
	ArrayGetArray(services, service_id, service);
		
	new szText[64], data[3];
	
	formatex(szText, charsmax(szText), "\rSklep SMS^n\yWybierz ilosc %s:", service[sNAME]);
	
	new menu = menu_create(szText, "wyborMenu_handler");
	
	new price[e_Price], number[MAX_NUMBER+1];
	for(new i = 0; i < ArraySize( pricelist ); ++i) {
		ArrayGetArray(pricelist, i, price);
		// ID usługi jest inne
		if( !equali(price[pSERVICE], service[sID]) )
			continue;
		
		// Pobranie numeru na ktory trzeba wyslac SMSa
		setc(number, strlen(number), 0);
		_getNumberByTariff(price[pTARIFF], number, charsmax(number));
		
		// Przy danej metodzie płatności nie można użyć danej taryfy
		if( !strlen(number) )
			continue;
		
		new amount[32+1];
		if( price[AMOUNT] == -1 ) // Jezeli -1 to usluga jest na zawsze
			formatex(amount, charsmax(amount), "Na zawsze");
		else {
			groupDigits(price[AMOUNT], amount, charsmax(amount));
			format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
		}
		new temp_cost = get_sms_cost(number);
		formatex(szText, charsmax(szText), 
			"\y%s \wza %d.%s %s + VAT\d ( %d.%s %s )", 
			amount, temp_cost/100, two_number_value(temp_cost%100), st_currency, floatround(temp_cost*st_vat)/100, 
			two_number_value(floatround(temp_cost*st_vat)%100), st_currency
		);
		data[0] = service_id+1;
		data[1] = min(127, i); // Problem przy ilosci uslug powyzej 256!
		data[2] = min(127, i-data[1]);
		menu_additem(menu, szText, data);
	}
	
	// Wyjdz zamiast Exit
	menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
	
	if( menu_items(menu) > 1 )
		menu_display(id, menu);
	else if(menu_items(menu) == 1) { // Jezeli jest tylko jeden item, przejdz od razu do informacji o smsie
		which_service[id] = service_id;
		which_price[id] = data[1]+data[2];
		prev_infoSMS(id);
	}
	else // Zero
		client_print_color(id, Red, "^4[%s] ^1Brak cennika dla tej uslugi.", PREFIX);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: wyborMenu");
	#endif
}

public wyborMenu_handler(id, menu, item) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: wyborMenu_handler");
	#endif
	
	if(!is_user_connected(id) || item == MENU_EXIT) {
		menu_destroy(menu);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: wyborMenu_handler");
		#endif
		return;
	}
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	which_service[id] = data[0]-1;
	which_price[id] = data[1]+data[2];
	
	prev_infoSMS(id);
	menu_destroy(menu);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: wyborMenu_handler");
	#endif
}
/* Koniec menu wyboru */

/* Informacje dot SMSa */

public prev_infoSMS(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: prev_infoSMS");
	#endif
	
	new service[e_Service];
	ArrayGetArray(services, which_service[id], service);
	
	if( service[TYPES] & (TYPE_NICK|TYPE_IP|TYPE_SID) ) {	
		// Wyswietlamy menu z wyborem na co chcemy kupic usluge
		new menu = menu_create("Wybierz typ uslugi", "menuServiceType_handler");
		new menu_callback = menu_makecallback("menuServiceType_callback");
	
		menu_additem(menu, "Na Nick + haslo", "", 0, menu_callback);
		menu_additem(menu, "Na IP + haslo", "", 0, menu_callback);
		menu_additem(menu, "Na SteamID", "", 0, menu_callback);
	
		menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER);
	
		new data[4];
		data[0] = id;
		data[1] = menu;
		
		menuDisplayServiceTypes(data);
	}
	else
		_serviceChosen(id);
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: prev_infoSMS");
	#endif
}

public menuServiceType_callback(id, menu, item) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: menuServiceType_callback");
	#endif
	
	new service[e_Service];
	ArrayGetArray(services, which_service[id], service);

	switch( item ) {
		case 0: return service[TYPES]&TYPE_NICK ? ITEM_ENABLED : ITEM_DISABLED;
		case 1: return service[TYPES]&TYPE_IP ? ITEM_ENABLED : ITEM_DISABLED;
		case 2: return service[TYPES]&TYPE_SID && is_steam(id) ? ITEM_ENABLED : ITEM_DISABLED;
	}
	
	return ITEM_DISABLED;
}

public menuDisplayServiceTypes(data[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: menuDisplayServiceTypes");
	#endif
	
	new id = data[0];
	if( !is_user_connected(id) ) {
		menu_destroy(data[1]);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: menuDisplayServiceTypes");
		#endif
		return;
	}
	
	new menu, newmenu;
	player_menu_info(id, menu, newmenu);
	if(newmenu != data[1])
		menu_display(id, data[1]);
			
	set_task(0.1, "menuDisplayServiceTypes", TASK_SHOW_MENU_SERVICE_TYPES+id, data, 2);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: menuDisplayServiceTypes");
	#endif
}

public menuServiceType_handler(id, menu, item) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: menuServiceType_handler");
	#endif
	
	switch(item) {
		case 0: {
			client_cmd(id, "messagemode ssnick_Podaj_Haslo");
		}
		case 1: {
			client_cmd(id, "messagemode ssip_Podaj_Haslo");
		}
		case 2: {
			_serviceChosen(id, TYPE_SID, "");
		}
	}
	
	if( 0 <= item <= 2) {
		remove_task(TASK_SHOW_MENU_SERVICE_TYPES+id);
		menu_destroy(menu);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: menuServiceType_handler");
	#endif
}

public menuServiceType_nick(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: menuServiceType_nick");
	#endif
	
	new szPassword[65];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if( !_menuServiceType_checkPass(id, TYPE_NICK, szPassword) )
		client_cmd(id, "messagemode ssnick_Podaj_Haslo");
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: menuServiceType_nick");
	#endif
}

public menuServiceType_ip(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: menuServiceType_ip");
	#endif
	
	new szPassword[65];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if( !_menuServiceType_checkPass(id, TYPE_IP, szPassword) )
		client_cmd(id, "messagemode ssip_Podaj_Haslo");
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: menuServiceType_ip");
	#endif
}

bool:_menuServiceType_checkPass(id, type, szPassword[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _menuServiceType_checkPass");
	#endif
	
	if( strlen(szPassword) > 30 ) {
		client_print(id, print_center, "Podane haslo jest za dlugie. Maksymalna ilosc znakow wynosi 30.");
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: _menuServiceType_checkPass");
		#endif
		return false;
	}
	else if( !strlen(szPassword) ) {
		client_print(id, print_center, "Haslo nie zostalo wprowadzone. Wprowadz je.");
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: _menuServiceType_checkPass");
		#endif
		return false;
	}
	
	_serviceChosen(id, type, szPassword);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end3: _menuServiceType_checkPass");
	#endif
	return true;
}

public checkServicePassword(FailState, Handle:Query, Error[], Errorcode, data[], data_size) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: checkServicePassword");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: checkServicePassword");
		#endif
		return;
	}

	new id = data[0];
	new type = data[1];
	// Haslo takie jak do innych uslug
	if( SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "equal")) ) {
		new szPassword[33];
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "password"), szPassword, charsmax(szPassword));
		_serviceChosen(id, type, szPassword);
	}
	else {
		if( type == TYPE_NICK ) {
			client_print_color(id, Red, "^4[%s] ^1Istnieje juz usluga wykupiona na ten ^3nick^1, lecz posiada inne haslo. Wprowadz haslo ^3ponownie^1.", PREFIX);
			client_cmd(id, "messagemode ssnick_Podaj_Haslo");
		}
		else if( type == TYPE_IP ) {
			client_print_color(id, Blue, "^4[%s] ^1Istnieje juz usluga wykupiona na ten ^3adres IP^1, lecz posiada inne haslo. Wprowadz haslo ^3ponownie^1.", PREFIX);
			client_cmd(id, "messagemode ssip_Podaj_Haslo");
		}
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: checkServicePassword");
	#endif
}

_serviceChosen(id, type=0, szPassword[] = "") {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _serviceChosen");
	#endif
	
	new service[e_Service], price[e_Price];
	ArrayGetArray(services, which_service[id], service);
	ArrayGetArray(pricelist, which_price[id], price);
	copy(b_passwords[id], MAX_PASSWORD, szPassword);
	b_types[id] = type;

	new ret;
	new forward_handle = CreateOneForward(service[PLUGIN], "ss_service_chosen", FP_CELL, FP_CELL);
	ExecuteForward(forward_handle, ret, id, price[AMOUNT]);
	DestroyForward(forward_handle);
	
	if( ret != SS_STOP ) {
		infoSMS(id);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: _serviceChosen");
	#endif
}

public infoSMS(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: infoSMS");
	#endif
	
	if( !is_user_connected(id) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: infoSMS");
		#endif
		return;
	}
	
	new service[e_Service], price[e_Price], number[MAX_NUMBER+1], szText[512];
	ArrayGetArray(services, which_service[id], service);
	ArrayGetArray(pricelist, which_price[id], price);
	_getNumberByTariff(price[pTARIFF], number, charsmax(number));
	
	new amount[32+1];
	if( price[AMOUNT] == -1 ) // Jezeli -1 to usluga jest na zawsze
		formatex(amount, charsmax(amount), "Na zawsze");
	else {
		groupDigits(price[AMOUNT], amount, charsmax(amount));
		format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
	}
	
	formatex(szText, charsmax(szText), "\rSklep SMS^n^n");
	format(szText, charsmax(szText), "%sWybrales/as opcje zakupu %s ^n\wInfo: \y%s", szText, service[sNAME], amount);
	new temp_cost = get_sms_cost(number);
	format(szText, charsmax(szText), 
		"%s^n^n\rW celu dokonania zakupu, wyslij SMSa^n\wO tresci: \y%s^n\wNa numer: \y%s^n\wKoszt: \y%d.%s %s + VAT\d ( %d.%s %s )", 
		szText, transaction_service[SMS_TEXT], number, temp_cost/100, two_number_value(temp_cost%100), st_currency, floatround(temp_cost*st_vat)/100, 
		two_number_value(floatround(temp_cost*st_vat)%100), st_currency
	);
	format(szText, charsmax(szText), "%s^n^n\wPo wyslaniu SMSa poczekaj na kod zwrotny.^nW celu wprowadzenia go, wcisnij: \y1^n^n\wAby wyjsc, wcisnij: \y0", szText);
	
	//Wyswietlane caly czas menu zakupu
	infoSMS_wyswietl(szText, id+TASK_WYSWIETL);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: infoSMS");
	#endif
}

public infoSMS_wyswietl(info[], id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: infoSMS_wyswietl");
	#endif
	
	id -= TASK_WYSWIETL;
	if( !is_user_connected(id) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: infoSMS_wyswietl");
		#endif
		return;
	}
		
	show_menu(id, KEYS, info, 1, "SMS_Info");
	set_task(0.9, "infoSMS_wyswietl", id+TASK_WYSWIETL, info, strlen(info));
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: infoSMS_wyswietl");
	#endif
}

public infoSMS_handler(id, key) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: infoSMS_handler");
	#endif
	
	if(task_exists(id+TASK_WYSWIETL)) remove_task(id+TASK_WYSWIETL);
		
	if( !is_user_connected(id) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: infoSMS_handler");
		#endif
		return;
	}
		
	if(key == 0) {
		client_cmd(id, "messagemode Podaj_Kod_Zwrotny");
	}
	else if(key == 9) {
		client_print_color(id, Red, "^4[%s] ^1Transakcja zostala ^3przerwana^1.", PREFIX);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: infoSMS_handler");
	#endif
}

// Wprowadzanie kodu zwrotnego
public kodZwrotny(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: kodZwrotny");
	#endif
	
	if( !is_user_connected(id) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: kodZwrotny");
		#endif
		return;
	}
		
	new sms_code[MAX_CODE+1], szUrl[512];
	read_argv(1, sms_code, charsmax(sms_code));
	
	dodajLog2(id, "Wprowadzono kod: %s", sms_code);
	
	if(!strlen(sms_code)) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: kodZwrotny");
		#endif
		client_print_color(id, Red, "^4[%s] ^1Nie wprowadzono kodu zwrotnego.", PREFIX);
		return;
	}
	else if(containi(sms_code, " ") != -1) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end3: kodZwrotny");
		#endif
		client_print_color(id, Red, "^4[%s] ^1Kod zwrotny ^3nie moze ^1zawierac ^3spacji^1.", PREFIX);
		return;
	}
	else if(strlen(sms_code) == 1 && containi(sms_code, "0") == 0) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end4: kodZwrotny");
		#endif
		client_print_color(id, Red, "^4[%s] ^1Kod zwrotny ^3nie moze ^1byc rowny^3 0^1.", PREFIX);
		return;
	}
	
	client_print_color(id, Red, "^4[%s] ^1Trwa weryfikacja kodu...", PREFIX);
	
	// ############# ZAKUP USLUGI ###############
	
	new service[e_Service], auth_data[32], price[e_Price], ip[32];
	new u_service_id[65], u_auth_data[64], u_password[65], u_sms_service[65], u_sms_code[MAX_CODE*2+1], u_ip[64];
	
	// Pobieramy dane o usludze
	ArrayGetArray(services, which_service[id], service);
		
	// Pobieramy dane gracza Nick / IP / SID
	switch( b_types[id] ) {
		case TYPE_IP: get_user_ip(id, auth_data, charsmax(auth_data), 1);
		case TYPE_SID: get_user_authid(id, auth_data, charsmax(auth_data));
		case TYPE_NICK: get_user_name(id, auth_data, charsmax(auth_data));
	}
	
	// Jezeli usluga nie jest wykupowana na nickpass, ippass, sid, to pobieramy nick
	if( !strlen(auth_data) )
		get_user_name(id, auth_data, charsmax(auth_data));
		
	// Pobieramy IP gracza
	get_user_ip(id, ip, charsmax(ip), 1);
			
	// Pobieramy taryfe
	ArrayGetArray(pricelist, which_price[id], price);
	
	// Urlencode
	StringURLEncode(service[sID], u_service_id, charsmax(u_service_id));
	StringURLEncode(auth_data, u_auth_data, charsmax(u_auth_data));
	StringURLEncode(b_passwords[id], u_password, charsmax(u_password));
	StringURLEncode(st_sms_service, u_sms_service, charsmax(u_sms_service));
	StringURLEncode(sms_code, u_sms_code, charsmax(u_sms_code));
	StringURLEncode(ip, u_ip, charsmax(u_ip));
	
	formatex(szUrl, charsmax(szUrl), 
		"%sservers_stuff.php?action=purchase_service&key=%s&service=%s&type=%d&auth_data=%s&password=%s&method=sms&server=%d&transaction_service=%s&sms_code=%s&tariff=%d&uid=0&ip=%s&platform=engine_amxx&language=polish", 
		shop_url_add, st_random_key_md5, u_service_id, b_types[id], u_auth_data, u_password, server_id, u_sms_service, u_sms_code, price[pTARIFF], u_ip
	);
	sendSocket(id, shop_url, szUrl, "purchase_service");
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end4: kodZwrotny");
	#endif
}

public purchaseService_callback(id, return_value[], szText[], positive, bsid, szWarnings[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: purchaseService_callback");
	#endif
	
	client_print_color(id, Red, "^4[%s] ^1%s", PREFIX, szText);
	
	if( strlen(szWarnings) ) {
		format(szWarnings, 1023, 
			"<html>\
			<head><meta http-equiv=^"Content-Type^" content=^"text/html^" charset=^"UTF-8^"></head>\
			<body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^">\
			<div style=^"text-align: center; font-size: 22px; font-weight: bold;^">Bledy ktore wystapily przy zakupie uslugi</div>\
			%s\
			<i>Uzyj jeszcze raz tego samego kodu zwrotnego sms</i>.</body>\
			</html>", 
			szWarnings
		);
		show_motd(id, szWarnings, "Bledy przy zakupie uslugi");
	}
	
	// Wystapil jakis blad, wiec przerywamy
	if( positive != 1 ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: purchaseService_callback");
		#endif
		return;
	}
		
	new ret, forward_handle, service[e_Service], price[e_Price], number[MAX_NUMBER+1];
	ArrayGetArray(services, which_service[id], service);
	ArrayGetArray(pricelist, which_price[id], price);
	_getNumberByTariff(price[pTARIFF], number, charsmax(number));
	
	forward_handle = CreateOneForward(service[PLUGIN], "ss_service_bought", FP_CELL, FP_CELL);
	ExecuteForward(forward_handle, ret, id, price[AMOUNT]);
	DestroyForward(forward_handle);
	
	// Wystapil jakis blad
	if( ret == SS_ERROR ) {		
		client_print_color(id, Red, "^4[%s] ^1Wystapil ^3blad ^1podczas kupowania uslugi. Zglos nam to: ^4%s", PREFIX, st_contact);
		
		new amount[32+1];
		if( price[AMOUNT] == -1 ) // Jezeli -1 to usluga jest na zawsze
			formatex(amount, charsmax(amount), "Na zawsze");
		else {
			groupDigits(price[AMOUNT], amount, charsmax(amount));
			format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
		}
		
		dodajLog2(id, "Wystapil blad podczas kupowania %s - %s; Taryfa: %d", service[sNAME], amount, price[pTARIFF]);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: purchaseService_callback");
		#endif
		return;
	}
	
	// Jezeli usluga ma flagi do ustawienia to wczytujemy ponownie dane z bazy
	if( service[FLAGS] )
		usersReloadData();
	
	// Info w przypadku usługi na haslo
	if( b_types[id] & (TYPE_NICK|TYPE_IP) ) {
		// Ustawienie hasla
		client_cmd(id, "setinfo _ss ^"%s^"", b_passwords[id]);
		
		new szText[512];
		formatex(szText, charsmax(szText), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>Wykupiles/as usluge: <span style=^"color: red^">%s</span><br /><br />\
			Aby usluga dziala, dodaj wpis do pliku <i>config.cfg</>: <span style=^"color: #3399ff^">setinfo _ss ^"%s^"</span><br /><br />\
			W razie problemow skontaktuj sie z nami.\
			</center></body></html>", 
			service[sNAME], b_passwords[id]
		);
		show_motd(id, szText, "Informacje dotyczace uslugi");
	}
	else if( b_types[id]&TYPE_SID ) {
		new szText[512];
		formatex(szText, charsmax(szText), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>Wykupiles/as usluge: <span style=^"color: red^">%s</span><br /><br />\
			W razie problemow skontaktuj sie z nami.\
			</center></body></html>", 
			service[sNAME]
		);
		show_motd(id, szText, "Informacje dotyczace uslugi");
	}
	
	new amount[32+1];
	if( price[AMOUNT] == -1 ) // Jezeli -1 to usluga jest na zawsze
		formatex(amount, charsmax(amount), "Na zawsze");
	else {
		groupDigits(price[AMOUNT], amount, charsmax(amount));
		format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
	}
	
	client_print_color(id, Blue, "^4[%s] ^1Prawidlowo kupiono ^4%s^1: %s", PREFIX, service[sNAME], amount);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end3: purchaseService_callback");
	#endif
}

// Dodanie kodu do bazy kodow
public addCode(sms_code[], sms_tariff, free) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: addCode");
	#endif
	
	formatex(szTemp, charsmax(szTemp), "INSERT INTO `%ssms_codes` (`code`, `tariff`, `free`) VALUES ('%s', '%d', '%d')", TABLE_PREFIX, sms_code, sms_tariff, free);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "IgnoreHandle", szTemp);
	dodajLog2(0, "Dodano SMSa do tabeli kodow do wykorzystania. Kod: %s Taryfa: %d", sms_code, sms_tariff);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: addCode");
	#endif
	return SS_OK;
}

// Wyswietlenie obecnych uslug gracza

_showPlayerServices(id) {
	if( !is_user_connected(id) )
		return;
		
	new name[64+1], sid[64+1], ip[32+1];
	get_user_name(id, name, charsmax(name));
	escape(name, charsmax(name));
	get_user_ip(id, ip, charsmax(ip), 1);
	escape(ip, charsmax(ip));
	get_user_authid(id, sid, charsmax(sid));
	escape(sid, charsmax(sid));

	new data[1]; data[0] = id;
	formatex(szTemp, charsmax(szTemp),
		"SELECT s.name AS `service`, FROM_UNIXTIME(ps.expire) AS `expire`, ps.expire AS `expire_num` FROM `%splayers_services` AS ps \
		LEFT JOIN `%sservices` AS s ON ps.service = s.id \
		WHERE ps.server = '%d' \
		AND ((ps.type = '%d' AND ps.auth_data = '%s') \
		OR (ps.type = '%d' AND ps.auth_data = '%s') \
		OR (ps.type = '%d' AND ps.auth_data = '%s'))",
		TABLE_PREFIX, TABLE_PREFIX, server_id, TYPE_NICK, name, TYPE_IP, ip, TYPE_SID, sid
	);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getPlayerServices", szTemp, data, sizeof data);
}

public getPlayerServices(FailState, Handle:Query, Error[], Errorcode, data[], data_size) {
	new id = data[0];
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		client_print_color(id, Red, "^4[%s] ^1Niestety, nie udalo sie pozyskac informacji o Twoich uslugach.", PREFIX);
		return;
	}

	new menu = menu_create("Twoje obecne uslugi", "showPlayerServices_handler");

	while(SQL_MoreResults(Query)) {
		new service[MAX_ID+1], expire[32+1], item_text[128];
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "service"), service, charsmax(service));
		
		if( SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "expire_num")) == -1 )
			copy(expire, charsmax(expire), "Nigdy");
		else
			SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "expire"), expire, charsmax(expire));
		
		formatex(item_text, charsmax(item_text), "%s - wygasa: %s", service, expire);
		menu_additem(menu, item_text);
		
		SQL_NextRow(Query);
	}
	
	if( menu_items(menu) ) {
		menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
		menu_display(id, menu);
	}
	else
		client_print_color(id, Red, "^4[%s] ^1Nie masz jeszcze ^3zadnej uslugi^1. Moze czas to zmienic? ;-) Wpisz: ^3%s.", PREFIX, sklep_komenda);
}

public showPlayerServices_handler(id, menu, item) {	
	menu_destroy(menu);
}

// Funkcje dotyczace flag graczy 

public pre_usersReload(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: pre_usersReload");
	#endif
	
	if(ostatnie_przeladowanie+10 > get_systime()) {
		client_print_color(id, Red, "^4[%s] ^1Ktos przed chwila przeladowal liste. Odczekaj chwile.", PREFIX);
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: pre_usersReload");
		#endif
		return;
	}
	ostatnie_przeladowanie = get_systime();
	_usersReload(id);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: pre_usersReload");
	#endif
}

_usersReload(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _usersReload");
	#endif
	
	for(new i = 1; i <= get_maxplayers(); ++i) {
		if( !is_user_connected(i) )
			continue;
			
		_usersCheckUser(i);
	}
	if( id )
		client_print_color(id, Red, "^4[%s] ^1Prawidlowo przeladowano liste flag wykupionych w sklepiku.", PREFIX);
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: _usersReload");
	#endif
}

// Funkcja wczytujaca z bazy ponownie dane graczy
public usersReloadData() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: usersReloadData");
	#endif
	
	// Wczytywanie danych graczy
	_usersLoad(true);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: usersReloadData");
	#endif
}

_usersLoad(bool:reload) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _usersLoad");
	#endif
	
	// Czyscimy dotychczasowe dane
	ArrayClear(players_flags);
	players_loaded = false;
	
	new ip[16], port[8];
	split(server_ip, ip, charsmax(ip), port, charsmax(port), ":");
	
	formatex(szTemp, charsmax(szTemp), 
		"SELECT f.id, f.type, f.auth_data, f.password, f.a, f.b, f.c, f.d, f.e, f.f, f.g, f.h, f.i, f.j, f.k, f.l, f.m, f.n, f.o, f.p, f.q, f.r, f.s, f.t, f.u, f.y, f.v, f.w, f.x, f.z \
		FROM `%splayers_flags` AS f \
		JOIN `%sservers` AS s ON s.id = f.server \
		WHERE s.ip = '%s' \
		AND s.port = '%s' \
		ORDER BY f.auth_data, f.type DESC", 
		TABLE_PREFIX, TABLE_PREFIX, ip, port
	);
	
	new data[1]; data[0] = reload; // Przeladuj liste adminow w amxbans
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getPlayersData", szTemp, data, sizeof data);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: _usersLoad");
	#endif	
}

public getPlayersData(FailState, Handle:Query, Error[], Errorcode, data[], data_size) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getPlayersData");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: getPlayersData");
		#endif
		return;
	}

	while(SQL_MoreResults(Query))
	{
		new player_flags[e_PlayerFlags], type;
		type = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "type"));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "auth_data"), player_flags[pfPLAYER], 32);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "password"), player_flags[pfPASSWORD], MAX_PASSWORD);
		
		for(new i = 0; i < strlen(all_flags); ++i) {
			new temp[4];
			formatex(temp, charsmax(temp), "%c", all_flags[i]);
			new expire = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, temp));
			if( expire > get_systime() || expire == -1 )
				player_flags[pfFLAGS] |= read_flags(temp);
		}
		
		if( type == TYPE_SID )
			player_flags[pfTYPE] = FLAG_AUTHID|FLAG_NOPASS;
		else if( type == TYPE_IP )
			player_flags[pfTYPE] = FLAG_IP;
		else
			player_flags[pfTYPE] = FLAG_NICK|FLAG_KICK;
			
		//Dodanie do tablicy
		if( player_flags[pfFLAGS] != 0 ) {
			ArrayPushArray(players_flags, player_flags);
		}
		
		SQL_NextRow(Query);
	}
	
	players_loaded = true;
	
	if( data[0] && is_amxbans ) {// Przeladuj dane w amxbans, a tym samym uruchom komende dodawania danych do tablicy globalnej uprawnien
		server_cmd("amx_reloadadmins");
	}
	else {
		// Sprawdzamy uprawnienia graczy
		_usersReload(0);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: getPlayersData");
	#endif	
}

public amxbans_sql_initialized() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: amxbans_sql_initialized");
	#endif
	
	is_amxbans = true;
	addUsersToGlobalArray();
	// Sprawdzamy uprawnienia graczy
	_usersReload(0);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: amxbans_sql_initialized");
	#endif
}

// Funkcja sluzaca do dodania graczy do tablicy globalnej przechowujacej dane uprawnien graczy
public addUsersToGlobalArray() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: addUsersToGlobalArray");
	#endif
	
	if( !players_loaded ) { // Dane uzytkownikow nie zostaly jeszcze zaladowane
		set_task(0.1, "addUsersToGlobalArray");
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: addUsersToGlobalArray");
		#endif
		return;
	}
	
	// Potrzebujemy drugiej tablicy, zeby elementy z amxbansa mialy takie samo id
	new Array:users, Array:users2;
	users = ArrayCreate(e_PlayerFlags);
	users2 = ArrayCreate(e_PlayerFlags);
	
	for(new i = 0; i < ArraySize(players_flags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(players_flags, i, player_flags);
		ArrayPushArray(users, player_flags);
	}
	
	for(new i = 0; i < admins_num(); ++i) {
		new player_flags[e_PlayerFlags], name_bak[33];
		
		admins_lookup(i, AdminProp_Auth, player_flags[pfPLAYER], 32);
		copy(name_bak, charsmax(name_bak), player_flags[pfPLAYER]);
		strtolower(name_bak);
		
		admins_lookup(i, AdminProp_Password, player_flags[pfPASSWORD], MAX_PASSWORD);
		
		player_flags[pfTYPE] = admins_lookup(i, AdminProp_Flags);
		player_flags[pfFLAGS] = admins_lookup(i, AdminProp_Access);
		
		new l = 0, p = ArraySize(users)-1, s;
		while(l <= p) {
			new player_flags2[e_PlayerFlags];
			s = (l + p) / 2;
			
			ArrayGetArray(users, s, player_flags2);
			strtolower(player_flags2[pfPLAYER]);
			if( equali(name_bak, player_flags2[pfPLAYER]) && player_flags[pfTYPE] == player_flags2[pfTYPE] ) {
				// Zostawiamy haslo AMXBansa
				player_flags[pfFLAGS] |= player_flags2[pfFLAGS];
				ArrayPushArray(users2, player_flags);
				ArrayDeleteItem(users, s);
				break;
			}
			else if( strcmp(name_bak, player_flags2[pfPLAYER]) > 0 ) {
				l = s + 1;
			}
			else if( equali(name_bak, player_flags2[pfPLAYER]) && _getOrderOfType(player_flags[pfTYPE]) > _getOrderOfType(player_flags2[pfTYPE]) ) {
				l = s + 1;
			}
			else {
				p = s - 1;
			}
		}
		
		if( p < l ) {
			ArrayPushArray(users2, player_flags);
		}
	}
	admins_flush();
	
	for(new i = 0; i < ArraySize(users2); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(users2, i, player_flags);
		admins_push(player_flags[pfPLAYER], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
	for(new i = 0; i < ArraySize(users); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(users, i, player_flags);
		admins_push(player_flags[pfPLAYER], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: addUsersToGlobalArray");
	#endif
}

_getOrderOfType(type) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _getOrderOfType");
	#endif
	
	switch(type) {
		case FLAG_IP: return 1;
		case FLAG_NICK : return 2;
		case FLAG_AUTHID: return 3;
	}
	
	return 0;
}

public usersCheckUser_task(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: sersCheckUser_task");
	#endif
	
	_usersCheckUser(id-TASK_CHECK_USER);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: sersCheckUser_task");
	#endif
}

public _usersCheckUser(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _usersCheckUser");
	#endif
	
	if( !players_loaded ) {
		if( !task_exists(TASK_CHECK_USER+id) )
			set_task(0.1, "usersCheckUser_task", TASK_CHECK_USER+id);
			
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: _usersCheckUser");
		#endif
		return;
	}
	
	for(new i = 0; i < ArraySize(players_flags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(players_flags, i, player_flags);
		
		if( player_flags[pfTYPE]&FLAG_NICK ) {
			new name[32];
			get_user_name(id, name, charsmax(name));
			if( !equali(name, player_flags[pfPLAYER]) )
				continue;
		}
		else if( player_flags[pfTYPE]&FLAG_IP ) {
			new ip[32];
			get_user_ip(id, ip, charsmax(ip), 1);
			if( !equali(ip, player_flags[pfPLAYER]) )
				continue;
		}
		else if( player_flags[pfTYPE]&FLAG_AUTHID ) {			
			new sid[32], arr_sid[32];
			copy(arr_sid, charsmax(arr_sid), player_flags[pfPLAYER]);
			get_user_authid(id, sid, charsmax(sid));
			
			strtolower(arr_sid);
			strtolower(sid);
			replace(sid, charsmax(sid), "steam_", "");
			replace(arr_sid, charsmax(arr_sid), "steam_", "");
			
			if( !equali(sid, arr_sid) )
				continue;
		}
		
		if( strlen(player_flags[pfPASSWORD]) ) {
			new password[33], password_md5[34];
			
			get_user_info(id, "_pw", password, charsmax(password));
			md5(password, password_md5);
			
			if( !equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD]) ) {
				get_user_info(id, "_pw2", password, charsmax(password));
				md5(password, password_md5);
				if( !equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD]) ) {
					get_user_info(id, "_pw3", password, charsmax(password));
					md5(password, password_md5);
					if( !equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD]) ) {
						get_user_info(id, "_ss", password, charsmax(password));
						md5(password, password_md5);
						if( !equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD]) ) {
							if( !(player_flags[pfTYPE]&FLAG_KICK) ) // Nie kickuj gracza, tylko mu nie przydziel flag
								continue;
						
							server_cmd("kick #%d ^"Bledne haslo^"", get_user_userid(id));
							
							#if defined TRACE_FILE
							log_to_file(TRACE_FILE, "end2: _usersCheckUser");
							#endif
							return;
						}
					}
				}
			}
		}
		
		set_user_flags(id, player_flags[pfFLAGS]);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end3: _usersCheckUser");
	#endif
}

public brakSciezki(id, path[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: brakSciezki");
	#endif
	
	dodajLog2(0, "Nie mozna utworzyc pliku/folderu: %s. Prawdopodonbnie brak uprawnien do zapisu. Utworz plik recznie.", path);
	log_to_file(LOG_FILE, "Nie mozna utworzyc pliku/folderu: %s. Prawdopodonbnie brak uprawnien do zapisu. Utworz plik recznie.", path);
	if( id )
		client_print_color(id, Blue, "^4[%s] ^1Wystapil ^3blad ^1przy zapisywaniu ustawien. Prawdopodobnie ^4brak uprawnien^1.", PREFIX);

	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: brakSciezki");
	#endif
}

public reklama() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: reklama");
	#endif
	
	if(get_playersnum()>1) {
		client_print_color(0, Red, "^4[%s] ^1Zapraszamy wszystkich do korzystania ze ^3sklepiku! ^1Wystarczy wpisac: ^4%s", PREFIX, sklep_komenda);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: reklama");
	#endif
}

public dodajLog2(id, const szFormat[], any:...) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: dodajLog2");
	#endif
	
	#if defined LOGING
	new szText[256], name[33], ip[22], sid[22];
	vformat(szText, charsmax(szText), szFormat, 3);
	get_user_name(id, name, charsmax(name));
	get_user_ip(id, ip, charsmax(ip), 1);
	get_user_authid(id, sid, charsmax(sid));
	
	if(id) format(szText, charsmax(szText), "%s; %s; %s. %s", name, ip, sid, szText);
	
	log_to_sql(szText, charsmax(szText));
	#endif
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: dodajLog2");
	#endif
}

public log_to_sql(text[], text_len) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: log_to_sql");
	#endif
	
	format(text, text_len, "%s. Serwer: %d", text, server_id);
	escape(text, text_len);
	
	formatex(szTemp, charsmax(szTemp), "INSERT INTO `%slogs` (text) VALUES ('%s')", TABLE_PREFIX, text);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "IgnoreHandle", szTemp);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: log_to_sql");
	#endif
}

public getServerData(FailState, Handle:Query, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getServerData");
	#endif
	
	sql_connected = true;
	if(FailState != TQUERY_SUCCESS) {
		log_to_file(LOG_FILE, "Tresc bledu ( %d ): %s", Errorcode, Error );
		
		SQL_GetQueryString(Query, szTemp, charsmax(szTemp));
		log_to_file(LOG_FILE, "Zapytanie: %s", szTemp);
	
		if(FailState == TQUERY_QUERY_FAILED) {
			if(containi(Error, "exist") != -1) _error22(Errorcode, Error);
			else _error15("getServerData", Errorcode, Error);
		}
		else if( FailState == TQUERY_CONNECT_FAILED ) {
			sql_connected = false;
			_error41(Errorcode, Error);
			
			#if defined TRACE_FILE
			log_to_file(TRACE_FILE, "end1: getServerData");
			#endif
			return;
		}
		
		_error40();
	}

	if(SQL_NumResults(Query) <= 0) {
		_error21();
	}
	
	// Pobranie id serwera
	server_id = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "id"));
	
	// Pobranie uslugi obslugujacej platnosci
	new sms_service[64];
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "sms_service"), sms_service, charsmax(sms_service));
	if( strlen(sms_service) )
		copy(st_sms_service, charsmax(st_sms_service), sms_service);
		
	// Pozyskanie uslug na serwerze
	new szServices[512];
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "services"), szServices, charsmax(szServices));
	
	// Pobranie ustawien sklepu
	formatex(szTemp, charsmax(szTemp), "SELECT * FROM `%ssettings` WHERE `key` IN ('currency', 'shop_url', 'signature', 'sms_service', 'contact', 'vat', 'random_key', 'license_login', 'license_password')", TABLE_PREFIX);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getSettings", szTemp);
	
	// Aktualizacja informacji o serwerze
	formatex(szTemp, charsmax(szTemp), "UPDATE `%sservers` SET `type` = 'amxx', `version` = '%s' WHERE `id` = '%d'", TABLE_PREFIX, VERSION, server_id);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "IgnoreHandle", szTemp);
	
	// Sprawdzanie dostepnosci usług
	new service_id[MAX_NAME+1], service_id_space[MAX_NAME+2+1], ids[512], ids_len = 0, ids_max = charsmax(ids);
	for(new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, service_id, charsmax(service_id));
		formatex(service_id_space, charsmax(service_id_space), " %s ", service_id);
		
		if( containi(szServices, service_id_space) != -1 ) {
			if( ids_len )
				ids_len += formatex(ids[ids_len], ids_max-ids_len, ",");
				
			ids_len += formatex(ids[ids_len], ids_max-ids_len, "'%s'", service_id);
		}
		else { // Usługa nieaktywna, lub brak usługi
			// Zatrzymaj plugin uslugi
			new plugin_name[64];
			get_plugin(ArrayGetCell(service_plugins, i), plugin_name, charsmax(plugin_name));
			pause("acd", plugin_name);
			ArrayDeleteItem(service_ids, i);
			ArrayDeleteItem(service_plugins, i);
			i -= 1;
		}
	}
	
	// Jest chociaz jedna usluga, wiec pobieramy dane o uslugach
	if( ids_len ) {
		formatex(szTemp, charsmax(szTemp), "SELECT * FROM `%sservices` WHERE `id` IN(%s) ORDER BY `order` ASC", TABLE_PREFIX, ids);
		if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getServicesData", szTemp);
	}
	else
		// Sprawdz zaladowane uslugi
		checkLoadedServices();
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: getServerData");
	#endif
}

public getServicesData(FailState, Handle:Query, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getServicesData");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		_error12();
	}

	new service[e_Service];
	new ids[512], ids_len = 0, ids_max = charsmax(ids);
	while(SQL_MoreResults(Query))
	{
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "id"), service[sID], MAX_ID);
		service[PLUGIN] = _getServicePluginByID(service[sID]);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "name"), service[sNAME], MAX_NAME);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "short_description"), service[DESCRIPTION], MAX_DESCRIPTION);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "tag"), service[TAG], MAX_SERVICE_TAG);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "flags"), service[FLAGS], 26);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "groups"), service[GROUPS], 32);
		service[TYPES] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "types"));
		
		ArrayPushArray(services, service);
			
		// Wyslanie danych uslugi do pluginu
		new ret, forward_handle;
		forward_handle = CreateOneForward(service[PLUGIN], "ss_service_data", FP_STRING, FP_STRING);
		ExecuteForward(forward_handle, ret, service[sNAME], service[FLAGS]);
		DestroyForward(forward_handle);
		
		// Przygotowywanie zapytania o priceliste
		if( ids_len )
			ids_len += formatex(ids[ids_len], ids_max-ids_len, ",", szTemp);
		
		ids_len += formatex(ids[ids_len], ids_max-ids_len, "'%s'", service[sID]);
		
		SQL_NextRow(Query);
	}
	
	// Sprawdz zaladowane uslugi
	checkLoadedServices();
	
	// Jest chociaz jedna usluga
	if( ids_len ) {
		formatex(szTemp, charsmax(szTemp), 
			"SELECT * FROM `%spricelist` \
			WHERE (`server`='%d' OR `server`='-1') AND `service` IN (%s) \
			ORDER BY `amount` ASC", 
			TABLE_PREFIX, server_id, ids
		);
		if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getPriceList", szTemp);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: getServicesData");
	#endif
}

public getPriceList(FailState, Handle:Query, Error[], Errorcode) {	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getPriceList");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: getPriceList");
		#endif
		return;
	}

	while(SQL_MoreResults(Query))
	{
		new price[e_Price];
		
		price[pTARIFF] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "tariff"));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "service"), price[pSERVICE], MAX_ID);
		price[AMOUNT] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "amount"));
		
		ArrayPushArray(pricelist, price);
		
		SQL_NextRow(Query);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: getPriceList");
	#endif
}

public getSettings(FailState, Handle:Query, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getSettings");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: getSettings");
		#endif
		return;
	}

	new key[128], value[256];
	while( SQL_MoreResults(Query) ) {
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "key"), key, charsmax(key));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "value"), value, charsmax(value));
		
		if(equali(key, "currency"))
			copy(st_currency, charsmax(st_currency), value);
		else if(equali(key, "shop_url")) {
			copy(st_shop_url, charsmax(st_shop_url), value);
			replace(st_shop_url, charsmax(st_shop_url), "http://www.", "");
			replace(st_shop_url, charsmax(st_shop_url), "http://", "");
			
			if( strlen(st_shop_url) == 0 ) {
				_error33();
			}
			
			if(st_shop_url[strlen(st_shop_url)-1] != '/')
				format(st_shop_url, charsmax(st_shop_url), "%s/", st_shop_url);
			
			split(st_shop_url, shop_url, charsmax(shop_url), shop_url_add, charsmax(shop_url_add), "/");
			
			format(shop_url_add, charsmax(shop_url_add), "/%s", shop_url_add);
		}
		else if(equali(key, "signature"))
			copy(st_signature, charsmax(st_signature), value);
		else if( equali(key, "sms_service") && !strlen(st_sms_service) )
			copy(st_sms_service, charsmax(st_sms_service), value);
		else if(equali(key, "contact"))
			copy(st_contact, charsmax(st_contact), value);
		else if(equali(key, "vat"))
			st_vat = str_to_float(value);
		else if(equali(key, "random_key")) {
			copy(st_random_key, charsmax(st_random_key), value);
			// Hashujemy random key
			md5(st_random_key, st_random_key_md5);
		}
		else if(equali(key, "license_login")) {
			copy(license, charsmax(license), value);
			trim(license);
		}
		else if(equali(key, "license_password")) {
			copy(license_password, charsmax(license_password), value);
		}
		
		SQL_NextRow(Query);
	}
	
	// Sprawdzamy czy licencja jest prawidłowa
	validateLicense();
	
	// Pobranie numerow sms
	escape(st_sms_service, charsmax(st_sms_service));
	formatex(szTemp, charsmax(szTemp), "SELECT `number`, `tariff` FROM `%ssms_numbers` WHERE `service` = '%s'", TABLE_PREFIX, st_sms_service);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getSMSesData", szTemp);
	
	// Pobranie danych o serwisie transakcyjnym
	formatex(szTemp, charsmax(szTemp), "SELECT * FROM `%stransaction_services` WHERE `id` = '%s'", TABLE_PREFIX, st_sms_service);
	if(SqlTuple) SQL_ThreadQuery(SqlTuple, "getTransactionServiceData", szTemp);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: getSettings");
	#endif
}

// Funkcja ktora wysyla zapytanie do serwera o sprawdzenie czy licencja jest prawidlowa
public validateLicense() {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: validateLicense");
	#endif
	
	// Sprawdzenie licencji
	new szUrl[512], szName[128];
	get_cvar_string("hostname", server_name, charsmax(server_name));
	StringURLEncode(server_name, szName, charsmax(szName)); // Escaepowanie adresu url
	
	formatex(szUrl, charsmax(szUrl), 
		"/license.php?action=login_server&type=engine_amxx&license_id=%s&license_password=%s&server_ip=%s&version=%s&name=%s", 
		license, license_password, server_ip, VERSION, szName
	);
	sendSocket(0, "license.sklep-sms.pl", szUrl, "validate_license");
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: validateLicense");
	#endif
}

public getTransactionServiceData(FailState, Handle:Query, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getTransactionServiceData");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: getTransactionServiceData");
		#endif
		return;
	}

	if( SQL_NumResults(Query) <= 0 ) {
		_error31();
	}
	
	if( !SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "sms")) ) {
		_error32();
	}
	
	new data[256];
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "id"), transaction_service[tsID], MAX_ID);
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "name"), transaction_service[tsNAME], MAX_NAME);
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "data"), data, charsmax(data));
	if( !json_decode(data, "sms_text", transaction_service[SMS_TEXT], MAX_SMS_TEXT) )
		log_to_file(LOG_FILE, "Nie udalo sie pobrac kodu sms.");
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: getTransactionServiceData");
	#endif
}

public getSMSesData(FailState, Handle:Query, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getSMSesData");
	#endif
	
	if( _checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: getSMSesData");
		#endif
		return;
	}

	new sms[e_SMS];
	while(SQL_MoreResults(Query))
	{
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "number"), sms[NUMBER], MAX_NUMBER);
		sms[sTARIFF] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "tariff"));
		ArrayPushArray(smses, sms);
		
		SQL_NextRow(Query);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: getSMSesData");
	#endif
}

_checkForSQLErrors(Handle:Query, FailState, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _checkForSQLErrors");
	#endif
	
	sql_connected = true;
	if(FailState != TQUERY_SUCCESS) {
		if(FailState == TQUERY_QUERY_FAILED)
			log_to_file(LOG_FILE, "Nie mozna podlaczyc sie do bazy danych.");
		else if(FailState == TQUERY_CONNECT_FAILED) {
			log_to_file(LOG_FILE, "Zapytanie anulowane.");
			sql_connected = false;
		}
		
		log_to_file(LOG_FILE, "Tresc bledu ( %d ): %s", Errorcode, Error );
		
		SQL_GetQueryString(Query, szTemp, charsmax(szTemp));
		log_to_file(LOG_FILE, "Zapytanie: %s", szTemp);
		
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: _checkForSQLErrors");
		#endif
		return PLUGIN_HANDLED;
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: _checkForSQLErrors");
	#endif
	return PLUGIN_CONTINUE;
}

public IgnoreHandle(FailState, Handle:Query, Error[], Errorcode) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: IgnoreHandle");
	#endif
	
	_checkForSQLErrors(Query, FailState, Error, Errorcode);
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: IgnoreHandle");
	#endif
}

/* #########################################################################################################################
 * ############################################### Zewnetrzne funkcje ######################################################
 * #########################################################################################################################
 */
 
public registerService(plugin, params) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: registerService");
	#endif
	
	if(params != 1) {
		log_to_file(LOG_FILE, "Wystapil blad podczas dodawania uslugi. Bledna ilosc argumentow funkcji ss_register_service");
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: registerService");
		#endif
		return SS_ERROR;
	}
		
	new id[MAX_NAME+1];
	
	get_string(1, id, charsmax(id));
	
	ArrayPushCell(service_plugins, plugin);
	ArrayPushString(service_ids, id);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: registerService");
	#endif
	return SS_OK;
}

// Dodawanie kodu do listy kodow do wykorzystania
public native_addCode(plugin, params) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: native_addCode");
	#endif
	
	if( params != 2 ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: native_addCode");
		#endif
		return;
	}
	
	new sms_code[MAX_CODE+1], tariff;
	get_string(1, sms_code, charsmax(sms_code));
	tariff = get_param(2);
	addCode(sms_code, tariff, 1);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: native_addCode");
	#endif
}

// Logowanie danych z pluginow zewnetrznych
public dodajLog(plugin, params) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: dodajLog");
	#endif
	
	#if defined LOGING
	new text[1024];
	vdformat(text, charsmax(text), 1, 2);
	log_to_sql(text, charsmax(text));
	#endif
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: dodajLog");
	#endif
}

public native_infoSMS(plugin, params) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: native_infoSMS");
	#endif
	
	if(params != 1) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: native_infoSMS");
		#endif
		return SS_ERROR;
	}
	
	infoSMS( get_param(1) );
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: native_infoSMS");
	#endif
	return SS_OK;
}

public bool:native_is_steam(plugin, params) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: native_is_steam");
	#endif
	
	if(params != 1) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: native_is_steam");
		#endif
		return false;
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: native_is_steam");
	#endif
	return is_steam( get_param(1) );
}

bool:is_steam(id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: is_steam");
	#endif
	
	new auth[32];
	get_user_authid(id, auth, charsmax(auth));
	if(contain(auth, "STEAM_0:0:") != -1 || contain(auth, "STEAM_0:1:") != -1) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: is_steam");
		#endif
		return true;
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: is_steam");
	#endif
	return false;
}

/* #########################################################################################################################
 * ###################################################### LICENCJA #########################################################
 * #########################################################################################################################
 */

/* ############ Poczatek: Licencja ################ */
public licenseUpdateActivity() {
	/*new szUrl[256], szName[128]
	get_user_name(0, server_name, charsmax(server_name));
	StringURLEncode(server_name, szName, charsmax(szName)); // Escaepowanie adresu url
	formatex(szUrl, charsmax(szUrl), "%slicense.php?action=update_activity&license_id=%s&server_ip=%s&version=%s&name=%s", shop_url_add, license, server_ip, VERSION, szName);
	sendSocket(0, "license.sklep-sms.pl", szUrl, "update_activity");
	
	set_task(300.0, "licenseUpdateActivity");*/
}

// ######### TYPY BŁĘDÓW ##########
// ## 1 - licencja
// ## 2 - server w bazie
// ## 3 - metody płatnosci
// ## 4 - sklep ogolnie
// ################################

_error10() {
	_make_error("Error 10 - Wystapil blad");
}

_error12() {
	_make_error("Error 12 - Blad ladowania licencji");
}

_error13() {
	new szText[128];
	formatex(szText, charsmax(szText), "Error 13 - Brak licencji o numerze identyfikacyjnym: %s lub bledne haslo.", license);
	_make_error(szText);
}

_error14() {
	log_to_file(LOG_FILE, "Error 14 - Nie udalo sie zaktualizowac aktywnosci serwera.");
	blocked = true;
}

// Problemy programistyczne
_error15(details[], errorcode, error[]) {
	#if defined DEBUG
	if(errorcode) log_to_file(DEBUG, "%d: %s", errorcode, error);
	log_to_file(DEBUG, "Error 15 - Zglos ten blad: seek@sklep-sms.pl lub GG: 8930366. Szczegoly: %s", details);
	#endif
}

// Problemy z serwerem w bazie
_error21() {
	_make_error("Error 21 - Serwer nie znajduje sie nie liscie serwerow na stronie WWW.");
}

_error22(errorcode, error[]) {
	#if defined DEBUG
	if(errorcode) log_to_file(DEBUG, "%d: %s", errorcode, error);
	#endif
	_make_error("Error 22 - Brak tabeli ss_servers w bazie.");
}

// Metody Płatnosci
_error31() {
	#if defined DEBUG
	log_to_file(DEBUG, "Error 31 - Brak danej metody platnosci.");
	#endif
	blocked = true;
}

_error32() {
	#if defined DEBUG
	log_to_file(DEBUG, "Error 32 - Wybrana metoda platnosci nie obsluguje platnosci SMS.");
	#endif
	blocked = true;
}

_error33() {
	#if defined DEBUG
	log_to_file(DEBUG, "Error 33 - Brak podanego adresu sklepu w ustawieniach.");
	#endif
	blocked = true;
}

// Niesprecyzowany blad
_error40() {
	#if defined DEBUG
	log_to_file(DEBUG, "Error 40 - Wystapil nieznany blad przy polaczeniu z baza sklepu.");
	#endif
	blocked = true;
}

_error41(errorcode, error[]) {
	#if defined DEBUG
	if(errorcode) log_to_file(DEBUG, "%d: %s", errorcode, error);
	#endif
	log_to_file(LOG_FILE, "Error 41 - Nie mozna polaczyc sie z baza danych sklepu.");
	blocked = true;
}

_error42(details[]) {
	log_to_file(DEBUG, "Error 42 - Zglos ten blad: seek@sklep-sms.pl lub GG: 8930366. Szczegoly: %s", details);
}

_make_error(informacja[]) {
	set_fail_state(informacja);
}
/* ############# Koniec: Licencja ################## */

// ######### Sockets #########
public socket_polacz(id, szHost[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: socket_polacz");
	#endif
	
	new error;
	if( sockets[id] ) {
		closeSocket(id);
	}
	
	sockets[id] = socket_open(szHost, 80, SOCKET_TCP, error);
	//error = 3;
	if( error ) {
		if(is_user_connected(id))
			client_print_color(id, Red, "^4[%s] ^1Nie mozna polaczyc sie z serwerem.", PREFIX);
		#if defined LOG_FILE
		log_to_file(LOG_FILE, "Nie mozna polaczyc sie z hostem: %s. ID bledu: %d.", szHost, error);
		#endif
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: socket_polacz");
		#endif
		return 0;
	}
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: socket_polacz");
	#endif
	return 1;
}

public socket_CheckData(szAction[], id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: socket_CheckData");
	#endif
	
	id -= TASK_CHECK_SOCKET;
	if(!socket_change(sockets[id])) {
		set_task(0.6, "socket_CheckData", TASK_CHECK_SOCKET+id, szAction, strlen(szAction));
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: socket_CheckData");
		#endif
		return;
	}
	
	new szData[1024];
	
	socket_recv(sockets[id], szData, charsmax(szData));
		
	if(contain(szData, "Status: 404") >= 0) {
		#if defined DEBUG
		log_to_file(DEBUG, "Nie znaleziono pliku. Akcja: %s", szAction);
		#endif
		closeSocket(id);
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: socket_CheckData");
		#endif
		return;
	}
	
	//log_to_file(DEBUG, "%s", szData);
	
	if( equal(szAction, "purchase_service") ) {
		new return_value[33], szText[128], szPositive[3], szBsid[16], szWarnings[1024];
		
		getXMLValue(szData, "return_value", return_value, charsmax(return_value));
		getXMLValue(szData, "text", szText, charsmax(szText));
		getXMLValue(szData, "positive", szPositive, charsmax(szPositive));
		getXMLValue(szData, "bsid", szBsid, charsmax(szBsid));
		getXMLValue(szData, "warnings", szWarnings, charsmax(szWarnings));
		
		purchaseService_callback(id, return_value, szText, str_to_num(szPositive), str_to_num(szBsid), szWarnings);
	}
	else if( equal(szAction, "validate_license") ) {
		new text[33];
		
		getXMLValue(szData, "text", text, charsmax(text));
		
		if( equal(text, "updated") ) {
			new szFooter[2];
			getXMLValue(szData, "footer", szFooter, charsmax(szFooter));
			footer = str_to_num(szFooter) ? true : false;
			
			//set_task(300.0, "licenseUpdateActivity");
			log_amx("Walidacja licencji o numerze identyfikacyjnym: %s zostala zakonczona pomyslnie", license);
			shop_registered = true;
		}
		else if( equal(text, "not_updated") ) {
			_error14();
		}
		else if( equal(text, "not_logged_successfully") ) {
			_error13();
		}
		else {
			#if defined DEBUG
			log_to_file(DEBUG, "%s", szData);
			#endif
			_error10();
		}
	}
	else if( equal(szAction, "update_activity") ) {
		new text[33];
		
		getXMLValue(szData, "text", text, charsmax(text));
		
		if( equal(text, "updated") ) {
			blocked = false;
		}
		else if( equal(text, "not_updated") ) {
			_error14();
		}
		else if( equal(text, "not_logged") ) {
			// Probujemy sie ponownie zalogowac
			set_task(0.1, "validateLicense");
		}
	}

	closeSocket(id);
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end3: socket_CheckData");
	#endif
}

public sendSocket(id, szHost[], szUrl[], szAction[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: sendSocket");
	#endif
	
	if( !socket_polacz(id, szHost) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: sendSocket");
		#endif
		return;
	}
	
	new szText[512];
	formatex(szText, charsmax(szText), "GET %s HTTP/1.1^r^nHost: %s^r^n^r^n", szUrl, szHost);
	socket_send(sockets[id], szText, strlen(szText));
	
	format(szText, charsmax(szText), "%s|%s", szAction, szText);
	//Utworzenie nowego pseudo watku oczekujacego na odpowiedz
	set_task(0.6, "socket_CheckData", TASK_CHECK_SOCKET+id, szAction, strlen(szAction));
	set_task(10.0, "socket_TimeOut", TASK_TIME_OUT+id, szText, strlen(szText));
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: sendSocket");
	#endif
}

public socket_TimeOut(szData[], id) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: socket_TimeOut");
	#endif
	
	id -= TASK_TIME_OUT;
	
	new szAction[32], szText[512];
	split(szData, szAction, charsmax(szAction), szText, charsmax(szText), "|");
	
	// Dodajemy szczegoly zapytania
	log_to_file(DEBUG, "Wyslano zapytanie HTTP z akcja: %s, tresc: %s", szAction, szText);
	
	if( is_user_connected(id) ) client_print_color(id, Red, "^4[%s] ^1Przekroczono limit czasu polaczenia z serwerem.", PREFIX);
	#if defined LOG_FILE
	log_to_file(LOG_FILE, "Przekroczono limit czasu polaczenia z serwerem.");
	#endif
	closeSocket(id);
	
	if( equal(szAction, "validate_license") ) {
		log_to_file(LOG_FILE, "Nie udalo sie przeprowadzic walidacji licencji o numerze identyfikacyjnym: %s", license);
		shop_registered = false;
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: closeSocket");
	#endif
}

public closeSocket(socketID) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: closeSocket");
	#endif
	
	socket_close(sockets[socketID]);
	sockets[socketID] = 0;
	remove_task(TASK_CHECK_SOCKET+socketID);
	remove_task(TASK_TIME_OUT+socketID);
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: closeSocket");
	#endif
}
// ######### Koniec Socketow #########

_getServicePluginByID( id[] ) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _getServicePluginByID");
	#endif
	
	new temp[MAX_NAME+1];
	for(new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, temp, charsmax(temp));
		if( equali(id, temp) ) {
			#if defined TRACE_FILE
			log_to_file(TRACE_FILE, "end1: _getServicePluginByID");
			#endif
			return ArrayGetCell(service_plugins, i);
		}
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: _getServicePluginByID");
	#endif
	return -1;
}

/*_getServiceByID( id[] ) {
	new service[e_Service];
	for(new i = 0; i < ArraySize(services); ++i) {
		ArrayGetArray(services, i, service);
		if( equal(id, service[sID] ) ) {
			return i;
		}
	}
	return -1;
}*/

_getNumberByTariff( tariff, number[], len ) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: _getNumberByTariff");
	#endif
	
	new sms[e_SMS];
	for(new i = 0; i < ArraySize(smses); ++i) {
		ArrayGetArray(smses, i, sms);
		if( tariff == sms[sTARIFF] ) {
			copy(number, len, sms[NUMBER]);
			#if defined TRACE_FILE
			log_to_file(TRACE_FILE, "end1: _getNumberByTariff");
			#endif
			return;
		}
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: _getNumberByTariff");
	#endif
}

/* Stocki */
stock usunPusteLinie(sciezka[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: usunPusteLinie");
	#endif
	
	if( !file_exists(sciezka) ) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: usunPusteLinie");
		#endif
		return;
	}
		
	new zastepcza[64], licznik = 0
	do {
		formatex(zastepcza, charsmax(zastepcza), "%d", licznik);
		++licznik;
	} while( file_exists(zastepcza) )
	
	new szLine[128], iLen;
	for(new i=0; read_file(sciezka, i, szLine, charsmax(szLine), iLen); i++) {
		trim(szLine);
		// pusta linia
		if (!strlen(szLine))
			continue;
		
		write_file(zastepcza, szLine, -1);
	}
	
	if(file_size(zastepcza)>1) {
		//Usuwa stary plik
		unlink(sciezka);
		//Zmienia nazwe tymczasowego pliku na stary plik
		rename_file(zastepcza, sciezka, 1);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end2: usunPusteLinie");
	#endif
}

stock escape(string[], string_len=64) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: escape");
	#endif
	
	replace_all(string, string_len, "'", "\'");
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: escape");
	#endif
	return 1;
}

stock get_sms_cost(szNumber[]) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: get_sms_cost");
	#endif
	
	if(strlen(szNumber) < 4) {
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end1: get_sms_cost");
		#endif
		return 0;
	}
	else if(szNumber[0] == '7') {
		new temp[4];
		formatex(temp, charsmax(temp), "%c", szNumber[1]);
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end2: get_sms_cost");
		#endif
		return szNumber[1] == '0' ? 50 : str_to_num(temp)*100;
	}
	else if(szNumber[0] == '9') {
		new temp[4];
		formatex(temp, charsmax(temp), "%c%c", szNumber[1], szNumber[2]);
		#if defined TRACE_FILE
		log_to_file(TRACE_FILE, "end3: get_sms_cost");
		#endif
		return str_to_num(temp)*100;
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end4: get_sms_cost");
	#endif
	return 0;
}

stock two_number_value(value) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: two_number_value");
	#endif
	
	new temp[17];
	if( value < 10 )
		formatex(temp, charsmax(temp), "0%d", value);
	else
		formatex(temp, charsmax(temp), "%d", value);
		
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: two_number_value");
	#endif
		
	return temp;
}

stock groupDigits(a, output[], len) {
	setc(output, len, 0);
	new number[32];
	num_to_str(a, number, charsmax(number));
	
	for(new i = 0; i < strlen(number); ++i) {
		if(i && i % 3 == 0)
			format(output, len, " %s", output);
		
		format(output, len, "%c%s", number[strlen(number) - 1 - i], output);
	}
}

stock getXMLValue(szText[], tag[], output[], len) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: getXMLValue");
	#endif
	
	new temp[64], textStart, textEnd;
	
	formatex(temp, charsmax(temp), "<%s>", tag);
	textStart = contain(szText, temp);
	
	formatex(temp, charsmax(temp), "</%s>", tag);
	textEnd = contain(szText, temp);
	
	if ( textStart >= 0 )
	{
		new tag_len = 2 + strlen(tag);
		copy(output, min(len, textEnd - textStart - tag_len), szText[textStart + tag_len]);
	}
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: getXMLValue");
	#endif
}

stock StringURLEncode( const szInput[ ], szOutput[ ], const iLen ) {
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "start: StringURLEncode");
	#endif
	
	static const HEXCHARS[ 16 ] = {
		0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 
		0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66
	};
	
	new iPos, cChar, iFLen;
	while( ( cChar = szInput[ iPos ] ) && iFLen < iLen )
	{
		if( cChar == 0x20 ) {
			szOutput[ iFLen++ ] = 0x2B;
		}
		else if( !( 0x41 <= cChar <= 0x5A )
		&& !( 0x61 <= cChar <= 0x7A )
		&& !( 0x30 <= cChar <= 0x39 )
		&& cChar != 0x2D
		&& cChar != 0x2E
		&& cChar != 0x5F )
		{
			if( ( iFLen + 3 ) > iLen ) {
				break;
			}
			else if( cChar > 0xFF || cChar < 0x00 ) {
				cChar = 0x2A;
			}
            
			szOutput[ iFLen++ ] = 0x25;
			szOutput[ iFLen++ ] = HEXCHARS[ cChar >> 4 ];
			szOutput[ iFLen++ ] = HEXCHARS[ cChar & 15 ];
		}
		else {
			szOutput[ iFLen++ ] = cChar;
		}
	
		iPos++;
	}
	
	szOutput[ iFLen ] = 0;
	
	#if defined TRACE_FILE
	log_to_file(TRACE_FILE, "end1: StringURLEncode");
	#endif
	
	return iFLen;
}

stock bool:json_decode(const string[], const key[], output[], output_len) {
	new pos = 0;
	new len = strlen(string);
	new key_start, key_len;
	new temp_key[ 512 ];
	new value_start, value_len;
	new escaped = false;
	
	while( pos < len ) {

		while( string[pos] != '"' ) pos++;
	
		// Pozyskujemy nazwe klucza
		key_start = pos + 1;
		escaped = false;
		while( ++pos < len ) {
			if( pos == len )
				return false;
	
			if( escaped )
				escaped = false;
			else if( string[ pos ] == '\' )
				escaped = true;
			else if( string [ pos ] == '"' )
				break;
		}
		if( pos == len ) return false;
		
		if( !(key_len = pos - key_start) )
			continue;
		
		copy(temp_key, min(charsmax(temp_key), key_len), string[key_start]);
	
		pos++; // Przechodzimy o jeden dalej, bo zatrzymalismy sie na znaku '"'
		while( pos < len && isspace( string[pos] ) ) ++pos;
		if( pos == len ) return false;
	
		if( string[ pos ] != ':' )
			continue;
			
		pos++; // Przechodzimy o jeden dalej, bo zatrzymalismy sie na znaku ':'
			
		while( pos < len && isspace( string[pos] ) ) ++pos;
		if( pos == len ) return false;
		
		value_start = pos;
		
		pos--; // Wracamy o jeden, bo pozniej mamy pre inkrementacje
		while( ++pos < len ) {
			if( escaped )
				escaped = false;
			else if( string[ pos ] == '\' )
				escaped = true;
			else if( string [ pos ] == ',' || string [ pos ] == '}' )
				break;
		}
		if( pos == len ) return false;
		
		if( !(value_len = pos - value_start) )
			continue;
			
		// Jezeli klucz jest inny niz ten w argumencie funkcji, to nie kopiuj jego value
		if( !equal(temp_key, key) )
			continue;
		
		copy(output, min(output_len, value_len), string[value_start]);
		trim(output);
		remove_quotes(output);
		
		return true;
	}
	
	return false;
}
