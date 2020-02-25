# [Sklep SMS](https://sklep-sms.pl/) [![Release](https://img.shields.io/github/v/release/gammerce/plugin-amxmodx)](https://github.com/gammerce/plugin-amxmodx/releases/latest)

Plugin AMX Mod X do Sklepu SMS, który umożliwia dokonywanie zakupow z serwera.

[Instrukcja instalacji](https://github.com/gammerce/plugin-amxmodx/wiki/Konfiguracja-pluginu)

## Wymagania
* AMX Mod X 1.8.2+
* Moduł CURL

## Lista obsługiwanych gier
* Counter-Strike v1.6

## Lista domyślnie dostępnych usług
* VIP
* VIP PRO
* Rezerwacja Nicku
* Rezerwacja Slota
* Niestandardowe usługi oparte na nadawaniu graczowi flag ( np. klasy Premium ) - [Instrukcja](https://github.com/gammerce/plugin-amxmodx/wiki/Utworzenie-us%C5%82ugi-nadaj%C4%85cej-graczowi-flagi)
* CoD: EXP
* CoD: Przeniesienie EXPa
* GXM: EXP
* ZP: Bezlitosne monety
* ZP: Ammo Packs
* BF2: Odznaki ( wymaga edycji kodu ) - [Instrukcja](https://github.com/gammerce/plugin-amxmodx/wiki/Dodanie-us%C5%82ugi-BF2:-Odznaki)

## Komendy chatu

#### /sklepsms
Otwiera menu sklepu

#### /uslugi
Wyświetla aktywne usługi gracza

#### /przeladuj
Wymusza przeładowanie usług wykupionych w sklepie

## CVARs

#### sklepsms_on "1"
Włącza (1) / wyłącza (0) sklep

#### sklepsms_sklep_komenda "/sklepsms,/shopsms"
Lista [komend](https://github.com/gammerce/plugin-amxmodx#sklepsms) oddzielonych przecinkiem, które można wpisać na chacie, w celu wyświetlenia menu sklepu.

#### sklepsms_przeladuj_komenda "/uslugi"
Lista [komend](https://github.com/gammerce/plugin-amxmodx#uslugi) oddzielonych przecinkiem, które można wpisać na chacie, w celu wyświetlenie usług wykupionych w sklepie.

#### sklepsms_przeladuj_komenda "/przeladuj"
Lista [komend](https://github.com/gammerce/plugin-amxmodx#przeladuj) oddzielonych przecinkiem, które można wpisać na chacie, w celu przeładowania usług wykupionych w sklepie.

#### sklepsms_info "1"
Czy wyswietlać informację o sklepie na chacie?

#### sklepsms_ciche_komendy "0"
Czy ukrywać na chacie komendy sklepu, które użytkownik wpisuje.
