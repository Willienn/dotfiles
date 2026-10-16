import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    property real contentSpacing: 2
    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.messageData?.content)

    property bool isUser: messageData?.role === 'user'
    property bool isAssistant: messageData?.role === 'assistant'
    property bool isInterface: messageData?.role === 'interface'
    property bool hovered: hoverHandler.hovered || root.editing
    
    readonly property real maxBubbleWidth: mainColumn.width * 0.85
    readonly property int contentChars: (root.messageData?.content ?? "").length
    readonly property bool shortMessage: !(root.messageData?.content ?? "").includes("\n") && contentChars < 60
    readonly property real estimatedBubbleWidth: Math.min(contentChars * 9 + 24, maxBubbleWidth)

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: mainColumn.implicitHeight

    function saveMessage() {
        if (!root.editing) return;
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");
        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift ||
            event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
            event.accepted = true
        }
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true
        }
    }

   HoverHandler {
        id: hoverHandler
    }

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4

        // === Header (assistant/interface only, subtle) ===
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            spacing: 6
            visible: !root.isUser

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: root.isAssistant ? "neurology" : "settings"
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.isAssistant
                    ? (Ai.models[root.messageData?.model]?.name ?? Translation.tr("Assistant"))
                    : Translation.tr("Interface")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // === Content ===
        Item {
            Layout.fillWidth: true
            implicitHeight: bubble.height

            Rectangle {
                id: bubble
                anchors.right: root.isUser ? parent.right : undefined
                anchors.left: root.isUser ? undefined : parent.left

                width: {
                    // Estimativa de largura natural pelo conteúdo
                    const content = root.messageData?.content ?? "";
                    const hasNewline = content.includes("\n");
                    const hasCode = content.includes("```");
                    const charCount = content.length;
                    const avgCharWidth = 7.5;
                    const padding = root.isUser ? 20 : 0;
                    const naturalWidth = charCount * avgCharWidth + padding;
                    const maxWidth = parent.width * (root.isUser ? 0.95 : 1.0);                    if (hasNewline || hasCode || charCount > 60) return maxWidth;
                    return Math.min(naturalWidth, maxWidth);
                }
                height: contentColumn.implicitHeight + (root.isUser ? 20 : 0)

                radius: root.isUser ? Appearance.rounding.normal : 0
                color: root.isUser ? Appearance.colors.colLayer2 : "transparent"
                clip: true
                Behavior on height {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: root.isUser ? 10 : 0
                    anchors.rightMargin: root.isUser ? 10 : 0
                    anchors.topMargin: root.isUser ? 10 : 0
                    spacing: root.contentSpacing

                    Loader {
                        Layout.fillWidth: true
                        active: root.messageData?.localFilePath && root.messageData?.localFilePath.length > 0
                        visible: active
                        sourceComponent: AttachedFileIndicator {
                            filePath: root.messageData?.localFilePath
                            canRemove: false
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                        visible: implicitHeight > 0
                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        FadeLoader {
                            id: loadingIndicatorLoader
                            anchors.centerIn: parent
                            shown: (root.messageBlocks.length < 1) && (!root.messageData.done)
                            sourceComponent: MaterialLoadingIndicator {
                                loading: true
                            }
                        }
                    }

                    ColumnLayout {
                        id: messageContentColumnLayout
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: ScriptModel {
                                values: root.messageBlocks
                            }
                            delegate: DelegateChooser {
                                id: messageDelegate
                                role: "type"

                                DelegateChoice { roleValue: "code"; MessageCodeBlock {
                                    editing: root.editing
                                    renderMarkdown: root.renderMarkdown
                                    enableMouseSelection: root.enableMouseSelection
                                    segmentContent: modelData.content
                                    segmentLang: modelData.lang
                                    messageData: root.messageData
                                } }
                                DelegateChoice { roleValue: "think"; MessageThinkBlock {
                                    editing: root.editing
                                    renderMarkdown: root.renderMarkdown
                                    enableMouseSelection: root.enableMouseSelection
                                    segmentContent: modelData.content
                                    messageData: root.messageData
                                    done: root.messageData?.done ?? false
                                    completed: modelData.completed ?? false
                                } }
                                DelegateChoice { roleValue: "text"; MessageTextBlock {
                                    editing: root.editing
                                    renderMarkdown: root.renderMarkdown
                                    enableMouseSelection: root.enableMouseSelection
                                    segmentContent: modelData.content
                                    messageData: root.messageData
                                    done: root.messageData?.done ?? false
                                    forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                                } }
                            }
                        }
                    }

                    Flow {
                        visible: root.messageData?.annotationSources?.length > 0
                        spacing: 5
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft
                        Repeater {
                            model: ScriptModel {
                                values: root.messageData?.annotationSources || []
                            }
                            delegate: AnnotationSourceButton {
                                required property var modelData
                                displayText: modelData.text
                                url: modelData.url
                            }
                        }
                    }

                    Flow {
                        visible: root.messageData?.searchQueries?.length > 0
                        spacing: 5
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft
                        Repeater {
                            model: ScriptModel {
                                values: root.messageData?.searchQueries || []
                            }
                            delegate: SearchQueryButton {
                                required property var modelData
                                query: modelData
                            }
                        }
                    }
                }
            }
        }

        // === Action buttons (hover only) ===
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.bottomMargin: 2
            spacing: 2
            opacity: root.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Item { Layout.fillWidth: root.isUser }

            ButtonGroup {
                spacing: 2

                AiMessageControlButton {
                    id: regenButton
                    visible: root.isAssistant
                    buttonIcon: "refresh"
                    onClicked: Ai.regenerate(root.messageIndex)
                    StyledToolTip { text: Translation.tr("Regenerate") }
                }

                AiMessageControlButton {
                    id: copyButton
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.messageData?.content
                        copyButton.activated = true
                        copyIconTimer.restart()
                    }
                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: copyButton.activated = false
                    }
                    StyledToolTip { text: Translation.tr("Copy") }
                }

                AiMessageControlButton {
                    id: editButton
                    activated: root.editing
                    enabled: root.messageData?.done ?? false
                    buttonIcon: "edit"
                    onClicked: {
                        root.editing = !root.editing
                        if (!root.editing) root.saveMessage()
                    }
                    StyledToolTip { text: root.editing ? Translation.tr("Save") : Translation.tr("Edit") }
                }

                AiMessageControlButton {
                    id: toggleMarkdownButton
                    visible: !root.isUser
                    activated: !root.renderMarkdown
                    buttonIcon: "code"
                    onClicked: root.renderMarkdown = !root.renderMarkdown
                    StyledToolTip { text: Translation.tr("View Markdown source") }
                }

                AiMessageControlButton {
                    id: deleteButton
                    buttonIcon: "close"
                    onClicked: Ai.removeMessage(root.messageIndex)
                    StyledToolTip { text: Translation.tr("Delete") }
                }
            }
        }
    }
}