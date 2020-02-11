#include <amxmodx>
#include <amxmisc>
#include <sqlx>
#include <curl>
#include <regex>
#include <shop_sms_const>
#include <custom_color_chat>

#pragma semicolon 1
#pragma dynamic 65536

forward amxbans_sql_initialized(Handle:sqlTuple, dbPrefix[]);
forward client_admin(id, flags);
forward amxx_admin_access(id, flags, timestamp);

//#define IS_DEBUG;

#define FLAG_NICK (1<<5)

// ID zadan
#define TASK_KEEP_INFO_SMS 2000
#define TASK_ASSIGN_PLAYER_FLAGS 5000
#define TASK_DISPLAY_LOADING 6000
#define TASK_KEEP_DISPLAYING_MENU 8000

// Klawisze ktore mozna uzyc w menu
#define KEYS (1<<0)|(1<<9) // Keys: 10

// Logowanie danych
new const CFG_FILE[] = "sklep_sms.cfg";
new const LOG_FILE[] = "sklep_sms.log";

const MAX_COMMAND = 32;
const MAX_CONTACT = 64;
const MAX_RANDOM_KEY = 32;
const MAX_FLAGS = 26;
const MAX_SERVER_NAME = 128;
const MAX_SERVICE_TAG = 16;
const MAX_SERVICE_NAME = 32;
const MAX_SMS_TEXT = 32;
const MAX_PASSWORD = 32;
const MAX_DESCRIPTION = 28;
const MAX_CODE = 16;
const MAX_NUMBER = 16;
const MAX_NAME = 32;
const MAX_SID = 18;
const MAX_IP = 15;
const MAX_PORT = 8;
const MAX_FULL_IP = MAX_IP + MAX_PORT + 1; // ip + semicolon + port
const MAX_URL_HOST = 128;
const MAX_URL_PATH = 384;
const MAX_URL = MAX_URL_HOST + MAX_URL_PATH;
const MAX_HEADER = 128;
const MAX_BODY = 384;
const MAX_FUNCTION = 128;
const TYPE_NICK = 1<<0;
const TYPE_IP = 1<<1;
const TYPE_SID = 1<<2;

new bool:g_AmxbansExists = false;

// FORWARDs
new forwrdClientAccess;

// CVARs
new cvar_on, cvar_show_info, cvar_sklep, cvar_przeladuj, cvar_uslugi, cvar_host, cvar_user, cvar_pass, cvar_db, cvar_server_ip, cvar_silent_command;
new show_info;
new Array:g_shopCommands,
	Array:g_serviceListCommands,
	Array:g_reloadCommands;

// MySQL
new const TABLE_PREFIX[] = "ss_";
new Handle:SqlTuple;
new bool:g_sqlConnected = false;
new sql_host[MAX_URL_HOST + 1], sql_user[32], sql_pass[32], sql_db[32];
new const all_flags[MAX_FLAGS + 1] = "abcdefghijklmnopqrstuyvwxz";
new g_szTemp[4096];

// Server
new g_serverIp[MAX_IP + 1],
	g_serverPort[MAX_PORT + 1],
	g_serverName[MAX_SERVER_NAME + 1],
	g_signature,
	g_configPath[128];

// Server config
new g_serverId,
	g_currency[16],
	g_smsPlatformId,
	g_contact[MAX_CONTACT + 1], 
	g_randomKey[MAX_RANDOM_KEY + 1], 
	g_randomKeyMD5[34], 
	g_shopPageUrl[MAX_URL + 1],
	g_smsText[MAX_SMS_TEXT + 1],
	Float:g_vat,
	g_accountsSteamIds[4096] = "",
	g_licenseToken[63];

// License
new bool:g_footer = true,
	bool:g_blocked = false,
	bool:g_validationAttempt = false,
	bool:g_shopRegistered = false;

enum e_Service {
	sID[MAX_SERVICE_ID + 1], 
	PLUGIN, 
	sNAME[MAX_SERVICE_NAME + 1], 
	DESCRIPTION[MAX_DESCRIPTION + 1], 
	TAG[MAX_SERVICE_TAG + 1], 
	FLAGS[MAX_FLAGS + 1], 
	TYPES
};

new Array:service_plugins, 
	Array:service_ids, 
	Array:g_services;

enum e_SMS {
	NUMBER[MAX_NUMBER + 1], 
	PRICE, 
};
new Array:g_smses;

enum e_Price {
	pID,
	pSERVICE_ID[MAX_SERVICE_ID + 1], 
	SMS_PRICE, 
	QUANTITY, 
};
new Array:g_prices;

enum e_PlayerFlags {
	pfPLAYER[33], 
	pfFLAGS, 
	pfPASSWORD[MAX_PASSWORD+2], 
	pfTYPE
};
new Array:g_playersFlags;
new bool:g_playersLoaded = false;
new g_lastReassign;

// Dodatkowe zmienne
new which_service[33], 
	which_price[33], 
	b_passwords[33][MAX_PASSWORD + 1], 
	b_types[33];

// Requests
const MAX_RESPONSE = 4096;
const MAX_REQUESTS_COUNT = 5;
new g_requestCounter = 0,
	g_responses[MAX_REQUESTS_COUNT][MAX_RESPONSE + 1],
	bool:g_requestsInProgress[MAX_REQUESTS_COUNT];

enum requestStruct {
	RequestId,
	curl_slist: RequestHeaders,
	RequestCallback[MAX_FUNCTION + 1],
	RequestPlayerId,
};

public plugin_natives()
{
	register_library("shop_sms");
	register_native("ss_register_service", "native_registerService");
	register_native("ss_show_service_purchase", "native_showServicePurchase");
	register_native("ss_show_sms_info", "native_displaySmsDetails");
	register_native("ss_log", "native_addLog");
	register_native("ss_is_steam", "native_is_steam");
}

public plugin_precache()
{
	get_configsdir(g_configPath, charsmax(g_configPath));
	
	_createShopSmsConfigFile();
	
	cvar_on 	= register_cvar("sklepsms_on", "1");
	cvar_sklep 	= register_cvar("sklepsms_sklep_komenda", "/sklepsms,/shopsms");
	cvar_przeladuj 	= register_cvar("sklepsms_przeladuj_komenda", "/przeladuj");
	cvar_uslugi 	= register_cvar("sklepsms_uslugi_komenda", "/uslugi");
	cvar_show_info 	= register_cvar("sklepsms_info", "1");
	cvar_host 	= register_cvar("sklepsms_host", "localhost");
	cvar_user 	= register_cvar("sklepsms_user", "root");
	cvar_pass 	= register_cvar("sklepsms_pass", "");
	cvar_db 	= register_cvar("sklepsms_db", "");
	cvar_server_ip	= register_cvar("sklepsms_server_ip", "");
	cvar_silent_command	= register_cvar("sklepsms_ciche_komendy", "0");
	
	// Read config
	if (file_exists(g_configPath)) {
		server_cmd("exec %s", g_configPath);
	}
	
	service_plugins = ArrayCreate();
	service_ids = ArrayCreate(MAX_SERVICE_ID + 1);
	
	g_playersFlags = ArrayCreate(e_PlayerFlags);
	g_smses = ArrayCreate(e_SMS);
	g_services = ArrayCreate(e_Service);
	g_prices = ArrayCreate(e_Price);
	g_shopCommands = ArrayCreate(MAX_COMMAND + 1);
	g_serviceListCommands = ArrayCreate(MAX_COMMAND + 1);
	g_reloadCommands = ArrayCreate(MAX_COMMAND + 1);
}

public plugin_init()
{	
	register_plugin("Sklep SMS", VERSION, "SeeK");
	
	register_menucmd(register_menuid("smsDetails"), KEYS, "smsDetails_handler");
	register_concmd("Podaj_Kod_Zwrotny", "onSmsCodeEntered");
	register_concmd("ssnick_Podaj_Haslo", "onNickPasswordEntered");
	register_concmd("ssip_Podaj_Haslo", "onIpPasswordEntered");
	register_concmd("sklepsms_reloaddata", "command_loadPlayersServices");
	register_concmd("sklepsms_reloadusers", "command_reassignPlayersFlags");
	
	register_clcmd("say", "sayHook");
	register_clcmd("say_team", "sayHook");
	
	if (show_info) {
		set_task(137.0, "displayCommercial", _, _, _, "b");
	}

	g_signature = random_num(1, 99999999);
	forwrdClientAccess = CreateMultiForward("ss_client_access", ET_IGNORE, FP_CELL, FP_CELL);
}

public plugin_cfg() {
	// Blad przy tworzeniu (brak uprawnien)
	if (!file_exists(g_configPath)) {
		_invalidPath(0, g_configPath);
	}
		
	// Ponowne wczytywanie confingu
	if (file_exists(g_configPath)) {
		server_cmd("exec %s", g_configPath);
		server_exec();
	}
	
	_loadCvars();
	
	SqlTuple = SQL_MakeDbTuple(sql_host, sql_user, sql_pass, sql_db);
	if (! SqlTuple) {
		_error51();
	}

	#if defined SQL_SetCharset
	SQL_SetCharset(SqlTuple, "utf8mb4");
	#endif
	
	// Get server ip
	new fullIp[MAX_FULL_IP];
	get_pcvar_string(cvar_server_ip, fullIp, charsmax(fullIp));

	// Brak ip w cvarach
	if (!strlen(fullIp)) {
		get_user_ip(0, fullIp, charsmax(fullIp), false);
	}
	
	split(fullIp, g_serverIp, charsmax(g_serverIp), g_serverPort, charsmax(g_serverPort), ":");

	_loadPlayersServices(false);
	_loadSettings();
}

public plugin_end()
{	
	if (SqlTuple) {
		SqlTuple = Empty_Handle;
	}
}

_loadCvars()
{
	get_pcvar_string(cvar_sklep, g_szTemp, charsmax(g_szTemp));
	explode(g_szTemp, ',', g_shopCommands, MAX_COMMAND);

	get_pcvar_string(cvar_przeladuj, g_szTemp, charsmax(g_szTemp));
	explode(g_szTemp, ',', g_reloadCommands, MAX_COMMAND);
	
	get_pcvar_string(cvar_uslugi, g_szTemp, charsmax(g_szTemp));
	explode(g_szTemp, ',', g_serviceListCommands, MAX_COMMAND);
	
	show_info = get_pcvar_num(cvar_show_info);
	
	get_pcvar_string(cvar_host, sql_host, charsmax(sql_host));
	get_pcvar_string(cvar_user, sql_user, charsmax(sql_user));
	get_pcvar_string(cvar_pass, sql_pass, charsmax(sql_pass));
	get_pcvar_string(cvar_db, sql_db, charsmax(sql_db));
}

public client_authorized(id)
{	
	_assignPlayerFlags(id);
}

public client_putinserver(id)
{	
	_assignPlayerFlags(id);
}

public amxbans_sql_initialized()
{	
	g_AmxbansExists = true;
	_reassignPlayersFlags();
}

public client_admin(id, flags)
{
	_assignPlayerFlags(id);
}

public amxx_admin_access(id, flags, timestamp)
{
	_assignPlayerFlags(id);
}

public sayHook(id)
{	
	new text[MAX_COMMAND + 1];
	read_argv(1, text, charsmax(text));
	
	if (_matchCommand(text, g_shopCommands)) {
		_openShopMenu(id);
	}
	else if (_matchCommand(text, g_reloadCommands)) {
		command_reassignPlayersFlags(id);
	}
	else if (_matchCommand(text, g_serviceListCommands)) {
		_showPlayerServices(id);
	}
	
	return get_pcvar_num(cvar_silent_command) ? PLUGIN_HANDLED : PLUGIN_CONTINUE;
}

//
// ----------------------------------------- SERVER CONFIGURATION --------------------------------------------
//

_loadSettings()
{
	formatex(g_szTemp, charsmax(g_szTemp),
		"SELECT * FROM `%ssettings` \
		WHERE `key` IN ('shop_url', 'random_key')",
		TABLE_PREFIX
	);
	SQL_ThreadQuery(SqlTuple, "loadSettingsHandler", g_szTemp);
}

public loadSettingsHandler(FailState, Handle:Query, Error[], Errorcode)
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
	new curl_slist: headers;

	headers = curl_slist_append(headers, "Accept: application/assoc");
	formatex(url, charsmax(url), "%s/api/server/config?key=%s&ip=%s&port=%s&version=%s", g_shopPageUrl, g_randomKeyMD5, g_serverIp, g_serverPort, VERSION);

	if (!makeRequest("GET", url, headers, "", "onLoadServerConfigResponse")) {
		_errorConfigFailed(999);
	}
}

public onLoadServerConfigResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (code != CURLE_OK) {
		_errorConfigFailed(_:code);
		return;
	}

	if (statusCode == 404) {
		_errorNoServer();
		return;
	}

	if (statusCode == 402) {
		_errorOutdatedVersion();
		return;
	}

	if (statusCode >= 300) {
		_log("Invalid server config response HTTP code | %d", statusCode);
		_errorConfigInvalidResponse();
		return;
	}

	if (!getField(content, "license_token", g_licenseToken, charsmax(g_licenseToken))) {
		_log("Invalid server config response | %s", content);
		_errorConfigInvalidResponse();
		return;
	}
	
	_validateLicense();

	getField(content, "id", g_szTemp, charsmax(g_szTemp));
	g_serverId = str_to_num(g_szTemp);
	getField(content, "sms_platform_id", g_szTemp, charsmax(g_szTemp));
	g_smsPlatformId = str_to_num(g_szTemp);
	getField(content, "sms_text", g_smsText, charsmax(g_smsText));
	getField(content, "steam_ids", g_accountsSteamIds, charsmax(g_accountsSteamIds));
	getField(content, "currency", g_currency, charsmax(g_currency));
	getField(content, "contact", g_contact, charsmax(g_contact));
	getField(content, "vat", g_szTemp, charsmax(g_szTemp));
	g_vat = str_to_float(g_szTemp);

	_extractSmsNumbers(content);
	_extractPrices(content);
	_extractServices(content);

	_stopPlugins();
	_checkLoadedServices();
}

_extractSmsNumbers(const content[])
{
	new key[256];

	formatex(key, charsmax(key), "sn.c");
	getField(content, key, g_szTemp, charsmax(g_szTemp));
	new count = str_to_num(g_szTemp);

	for (new i = 0; i < count; ++i) {
		new sms[e_SMS];
		
		formatex(key, charsmax(key), "sn.%d", i);
		getField(content, key, sms[NUMBER], MAX_NUMBER);

		sms[PRICE] = get_sms_cost(sms[NUMBER]);

		ArrayPushArray(g_smses, sms);
	}
}

_extractPrices(const content[])
{
	new key[256];

	formatex(key, charsmax(key), "pr.c");
	getField(content, key, g_szTemp, charsmax(g_szTemp));
	new count = str_to_num(g_szTemp);

	for (new i = 0; i < count; ++i) {
		new price[e_Price];
		
		formatex(key, charsmax(key), "pr.%d.i", i);
		getField(content, key, g_szTemp, charsmax(g_szTemp));
		price[pID] = str_to_num(g_szTemp);
		
		formatex(key, charsmax(key), "pr.%d.s", i);
		getField(content, key, price[pSERVICE_ID], MAX_SERVICE_ID);

		formatex(key, charsmax(key), "pr.%d.p", i);
		getField(content, key, g_szTemp, charsmax(g_szTemp));
		price[SMS_PRICE] = str_to_num(g_szTemp);

		formatex(key, charsmax(key), "pr.%d.q", i);
		getField(content, key, g_szTemp, charsmax(g_szTemp));
		price[QUANTITY] = str_to_num(g_szTemp);

		ArrayPushArray(g_prices, price);
	}
}

_extractServices(const content[])
{
	new key[256];

	formatex(key, charsmax(key), "se.c");
	getField(content, key, g_szTemp, charsmax(g_szTemp));
	new count = str_to_num(g_szTemp);

	for (new i = 0; i < count; ++i) {
		new service[e_Service];
		
		formatex(key, charsmax(key), "se.%d.i", i);
		getField(content, key, service[sID], MAX_SERVICE_ID);
		
		service[PLUGIN] = _getServicePluginByID(service[sID]);
		if (service[PLUGIN] == -1) {
			#if defined IS_DEBUG
			_log("Service plugin was not found | service_id: [%s]", service[sID]);
			#endif
			continue;
		}

		formatex(key, charsmax(key), "se.%d.n", i);
		getField(content, key, service[sNAME], MAX_SERVICE_NAME);

		formatex(key, charsmax(key), "se.%d.d", i);
		getField(content, key, service[DESCRIPTION], MAX_DESCRIPTION);

		formatex(key, charsmax(key), "se.%d.ta", i);
		getField(content, key, service[TAG], MAX_SERVICE_TAG);

		formatex(key, charsmax(key), "se.%d.f", i);
		getField(content, key, service[FLAGS], MAX_FLAGS);

		formatex(key, charsmax(key), "se.%d.ty", i);
		getField(content, key, g_szTemp, charsmax(g_szTemp));
		service[TYPES] = str_to_num(g_szTemp);

		ArrayPushArray(g_services, service);
		
		new ret, forward_handle;
		forward_handle = CreateOneForward(service[PLUGIN], "ss_service_data", FP_STRING, FP_STRING);
		ExecuteForward(forward_handle, ret, service[sNAME], service[FLAGS]);
		DestroyForward(forward_handle);
	}
}

_stopPlugins()
{
	new service_id[MAX_SERVICE_ID + 1];
	
	for (new i = 0; i < ArraySize(service_ids); ++i) {
		ArrayGetString(service_ids, i, service_id, charsmax(service_id));
		new index = _getServiceByID(service_id);

		// Service is inactive or does not exist
		if (index == -1) {
			// Stop the plugin
			new plugin_name[64];
			get_plugin(ArrayGetCell(service_plugins, i), plugin_name, charsmax(plugin_name));
			pause("acd", plugin_name);
			ArrayDeleteItem(service_ids, i);
			ArrayDeleteItem(service_plugins, i);
			i -= 1;
		}
	}
}

//
// --------------------------------------------- PLAYERS FLAGS ------------------------------------------------
//

/**
 * Funkcja wczytujaca z bazy ponownie dane graczy
 */
public command_loadPlayersServices()
{	
	_loadPlayersServices(true);
}

public command_reassignPlayersFlags(id)
{	
	if (g_lastReassign + 10 > get_systime()) {
		client_print_color(id, Red, "^4[%s] ^1Ktos przed chwila przeladowal liste. Odczekaj chwile.", PREFIX);
		return;
	}
	
	g_lastReassign = get_systime();
	_reassignPlayersFlags();

	if (is_user_connected(id)) {
		client_print_color(id, Red, "^4[%s] ^1Prawidlowo przeladowano liste flag wykupionych w sklepiku.", PREFIX);
	}
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
		SQL_ThreadQuery(SqlTuple, "loadPlayersServicesHandler", g_szTemp, data, sizeof data);
	}
}

public loadPlayersServicesHandler(FailState, Handle:Query, Error[], Errorcode, data[], data_size)
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
	
	log_amx("Zaladowano %d uslug graczy.", ArraySize(g_playersFlags));
	g_playersLoaded = true;
	
	if (data[0] && g_AmxbansExists) { // Przeladuj dane w amxbans, a tym samym uruchom komende dodawania danych do tablicy globalnej uprawnien
		server_cmd("amx_reloadadmins");
	}
	else {
		_reassignPlayersFlags();
	}
}

/**
 * Reload players flags and assign them again
 */
_reassignPlayersFlags()
{
	addUsersToGlobalArray();

	for (new i = 1; i <= get_maxplayers(); ++i) {
		if (! is_user_connected(i)) {
			continue;
		}
			
		_assignPlayerFlags(i);
	}
}

/**
 * Funkcja sluzaca do dodania graczy do tablicy globalnej przechowujacej dane uprawnien graczy
 */
public addUsersToGlobalArray()
{
	if (!g_playersLoaded) { // Dane uzytkownikow nie zostaly jeszcze zaladowane
		set_task(0.1, "addUsersToGlobalArray");
		return;
	}

	// We want to persist order on the global admins list!
	// We clone players flags. Then we iterate over admins stored in global admins storage.
	// 1. If there is the same entry in our players flags list and in the global storage,
	// then we join them into one entry and store it in the global_users. User is removed
	// from the local_users. 
	// 2. If entry exists only in the global storage, then we simply copy it to global_users.
	// Now we put local_users and global_users into the global admins storage.

	new Array:local_users, Array:global_users;
	local_users = ArrayCreate(e_PlayerFlags);
	global_users = ArrayCreate(e_PlayerFlags);
	
	for (new i = 0; i < ArraySize(g_playersFlags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(g_playersFlags, i, player_flags);
		ArrayPushArray(local_users, player_flags);
	}
	
	for (new i = 0; i < admins_num(); ++i) {
		new global_player[e_PlayerFlags], global_player_name[33];
		
		admins_lookup(i, AdminProp_Auth, global_player[pfPLAYER], 32);
		copy(global_player_name, charsmax(global_player_name), global_player[pfPLAYER]);
		strtolower(global_player_name);
		
		admins_lookup(i, AdminProp_Password, global_player[pfPASSWORD], MAX_PASSWORD);
		
		global_player[pfTYPE] = admins_lookup(i, AdminProp_Flags);
		global_player[pfFLAGS] = admins_lookup(i, AdminProp_Access);
		
		new l = 0, p = ArraySize(local_users)-1, s;
		while (l <= p) {
			new local_player[e_PlayerFlags];
			s = (l + p) / 2;
			
			ArrayGetArray(local_users, s, local_player);
			strtolower(local_player[pfPLAYER]);
			if (global_player[pfTYPE] == local_player[pfTYPE] && equali(global_player_name, local_player[pfPLAYER])) {
				// Leave global password
				global_player[pfFLAGS] |= local_player[pfFLAGS];
				ArrayPushArray(global_users, global_player);
				ArrayDeleteItem(local_users, s);
				break;
			}
			else if (strcmp(global_player_name, local_player[pfPLAYER]) > 0) {
				l = s + 1;
			}
			else if (
				_getOrderOfType(global_player[pfTYPE]) > _getOrderOfType(local_player[pfTYPE]) &&
				equali(global_player_name, local_player[pfPLAYER])
			) {
				l = s + 1;
			}
			else {
				p = s - 1;
			}
		}
		
		if (p < l) {
			ArrayPushArray(global_users, global_player);
		}
	}

	admins_flush();
	for (new i = 0; i < ArraySize(global_users); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(global_users, i, player_flags);
		admins_push(player_flags[pfPLAYER], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
	for (new i = 0; i < ArraySize(local_users); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(local_users, i, player_flags);
		admins_push(player_flags[pfPLAYER], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
}

public task_assignPlayerFlags(id)
{
	_assignPlayerFlags(id-TASK_ASSIGN_PLAYER_FLAGS);
}

_assignPlayerFlags(id)
{	
	if (! g_playersLoaded) {
		if (! task_exists(TASK_ASSIGN_PLAYER_FLAGS+id)) {
			set_task(0.1, "task_assignPlayerFlags", TASK_ASSIGN_PLAYER_FLAGS+id);
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
		
		if (
			strlen(player_flags[pfPASSWORD]) &&
			!_checkPassword(id, "_pw", player_flags[pfPASSWORD]) &&
			!_checkPassword(id, "_pw2", player_flags[pfPASSWORD]) &&
			!_checkPassword(id, "_pw3", player_flags[pfPASSWORD]) && 
			!_checkPassword(id, "_ss", player_flags[pfPASSWORD])
		) {

			if (player_flags[pfTYPE]&FLAG_KICK) {
				server_cmd("kick #%d ^"Nieprawidlowe haslo^"", get_user_userid(id));
				return;
			}

			// Do not kick the player, instead do not assign him any flags
			continue;
		}
		
		set_user_flags(id, player_flags[pfFLAGS]);

		new ret;
		ExecuteForward(forwrdClientAccess, ret, id, player_flags[pfFLAGS]);
	}
}

_checkPassword(id, const tag[], const valid_password[])
{
	new password[MAX_PASSWORD + 1], password_md5[34];
			
	get_user_info(id, tag, password, charsmax(password));
	vc_md5(password, password_md5);

	return equal(password_md5, valid_password) || equal(password, valid_password);
}

//
// ------------------------------------------------- SHOP MENU ----------------------------------------------------
//

_openShopMenu(id)
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
	
	if (!ArraySize(g_services)) {
		client_print_color(id, Red, "^4[%s] ^1Brak dostepnych uslug do kupienia.", PREFIX);
		return;
	}
	
	if (!g_shopRegistered) {
		client_print_color(id, Red, "^4[%s] ^1Nie udalo sie przeprowadzic walidacji licencji lub wystapil blad w zapytaniu do bazy danych.", PREFIX);
		return;
	}
	
	new menu;
	if (g_footer) {
		menu = menu_create("\rSklep SMS\d napedzany przez\w sklep-sms.pl^n\yWybierz usluge:", "shopMenu_handler");
	} else {
		menu = menu_create("\rSklep SMS^n\yWybierz usluge:", "shopMenu_handler");
	}
		
	new menu_callback = menu_makecallback("shopMenu_callback");
	
	new szText[64], service[e_Service];
	for (new i = 0; i < ArraySize(g_services); ++i) {
		new data[4];
		data[0] = i + 1;
		ArrayGetArray(g_services, i, service);
		
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
	
	// Replace Exit with Wyjdz
	menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
	menu_display(id, menu);
	
	client_print_color(id, Red, "^4[%s] ^1W razie problemow mozesz sie z nami skontaktowac", PREFIX);
	client_print_color(id, Red, "^4[%s] ^1poprzez: ^3%s", PREFIX, g_contact);
}

public shopMenu_callback(id, menu, item)
{	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	return data[1] == ITEM_DISABLED ? ITEM_DISABLED : ITEM_ENABLED;
}

public shopMenu_handler(id, menu, item)
{
	if (!is_user_connected(id) || item == MENU_EXIT) {
		menu_destroy(menu);
		return;
	}
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	_openPricingMenu(id, data[0]-1);
	menu_destroy(menu);
}

_openPricingMenu(id, service_id)
{	
	if (!is_user_connected(id)) {
		return;
	}
		
	new service[e_Service];
	new szText[64], data[3];
	
	ArrayGetArray(g_services, service_id, service);
	formatex(szText, charsmax(szText), "\rSklep SMS^n\yWybierz ilosc %s:", service[sNAME]);
	
	new menu = menu_create(szText, "pricingMenu_handler");
	
	new price[e_Price];
	for (new i = 0; i < ArraySize(g_prices); ++i) {
		ArrayGetArray(g_prices, i, price);
		
		// ID usługi jest inne
		if (!equali(price[pSERVICE_ID], service[sID])) {
			continue;
		}

		// There is no SMS with a given price
		if (_getSmsIndexByPrice(price[SMS_PRICE]) == -1) {
			continue;
		}

		new quantity[32 + 1];
		_getPriceQuantity(i, service_id, quantity, charsmax(quantity));
		
		formatex(szText, charsmax(szText), 
			"\y%s \wza %d.%s %s + VAT\d ( %d.%s %s )", 
			quantity,
			price[SMS_PRICE] / 100,
			two_number_value(price[SMS_PRICE] % 100),
			g_currency,
			floatround(price[SMS_PRICE] * g_vat) / 100, 
			two_number_value(floatround(price[SMS_PRICE] * g_vat) %100),
			g_currency
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
	}
	// Jezeli jest tylko jeden item, przejdz od razu do informacji o smsie
	else if (menu_items(menu) == 1) {
		which_service[id] = service_id;
		which_price[id] = data[1]+data[2];
		_openServiceTypeMenu(id);
	}
	// Zero
	else {
		client_print_color(id, Red, "^4[%s] ^1Brak cennika dla tej uslugi.", PREFIX);
	}
}

public pricingMenu_handler(id, menu, item)
{	
	if (!is_user_connected(id) || item == MENU_EXIT) {
		menu_destroy(menu);
		return;
	}
	
	new data[4], zaccess, callback;
	menu_item_getinfo(menu, item, zaccess, data, sizeof data, _, _, callback);
	
	which_service[id] = data[0] - 1;
	which_price[id] = data[1] + data[2];
	
	_openServiceTypeMenu(id);
	menu_destroy(menu);
}

_openServiceTypeMenu(id)
{
	new service[e_Service];
	ArrayGetArray(g_services, which_service[id], service);
	
	if (service[TYPES] & (TYPE_NICK|TYPE_IP|TYPE_SID)) {	
		// Wyswietlamy menu z wyborem na co chcemy kupic usluge
		new menu = menu_create("Wybierz typ uslugi", "serviceTypeMenu_handler");
		new menu_callback = menu_makecallback("serviceTypeMenu_callback");
	
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

public serviceTypeMenu_callback(id, menu, item)
{	
	new service[e_Service];
	ArrayGetArray(g_services, which_service[id], service);

	switch (item) {
		case 0: return service[TYPES]&TYPE_NICK ? ITEM_ENABLED : ITEM_DISABLED;
		case 1: return service[TYPES]&TYPE_IP ? ITEM_ENABLED : ITEM_DISABLED;
		case 2: return service[TYPES]&TYPE_SID && is_steam(id) ? ITEM_ENABLED : ITEM_DISABLED;
	}
	
	return ITEM_DISABLED;
}

public serviceTypeMenu_handler(id, menu, item)
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

public onNickPasswordEntered(id)
{	
	new szPassword[MAX_PASSWORD + 1];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (!_serviceTypeMenu_checkPass(id, TYPE_NICK, szPassword)) {
		client_cmd(id, "messagemode ssnick_Podaj_Haslo");
	}
}

public onIpPasswordEntered(id)
{
	new szPassword[MAX_PASSWORD + 1];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (! _serviceTypeMenu_checkPass(id, TYPE_IP, szPassword)) {
		client_cmd(id, "messagemode ssip_Podaj_Haslo");
	}
}

bool:_serviceTypeMenu_checkPass(id, type, const szPassword[MAX_PASSWORD + 1])
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

_serviceChosen(id, type = 0, const szPassword[MAX_PASSWORD + 1] = "")
{	
	new service[e_Service], price[e_Price];
	ArrayGetArray(g_services, which_service[id], service);
	ArrayGetArray(g_prices, which_price[id], price);
	copy(b_passwords[id], MAX_PASSWORD, szPassword);
	b_types[id] = type;

	new ret;
	new forward_handle = CreateOneForward(service[PLUGIN], "ss_service_chosen", FP_CELL, FP_CELL);
	ExecuteForward(forward_handle, ret, id, price[QUANTITY]);
	DestroyForward(forward_handle);
	
	if (ret != SS_STOP) {
		_openPaymentMethodMenu(id);
	}
}

_openPaymentMethodMenu(id)
{	
	new menu = menu_create("Wybierz metode platnosci", "paymentMethodMenu_handler");
	new menu_callback = menu_makecallback("paymentMethodMenu_callback");

	menu_additem(menu, "SMS", "", 0, menu_callback);
	menu_additem(menu, "Portfel", "", 0, menu_callback);

	new data[4];
	data[0] = id;
	data[1] = menu;
	
	keepDisplayingMenu(data);
}

public paymentMethodMenu_callback(id, menu, item)
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

public paymentMethodMenu_handler(id, menu, item)
{
	remove_task(TASK_KEEP_DISPLAYING_MENU + id);
	menu_destroy(menu);

	switch (item) {
		case 0: {
			_displaySmsDetails(id);
		}
		case 1: {
			_purchaseService(id, "wallet");
		}
	}
}

_displaySmsDetails(id)
{	
	if (!is_user_connected(id)) {
		return;
	}
	
	new service[e_Service], price[e_Price], sms[e_SMS], quantity[32 + 1];
	ArrayGetArray(g_services, which_service[id], service);
	ArrayGetArray(g_prices, which_price[id], price);

	new sms_index = _getSmsIndexByPrice(price[SMS_PRICE]);
	ArrayGetArray(g_smses, sms_index, sms);

	_getPriceQuantity(which_price[id], which_service[id], quantity, charsmax(quantity));
	
	formatex(g_szTemp, charsmax(g_szTemp), "\rSklep SMS^n^n");
	format(g_szTemp, charsmax(g_szTemp), "%sWybrales/as opcje zakupu %s ^n\wInfo: \y%s", g_szTemp, service[sNAME], quantity);
	format(g_szTemp, charsmax(g_szTemp), 
		"%s^n^n\rW celu dokonania zakupu, wyslij SMSa^n\wO tresci: \y%s^n\wNa numer: \y%s^n\wKoszt: \y%d.%s %s + VAT\d ( %d.%s %s )", 
		g_szTemp,
		g_smsText,
		sms[NUMBER],
		price[SMS_PRICE] / 100,
		two_number_value(price[SMS_PRICE] % 100),
		g_currency,
		floatround(price[SMS_PRICE] * g_vat)/100, 
		two_number_value(floatround(price[SMS_PRICE] * g_vat) % 100),
		g_currency
	);
	format(g_szTemp, charsmax(g_szTemp), "%s^n^n\wPo wyslaniu SMSa poczekaj na kod zwrotny.^nW celu wprowadzenia go, wcisnij: \y1^n^n\wAby wyjsc, wcisnij: \y0", g_szTemp);
	
	keepDisplayingSmsDetails(g_szTemp, TASK_KEEP_INFO_SMS + id);
}

public keepDisplayingSmsDetails(const info[], id)
{	
	id -= TASK_KEEP_INFO_SMS;
	if (!is_user_connected(id)) {
		return;
	}
		
	show_menu(id, KEYS, info, 1, "smsDetails");
	set_task(0.9, "keepDisplayingSmsDetails", id+TASK_KEEP_INFO_SMS, info, strlen(info));
}

public smsDetails_handler(id, key)
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

public onSmsCodeEntered(id)
{	
	if (!is_user_connected(id)) {
		return;
	}
		
	new sms_code[MAX_CODE + 1];
	read_argv(1, sms_code, charsmax(sms_code));
	
	_logActor(id, "Wprowadzono kod: %s", sms_code);
	
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

	_purchaseService(id, "sms", sms_code);
}

_purchaseService(id, const method[], const sms_code[] = "") {
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
		
		new sign[34], sign_body[1 + charsmax(auth_data) + MAX_CODE + charsmax(g_randomKey) + 1];
		new header[MAX_HEADER + 1];

		// Pobieramy dane o usludze
		ArrayGetArray(g_services, which_service[id], service);
		
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
		
		ArrayGetArray(g_prices, which_price[id], price);
	
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
		headers = curl_slist_append(headers, "Accept: application/assoc");
		
		formatex(body, charsmax(body),
			"sign=%s&service_id=%s&type=%d&auth_data=%s&password=%s&method=%s&server_id=%d&payment_platform_id=%d&sms_code=%s&price_id=%d&ip=%s",
			sign, u_service_id, b_types[id], u_auth_data, u_password, method, g_serverId, g_smsPlatformId, u_sms_code, price[pID], ip
		);
		
		formatex(url, charsmax(url), "%s/api/server/purchase?key=%s&language=polish", g_shopPageUrl, g_randomKeyMD5);
	}

	if (!makeRequest("POST", url, headers, body, "onPurchaseServiceResponse", id)) {
		client_print_color(id, Red, "^4[%s] ^1Nie udalo sie wykonac zapytania HTTP.", PREFIX);
	}
}

public onPurchaseServiceResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (!is_user_connected(playerId)) {
		return;
	}

	if (code != CURLE_OK) {
		_log("Zakup nie zostal sfinalizowany z nieznanych powodow. Error: %d", code);
		client_print_color(playerId, Red, "^4[%s] ^1Zakup ^3nie zostal sfinalizowany ^1z nieznanych powodow. Error: %d", PREFIX, code);
		return;
	}

	if (statusCode >= 300) {
		client_print_color(playerId, Red, "^4[%s] ^1Zapytanie zwrocilo bledny HTTP code: %d", PREFIX, statusCode);
		return;
	}
	
	new status[128], text[128];
	getField(content, "status", status, charsmax(status));
	getField(content, "text", text, charsmax(text));
	
	if (strlen(text)) {
		client_print_color(playerId, Red, "^4[%s] ^1%s", PREFIX, text);
	} else {
		log_amx("Invalid response: %s", content);
		client_print_color(playerId, Red, "^4[%s] ^1Wystapil blad. Brak odpowiedzi z serwera.", PREFIX);
	}

	if (equal(status, "warnings")) {
		new szWarnings[256];
		getField(content, "warnings", szWarnings, charsmax(szWarnings));

		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html>\
			<head><meta http-equiv=^"Content-Type^" content=^"text/html^" charset=^"UTF-8^"></head>\
			<body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^">\
			<div style=^"text-align: center; font-size: 22px; font-weight: bold;^">Bledy ktore wystapily przy zakupie uslugi</div>\
			%s\
			<i>Uzyj jeszcze raz tego samego kodu zwrotnego sms</i>.</body>\
			</html>", 
			szWarnings
		);
		show_motd(playerId, g_szTemp, "Bledy przy zakupie uslugi");
	}
	else if (equal(status, "purchased")) {
		_handleServicePurchase(playerId);
	}
}

_handleServicePurchase(id)
{
	new ret, forward_handle, service[e_Service], price[e_Price];
	ArrayGetArray(g_services, which_service[id], service);
	ArrayGetArray(g_prices, which_price[id], price);
	
	forward_handle = CreateOneForward(service[PLUGIN], "ss_service_bought", FP_CELL, FP_CELL);
	ExecuteForward(forward_handle, ret, id, price[QUANTITY]);
	DestroyForward(forward_handle);

	new quantity[32 + 1];
	_getPriceQuantity(which_price[id], which_service[id], quantity, charsmax(quantity));
	
	// Wystapil jakis blad
	if (ret == SS_ERROR) {		
		client_print_color(id, Red, "^4[%s] ^1Wystapil ^3blad ^1podczas kupowania uslugi. Zglos nam to: ^4%s", PREFIX, g_contact);
		_logActor(id, "Wystapil blad podczas kupowania %s - %s; Kwota: %d", service[sNAME], quantity, price[SMS_PRICE]);
		return;
	}
	
	// Info w przypadku usługi na haslo
	if (b_types[id] & (TYPE_NICK | TYPE_IP)) {
		// Ustawienie hasla
		client_cmd(id, "setinfo _ss ^"%s^"", b_passwords[id]);
		
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>Wykupiles/as usluge: <span style=^"color: red^">%s</span><br /><br />\
			Aby usluga dziala, dodaj wpis do pliku <i>config.cfg</>:<br />\
			<span style=^"color: #3399ff^">setinfo _ss ^"%s^"</span><br /><br />\
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
	
	client_print_color(id, Blue, "^4[%s] ^1Prawidlowo kupiono ^4%s^1: %s", PREFIX, service[sNAME], quantity);
	
	// Jezeli usluga ma flagi do ustawienia to wczytujemy ponownie dane z bazy
	if (service[FLAGS]) {
		// Musimy przeladowac z opoznieniem, aby dane uzytkownika zalapaly nowe haslo
		set_task(2.0, "command_loadPlayersServices");
	}
}

_showPlayerServices(id)
{
	if (!is_user_connected(id)) {
		return;
	}
	
	new name[MAX_NAME + 1],	ip[MAX_IP + 1], steam_id[MAX_SID + 1];
	new escaped_name[MAX_NAME * 2 + 1], escaped_ip[MAX_IP * 2 + 1], escaped_steam_id[MAX_SID * 2 + 1];
	
	get_user_name(id, name, charsmax(name));
	get_user_ip(id, ip, charsmax(ip), true);
	get_user_authid(id, steam_id, charsmax(steam_id));

	StringURLEncode(name, escaped_name, charsmax(escaped_name));
	StringURLEncode(ip, escaped_ip, charsmax(escaped_ip));
	StringURLEncode(steam_id, escaped_steam_id, charsmax(escaped_steam_id));

	new url[MAX_URL + 1];
	new curl_slist: headers;

	headers = curl_slist_append(headers, "Accept: application/assoc");
	formatex(
		url, charsmax(url),
		"%s/api/server/user_services?key=%s&server_id=%d&nick=%s&ip=%s&steam_id=%s",
		g_shopPageUrl, g_randomKeyMD5, g_serverId, escaped_name, escaped_ip, escaped_steam_id
	);

	if (makeRequest("GET", url, headers, "", "onShowPlayerServicesResponse", id)) {
		set_task(0.0, "task_displayLoading", TASK_DISPLAY_LOADING + id);
	} else {
		client_print_color(id, Red, "^4[%s] ^1Niestety, nie udalo sie uzyskac informacji o Twoich uslugach.", PREFIX);
	}
}

public onShowPlayerServicesResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (!is_user_connected(playerId)) {
		return;
	}
	
	if (code != CURLE_OK) {
		client_print_color(playerId, Red, "^4[%s] ^1Niestety, nie udalo sie uzyskac informacji o Twoich uslugach. Error: %d", PREFIX, code);
		return;
	}

	if (statusCode >= 300) {
		client_print_color(playerId, Red, "^4[%s] ^1Zapytanie zwrocilo bledny HTTP code: %d.", PREFIX, statusCode);
		return;
	}

	new key[256];
	new menu = menu_create("Twoje obecne uslugi", "showPlayerServices_handler");

	formatex(key, charsmax(key), "c");
	if (!getField(content, key, g_szTemp, charsmax(g_szTemp))) {
		log_amx("Invalid user services response. | %s", content);
	}
	new count = str_to_num(g_szTemp);

	for (new i = 0; i < count; ++i) {
		new service_name[MAX_SERVICE_ID + 1], expire[32 + 1], item_text[128];
		
		formatex(key, charsmax(key), "%d.s", i);
		getField(content, key, service_name, charsmax(service_name));

		formatex(key, charsmax(key), "%d.e", i);
		getField(content, key, expire, charsmax(expire));

		formatex(item_text, charsmax(item_text), "%s - wygasa: %s", service_name, expire);
		menu_additem(menu, item_text);
	}
	
	if (menu_items(menu)) {
		menu_setprop(menu, MPROP_EXITNAME, "Wyjdz");
		menu_display(playerId, menu);
	}
	else {
		new command[MAX_COMMAND + 1];
		_getFirstCommand(g_shopCommands, command, charsmax(command));
		client_print_color(playerId, Red, "^4[%s] ^1Nie masz jeszcze ^3zadnej uslugi^1. Moze czas to zmienic? ;-) Wpisz: ^3%s.", PREFIX, command);
	}
}

public showPlayerServices_handler(id, menu, item)
{	
	menu_destroy(menu);
}

//
// ----------------------------------------------- OTHER ----------------------------------------------------
//

_logActor(id, const format[], any:...)
{
	vformat(g_szTemp, charsmax(g_szTemp), format, 3);
	
	if (is_user_connected(id)) {
		new name[MAX_NAME + 1], ip[MAX_IP + 1], sid[MAX_SID + 1];
		get_user_name(id, name, charsmax(name));
		get_user_ip(id, ip, charsmax(ip), true);
		get_user_authid(id, sid, charsmax(sid));
		log_to_file(LOG_FILE, "%s; %s; %s. %s", name, ip, sid, g_szTemp);
	} else {
		log_to_file(LOG_FILE, "%s", g_szTemp);
	}
}

_log(const format[], any:...)
{
	vformat(g_szTemp, charsmax(g_szTemp), format, 2);
	log_to_file(LOG_FILE, "%s", g_szTemp);
}

public displayCommercial()
{	
	if (get_playersnum() > 1) {
		new command[MAX_COMMAND + 1];
		_getFirstCommand(g_shopCommands, command, charsmax(command));
		client_print_color(0, Red, "^4[%s] ^1Zapraszamy wszystkich do korzystania ze ^3sklepiku! ^1Wystarczy wpisac: ^4%s", PREFIX, command);
	}
}

_createShopSmsConfigFile()
{
	format(g_configPath, charsmax(g_configPath), "%s/%s", g_configPath, CFG_FILE);
	
	if (!file_exists(g_configPath)) {
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
		iLen += formatex(szText[iLen], iMax-iLen, "// Lista komend oddzielonych przecinkiem, ktore mozna wpisac na chacie, w celu wyswietlenia menu sklepiku^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_sklep_komenda ^"/sklepsms,/shopsms^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Lista komend oddzielonych przecinkiem, ktore mozna wpisac na chacie, w celu przeladowania flag wykupionych w sklepiku^n");
		iLen += formatex(szText[iLen], iMax-iLen, "sklepsms_przeladuj_komenda ^"/przeladuj^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Lista komend oddzielonych przecinkiem, ktore mozna wpisac na chacie, aby zobaczyc swoje aktywne uslugi^n");
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
		write_file(g_configPath, szText);
	}
}

//
// ----------------------------------------------- LICENSE ----------------------------------------------------
//

_validateLicense()
{
	new curl_slist: headers;
	new header[MAX_HEADER + 1];
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
		headers = curl_slist_append(headers, "Accept: application/assoc");

		formatex(body, charsmax(body),
			"url=%s:%s&name=%s&version=%s&signature=%d&platform_version=%s",
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
		_log("Licencja nie zostala zwalidowana z nieznanych powodow. Error: %d", code);
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
		getField(content, "text", text, charsmax(text));
		_errorForbidden(text);
		return;
	}

	if (statusCode >= 300) {
		_errorLicenseInvalidResponse(statusCode);
		return;
	}

	new text[32 + 1];
	getField(content, "text", text, charsmax(text));

	if (!equal(text, "ok")) {
		_log("Invalid license validation response | %s", content);
		_errorUnknown();
		return;
	}

	new szSignature[16];
	getField(content, "signature", szSignature, charsmax(szSignature));

	if (str_to_num(szSignature) != g_signature) {
		_errorForbidden();
		return;
	}

	new footer[2];
	getField(content, "footer", footer, charsmax(footer));
	g_footer = str_to_num(footer) ? true : false;

	g_shopRegistered = true;
	log_amx("Walidacja licencji zostala zakonczona pomyslnie.");
}

//
// ------------------------------------------------- HELPERS ----------------------------------------------------
//

_checkForSQLErrors(Handle:Query, FailState, Error[], Errorcode)
{	
	g_sqlConnected = true;
	
	if (FailState != TQUERY_SUCCESS) {
		if (FailState == TQUERY_QUERY_FAILED) {
			_log("Nie mozna polaczyc sie z baza danych.");
		}
		else if (FailState == TQUERY_CONNECT_FAILED) {
			_log("Zapytanie anulowane.");
			g_sqlConnected = false;
		}
		
		_log("Tresc bledu (%d): %s", Errorcode, Error);
		
		SQL_GetQueryString(Query, g_szTemp, charsmax(g_szTemp));
		_log("Zapytanie: %s", g_szTemp);
		
		return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public IgnoreHandle(FailState, Handle:Query, Error[], Errorcode)
{	
	_checkForSQLErrors(Query, FailState, Error, Errorcode);
}

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

_checkLoadedServices()
{	
	if (!ArraySize(g_services)) {
		log_amx("Nie zaladowano zadnych uslug do zakupienia.");
	} else {
		log_amx("Zaladowano %d uslug do zakupienia.", ArraySize(g_services));
	}
}

_invalidPath(id, const path[])
{
	_log("Nie mozna utworzyc pliku/folderu: %s. Prawdopodonbnie brak uprawnien do zapisu. Utworz plik recznie.", path);
	
	if (id) {
		client_print_color(id, Blue, "^4[%s] ^1Wystapil ^3blad ^1przy zapisywaniu ustawien. Prawdopodobnie ^4brak uprawnien^1.", PREFIX);
	}
}

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
	for (new i = 0; i < ArraySize(g_services); ++i) {
		ArrayGetArray(g_services, i, service);
		if (equal(id, service[sID])) {
			return i;
		}
	}
	return -1;
}

_getSmsIndexByPrice(price)
{
	new sms[e_SMS];
	for (new i = 0; i < ArraySize(g_smses); ++i) {
		ArrayGetArray(g_smses, i, sms);
		if (price == sms[PRICE]) {
			return i;
		}
	}

	return -1;
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

_getPriceQuantity(price_index, service_index, output[], len)
{
	new price[e_Price];
	new service[e_Service];

	ArrayGetArray(g_prices, price_index, price);
	ArrayGetArray(g_services, service_index, service);

	if (price[QUANTITY] == -1) {
		formatex(output, len, "Na zawsze");
	}
	else {
		new temp[32 + 1];
		groupDigits(price[QUANTITY], temp, charsmax(temp));
		formatex(output, len, "%s %s", temp, service[TAG]);
	}
}

_canUseShop()
{
	return !g_blocked && g_shopRegistered && get_pcvar_num(cvar_on) && g_sqlConnected;
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

//
// ------------------------------------------------- ERRORS ----------------------------------------------------
//

// License
_errorUnknown() {
	_log("Error 10 - Wystapil blad podczas odczytywania odpowiedzi od serwera walidujacego licencje. Zobacz logi.");
	g_blocked = true;
}

_errorLicenseInvalidResponse(statusCode) {
	_log("Error 11 - Serwer walidacyjny zwrocil bledny HTTP CODE %d.", statusCode);
	g_blocked = true;
}

_errorValidationError() {
	_log("Error 12 - Walidacja wyslanych danych do serwera walidacyjnego nie powiodla sie.");
	g_blocked = true;
}

_errorInvalidToken() {
	_log("Error 13 - Bledny token licencji.");
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
	_log("Error 20 - Nie udalo sie pobrac konfiguracji serwera. Error: %d", code);
	g_blocked = true;
}

_errorNoServer() {
	_make_error("Error 21 - Serwer nie znajduje sie nie liscie serwerow na stronie WWW.");
}

_errorOutdatedVersion() {
	_make_error("Error 22 - Obecna wersja pluginu nie jest juz wspierana. Dokonaj aktualizacji pluginu.");
}

_errorConfigInvalidResponse() {
	_log("Error 23 - Wystapil blad podczas ladowania konfiguracji serwera.");
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

//
// ------------------------------------------------- HTTP Requests ----------------------------------------------------
//

public task_displayLoading(task_id)
{
	new id = task_id - TASK_DISPLAY_LOADING;

	if (is_user_connected(id)) {
		client_print_color(id, Red, "^4[%s] ^1Ladowanie...", PREFIX);
	}
}

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

	#if defined IS_DEBUG
	log_amx("Request | %s %s %s", method, url, body);
	#endif
   	
   	handle = curl_easy_init();
   	if (!handle) {
   		_log("Nie udalo sie utworzyc uchwytu CURL.");
   		return false;
   	}

   	new requestId = g_requestCounter++ % MAX_REQUESTS_COUNT;

   	if (g_requestsInProgress[requestId]) {
   		_log("Pula requestetow jest pelna. Request nie zostal wykonany.");
   		return false;
   	}

	// Clear response array
	setc(g_responses[RequestId], MAX_RESPONSE, 0);
	g_requestsInProgress[requestId] = true;
	data[RequestId] = requestId;
	data[RequestPlayerId] = playerId;
	formatex(data[RequestCallback], MAX_FUNCTION, callback);

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
	new iLen = strlen(g_responses[requestId]);
	new max_length = MAX_RESPONSE - iLen;

	if (max_length < nmemb) {
		_log("Response too big error | %s", data);
	}

	// We want to get "nmemb" chars from "data", because sometime there is some noise at the end od "data"
	formatex(g_responses[requestId][iLen], min(nmemb, max_length), data);

	// Tell curl how many bytes we handled
	return size * nmemb;
}

@requestComplete(CURL: curl, CURLcode: code, const data[requestStruct])
{
	if (code != CURLE_OK) {
		new szError[128];
		curl_easy_strerror(code, szError, charsmax(szError));
		_log("CURL error: %d %s", code, szError);
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
	#if defined IS_DEBUG
	log_amx("Request response | %d %d %s", code, statusCode, httpResponseContent);
	#endif

	if (!strlen(function) || callfunc_begin(function) == 1) {
		callfunc_push_str(httpResponseContent);
		callfunc_push_int(_:code);
		callfunc_push_int(statusCode);
		callfunc_push_int(playerId);
		callfunc_end();
	} else {
		_log("Funkcja nie zostala prawidlowo wywolana [%s]", function);
	}
}


//
// ------------------------------------------------- External Functions ----------------------------------------------------
//
 
public native_registerService(plugin, params)
{	
	if (params != 1) {
		_log("Wystapil blad podczas dodawania uslugi. Bledna ilosc argumentow funkcji ss_register_service");
		return SS_BAD_ARGS;
	}
		
	new id[MAX_SERVICE_ID + 1];
	
	get_string(1, id, charsmax(id));
	
	ArrayPushCell(service_plugins, plugin);
	ArrayPushString(service_ids, id);
	
	return SS_OK;
}

public native_addLog(plugin, params)
{	
	vdformat(g_szTemp, charsmax(g_szTemp), 1, 2);
	log_to_file(LOG_FILE, "%s", g_szTemp);
}

public native_showServicePurchase(plugin, params)
{
	if (params != 2) {
		return SS_BAD_ARGS;
	}
	
	new service_id[MAX_SERVICE_ID + 1];
	new id = get_param(1);
	get_string(2, service_id, charsmax(service_id));
	
	_openPricingMenu(id, _getServiceByID(service_id));
	return SS_OK;
}

public native_displaySmsDetails(plugin, params)
{	
	if (params != 1) {
		return SS_BAD_ARGS;
	}
	
	_displaySmsDetails(get_param(1));
	return SS_OK;
}

public bool:native_is_steam(plugin, params)
{	
	if (params != 1) {
		return false;
	}
	
	return is_steam(get_param(1));
}

//
// ------------------------------------------------- Versions Compatibility ----------------------------------------------------
//

vc_md5(const szString[], md5buffer[34])
{
	#if defined hash_string
	hash_string(szString, Hash_Md5, md5buffer, 34);
	#else
	md5(szString, md5buffer);
	#endif
}

// --------------------------------------------------------- Stocks ------------------------------------------------------------

stock bool:_matchCommand(const text[], Array:commands)
{
	for (new i = 0; i < ArraySize(commands); ++i) {
		new command[MAX_COMMAND + 1];
		ArrayGetString(commands, i, command, charsmax(command));

		if (equali(text, command)) {
			return true;
		}
	}

	return false;
}

stock _getFirstCommand(Array:commands, output[], maxlen)
{
	if (ArraySize(commands) == 0) {
		formatex(output, maxlen, "");
	} else {
		ArrayGetString(commands, 0, output, maxlen);
	}
}

stock bool:is_steam(id)
{	
	new auth[32];
	get_user_authid(id, auth, charsmax(auth));
	if (contain(auth, "STEAM_0:0:") != -1 || contain(auth, "STEAM_0:1:") != -1) {
		return true;
	}
	
	return false;
}

stock get_sms_cost(const number[])
{	
	if (strlen(number) < 4) {
		return 0;
	}
	
	if (number[0] == '7') {
		new temp[4];
		formatex(temp, charsmax(temp), "%c", number[1]);
		return number[1] == '0' ? 50 : str_to_num(temp) * 100;
	}
	
	if (number[0] == '9') {
		new temp[4];
		formatex(temp, charsmax(temp), "%c%c", number[1], number[2]);
		return str_to_num(temp) * 100;
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

stock getField(const text[], const field[], output[], len)
{
	new pattern[64];
	formatex(pattern, charsmax(pattern), "^^%s:(.*)$", field);
	return matchRegex(text, pattern, output, len, 1);
}

stock matchRegex(const text[], const pattern[], output[], len, group = 0)
{
	new ret, error[32];
	new Regex:reg = regex_match(text, pattern, ret, error, charsmax(error), "m");
	
	if (reg > REGEX_NO_MATCH) {
		regex_substr(reg, group, output, len);
		regex_free(reg);
		return true;
	}
	
	_log("Regex error. Pattern: %s, Error: %s, Reg: %d", pattern, error, reg);
	return false;
}

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

/**
 * https://amxx.pl/topic/43223-explode/
 */
stock explode(const string[], const character, Array:output, maxlen)
{
	new len = strlen(string);
	new oLen = 0;
	
	while (oLen < len)
	{
		new text[128 + 1];
		oLen += (1 + copyc(text, maxlen, string[oLen], character));
		ArrayPushString(output, text);
	}
}
