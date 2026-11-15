# Lidswitch — Omarchy-balkwidget

Balkwidget voor [lidswitch](https://github.com/michielturmel-max/lidswitch): zie
in één oogopslag of je weg bent, of er nog werk loopt en welke vragen op je
wachten. Linksklik wisselt tussen aanwezig en afwezig, rechtsklik opent het
overzicht met de instellingen, middenklik ververst.

> **Status: experimenteel.** De widget is een dunne laag over de lidswitch-CLI.
> De volledige installatie bestaat uit een CLI, een systemd-user-service, een
> opencode-plugin en één logind-wijziging. Zonder die onderdelen doet de widget
> niets.

## Wat je ziet

Het icoon in de balk is een deksel met een stip:

- **geen stip** — je bent aanwezig en er loopt niets.
- **stip** — je bent weg (`away`), of er is nog werk: een bezige sessie of een
  openstaande todo.
- **tooltip** — dekselstand, aanwezig/weg, aantal sessies, bezig, todo, wachtend
  en uitgesteld.

Het paneel toont dezelfde stand uitgebreid: deksel, sinds wanneer je weg bent,
het aantal sessies, alle uitgestelde vragen en een knop om handmatig te
wisselen.

## Vereisten

- [lidswitch](https://github.com/michielturmel-max/lidswitch) volledig
  geïnstalleerd: CLI in `~/.local/bin`, systemd-user-service en de
  opencode-plugin.
- Omarchy met de Quickshell-shell.
- `systemd` (user), `jq` en `notify-send` — op een standaard Omarchy-installatie
  al aanwezig.

Installeer eerst het hoofdproject:

```bash
git clone https://github.com/michielturmel-max/lidswitch.git
cd lidswitch
./install.sh
```

Herstart daarna je opencode-sessie en de laptop, zodat de logind-instelling
actief wordt. Controleer met:

```bash
lidswitch check
```

## Installeren

```bash
omarchy plugin add https://github.com/michielturmel-max/lidswitch-omarchy --enable
```

Of met de hand:

```bash
git clone https://github.com/michielturmel-max/lidswitch-omarchy.git \
  ~/.config/omarchy/plugins/lidswitch
omarchy plugin enable lidswitch
```

Daarna staat de widget in de balk. Zo niet: `omarchy-restart-shell`.

De widget leest en schrijft alleen via `bin/lidswitch-widget`, dat op zijn beurt
`lidswitch` aanroept. Er is dus altijd één schrijver per bestand.

## Bediening

| Actie | Wat het doet |
| --- | --- |
| linksklik | wissel tussen aanwezig en afwezig (handmatige override) |
| rechtsklik | paneel met overzicht, instellingen en controle |
| middenklik | verversen |
| `t` in het paneel | zelfde als linksklik |
| `r` in het paneel | verversen |
| `c` in het paneel | `lidswitch check` draaien |

`aanwezig` zet alleen de handmatige stand terug; de watch-loop blijft de echte
dekselstand lezen. De hardware is dus altijd leidend.

## Instellingen

De schakelaars en schuiven staan in het paneel (rechtsklik) en schrijven direct
naar `~/.config/lidswitch/config.json`:

| Instelling | Betekenis |
| --- | --- |
| Meldingen | desktopmelding bij deksel dicht, terug en klaar |
| Afwezig in clamshell | dicht deksel mét extern scherm telt als afwezig; zet uit als je gewoon doorwerkt op het externe scherm |
| Slaapstand als het klaar is | de laptop mag in slaapstand zodra alle sessies klaar zijn |
| Alleen loggen (dry run) | logt wat er zou gebeuren in plaats van echt te suspenderen |
| Rust voordat hij slaapt | minuten niets te doen voordat de slaapstand begint (0–120) |
| Minimaal weg voordat slapen mag | nooit korter dan dit na het sluiten (0–120) |

De twee schuiven zijn alleen actief als `Slaapstand als het klaar is` aan staat.
Ze schrijven pas als je de schuif loslaat, zodat een sleepbeweging niet bij elke
pixel een bestand herschrijft.

## Controle en probleemoplossing

Druk in het paneel op `c`, of draai in een terminal:

```bash
lidswitch check
lidswitch status
```

- **Widget niet in de balk** — `omarchy plugin list` moet `lidswitch` tonen;
  daarna `omarchy-restart-shell`.
- **Schakelaars en schuiven grijs** — de widget kon de CLI niet bereiken.
  Controleer of `~/.local/bin/lidswitch` bestaat en of `lidswitch status --json`
  werkt. Zonder CLI blijft het paneel in de laadstand.
- **Verkeerde dekselstand** — de CLI leest het ACPI-bestand; test met
  `lidswitch override closed` en `lidswitch override open`.
- **Alles staat goed, maar er gebeurt niets bij een dicht deksel** — de
  logind-drop-in is niet actief. `lidswitch check` wijst dat aan; herstart de
  laptop na het plaatsen.

## Bijwerken

```bash
omarchy plugin update lidswitch
```

Of, bij een handmatige clone:

```bash
git -C ~/.config/omarchy/plugins/lidswitch pull
omarchy-restart-shell
```

## Verwijderen

```bash
omarchy plugin remove lidswitch
```

Het hoofdproject verwijder je met `lidswitch-uninstall`. De logind-regel blijft
staan; haal die weg met:

```bash
sudo rm /etc/systemd/logind.conf.d/50-lidswitch.conf
```

Je eigen configuratie (`~/.config/lidswitch/`) laat de widget met rust.

## Licentie

MIT, zie [LICENSE](LICENSE).
