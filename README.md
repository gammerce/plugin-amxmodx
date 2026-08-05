# [Sklep SMS](https://sklep-sms.pl/) ![Build](https://github.com/gammerce/plugin-amxmodx/workflows/Compile%20plugins/badge.svg) [![Release](https://img.shields.io/github/v/release/gammerce/plugin-amxmodx)](https://github.com/gammerce/plugin-amxmodx/releases/latest)

AMX Mod X plugin that allows players to make purchases using Sklep-SMS. 

[Installation Guide](https://github.com/gammerce/plugin-amxmodx/wiki/Konfiguracja-pluginu)

## Requirements
* AMX Mod X 1.8.2+
* CURL module

## Supported video games
* Counter-Strike v1.6

## Default services
* VIP
* VIP PRO
* Nick reservation
* Slot reservation
* Custom services based on player flags ( eg. premium classes ) - [Manual](https://github.com/gammerce/plugin-amxmodx/wiki/Utworzenie-us%C5%82ugi-nadaj%C4%85cej-graczowi-flagi)
* CoD: EXP
* CoD: EXP Transfer
* GXM: EXP
* ZP: Bezlitosne monety
* ZP: Ammo Packs
* BF2: Odznaki ( code edition required ) - [Manual](https://github.com/gammerce/plugin-amxmodx/wiki/Dodanie-us%C5%82ugi-BF2:-Odznaki)
* JB pack - [Link](https://amxx.pl/topic/127942-jailbreak-pack-shop/)

## Chat commands

#### /sklepsms
Open Sklep-SMS menu

#### /uslugi
Show players active services

#### /przeladuj
Reload players flags

## CVARs

#### shopsms_on "1"
Turn the shop On (1) / Off (0)

#### shopsms_shop_commands "/sklepsms,/shopsms"
Comma-separated commands list, which can be used via chat, to display the shop menu

#### shopsms_services_commands "/uslugi"
Comma-separated commands list, which can be used via chat, to display your active services

#### shopsms_reload_commands "/przeladuj"
Comma-separated commands list, which can be used via chat, to reload players flags

#### shopsms_silent_commands "0"
Should the above commands be visible on the chat after usage.

#### shopsms_commercial "137"
How often (seconds) should the shop commercial be displayed on the chat? 0 - never

## Build

The repository contains the full plugin source: the shop engine (`shopsms.sma`) and all service modules. Requires Docker and the `budziam/amxmodx-builder` image.

```bash
./build.sh 1.10.0   # compiles everything into cstrike/addons/amxmodx/plugins/
./package.sh 1.10.0 # produces out/amxmodx-1.10.0.zip (full cstrike/ tree, sources included)
```

Supported compiler versions: 1.8.2, 1.8.3, 1.9.0, 1.10.0.

## Test server

A runnable CS 1.6 test server (Docker HLDS + Metamod + AMX Mod X) lives in `server/`:

```bash
./build.sh 1.10.0
./server/run.sh 1.10.0
```
