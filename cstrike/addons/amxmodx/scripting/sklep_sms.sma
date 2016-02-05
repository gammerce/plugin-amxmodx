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
#define LOG_SQL
#define CFG_FILE "sklep_sms.cfg"
new const DEBUG_FILE[] = "sklep_sms_debug.log";
new const LOG_FILE[] = "sklep_sms.log";

const MAX_KOMENDA = 32;
const MAX_KONTAKT = 64;

enum e_KeyValue {
	kvKEY[128],
	kvVALUE[128]
};

// Rejestracja uslug
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

new Array:service_plugins, 
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

// Lista cen (taryf) dla usług
enum e_Price {
	pSERVICE[MAX_ID+1], 
	pTARIFF, 
	AMOUNT, 
};
new Array:pricelist;

//Dodatkowe zmienne
new which_service[33], 
	which_price[33], 
	b_passwords[33][MAX_PASSWORD+1], 
	b_types[33];

//CVARy
new cvar_on, cvar_show_info, cvar_sklep, cvar_przeladuj, cvar_uslugi, cvar_host, cvar_user, cvar_pass, cvar_db, cvar_server_ip, cvar_silent_command;
new cvar_debug;
new sklep_komenda[MAX_KOMENDA+1], przeladuj_komenda[MAX_KOMENDA+1], uslugi_komenda[MAX_KOMENDA+1], show_info;

// Sciezka do pliku konfiguracyjnego
new config_path[128];

//Licencja
new license[32], license_password[33];
new bool:g_footer = true;
new g_serverIp[32];
new g_serverName[128];
new bool:g_blocked = false;

// MySQL
new const TABLE_PREFIX[] = "ss_";
new Handle:SqlTuple;
new bool:g_sqlConnected = false;
new sql_host[64], sql_user[32], sql_pass[32], sql_db[32];
new g_serverId;
new const all_flags[] = "abcdefghijklmnopqrstuyvwxz";
new g_szTemp[4096];

// Flagi graczy
enum e_PlayerFlags {
	pfPLAYER[33], 
	pfFLAGS, 
	pfPASSWORD[MAX_PASSWORD+2], 
	pfTYPE
};
new Array:players_flags;
new bool:g_playersLoaded = false;
new g_lastReload;

// Sockets
#define SOCKET_OK -1
#define SOCKET_TIMEOUT -2

const MAX_SOCKETS = 40;
new g_sockets[MAX_SOCKETS];
new g_socketCounter = 0;

// Settings
new st_currency[16],
	st_signature[128], 
	st_sms_service[65], 
	st_contact[MAX_KONTAKT+1], 
	st_random_key[33], 
	st_random_key_md5[34], 
	Float:st_vat;
	
new g_shopPageUrl[256];
new g_shopPagePort = 80;

new bool:g_shopRegistered = false;
new bool:g_AmxbansExists = false;

public plugin_natives()
{
	register_library("shop_sms");
	register_native("ss_register_service", "registerService");
	register_native("ss_show_service_purchase", "native_showServicePurchase");
	register_native("ss_show_sms_info", "native_infoSMS");
	register_native("ss_add_code", "native_addCode");
	register_native("ss_log", "dodajLog");
	register_native("ss_is_steam", "native_is_steam");
}

public plugin_precache()
{
	get_configsdir(config_path, charsmax(config_path));
	
	// Tworzenie pliku sklep_sms.cfg
	format(config_path, charsmax(config_path), "%s/%s", config_path, CFG_FILE);
	if (!file_exists(config_path)) {
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
		iLen += formatex(szText[iLen], iMax-iLen, "// Czy po uzyciu powyzszych komend wyswietla sie one w chacie^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_ciche_komendy ^"0^"^n");
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
	cvar_silent_command	= register_cvar("sklepsms_ciche_komendy", "0");
	cvar_debug = register_cvar("sklepsms_debug", "0");
	
	// Wczytywanie confingu
	if (file_exists(config_path)) {
		server_cmd("exec %s", config_path);
	}
	
	service_plugins = ArrayCreate();
	service_ids = ArrayCreate(MAX_NAME);
	
	players_flags = ArrayCreate(e_PlayerFlags);
	smses = ArrayCreate(e_SMS);
	services = ArrayCreate(e_Service);
	pricelist = ArrayCreate(e_Price);
}

public plugin_init()
{	
	register_plugin("Sklep SMS", VERSION, "SeeK");
	
	register_menucmd(register_menuid("SMS_Info"), KEYS, "infoSMS_handler");
	register_concmd("Podaj_Kod_Zwrotny", "kodZwrotny");
	register_concmd("ssnick_Podaj_Haslo", "menuServiceType_nick");
	register_concmd("ssip_Podaj_Haslo", "menuServiceType_ip");
	register_concmd("sklepsms_reloaddata", "usersReloadData");
	register_concmd("sklepsms_reloadusers", "pre_usersReload");
	
	register_clcmd("say", "sayHook");
	register_clcmd("say_team", "sayHook");
	
	if (show_info) {
		set_task(137.0, "reklama", _, _, _, "b");
	}
}

public loadCvars()
{
	//Pobieranie wartosci cvarow
	get_pcvar_string(cvar_sklep, sklep_komenda, charsmax(sklep_komenda));
	get_pcvar_string(cvar_przeladuj, przeladuj_komenda, charsmax(przeladuj_komenda));
	get_pcvar_string(cvar_uslugi, uslugi_komenda, charsmax(uslugi_komenda));
	show_info = get_pcvar_num(cvar_show_info);
	
	get_pcvar_string(cvar_host, sql_host, charsmax(sql_host));
	get_pcvar_string(cvar_user, sql_user, charsmax(sql_user));
	get_pcvar_string(cvar_pass, sql_pass, charsmax(sql_pass));
	get_pcvar_string(cvar_db, sql_db, charsmax(sql_db));
}

public plugin_end()
{	
	if (SqlTuple) {
		SqlTuple = Empty_Handle;
	}
}

public plugin_cfg() {	
	// Blad przy tworzeniu (brak uprawnien)
	if (!file_exists(config_path)) {
		brakSciezki(0, config_path);
	}
		
	// Ponowne wczytywanie confingu
	if (file_exists(config_path)) {
		server_cmd("exec %s", config_path);
		server_exec();
	}
	
	// Pobieranie ip serwera
	get_pcvar_string(cvar_server_ip, g_serverIp, charsmax(g_serverIp));
	if (!strlen(g_serverIp)) { // Brak ip w cvarach
		get_user_ip(0, g_serverIp, charsmax(g_serverIp));
	}
	
	// Ladownaie cvarow
	loadCvars();
	
	// Łaczenie z baza
	SqlTuple = SQL_MakeDbTuple(sql_host, sql_user, sql_pass, sql_db);
	if (! SqlTuple) {
		_error51();
	}
	
	// Zaladuj flagi
	_usersLoad(false);
	
	if (SqlTuple) {
		new ip[22], port[10];
		split(g_serverIp, ip, charsmax(ip), port, charsmax(port), ":");
	
		formatex(g_szTemp, charsmax(g_szTemp),
			"SELECT s.id, s.name, s.sms_service, CONCAT(' ', GROUP_CONCAT( ss.service_id SEPARATOR ' ' ), ' ') AS `services` \
			FROM `%sservers` AS s \
			LEFT JOIN `%sservers_services` AS ss ON ss.server_id = s.id \
			WHERE s.ip = '%s' AND s.port = '%s' \
			GROUP BY s.id",
			TABLE_PREFIX, TABLE_PREFIX, ip, port
		);
	
		SQL_ThreadQuery(SqlTuple, "getServerData", g_szTemp);
	}
}

public checkLoadedServices()
{	
	if (!ArraySize(services)) {
		log_amx("Nie zaladowano zadnych uslug.");
	} else {
		log_amx("Zaladowano %d uslug.", ArraySize(services));
	}
}

public client_authorized(id)
{	
	_usersCheckUser(id);
}

public client_putinserver(id)
{	
	_usersCheckUser(id);
}

public sayHook(id)
{	
	new tekst[32];
	read_argv(1, tekst, charsmax(tekst));
	
	if (equali(tekst, sklep_komenda)) {
		sklepMenu(id);
	}
	else if (equali(tekst, przeladuj_komenda)) {
		pre_usersReload(id);
	}
	else if (equali(tekst, uslugi_komenda)) {
		_showPlayerServices(id);
	}
	
	return get_pcvar_num(cvar_silent_command) ? PLUGIN_HANDLED : PLUGIN_CONTINUE;
}

/* Menu sklepu */
public sklepMenu(id)
{
	if (!is_user_connected(id)) {
		return;
	}
	
	if (!get_pcvar_num(cvar_on)) {
		client_print_color(id, Red, "^4[%s] ^1Sklep jest obecnie ^3wylaczony^1.", PREFIX);
		return;
	}
	
	if (g_blocked) {
		client_print_color(id, Red, "^4[%s] ^1Nie mozna otworzyc sklepu z powodu bledow ze sklepem. Zobacz logi.", PREFIX);
	}
	
	if (!g_sqlConnected) {
		client_print_color(id, Red, "^4[%s] ^1Nie polaczono z baza danych.", PREFIX);
		return;
	}
	
	if (!ArraySize(services)) {
		client_print_color(id, Red, "^4[%s] ^1Brak dostepnych uslug do kupienia.", PREFIX);
		return;
	}
	if (!g_shopRegistered) {
		client_print_color(id, Red, "^4[%s] ^1Nie udalo sie przeprowadzic walidacji licencji lub wystapil blad w zapytaniu do bazy danych.", PREFIX);
		return;
	}
	
	new menu;
	if (g_footer) {
		menu = menu_create("\rSklep SMS\d napedzany przez\w sklep-sms.pl^n\yWybierz usluge:", "sklepMenu_handler");
	} else {
		menu = menu_create("\rSklep SMS^n\yWybierz usluge:", "sklepMenu_handler");
	}
		
	new menu_callback = menu_makecallback("sklepMenu_callback");
	
	new szText[64], service[e_Service];
	for (new i = 0; i < ArraySize(services); ++i) {
		new data[4];
		data[0] = i+1;
		// Pobierz dane o usludze
		ArrayGetArray(services, i, service);
		
		// Usluga wymaga posiadania grupy, TODO zakodzic to
		// if (strlen(service[GROUPS])) {
		//	 continue;
		// }
		
		// Sforamtuj punkt w menu
		if (service[DESCRIPTION]) {
			formatex(szText, charsmax(szText), "Kup %s \d(%s)", service[sNAME], service[DESCRIPTION]);
		}
		else {
			formatex(szText, charsmax(szText), "Kup %s", service[sNAME]);
		}
		
		new ret;
		new forward_handle = CreateOneForward(service[PLUGIN], "ss_service_addingtolist", FP_CELL);
		ExecuteForward(forward_handle, ret, id);
		DestroyForward(forward_handle);
		
		data[1] = ret;
		
		if (data[1] != ITEM_OFF) {
			menu_additem(menu, szText, data, 0, menu_callback);
		}
	}
	
	// Wyjdz zamiast Exit
	menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
	menu_display(id, menu);
	
	client_print_color(id, Red, "^4[%s] ^1W razie problemow mozesz sie z nami skontaktowac", PREFIX);
	client_print_color(id, Red, "^4[%s] ^1poprzez: ^3%s", PREFIX, st_contact);
}

public sklepMenu_callback(id, menu, item)
{	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	return data[1] == ITEM_DISABLED ? ITEM_DISABLED : ITEM_ENABLED;
}

public sklepMenu_handler(id, menu, item)
{
	if (!is_user_connected(id) || item == MENU_EXIT) {
		menu_destroy(menu);
		return;
	}
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	wyborMenu(id, data[0]-1);
	menu_destroy(menu);
}
/* Konie menu sklepu */

/* Menu wyboru */
public wyborMenu(id, service_id)
{	
	if (!is_user_connected(id)) {
		return;
	}
		
	new service[e_Service];
	ArrayGetArray(services, service_id, service);
		
	new szText[64], data[3];
	
	formatex(szText, charsmax(szText), "\rSklep SMS^n\yWybierz ilosc %s:", service[sNAME]);
	
	new menu = menu_create(szText, "wyborMenu_handler");
	
	new price[e_Price], number[MAX_NUMBER+1];
	for (new i = 0; i < ArraySize(pricelist); ++i) {
		ArrayGetArray(pricelist, i, price);
		// ID usługi jest inne
		if (!equali(price[pSERVICE], service[sID])) {
			continue;
		}
		
		// Pobranie numeru na ktory trzeba wyslac SMSa
		setc(number, strlen(number), 0);
		_getNumberByTariff(price[pTARIFF], number, charsmax(number));
		
		// Przy danej metodzie płatności nie można użyć danej taryfy
		if (!strlen(number)) {
			continue;
		}
		
		new amount[32+1];
		if (price[AMOUNT] == -1) { // Jezeli -1 to usluga jest na zawsze
			formatex(amount, charsmax(amount), "Na zawsze");
		} else {
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
	
	if (menu_items(menu) > 1) {
		menu_display(id, menu);
	} else if (menu_items(menu) == 1) { // Jezeli jest tylko jeden item, przejdz od razu do informacji o smsie
		which_service[id] = service_id;
		which_price[id] = data[1]+data[2];
		prev_infoSMS(id);
	} else { // Zero
		client_print_color(id, Red, "^4[%s] ^1Brak cennika dla tej uslugi.", PREFIX);
	}
}

public wyborMenu_handler(id, menu, item)
{	
	if (!is_user_connected(id) || item == MENU_EXIT) {
		menu_destroy(menu);
		return;
	}
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	which_service[id] = data[0]-1;
	which_price[id] = data[1]+data[2];
	
	prev_infoSMS(id);
	menu_destroy(menu);
}
/* Koniec menu wyboru */

/* Informacje dot SMSa */
public prev_infoSMS(id)
{
	
	new service[e_Service];
	ArrayGetArray(services, which_service[id], service);
	
	if (service[TYPES] & (TYPE_NICK|TYPE_IP|TYPE_SID)) {	
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
	else {
		_serviceChosen(id);
	}
}

public menuServiceType_callback(id, menu, item)
{	
	new service[e_Service];
	ArrayGetArray(services, which_service[id], service);

	switch (item) {
		case 0: return service[TYPES]&TYPE_NICK ? ITEM_ENABLED : ITEM_DISABLED;
		case 1: return service[TYPES]&TYPE_IP ? ITEM_ENABLED : ITEM_DISABLED;
		case 2: return service[TYPES]&TYPE_SID && is_steam(id) ? ITEM_ENABLED : ITEM_DISABLED;
	}
	
	return ITEM_DISABLED;
}

public menuDisplayServiceTypes(data[])
{	
	new id = data[0];
	if (!is_user_connected(id)) {
		menu_destroy(data[1]);
		return;
	}
	
	new menu, newmenu;
	player_menu_info(id, menu, newmenu);
	if (newmenu != data[1])
		menu_display(id, data[1]);
			
	set_task(0.1, "menuDisplayServiceTypes", TASK_SHOW_MENU_SERVICE_TYPES+id, data, 2);
}

public menuServiceType_handler(id, menu, item)
{	
	switch (item) {
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
	
	if (0 <= item <= 2) {
		remove_task(TASK_SHOW_MENU_SERVICE_TYPES+id);
		menu_destroy(menu);
	}
}

public menuServiceType_nick(id)
{	
	new szPassword[65];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (!_menuServiceType_checkPass(id, TYPE_NICK, szPassword)) {
		client_cmd(id, "messagemode ssnick_Podaj_Haslo");
	}
}

public menuServiceType_ip(id)
{
	new szPassword[65];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (! _menuServiceType_checkPass(id, TYPE_IP, szPassword)) {
		client_cmd(id, "messagemode ssip_Podaj_Haslo");
	}
}

bool:_menuServiceType_checkPass(id, type, szPassword[])
{
	if (strlen(szPassword) > 30) {
		client_print(id, print_center, "Podane haslo jest za dlugie. Maksymalna ilosc znakow wynosi 30.");
		return false;
	}
	else if (!strlen(szPassword)) {
		client_print(id, print_center, "Haslo nie zostalo wprowadzone. Wprowadz je.");
		return false;
	}
	
	_serviceChosen(id, type, szPassword);
	return true;
}

public checkServicePassword(FailState, Handle:Query, Error[], Errorcode, data[], data_size)
{
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	new id = data[0];
	new type = data[1];
	// Haslo takie jak do innych uslug
	if (SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "equal"))) {
		new szPassword[33];
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "password"), szPassword, charsmax(szPassword));
		_serviceChosen(id, type, szPassword);
	}
	else {
		if (type == TYPE_NICK) {
			client_print_color(id, Red, "^4[%s] ^1Istnieje juz usluga wykupiona na ten ^3nick^1, lecz posiada inne haslo. Wprowadz haslo ^3ponownie^1.", PREFIX);
			client_cmd(id, "messagemode ssnick_Podaj_Haslo");
		}
		else if (type == TYPE_IP) {
			client_print_color(id, Blue, "^4[%s] ^1Istnieje juz usluga wykupiona na ten ^3adres IP^1, lecz posiada inne haslo. Wprowadz haslo ^3ponownie^1.", PREFIX);
			client_cmd(id, "messagemode ssip_Podaj_Haslo");
		}
	}
}

_serviceChosen(id, type=0, szPassword[] = "")
{	
	new service[e_Service], price[e_Price];
	ArrayGetArray(services, which_service[id], service);
	ArrayGetArray(pricelist, which_price[id], price);
	copy(b_passwords[id], MAX_PASSWORD, szPassword);
	b_types[id] = type;

	new ret;
	new forward_handle = CreateOneForward(service[PLUGIN], "ss_service_chosen", FP_CELL, FP_CELL);
	ExecuteForward(forward_handle, ret, id, price[AMOUNT]);
	DestroyForward(forward_handle);
	
	if (ret != SS_STOP) {
		infoSMS(id);
	}
}

public infoSMS(id)
{	
	if (!is_user_connected(id)) {
		return;
	}
	
	new service[e_Service], price[e_Price], number[MAX_NUMBER+1];
	ArrayGetArray(services, which_service[id], service);
	ArrayGetArray(pricelist, which_price[id], price);
	_getNumberByTariff(price[pTARIFF], number, charsmax(number));
	
	new amount[32+1];
	if (price[AMOUNT] == -1) { // Jezeli -1 to usluga jest na zawsze
		formatex(amount, charsmax(amount), "Na zawsze");
	} else {
		groupDigits(price[AMOUNT], amount, charsmax(amount));
		format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
	}
	
	formatex(g_szTemp, charsmax(g_szTemp), "\rSklep SMS^n^n");
	format(g_szTemp, charsmax(g_szTemp), "%sWybrales/as opcje zakupu %s ^n\wInfo: \y%s", g_szTemp, service[sNAME], amount);
	new temp_cost = get_sms_cost(number);
	format(g_szTemp, charsmax(g_szTemp), 
		"%s^n^n\rW celu dokonania zakupu, wyslij SMSa^n\wO tresci: \y%s^n\wNa numer: \y%s^n\wKoszt: \y%d.%s %s + VAT\d ( %d.%s %s )", 
		g_szTemp, transaction_service[SMS_TEXT], number, temp_cost/100, two_number_value(temp_cost%100), st_currency, floatround(temp_cost*st_vat)/100, 
		two_number_value(floatround(temp_cost*st_vat)%100), st_currency
	);
	format(g_szTemp, charsmax(g_szTemp), "%s^n^n\wPo wyslaniu SMSa poczekaj na kod zwrotny.^nW celu wprowadzenia go, wcisnij: \y1^n^n\wAby wyjsc, wcisnij: \y0", g_szTemp);
	
	//Wyswietlane caly czas menu zakupu
	infoSMS_wyswietl(g_szTemp, id+TASK_WYSWIETL);
}

public infoSMS_wyswietl(info[], id)
{	
	id -= TASK_WYSWIETL;
	if (!is_user_connected(id)) {
		return;
	}
		
	show_menu(id, KEYS, info, 1, "SMS_Info");
	set_task(0.9, "infoSMS_wyswietl", id+TASK_WYSWIETL, info, strlen(info));
}

public infoSMS_handler(id, key)
{	
	if (task_exists(id+TASK_WYSWIETL)) {
		remove_task(id+TASK_WYSWIETL);
	}
		
	if (!is_user_connected(id)) {
		return;
	}
		
	if (key == 0) {
		client_cmd(id, "messagemode Podaj_Kod_Zwrotny");
	} else if (key == 9) {
		client_print_color(id, Red, "^4[%s] ^1Transakcja zostala ^3przerwana^1.", PREFIX);
	}
}

// Wprowadzanie kodu zwrotnego
public kodZwrotny(id)
{	
	if (!is_user_connected(id)) {
		return;
	}
		
	new sms_code[MAX_CODE+1];
	read_argv(1, sms_code, charsmax(sms_code));
	
	dodajLog2(id, "Wprowadzono kod: %s", sms_code);
	
	if (!strlen(sms_code)) {
		client_print_color(id, Red, "^4[%s] ^1Nie wprowadzono kodu zwrotnego.", PREFIX);
		return;
	}
	
	if (containi(sms_code, " ") != -1) {
		client_print_color(id, Red, "^4[%s] ^1Kod zwrotny ^3nie moze ^1zawierac ^3spacji^1.", PREFIX);
		return;
	}
	
	if (strlen(sms_code) == 1 && containi(sms_code, "0") == 0) {
		client_print_color(id, Red, "^4[%s] ^1Kod zwrotny ^3nie moze ^1byc rowny^3 0^1.", PREFIX);
		return;
	}
	
	client_print_color(id, Red, "^4[%s] ^1Trwa weryfikacja kodu...", PREFIX);
	
	// ############# ZAKUP USLUGI ###############
	
	new service[e_Service], auth_data[32+1], price[e_Price], ip[32];
	new u_service_id[64+1], u_auth_data[64+1], u_password[64+1], u_sms_service[64+1], u_sms_code[MAX_CODE*2+1], u_ip[64+1];
	
	// Pobieramy dane o usludze
	ArrayGetArray(services, which_service[id], service);
		
	// Pobieramy dane gracza Nick / IP / SID
	switch (b_types[id]) {
		case TYPE_IP: get_user_ip(id, auth_data, charsmax(auth_data), 1);
		case TYPE_SID: get_user_authid(id, auth_data, charsmax(auth_data));
		case TYPE_NICK: get_user_name(id, auth_data, charsmax(auth_data));
	}
	
	// Jezeli usluga nie jest wykupowana na nickpass, ippass, sid, to pobieramy nick
	if (!strlen(auth_data)) {
		get_user_name(id, auth_data, charsmax(auth_data));
	}
		
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
	
	formatex(g_szTemp, charsmax(g_szTemp), 
		"%s/servers_stuff.php?action=purchase_service&key=%s&service=%s&type=%d&auth_data=%s&password=%s&method=sms&server=%d&transaction_service=%s&sms_code=%s&tariff=%d&uid=0&ip=%s&platform=engine_amxx&language=polish", 
		g_shopPageUrl, st_random_key_md5, u_service_id, b_types[id], u_auth_data, u_password, g_serverId, u_sms_service, u_sms_code, price[pTARIFF], u_ip
	);
	getWebPage(g_szTemp, g_shopPagePort, "getWebPagePurchaseService");
}

public getWebPagePurchaseService(const data[], const content[], playerId, status, statusCode)
{
	switch (status) {
		case SOCKET_OK: {
			if (statusCode >= 300) {
				client_print_color(playerId, Red, "^4[%s] ^1Zapytanie zwrociło bledny http code.", PREFIX);
				return;
			}
			
			new return_value[33], szText[128], szPositive[3], szBsid[16], szWarnings[1024];
	
			getXMLValue(content, "return_value", return_value, charsmax(return_value));
			getXMLValue(content, "text", szText, charsmax(szText));
			getXMLValue(content, "positive", szPositive, charsmax(szPositive));
			getXMLValue(content, "bsid", szBsid, charsmax(szBsid));
			getXMLValue(content, "warnings", szWarnings, charsmax(szWarnings));
	
			purchaseServicePost(playerId, return_value, szText, str_to_num(szPositive), str_to_num(szBsid), szWarnings);
		}
		
		case SOCKET_TIMEOUT: {
			log_to_file(LOG_FILE, "Zakup nie zostal sfinalizowany z powodu przekroczenia limitu czasu polaczenia.");
			client_print_color(playerId, Red, "^4[%s] ^1Zakup ^3nie zostal sfinalizowany ^1z powodu przekroczenia limitu czasu polaczenia.", PREFIX);
		}
		
		default: {
			log_to_file(LOG_FILE, "Zakup nie zostal sfinalizowany z nieznanych powodow.");
			client_print_color(playerId, Red, "^4[%s] ^1Zakup ^3nie zostal sfinalizowany ^1z nieznanych powodow.", PREFIX);
		}
	}
}

public purchaseServicePost(id, return_value[], szText[], positive, bsid, szWarnings[])
{	
	client_print_color(id, Red, "^4[%s] ^1%s", PREFIX, szText);
	
	if (strlen(szWarnings)) {
		format(g_szTemp, charsmax(g_szTemp), 
			"<html>\
			<head><meta http-equiv=^"Content-Type^" content=^"text/html^" charset=^"UTF-8^"></head>\
			<body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^">\
			<div style=^"text-align: center; font-size: 22px; font-weight: bold;^">Bledy ktore wystapily przy zakupie uslugi</div>\
			%s\
			<i>Uzyj jeszcze raz tego samego kodu zwrotnego sms</i>.</body>\
			</html>", 
			szWarnings
		);
		show_motd(id, g_szTemp, "Bledy przy zakupie uslugi");
	}
	
	// Wystapil jakis blad, wiec przerywamy
	if (! positive) {
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
	if (ret == SS_ERROR) {		
		client_print_color(id, Red, "^4[%s] ^1Wystapil ^3blad ^1podczas kupowania uslugi. Zglos nam to: ^4%s", PREFIX, st_contact);
		
		new amount[32+1];
		if (price[AMOUNT] == -1) { // Jezeli -1 to usluga jest na zawsze
			formatex(amount, charsmax(amount), "Na zawsze");
		}
		else {
			groupDigits(price[AMOUNT], amount, charsmax(amount));
			format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
		}
		
		dodajLog2(id, "Wystapil blad podczas kupowania %s - %s; Taryfa: %d", service[sNAME], amount, price[pTARIFF]);
		
		return;
	}
	
	// Info w przypadku usługi na haslo
	if (b_types[id] & (TYPE_NICK|TYPE_IP)) {
		// Ustawienie hasla
		client_cmd(id, "setinfo _ss ^"%s^"", b_passwords[id]);
		
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>Wykupiles/as usluge: <span style=^"color: red^">%s</span><br /><br />\
			Aby usluga dziala, dodaj wpis do pliku <i>config.cfg</>: <span style=^"color: #3399ff^">setinfo _ss ^"%s^"</span><br /><br />\
			W razie problemow skontaktuj sie z nami.\
			</center></body></html>", 
			service[sNAME], b_passwords[id]
		);
		show_motd(id, g_szTemp, "Informacje dotyczace uslugi");
	}
	else if (b_types[id]&TYPE_SID) {
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>Wykupiles/as usluge: <span style=^"color: red^">%s</span><br /><br />\
			W razie problemow skontaktuj sie z nami.\
			</center></body></html>", 
			service[sNAME]
		);
		show_motd(id, g_szTemp, "Informacje dotyczace uslugi");
	}
	
	new amount[32+1];
	if (price[AMOUNT] == -1) {// Jezeli -1 to usluga jest na zawsze
		formatex(amount, charsmax(amount), "Na zawsze");
	}
	else {
		groupDigits(price[AMOUNT], amount, charsmax(amount));
		format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
	}
	
	client_print_color(id, Blue, "^4[%s] ^1Prawidlowo kupiono ^4%s^1: %s", PREFIX, service[sNAME], amount);
	
	// Jezeli usluga ma flagi do ustawienia to wczytujemy ponownie dane z bazy
	if (service[FLAGS]) {
		// Musimy przeladowac z opoznieniem, aby dane uzytkownika zalapaly nowe haslo
		set_task(2.0, "usersReloadData");
	}
}

/**
 * Dodanie kodu do bazy kodow
 *
 * @param char[]	sms_code
 * @param int		sms_tariff	
 * @param bool		free
 */
addCode(sms_code[], sms_tariff, bool:free=true)
{	
	formatex(g_szTemp, charsmax(g_szTemp),
		"INSERT INTO `%ssms_codes` (`code`, `tariff`, `free`) \
		VALUES ('%s', '%d', '%d')",
		TABLE_PREFIX, sms_code, sms_tariff, free
	);
	
	if (!SqlTuple) {
		return SS_ERROR;
	}
	
	SQL_ThreadQuery(SqlTuple, "IgnoreHandle", g_szTemp);
	dodajLog2(0, "Dodano SMSa do tabeli kodow do wykorzystania. Kod: %s Taryfa: %d", sms_code, sms_tariff);
	return SS_OK;
}

// Wyswietlenie obecnych uslug gracza

_showPlayerServices(id)
{
	if (!is_user_connected(id)) {
		return;
	}
		
	new name[64+1], sid[64+1], ip[32+1];
	get_user_name(id, name, charsmax(name));
	escapeQuotes(name, charsmax(name));
	get_user_ip(id, ip, charsmax(ip), 1);
	escapeQuotes(ip, charsmax(ip));
	get_user_authid(id, sid, charsmax(sid));
	escapeQuotes(sid, charsmax(sid));

	if (SqlTuple) {
		new data[1]; data[0] = id;
		formatex(g_szTemp, charsmax(g_szTemp),
			"SELECT s.name AS `service`, FROM_UNIXTIME(us.expire) AS `expire`, us.expire AS `expire_num` FROM `%suser_service` AS us \
			INNER JOIN `%suser_service_extra_flags` AS usef ON usef.us_id = us.id \
			INNER JOIN `%sservices` AS s ON us.service = s.id \
			WHERE usef.server = '%d' \
			AND ((usef.type = '%d' AND usef.auth_data = '%s') \
			OR (usef.type = '%d' AND usef.auth_data = '%s') \
			OR (usef.type = '%d' AND usef.auth_data = '%s'))",
			TABLE_PREFIX, TABLE_PREFIX, TABLE_PREFIX, g_serverId, TYPE_NICK, name, TYPE_IP, ip, TYPE_SID, sid
		);
	
		SQL_ThreadQuery(SqlTuple, "getPlayerServices", g_szTemp, data, sizeof data);
	}
}

public getPlayerServices(FailState, Handle:Query, Error[], Errorcode, data[], data_size)
{
	new id = data[0];
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		client_print_color(id, Red, "^4[%s] ^1Niestety, nie udalo sie pozyskac informacji o Twoich uslugach.", PREFIX);
		return;
	}

	new menu = menu_create("Twoje obecne uslugi", "showPlayerServices_handler");

	while (SQL_MoreResults(Query)) {
		new service[MAX_ID+1], expire[32+1], item_text[128];
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "service"), service, charsmax(service));
		
		if (SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "expire_num")) == -1) {
			copy(expire, charsmax(expire), "Nigdy");
		} else {
			SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "expire"), expire, charsmax(expire));
		}
		
		formatex(item_text, charsmax(item_text), "%s - wygasa: %s", service, expire);
		menu_additem(menu, item_text);
		
		SQL_NextRow(Query);
	}
	
	if (menu_items(menu)) {
		menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
		menu_display(id, menu);
	}
	else {
		client_print_color(id, Red, "^4[%s] ^1Nie masz jeszcze ^3zadnej uslugi^1. Moze czas to zmienic? ;-) Wpisz: ^3%s.", PREFIX, sklep_komenda);
	}
}

public showPlayerServices_handler(id, menu, item)
{	
	menu_destroy(menu);
}

// Funkcje dotyczace flag graczy 

public pre_usersReload(id)
{	
	if (g_lastReload+10 > get_systime()) {
		client_print_color(id, Red, "^4[%s] ^1Ktos przed chwila przeladowal liste. Odczekaj chwile.", PREFIX);
		return;
	}
	g_lastReload = get_systime();
	_usersReload(id);
}

_usersReload(id)
{
	for (new i = 1; i <= get_maxplayers(); ++i) {
		if (! is_user_connected(i)) {
			continue;
		}
			
		_usersCheckUser(i);
	}
	if (id) {
		client_print_color(id, Red, "^4[%s] ^1Prawidlowo przeladowano liste flag wykupionych w sklepiku.", PREFIX);
	}
}

// Funkcja wczytujaca z bazy ponownie dane graczy
public usersReloadData() {	
	// Wczytywanie danych graczy
	_usersLoad(true);
}

_usersLoad(bool:reload) {
	// Czyscimy dotychczasowe dane
	ArrayClear(players_flags);
	g_playersLoaded = false;
	
	if (SqlTuple) {
		new ip[16], port[8];
		split(g_serverIp, ip, charsmax(ip), port, charsmax(port), ":");
	
		formatex(g_szTemp, charsmax(g_szTemp), 
			"SELECT f.id, f.type, f.auth_data, f.password, f.a, f.b, f.c, f.d, f.e, f.f, f.g, f.h, f.i, f.j, f.k, f.l, f.m, f.n, f.o, f.p, f.q, f.r, f.s, f.t, f.u, f.y, f.v, f.w, f.x, f.z \
			FROM `%splayers_flags` AS f \
			JOIN `%sservers` AS s ON s.id = f.server \
			WHERE s.ip = '%s' \
			AND s.port = '%s' \
			ORDER BY f.auth_data, f.type DESC", 
			TABLE_PREFIX, TABLE_PREFIX, ip, port
		);
	
		new data[1]; data[0] = reload; // Przeladuj liste adminow w amxbans
		SQL_ThreadQuery(SqlTuple, "getPlayersData", g_szTemp, data, sizeof data);
	}
}

public getPlayersData(FailState, Handle:Query, Error[], Errorcode, data[], data_size)
{
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	while (SQL_MoreResults(Query))
	{
		new player_flags[e_PlayerFlags], type;
		type = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "type"));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "auth_data"), player_flags[pfPLAYER], 32);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "password"), player_flags[pfPASSWORD], MAX_PASSWORD);
		
		for (new i = 0; i < strlen(all_flags); ++i) {
			new temp[4];
			formatex(temp, charsmax(temp), "%c", all_flags[i]);
			new expire = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, temp));
			if (expire > get_systime() || expire == -1) {
				player_flags[pfFLAGS] |= read_flags(temp);
			}
		}
		
		switch (type) {
			case TYPE_SID: player_flags[pfTYPE] = FLAG_AUTHID|FLAG_NOPASS;
			case TYPE_IP: player_flags[pfTYPE] = FLAG_IP;
			default: player_flags[pfTYPE] = FLAG_NICK|FLAG_KICK;
		}
		
		// Dodanie do tablicy
		if (player_flags[pfFLAGS] != 0) {
			ArrayPushArray(players_flags, player_flags);
		}
		
		SQL_NextRow(Query);
	}
	
	g_playersLoaded = true;
	
	if (data[0] && g_AmxbansExists) { // Przeladuj dane w amxbans, a tym samym uruchom komende dodawania danych do tablicy globalnej uprawnien
		server_cmd("amx_reloadadmins");
	}
	else {
		// Sprawdzamy uprawnienia graczy
		_usersReload(0);
	}
}

public amxbans_sql_initialized()
{	
	g_AmxbansExists = true;
	addUsersToGlobalArray();
	// Sprawdzamy uprawnienia graczy
	_usersReload(0);
}

// Funkcja sluzaca do dodania graczy do tablicy globalnej przechowujacej dane uprawnien graczy
public addUsersToGlobalArray()
{	
	if (!g_playersLoaded) { // Dane uzytkownikow nie zostaly jeszcze zaladowane
		set_task(0.1, "addUsersToGlobalArray");
		return;
	}
	
	// Potrzebujemy drugiej tablicy, zeby elementy z amxbansa mialy takie samo id
	new Array:users, Array:users2;
	users = ArrayCreate(e_PlayerFlags);
	users2 = ArrayCreate(e_PlayerFlags);
	
	for (new i = 0; i < ArraySize(players_flags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(players_flags, i, player_flags);
		ArrayPushArray(users, player_flags);
	}
	
	for (new i = 0; i < admins_num(); ++i) {
		new player_flags[e_PlayerFlags], name_bak[33];
		
		admins_lookup(i, AdminProp_Auth, player_flags[pfPLAYER], 32);
		copy(name_bak, charsmax(name_bak), player_flags[pfPLAYER]);
		strtolower(name_bak);
		
		admins_lookup(i, AdminProp_Password, player_flags[pfPASSWORD], MAX_PASSWORD);
		
		player_flags[pfTYPE] = admins_lookup(i, AdminProp_Flags);
		player_flags[pfFLAGS] = admins_lookup(i, AdminProp_Access);
		
		new l = 0, p = ArraySize(users)-1, s;
		while (l <= p) {
			new player_flags2[e_PlayerFlags];
			s = (l + p) / 2;
			
			ArrayGetArray(users, s, player_flags2);
			strtolower(player_flags2[pfPLAYER]);
			if (equali(name_bak, player_flags2[pfPLAYER]) && player_flags[pfTYPE] == player_flags2[pfTYPE]) {
				// Zostawiamy haslo AMXBansa
				player_flags[pfFLAGS] |= player_flags2[pfFLAGS];
				ArrayPushArray(users2, player_flags);
				ArrayDeleteItem(users, s);
				break;
			}
			else if (strcmp(name_bak, player_flags2[pfPLAYER]) > 0) {
				l = s + 1;
			}
			else if (equali(name_bak, player_flags2[pfPLAYER]) && _getOrderOfType(player_flags[pfTYPE]) > _getOrderOfType(player_flags2[pfTYPE])) {
				l = s + 1;
			}
			else {
				p = s - 1;
			}
		}
		
		if (p < l) {
			ArrayPushArray(users2, player_flags);
		}
	}
	admins_flush();
	
	for (new i = 0; i < ArraySize(users2); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(users2, i, player_flags);
		admins_push(player_flags[pfPLAYER], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
	for (new i = 0; i < ArraySize(users); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(users, i, player_flags);
		admins_push(player_flags[pfPLAYER], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
}

_getOrderOfType(type)
{	
	switch (type) {
		case FLAG_IP: return 1;
		case FLAG_NICK : return 2;
		case FLAG_AUTHID: return 3;
	}
	
	return 0;
}

public usersCheckUser_task(id)
{
	_usersCheckUser(id-TASK_CHECK_USER);
}

public _usersCheckUser(id)
{	
	if (! g_playersLoaded) {
		if (! task_exists(TASK_CHECK_USER+id)) {
			set_task(0.1, "usersCheckUser_task", TASK_CHECK_USER+id);
		}
			
		return;
	}
	
	for (new i = 0; i < ArraySize(players_flags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(players_flags, i, player_flags);
		
		if (player_flags[pfTYPE]&FLAG_NICK) {
			new name[32];
			get_user_name(id, name, charsmax(name));
			if (! equali(name, player_flags[pfPLAYER])) {
				continue;
			}
		}
		else if (player_flags[pfTYPE]&FLAG_IP) {
			new ip[32];
			get_user_ip(id, ip, charsmax(ip), 1);
			if (! equali(ip, player_flags[pfPLAYER])) {
				continue;
			}
		}
		else if (player_flags[pfTYPE]&FLAG_AUTHID) {			
			new sid[32], arr_sid[32];
			copy(arr_sid, charsmax(arr_sid), player_flags[pfPLAYER]);
			get_user_authid(id, sid, charsmax(sid));
			
			strtolower(arr_sid);
			strtolower(sid);
			replace(sid, charsmax(sid), "steam_", "");
			replace(arr_sid, charsmax(arr_sid), "steam_", "");
			
			if (! equali(sid, arr_sid)) {
				continue;
			}
		}
		
		if (strlen(player_flags[pfPASSWORD])) {
			new password[33], password_md5[34];
			
			get_user_info(id, "_pw", password, charsmax(password));
			md5(password, password_md5);
			
			if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
				get_user_info(id, "_pw2", password, charsmax(password));
				md5(password, password_md5);
				if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
					get_user_info(id, "_pw3", password, charsmax(password));
					md5(password, password_md5);
					if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
						get_user_info(id, "_ss", password, charsmax(password));
						md5(password, password_md5);
						if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
							if (! (player_flags[pfTYPE]&FLAG_KICK)) { // Nie kickuj gracza, tylko mu nie przydziel flag
								continue;
							}
						
							server_cmd("kick #%d ^"Nieprawidlowe haslo^"", get_user_userid(id));
							
							return;
						}
					}
				}
			}
		}
		
		set_user_flags(id, player_flags[pfFLAGS]);
	}
}

public brakSciezki(id, path[])
{	
	dodajLog2(0, "Nie mozna utworzyc pliku/folderu: %s. Prawdopodonbnie brak uprawnien do zapisu. Utworz plik recznie.", path);
	log_to_file(LOG_FILE, "Nie mozna utworzyc pliku/folderu: %s. Prawdopodonbnie brak uprawnien do zapisu. Utworz plik recznie.", path);
	
	if (id) {
		client_print_color(id, Blue, "^4[%s] ^1Wystapil ^3blad ^1przy zapisywaniu ustawien. Prawdopodobnie ^4brak uprawnien^1.", PREFIX);
	}
}

public reklama()
{	
	if (get_playersnum()>1) {
		client_print_color(0, Red, "^4[%s] ^1Zapraszamy wszystkich do korzystania ze ^3sklepiku! ^1Wystarczy wpisac: ^4%s", PREFIX, sklep_komenda);
	}
}

public dodajLog2(id, const szFormat[], any:...)
{	
	#if defined LOG_SQL
	new g_szTemp[256], name[33], ip[22], sid[22];
	vformat(g_szTemp, charsmax(g_szTemp), szFormat, 3);
	get_user_name(id, name, charsmax(name));
	get_user_ip(id, ip, charsmax(ip), 1);
	get_user_authid(id, sid, charsmax(sid));
	
	if (id) {
		format(g_szTemp, charsmax(g_szTemp), "%s; %s; %s. %s", name, ip, sid, g_szTemp);
	}
	
	log_to_sql(g_szTemp, charsmax(g_szTemp));
	#endif
}

public log_to_sql(text[], text_len)
{
	if (SqlTuple) {
		format(text, text_len, "%s. Serwer: %d", text, g_serverId);
		escapeQuotes(text, text_len);
		
		// Cannot be formatex, because param text is probably g_szTemp
		format(g_szTemp, charsmax(g_szTemp),
			"INSERT INTO `%slogs` (text) \
			VALUES ('%s')",
			TABLE_PREFIX, text
		);
		SQL_ThreadQuery(SqlTuple, "IgnoreHandle", g_szTemp);
	}
}

public getServerData(FailState, Handle:Query, Error[], Errorcode)
{
	
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		if (FailState == TQUERY_QUERY_FAILED) {
			if (containi(Error, "exist") != -1) {
				_error22();
			}
		}
		
		g_blocked = true;
	}

	if (SQL_NumResults(Query) <= 0) {
		_error21();
	}
	
	// Pobranie id serwera
	g_serverId = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "id"));
	
	// Pobranie uslugi obslugujacej platnosci
	new sms_service[64];
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "sms_service"), sms_service, charsmax(sms_service));
	if (strlen(sms_service)) {
		copy(st_sms_service, charsmax(st_sms_service), sms_service);
	}
		
	// Pozyskanie uslug na serwerze
	new szServices[512];
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "services"), szServices, charsmax(szServices));
	
	if (SqlTuple) {
		// Get shop settings
		formatex(g_szTemp, charsmax(g_szTemp),
			"SELECT * FROM `%ssettings` \
			WHERE `key` IN ('currency', 'shop_url', 'signature', 'sms_service', 'contact', 'vat', 'random_key', 'license_login', 'license_password')",
			TABLE_PREFIX
		);
		SQL_ThreadQuery(SqlTuple, "getSettings", g_szTemp);
	
		// Update server info
		formatex(g_szTemp, charsmax(g_szTemp),
			"UPDATE `%sservers` \
			SET `type` = 'amxx', `version` = '%s' \
			WHERE `id` = '%d'",
			TABLE_PREFIX, VERSION, g_serverId
		);
		SQL_ThreadQuery(SqlTuple, "IgnoreHandle", g_szTemp);
	}
	
	// Sprawdzanie dostepnosci usług
	new service_id[MAX_NAME+1], service_id_space[MAX_NAME+2+1], ids[512], ids_len = 0, ids_max = charsmax(ids);
	for (new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, service_id, charsmax(service_id));
		formatex(service_id_space, charsmax(service_id_space), " %s ", service_id);
		
		if (containi(szServices, service_id_space) != -1) {
			if (ids_len) {
				ids_len += formatex(ids[ids_len], ids_max-ids_len, ",");
			}
				
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
	if (ids_len) {
		if (SqlTuple) {
			formatex(g_szTemp, charsmax(g_szTemp),
				"SELECT * FROM `%sservices` \
				WHERE `id` IN(%s) \
				ORDER BY `order` ASC",
				TABLE_PREFIX, ids
			);
		
			SQL_ThreadQuery(SqlTuple, "getServicesData", g_szTemp);
		}
	} else {
		checkLoadedServices(); // Sprawdz zaladowane uslugi
	}
}

public getServicesData(FailState, Handle:Query, Error[], Errorcode) {
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	new service[e_Service];
	new ids[512], ids_len = 0, ids_max = charsmax(ids);
	while (SQL_MoreResults(Query))
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
		if (ids_len) {
			ids_len += formatex(ids[ids_len], ids_max-ids_len, ",", g_szTemp);
		}
		
		ids_len += formatex(ids[ids_len], ids_max-ids_len, "'%s'", service[sID]);
		
		SQL_NextRow(Query);
	}
	
	// Sprawdz zaladowane uslugi
	checkLoadedServices();
	
	// Jest chociaz jedna usluga
	if (ids_len) {
		if (SqlTuple) {
			formatex(g_szTemp, charsmax(g_szTemp), 
				"SELECT * FROM `%spricelist` \
				WHERE (`server`='%d' OR `server`='-1') AND `service` IN (%s) \
				ORDER BY `amount` ASC", 
				TABLE_PREFIX, g_serverId, ids
			);
			SQL_ThreadQuery(SqlTuple, "getPriceList", g_szTemp);
		}
	}
}

public getPriceList(FailState, Handle:Query, Error[], Errorcode)
{		
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	while (SQL_MoreResults(Query))
	{
		new price[e_Price];
		
		price[pTARIFF] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "tariff"));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "service"), price[pSERVICE], MAX_ID);
		price[AMOUNT] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "amount"));
		
		ArrayPushArray(pricelist, price);
		
		SQL_NextRow(Query);
	}
}

public getSettings(FailState, Handle:Query, Error[], Errorcode)
{	
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	while (SQL_MoreResults(Query)) {
		new key[128], value[256];
		
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "key"), key, charsmax(key));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "value"), value, charsmax(value));
		
		if (equali(key, "currency")) {
			copy(st_currency, charsmax(st_currency), value);
		}
		else if (equali(key, "shop_url")) {
			copy(g_shopPageUrl, charsmax(g_shopPageUrl), value);
			
			// TODO: implement https
			if (replace(g_shopPageUrl, charsmax(g_shopPageUrl), "https://", "")) {
				g_shopPagePort = 80;
			} else if (replace(g_shopPageUrl, charsmax(g_shopPageUrl), "http://", "")) {
				g_shopPagePort = 80;
			}
			
			// Remove trailing slash
			if (g_shopPageUrl[strlen(g_shopPageUrl) - 1] == '/') {
				g_shopPageUrl[strlen(g_shopPageUrl) - 1] = 0;
			}
			
			if (! strlen(g_shopPageUrl)) {
				_error33();
			}
		}
		else if (equali(key, "signature")) {
			copy(st_signature, charsmax(st_signature), value);
		}
		else if (equali(key, "sms_service") && !strlen(st_sms_service)) {
			copy(st_sms_service, charsmax(st_sms_service), value);
		}
		else if (equali(key, "contact")) {
			copy(st_contact, charsmax(st_contact), value);
		}
		else if (equali(key, "vat")) {
			st_vat = str_to_float(value);
		}
		else if (equali(key, "random_key")) {
			copy(st_random_key, charsmax(st_random_key), value);
			md5(st_random_key, st_random_key_md5); // Hashujemy random key
		}
		else if (equali(key, "license_login")) {
			copy(license, charsmax(license), value);
			trim(license);
		}
		else if (equali(key, "license_password")) {
			copy(license_password, charsmax(license_password), value);
		}
		
		SQL_NextRow(Query);
	}
	
	// Sprawdzamy czy licencja jest prawidłowa
	validateLicense();
	
	if (SqlTuple) {
		// Pobranie numerow sms
		escapeQuotes(st_sms_service, charsmax(st_sms_service));
		formatex(g_szTemp, charsmax(g_szTemp),
			"SELECT `number`, `tariff` \
			FROM `%ssms_numbers` \
			WHERE `service` = '%s'",
			TABLE_PREFIX, st_sms_service
		);
		SQL_ThreadQuery(SqlTuple, "getSMSesData", g_szTemp);
	
		// Pobranie danych o serwisie transakcyjnym
		formatex(g_szTemp, charsmax(g_szTemp),
			"SELECT * FROM `%stransaction_services` \
			WHERE `id` = '%s'",
			TABLE_PREFIX, st_sms_service
		);
		SQL_ThreadQuery(SqlTuple, "getTransactionServiceData", g_szTemp);
	}
}

// Funkcja ktora wysyla zapytanie do serwera o sprawdzenie czy licencja jest prawidlowa
public validateLicense()
{	
	// Sprawdzenie licencji
	new serverNameEscaped[128];
	get_cvar_string("hostname", g_serverName, charsmax(g_serverName));
	StringURLEncode(g_serverName, serverNameEscaped, charsmax(serverNameEscaped));
	
	formatex(g_szTemp, charsmax(g_szTemp), 
		"license.sklep-sms.pl/license.php?action=login_server&type=engine_amxx&license_id=%s&license_password=%s&server_ip=%s&version=%s&name=%s", 
		license, license_password, g_serverIp, VERSION, serverNameEscaped
	);
	getWebPage(g_szTemp, _, "getWebPageValidateLicense");
}

public getWebPageValidateLicense(const data[], const content[], playerId, status, statusCode)
{
	switch (status) {
		case SOCKET_OK: {
			if (statusCode >= 300) {
				g_shopRegistered = false;
				log_to_file(LOG_FILE, "Licencja nie zostala zwalidowana z powodu blednego HTTP CODE.");
				return;
			}
		
			new text[33];
		
			getXMLValue(content, "text", text, charsmax(text));
		
			if (equal(text, "updated")) {
				g_shopRegistered = true;
			
				new footer[2];
				getXMLValue(content, "footer", footer, charsmax(footer));
				g_footer = str_to_num(footer) ? true : false;
				
				log_amx("Walidacja licencji o numerze identyfikacyjnym: %s zostala zakonczona pomyslnie", license);
			}
			else if (equal(text, "not_updated")) {
				_error14();
			}
			else if (equal(text, "not_logged_successfully")) {
				_error13();
			}
			else {
				log_to_file(LOG_FILE, "%s", content);
				_error10();
			}
		}
		
		case SOCKET_TIMEOUT: {
			g_shopRegistered = false;
			log_to_file(LOG_FILE, "Licencja nie zostala zwalidowana z powodu przekroczenia limitu czasu polaczenia.");
		}
		
		default: {
			g_shopRegistered = false;
			log_to_file(LOG_FILE, "Licencja nie zostala zwalidowana z nieznanych powodow.");
		}
	}
}

public getTransactionServiceData(FailState, Handle:Query, Error[], Errorcode)
{	
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	if (SQL_NumResults(Query) <= 0) {
		_error31();
	}
	
	if (!SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "sms"))) {
		_error32();
	}
	
	new data[256];
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "id"), transaction_service[tsID], MAX_ID);
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "name"), transaction_service[tsNAME], MAX_NAME);
	SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "data"), data, charsmax(data));
	
	if (! json_decode(data, "sms_text", transaction_service[SMS_TEXT], MAX_SMS_TEXT)) {
		log_to_file(LOG_FILE, "Nie udalo sie pozyskac kodu sms.^nDane: %s", data);
	}
}

public getSMSesData(FailState, Handle:Query, Error[], Errorcode)
{	
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	new sms[e_SMS];
	while (SQL_MoreResults(Query))
	{
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "number"), sms[NUMBER], MAX_NUMBER);
		sms[sTARIFF] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "tariff"));
		ArrayPushArray(smses, sms);
		
		SQL_NextRow(Query);
	}
}

_checkForSQLErrors(Handle:Query, FailState, Error[], Errorcode)
{	
	g_sqlConnected = true;
	
	if (FailState != TQUERY_SUCCESS) {
		if (FailState == TQUERY_QUERY_FAILED) {
			log_to_file(LOG_FILE, "Nie mozna polaczyc sie z baza danych.");
		}
		else if (FailState == TQUERY_CONNECT_FAILED) {
			log_to_file(LOG_FILE, "Zapytanie anulowane.");
			g_sqlConnected = false;
		}
		
		log_to_file(LOG_FILE, "Tresc bledu (%d): %s", Errorcode, Error);
		
		SQL_GetQueryString(Query, g_szTemp, charsmax(g_szTemp));
		log_to_file(LOG_FILE, "Zapytanie: %s", g_szTemp);
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public IgnoreHandle(FailState, Handle:Query, Error[], Errorcode)
{	
	_checkForSQLErrors(Query, FailState, Error, Errorcode);
}

/* #########################################################################################################################
 * ############################################### Zewnetrzne funkcje ######################################################
 * #########################################################################################################################
 */
 
public registerService(plugin, params)
{	
	if (params != 1) {
		log_to_file(LOG_FILE, "Wystapil blad podczas dodawania uslugi. Bledna ilosc argumentow funkcji ss_register_service");
		return SS_BAD_ARGS;
	}
		
	new id[MAX_NAME+1];
	
	get_string(1, id, charsmax(id));
	
	ArrayPushCell(service_plugins, plugin);
	ArrayPushString(service_ids, id);
	
	return SS_OK;
}

// Dodawanie kodu do listy kodow do wykorzystania
public native_addCode(plugin, params)
{	
	if (params != 2) {
		return SS_BAD_ARGS;
	}
	
	new sms_code[MAX_CODE+1], tariff;
	get_string(1, sms_code, charsmax(sms_code));
	tariff = get_param(2);
	
	return addCode(sms_code, tariff);
}

// Logowanie danych z pluginow zewnetrznych
public dodajLog(plugin, params)
{	
	#if defined LOG_SQL
	vdformat(g_szTemp, charsmax(g_szTemp), 1, 2);
	log_to_sql(g_szTemp, charsmax(g_szTemp));
	#endif
}

public native_showServicePurchase(plugin, params)
{
	if (params != 2) {
		return SS_BAD_ARGS;
	}
	
	new service_id[MAX_ID+1];
	new id = get_param(1);
	get_string(2, service_id, charsmax(service_id));
	
	wyborMenu(id, _getServiceByID(service_id));
	return SS_OK;
}

public native_infoSMS(plugin, params)
{	
	if (params != 1) {
		return SS_BAD_ARGS;
	}
	
	infoSMS(get_param(1));
	return SS_OK;
}

public bool:native_is_steam(plugin, params)
{	
	if (params != 1) {
		return false;
	}
	
	return is_steam(get_param(1));
}

bool:is_steam(id)
{	
	new auth[32];
	get_user_authid(id, auth, charsmax(auth));
	if (contain(auth, "STEAM_0:0:") != -1 || contain(auth, "STEAM_0:1:") != -1) {
		return true;
	}
	
	return false;
}

// ######### TYPY BŁĘDÓW ##########
// ## 1 - licencja
// ## 2 - problem z baza
// ## 3 - metody płatnosci
// ## 4 - sklep ogolnie
// ## 5 - probem z serwerem
// ################################

_error10() {
	_make_error("Error 10 - Wystapil blad podczas odczytywania odpowiedzi od serwera walidujacego licencje. Zobacz logi.");
}

_error13() {
	formatex(g_szTemp, charsmax(g_szTemp), "Error 13 - Brak licencji o numerze identyfikacyjnym: %s lub bledne haslo.", license);
	_make_error(g_szTemp);
}

_error14() {
	log_to_file(LOG_FILE, "Error 14 - Nie udalo sie zaktualizowac aktywnosci serwera.");
	g_blocked = true;
}

_error21() {
	_make_error("Error 21 - Serwer nie znajduje sie nie liscie serwerow na stronie WWW.");
}

_error22() {	
	_make_error("Error 22 - Brak tabeli ss_servers w bazie.");
}

_error31() {
	log_to_file(LOG_FILE, "Error 31 - Wybrana metoda platnosci nie istnieje w bazie danych.");
	g_blocked = true;
}

_error32() {
	log_to_file(LOG_FILE, "Error 32 - Wybrana metoda platnosci nie obsluguje platnosci SMS.");
	g_blocked = true;
}

_error33() {
	log_to_file(LOG_FILE, "Error 33 - Nie podano adresu sklepu w ustawieniach.");
	g_blocked = true;
}

_error51() {
	_make_error("Error 51 - Nie udalo sie utworzyc uchwytu do bazy danych.");
}

_make_error(message[]) {
	set_fail_state(message);
}
/* ############# Koniec: Licencja ################## */

/**
 * Get page content
 *
 * @param const char[]	url			path (eg. example.com/shop/ddd)
 * @param int			port			eg. 80
 * @param const char[]	callback		callback function
 * @param const char[]	functionData	callback function data
 * @param int			playerId		id of the player
 * 
 * @return bool
 */
bool:getWebPage(const url[], port = 80, const callback[] = "", const functionData[] = "", playerId = 0)
{
	new host[128], path[256];
	split(url, host, charsmax(host), path, charsmax(path), "/");
	
	new socketId = mySocketOpen(host, port, playerId);
	if (socketId == SS_ERROR) {
		return false;
	}
	
	new httpRequest[512];
	formatex(httpRequest, charsmax(httpRequest),
		"GET /%s HTTP/1.1^r^n\
		Host: %s^r^n^r^n",
		path, host
	);
	socket_send(g_sockets[socketId], httpRequest, strlen(httpRequest));
	
	/*
	 * Utworzenie nowego pseudo watku oczekujacego na odpowiedz
	 */
	new requestData[1024];
	
	if (true) { // pseudo deleting variables
		new callbackEscaped[256], functionDataEscaped[512];
		
		copy(callbackEscaped, charsmax(callbackEscaped), callback);
		copy(functionDataEscaped, charsmax(functionDataEscaped), functionData);
		replace_all(httpRequest, charsmax(httpRequest), "^"", "^^^"");
		replace_all(callbackEscaped, charsmax(callbackEscaped), "^"", "^^^"");
		replace_all(functionDataEscaped, charsmax(functionDataEscaped), "^"", "^^^"");
	
		// "httpRequest" "function" "functionData"
		formatex(requestData, charsmax(requestData), "%d ^"%s^" ^"%s^" ^"%s^"", playerId, httpRequest, callbackEscaped, functionDataEscaped);
	}
	
	set_task(0.6, "mySocketCheckData", TASK_CHECK_SOCKET + socketId, requestData, strlen(requestData));
	set_task(10.0, "mySocketTimeout", TASK_TIME_OUT + socketId, requestData, strlen(requestData));
	
	return true;
}

// -------------------------------------------------------- Sockets ------------------------------------------------------------

/**
 * Open a new socket
 *
 * @param const char[]	host		host name
 * @param int			port
 * @param int			playerId	id of the player
 *
 * @return int id of opened socket
 */
mySocketOpen(const host[], port = 80, playerId = 0)
{
	new socketId = ++g_socketCounter % MAX_SOCKETS;
	if (g_sockets[socketId]) {
		mySocketClose(socketId);
	}
	
	new error;
	g_sockets[socketId] = socket_open(host, port, SOCKET_TCP, error);
	
	if (error) {
		if (is_user_connected(playerId)) {
			client_print_color(playerId, Red, "^4[%s] ^1Nie udalo sie utworzyc socketu.", PREFIX);
		}
		
		log_to_file(LOG_FILE, "Nie mozna polaczyc sie z hostem: %s:%d. Blad: %d.", host, port, error);
		
		return SS_ERROR;
	}
	
	return socketId;
}

public mySocketCheckData(const requestData[], socketId)
{	
	socketId -= TASK_CHECK_SOCKET;
	
	if (! socket_change(g_sockets[socketId])) {
		set_task(0.6, "mySocketCheckData", TASK_CHECK_SOCKET + socketId, requestData, strlen(requestData));
		return;
	}
	
	new receiveDataContent[1024], statusCode, statusMessage[64];
	statusCode = mySocketReceiveData(socketId, receiveDataContent, charsmax(receiveDataContent), statusMessage, charsmax(statusMessage));
	
	// Parse request data
	new httpRequest[512], szPlayerId[4], function[256], functionData[512], playerId;
	parse(requestData, szPlayerId, charsmax(szPlayerId), httpRequest, charsmax(httpRequest), function, charsmax(function), functionData, charsmax(functionData));
	playerId = str_to_num(szPlayerId);
	
	if (!statusCode || statusCode >= 300) {
		log_to_file(LOG_FILE, "Zapytanie zwrocilo blad: %d %s^n%s", statusCode, statusMessage, httpRequest);
	}
	
	mySocketCallCallback(function, functionData, receiveDataContent, playerId, SOCKET_OK, statusCode);
}

/**
 *
 * @return int status code
 */
mySocketReceiveData(socketId, receiveDataContent[], receiveDataContentLen, statusMessage[], statusMessageLen)
{
	new receiveData[1024], receiveDataHeader[128];
	
	socket_recv(g_sockets[socketId], receiveData, charsmax(receiveData));
	mySocketClose(socketId);
	
	// Parse received data
	new headerFirstLine[128], httpInfo[16], status[64], szStatusCode[4];
		
	// Split header from content
	split(receiveData, receiveDataHeader, charsmax(receiveDataHeader), receiveDataContent, receiveDataContentLen, "^r^n^r^n");
		
	// Extract first line of header
	split(receiveDataHeader, headerFirstLine, charsmax(headerFirstLine), receiveDataHeader, charsmax(receiveDataHeader), "^r^n");
		
	// Split first line: httpInfo status
	split(headerFirstLine, httpInfo, charsmax(httpInfo), status, charsmax(status), " ");
		
	// Split status: code message
	split(status, szStatusCode, charsmax(szStatusCode), statusMessage, statusMessageLen, " ");
	
	return str_to_num(szStatusCode);
}

/**
 * Function called on socket connection timeout
 *
 * @param char[]	requestData
 * @param int		socketId	task id
 */
public mySocketTimeout(requestData[], socketId)
{	
	socketId -= TASK_TIME_OUT;
	mySocketClose(socketId);
	
	// Parse request data
	new httpRequest[512], szPlayerId[4], function[256], functionData[512], playerId;
	parse(requestData, szPlayerId, charsmax(szPlayerId), httpRequest, charsmax(httpRequest), function, charsmax(function), functionData, charsmax(functionData));
	playerId = str_to_num(szPlayerId);
	
	log_to_file(LOG_FILE, "Przekroczono limit czasu zapytania HTTP^n%s", httpRequest);
	
	if (is_user_connected(playerId)) {
		client_print_color(playerId, Red, "^4[%s] ^1Przekroczono limit czasu zapytania HTTP.", PREFIX);
	}
	
	mySocketCallCallback(function, functionData, "", playerId, SOCKET_TIMEOUT);
}

mySocketCallCallback(const function[], const functionData[], const receiveDataContent[], playerId, status, statusCode = 0)
{
	if (! strlen(function)) {
		return;
	}

	if (callfunc_begin(function) == 1) {
		callfunc_push_str(functionData); // function data
		callfunc_push_str(receiveDataContent);
		callfunc_push_int(playerId); // player id
		callfunc_push_int(status);
		callfunc_push_int(statusCode);
		callfunc_end();
	} else {
		log_to_file(LOG_FILE, "Funkcja %s nie zostala prawidlowo wywolana.", function);
	}
}

/*Array:mySocketParseHeader(const header[])
{
	new Array:explodedHeader;
	explodedHeader = ArrayCreate(e_KeyValue);

	new headerCopy[512];
	formatex(headerCopy, charsmax(headerCopy), "%s", header);
	while (strlen(headerCopy)) {
		new line[256], pair[e_KeyValue];
		
		split(headerCopy, line, charsmax(line), headerCopy, charsmax(headerCopy), "^r^n");
		split(line, pair[kvKEY], 127, pair[kvVALUE], 127, ":");
		
		trim(pair[kvKEY]);
		trim(pair[kvVALUE]);
		
		ArrayPushArray(explodedHeader, pair);
	}
	
	return explodedHeader;
}*/

/**
 * Close socket
 *
 * @param int	socketId
 */
public mySocketClose(socketID)
{	
	socket_close(g_sockets[socketID]);
	g_sockets[socketID] = 0;
	remove_task(TASK_CHECK_SOCKET + socketID);
	remove_task(TASK_TIME_OUT + socketID);
}

// ----------------------------------------------------- End of sockets --------------------------------------------------------

_getServicePluginByID( id[])
{
	new temp[MAX_NAME+1];
	for (new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, temp, charsmax(temp));
		if (equali(id, temp)) {
			return ArrayGetCell(service_plugins, i);
		}
	}
	
	return -1;
}

_getServiceByID( id[])
{
	new service[e_Service];
	for (new i = 0; i < ArraySize(services); ++i) {
		ArrayGetArray(services, i, service);
		if (equal(id, service[sID])) {
			return i;
		}
	}
	return -1;
}

_getNumberByTariff( tariff, number[], len)
{	
	new sms[e_SMS];
	for (new i = 0; i < ArraySize(smses); ++i) {
		ArrayGetArray(smses, i, sms);
		if (tariff == sms[sTARIFF]) {
			copy(number, len, sms[NUMBER]);
			return;
		}
	}
}

bool:isDebug()
{
	return bool:get_pcvar_num(cvar_debug);
}

// --------------------------------------------------------- Stocks ------------------------------------------------------------
stock deleteEmptyLines(sciezka[])
{	
	if (!file_exists(sciezka)) {
		return;
	}
		
	new zastepcza[64], licznik = 0
	do {
		formatex(zastepcza, charsmax(zastepcza), "%d", licznik);
		++licznik;
	} while (file_exists(zastepcza))
	
	new szLine[128], iLen;
	for (new i=0; read_file(sciezka, i, szLine, charsmax(szLine), iLen); i++) {
		trim(szLine);
		// pusta linia
		if (!strlen(szLine))
			continue;
		
		write_file(zastepcza, szLine, -1);
	}
	
	if (file_size(zastepcza)>1) {
		//Usuwa stary plik
		unlink(sciezka);
		//Zmienia nazwe tymczasowego pliku na stary plik
		rename_file(zastepcza, sciezka, 1);
	}
}

stock escapeQuotes(string[], string_len=64)
{	
	replace_all(string, string_len, "'", "\'");
}

stock get_sms_cost(szNumber[])
{	
	if (strlen(szNumber) < 4) {
		return 0;
	}
	else if (szNumber[0] == '7') {
		new temp[4];
		formatex(temp, charsmax(temp), "%c", szNumber[1]);
		return szNumber[1] == '0' ? 50 : str_to_num(temp)*100;
	}
	else if (szNumber[0] == '9') {
		new temp[4];
		formatex(temp, charsmax(temp), "%c%c", szNumber[1], szNumber[2]);
		return str_to_num(temp)*100;
	}
	
	return 0;
}

stock two_number_value(value)
{	
	new temp[17];
	if (value < 10) {
		formatex(temp, charsmax(temp), "0%d", value);
	} else {
		formatex(temp, charsmax(temp), "%d", value);
	}
		
	return temp;
}

stock groupDigits(a, output[], len)
{
	setc(output, len, 0);
	new number[32];
	num_to_str(a, number, charsmax(number));
	
	for (new i = 0; i < strlen(number); ++i) {
		if (i && i % 3 == 0)
			format(output, len, " %s", output);
		
		format(output, len, "%c%s", number[strlen(number) - 1 - i], output);
	}
}

stock getXMLValue(const szText[], const tag[], output[], len)
{	
	static temp[64], textStart, textEnd;
	
	formatex(temp, charsmax(temp), "<%s>", tag);
	textStart = contain(szText, temp);
	
	formatex(temp, charsmax(temp), "</%s>", tag);
	textEnd = contain(szText, temp);
	
	if (textStart >= 0) {
		new tag_len = 2 + strlen(tag);
		copy(output, min(len, textEnd - textStart - tag_len), szText[textStart + tag_len]);
	}
}

stock StringURLEncode( const szInput[ ], szOutput[ ], const iLen)
{	
	static const HEXCHARS[ 16 ] = {
		0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 
		0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66
	};
	
	new iPos, cChar, iFLen;
	while (( cChar = szInput[ iPos ] ) && iFLen < iLen )
	{
		if (cChar == 0x20) {
			szOutput[ iFLen++ ] = 0x2B;
		}
		else if (!( 0x41 <= cChar <= 0x5A )
		&& !( 0x61 <= cChar <= 0x7A )
		&& !( 0x30 <= cChar <= 0x39 )
		&& cChar != 0x2D
		&& cChar != 0x2E
		&& cChar != 0x5F )
		{
			if (( iFLen + 3 ) > iLen) {
				break;
			}
			else if (cChar > 0xFF || cChar < 0x00) {
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
	
	return iFLen;
}

stock bool:json_decode(const string[], const key[], output[], output_len)
{
	new pos = 0;
	new len = strlen(string);
	new key_start, key_len;
	new temp_key[ 512 ];
	new value_start, value_len;
	new escaped = false;
	
	while (pos < len) {

		while (string[pos] != '"') {
			pos++;
		}
	
		// Pozyskujemy nazwe klucza
		key_start = pos + 1;
		escaped = false;
		while (++pos < len) {
			if (pos == len) {
				return false;
			}
	
			if (escaped) {
				escaped = false;
			} else if (string[ pos ] == '\') {
				escaped = true;
			} else if (string [ pos ] == '"') {
				break;
			}
		}
		
		if (pos == len) {
			return false;
		}
		
		if (!(key_len = pos - key_start)) {
			continue;
		}
		
		copy(temp_key, min(charsmax(temp_key), key_len), string[key_start]);
	
		pos++; // Przechodzimy o jeden dalej, bo zatrzymalismy sie na znaku '"'
		while (pos < len && isspace(string[pos])) ++pos;
		if (pos == len) {
			return false;
		}
	
		if (string[ pos ] != ':') {
			continue;
		}
			
		pos++; // Przechodzimy o jeden dalej, bo zatrzymalismy sie na znaku ':'
			
		while (pos < len && isspace(string[pos])) ++pos;
		if (pos == len) {
			return false;
		}
		
		value_start = pos;
		
		pos--; // Wracamy o jeden, bo pozniej mamy pre inkrementacje
		while (++pos < len) {
			if (escaped) {
				escaped = false;
			} else if (string[ pos ] == '\') {
				escaped = true;
			} else if (string [ pos ] == ',' || string [ pos ] == '}') {
				break;
			}
		}
		if (pos == len) {
			return false;
		}
		
		if (!(value_len = pos - value_start)) {
			continue;
		}
			
		// Jezeli klucz jest inny niz ten w argumencie funkcji, to nie kopiuj jego value
		if (!equal(temp_key, key)) {
			continue;
		}
		
		copy(output, min(output_len, value_len), string[value_start]);
		trim(output);
		remove_quotes(output);
		
		return true;
	}
	
	return false;
}
