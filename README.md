# Lidswitch — Omarchy-widget

Balkwidget voor [lidswitch](https://github.com/michielturmel-max/lidswitch): zie in één oogopslag of je weg bent, of er nog werk loopt en welke vragen op je wachten. Linkerklik wisselt tussen aanwezig en afwezig, rechtsklik opent het overzicht, middenklik ververst.

> **Status: experimenteel.** De widget is een dunne laag over de lidswitch-CLI. De volledige installatie bestaat uit een CLI, een systemd-user-service, een opencode-plugin en één logind-wijziging. Zonder die onderdelen doet de widget niets.

## Vereisten

- [lidswitch](https://github.com/michielturmel-max/lidswitch) volledig geïnstalleerd (CLI, service en opencode-plugin).
- Omarchy met de Quickshell-shell.
- systemd (user).

Installeer eerst het hoofdproject:

```bash
git clone https://github.com/michielturmel-max/lidswitch.git
cd lidswitch
./install.sh
```

Herstart daarna je opencode-sessie en de laptop, zodat de logind-instelling actief wordt. Controleer met `lidswitch check`.

## Downloaden en installeren

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

## Bediening

| Actie | Wat het doet |
| --- | --- |
| linksklik | wissel tussen aanwezig en afwezig |
| rechtsklik | overzicht met snelle instellingen en log |
| middenklik | verversen |

Het paneel toont de dekselstand, of je afwezig bent, clamshell-gebruik, het aantal actieve sessies, wachtende vragen en uitgestelde items.

## Verwijderen

```bash
omarchy plugin remove lidswitch
```

Het hoofdproject verwijder je met `lidswitch-uninstall` en de logind-regel met
`sudo rm /etc/systemd/logind.conf.d/50-lidswitch.conf`.

## Licentie

MIT, zie [LICENSE](LICENSE).
