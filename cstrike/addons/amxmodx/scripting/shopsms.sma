#include <amxmodx>
#include <amxmisc>
#include <curl>
#include <nvault>
#include <shopsms_const>
#include <custom_color_chat>

#pragma semicolon 1
#pragma dynamic 131072

forward amxbans_sql_initialized(Handle:sqlTuple, dbPrefix[]);
forward client_admin(id, flags);
forward amxx_admin_access(id, flags, timestamp);

//#define IS_DEBUG;

#define FLAG_NICK (1<<5)

// Tasks ID
#define TASK_KEEP_INFO_SMS 2000
#define TASK_DISPLAY_LOADING 6000
#define TASK_KEEP_DISPLAYING_MENU 8000

// Available menu keys
#define KEYS (1<<0)|(1<<9) // Keys: 10

// LOGS
new const CFG_FILE[] = "shopsms.cfg";
new const LOG_FILE[] = "shopsms.log";

const MAX_COMMAND = 32;
const MAX_CONTACT = 64;
const MAX_FLAGS = 26;
const MAX_SERVER_NAME = 128;
const MAX_SERVICE_TAG = 16;
const MAX_SERVICE_NAME = 32;
const MAX_SMS_TEXT = 32;
const MAX_PASSWORD = 32;
const MAX_DESCRIPTION = 28;
const MAX_CODE = 16;
const MAX_NUMBER = 16;
const MAX_AUTH_DATA = 32;
const MAX_NAME = 32;
const MAX_SID = 34;
const MAX_IP = 15;
const MAX_PORT = 8;
const MAX_SHOP_TOKEN = 32;
const MAX_FULL_IP = MAX_IP + MAX_PORT + 1; // ip + semicolon + port
const MAX_URL_HOST = 128;
const MAX_URL_PATH = 384;
const MAX_URL = MAX_URL_HOST + MAX_URL_PATH;
const MAX_HEADER = 128;
const MAX_BODY = 384;
const MAX_FUNCTION = 128;
const MAX_CONFIG_KEY = 64;
const MAX_NUMBER_LENGTH = 32;

const TYPE_NICK = 1<<0;
const TYPE_IP = 1<<1;
const TYPE_SID = 1<<2;

new g_szTemp[16384];

// nVault
new g_vaultHandle;
new const VAULT_PLAYER_FLAGS_KEY[] = "player_flags";

// FORWARDs
new forwrdClientAccess;

// CVARs
new g_cvarOn,
	g_cvarCommercial,
	g_cvarShopCommands,
	g_cvarReloadCommands,
	g_cvarServicesCommands,
	g_cvarSilentCommands,
	g_cvarShopUrl,
	g_cvarShopToken;

new Trie:g_shopCommands,
	Trie:g_serviceListCommands,
	Trie:g_reloadCommands;

// Server
new g_serverIp[MAX_IP + 1],
	g_serverPort[MAX_PORT + 1],
	g_serverName[MAX_SERVER_NAME + 1],
	g_signature,
	g_configPath[128];

// Server config
new g_currency[16],
	g_contact[MAX_CONTACT + 1],
	g_smsText[MAX_SMS_TEXT + 1],
	Float:g_vat,
	Trie:g_accountsSteamIds,
	g_licenseToken[63];

// License
new bool:g_footer = true,
	bool:g_blocked = false,
	bool:g_validationAttempt = false,
	bool:g_licenseValidated = false;

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
	DISCOUNT, 
};
new Array:g_prices;

enum e_PlayerFlags {
	pfAUTH[MAX_AUTH_DATA+1], 
	pfFLAGS, 
	pfPASSWORD[MAX_PASSWORD+1], 
	pfTYPE
};
new Array:g_playersFlags;
new bool:g_playersLoaded = false;
new g_lastReassign;

// Purchase additional variables
new which_service[33], 
	which_price[33], 
	b_passwords[33][MAX_PASSWORD + 1], 
	b_types[33];

// Requests
const MAX_RESPONSE = 16384;
const MAX_REQUESTS_COUNT = 4;
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
	register_library("shopsms");
	register_native("ss_register_service", "native_registerService");
	register_native("ss_show_service_purchase", "native_showServicePurchase");
	register_native("ss_open_payment_method_menu", "native_openPaymentMethodMenu");
	register_native("ss_log", "native_addLog");
	register_native("ss_is_steam", "native_is_steam");
}

public plugin_precache()
{
	get_configsdir(g_configPath, charsmax(g_configPath));
	
	_createShopSmsConfigFile();
	
	g_cvarOn = register_cvar("shopsms_on", "1");
	g_cvarShopCommands = register_cvar("shopsms_shop_commands", "/sklepsms,/shopsms");
	g_cvarReloadCommands = register_cvar("shopsms_reload_commands", "/przeladuj");
	g_cvarServicesCommands = register_cvar("shopsms_services_commands", "/uslugi");
	g_cvarCommercial = register_cvar("shopsms_commercial", "137");
	g_cvarShopUrl = register_cvar("shopsms_url", "");
	g_cvarShopToken = register_cvar("shopsms_token", "");
	g_cvarSilentCommands = register_cvar("shopsms_silent_commands", "0");
	
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
	g_shopCommands = TrieCreate();
	g_serviceListCommands = TrieCreate();
	g_reloadCommands = TrieCreate();
	g_accountsSteamIds = TrieCreate();
}

public plugin_init()
{
	register_plugin("Shop SMS", VERSION, "SeeK");
	
	register_dictionary("shopsms.txt");

	register_menucmd(register_menuid("smsDetails"), KEYS, "smsDetails_handler");
	register_concmd("Podaj_Kod_Zwrotny", "onSmsCodeEntered");
	register_concmd("ssnick_Password", "onNickPasswordEntered");
	register_concmd("ssip_Password", "onIpPasswordEntered");
	register_concmd("ss_reload", "command_reloadServerConfig");
	register_concmd("ss_reload_players_flags", "command_reloadPlayersFlags");
	register_concmd("ss_reassign_players_flags", "command_reassignPlayersFlags");
	
	register_clcmd("say", "sayHook");
	register_clcmd("say_team", "sayHook");
	
	new Float:time = get_pcvar_float(g_cvarCommercial);
	if (time) {
		set_task(get_pcvar_float(g_cvarCommercial), "displayCommercial");
	}

	g_signature = random_num(1, 99999999);
	forwrdClientAccess = CreateMultiForward("ss_client_access", ET_IGNORE, FP_CELL, FP_CELL);

	g_vaultHandle = nvault_open("shopsms");
	if (g_vaultHandle == INVALID_HANDLE) {
		_log("Couldn't open 'shopsms' nvault.");
	}
}

public plugin_cfg()
{
	if (file_exists(g_configPath)) {
		// Read config once again
		server_cmd("exec %s", g_configPath);
		server_exec();
	} else {
		// File was not created (probably due to invalid permissions)
		_log("Couldn't create the file: %s. Probably due to lack of permissions. Create the file manually.", g_configPath);
	}

	new shop_url[MAX_URL + 1], shop_token[MAX_SHOP_TOKEN + 1];

	_getShopToken(shop_token, charsmax(shop_token));
	_getShopUrl(shop_url, charsmax(shop_url));

	if (!strlen(shop_url) || !strlen(shop_token)) {
		_errorNoShopCreds();
		return;
	}
	
	_loadCvars();
	
	// Get server ip
	new full_ip[MAX_FULL_IP];
	get_user_ip(0, full_ip, charsmax(full_ip), false);
	split(full_ip, g_serverIp, charsmax(g_serverIp), g_serverPort, charsmax(g_serverPort), ":");

	_loadServerConfig();
	_restorePlayerFlagsFromVault();
}

public plugin_end()
{
	nvault_close(g_vaultHandle);
	TrieDestroy(g_shopCommands);
	TrieDestroy(g_serviceListCommands);
	TrieDestroy(g_reloadCommands);
	TrieDestroy(g_accountsSteamIds);
}

_loadCvars()
{
	get_pcvar_string(g_cvarShopCommands, g_szTemp, charsmax(g_szTemp));
	_explodeCommands(g_szTemp, g_shopCommands);

	get_pcvar_string(g_cvarReloadCommands, g_szTemp, charsmax(g_szTemp));
	_explodeCommands(g_szTemp, g_reloadCommands);
	
	get_pcvar_string(g_cvarServicesCommands, g_szTemp, charsmax(g_szTemp));
	_explodeCommands(g_szTemp, g_serviceListCommands);
}

public client_authorized(id)
{
	#if defined IS_DEBUG
	if (!g_playersLoaded) {
		_log("Player [%d] joined before server config was loaded. It may result in a lack of proper permissions.", id);
	}
	#endif

	new access = _assignPlayerFlags(id);
	
	if (access) {
		new name[MAX_NAME + 1], steam_id[MAX_SID + 1], ip[MAX_IP + 1], flags[MAX_FLAGS + 1];
		get_user_name(id, name, charsmax(name));
		get_user_authid(id, steam_id, charsmax(steam_id));
		get_user_ip(id, ip, charsmax(ip), true);
		get_flags(access, flags, charsmax(flags));
		log_amx("User: ^"%s<%d><%s><%s>^" was given an access ^"%s^"", name, get_user_userid(id), steam_id, ip, flags);
	}
}

public amxbans_sql_initialized()
{
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
	strtolower(text);
	
	if (TrieKeyExists(g_shopCommands, text)) {
		_openShopMenu(id);
	}
	else if (TrieKeyExists(g_reloadCommands, text)) {
		_sayCommand_reassignPlayersFlags(id);
	}
	else if (TrieKeyExists(g_serviceListCommands, text)) {
		_showPlayerServices(id);
	}
	
	return get_pcvar_num(g_cvarSilentCommands) ? PLUGIN_HANDLED : PLUGIN_CONTINUE;
}

//
// ----------------------------------------- SERVER CONFIGURATION --------------------------------------------
//

_loadServerConfig()
{
	new shop_url[MAX_URL + 1], shop_token[MAX_SHOP_TOKEN + 1], url[MAX_URL + 1];
	new curl_slist: headers;

	_getShopUrl(shop_url, charsmax(shop_url));
	_getShopToken(shop_token, charsmax(shop_token));

	headers = curl_slist_append(headers, "Accept: application/assoc");
	formatex(url, charsmax(url), "%s/api/server/config?token=%s&version=%s&language=english", shop_url, shop_token, VERSION);

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

	if (statusCode == 400) {
		_errorInvalidServerToken();
		return;
	}

	if (statusCode == 402) {
		_errorOutdatedVersion();
		return;
	}

	if (statusCode >= 300) {
		_log("Invalid server config response HTTP code [%d]", statusCode);
		_errorConfigInvalidResponse();
		return;
	}

	new Trie:dict = _createResponseDict(content);

	if (!TrieGetString(dict, "license_token", g_licenseToken, charsmax(g_licenseToken))) {
		_log("Invalid server config response | %s", content);
		_errorConfigInvalidResponse();
		TrieDestroy(dict);
		return;
	}
	
	// Do not validate twice, in case of reloading server config
	if (!g_licenseValidated) {
		_validateLicense();
	}

	TrieGetString(dict, "sms_text", g_smsText, charsmax(g_smsText));
	TrieGetString(dict, "currency", g_currency, charsmax(g_currency));
	TrieGetString(dict, "contact", g_contact, charsmax(g_contact));
	TrieGetTextFloat(dict, "vat", g_vat);

	TrieGetString(dict, "steam_ids", g_szTemp, charsmax(g_szTemp));

	TrieClear(g_accountsSteamIds);
	new cur_len = 0, max_len = strlen(g_szTemp);
	while (cur_len < max_len)
	{
		new steam_id[MAX_SID + 1];
		cur_len += copyc(steam_id, charsmax(steam_id), g_szTemp[cur_len], ';') + 1;
		strtolower(steam_id);
		trim(steam_id);

		if (strlen(steam_id)) {
			TrieSetCell(g_accountsSteamIds, steam_id, 1);
		}
	}
	
	_extractSmsNumbers(dict);
	_extractPrices(dict);
	_extractServices(dict);
	_extractPlayersFlags(dict);
	
	TrieDestroy(dict);

	_stopPlugins();
	_checkLoadedPlayersFlags();
	_checkLoadedServices();
	_storePlayerFlagsDump();
}

_extractSmsNumbers(Trie:dict)
{
	new count, key[MAX_CONFIG_KEY + 1];

	if (!TrieGetTextInt(dict, "sn.c", count)) {
		_log("Invalid sms numbers dictionary.");
		return;
	}

	ArrayClear(g_smses);

	for (new i = 0; i < count; ++i) {
		new sms[e_SMS];
		
		formatex(key, charsmax(key), "sn.%d", i);
		TrieGetString(dict, key, sms[NUMBER], MAX_NUMBER);

		sms[PRICE] = get_sms_cost(sms[NUMBER]);

		ArrayPushArray(g_smses, sms);
	}
}

_extractPrices(Trie:dict)
{
	new count, key[MAX_CONFIG_KEY + 1];

	if (!TrieGetTextInt(dict, "pr.c", count)) {
		_log("Invalid prices dictionary.");
		return;
	}

	ArrayClear(g_prices);

	for (new i = 0; i < count; ++i) {
		new price[e_Price];
		
		formatex(key, charsmax(key), "pr.%d.i", i);
		TrieGetTextInt(dict, key, price[pID]);
		
		formatex(key, charsmax(key), "pr.%d.s", i);
		TrieGetString(dict, key, price[pSERVICE_ID], MAX_SERVICE_ID);

		formatex(key, charsmax(key), "pr.%d.p", i);
		TrieGetTextInt(dict, key, price[SMS_PRICE]);

		formatex(key, charsmax(key), "pr.%d.q", i);
		TrieGetTextInt(dict, key, price[QUANTITY]);

		formatex(key, charsmax(key), "pr.%d.d", i);
		TrieGetTextInt(dict, key, price[DISCOUNT]);

		ArrayPushArray(g_prices, price);
	}
}

_extractServices(Trie:dict)
{
	new count, key[MAX_CONFIG_KEY + 1];

	if (!TrieGetTextInt(dict, "se.c", count)) {
		_log("Invalid services dictionary.");
		return;
	}

	ArrayClear(g_services);

	for (new i = 0; i < count; ++i) {
		new service[e_Service];
		
		formatex(key, charsmax(key), "se.%d.i", i);
		TrieGetString(dict, key, service[sID], MAX_SERVICE_ID);
		
		service[PLUGIN] = _getServicePluginByID(service[sID]);
		if (service[PLUGIN] == -1) {
			#if defined IS_DEBUG
			_log("Service plugin was not found | service_id: [%s]", service[sID]);
			#endif
			continue;
		}

		formatex(key, charsmax(key), "se.%d.n", i);
		TrieGetString(dict, key, service[sNAME], MAX_SERVICE_NAME);

		formatex(key, charsmax(key), "se.%d.d", i);
		TrieGetString(dict, key, service[DESCRIPTION], MAX_DESCRIPTION);

		formatex(key, charsmax(key), "se.%d.ta", i);
		TrieGetString(dict, key, service[TAG], MAX_SERVICE_TAG);

		formatex(key, charsmax(key), "se.%d.f", i);
		TrieGetString(dict, key, service[FLAGS], MAX_FLAGS);

		formatex(key, charsmax(key), "se.%d.ty", i);
		TrieGetTextInt(dict, key, service[TYPES]);

		ArrayPushArray(g_services, service);
		
		new ret, forward_handle;
		forward_handle = CreateOneForward(service[PLUGIN], "ss_service_data", FP_STRING, FP_STRING);
		ExecuteForward(forward_handle, ret, service[sNAME], service[FLAGS]);
		DestroyForward(forward_handle);
	}
}

_extractPlayersFlags(Trie:dict)
{
	new count, key[MAX_CONFIG_KEY + 1];

	if (!TrieGetTextInt(dict, "pf.c", count)) {
		_log("Invalid players flags dictionary.");
		return;
	}

	ArrayClear(g_playersFlags);

	for (new i = 0; i < count; ++i) {
		new player_flags[e_PlayerFlags], flags[MAX_FLAGS + 1], type;
		
		formatex(key, charsmax(key), "pf.%d.t", i);
		TrieGetTextInt(dict, key, type);

		formatex(key, charsmax(key), "pf.%d.a", i);
		TrieGetString(dict, key, player_flags[pfAUTH], MAX_AUTH_DATA);

		formatex(key, charsmax(key), "pf.%d.p", i);
		TrieGetString(dict, key, player_flags[pfPASSWORD], MAX_PASSWORD);

		formatex(key, charsmax(key), "pf.%d.f", i);
		TrieGetString(dict, key, flags, charsmax(flags));

		for (new i = 0; i < strlen(flags); ++i) {
			player_flags[pfFLAGS] |= read_flags(flags[i]);
		}
		
		switch (type) {
			case TYPE_SID: player_flags[pfTYPE] = FLAG_AUTHID|FLAG_NOPASS;
			case TYPE_IP: player_flags[pfTYPE] = FLAG_IP;
			default: player_flags[pfTYPE] = FLAG_NICK|FLAG_KICK;
		}

		if (player_flags[pfFLAGS] != 0) {
			ArrayPushArray(g_playersFlags, player_flags);
		}
	}

	g_playersLoaded = true;
	_reassignPlayersFlags();
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
			server_print("Stop %s", plugin_name);
			pause("acd", plugin_name);
			ArrayDeleteItem(service_ids, i);
			ArrayDeleteItem(service_plugins, i);
			i -= 1;
		}
	}
}

/**
 * Load players flags from API
 */
public loadPlayersFlags()
{
	new shop_url[MAX_URL + 1], shop_token[MAX_SHOP_TOKEN + 1], url[MAX_URL + 1];
	new curl_slist: headers;

	_getShopUrl(shop_url, charsmax(shop_url));
	_getShopToken(shop_token, charsmax(shop_token));

	headers = curl_slist_append(headers, "Accept: application/assoc");
	formatex(url, charsmax(url), "%s/api/server/players_flags?token=%s&language=english", shop_url, shop_token);
	makeRequest("GET", url, headers, "", "onLoadPlayersFlagsResponse");
}

public onLoadPlayersFlagsResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (code != CURLE_OK) {
		return;
	}

	if (statusCode == 400) {
		_errorInvalidServerToken();
		return;
	}

	if (statusCode >= 300) {
		_log("Invalid players flags response HTTP code | %d", statusCode);
		return;
	}

	new Trie:dict = _createResponseDict(content);
	_extractPlayersFlags(dict);
	TrieDestroy(dict);

	_storePlayerFlagsDump();
}

Trie:_createResponseDict(const content[])
{
	new Trie:dict = TrieCreate();
	new cur_len = 0, max_len = strlen(content);

	while (cur_len < max_len)
	{
		new key[MAX_CONFIG_KEY + 1];

		cur_len += copyc(g_szTemp, charsmax(g_szTemp), content[cur_len], '^n') + 1;
		new position = copyc(key, charsmax(key), g_szTemp, ':') + 1;
		
		if (strlen(key)) {
			TrieSetString(dict, key, g_szTemp[position]);
		}
	}

	return dict;
}

//
// --------------------------------------------- PLAYERS FLAGS ------------------------------------------------
//

public command_reloadServerConfig()
{
	_loadServerConfig();
	log_amx("Server config has been reloaded.");
}

public command_reloadPlayersFlags()
{
	loadPlayersFlags();
	log_amx("Players flags have been reloaded.");
}

public command_reassignPlayersFlags()
{
	g_lastReassign = get_systime();
	_reassignPlayersFlags();
	log_amx("Players flags have been reassigned.");
}

_sayCommand_reassignPlayersFlags(id)
{
	if (g_lastReassign + 10 > get_systime()) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "FLAGS_RELOADED_RECENTLY");
		return;
	}
	
	g_lastReassign = get_systime();
	_reassignPlayersFlags();

	client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "FLAGS_RELOADED");
}

/**
 * Reload players flags and assign them again
 */
_reassignPlayersFlags()
{
	_addUsersToGlobalArray();

	for (new i = 1; i <= get_maxplayers(); ++i) {
		if (is_user_connected(i)) {
			_assignPlayerFlags(i);
		}
	}
}

/**
 * Add players flags to global array storing players' access.
 */
_addUsersToGlobalArray()
{
	if (!g_playersLoaded) {
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
		
		admins_lookup(i, AdminProp_Auth, global_player[pfAUTH], MAX_AUTH_DATA);
		copy(global_player_name, charsmax(global_player_name), global_player[pfAUTH]);
		strtolower(global_player_name);
		
		admins_lookup(i, AdminProp_Password, global_player[pfPASSWORD], MAX_PASSWORD);
		
		global_player[pfTYPE] = admins_lookup(i, AdminProp_Flags);
		global_player[pfFLAGS] = admins_lookup(i, AdminProp_Access);

		// It is important to have sorted list of users, since we use binary search here
		// to achieve O(nlogn) instead of O(n)
		
		new l = 0, p = ArraySize(local_users)-1, s;
		while (l <= p) {
			new local_player[e_PlayerFlags];
			s = (l + p) / 2;
			
			ArrayGetArray(local_users, s, local_player);
			strtolower(local_player[pfAUTH]);
			if (global_player[pfTYPE] == local_player[pfTYPE] && equali(global_player_name, local_player[pfAUTH])) {
				// Leave global password
				global_player[pfFLAGS] |= local_player[pfFLAGS];
				ArrayPushArray(global_users, global_player);
				ArrayDeleteItem(local_users, s);
				break;
			}
			else if (strcmp(global_player_name, local_player[pfAUTH]) > 0) {
				l = s + 1;
			}
			else if (
				_getOrderOfType(global_player[pfTYPE]) > _getOrderOfType(local_player[pfTYPE]) &&
				equali(global_player_name, local_player[pfAUTH])
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
		admins_push(player_flags[pfAUTH], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
	for (new i = 0; i < ArraySize(local_users); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(local_users, i, player_flags);
		admins_push(player_flags[pfAUTH], player_flags[pfPASSWORD], player_flags[pfFLAGS], player_flags[pfTYPE]);
	}
}

_assignPlayerFlags(id)
{	
	if (!g_playersLoaded) {
		return 0;
	}

	new access = 0;
	
	for (new i = 0; i < ArraySize(g_playersFlags); ++i) {
		new player_flags[e_PlayerFlags];
		ArrayGetArray(g_playersFlags, i, player_flags);
		
		if (player_flags[pfTYPE] & FLAG_NICK) {
			new name[MAX_NAME + 1];
			get_user_name(id, name, charsmax(name));
			if (! equali(name, player_flags[pfAUTH])) {
				continue;
			}
		}
		else if (player_flags[pfTYPE] & FLAG_IP) {
			new ip[MAX_IP + 1];
			get_user_ip(id, ip, charsmax(ip), true);
			if (! equali(ip, player_flags[pfAUTH])) {
				continue;
			}
		}
		else if (player_flags[pfTYPE] & FLAG_AUTHID) {			
			new sid[MAX_SID + 1], arr_sid[MAX_SID + 1];
			copy(arr_sid, charsmax(arr_sid), player_flags[pfAUTH]);
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
				server_cmd("kick #%d ^"%L^"", get_user_userid(id), id, "INVALID_PASSWORD");
				return 0;
			}

			// Do not kick the player, instead do not assign him any flags
			continue;
		}

		access |= player_flags[pfFLAGS];
	}

	if (access) {
		set_user_flags(id, access);
		
		new ret;
		ExecuteForward(forwrdClientAccess, ret, id, access);
	}

	return access;
}

_checkPassword(id, const tag[], const valid_password[])
{
	new password[MAX_PASSWORD + 1], password_md5[34];
			
	get_user_info(id, tag, password, charsmax(password));
	vc_md5(password, password_md5);

	return equal(password_md5, valid_password) || equal(password, valid_password);
}

//
// ----------------------------------------------- CONFIG VAULT ---------------------------------------------------
//

_storePlayerFlagsDump()
{
	new iLen = 0, iMax = charsmax(g_szTemp);

	iLen += formatex(g_szTemp[iLen], iMax-iLen, "pf.c:%d^n", ArraySize(g_playersFlags));

	for (new i = 0; i < ArraySize(g_playersFlags); ++i) {
		new player_flags[e_PlayerFlags], flags[MAX_FLAGS + 1], type;

		ArrayGetArray(g_playersFlags, i, player_flags);
		get_flags(player_flags[pfFLAGS], flags, charsmax(flags));

		if (player_flags[pfTYPE] & FLAG_AUTHID) {
			type = TYPE_SID;
		} else if (player_flags[pfTYPE] & FLAG_IP) {
			type = TYPE_IP;
		} else {
			type = TYPE_NICK;
		}

		iLen += formatex(g_szTemp[iLen], iMax-iLen, "pf.%d.t:%d^n", i, type);
		iLen += formatex(g_szTemp[iLen], iMax-iLen, "pf.%d.a:%s^n", i, player_flags[pfAUTH]);
		iLen += formatex(g_szTemp[iLen], iMax-iLen, "pf.%d.p:%s^n", i, player_flags[pfPASSWORD]);
		iLen += formatex(g_szTemp[iLen], iMax-iLen, "pf.%d.f:%s^n", i, flags);
	}

	nvault_set(g_vaultHandle, VAULT_PLAYER_FLAGS_KEY, g_szTemp);
}

_restorePlayerFlagsFromVault()
{
	nvault_get(g_vaultHandle, VAULT_PLAYER_FLAGS_KEY, g_szTemp, charsmax(g_szTemp));

	if (strlen(g_szTemp)) {
		new Trie:dict = _createResponseDict(g_szTemp);
		_extractPlayersFlags(dict);
		TrieDestroy(dict);
	}
}

//
// ------------------------------------------------- SHOP MENU ----------------------------------------------------
//

_openShopMenu(id)
{
	if (!is_user_connected(id)) {
		return;
	}

	if (!get_pcvar_num(g_cvarOn)) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "SHOP_IS_DISABLED");
		return;
	}

	if (g_blocked) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "SHOP_IS_BLOCKED");
	}

	if (!ArraySize(g_services)) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "NO_AVAILABLE_SERVICE");
		return;
	}

	if (!g_licenseValidated) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "LICENSE_VALIDATION_FAILED");
		return;
	}

	new menu_title[64];
	if (g_footer) {
		formatex(menu_title, charsmax(menu_title), "\r%L\d powered by\w sklep-sms.pl^n\y%L", id, "SHOP_SMS", id, "CHOOSE_SERVICE");
	} else {
		formatex(menu_title, charsmax(menu_title), "\r%L^n\y%L", id, "SHOP_SMS", id, "CHOOSE_SERVICE");
	}

	new menu = menu_create(menu_title, "shopMenu_handler");
	new menu_callback = menu_makecallback("shopMenu_callback");

	new menu_text[64], service[e_Service];
	for (new i = 0; i < ArraySize(g_services); ++i) {
		new data[4];
		data[0] = i + 1;
		ArrayGetArray(g_services, i, service);

		if (service[DESCRIPTION]) {
			formatex(menu_text, charsmax(menu_text), "%s \d(%s)", service[sNAME], service[DESCRIPTION]);
		}
		else {
			formatex(menu_text, charsmax(menu_text), "%s", service[sNAME]);
		}

		new ret;
		new forward_handle = CreateOneForward(service[PLUGIN], "ss_service_addingtolist", FP_CELL);
		ExecuteForward(forward_handle, ret, id);
		DestroyForward(forward_handle);

		data[1] = ret;

		if (data[1] != ITEM_OFF) {
			menu_additem(menu, menu_text, data, 0, menu_callback);
		}
	}

	menu_display(id, menu);

	client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "CONTACT_US");
	client_print_color(id, Red, "^4[%s] ^3%s", PREFIX, g_contact);
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
	new szText[128], data[3];

	ArrayGetArray(g_services, service_id, service);
	
	formatex(szText, charsmax(szText), "\r%L^n\y%L", id, "SHOP_SMS", id, "CHOOSE_QUANTITY", service[sNAME]);
	new menu = menu_create(szText, "pricingMenu_handler");

	new price[e_Price];
	for (new i = 0; i < ArraySize(g_prices); ++i) {
		ArrayGetArray(g_prices, i, price);

		if (!equali(price[pSERVICE_ID], service[sID])) {
			continue;
		}

		// There is no SMS with a given price
		if (_getSmsIndexByPrice(price[SMS_PRICE]) == -1) {
			continue;
		}

		new quantity[32 + 1];
		_getPriceQuantity(i, service_id, id, quantity, charsmax(quantity));

		formatex(szText, charsmax(szText), 
			"\y%s \w%s", 
			quantity,
			format_price(floatround(price[SMS_PRICE] * g_vat))
		);

		if (price[DISCOUNT]) {
			formatex(szText[strlen(szText)], charsmax(szText) - strlen(szText), " \r[-%d%%]", price[DISCOUNT]);
		}

		data[0] = service_id+1;
		// Prices count limit is 256
		data[1] = min(127, i);
		data[2] = min(127, i-data[1]);
		
		menu_additem(menu, szText, data);
	}

	if (menu_items(menu) > 1) {
		menu_display(id, menu);
	}
	// If there is only one element in the menu, let's choose it right away 
	else if (menu_items(menu) == 1) {
		which_service[id] = service_id;
		which_price[id] = data[1]+data[2];
		_openServiceTypeMenu(id);
	}
	else {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "NO_PRICE_LIST");
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
		new menu_title[64], item_text[64];
		
		formatex(menu_title, charsmax(menu_title), "%L", id, "CHOOSE_SERVICE_TYPE");
		new menu = menu_create(menu_title, "serviceTypeMenu_handler");
		new menu_callback = menu_makecallback("serviceTypeMenu_callback");

		formatex(item_text, charsmax(item_text), "%L", id, "TYPE_NICK_PASS");
		menu_additem(menu, item_text, "", 0, menu_callback);
		formatex(item_text, charsmax(item_text), "%L", id, "TYPE_IP_PASS");
		menu_additem(menu, item_text, "", 0, menu_callback);
		formatex(item_text, charsmax(item_text), "%L", id, "TYPE_STEAM_ID");
		menu_additem(menu, item_text, "", 0, menu_callback);

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
	remove_task(TASK_KEEP_DISPLAYING_MENU+id);
	menu_destroy(menu);

	switch (item) {
		case 0: {
			client_cmd(id, "messagemode ssnick_Password");
		}
		case 1: {
			client_cmd(id, "messagemode ssip_Password");
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
		client_cmd(id, "messagemode ssnick_Password");
	}
}

public onIpPasswordEntered(id)
{
	new szPassword[MAX_PASSWORD + 1];
	read_argv(1, szPassword, charsmax(szPassword));
	
	if (! _serviceTypeMenu_checkPass(id, TYPE_IP, szPassword)) {
		client_cmd(id, "messagemode ssip_Password");
	}
}

bool:_serviceTypeMenu_checkPass(id, type, const szPassword[MAX_PASSWORD + 1])
{
	new max_length = 30;
	new min_length = 2;
	
	if (strlen(szPassword) > max_length) {
		client_print(id, print_center, "%L", id, "PASSWORD_TOO_LONG", max_length);
		return false;
	}
	else if (strlen(szPassword) < min_length) {
		client_print(id, print_center, "%L", id, "PASSWORD_TOO_SHORT", min_length);
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
	new menu_title[64], item_text[64];
	formatex(menu_title, charsmax(menu_title), "%L", id, "CHOOSE_PAYMENT_METHOD");
	
	new menu = menu_create(menu_title, "paymentMethodMenu_handler");
	new menu_callback = menu_makecallback("paymentMethodMenu_callback");

	formatex(item_text, charsmax(item_text), "%L", id, "PAYMENT_METHOD_SMS");
	menu_additem(menu, item_text, "", 0, menu_callback);
	
	formatex(item_text, charsmax(item_text), "%L", id, "PAYMENT_METHOD_WALLET");
	menu_additem(menu, item_text, "", 0, menu_callback);

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

	_getPriceQuantity(which_price[id], which_service[id], id, quantity, charsmax(quantity));

	formatex(g_szTemp, charsmax(g_szTemp),
		"\r%L^n^n%L",
		id, "SHOP_SMS",
		id, "PAYMENT_SMS_INFO",
		service[sNAME],
		quantity,
		g_smsText,
		sms[NUMBER],
		format_price(price[SMS_PRICE]),
		format_price(floatround(price[SMS_PRICE] * g_vat))
	);
	
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
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "TRANSACTION_ABORTED");
	}
}

public onSmsCodeEntered(id)
{	
	if (!is_user_connected(id)) {
		return;
	}
		
	new sms_code[MAX_CODE + 1];
	read_argv(1, sms_code, charsmax(sms_code));
	
	_logActor(id, "Entered sms code: [%s]", sms_code);
	
	if (strlen(sms_code) < 2) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "SMS_CODE_TOO_SHORT");
		return;
	}
	
	if (containi(sms_code, " ") != -1) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "SMS_CODE_NO_SPACE");
		return;
	}

	_purchaseService(id, "sms", sms_code);
}

_purchaseService(id, const method[], const sms_code[] = "") {
	client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "PURCHASE_IN_PROGRESS");

	if (!_canUseShop()) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "SHOP_IS_UNAVAILABLE");
		return;
	}
	
	new url[MAX_URL + 1];
	new body[MAX_BODY + 1];
	new curl_slist: headers;
	{
		new service[e_Service], auth_data[32 + 1], steam_id[32 + 1], price[e_Price], ip[MAX_IP + 1];
		new u_service_id[MAX_SERVICE_ID * 2 + 1], u_auth_data[64 + 1], u_password[MAX_PASSWORD * 2 + 1], u_sms_code[MAX_CODE * 2 + 1];
		
		new sign[34], sign_body[1 + charsmax(auth_data) + MAX_CODE + MAX_SHOP_TOKEN + 1];
		new header[MAX_HEADER + 1];

		new shop_url[MAX_URL + 1], shop_token[MAX_SHOP_TOKEN + 1];

		_getShopUrl(shop_url, charsmax(shop_url));
		_getShopToken(shop_token, charsmax(shop_token));

		// Get service's data
		ArrayGetArray(g_services, which_service[id], service);
		
		// Get player's auth data
		switch (b_types[id]) {
			case TYPE_IP: get_user_ip(id, auth_data, charsmax(auth_data), true);
			case TYPE_SID: get_user_authid(id, auth_data, charsmax(auth_data));
			case TYPE_NICK: get_user_name(id, auth_data, charsmax(auth_data));
		}
	
		// Get username for services without type - e.g. using OTHER service module 
		if (!strlen(auth_data)) {
			get_user_name(id, auth_data, charsmax(auth_data));
		}

		get_user_ip(id, ip, charsmax(ip), true);
		get_user_authid(id, steam_id, charsmax(steam_id));
		ArrayGetArray(g_prices, which_price[id], price);

		StringURLEncode(service[sID], u_service_id, charsmax(u_service_id));
		StringURLEncode(auth_data, u_auth_data, charsmax(u_auth_data));
		StringURLEncode(b_passwords[id], u_password, charsmax(u_password));
		StringURLEncode(sms_code, u_sms_code, charsmax(u_sms_code));

		// Get players's language
		new language[16];
		formatex(language, charsmax(language), "%L", id, "LANG");

		// Calculate body sign
		formatex(sign_body, charsmax(sign_body),
			"%d#%s#%s#%s",
			b_types[id], auth_data, sms_code, shop_token
		);
		vc_md5(sign_body, sign);

		formatex(header, charsmax(header), "Authorization: %s", steam_id);
		headers = curl_slist_append(headers, header);
		headers = curl_slist_append(headers, "Accept: application/assoc");
		
		formatex(body, charsmax(body),
			"sign=%s&service_id=%s&type=%d&auth_data=%s&password=%s&method=%s&sms_code=%s&price_id=%d&ip=%s",
			sign, u_service_id, b_types[id], u_auth_data, u_password, method, u_sms_code, price[pID], ip
		);
		
		formatex(url, charsmax(url), "%s/api/server/purchase?token=%s&language=%s", shop_url, shop_token, language);
	}

	if (!makeRequest("POST", url, headers, body, "onPurchaseServiceResponse", id)) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "PURCHASE_REQUEST_FAILED");
	}
}

public onPurchaseServiceResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (!is_user_connected(playerId)) {
		return;
	}

	if (code != CURLE_OK) {
		client_print_color(playerId, Red, "^4[%s] ^1%L ^1Error: %d", PREFIX, playerId, "PURCHASE_REQUEST_FAILED", code);
		return;
	}

	if (statusCode >= 300) {
		client_print_color(playerId, Red, "^4[%s] ^1%L ^1HTTP code: %d", PREFIX, playerId, "PURCHASE_REQUEST_FAILED", statusCode);
		return;
	}

	new status[128], text[128], warnings[512];

	new Trie:dict = _createResponseDict(content);
	TrieGetString(dict, "status", status, charsmax(status));
	TrieGetString(dict, "text", text, charsmax(text));
	TrieGetString(dict, "warnings", warnings, charsmax(warnings));
	TrieDestroy(dict);

	if (strlen(text)) {
		client_print_color(playerId, Red, "^4[%s] ^1%s", PREFIX, text);
	} else {
		_log("Invalid purchase response: %s", content);
		client_print_color(playerId, Red, "^4[%s] ^1%L ^1Invalid response.", PREFIX, playerId, "PURCHASE_REQUEST_FAILED");
	}

	if (equal(status, "warnings")) {
		new title[64];
		formatex(title, charsmax(title), "%L", playerId, "PURCHASE_ERRORS");
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html>\
			<head><meta http-equiv=^"Content-Type^" content=^"text/html^" charset=^"UTF-8^"></head>\
			<body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^">\
			<div style=^"text-align: center; font-size: 22px; font-weight: bold;^">%s</div>\
			%s<br/>\
			<i>%L</i></body>\
			</html>",
			title,
			warnings,
			playerId, "REUSE_SMS_CODE"
		);
		show_motd(playerId, g_szTemp, title);
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
	_getPriceQuantity(which_price[id], which_service[id], id, quantity, charsmax(quantity));
	
	if (ret == SS_ERROR) {		
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "PURCHASE_FAILED", g_contact);
		_logActor(id, "Purchase error. Service: [%s] Quantity: [%s] Price: [%d]", service[sNAME], quantity, price[SMS_PRICE]);
		return;
	}

	new title[64];
	formatex(title, charsmax(title), "%L", id, "PURCHASE_DETAILS");
	
	if (b_types[id] & (TYPE_NICK | TYPE_IP)) {
		// Set user a password
		client_cmd(id, "setinfo _ss ^"%s^"", b_passwords[id]);
		
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>%L <span style=^"color: red^">%s</span><br /><br />\
			%L<br />\
			<span style=^"color: #3399ff^">setinfo _ss ^"%s^"</span><br /><br />\
			%L\
			</center></body></html>",
			id, "PURCHASE_SUCCEED",
			service[sNAME],
			id, "SETINFO_INSTRUCTION", "<i>config.cfg</i>",
			b_passwords[id],
			id, "CONTACT_US"
		);
		show_motd(id, g_szTemp, title);
	}
	else if (b_types[id] & TYPE_SID) {
		formatex(g_szTemp, charsmax(g_szTemp), 
			"<html><body style=^"background-color: #0f0f0f; color: #ccc; font-size: 14px;^"><center><br /><br />\
			<h1>%L <span style=^"color: red^">%s</span><br /><br />\
			%L\
			</center></body></html>",
			id, "PURCHASE_SUCCEED",
			service[sNAME],
			id, "CONTACT_US"
		);
		show_motd(id, g_szTemp, title);
	}
	
	client_print_color(id, Blue, "^4[%s] ^1%L ^4%s^1: %s", PREFIX, id, "PURCHASE_SUCCEED", service[sNAME], quantity);
	
	// If the service has flags assigned then let's reload players flags
	// Reload has to be delayed a little bit so that user password would be loaded already
	if (service[FLAGS]) {
		set_task(2.0, "loadPlayersFlags");
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

	// Get players's language
	new language[16];
	formatex(language, charsmax(language), "%L", id, "LANG");

	new shop_url[MAX_URL + 1], shop_token[MAX_SHOP_TOKEN + 1], url[MAX_URL + 1];
	new curl_slist: headers;

	_getShopUrl(shop_url, charsmax(shop_url));
	_getShopToken(shop_token, charsmax(shop_token));

	headers = curl_slist_append(headers, "Accept: application/assoc");
	formatex(
		url, charsmax(url),
		"%s/api/server/user_services?token=%s&nick=%s&ip=%s&steam_id=%s&language=%s",
		shop_url, shop_token, escaped_name, escaped_ip, escaped_steam_id, language
	);

	if (makeRequest("GET", url, headers, "", "onShowPlayerServicesResponse", id)) {
		set_task(0.0, "task_displayLoading", TASK_DISPLAY_LOADING + id);
	} else {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "LOAD_PLAYER_SERVICES_FAILED");
	}
}

public onShowPlayerServicesResponse(const content[], CURLcode: code, statusCode, playerId)
{
	if (!is_user_connected(playerId)) {
		return;
	}

	if (task_exists(TASK_DISPLAY_LOADING + playerId)) {
		remove_task(TASK_DISPLAY_LOADING + playerId);
	}
	
	if (code != CURLE_OK) {
		client_print_color(playerId, Red, "^4[%s] ^1%L ^1Error: %d", PREFIX, playerId, "LOAD_PLAYER_SERVICES_FAILED", code);
		return;
	}

	if (statusCode >= 300) {
		client_print_color(playerId, Red, "^4[%s] ^1%L ^1HTTP code %d.", PREFIX, playerId, "PLAYER_SERVICES_REQUEST_FAILED", statusCode);
		return;
	}

	new count, key[MAX_CONFIG_KEY + 1], menu_title[64];
	formatex(menu_title, charsmax(menu_title), "%L", playerId, "ACTIVE_PLAYER_SERVICES");
	new menu = menu_create(menu_title, "showPlayerServices_handler");

	new Trie:dict = _createResponseDict(content);

	if (!TrieGetTextInt(dict, "c", count)) {
		_log("Invalid player services response. | %s", content);
		client_print_color(playerId, Red, "^4[%s] ^1%L ^1Invalid response", PREFIX, playerId, "PLAYER_SERVICES_REQUEST_FAILED");
		TrieDestroy(dict);
		return;
	}

	for (new i = 0; i < count; ++i) {
		new service_name[MAX_SERVICE_ID + 1], expire[32 + 1], item_text[128];
		
		formatex(key, charsmax(key), "%d.s", i);
		TrieGetString(dict, key, service_name, charsmax(service_name));

		formatex(key, charsmax(key), "%d.e", i);
		TrieGetString(dict, key, expire, charsmax(expire));

		formatex(item_text, charsmax(item_text), "%L", playerId, "PLAYER_SERVICE_INFO", service_name, expire);
		menu_additem(menu, item_text);
	}

	TrieDestroy(dict);
	
	if (menu_items(menu)) {
		menu_display(playerId, menu);
	}
	else {
		new command[MAX_COMMAND + 1];
		_getShopCommand(command, charsmax(command));
		client_print_color(playerId, Red, "^4[%s] ^1%L", PREFIX, playerId, "NO_PLAYER_SERVICES", command);
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
	new command[MAX_COMMAND + 1];
	_getShopCommand(command, charsmax(command));
	
	for (new id = 0; id < get_maxplayers(); ++id) {
		if (is_user_connected(id)) {
			client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "COMMERCIAL", command);
		}
	}

	new Float:time = get_pcvar_float(g_cvarCommercial);

	if (time) {
		set_task(time, "displayCommercial");
	}
}

_createShopSmsConfigFile()
{
	format(g_configPath, charsmax(g_configPath), "%s/%s", g_configPath, CFG_FILE);
	
	if (!file_exists(g_configPath)) {
		new szText[1024], iLen=0, iMax=charsmax(szText);
		iLen += formatex(szText[iLen], iMax-iLen, "// ----------------------------------^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// SHOP SMS: - Configuration file^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// ----------------------------------^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Turn the shop On / Off^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// 1 - ON^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// 0 - OFF^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_on ^"1^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Comma-separated commands list, which can be used via chat, to display the shop menu^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_shop_commands ^"/sklepsms,/shopsms^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Comma-separated commands list, which can be used via chat, to reload players flags^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_reload_commands ^"/przeladuj^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Comma-separated commands list, which can be used via chat, to display your active services^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_services_commands ^"/uslugi^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Should the above commands be visible on the chat after usage^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_silent_commands ^"0^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// How often (seconds) should the shop commercial be displayed on the chat? 0 - never^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_commercial ^"137^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// #####################^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// ###   Shop WEB    ###^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// #####################^n^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Shop URL^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_url ^"^"^n");
		iLen += formatex(szText[iLen], iMax-iLen, "^n");
		iLen += formatex(szText[iLen], iMax-iLen, "// Server token^n");
		iLen += formatex(szText[iLen], iMax-iLen, "shopsms_token ^"^"^n");
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
		_errorForbidden("There is no space in the request pool");
	}
}

public onValidateLicenseResponse(const content[], CURLcode: code, statusCode, playerId)
{
	g_licenseValidated = false;

	if (g_validationAttempt) {
		_errorForbidden();
		return;
	}

	g_validationAttempt = true;

	if (code != CURLE_OK) {
		_log("Invalid CURL code: %d", code);
		_errorUnknown();
		return;
	}

	if (statusCode == 401) {
		_errorInvalidLicenseToken();
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

		new Trie:dict = _createResponseDict(content);
		TrieGetString(dict, "text", text, charsmax(text));
		TrieDestroy(dict);

		_errorForbidden(text);
		return;
	}

	if (statusCode >= 300) {
		_errorLicenseInvalidResponse(statusCode);
		return;
	}

	new text[32 + 1], signature;

	new Trie:dict = _createResponseDict(content);
	TrieGetString(dict, "text", text, charsmax(text));
	TrieGetTextInt(dict, "signature", signature);
	TrieGetTextInt(dict, "footer", g_footer);
	TrieDestroy(dict);

	if (!equal(text, "ok")) {
		_log("Invalid license validation response | %s", content);
		_errorUnknown();
		return;
	}

	if (signature != g_signature) {
		_errorForbidden();
		return;
	}

	g_licenseValidated = true;
	log_amx("%L", 0, "LICENSE_VALIDATED");
}

//
// ------------------------------------------------- HELPERS ----------------------------------------------------
//

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

_checkLoadedPlayersFlags()
{	
	log_amx("%L", 0, "PLAYER_SERVICES_LOADED", ArraySize(g_playersFlags));
}

_checkLoadedServices()
{
	log_amx("%L", 0, "SERVICES_LOADED", ArraySize(g_services));
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

_getPriceQuantity(price_index, service_index, player_id, output[], len)
{
	new price[e_Price];
	new service[e_Service];

	ArrayGetArray(g_prices, price_index, price);
	ArrayGetArray(g_services, service_index, service);

	if (price[QUANTITY] == -1) {
		formatex(output, len, "%L", player_id, "FOREVER");
	}
	else {
		groupDigits(price[QUANTITY], output, len);
		formatex(output[strlen(output)], len - strlen(output), " %s", service[TAG]);
	}
}

_canUseShop()
{
	return !g_blocked && g_licenseValidated && get_pcvar_num(g_cvarOn);
}

_canPayWithWallet(id)
{
	new steam_id[MAX_SID + 1];

	get_user_authid(id, steam_id, charsmax(steam_id));
	strtolower(steam_id);

	if (TrieKeyExists(g_accountsSteamIds, steam_id)) {
		return true;
	}

	// CSGO uses different steamid prefix. STEAM_1 instead of STEAM_0.
	// We want to check against it as well.
	replace(steam_id, charsmax(steam_id), "steam_1", "steam_0");
	if (TrieKeyExists(g_accountsSteamIds, steam_id)) {
		return true;
	}

	replace(steam_id, charsmax(steam_id), "steam_0", "steam_1");
	return TrieKeyExists(g_accountsSteamIds, steam_id);
}

_getShopCommand(output[], len)
{
	#if defined TrieIterCreate
	new TrieIter:iter = TrieIterCreate(g_shopCommands);
	if (!TrieIterEnded(iter)) {
		TrieIterGetKey(iter, output, len);
	} else {
		formatex(output, len, "");
	}
	TrieIterDestroy(iter);
	#else
	get_pcvar_string(g_cvarShopCommands, g_szTemp, charsmax(g_szTemp));
	copyc(output, len, g_szTemp, ',');
	#endif
}

_getShopToken(output[], len)
{
	get_pcvar_string(g_cvarShopToken, output, len);
	trim(output);
}

_getShopUrl(output[], len)
{
	get_pcvar_string(g_cvarShopUrl, output, len);
	trim(output);

	// Remove trailing slash
	if (strlen(output) && output[strlen(output) - 1] == '/') {
		output[strlen(output)-1] = 0;
	}
}

/**
 * https://amxx.pl/topic/43223-explode/
 */
_explodeCommands(const text[], Trie:dict)
{
	TrieClear(dict);

	new cur_len = 0, max_len = strlen(text);
	
	while (cur_len < max_len)
	{
		new command[MAX_COMMAND + 1];
		cur_len += copyc(command, charsmax(command), text[cur_len], ',') + 1;
		strtolower(command);
		trim(command);

		if (strlen(command)) {
			TrieSetCell(dict, command, 1);
		}
	}
}

//
// ------------------------------------------------- ERRORS ----------------------------------------------------
//

// License
_errorUnknown() {
	g_blocked = true;
	_log("%L", 0, "ERROR_10");
}

_errorLicenseInvalidResponse(statusCode) {
	g_blocked = true;
	_log("%L", 0, "ERROR_11", statusCode);
}

_errorValidationError() {
	g_blocked = true;
	_log("%L", 0, "ERROR_12");
}

_errorInvalidLicenseToken() {
	g_blocked = true;
	_log("%L", 0, "ERROR_13");
}

_errorPaymentRequired() {
	_throwError("ERROR_14");
}

_error

_errorForbidden(const text[] = "") {
	#if AMXX_VERSION_NUM > 182
	set_fail_state("%L", 0, "ERROR_15", text);
	#else
	set_fail_state("ERROR_15");
	#endif
}

// Config
_errorConfigFailed(code) {
	g_blocked = true;
	_log("%L", 0, "ERROR_20", code);
}

_errorInvalidServerToken() {
	_throwError("ERROR_21");
}

_errorOutdatedVersion() {
	_throwError("ERROR_22");
}

_errorConfigInvalidResponse() {
	g_blocked = true;
	_log("%L", 0, "ERROR_23");
}

_errorNoShopCreds() {
	_throwError("ERROR_24");
}

_throwError(const error[])
{
	#if AMXX_VERSION_NUM > 182
	set_fail_state("%L", 0, error);
	#else
	set_fail_state(error);
	#endif
}

//
// ------------------------------------------------- HTTP Requests ----------------------------------------------------
//

public task_displayLoading(task_id)
{
	new id = task_id - TASK_DISPLAY_LOADING;

	if (is_user_connected(id)) {
		client_print_color(id, Red, "^4[%s] ^1%L", PREFIX, id, "LOADING");
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
	_log("Request | %s %s %s", method, url, body);
	#endif
   	
   	handle = curl_easy_init();
   	if (!handle) {
   		_log("The CURL handle couldn't be initialized.");
   		return false;
   	}

   	new requestId = g_requestCounter++ % MAX_REQUESTS_COUNT;

   	if (g_requestsInProgress[requestId]) {
   		_log("Requests pool is full. Request has not been execeuted.");
   		return false;
   	}

	// Clear response array
	setc(g_responses[requestId], MAX_RESPONSE, 0);
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
		_log("CURL error: [%d] %s", code, szError);
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
	_log("Request response | [%d] [%d] %s", code, statusCode, httpResponseContent);
	#endif

	if (!strlen(function) || callfunc_begin(function) == 1) {
		callfunc_push_str(httpResponseContent);
		callfunc_push_int(_:code);
		callfunc_push_int(statusCode);
		callfunc_push_int(playerId);
		callfunc_end();
	} else {
		_log("Functions hasn't been execeuted properly [%s]", function);
	}
}


//
// ------------------------------------------------- External Functions ----------------------------------------------------
//
 
public native_registerService(plugin, params)
{	
	if (params != 1) {
		_log("An error occurred while registering the service. Invalid number of arguments passed to the ss_register_service function.");
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

public native_openPaymentMethodMenu(plugin, params)
{	
	if (params != 1) {
		return SS_BAD_ARGS;
	}
	
	_openPaymentMethodMenu(get_param(1));
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

stock bool:is_steam(id)
{	
	new auth[32];
	get_user_authid(id, auth, charsmax(auth));
	return contain(auth, "STEAM_0:0:") != -1 || contain(auth, "STEAM_0:1:") != -1;
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

stock format_price(value)
{
	new price[32];
	
	formatex(price, charsmax(price), "%d.%s %s", value / 100, two_number_value(value % 100), g_currency);
	
	return price;
}

stock two_number_value(value)
{	
	new text[17];
	
	if (value < 10) {
		formatex(text, charsmax(text), "0%d", value);
	} else {
		formatex(text, charsmax(text), "%d", value);
	}
		
	return text;
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

stock bool:TrieGetTextInt(Trie: dict, const key[], &output)
{
	new szNumber[MAX_NUMBER_LENGTH + 1];

	if (TrieGetString(dict, key, szNumber, charsmax(szNumber))) {
		output = str_to_num(szNumber);
		return true;
	}

	return false;
}

stock bool:TrieGetTextFloat(Trie: dict, const key[], &Float:output)
{
	new szNumber[MAX_NUMBER_LENGTH + 1];

	if (TrieGetString(dict, key, szNumber, charsmax(szNumber))) {
		output = str_to_float(szNumber);
		return true;
	}

	return false;
}
