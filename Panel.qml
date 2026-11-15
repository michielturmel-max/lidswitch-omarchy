import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget for lidswitch: the icon shows whether you are away and whether work
// is still running; the panel is the overview plus the settings that are safe to
// change from here. Everything it shows or changes goes through
// bin/lidswitch-widget, a thin wrapper over the CLI, so this widget never becomes
// a second writer of lid.json or config.json.
Panel {
  id: root
  moduleName: "lidswitch"
  ipcTarget: "lidswitch"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/lidswitch/bin/lidswitch-widget"

  // The bridge answers every command with one JSON object:
  // {"status": {...}, "config": {...}}. Anything written is echoed back in the
  // same reply, which is what keeps the controls showing the stored value.
  property var staat: ({})
  property bool geladen: false
  property string controle: ""
  // Values the user just wrote, held until the reply confirms them so a slider
  // does not snap back for a frame after the drag ends.
  property var voorlopig: ({})
  property var wachtrij: []

  readonly property var info: staat.status || ({})
  readonly property var cfg: staat.config || ({})

  readonly property string lid: info.lid ? String(info.lid) : "unknown"
  readonly property bool away: info.away === true
  readonly property string since: info.awaySince ? String(info.awaySince) : ""
  readonly property var sessions: info.sessions || []
  readonly property var uitgesteld: {
    var alle = []
    for (var i = 0; i < sessions.length; i++) alle = alle.concat(sessions[i].deferred || [])
    return alle
  }
  readonly property int sessionCount: sessions.length
  readonly property int busyCount: sessions.filter(function (s) { return s.busy === true }).length
  readonly property int waitingCount: sessions.filter(function (s) { return s.waiting === true }).length
  readonly property int openTodoCount: sessions.reduce(function (a, s) { return a + (s.openTodos || 0) }, 0)

  readonly property bool meldingen: cfg.notify === true
  readonly property bool clamshell: cfg.awayInClamshell === true
  readonly property bool slaapAan: cfg.sleepWhenDone ? cfg.sleepWhenDone.enabled === true : false
  readonly property bool dryRun: cfg.sleepWhenDone ? cfg.sleepWhenDone.dryRun === true : false

  readonly property string stateText: away ? "weg" : "aanwezig"
  readonly property string tooltipText: {
    var p = ["deksel:" + lid, stateText, "sessies:" + sessionCount]
    if (busyCount) p.push("bezig:" + busyCount)
    if (openTodoCount) p.push("todo:" + openTodoCount)
    if (waitingCount) p.push("wacht:" + waitingCount)
    if (uitgesteld.length) p.push("uitgesteld:" + uitgesteld.length)
    return p.join("  ")
  }

  // ---------------------------------------------------------------- acties --

  // Commands run one at a time: the bridge rewrites config.json, and two
  // overlapping writers would race. A quick second click waits its turn instead
  // of being dropped.
  function run(args) {
    root.wachtrij = root.wachtrij.concat([args])
    root.pump()
  }

  function pump() {
    if (stateProc.running || root.wachtrij.length === 0) return
    var volgende = root.wachtrij[0]
    root.wachtrij = root.wachtrij.slice(1)
    stateProc.command = [root.scriptPath].concat(volgende)
    stateProc.running = true
  }

  function herlaad() { root.run(["state"]) }
  function wissel() { root.run(["toggle"]) }

  function zet(pad, waarde) {
    var nu = {}
    for (var k in root.voorlopig) nu[k] = root.voorlopig[k]
    nu[pad] = waarde
    root.voorlopig = nu
    root.run(["set", pad + "=" + waarde])
  }

  // Config value for a dotted path, with the in-flight write in front of it.
  function waarde(pad) {
    if (root.voorlopig[pad] !== undefined) return Number(root.voorlopig[pad])
    var delen = pad.split(".")
    var v = root.cfg
    for (var i = 0; i < delen.length; i++) v = (v === undefined || v === null) ? undefined : v[delen[i]]
    return Number(v === undefined || v === null ? 0 : v)
  }

  function controleer() {
    root.controle = ""
    checkProc.running = true
  }

  // ---------------------------------------------------------------- proces --

  Process {
    id: stateProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text).trim()
        if (raw !== "") {
          try {
            var next = JSON.parse(raw)
            if (next && next.status) {
              root.staat = next
              root.geladen = true
              // The reply is authoritative now; drop the optimistic values.
              root.voorlopig = ({})
            }
          } catch (e) {
            console.warn("lidswitch: kon status niet lezen:", raw)
          }
        }
        Qt.callLater(root.pump)
      }
    }
    onExited: Qt.callLater(root.pump)
  }

  Process {
    id: checkProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controle = String(text).trim()
    }
  }

  // While the panel is open the session list can change under it, so keep it
  // fresh; closed, there is nothing to show and nothing to poll.
  Timer {
    interval: 5000
    repeat: true
    running: root.opened
    onTriggered: root.herlaad()
  }

  onOpenedChanged: if (root.opened) root.herlaad()

  // --------------------------------------------------------------- icoon ----

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltipText
    // Active while away or while anything waits for you: that is exactly when
    // the panel has something to say.
    active: root.away || root.uitgesteld.length > 0

    onPressed: function (b) {
      if (b === Qt.MiddleButton) { root.herlaad(); return }
      if (b === Qt.RightButton) { root.toggle(); return }
      root.wissel()
    }

    // Eigen icoon: een deksel dat zichtbaar dicht klapt wanneer je weg bent,
    // met een stip als er werk openstaat. Glyphs zijn op bar-hoogte onleesbaar.
    iconComponent: Component {
      // Geen anchors.fill op deze root: de Loader in BarIconContent geeft een
      // item zonder eigen maat pas na het laden een canvas, en een anchor naar
      // de parent houdt hem op 0x0.
      Item {
        readonly property real s: width / 24
        readonly property color ink: button.foreground

        Rectangle {
          x: 3 * s; y: 6 * s
          width: 18 * s; height: 11 * s
          radius: 1.6 * s
          color: "transparent"
          border.width: Math.max(1, Math.round(1.7 * s))
          border.color: ink
        }

        // Deksel: scharnier bovenaan, kantelt omhoog als het dicht is.
        Rectangle {
          x: 3.6 * s
          y: root.away ? 1.6 * s : 4.4 * s
          width: 16.8 * s
          height: 2.2 * s
          radius: 1.1 * s
          color: ink
        }

        // Open werk. Eén stip is genoeg; een balk zou de icon te zwaar maken.
        Rectangle {
          visible: root.busyCount > 0 || root.openTodoCount > 0
          x: 15.2 * s; y: 10.4 * s
          width: 3 * s; height: 3 * s
          radius: 1.5 * s
          color: root.away ? ink : "transparent"
          border.width: root.away ? 0 : Math.max(1, Math.round(1.2 * s))
          border.color: ink
        }
      }
    }
  }

  // --------------------------------------------------------------- paneel ---

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: Style.space(420)
    contentHeight: Style.space(620)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.herlaad()
        if (t === "c" || t === "C") root.controleer()
        if (t === "t" || t === "T") root.wissel()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: kolom.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: kolom
          width: flick.width
          spacing: Style.space(10)

          PanelSectionHeader {
            width: parent.width
            text: "LIDSWITCH"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          // ---------------------------------------------------------- stand --

          Text {
            width: parent.width
            text: root.away
              ? "Je bent weg. Het model werkt zelfstandig door."
              : "Je bent aanwezig. Het deksel is " + root.lid + "."
            color: root.away ? Color.accent : root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: (root.since ? "weg sinds " + root.since.replace("T", " ").slice(0, 16) + "  ·  " : "")
              + root.sessionCount + " sessie(s)"
              + (root.busyCount ? "  ·  " + root.busyCount + " bezig" : "")
              + (root.openTodoCount ? "  ·  " + root.openTodoCount + " open todo" : "")
              + (root.waitingCount ? "  ·  " + root.waitingCount + " wacht" : "")
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width }

          // ---------------------------------------------- uitgestelde vragen --

          PanelSectionHeader {
            width: parent.width
            text: root.uitgesteld.length ? "UITGESTELD (" + root.uitgesteld.length + ")" : "UITGESTELD"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Text {
            width: parent.width
            visible: root.uitgesteld.length === 0
            text: "Niets. Alles wat je beslissing nodig had is al afgehandeld."
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.uitgesteld

            delegate: Rectangle {
              required property var modelData
              width: kolom.width
              implicitHeight: uitgesteldKolom.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Color.menu.background

              Column {
                id: uitgesteldKolom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: modelData.title || modelData.type || "iets"
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  text: modelData.reason || "vereist de gebruiker"
                  color: Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ----------------------------------------------------- snelknoppen --

          Button {
            width: parent.width
            text: root.away ? "Zet op aanwezig" : "Zet op afwezig (handmatig)"
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            bordered: true
            focusable: true
            enabled: root.geladen
            onClicked: root.wissel()
          }

          Text {
            width: parent.width
            text: "De hardware blijft leidend: 'aanwezig' zet alleen de handmatige stand terug, maar de watch-loop leest de echte dekselstand elke seconde."
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width }

          // ---------------------------------------------------- instellingen --

          PanelSectionHeader {
            width: parent.width
            text: "INSTELLINGEN"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Toggle {
            width: parent.width
            label: "Meldingen"
            description: "Desktopmelding bij deksel dicht, terug en klaar."
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            checked: root.meldingen
            enabled: root.geladen
            onClicked: root.zet("notify", root.meldingen ? "false" : "true")
          }

          Toggle {
            width: parent.width
            label: "Afwezig in clamshell"
            description: "Dicht deksel mét extern scherm telt als afwezig. Zet uit als je gewoon verder kijkt op het externe scherm."
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            checked: root.clamshell
            enabled: root.geladen
            onClicked: root.zet("awayInClamshell", root.clamshell ? "false" : "true")
          }

          Toggle {
            width: parent.width
            label: "Slaapstand als het klaar is"
            description: "De laptop gaat in slaapstand zodra alle sessies klaar zijn. Dit is de enige manier waarop lidswitch de machine in slaapstand stuurt."
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            checked: root.slaapAan
            enabled: root.geladen
            onClicked: root.zet("sleepWhenDone.enabled", root.slaapAan ? "false" : "true")
          }

          Toggle {
            width: parent.width
            label: "Alleen loggen (dry run)"
            description: "Zet uit voor echt slapen. De daemon logt dan elke keer wat er zou zijn gebeurd."
            foreground: root.barForeground
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            checked: root.dryRun
            enabled: root.geladen && root.slaapAan
            onClicked: root.zet("sleepWhenDone.dryRun", root.dryRun ? "false" : "true")
          }

          // De drempels zijn zinloos zonder de schakelaar erboven, dus ze gaan
          // mee uit én worden als inactief getekend.
          Column {
            width: parent.width
            spacing: Style.space(6)
            opacity: root.slaapAan ? 1 : 0.45

            Text {
              width: parent.width
              text: "Rust voordat hij slaapt: "
                + (sliderRust.dragging ? Math.round(sliderRust.liveValue) : root.waarde("sleepWhenDone.afterMinutes"))
                + " min"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            PanelSlider {
              id: sliderRust
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 120
              step: 1
              integer: true
              value: root.waarde("sleepWhenDone.afterMinutes")
              enabled: root.geladen && root.slaapAan
              onReleased: function (v) { root.zet("sleepWhenDone.afterMinutes", Math.round(v)) }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            opacity: root.slaapAan ? 1 : 0.45

            Text {
              width: parent.width
              text: "Minimaal weg voordat slapen mag: "
                + (sliderWeg.dragging ? Math.round(sliderWeg.liveValue) : root.waarde("sleepWhenDone.minAwayMinutes"))
                + " min"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            PanelSlider {
              id: sliderWeg
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: 120
              step: 1
              integer: true
              value: root.waarde("sleepWhenDone.minAwayMinutes")
              enabled: root.geladen && root.slaapAan
              onReleased: function (v) { root.zet("sleepWhenDone.minAwayMinutes", Math.round(v)) }
            }
          }

          PanelSeparator { width: parent.width }

          // -------------------------------------------------------- controle --

          PanelSectionHeader {
            width: parent.width
            text: "CONTROLE"
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          }

          Text {
            width: parent.width
            text: "Druk op c om `lidswitch check` te draaien. Dat kijkt ook naar logind en de service, wat hier vandaan het vaakst misgaat."
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: checkProc.running
            text: "bezig…"
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            width: parent.width
            visible: root.controle !== ""
            implicitHeight: controleTekst.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Color.menu.background

            Text {
              id: controleTekst
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(8)
              text: root.controle
              color: Color.muted
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            }
          }

          Text {
            width: parent.width
            text: "t = aanwezig/afwezig · r = verversen · c = controle · esc = sluiten"
            color: Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  Component.onCompleted: root.herlaad()
}
