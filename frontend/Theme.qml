pragma Singleton
import QtQuick

// The app's look: colors (dark / light), typography, metrics and animation
// timing. Nothing else: icons are in Icon.qml, helpers in Util.qml.
QtObject {
    // No pointer to hover with (phones): what shows on hover elsewhere must
    // stay visible there
    readonly property bool touchOnly: Qt.platform.os === "android" || Qt.platform.os === "ios"

    // Dark or light colors, from Settings > Appearance: "system" follows the
    // desktop's preference (dark when the desktop doesn't say).
    readonly property bool isDark: SettingsController.themeMode === "system"
                                   ? Application.styleHints.colorScheme !== Qt.ColorScheme.Light
                                   : SettingsController.themeMode !== "light"

    // Colors. Translucent ones work on any cover tint: white glazes in dark
    // mode, black ones in light mode.
    readonly property color background: isDark ? "#111116" : "#f3f3f7"
    readonly property color surface:    isDark ? "#17171e" : "#ffffff"
    readonly property color surfaceAlt: isDark ? "#1f1f28" : "#e9e9f0"
    readonly property color border:     isDark ? "#22ffffff" : "#1f000000"
    readonly property color hover:      isDark ? "#12ffffff" : "#0f000000"
    readonly property color selection:  isDark ? "#24ffffff" : "#1c000000"
    readonly property color accent:     isDark ? "#9b8cff" : "#6a55e0"
    readonly property color accentSoft: withAlpha(accent, 0.2)
    readonly property color text:       isDark ? "#ececf2" : "#1b1b22"
    // Phones: stronger greys, easier to read over the cover-tinted background
    readonly property color textMuted:  touchOnly ? (isDark ? "#a6a6b8" : "#4c4c5e")
                                                  : (isDark ? "#8b8b9e" : "#5f5f72")
    readonly property color textDim:    touchOnly ? (isDark ? "#6e6e82" : "#8a8a9c")
                                                  : (isDark ? "#5c5c6e" : "#9a9aab")
    readonly property color error:      isDark ? "#f06a6a" : "#d64545"

    // Glazes for fields, chips, headers and buttons (weakest to strongest)
    readonly property color fillSoft:   isDark ? "#0dffffff" : "#08000000"
    readonly property color fill:       isDark ? "#14ffffff" : "#0d000000"
    readonly property color fillHover:  isDark ? "#1fffffff" : "#14000000"
    readonly property color fillStrong: isDark ? "#24ffffff" : "#1a000000"
    // The playing song's row, and an active button while hovered
    readonly property color currentRow:      withAlpha(accent, 0.15)
    readonly property color currentRowHover: withAlpha(accent, 0.25)
    readonly property color accentSoftHover: withAlpha(accent, 0.3)
    readonly property color errorSoft:  withAlpha(error, 0.2)
    // Switch track (off), and while hovered
    readonly property color switchTrack:      isDark ? "#2effffff" : "#26000000"
    readonly property color switchTrackHover: isDark ? "#40ffffff" : "#33000000"
    // Behind dialogs; under panels (softens the cover tint); the lyrics capsule
    readonly property color scrim:      isDark ? "#99000000" : "#59000000"
    readonly property color panelShade: isDark ? "#4d000000" : "#73ffffff"
    readonly property color capsule:    isDark ? "#33000000" : "#14000000"
    readonly property color miniPlayer: isDark ? "#e61b1b23" : "#f2ffffff"
    readonly property color tooltip:    isDark ? "#f21f1f28" : "#f2ffffff"

    function withAlpha(c, alpha) {
        return Qt.rgba(c.r, c.g, c.b, alpha)
    }

    // Typography (phones: a step bigger, easier to read at arm's length)
    readonly property int fontSizeSmall: touchOnly ? 12 : 11
    readonly property int fontSize:      touchOnly ? 14 : 13
    readonly property int fontSizeLarge: touchOnly ? 17 : 16
    readonly property int fontSizeTitle: touchOnly ? 23 : 21

    // Metrics
    readonly property int spacing:      8
    readonly property int padding:      12
    readonly property int radius:       8
    readonly property int radiusLarge:  14
    readonly property int headerHeight: 46
    readonly property int radiusCard:   18 // floating panels
    readonly property int cardGap:      10 // space around / between panels

    // Animation
    // Scrolling: how fast a flick can go, and how quickly it slows down
    readonly property real flickVelocity: 12000
    readonly property real flickDeceleration: 2000

    readonly property int animFast:   120
    readonly property int anim:       220
    readonly property int animSlow:   420
    readonly property int easing:     Easing.OutCubic
    readonly property int easingBack: Easing.OutBack
    // Panels: quick, soft deceleration
    readonly property int animPanel:  300
    readonly property int easingPanel: Easing.OutCubic

    // Below this window width the app switches to the phone-like layout.
    readonly property int compactBreakpoint: 700
}
