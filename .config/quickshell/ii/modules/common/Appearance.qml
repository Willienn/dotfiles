import QtQuick
import Quickshell
import qs.modules.common.functions
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject sizes
    property string syntaxHighlightingTheme

    // Transparency. The quadratic functions were derived from analysis of hand-picked transparency values.
    ColorQuantizer {
        id: wallColorQuant
        property string wallpaperPath: Config.options.background.wallpaperPath
        property bool wallpaperIsVideo: wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm") || wallpaperPath.endsWith(".mkv") || wallpaperPath.endsWith(".avi") || wallpaperPath.endsWith(".mov")
        source: Qt.resolvedUrl(wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath)
        depth: 0 // 2^0 = 1 color
        rescaleSize: 10
    }
    property real wallpaperVibrancy: (wallColorQuant.colors[0]?.hslSaturation + wallColorQuant.colors[0]?.hslLightness) / 2
    property real autoBackgroundTransparency: { // y = 0.5768x^2 - 0.759x + 0.2896
        let x = wallpaperVibrancy
        let y = 0.5768 * (x * x) - 0.759 * (x) + 0.2896
        return Math.max(0, Math.min(0.22, y)) - 0.12 * (m3colors.darkmode ? 0 : 1)
    }
    property real autoContentTransparency: 0.9
    property real backgroundTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoBackgroundTransparency : Config?.options.appearance.transparency.backgroundTransparency : 0
    property real contentTransparency: Config?.options.appearance.transparency.automatic ? autoContentTransparency : Config?.options.appearance.transparency.contentTransparency

    m3colors: QtObject {
    property bool darkmode: true
    property bool transparent: false

    // ── Fundos: só os 4 tons que existem no sideBerry.css ──
    property color m3background: "#151515"              // --frame-bg
    property color m3onBackground: "#f4decd"            // --frame-fg
    property color m3surface: "#151515"                 // = bg (Firefox não separa)
    property color m3surfaceDim: "#151515"
    property color m3surfaceBright: "#272a28"           // --frame-el-overlay-hover-bg
    property color m3surfaceContainerLowest: "#151515"
    property color m3surfaceContainerLow: "#1e1f1e"     // --popup-bg
    property color m3surfaceContainer: "#1e1f1e"        // idem
    property color m3surfaceContainerHigh: "#272a28"    // --frame-el-overlay-hover-bg
    property color m3surfaceContainerHighest: "#3b403c" // --border
    property color m3onSurface: "#f4decd"
    property color m3surfaceVariant: "#272a28"
    property color m3onSurfaceVariant: "#f4decd"
    property color m3inverseSurface: "#f4decd"
    property color m3inverseOnSurface: "#151515"

    // ── Bordas ──
    property color m3outline: "#3b403c"                 // --border
    property color m3outlineVariant: "#272a28"          // borda sutil

    // ── Shadow/scrim/tint ──
    property color m3shadow: "#000000"
    property color m3scrim: "#000000"
    property color m3surfaceTint: "#ef934d"

    // ── Accent ──
    property color m3primary: "#ef934d"                 // --accent
    property color m3onPrimary: "#151515"
    property color m3primaryContainer: "#272a28"
    property color m3onPrimaryContainer: "#ef934d"
    property color m3inversePrimary: "#ef934d"

    // ── Secondary ──
    property color m3secondary: "#f4b585"               // --color-accent-secondary
    property color m3onSecondary: "#151515"
    property color m3secondaryContainer: "#272a28"
    property color m3onSecondaryContainer: "#f4b585"

    // ── Tertiary ──
    property color m3tertiary: "#efbf71"                // --status-notice
    property color m3onTertiary: "#151515"
    property color m3tertiaryContainer: "#272a28"
    property color m3onTertiaryContainer: "#efbf71"

    // ── Error ──
    property color m3error: "#f16e65"                   // --status-err
    property color m3onError: "#151515"
    property color m3errorContainer: "#1e1f1e"          // Firefox não tem bg de erro
    property color m3onErrorContainer: "#f16e65"

    // ── Fixed (Firefox não distingue → espelha o accent) ──
    property color m3primaryFixed: "#ef934d"
    property color m3primaryFixedDim: "#ef934d"
    property color m3onPrimaryFixed: "#151515"
    property color m3onPrimaryFixedVariant: "#151515"
    property color m3secondaryFixed: "#f4b585"
    property color m3secondaryFixedDim: "#f4b585"
    property color m3onSecondaryFixed: "#151515"
    property color m3onSecondaryFixedVariant: "#151515"
    property color m3tertiaryFixed: "#efbf71"
    property color m3tertiaryFixedDim: "#efbf71"
    property color m3onTertiaryFixed: "#151515"
    property color m3onTertiaryFixedVariant: "#151515"

    // ── Success ──
    property color m3success: "#7ec97e"                 // --status-ok
    property color m3onSuccess: "#151515"
    property color m3successContainer: "#272a28"
    property color m3onSuccessContainer: "#7ec97e"

    // ── Terminal (de userContent.css) ──
    property color term0: "#151515"
    property color term1: "#f16e65"
    property color term2: "#7ec97e"
    property color term3: "#efbf71"
    property color term4: "#71b4d6"
    property color term5: "#ef934d"
    property color term6: "#7ec9a3"
    property color term7: "#f4decd"
    property color term8: "#3b403c"
    property color term9: "#f16e65"
    property color term10: "#7ec97e"
    property color term11: "#efbf71"
    property color term12: "#71b4d6"
    property color term13: "#ef934d"
    property color term14: "#7ec9a3"
    property color term15: "#f4decd"
}

   colors: QtObject {
    // Subtext = #f4decd em 75% sobre #151515 (o que o --tabs-discarded-title-opacity faz)
    property color colSubtext: "#bcac9f"
    // Layer 0 (bg)
    property color colLayer0Base: "#151515"
    property color colLayer0: "#151515"
    property color colOnLayer0: "#f4decd"
    property color colLayer0Hover: "#272a28"
    property color colLayer0Active: "#3b403c"
    property color colLayer0Border: "#3b403c"
    // Layer 1 (surface)
    property color colLayer1Base: "#1e1f1e"
    property color colLayer1: "#1e1f1e"
    property color colOnLayer1: "#f4decd"
    property color colOnLayer1Inactive: "#bcac9f"
    property color colLayer1Hover: "#272a28"
    property color colLayer1Active: "#3b403c"
    // Layer 2 (hover)
    property color colLayer2Base: "#272a28"
    property color colLayer2: "#272a28"
    property color colLayer2Hover: "#3b403c"
    property color colLayer2Active: "#3b403c"
    property color colLayer2Disabled: "#1e1f1e"
    property color colOnLayer2: "#f4decd"
    property color colOnLayer2Disabled: "#bcac9f"
    // Layer 3 (border — cap, sem subir mais)
    property color colLayer3Base: "#3b403c"
    property color colLayer3: "#3b403c"
    property color colLayer3Hover: "#3b403c"
    property color colLayer3Active: "#3b403c"
    property color colOnLayer3: "#f4decd"
    // Layer 4 (mesmo cap)
    property color colLayer4Base: "#3b403c"
    property color colLayer4: "#3b403c"
    property color colLayer4Hover: "#3b403c"
    property color colLayer4Active: "#3b403c"
    property color colOnLayer4: "#f4decd"
    // Primary (= --accent, sem variante de hover — Firefox não muda accent no hover)
    property color colPrimary: "#ef934d"
    property color colOnPrimary: "#151515"
    property color colPrimaryHover: "#ef934d"
    property color colPrimaryActive: "#ef934d"
    property color colPrimaryContainer: "#272a28"
    property color colPrimaryContainerHover: "#3b403c"
    property color colPrimaryContainerActive: "#3b403c"
    property color colOnPrimaryContainer: "#ef934d"
    // Secondary (= --color-accent-secondary)
    property color colSecondary: "#f4b585"
    property color colSecondaryHover: "#f4b585"
    property color colSecondaryActive: "#f4b585"
    property color colOnSecondary: "#151515"
    property color colSecondaryContainer: "#272a28"
    property color colSecondaryContainerHover: "#3b403c"
    property color colSecondaryContainerActive: "#3b403c"
    property color colOnSecondaryContainer: "#f4b585"
    // Tertiary (= --status-notice)
    property color colTertiary: "#efbf71"
    property color colTertiaryHover: "#efbf71"
    property color colTertiaryActive: "#efbf71"
    property color colOnTertiary: "#151515"
    property color colTertiaryContainer: "#272a28"
    property color colTertiaryContainerHover: "#3b403c"
    property color colTertiaryContainerActive: "#3b403c"
    property color colOnTertiaryContainer: "#efbf71"
    // Surface
    property color colBackgroundSurfaceContainer: "#1e1f1e"
    property color colSurfaceContainerLow: "#151515"
    property color colSurfaceContainer: "#1e1f1e"
    property color colSurfaceContainerHigh: "#272a28"
    property color colSurfaceContainerHighest: "#3b403c"
    property color colSurfaceContainerHighestHover: "#3b403c"
    property color colSurfaceContainerHighestActive: "#3b403c"
    property color colOnSurface: "#f4decd"
    property color colOnSurfaceVariant: "#f4decd"
    // Misc
    property color colTooltip: "#1e1f1e"
    property color colOnTooltip: "#f4decd"
    property color colScrim: "#80000000"
    property color colShadow: "#00000000"   // Firefox usa border 1px, não blur → sem sombra
    property color colOutline: "#3b403c"
    property color colOutlineVariant: "#3b403c"
    property color colError: "#f16e65"
    property color colErrorHover: "#f16e65"
    property color colErrorActive: "#f16e65"
    property color colOnError: "#151515"
    property color colErrorContainer: "#272a28"
    property color colErrorContainerHover: "#3b403c"
    property color colErrorContainerActive: "#3b403c"
    property color colOnErrorContainer: "#f16e65"
}
    rounding: QtObject {
    property int unsharpen: 4       // (mantém, é quase nada)
    property int unsharpenmore: 4   // era 6
    property int verysmall: 4       // era 8
    property int small: 4           // era 12
    property int normal: 5          // era 17
    property int large: 7           // era 23
    property int verylarge: 9       // era 30
    property int full: 9999         // mantém — usado pra círculos funcionais
    property int screenRounding: 0  // sem cantos de tela
    property int windowRounding: 0  // Firefox não tem
}

    font: QtObject {
        property QtObject family: QtObject {
            property string main: Config.options.appearance.fonts.main
            property string numbers: Config.options.appearance.fonts.numbers
            property string title: Config.options.appearance.fonts.title
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: Config.options.appearance.fonts.iconNerd
            property string monospace: Config.options.appearance.fonts.monospace
            property string reading: Config.options.appearance.fonts.reading
            property string expressive: Config.options.appearance.fonts.expressive
        }
        property QtObject variableAxes: QtObject {
            property var main: ({
                "wght": 450,
                "wdth": 100,
            })
            property var numbers: ({
                "wght": 450,
            })
            property var title: ({ // Slightly bold weight for title
                "wght": 550, // Weight (Lowered to compensate for increased grade)
            })
        }
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            property int smaller: 12
            property int smallie: 13
            property int small: 15
            property int normal: 16
            property int large: 17
            property int larger: 19
            property int huge: 22
            property int hugeass: 23
            property int title: huge
        }
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
        readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1] // Default, 650ms
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1] // Default, 200ms
        readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property real expressiveFastSpatialDuration: 350
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveSlowSpatialDuration: 650
        readonly property real expressiveEffectsDuration: 200
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveSmall: QtObject {
            property int duration: animationCurves.expressiveFastSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveFastSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveSmall.duration
                    easing.type: root.animation.elementMoveSmall.type
                    easing.bezierCurve: root.animation.elementMoveSmall.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveExit: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: 850
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
        }

        property QtObject elementResize: QtObject {
            property int duration: 300
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }

        property QtObject clickBounce: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 850
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.clickBounce.duration
                easing.type: root.animation.clickBounce.type
                easing.bezierCurve: root.animation.clickBounce.bezierCurve
            }}
        }
        
        property QtObject scroll: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: root.animationCurves.standardDecel
        }

        property QtObject menuDecel: QtObject {
            property int duration: 350
            property int type: Easing.OutExpo
        }
    }

    sizes: QtObject {
        property real baseBarHeight: 40
        property real barHeight: Config.options.bar.cornerStyle === 1 ? 
            (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: 10
        property real fabShadowRadius: 5
        property real fabHoveredShadowRadius: 7
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real mediaControlsHeight: 160
        property real notificationPopupWidth: 410
        property real osdWidth: 180
        property real searchWidthCollapsed: 210
        property real searchWidth: 360
        property real sidebarWidth: 460
        property real sidebarWidthExtended: 750
        property real baseVerticalBarWidth: 46
        property real verticalBarWidth: Config.options.bar.cornerStyle === 1 ? 
            (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
        property real wallpaperSelectorWidth: 1200
        property real wallpaperSelectorHeight: 690
        property real wallpaperSelectorItemMargins: 8
        property real wallpaperSelectorItemPadding: 6
    }

    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
