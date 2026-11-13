import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget for lidswitch. The icon shows whether you are away and whether work
// is still running; the panel is the overview plus the settings that are safe to
// change from here. Everything it shows or changes goes through
// bin/lidswitch-widget, which is a thin wrapper over the CLI, so the widget never
// becomes a second writer of lid.json or config.json.
Panel {
  id: root
  moduleName: "lidswitch"
  ipcTarget: "lidswitch"

  implicitWidth: button.implicitWidth
  implicitHeight: bar ? bar.barSize : 26

  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/lidswitch/bin/lidswitch-widget"

  // Prefixed names, because QML reserves the plain ones: `data` is the child
  // list of an Item, and shadowing it breaks every child declared below.
  property bool bezig: false
  property string ruweStatus: ""
  property string ruweConfig: ""
  property string controleUit: ""
  property var info: ({})

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
  readonly property int busyCount: sessions.filter(s => s.busy).length
  readonly property int waitingCount: sessions.filter(s => s.waiting).length
  readonly property int openTodoCount: sessions.reduce((a, s) => a + (s.openTodos || 0), 0)

  // Effective config as the CLI will read it. Defaults are already filled in by
  // the script, so a slider bound here shows the value in force, not a guess.
  property bool cfgGeladen: false
  property var cfg: ({})
  readonly property bool meldingen: cfg.notify === true
  readonly property bool clamshell: cfg.awayInClamshell === true
  readonly property var slaap: cfg.sleepWhenDone || ({})

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

  function run(args, done) {
    if (root.bezig) return
    root.bezig = true
    proc.args = args
    proc.done = done
    proc.running = true
  }

  function herlaad() { run(["status-json", "config"], function (d) { root.info = d.status; root.cfg = d.config; root.cfgGeladen = true }) }
  function wissel() { run(["toggle", "config"], function (d) { root.info = d.status; root.cfg = d.config }) }

  // Toggles are written straight away: a switch that only remembers its own
  // position until the panel closes is worse than one that does nothing.
  function zet(pad, waarde) {
    run(["set", pad + "=" + waarde, "status-json", "config"], function (d) {
      root.info = d.status
      root.cfg = d.config
      root.cfgGeladen = true
    })
  }

  // Sliders only write on release. Committing per drag step would rewrite
  // config.json dozens of times for one gesture.
  function zetSlider(pad, waarde) {
    var v = Math.round(waarde)
    if (String(v) === String(root.opgeslagenWaarde(pad))) return
    root.tijdelijk[pad] = v
    root.zet(pad, String(v))
  }

  property var tijdelijk: ({})

  function opgeslagenWaarde(pad) {
    if (root.tijdelijk[pad] !== undefined) return root.tijdelijk[pad]
    var delen = pad.split(".")
    var v = root.cfg
    for (var i = 0; i < delen.length; i++) v = v ? v[delen[i]] : undefined
    return v === undefined ? 0 : v
  }

  function sliderWaarde(pad) {
    return Number(root.opgeslagenWaarde(pad))
  }

  // ---------------------------------------------------------------- proces --

  Process {
    id: proc
    property var done: null
    property var args: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text).trim().split("\n").filter(l => l.trim() !== "")
        var parsed = []
        for (var i = 0; i < lines.length; i++) {
          try { parsed.push(JSON.parse(lines[i])) } catch (e) { /* geen json, overslaan */ }
        }
        if (root.proc.done) root.proc.done(parsed)
        root.bezig = false
      }
    }
    onExited: root.bezig = false
  }

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
      Item {
        anchors.fill: parent
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
      onActivateRequested: root.wissel()
      onCloseRequested: root.close()
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.herlaad()
        if (t === "c" || t === "C") { root.controleUit = ""; root.run(["check"], function (d) { root.controleUit = d.length ? d[d.length - 1].out || "" : "" }) }
      }
    }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: kolom.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      Column {
        id: kolom
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          width: parent.width
          text: "LIDSWITCH"
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        // ------------------------------------------------------------ stand --

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

        // -------------------------------------------------- uitgestelde vragen --

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
            implicitHeight: uitgesteldKolom.implicitHeight + Style.space(10)
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

        // --------------------------------------------------------- snelknop --

        PanelSectionHeader {
          width: parent.width
          text: "SNELKNOPPEN"
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        }

        Rectangle {
          width: parent.width
          implicitHeight: nuAanwezig.implicitHeight + Style.space(20)
          radius: Style.cornerRadius
          color: hoverAanwezig.containsMouse ? Color.menu.selectedBackground : Color.menu.background

          Text {
            id: nuAanwezig
            anchors.centerIn: parent
            text: root.away ? "Zet op aanwezig" : "Zet op afwezig (handmatig)"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          MouseArea {
            id: hoverAanwezig
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.wissel()
          }
        }

        Text {
          width: parent.width
          text: "De hardware blijft leidend: 'aanwezig' zet alleen het handmatige omslaggevaar weg, maar de watch-loop leest de echte stand elke seconde."
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator { width: parent.width }

        // ------------------------------------------------------- instellingen --

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
          enabled: root.cfgGeladen
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
          enabled: root.cfgGeladen
          onClicked: root.zet("awayInClamshell", root.clamshell ? "false" : "true")
        }

        Toggle {
          width: parent.width
          label: "Slaapstand als het klaar is"
          description: "De laptop gaat in slaapstand zodra alle sessies klaar zijn. Dit is de enige manier waarop lidswitch de machine in slaapstand stuurt."
          foreground: root.barForeground
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          checked: root.slaap.enabled === true
          enabled: root.cfgGeladen
          onClicked: root.zet("sleepWhenDone.enabled", root.slaap.enabled === true ? "false" : "true")
        }

        Toggle {
          width: parent.width
          label: "Alleen loggen (dry run)"
          description: "Zet uit voor echt slapen. De daemon logt dan elke keer wat er zou zijn gebeurd."
          foreground: root.barForeground
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          checked: root.slaap.dryRun === true
          enabled: root.cfgGeladen && root.slaap.enabled === true
          onClicked: root.zet("sleepWhenDone.dryRun", root.slaap.dryRun === true ? "false" : "true")
        }

        // De drempels zijn zinloos zonder de schakelaar erboven, dus ze worden
        // niet alleen disabled maar ook weergegeven als inactief.
        Item {
          width: parent.width
          implicitHeight: rustLabel.implicitHeight + sliderRust.implicitHeight + sliderWeg.implicitHeight + Style.space(24)
          opacity: root.slaap.enabled === true ? 1 : 0.45

          Text {
            id: rustLabel
            width: parent.width
            text: "Rust voordat hij slaapt: " + root.sliderWaarde("sleepWhenDone.afterMinutes") + " min"
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
            integer: true
            value: root.sliderWaarde("sleepWhenDone.afterMinutes")
            enabled: root.slaap.enabled === true
            onReleased: function (v) { root.zetSlider("sleepWhenDone.afterMinutes", v) }
          }
        }

        Item {
          width: parent.width
          implicitHeight: wegLabel.implicitHeight + sliderWeg.implicitHeight + Style.space(12)
          opacity: root.slaap.enabled === true ? 1 : 0.45

          Text {
            id: wegLabel
            width: parent.width
            text: "Minimaal weg voordat slapen mag: " + root.sliderWaarde("sleepWhenDone.minAwayMinutes") + " min"
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
            integer: true
            value: root.sliderWaarde("sleepWhenDone.minAwayMinutes")
            enabled: root.slaap.enabled === true
            onReleased: function (v) { root.zetSlider("sleepWhenDone.minAwayMinutes", v) }
          }
        }

        PanelSeparator { width: parent.width }

        // ------------------------------------------------------------ controle --

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

        Rectangle {
          width: parent.width
          visible: root.controleUit !== ""
          implicitHeight: controleTekst.implicitHeight + Style.space(16)
          radius: Style.cornerRadius
          color: Color.menu.background

          Text {
            id: controleTekst
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            text: root.controleUit
            color: Color.muted
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          }
        }

        Text {
          width: parent.width
          text: "enter = aanwezig/afwezig · r = verversen · c = controle · esc = sluiten"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  Component.onCompleted: root.herlaad()
}