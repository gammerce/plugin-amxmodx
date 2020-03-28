#if defined _shop_sms_included
	#endinput
#endif
#define _shop_sms_included

#pragma library "shop_sms"

#include <shop_sms_const>

native ss_register_service(const service_id[]);
/*------------------------------
 * Rejestruje usluge, ktora bedzie pozniej dostepna w sklepie
 * ---------------------------
 * service_id[] - id uslugi
------------------------------*/

native ss_open_payment_method_menu(id);
/*------------------------------
 * Kontynuuje proces zakupu po zwroceniu wartosci SS_STOP w forwardzie ss_service_chosen
 * ---------------------------
 * id - index gracza dokonujacego zakupu
------------------------------*/

native ss_show_service_purchase(id, const service_id[]);
/*------------------------------
 * Wyswietla menu z zakupem danej uslugi
 * ---------------------------
 * id - index gracza dokonujacego zakupu
 * service_id[] - id uslugi do zakupienia
------------------------------*/

native ss_log(const message[], any:...);
/*------------------------------
 * Dodaje informacje do log�w.
------------------------------*/

native bool:ss_is_steam(id);
/*------------------------------
 * Sprawdza, czy gracz ma steama
 * ---------------------------
 * id - index gracza 
------------------------------*/

forward ss_service_data(name[], flags[]);
/*------------------------------
 * Forward wysylany ( do pluginu z ktorego zostala zarejstrowana usluga )
 * w momencie pobrania danych o usludze.
 * ---------------------------
 * name[] - nazwa uslugi
 * flags[] - flagi danej uslugi
 * ---------------------------
 */

forward ss_service_addingtolist(id);
/*------------------------------
 * Forward wysylany ( do pluginu z ktorego zostala zarejstrowana usluga )
 * w momencie dodawania uslugi do menu z uslugami.
 * Funkcja powinna zwracać jedną z dwóch wartosci:
 *  ITEM_ENABLED - usluga ma byc dostepna
 *  ITEM_DISABLED - usluga ma byc niedostepna
 * ---------------------------
 * id - index gracza dokonujacego zakupu
------------------------------*/

forward ss_service_chosen(id, quantity);
/*------------------------------
 * Forward wysylany ( do pluginu z ktorego zostala zarejstrowana usluga )
 * w momencie wybrania uslugi.
 * Funkcja powinna zwracac jedna z dwoch wartosci:
 *  SS_OK
 *  SS_STOP - gdy chcemy na pewien czas zatrzymać proces wykupowania usługi.
 *		Potem musimy go wznowić za pomoca natywu ss_open_payment_method_menu.
 * ---------------------------
 * id - index gracza dokonujacego zakupu
 * quantity - wybrana ilosc ( opcja )
------------------------------*/

forward ss_service_bought(id, quantity);
/*------------------------------
 * Forward wysylany ( do pluginu z ktorego zostala zarejstrowana usluga ) w momencie zakupu uslugi.
 * Mozna zwrocic wartosc SS_ERROR w przypadku wystapienia bledu przy dodawaniu uslugi.
 * ---------------------------
 * id - index gracza dokonujacego zakupu
 * quantity - ilosc wykupionej uslugi
------------------------------*/

forward ss_client_access(id, flags);
/*------------------------------
 * Forward wysylany do wszystkich pluginow w momencie przypisania uzytkownikowi flag.
 * Zwracana wartosc jest ignorowana.
 * ---------------------------
 * id - index gracza
 * flags - flagi, ktore zostaly ustawione uzytkownikowi 
------------------------------*/

stock pause_plugin() {
	static szFile[32];
	get_plugin(-1, szFile, sizeof szFile);
	pause("ad", szFile);
}
