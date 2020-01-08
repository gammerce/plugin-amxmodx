#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <curl>
#include <regex>
#include <shop_sms_const>
#include <custom_color_chat>

#pragma semicolon 1

forward amxbans_sql_initialized(Handle:sqlTuple, dbPrefix[]);
forward client_admin(id, flags);
forward amxx_admin_access(id, flags, timestamp);

#define FLAG_NICK (1<<5)

// ID zadan
#define TASK_KEEP_INFO_SMS 2000
#define TASK_CHECK_USER 5000
#define TASK_KEEP_DISPLAYING_MENU 8000

// Klawisze ktore mozna uzyc w menu
#define KEYS (1<<0)|(1<<9) // Keys: 10

// Logowanie danych
#define LOG_SQL
#define CFG_FILE "sklep_sms.cfg"
new const LOG_FILE[] = "sklep_sms.log";

const MAX_COMMAND = 32;
const MAX_CONTACT = 64;
const MAX_RANDOM_KEY = 32;
const MAX_PAYMENT_MODULE_ID = 32;

enum e_KeyValue {
	kvKEY[128],
	kvVALUE[128]
};

// Rejestracja uslug
enum e_Service {
	sID[MAX_SERVICE_ID + 1], 
	PLUGIN, 
	sNAME[MAX_SERVICE_NAME + 1], 
	DESCRIPTION[MAX_DESCRIPTION + 1], 
	TAG[MAX_SERVICE_TAG + 1], 
	GROUPS[33], 
	FLAGS[27], 
	TYPES
};

new Array:service_plugins, 
	Array:service_ids, 
	Array:services;
	
// Numery i taryfy SMS
enum e_SMS {
	NUMBER[MAX_NUMBER + 1], 
	sTARIFF, 
};
new Array:smses;

// Lista cen (taryf) dla usług
enum e_Price {
	pSERVICE[MAX_SERVICE_ID + 1], 
	pTARIFF, 
	AMOUNT, 
};
new Array:pricelist;

//Dodatkowe zmienne
new which_service[33], 
	which_price[33], 
	b_passwords[33][MAX_PASSWORD + 1], 
	b_types[33];

// CVARy
new cvar_on, cvar_show_info, cvar_sklep, cvar_przeladuj, cvar_uslugi, cvar_host, cvar_user, cvar_pass, cvar_db, cvar_server_ip, cvar_silent_command;
new sklep_komenda[MAX_COMMAND + 1], przeladuj_komenda[MAX_COMMAND + 1], uslugi_komenda[MAX_COMMAND + 1], show_info;

// Sciezka do pliku konfiguracyjnego
new config_path[128];

// Requests
const MAX_RESPONSE = 1024;
const MAX_RESPONSE_COUNT = 5;
new g_requestCounter = 0;
new g_responses[MAX_RESPONSE_COUNT][MAX_RESPONSE + 1];
new bool:g_requestsInProgress[MAX_RESPONSE_COUNT];

enum requestStruct {
	RequestId,
	curl_slist: RequestHeaders,
	RequestCallback[MAX_FUNCTION + 1],
	RequestPlayerId,
};

// License
new g_licenseToken[63];
new bool:g_footer = true;
new g_serverIp[MAX_IP + 1];
new g_serverPort[MAX_PORT + 1];
new g_serverName[MAX_SERVER_NAME + 1];
new bool:g_blocked = false;
new bool:g_validationAttempt = false;
new g_signature;

// MySQL
new const TABLE_PREFIX[] = "ss_";
new Handle:SqlTuple;
new bool:g_sqlConnected = false;
new sql_host[MAX_URL_HOST + 1], sql_user[32], sql_pass[32], sql_db[32];
new g_serverId;
new const all_flags[] = "abcdefghijklmnopqrstuyvwxz";
new g_szTemp[4096];

// Players flags
enum e_PlayerFlags {
	pfPLAYER[33], 
	pfFLAGS, 
	pfPASSWORD[MAX_PASSWORD+2], 
	pfTYPE
};
new Array:g_playersFlags;
new bool:g_playersLoaded = false;
new g_lastReassign;

// Accounts
new g_accountsSteamIds[4096] = "";

// Settings
new g_currency[16],
	g_smsPlatformId,
	g_smsModuleId[MAX_PAYMENT_MODULE_ID + 1],
	g_contact[MAX_CONTACT + 1], 
	g_randomKey[MAX_RANDOM_KEY + 1], 
	g_randomKeyMD5[34], 
	g_shopPageUrl[MAX_URL + 1],
	g_smsText[MAX_SMS_TEXT + 1],
	Float:g_vat;

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
	
	// Wczytywanie confingu
	if (file_exists(config_path)) {
		server_cmd("exec %s", config_path);
	}
	
	service_plugins = ArrayCreate();
	service_ids = ArrayCreate(MAX_SERVICE_ID + 1);
	
	g_playersFlags = ArrayCreate(e_PlayerFlags);
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
	register_concmd("sklepsms_reloaddata", "realoadPlayersServices");
	register_concmd("sklepsms_reloadusers", "pre_reassignPlayersFlags");
	
	register_clcmd("say", "sayHook");
	register_clcmd("say_team", "sayHook");
	
	if (show_info) {
		set_task(137.0, "reklama", _, _, _, "b");
	}

	g_signature = random_num(1, 99999999);
}

public loadCvars()
{
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
	
	loadCvars();
	
	// Łaczenie z baza
	SqlTuple = SQL_MakeDbTuple(sql_host, sql_user, sql_pass, sql_db);
	if (! SqlTuple) {
		_error51();
	}
	
	// Get server ip
	new fullIp[MAX_FULL_IP];
	get_pcvar_string(cvar_server_ip, fullIp, charsmax(fullIp));
	if (!strlen(fullIp)) { // Brak ip w cvarach
		get_user_ip(0, fullIp, charsmax(fullIp), false);
	}
	
	split(fullIp, g_serverIp, charsmax(g_serverIp), g_serverPort, charsmax(g_serverPort), ":");

	_loadPlayersServices(false);
	_loadSettings();
}

public checkLoadedServices()
{	
	if (!ArraySize(services)) {
		log_amx("Nie zaladowano zadnych uslug do zakupienia.");
	} else {
		log_amx("Zaladowano %d uslug do zakupienia.", ArraySize(services));
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
		pre_reassignPlayersFlags(id);
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
		data[0] = i + 1;
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
	client_print_color(id, Red, "^4[%s] ^1poprzez: ^3%s", PREFIX, g_contact);
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
		
		new amount[32 + 1];
		if (price[AMOUNT] == -1) { // Jezeli -1 to usluga jest na zawsze
			formatex(amount, charsmax(amount), "Na zawsze");
		} else {
			groupDigits(price[AMOUNT], amount, charsmax(amount));
			format(amount, charsmax(amount), "%s %s", amount, service[TAG]);
		}
		new temp_cost = get_sms_cost(number);
		formatex(szText, charsmax(szText), 
			"\y%s \wza %d.%s %s + VAT\d ( %d.%s %s )", 
			amount, temp_cost/100, two_number_value(temp_cost%100), g_currency, floatround(temp_cost*g_vat)/100, 
			two_number_value(floatround(temp_cost*g_vat)%100), g_currency
		);
		data[0] = service_id+1;
		data[1] = min(127, i); // TODO: Problem przy ilosci uslug powyzej 256!
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
		displayServiceTypeMenu(id);
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
	
	which_service[id] = data[0] - 1;
	which_price[id] = data[1] + data[2];
	
	displayServiceTypeMenu(id);
	menu_destroy(menu);
}
/* Koniec menu wyboru */

public keepDisplayingMenu(data[])
{	
	new id = data[0];
	if (!is_user_connected(id)) {
		menu_destroy(data[1]);
		return;
	}
	
	new menu, newmenu;
	player_menu_info(id, menu, newmenu);
	if (newmenu != data[1]) {
		menu_display(id, data[1]);
	}
			
	set_task(0.1, "keepDisplayingMenu", TASK_KEEP_DISPLAYING_MENU + id, data, 2);
}

public displayServiceTypeMenu(id)
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
		
		keepDisplayingMenu(data);
	} else {
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

public menuServiceType_handler(id, menu, item)
{
	if (0 <= item && item <= 2) {
		remove_task(TASK_KEEP_DISPLAYING_MENU+id);
		menu_destroy(menu);
	}

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
}

public menuServiceType_nick(id)
{	
	new szPassword[MAX_PASSWORD + 1];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (!_menuServiceType_checkPass(id, TYPE_NICK, szPassword)) {
		client_cmd(id, "messagemode ssnick_Podaj_Haslo");
	}
}

public menuServiceType_ip(id)
{
	new szPassword[MAX_PASSWORD + 1];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (! _menuServiceType_checkPass(id, TYPE_IP, szPassword)) {
		client_cmd(id, "messagemode ssip_Podaj_Haslo");
	}
}

bool:_menuServiceType_checkPass(id, type, const szPassword[MAX_PASSWORD + 1])
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
		new szPassword[MAX_PASSWORD + 1];
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "password"), szPassword, charsmax(szPassword));
		_serviceChosen(id, type, szPassword);
	}
	else if (type == TYPE_NICK) {
		client_print_color(id, Red, "^4[%s] ^1Istnieje juz usluga wykupiona na ten ^3nick^1, lecz posiada inne haslo. Wprowadz haslo ^3ponownie^1.", PREFIX);
		client_cmd(id, "messagemode ssnick_Podaj_Haslo");
	}
	else if (type == TYPE_IP) {
		client_print_color(id, Blue, "^4[%s] ^1Istnieje juz usluga wykupiona na ten ^3adres IP^1, lecz posiada inne haslo. Wprowadz haslo ^3ponownie^1.", PREFIX);
		client_cmd(id, "messagemode ssip_Podaj_Haslo");
	}
}

_serviceChosen(id, type = 0, const szPassword[MAX_PASSWORD + 1] = "")
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
		displayPaymentMethodMenu(id);
	}
}

public displayPaymentMethodMenu(id)
{
	new service[e_Service];
	ArrayGetArray(services, which_service[id], service);
	
	new menu = menu_create("Wybierz metode platnosci", "menuPaymentMethod_handler");
	new menu_callback = menu_makecallback("menuPaymentMethod_callback");

	menu_additem(menu, "SMS", "", 0, menu_callback);
	menu_additem(menu, "Portfel", "", 0, menu_callback);

	new data[4];
	data[0] = id;
	data[1] = menu;
	
	keepDisplayingMenu(data);
}

public menuPaymentMethod_callback(id, menu, item)
{
	switch (item) {
		case 0: {
			return ITEM_ENABLED;
		}
		case 1: {
			return _canPayWithWallet(id) ? ITEM_ENABLED : ITEM_DISABLED;
		}
	}

	return ITEM_DISABLED;
}

public menuPaymentMethod_handler(id, menu, item)
{
	remove_task(TASK_KEEP_DISPLAYING_MENU + id);
	menu_destroy(menu);

	switch (item) {
		case 0: {
			displayInfoSMS(id);
		}
		case 1: {
			purchaseService(id, "wallet");
		}
	}
}

displayInfoSMS(id)
{	
	if (!is_user_connected(id)) {
		return;
	}
	
	new service[e_Service], price[e_Price], number[MAX_NUMBER + 1];
	ArrayGetArray(services, which_service[id], service);
	ArrayGetArray(pricelist, which_price[id], price);
	_getNumberByTariff(price[pTARIFF], number, charsmax(number));
	
	new amount[32 + 1];
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
		g_szTemp, g_smsText, number, temp_cost/100, two_number_value(temp_cost%100), g_currency, floatround(temp_cost*g_vat)/100, 
		two_number_value(floatround(temp_cost * g_vat)%100), g_currency
	);
	format(g_szTemp, charsmax(g_szTemp), "%s^n^n\wPo wyslaniu SMSa poczekaj na kod zwrotny.^nW celu wprowadzenia go, wcisnij: \y1^n^n\wAby wyjsc, wcisnij: \y0", g_szTemp);
	
	keepDisplayingInfoSMS(g_szTemp, TASK_KEEP_INFO_SMS + id);
}

public keepDisplayingInfoSMS(const info[], id)
{	
	id -= TASK_KEEP_INFO_SMS;
	if (!is_user_connected(id)) {
		return;
	}
		
	show_menu(id, KEYS, info, 1, "SMS_Info");
	set_task(0.9, "keepDisplayingInfoSMS", id+TASK_KEEP_INFO_SMS, info, strlen(info));
}

public infoSMS_handler(id, key)
{	
	if (task_exists(TASK_KEEP_INFO_SMS + id)) {
		remove_task(TASK_KEEP_INFO_SMS + id);
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
		
	new sms_code[MAX_CODE + 1];
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

	purchaseService(id, "sms", sms_code);
}

purchaseService(id, const method[], const sms_code[] = "") {
	client_print_color(id, Red, "^4[%s] ^1Trwa przeprowadzanie zakupu...", PREFIX);

	if (!_canUseShop()) {
		client_print_color(id, Red, "^4[%s] ^1Sklep jest tymczaosowo nieaktywny.", PREFIX);
		return;
	}
	
	new url[MAX_URL + 1];
	new body[MAX_BODY + 1];
	new curl_slist: headers;
	{
		new service[e_Service], auth_data[32 + 1], steam_id[32 + 1], price[e_Price], ip[MAX_IP + 1];
		new u_service_id[MAX_SERVICE_ID * 2 + 1], u_auth_data[64 + 1], u_steam_id[64 + 1],
			u_password[MAX_PASSWORD * 2 + 1], u_sms_code[MAX_CODE * 2 + 1];
		
		new sign[34], sign_body[1 + charsmax(auth_data) + charsmax(sms_code) + charsmax(g_randomKey) + 1];
		new header[MAX_HEADERS + 1];

		// Pobieramy dane o usludze
		ArrayGetArray(services, which_service[id], service);
		
		// Pobieramy dane gracza Nick / IP / SID
		switch (b_types[id]) {
			case TYPE_IP: get_user_ip(id, auth_data, charsmax(auth_data), true);
			case TYPE_SID: get_user_authid(id, auth_data, charsmax(auth_data));
			case TYPE_NICK: get_user_name(id, auth_data, charsmax(auth_data));
		}
	
		// Jezeli usluga nie jest wykupowana na nickpass, ippass, sid, to pobieramy nick
		if (!strlen(auth_data)) {
			get_user_name(id, auth_data, charsmax(auth_data));
		}
		
		// Get user's IP
		get_user_ip(id, ip, charsmax(ip), true);
		
		// Get user's SteamID
		get_user_authid(id, steam_id, charsmax(steam_id));
		
		// Get tariff
		ArrayGetArray(pricelist, which_price[id], price);
	
		// Encode url params
		StringURLEncode(service[sID], u_service_id, charsmax(u_service_id));
		StringURLEncode(auth_data, u_auth_data, charsmax(u_auth_data));
		StringURLEncode(b_passwords[id], u_password, charsmax(u_password));
		StringURLEncode(sms_code, u_sms_code, charsmax(u_sms_code));
		StringURLEncode(steam_id, u_steam_id, charsmax(u_steam_id));

		// Calculate body sign
		formatex(sign_body, charsmax(sign_body),
			"%d#%s#%s#%s",
			b_types[id], auth_data, sms_code, g_randomKey
		);
		vc_md5(sign_body, sign);

		formatex(header, charsmax(header), "Authorization: %s", steam_id);
		headers = curl_slist_append(headers, header);
		
		formatex(body, charsmax(body),
			"sign=%s&service=%s&type=%d&auth_data=%s&password=%s&method=%s&server=%d&payment_platform=%d&sms_code=%s&tariff=%d&ip=%s",
			sign, u_service_id, b_types[id], u_auth_data, u_password, method, g_serverId, g_smsPlatformId, u_sms_code, price[pTARIFF], ip
		);
		
		formatex(url, charsmax(url), "%s/api/server/purchase?key=%s&language=polish", g_shopPageUrl, g_randomKeyMD5);
	}

	if (!makeRequest("POST", url, headers, body, "getWebPagePurchaseService", id)) {
		client_print_color(id, Red, "^4[%s] ^1Nie udalo sie wykonac zapytania HTTP.", PREFIX);
	}
}

public getWebPagePurchaseService(const content[], CURLcode: code, statusCode, playerId)
{
	if (code != CURLE_OK) {
		log_to_file(LOG_FILE, "Zakup nie zostal sfinalizowany z nieznanych powodow. Error: %d", code);
		client_print_color(playerId, Red, "^4[%s] ^1Zakup ^3nie zostal sfinalizowany ^1z nieznanych powodow. Error: %d", PREFIX, code);
		return;
	}

	if (statusCode >= 300) {
		client_print_color(playerId, Red, "^4[%s] ^1Zapytanie zwrocilo bledny http code.", PREFIX);
		return;
	}
	
	new return_value[33], szText[128], szPositive[3], szBsid[16], szWarnings[256];

	getXMLValue(content, "return_value", return_value, charsmax(return_value));
	getXMLValue(content, "text", szText, charsmax(szText));
	getXMLValue(content, "positive", szPositive, charsmax(szPositive));
	getXMLValue(content, "bsid", szBsid, charsmax(szBsid));
	getXMLValue(content, "warnings", szWarnings, charsmax(szWarnings));
	
	trim(return_value);
	trim(szText);
	trim(szWarnings);

	if (!strlen(return_value)) {
		log_amx("Invalid response: %s", content);
	}

	purchaseServicePost(playerId, return_value, szText, str_to_num(szPositive), str_to_num(szBsid), szWarnings);
}

public purchaseServicePost(id, const return_value[], const szText[], positive, bsid, const szWarnings[])
{
	if (! is_user_connected(id)) {
		return;
	}
	
	client_print_color(id, Red, "^4[%s] ^1%s", PREFIX, strlen(szText) ? szText : "Wystapil blad. Brak odpowiedzi z serwera.");	
	
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
		client_print_color(id, Red, "^4[%s] ^1Wystapil ^3blad ^1podczas kupowania uslugi. Zglos nam to: ^4%s", PREFIX, g_contact);
		
		new amount[32 + 1];
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
	if (b_types[id] & (TYPE_NICK | TYPE_IP)) {
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
	else if (b_types[id] & TYPE_SID) {
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>Wykupiles/as usluge: <span style=^"color: red^">%s</span><br /><br />\
			W razie problemow skontaktuj sie z nami.\
			</center></body></html>", 
			service[sNAME]
		);
		show_motd(id, g_szTemp, "Informacje dotyczace uslugi");
	}
	
	new amount[32 + 1];
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
		set_task(2.0, "realoadPlayersServices");
	}
}

/**
 * Dodanie kodu do bazy kodow
 *
 * @param const char[]	sms_code
 * @param int			sms_tariff	
 * @param bool			free
 */
addCode(const sms_code[], sms_tariff, bool:free = true)
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
		
	new name[MAX_NAME * 2 + 1], sid[MAX_SID * 2 + 1], ip[MAX_IP + 1];
	get_user_name(id, name, charsmax(name));
	get_user_ip(id, ip, charsmax(ip), true);
	get_user_authid(id, sid, charsmax(sid));
	
	escapeQuotes(name, charsmax(name));
	escapeQuotes(ip, charsmax(ip));
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
		new service[MAX_SERVICE_ID + 1], expire[32 + 1], item_text[128];
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

/**
 * Wrapper for _reassignPlayersFlags
 *
 * @param int	id
 */
public pre_reassignPlayersFlags(id)
{	
	if (g_lastReassign + 10 > get_systime()) {
		client_print_color(id, Red, "^4[%s] ^1Ktos przed chwila przeladowal liste. Odczekaj chwile.", PREFIX);
		return;
	}
	
	g_lastReassign = get_systime();
	_reassignPlayersFlags(id);
}

/**
 * Reload players flags and assign them again
 *
 * @param int	id
 */
_reassignPlayersFlags(id = 0)
{
	addUsersToGlobalArray();

	for (new i = 1; i <= get_maxplayers(); ++i) {
		if (! is_user_connected(i)) {
			continue;
		}
			
		_usersCheckUser(i);
	}
	
	if (is_user_connected(id)) {
		client_print_color(id, Red, "^4[%s] ^1Prawidlowo przeladowano liste flag wykupionych w sklepiku.", PREFIX);
	}
}

// Funkcja wczytujaca z bazy ponownie dane graczy
public realoadPlayersServices() {	
	_loadPlayersServices(true);
}

_loadPlayersServices(bool:reloadAmxbans) {
	// Czyscimy dotychczasowe dane
	ArrayClear(g_playersFlags);
	g_playersLoaded = false;
	
	if (SqlTuple) {
		new iLen = 0, iMax = charsmax(g_szTemp);

		iLen += formatex(g_szTemp[iLen], iMax - iLen,
			"SELECT f.type, f.auth_data, f.password, \
			(f.a > UNIX_TIMESTAMP() OR f.a = '-1') AS `a`, \
			(f.b > UNIX_TIMESTAMP() OR f.b = '-1') AS `b`, \
			(f.c > UNIX_TIMESTAMP() OR f.c = '-1') AS `c`, \
			(f.d > UNIX_TIMESTAMP() OR f.d = '-1') AS `d`, \
			(f.e > UNIX_TIMESTAMP() OR f.e = '-1') AS `e`, \
			(f.f > UNIX_TIMESTAMP() OR f.f = '-1') AS `f`, \
			(f.g > UNIX_TIMESTAMP() OR f.g = '-1') AS `g`, \
			(f.h > UNIX_TIMESTAMP() OR f.h = '-1') AS `h`, "
		);
		
		iLen += formatex(g_szTemp[iLen], iMax - iLen,
			"(f.i > UNIX_TIMESTAMP() OR f.i = '-1') AS `i`, \
			(f.j > UNIX_TIMESTAMP() OR f.j = '-1') AS `j`, \
			(f.k > UNIX_TIMESTAMP() OR f.k = '-1') AS `k`, \
			(f.l > UNIX_TIMESTAMP() OR f.l = '-1') AS `l`, \
			(f.m > UNIX_TIMESTAMP() OR f.m = '-1') AS `m`, \
			(f.n > UNIX_TIMESTAMP() OR f.n = '-1') AS `n`, \
			(f.o > UNIX_TIMESTAMP() OR f.o = '-1') AS `o`, \
			(f.p > UNIX_TIMESTAMP() OR f.p = '-1') AS `p`, "
		);
		
		iLen += formatex(g_szTemp[iLen], iMax - iLen,
			"(f.q > UNIX_TIMESTAMP() OR f.q = '-1') AS `q`, \
			(f.r > UNIX_TIMESTAMP() OR f.r = '-1') AS `r`, \
			(f.s > UNIX_TIMESTAMP() OR f.s = '-1') AS `s`, \
			(f.t > UNIX_TIMESTAMP() OR f.t = '-1') AS `t`, \
			(f.u > UNIX_TIMESTAMP() OR f.u = '-1') AS `u`, \
			(f.y > UNIX_TIMESTAMP() OR f.y = '-1') AS `y`, \
			(f.v > UNIX_TIMESTAMP() OR f.v = '-1') AS `v`, \
			(f.w > UNIX_TIMESTAMP() OR f.w = '-1') AS `w`, \
			(f.x > UNIX_TIMESTAMP() OR f.x = '-1') AS `x`, \
			(f.z > UNIX_TIMESTAMP() OR f.z = '-1') AS `z` "
		);
		
		iLen += formatex(g_szTemp[iLen], iMax - iLen,
			"FROM `%splayers_flags` AS f \
			JOIN `%sservers` AS s ON s.id = f.server \
			WHERE s.ip = '%s' \
			AND s.port = '%s' \
			ORDER BY f.auth_data, f.type DESC",
			TABLE_PREFIX, TABLE_PREFIX, g_serverIp, g_serverPort
		);
	
		new data[1]; data[0] = reloadAmxbans; // Przeladuj liste adminow w amxbans
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
			if (SQL_ReadResult(Query, SQL_FieldNameToNum(Query, temp))) {
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
			ArrayPushArray(g_playersFlags, player_flags);
		}
		
		SQL_NextRow(Query);
	}
	
	log_amx("Zaladowano %d uslug graczy", ArraySize(g_playersFlags));
	g_playersLoaded = true;
	
	if (data[0] && g_AmxbansExists) { // Przeladuj dane w amxbans, a tym samym uruchom komende dodawania danych do tablicy globalnej uprawnien
		server_cmd("amx_reloadadmins");
	}
	else {
		_reassignPlayersFlags();
	}
}

public amxbans_sql_initialized()
{	
	g_AmxbansExists = true;
	_reassignPlayersFlags();
}

public client_admin(id, flags)
{
    _usersCheckUser(id);
}

public amxx_admin_access(id, flags, timestamp)
{
    _usersCheckUser(id);
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
	
	for (new i = 0; i < ArraySize(g_playersFlags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(g_playersFlags, i, player_flags);
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
	
	for (new i = 0; i < ArraySize(g_playersFlags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(g_playersFlags, i, player_flags);
		
		if (player_flags[pfTYPE] & FLAG_NICK) {
			new name[MAX_NAME + 1];
			get_user_name(id, name, charsmax(name));
			if (! equali(name, player_flags[pfPLAYER])) {
				continue;
			}
		}
		else if (player_flags[pfTYPE] & FLAG_IP) {
			new ip[MAX_IP + 1];
			get_user_ip(id, ip, charsmax(ip), true);
			if (! equali(ip, player_flags[pfPLAYER])) {
				continue;
			}
		}
		else if (player_flags[pfTYPE] & FLAG_AUTHID) {			
			new sid[MAX_SID + 1], arr_sid[MAX_SID + 1];
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
			new password[MAX_PASSWORD + 1], password_md5[34];
			
			get_user_info(id, "_pw", password, charsmax(password));
			vc_md5(password, password_md5);
			
			if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
				get_user_info(id, "_pw2", password, charsmax(password));
				vc_md5(password, password_md5);
				if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
					get_user_info(id, "_pw3", password, charsmax(password));
					vc_md5(password, password_md5);
					if (! equal(password_md5, player_flags[pfPASSWORD]) && !equal(password, player_flags[pfPASSWORD])) {
						get_user_info(id, "_ss", password, charsmax(password));
						vc_md5(password, password_md5);
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

public brakSciezki(id, const path[])
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
	vformat(g_szTemp, charsmax(g_szTemp), szFormat, 3);
	
	if (is_user_connected(id)) {
		new name[MAX_NAME + 1], ip[MAX_IP + 1], sid[MAX_SID + 1];
		get_user_name(id, name, charsmax(name));
		get_user_ip(id, ip, charsmax(ip), true);
		get_user_authid(id, sid, charsmax(sid));
		format(g_szTemp, charsmax(g_szTemp), "%s; %s; %s. %s", name, ip, sid, g_szTemp);
	}
	
	log_to_sql(g_szTemp);
	#endif
}

public log_to_sql(const text[])
{
	if (SqlTuple) {
		format(g_szTemp, charsmax(g_szTemp), "%s. Serwer: %d", text, g_serverId);
		escapeQuotes(g_szTemp, charsmax(g_szTemp));
		
		// Cannot be formatex, because param text is probably g_szTemp
		format(g_szTemp, charsmax(g_szTemp),
			"INSERT INTO `%slogs` (text) \
			VALUES ('%s')",
			TABLE_PREFIX, g_szTemp
		);
		SQL_ThreadQuery(SqlTuple, "IgnoreHandle", g_szTemp);
	}
}

_loadSettings()
{
	formatex(g_szTemp, charsmax(g_szTemp),
		"SELECT * FROM `%ssettings` \
		WHERE `key` IN ('shop_url', 'random_key')",
		TABLE_PREFIX
	);
	SQL_ThreadQuery(SqlTuple, "getSettingsHandler", g_szTemp);
}

public getSettingsHandler(FailState, Handle:Query, Error[], Errorcode)
{	
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	while (SQL_MoreResults(Query)) {
		new key[128], value[256];
		
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "key"), key, charsmax(key));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "value"), value, charsmax(value));

		if (equali(key, "shop_url")) {
			copy(g_shopPageUrl, charsmax(g_shopPageUrl), value);
			
			// Remove trailing slash
			if (strlen(g_shopPageUrl) && g_shopPageUrl[strlen(g_shopPageUrl) - 1] == '/') {
				g_shopPageUrl[strlen(g_shopPageUrl) - 1] = '^0';
			}
			
			if (! strlen(g_shopPageUrl)) {
				_errorNoShopUrl();
				return;
			}
		}
		else if (equali(key, "random_key")) {
			copy(g_randomKey, charsmax(g_randomKey), value);
			vc_md5(g_randomKey, g_randomKeyMD5); // Hashujemy random key
		}
		
		SQL_NextRow(Query);
	}
	
	_loadServerConfig();
}

_loadServerConfig()
{
	new url[MAX_URL + 1];
	formatex(url, charsmax(url), "%s/api/server/config?key=%s&ip=%s&port=%s&version=%s", g_shopPageUrl, g_randomKeyMD5, g_serverIp, g_serverPort, VERSION);

	if (!makeRequest("GET", url, 0, "", "onLoadServerConfigResponse")) {
		_errorConfigFailed(999);
	}
}

public onLoadServerConfigResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (code != CURLE_OK) {
		_errorConfigFailed(code);
		return;
	}

	if (statusCode == 404) {
		_errorNoServer();
	}

	if (statusCode == 402) {
		_errorOutdatedVersion();
	}

	if (statusCode >= 300) {
		_errorConfigInvalidResponse(statusCode);
		return;
	}

	new szServices[512];

	extractFieldValue(content, "id", g_szTemp, charsmax(g_szTemp));
	g_serverId = str_to_num(g_szTemp);
	extractFieldValue(content, "sms_platform_id", g_szTemp, charsmax(g_szTemp));
	g_smsPlatformId = str_to_num(g_szTemp);
	extractFieldValue(content, "sms_module_id", g_smsModuleId, charsmax(g_smsModuleId));
	extractFieldValue(content, "sms_text", g_smsText, charsmax(g_smsText));
	extractFieldValue(content, "services", szServices, charsmax(szServices));
	extractFieldValue(content, "steam_ids", g_accountsSteamIds, charsmax(g_accountsSteamIds));
	extractFieldValue(content, "currency", g_currency, charsmax(g_currency));
	extractFieldValue(content, "contact", g_contact, charsmax(g_contact));
	extractFieldValue(content, "vat", g_szTemp, charsmax(g_szTemp));
	g_vat = str_to_float(g_szTemp);
	extractFieldValue(content, "license_token", g_licenseToken, charsmax(g_licenseToken));

	_validateLicense();
	_getServicesData(szServices);
	_getSmsNumbers();
}

_getServicesData(const services[])
{
	// Sprawdzanie dostepnosci usług
	new service_id[MAX_SERVICE_ID + 1], service_id_space[MAX_SERVICE_ID + 2 + 1], ids[512], ids_len = 0, ids_max = charsmax(ids);
	for (new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, service_id, charsmax(service_id));
		formatex(service_id_space, charsmax(service_id_space), " %s ", service_id);
		
		if (containi(services, service_id_space) != -1) {
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
		
			SQL_ThreadQuery(SqlTuple, "getServicesDataHandler", g_szTemp);
		}
	} else {
		checkLoadedServices(); // Sprawdz zaladowane uslugi
	}
}

public getServicesDataHandler(FailState, Handle:Query, Error[], Errorcode) {
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	new service[e_Service];
	new ids[512], ids_len = 0, ids_max = charsmax(ids);
	while (SQL_MoreResults(Query))
	{
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "id"), service[sID], MAX_SERVICE_ID);
		service[PLUGIN] = _getServicePluginByID(service[sID]);
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "name"), service[sNAME], MAX_SERVICE_NAME);
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
			ids_len += formatex(ids[ids_len], ids_max-ids_len, ",");
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
			SQL_ThreadQuery(SqlTuple, "getPriceListHandler", g_szTemp);
		}
	}
}

public getPriceListHandler(FailState, Handle:Query, Error[], Errorcode)
{		
	if (_checkForSQLErrors(Query, FailState, Error, Errorcode) == PLUGIN_HANDLED) {
		return;
	}

	while (SQL_MoreResults(Query))
	{
		new price[e_Price];
		
		price[pTARIFF] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "tariff"));
		SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "service"), price[pSERVICE], MAX_SERVICE_ID);
		price[AMOUNT] = SQL_ReadResult(Query, SQL_FieldNameToNum(Query, "amount"));
		
		ArrayPushArray(pricelist, price);
		
		SQL_NextRow(Query);
	}
}

_getSmsNumbers()
{
	if (SqlTuple) {
		new payment_module_id[MAX_PAYMENT_MODULE_ID + 1];
		formatex(payment_module_id, charsmax(payment_module_id), "%s", g_smsModuleId);
		escapeQuotes(payment_module_id, charsmax(payment_module_id));
		
		formatex(g_szTemp, charsmax(g_szTemp),
			"SELECT `number`, `tariff` \
			FROM `%ssms_numbers` \
			WHERE `service` = '%s'",
			TABLE_PREFIX, payment_module_id
		);
		SQL_ThreadQuery(SqlTuple, "getSmsNumbersHandler", g_szTemp);
	}
}

public getSmsNumbersHandler(FailState, Handle:Query, Error[], Errorcode)
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

_canPayWithWallet(id)
{
	new steam_id[MAX_SID + 2];

	get_user_authid(id, steam_id, charsmax(steam_id));
	// CSGO uses different steamid prefix. STEAM_1 instead of STEAM_0.
	// That is why we want to ignore SID prefix.
	replace(steam_id, charsmax(steam_id), "STEAM_1", "");
	replace(steam_id, charsmax(steam_id), "STEAM_0", "");
	format(steam_id, charsmax(steam_id), "%s;", steam_id);

	return containi(g_accountsSteamIds, steam_id) != -1;
}

_validateLicense()
{
	new curl_slist: headers;
	new header[MAX_HEADERS + 1];
	new body[MAX_BODY + 1];
	
	{
		new serverNameEscaped[MAX_SERVER_NAME * 2 + 1];
		get_cvar_string("hostname", g_serverName, charsmax(g_serverName));
		StringURLEncode(g_serverName, serverNameEscaped, charsmax(serverNameEscaped));

		formatex(header, charsmax(header),
			"Authorization: %s",
			g_licenseToken
		);
		headers = curl_slist_append(headers, header);

		formatex(body, charsmax(body),
			"platform=amxmodx&url=%s:%s&name=%s&version=%s&signature=%d&platform_version=%s",
			g_serverIp, g_serverPort, serverNameEscaped, VERSION, g_signature, AMXX_VERSION_STR
		);
	}
	
	if (!makeRequest("POST", "https://license.sklep-sms.pl/v1/authorization/server", headers, body, "onValidateLicenseResponse")) {
		_errorForbidden("Brak miejsca w puli requestow");
	}
}

public onValidateLicenseResponse(const content[], CURLcode: code, statusCode, playerId)
{
	g_shopRegistered = false;

	if (g_validationAttempt) {
		_errorForbidden();
		return;
	}

	g_validationAttempt = true;

	if (code != CURLE_OK) {
		log_to_file(LOG_FILE, "Licencja nie zostala zwalidowana z nieznanych powodow. Error: %d", code);
		return;
	}

	if (statusCode == 401) {
		_errorInvalidToken();
		return;
	}

	if (statusCode == 422) {
		_errorValidationError();
		return;
	}

	if (statusCode == 402) {
		_errorPaymentRequired();
		return;
	}

	if (statusCode == 403) {
		new text[128 + 1];
		getXMLValue(content, "text", text, charsmax(text));
		trim(text);
		_errorForbidden(text);
		return;
	}

	if (statusCode >= 300) {
		_errorLicenseInvalidResponse(statusCode);
		return;
	}

	new text[32 + 1];
	getXMLValue(content, "text", text, charsmax(text));
	trim(text);

	if (!equal(text, "ok")) {
		log_to_file(LOG_FILE, "%s", content);
		_errorUnknown();
		return;
	}

	new szSignature[16], signature;
	getXMLValue(content, "signature", szSignature, charsmax(szSignature));
	signature = str_to_num(szSignature);

	if (signature != g_signature) {
		_errorForbidden();
		return;
	}

	new footer[2];
	getXMLValue(content, "footer", footer, charsmax(footer));
	g_footer = str_to_num(footer) ? true : false;
	
	g_shopRegistered = true;
	log_amx("Walidacja licencji zostala zakonczona pomyslnie");
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

_canUseShop()
{
	return !g_blocked && g_shopRegistered && get_pcvar_num(cvar_on) && g_sqlConnected;
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
		
	new id[MAX_SERVICE_ID + 1];
	
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
	
	new sms_code[MAX_CODE + 1], tariff;
	get_string(1, sms_code, charsmax(sms_code));
	tariff = get_param(2);
	
	return addCode(sms_code, tariff);
}

// Logowanie danych z pluginow zewnetrznych
public dodajLog(plugin, params)
{	
	#if defined LOG_SQL
	vdformat(g_szTemp, charsmax(g_szTemp), 1, 2);
	log_to_sql(g_szTemp);
	#endif
}

public native_showServicePurchase(plugin, params)
{
	if (params != 2) {
		return SS_BAD_ARGS;
	}
	
	new service_id[MAX_SERVICE_ID + 1];
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
	
	displayInfoSMS(get_param(1));
	return SS_OK;
}

public bool:native_is_steam(plugin, params)
{	
	if (params != 1) {
		return false;
	}
	
	return is_steam(get_param(1));
}
// ################################

// License
_errorUnknown() {
	log_to_file(LOG_FILE, "Error 10 - Wystapil blad podczas odczytywania odpowiedzi od serwera walidujacego licencje. Zobacz logi.");
	g_blocked = true;
}

_errorLicenseInvalidResponse(statusCode) {
	log_to_file(LOG_FILE, "Error 11 - Serwer walidacyjny zwrocil bledny HTTP CODE %d.", statusCode);
	g_blocked = true;
}

_errorValidationError() {
	log_to_file(LOG_FILE, "Error 12 - Walidacja wyslanych danych nie powiodla sie.");
	g_blocked = true;
}

_errorInvalidToken() {
	log_to_file(LOG_FILE, "Error 13 - Bledny token licencji.");
	g_blocked = true;
}

_errorPaymentRequired() {
	_make_error("Error 14 - Licencja nie wspiera tego typu serwera lub przekroczono limit stron WWW.");
}

_errorForbidden(const text[] = "") {
	new message[128 + 1];
	formatex(message, charsmax(message), "Error 15 - Blad licencji. %s", text);
	_make_error(message);
}

// Config
_errorConfigFailed(code) {
	log_to_file(LOG_FILE, "Error 20 - Nie udalo sie pobrac konfiguracji serwera. Error: %d", code);
	g_blocked = true;
}

_errorNoServer() {
	_make_error("Error 21 - Serwer nie znajduje sie nie liscie serwerow na stronie WWW.");
}

_errorOutdatedVersion() {
	_make_error("Error 22 - Obecna wersja pluginu nie jest juz wspierana. Dokonaj aktualizacji pluginu.");
}

_errorConfigInvalidResponse(statusCode) {
	log_to_file(LOG_FILE, "Error 23 - Podczas ladowania konfiguracji, strona WWW zwrocila bledny HTTP code %d.", statusCode);
	g_blocked = true;
}

_errorNoShopUrl() {
	_make_error("Error 24 - Nie podano adresu sklepu w ustawieniach.");
}

// General
_error51() {
	_make_error("Error 51 - Nie udalo sie utworzyc uchwytu do bazy danych.");
}

_make_error(message[]) {
	set_fail_state(message);
}
/* ############# Koniec: Licencja ################## */

/**
 * Make HTTP request
 *
 * @param const char[]	    method			GET POST PUT etc.
 * @param const char[]	    url				path (eg. example.com/shop/ddd)
 * @param const curl_slist	headers			headers
 * @param const char[]	    body			body params
 * @param const char[]	    callback		callback function
 * @param const int		    playerId		id of the player
 * 
 * @return bool
 */
bool:makeRequest(const method[], const url[MAX_URL + 1], const curl_slist: headers, const body[], const callback[MAX_FUNCTION + 1] = "", const playerId = 0)
{
	new CURL: handle, curl_slist: newHeaders, data[requestStruct];

	if (isDebug()) {
		log_amx("Request | %s %s %s", method, url, body);
	}
   	
   	handle = curl_easy_init();
   	if (!handle) {
   		log_to_file(LOG_FILE, "Nie udalo sie utworzyc uchwytu CURL.");
   		return false;
   	}

   	new requestId = g_requestCounter++ % MAX_RESPONSE_COUNT;

   	if (g_requestsInProgress[requestId]) {
   		log_to_file(LOG_FILE, "Pula requestetow jest pelna. Request nie zostal wykonany.");
   		return false;
   	}

	g_requestsInProgress[requestId] = true;
	data[RequestId] = requestId;
	data[RequestPlayerId] = playerId;
	format(data[RequestCallback], MAX_FUNCTION + 1, callback);
   	newHeaders = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded; charset=UTF-8");
   	data[RequestHeaders] = newHeaders;
   	
   	curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 0);
   	curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST, method);
   	curl_easy_setopt(handle, CURLOPT_URL, url);
   	curl_easy_setopt(handle, CURLOPT_USERAGENT, "amxmodx");
   	curl_easy_setopt(handle, CURLOPT_HTTPHEADER, headers);
   	curl_easy_setopt(handle, CURLOPT_COPYPOSTFIELDS, body);
   	curl_easy_setopt(handle, CURLOPT_WRITEDATA, data[RequestId]);
   	curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, "@responseWrite");

   	curl_easy_perform(handle, "@requestComplete", data, requestStruct);

   	return true;
}

@responseWrite(const data[], const size, const nmemb, const requestId)
{
	// We want to get "nmemb" chars from "data", because sometime there is some noise at the end od "data"
	format(g_responses[requestId], min(nmemb, MAX_RESPONSE), data);
    
	// tell curl how many bytes we handled
    return size * nmemb;
}

@requestComplete(CURL: curl, CURLcode: code, const data[requestStruct])
{
    if (code != CURLE_OK) {
        new szError[128];
        curl_easy_strerror(code, szError, charsmax(szError));
        log_to_file(LOG_FILE, "CURL error: %d %s", code, szError);
    }

	new statusCode;
	curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, statusCode);

    runRequestCallback(data[RequestCallback], g_responses[data[RequestId]], data[RequestPlayerId], code, statusCode);
    g_requestsInProgress[data[RequestId]] = false;

    curl_easy_cleanup(curl);
    curl_slist_free_all(data[RequestHeaders]);
}

runRequestCallback(const function[], const httpResponseContent[], playerId, CURLcode: code, statusCode)
{
	if (isDebug()) {
		log_amx("Request response | %d %d %s", code, statusCode, httpResponseContent);
	}

	if (!strlen(function) || callfunc_begin(function) == 1) {
		callfunc_push_str(httpResponseContent);
		callfunc_push_int(code);
		callfunc_push_int(statusCode);
		callfunc_push_int(playerId);
		callfunc_end();
	} else {
		log_to_file(LOG_FILE, "Funkcja nie zostala prawidlowo wywolana [%s]", function);
	}
}

// ----------------------------------------------------- End of requests --------------------------------------------------------

_getServicePluginByID(const id[])
{
	new tmp[MAX_SERVICE_ID + 1];
	for (new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, tmp, charsmax(tmp));
		if (equali(id, tmp)) {
			return ArrayGetCell(service_plugins, i);
		}
	}
	
	return -1;
}

_getServiceByID(const id[])
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

_getNumberByTariff(tariff, output[], len)
{	
	new sms[e_SMS];
	for (new i = 0; i < ArraySize(smses); ++i) {
		ArrayGetArray(smses, i, sms);
		if (tariff == sms[sTARIFF]) {
			copy(output, len, sms[NUMBER]);
			return;
		}
	}
}

bool:isDebug()
{
	return false;
}

// ------------------------------------------------- Versions Compatibility ----------------------------------------------------

vc_md5(const szString[], md5buffer[34])
{
	#if defined hash_string
	hash_string(szString, Hash_Md5, md5buffer, 34);
	#else
	md5(szString, md5buffer);
	#endif
}

// --------------------------------------------------------- Stocks ------------------------------------------------------------

stock bool:is_steam(id)
{	
	new auth[32];
	get_user_authid(id, auth, charsmax(auth));
	if (contain(auth, "STEAM_0:0:") != -1 || contain(auth, "STEAM_0:1:") != -1) {
		return true;
	}
	
	return false;
}

stock escapeQuotes(string[], string_len)
{	
	replace_all(string, string_len, "'", "\'");
}

stock get_sms_cost(const szNumber[])
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

stock extractFieldValue(const text[], const field[], output[], len)
{
	new pattern[64];
	formatex(pattern, charsmax(pattern), "^^%s:(.*)$", field);
	matchRegex(text, pattern, output, len, 1);
}

stock matchRegex(const text[], const pattern[], output[], len, group = 0)
{
	new ret, error[32];
	new Regex:reg = regex_match(text, pattern, ret, error, charsmax(error), "m");
	
	if (reg > REGEX_NO_MATCH) {
		regex_substr(reg, group, output, len);
		regex_free(reg);
	} else {
		log_to_file(LOG_FILE, "Regex error. Pattern: %s, Error: %s, Reg: %d", pattern, error, reg);
	}
}

stock getXMLValue(const szText[], const tag[], output[], len)
{	
	new temp[64], textStart, textEnd;
	
	formatex(temp, charsmax(temp), "<%s>", tag);
	textStart = contain(szText, temp);
	
	formatex(temp, charsmax(temp), "</%s>", tag);
	textEnd = contain(szText, temp);
	
	if (textStart >= 0) {
		new tag_len = 2 + strlen(tag);
		copy(output, min(len, textEnd - textStart - tag_len), szText[textStart + tag_len]);
	}
}

// TODO Does not work nice with polish characters
stock StringURLEncode(const szInput[], szOutput[], const iLen)
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
