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

    // IDs das mensagens que formam este turno (vem de Ai.turns)
    property string turnKey
    // Resolvido ao vivo no singleton (não depende do ScriptModel repassar objetos)
    readonly property var messageIds: Ai.idsForTurn(root.turnKey)
    readonly property int messageIndex: Ai.messageIDs.indexOf(root.messageIds[0])
    property var messageInputField

    property real contentSpacing: 2
    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    // Mensagens do turno, sem undefined (protege contra ordem de atualização)
    readonly property var turnMessages: root.messageIds
        .map(id => Ai.messageByID[id])
        .filter(m => m !== undefined && m !== null)

    // Última mensagem do turno (done, anotações, pendingAction)
    readonly property var messageData: turnMessages.length > 0
        ? turnMessages[turnMessages.length - 1] : null
    // Primeira mensagem do turno (nome do modelo)
    readonly property var firstData: turnMessages.length > 0 ? turnMessages[0] : null

    property bool isUser: messageData?.role === 'user'
    property bool isAssistant: messageData?.role === 'assistant'
    property bool isInterface: messageData?.role === 'interface'
    property bool hovered: hoverHandler.hovered || root.editing
    readonly property bool canEdit: root.turnMessages.length === 1

    // Conteúdo: junta todas as mensagens de assistant do turno
    readonly property string displayContent: {
        if (!root.isAssistant) return root.messageData?.content ?? "";
        let all = "";
        for (const msg of root.turnMessages) {
            if (msg.role !== "assistant") continue;
            let c = msg.content ?? "";
            const opens = (c.match(/<think>/g) || []).length;
            const closes = (c.match(/<\/think>/g) || []).length;
            for (let k = closes; k < opens; k++) c += "\n</think>";
            if (c.length > 0) {
                all += c;
                if (!c.endsWith("\n")) all += "\n\n";
            }
        }
        // Remove blocos de ação/json do texto exibido
        return all.replace(/```(?:action|json)[\s\S]*?(?:```|$)/g, "").trim();
    }

    // Chips de ação: acumula todas as ações do turno
    readonly property var actionNames: {
        if (!root.isAssistant) return [];
        const names = [];
        for (const msg of root.turnMessages) {
            if (msg.role !== "assistant") continue;
            // Tool calling nativo (Ollama/OpenAI): nomes vêm de msg.tool_calls
            for (const tc of (msg.tool_calls ?? [])) {
                names.push(tc?.function?.name ?? "?");
            }
            // Protocolo de texto (```action)
            const re = /```(?:action|json)\s*([\s\S]*?)```/g; // regex novo por mensagem
            const raw = msg.rawContent ?? "";
            let match;
            while ((match = re.exec(raw)) !== null) {
                try {
                    const parsed = JSON.parse(match[1]);
                    (Array.isArray(parsed) ? parsed : [parsed]).forEach(p => names.push(p?.name ?? "?"));
                } catch (e) {
                    names.push("?");
                }
            }
        }
        return names;
    }

    readonly property string actionName: root.actionNames.length === 0 ? ""
        : (root.actionNames.length === 1 ? root.actionNames[0]
            : `${root.actionNames.length} ações: ${root.actionNames.join(", ")}`)
    readonly property bool hasPendingAction: root.isAssistant
        && Ai.pendingAction !== null
        && root.turnMessages.some(m => m === Ai.pendingAction.message)

    property list<var> messageBlocks: StringUtils.splitMarkdownBlocks(root.displayContent)

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

    // DEBUG temporário: remova depois que funcionar
    Component.onCompleted: console.log("[AiMessage] key=" + root.turnKey + " ids=" + JSON.stringify(root.messageIds) + " msgs=" + root.turnMessages.length)

    HoverHandler {
        id: hoverHandler
    }

    ColumnLayout {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4

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
                    ? (Ai.models[root.firstData?.model]?.name ?? Translation.tr("Assistant"))
                    : Translation.tr("Interface")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: bubble.height

            Rectangle {
                id: bubble
                anchors.right: root.isUser ? parent.right : undefined
                anchors.left: root.isUser ? undefined : parent.left

                width: {
                    const content = root.displayContent;
                    const hasNewline = content.includes("\n");
                    const hasCode = content.includes("```");
                    const charCount = content.length;
                    const avgCharWidth = 7.5;
                    const padding = root.isUser ? 20 : 0;
                    const naturalWidth = charCount * avgCharWidth + padding;
                    const maxWidth = parent.width * (root.isUser ? 0.95 : 1.0);
                    if (hasNewline || hasCode || charCount > 60) return maxWidth;
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
                        active: (root.messageData?.localFilePath ?? "").length > 0
                        visible: active
                        sourceComponent: AttachedFileIndicator {
                            filePath: root.messageData?.localFilePath ?? ""
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
                            shown: (root.messageBlocks.length < 1) && (!(root.messageData?.done ?? true))
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
                                    forceDisableChunkSplitting: root.displayContent.includes("```")
                                } }
                            }
                        }
                    }

                    RowLayout {
                        visible: root.actionName.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 6

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                            text: "bolt"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                            text: root.hasPendingAction ? Ai.pendingAction.summary : root.actionName
                        }
                        Loader {
                            active: root.hasPendingAction
                            visible: active
                            sourceComponent: ButtonGroup {
                                GroupButton {
                                    contentItem: StyledText {
                                        text: Translation.tr("Reject")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer2
                                    }
                                    onClicked: Ai.denyAction()
                                }
                                GroupButton {
                                    toggled: true
                                    contentItem: StyledText {
                                        text: Translation.tr("Approve")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3onPrimary
                                    }
                                    onClicked: Ai.approveAction()
                                }
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
                        Quickshell.clipboardText = root.displayContent
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
                    enabled: (root.messageData?.done ?? false) && root.canEdit
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
                    onClicked: {
                        // Remove o turno inteiro, incluindo mensagens tool no meio
                        const first = Ai.messageIDs.indexOf(root.messageIds[0]);
                        const last = Ai.messageIDs.indexOf(root.messageIds[root.messageIds.length - 1]);
                        for (let i = last; i >= first; i--) Ai.removeMessage(i);
                    }
                    StyledToolTip { text: Translation.tr("Delete") }
                }
            }
        }
    }
}
