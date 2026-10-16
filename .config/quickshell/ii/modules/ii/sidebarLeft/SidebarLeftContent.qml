import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.updates
import qs.modules.ii.sidebarLeft.dotfiles
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    // Abas
    property bool aiChatEnabled: true
    property bool portsEnabled: true
    property bool monitorEnabled: true
    property bool updatesEnabled: true
    property bool dotfilesEnabled: true

    // A ordem aqui precisa bater com a ordem de contentChildren
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.portsEnabled ? [{"icon": "lan", "name": "Portas"}] : []),
        ...(root.monitorEnabled ? [{"icon": "monitor_heart", "name": "Sistema"}] : []),
        ...(root.updatesEnabled ? [{"icon": "update", "name": "Atualizações"}] : []),
        ...(root.dotfilesEnabled ? [{"icon": "folder_managed", "name": "Dotfiles"}] : [])
    ]
    // Notifica o pai quando a aba de IA está ativa
    property int tabCount: swipeView.count
    readonly property bool aiTabActive: root.aiChatEnabled && swipeView.currentIndex === 0

    Component.onCompleted: {
        if (scopeRoot) scopeRoot.aiTabActive = aiTabActive;
    }
    onAiTabActiveChanged: {
        if (scopeRoot) scopeRoot.aiTabActive = aiTabActive
    }

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Flickable {
            id: tabFlick
            visible: root.tabButtonList.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: tabBarContent.implicitHeight
            contentWidth: Math.max(tabBarContent.implicitWidth, width)
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width

            function scrollToCurrentTab() {
                const maxScroll = Math.max(0, contentWidth - width);
                if (root.tabCount <= 1 || maxScroll <= 0) return;
                const idx = Math.max(0, Math.min(root.tabCount - 1, swipeView.currentIndex));
                contentX = (idx / (root.tabCount - 1)) * maxScroll;
            }

            Behavior on contentX {
                enabled: !tabFlick.dragging
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Connections {
                target: swipeView
                function onCurrentIndexChanged() { tabFlick.scrollToCurrentTab(); }
            }

            Component.onCompleted: scrollToCurrentTab()

            Toolbar {
                id: tabBarContent
                width: implicitWidth
                height: tabFlick.height
                enableShadow: false
                ToolbarTabBar {
                    id: tabBar
                    Layout.alignment: Qt.AlignHCenter
                    tabButtonList: root.tabButtonList
                    currentIndex: swipeView.currentIndex
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView {
                id: swipeView
                anchors.fill: parent
                spacing: 10
                currentIndex: tabBar.currentIndex

                onCurrentIndexChanged: {
                    if (scopeRoot) scopeRoot.aiTabActive = root.aiTabActive;
                }

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                contentChildren: [
                    ...(root.aiChatEnabled ? [aiChat.createObject()] : []),
                    ...(root.portsEnabled ? [ports.createObject()] : []),
                    ...(root.monitorEnabled ? [sysMonitor.createObject()] : []),
                    ...(root.updatesEnabled ? [updates.createObject()] : []),
                    ...(root.dotfilesEnabled ? [dotfiles.createObject()] : []),
                ]
            }
        }

        Component { id: aiChat; AiChat {} }
        Component { id: ports; Ports {} }
        Component { id: sysMonitor; SystemMonitor {} }
        Component { id: updates; Updates {} }
        Component { id: dotfiles; Dotfiles {} }
    }
}