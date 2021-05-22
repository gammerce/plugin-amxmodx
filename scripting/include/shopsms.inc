#if defined _shopsms_included
	#endinput
#endif
#define _shopsms_included

#pragma library "shopsms"

#include <shopsms_const>

native ss_register_service(const service_id[]);
/*------------------------------
 * Register service so that players can purchase it.
 * ---------------------------
 * service_id[] - Unique service ID
------------------------------*/

native ss_open_shop(id);
/*------------------------------
 * Open shop menu
 * ---------------------------
 * id - ID of a player
------------------------------*/

native ss_open_payment_method_menu(id);
/*------------------------------
 * Continue shopping process. Function can be called if SS_STOP was returned in ss_service_chosen function.
 * ---------------------------
 * id - ID of a player making a purchase
------------------------------*/

native ss_show_service_purchase(id, const service_id[]);
/*------------------------------
 * Show service purchase menu
 * ---------------------------
 * id - ID of a player who makes a purchase
 * service_id[] - ID of a service to be shown
------------------------------*/

native ss_get_flag_expiration(id, flag);
/*------------------------------
 * Returns player's flag expiration timestamp. Returns 0 when a player doesn't have a given flag.
 * ---------------------------
 * id - ID of a player
 * flag - ID of a flag
------------------------------*/

native ss_log(const message[], any:...);
/*------------------------------
 * Log info to the shop server logs
------------------------------*/

native bool:ss_is_steam(id);
/*------------------------------
 * Check whether player is a steam player
 * ---------------------------
 * id - ID of a player
------------------------------*/

forward ss_service_data(name[], flags[]);
/*------------------------------
 * Forward sent ( to a service plugin ) when service data was fetched.
 * ---------------------------
 * name[] - service name
 * flags[] - service flags
 * ---------------------------
 */

forward ss_service_addingtolist(id);
/*------------------------------
 * Forward sent ( to a service plugin ) when service is being added to the services menu.
 * Function should return one of the following values:
 *  ITEM_ENABLED - service is AVAILABLE
 *  ITEM_DISABLED - service is UNAVAILABLE
 * ---------------------------
 * id - ID of a player making a purchase
------------------------------*/

forward ss_service_chosen(id, quantity);
/*------------------------------
 * Forward sent ( to a service plugin ) when service is chosen.
 * Function should return one of the following values:
 *  SS_OK
 *  SS_STOP - when we want to stop purchase process for some time.
 *		      Then we have to resume it using the ss_open_payment_method_menu native.
 * ---------------------------
 * id - ID of a player making a purchase
 * quantity - select quantity ( option )
------------------------------*/

forward ss_service_bought(id, quantity);
/*------------------------------
 * Forward sent ( to a service plugin ) when service is purchased.
 * Vaue SS_ERROR can be returned in case of an error while adding the service.
 * ---------------------------
 * id - ID of a player making a purchase
 * quantity - service quantity
------------------------------*/

forward ss_client_access(id, flags);
/*------------------------------
 * Forward sent to all plugins when a player is being granted access.
 * Returned value is ignored.
 * ---------------------------
 * id - ID of a player
 * flags - players flags
------------------------------*/

stock pause_plugin() {
	static szFile[32];
	get_plugin(-1, szFile, sizeof szFile);
	pause("ad", szFile);
}
