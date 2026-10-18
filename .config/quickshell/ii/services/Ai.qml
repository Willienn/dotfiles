pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 *
 * Two action mechanisms coexist:
 * 1. **Tool calling** (OpenAI/Mistral format): the model emits native `tool_calls`,
 *    we execute and return results as `role: "tool"` messages. Fast, structured.
 * 2. **Text protocol** (` ```action {json} ``` `): fallback for models without
 *    tool calling support. Has approval flow for `risk: "confirm"` actions.
 *
 * Web search runs BEFORE each message (when enabled) instead of via tool calling.
 * System actions are validated against a whitelist (`systemActions`) before execution.
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var visibleMessageIDs: root.messageIDs.filter(id => {
        const msg = root.messageByID[id];
        return msg?.visibleToUser ?? true;
    })

    // ---------------------------------------------------------------
    // Turnos: o que o AiChat renderiza (UMA bolha por turno).
    // Mensagens de assistant consecutivas (separadas só por tool/ocultas)
    // viram um único turno. Cada item: { key, role, ids }.
    // ---------------------------------------------------------------
    readonly property var turns: {
        const ids = root.messageIDs;
        const byID = root.messageByID;
        const out = [];
        let current = null;

        for (const id of ids) {
            const msg = byID[id];
            if (!msg) continue;                       // guarda contra ordem de atualização
            const visible = msg.visibleToUser ?? true;

            if (msg.role === "assistant") {
                if (current) current.ids.push(id);
                else {
                    current = { key: id, role: "assistant", ids: [id] };
                    out.push(current);
                }
            } else if (visible && (msg.role === "user" || msg.role === "interface")) {
                out.push({ key: id, role: msg.role, ids: [id] });
                current = null;                       // fecha o turno
            }
            // tool / ocultas: ignora e mantém o turno aberto
        }
        return out;
    }

    // Só as chaves (strings) — é isso que o ListView recebe, como antes com visibleMessageIDs.
    readonly property var turnKeys: root.turns.map(t => t.key)

    // IDs das mensagens do turno que começa em `key`. Função (não propriedade) para o
    // delegate poder chamá-la direto, sem depender de ler Ai.turns de outro arquivo.
    function idsForTurn(key) {
        const ids = root.messageIDs;
        const idx = ids.indexOf(key);
        if (idx === -1) return [];
        const first = root.messageByID[key];
        if (!first || first.role !== "assistant") return [key];
        const out = [key];
        for (let i = idx + 1; i < ids.length; i++) {
            const msg = root.messageByID[ids[i]];
            if (!msg) continue;
            if (msg.role === "assistant") out.push(ids[i]);
            else if ((msg.visibleToUser ?? true) && (msg.role === "user" || msg.role === "interface")) break;
        }
        return out;
    }

    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property bool webSearchEnabled: Persistent.states?.ai?.webSearchEnabled ?? false
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    // ---------------------------------------------------------------
    // System actions
    // ---------------------------------------------------------------
    property var pendingAction: null
    property int actionChainDepth: 0
    property bool chainTainted: false
    property var actionQueue: []
    property var actionResults: []
    property string actionBatchName: "action"

    // Tool-calling state
    property var toolQueue: []
    property int toolCallDepth: 0
    readonly property int maxToolCallDepth: 10

    // Guard contra thinking loops: aborta se rawContent passar disso
    readonly property int maxRawContentLength: 12000

    readonly property var systemActions: ({
        // ---- Hyprland (Lua API, 0.49+) ----
        "hypr_workspace": {
            risk: "safe",
            description: "Switch to a Hyprland workspace by ID",
            build: a => {
                const id = parseInt(a.id);
                if (isNaN(id) || id < 1 || id > 99) throw new Error("workspace must be 1-99");
                return ["hyprctl", "dispatch", `hl.dsp.focus({ workspace = ${id} })`];
            }
        },
        "hypr_reload": {
            risk: "safe",
            description: "Reload the Hyprland configuration",
            build: a => ["hyprctl", "reload"]
        },
        "hypr_dispatch": {
            risk: "confirm",
            description: "Dispatch a Hyprland window action (requires approval)",
            build: a => {
                const allowed = ["togglefloating", "fullscreen", "killactive", "movetoworkspace", "togglesplit"];
                if (!allowed.includes(a.dispatcher)) throw new Error("dispatcher not allowed");
                let luaExpr;
                switch (a.dispatcher) {
                    case "togglefloating": luaExpr = 'hl.dsp.window.float({ action = "toggle" })'; break;
                    case "fullscreen":     luaExpr = 'hl.dsp.window.fullscreen({ action = "toggle" })'; break;
                    case "killactive":     luaExpr = 'hl.dsp.window.close()'; break;
                    case "movetoworkspace": {
                        const ws = parseInt(a.arg);
                        if (isNaN(ws) || ws < 1 || ws > 99) throw new Error("workspace must be 1-99");
                        luaExpr = `hl.dsp.window.move({ workspace = ${ws} })`;
                        break;
                    }
                    case "togglesplit":    luaExpr = 'hl.dsp.layout("togglesplit")'; break;
                    default: throw new Error("dispatcher not implemented");
                }
                return ["hyprctl", "dispatch", luaExpr];
            }
        },
        "volume": {
            risk: "safe",
            description: "Set audio volume percentage (0-100)",
            build: a => ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
                         (Math.max(0, Math.min(100, parseInt(a.percent))) / 100).toFixed(2)]
        },
        "brightness": {
            risk: "safe",
            description: "Set screen brightness percentage (1-100)",
            build: a => ["brightnessctl", "set", `${Math.max(1, Math.min(100, parseInt(a.percent)))}%`]
        },
        "system_update": {
            risk: "confirm",
            description: "Run a system package update in a terminal (requires approval)",
            build: a => ["kitty", "fish", "-c", "yay -Syu; read -P 'Enter to close'"]
        },

        // ---- Query (read-only) ----
        "hypr_active_window": {
            risk: "safe",
            untrusted: true,
            description: "Get info about the focused window",
            build: a => ["bash", "-c", "hyprctl activewindow -j | jq -c '{class, title, workspace: .workspace.id, floating, fullscreen}'"]
        },
        "hypr_windows": {
            risk: "safe",
            untrusted: true,
            maxChars: 3000,
            description: "List all open windows: address, workspace, class, title",
            build: a => ["bash", "-c", `hyprctl clients -j | jq -r '.[] | "\\(.address) ws\\(.workspace.id) \\(.class): \\(.title[0:60])"'`]
        },
        "hypr_workspaces": {
            risk: "safe",
            description: "List workspaces and their window counts",
            build: a => ["bash", "-c", `hyprctl workspaces -j | jq -r '.[] | "ws\\(.id): \\(.windows) windows"'`]
        },
        "volume_get": {
            risk: "safe",
            description: "Get current audio volume",
            build: a => ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        },
        "brightness_get": {
            risk: "safe",
            description: "Get current screen brightness",
            build: a => ["brightnessctl", "-m"]
        },
        "battery": {
            risk: "safe",
            description: "Get battery status",
            build: a => ["bash", "-c", `ls /sys/class/power_supply/BAT* >/dev/null 2>&1 || { echo 'no battery'; exit 0; }; for b in /sys/class/power_supply/BAT*; do echo "$(basename $b): $(cat $b/capacity)% $(cat $b/status)"; done`]
        },
        "network_status": {
            risk: "safe",
            description: "Get network interface status",
            build: a => ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device"]
        },
        "media_status": {
            risk: "safe",
            untrusted: true,
            description: "Get currently playing media info",
            build: a => ["playerctl", "metadata", "--format", "{{status}}: {{artist}} - {{title}}"]
        },
        "media_control": {
            risk: "safe",
            description: "Control media playback",
            build: a => {
                const allowed = ["play-pause", "play", "pause", "next", "previous"];
                if (!allowed.includes(a.command)) throw new Error("command not allowed");
                return ["playerctl", a.command];
            }
        },

        // ---- Window management ----
        "hypr_move_window": {
            risk: "safe",
            description: "Move a window to a specific workspace (by address)",
            build: a => {
                let addr = String(a.address ?? a.target ?? "").trim();
                if (!addr.startsWith("0x") && !addr.startsWith("0X")) addr = "0x" + addr;
                const ws = parseInt(a.workspace);
                if (!/^0x[0-9a-f]+$/i.test(addr)) throw new Error(`invalid address "${addr}"`);
                if (isNaN(ws) || ws < 1 || ws > 99) throw new Error("workspace must be 1-99");
                return ["hyprctl", "dispatch", `hl.dsp.window.move({ workspace = ${ws}, window = "address:${addr}" })`];
            }
        },
        "hypr_focus": {
            risk: "safe",
            description: "Focus a window by its address",
            build: a => {
                let addr = String(a.address ?? a.target ?? "").trim();
                if (!addr.startsWith("0x") && !addr.startsWith("0X")) addr = "0x" + addr;
                if (!/^0x[0-9a-f]+$/i.test(addr)) throw new Error(`invalid address "${addr}"`);
                return ["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${addr}" })`];
            }
        },
        "hypr_swap": {
            risk: "safe",
            description: "Swap the active window with another (by address or direction l/r/u/d)",
            build: a => {
                const rawAddr = a.address ?? a.target;
                if (rawAddr !== undefined) {
                    let addr = String(rawAddr).trim();
                    if (!addr.startsWith("0x") && !addr.startsWith("0X")) addr = "0x" + addr;
                    if (!/^0x[0-9a-f]+$/i.test(addr)) throw new Error(`invalid address "${addr}"`);
                    // API Lua: window.swap usa "target", não "window"
                    return ["hyprctl", "dispatch", `hl.dsp.window.swap({ target = "address:${addr}" })`];
                }
                if (!["l", "r", "u", "d"].includes(a.direction)) throw new Error("use direction (l, r, u, d) or address");
                return ["hyprctl", "dispatch", `hl.dsp.window.swap({ direction = "${a.direction}" })`];
            }
        },
        "hypr_layoutmsg": {
            risk: "safe",
            description: "Send a layout message to Hyprland",
            build: a => {
                const allowed = ["swapsplit", "movetoroot", "togglesplit", "orientationnext", "swapwithmaster", "cyclenext", "cycleprev"];
                if (!allowed.includes(a.msg)) throw new Error("message not allowed");
                return ["hyprctl", "dispatch", `hl.dsp.layout("${a.msg}")`];
            }
        },

        // ---- Web ----
        "web_search": {
            risk: "safe",
            untrusted: true,
            taintExempt: true,
            maxChars: 3500,
            description: "Search the web for a query",
            build: a => {
                const q = String(a.query ?? "").trim();
                if (q.length === 0 || q.startsWith("-")) throw new Error("invalid query");
                return ["/home/skaaarlate/.local/bin/websift", "search", q];
            }
        },
        "web_fetch": {
            risk: "safe",
            untrusted: true,
            maxChars: 4000,
            description: "Fetch the text content of a URL",
            build: a => {
                const u = String(a.url ?? "").trim();
                if (!/^https?:\/\/\S+$/.test(u)) throw new Error("invalid url");
                return ["/home/skaaarlate/.local/bin/websift", "fetch", u];
            }
        },
    })

    readonly property var toolSchemas: ({
        hypr_workspace: {
            parameters: {
                type: "object",
                properties: { id: { type: "integer", minimum: 1, maximum: 99 } },
                required: ["id"]
            }
        },
        hypr_reload: { parameters: { type: "object", properties: {} } },
        hypr_dispatch: {
            parameters: {
                type: "object",
                properties: {
                    dispatcher: { type: "string", enum: ["togglefloating", "fullscreen", "killactive", "movetoworkspace", "togglesplit"] },
                    arg: { type: "integer" }
                },
                required: ["dispatcher"]
            }
        },
        volume: {
            parameters: {
                type: "object",
                properties: { percent: { type: "integer", minimum: 0, maximum: 100 } },
                required: ["percent"]
            }
        },
        brightness: {
            parameters: {
                type: "object",
                properties: { percent: { type: "integer", minimum: 1, maximum: 100 } },
                required: ["percent"]
            }
        },
        system_update: { parameters: { type: "object", properties: {} } },
        hypr_active_window: { parameters: { type: "object", properties: {} } },
        hypr_windows: { parameters: { type: "object", properties: {} } },
        hypr_workspaces: { parameters: { type: "object", properties: {} } },
        volume_get: { parameters: { type: "object", properties: {} } },
        brightness_get: { parameters: { type: "object", properties: {} } },
        battery: { parameters: { type: "object", properties: {} } },
        network_status: { parameters: { type: "object", properties: {} } },
        media_status: { parameters: { type: "object", properties: {} } },
        media_control: {
            parameters: {
                type: "object",
                properties: { command: { type: "string", enum: ["play-pause", "play", "pause", "next", "previous"] } },
                required: ["command"]
            }
        },
        hypr_move_window: {
            parameters: {
                type: "object",
                properties: {
                    address: { type: "string", description: "Window address (0x...)" },
                    target: { type: "string", description: "Alias for address" },
                    workspace: { type: "integer", minimum: 1, maximum: 99 }
                },
                required: ["workspace"]
            }
        },
        hypr_focus: {
            parameters: {
                type: "object",
                properties: {
                    address: { type: "string" },
                    target: { type: "string", description: "Alias for address" }
                }
            }
        },
        hypr_swap: {
            parameters: {
                type: "object",
                properties: {
                    address: { type: "string", description: "Window address (use this OR direction)" },
                    target: { type: "string", description: "Alias for address" },
                    direction: { type: "string", enum: ["l", "r", "u", "d"] }
                }
            }
        },
        hypr_layoutmsg: {
            parameters: {
                type: "object",
                properties: { msg: { type: "string", enum: ["swapsplit", "movetoroot", "togglesplit", "orientationnext", "swapwithmaster", "cyclenext", "cycleprev"] } },
                required: ["msg"]
            }
        },
        web_search: {
            parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] }
        },
        web_fetch: {
            parameters: { type: "object", properties: { url: { type: "string" } }, required: ["url"] }
        },
    })

    readonly property var toolDefinitions: {
        const tools = [];
        for (const name in root.systemActions) {
            const def = root.systemActions[name];
            if (!def || def.risk !== "safe") continue;
            if (root.webSearchEnabled && (name === "web_search" || name === "web_fetch")) continue;
            const schema = root.toolSchemas[name];
            tools.push({
                type: "function",
                function: {
                    name: name,
                    description: def.description ?? name,
                    parameters: schema?.parameters ?? { type: "object", properties: {} }
                }
            });
        }
        return tools;
    }

    // ---------------------------------------------------------------
    // ```action text protocol (fallback)
    // Accepts both ```action and ```json fences — small models often use json.
    // ---------------------------------------------------------------
    function extractActions(text) {
        const result = [];
        const re = /```(?:action|json)\s*([\s\S]*?)```/g;
        let m;
        while ((m = re.exec(text)) !== null) {
            try {
                const parsed = JSON.parse(m[1]);
                if (Array.isArray(parsed)) parsed.forEach(p => result.push(p));
                else result.push(parsed);
            } catch (e) {
                result.push({ name: "invalid_json" });
            }
        }
        return result;
    }

    function handleActions(actions, message) {
        if (actions.length > 8) {
            root.reportActionResult("batch", "No action was executed.\nMax 8 actions per response.");
            return;
        }
        const items = [];
        const errors = [];
        for (const action of actions) {
            const def = root.systemActions[action?.name];
            if (!def) { errors.push(`${action?.name ?? "?"}: unknown action`); continue; }
            try {
                items.push({ name: action.name, argv: def.build(action.args ?? {}), def: def });
            } catch (e) {
                errors.push(`${action.name}: invalid args (${e.message})`);
            }
        }
        if (errors.length > 0) {
            root.reportActionResult("batch", `No action was executed.\n${errors.join("\n")}`);
            return;
        }

        const needsApproval = items.some(it => it.def.risk !== "safe" || (root.chainTainted && !it.def.taintExempt));
        if (!needsApproval) {
            root.startQueue(items);
            return;
        }
        const summary = items.length === 1
            ? items[0].argv.join(" ")
            : `${items.length} actions: ${items.map(it => it.name).join(", ")}`;
        root.pendingAction = { items: items, summary: summary, message: message };
        root.addMessage(
            Translation.tr("Requested actions:\n\n%1\n\n/approve to execute all, /deny to cancel")
                .arg(items.map(it => "- `" + it.argv.join(" ") + "`").join("\n")),
            root.interfaceRole
        );
    }

    function startQueue(items) {
        root.actionQueue = items.slice();
        root.actionResults = [];
        root.actionBatchName = items.length === 1 ? items[0].name : "batch";
        root.runNext();
    }

    function runNext() {
        if (root.actionQueue.length === 0) {
            root.reportActionResult(root.actionBatchName, root.actionResults.join("\n\n"));
            return;
        }
        const item = root.actionQueue[0];
        root.actionQueue = root.actionQueue.slice(1);
        root.runAction(item.name, item.argv, item.def);
    }

    function approveAction() {
        if (!root.pendingAction) { root.addMessage(Translation.tr("Nothing pending"), root.interfaceRole); return; }
        const p = root.pendingAction;
        root.pendingAction = null;
        root.startQueue(p.items);
    }

    function denyAction() {
        if (!root.pendingAction) return;
        root.pendingAction = null;
        root.reportActionResult("batch", "denied by user");
    }

    function runAction(name, argv, def) {
        actionProc.actionName = name;
        actionProc.maxChars = def?.maxChars ?? 1500;
        if (def?.untrusted) root.chainTainted = true;
        actionProc.buffer = "";
        actionProc.command = argv;
        actionProc.running = true;
    }

    function reportActionResult(name, text) {
        if (root.actionChainDepth >= 3) {
            root.addMessage(Translation.tr("Action chain limit reached"), root.interfaceRole);
            return;
        }
        root.actionChainDepth++;
        root.addHiddenMessage(`[Result of action ${name}]\n${text}\n[End of result]`);
        requester.makeRequest();
    }

    Process {
        id: actionProc
        property string actionName: ""
        property int maxChars: 1500
        property string buffer: ""
        stdout: SplitParser { onRead: data => { actionProc.buffer += data + "\n"; } }
        stderr: SplitParser { onRead: data => { actionProc.buffer += data + "\n"; } }
        onExited: (exitCode, exitStatus) => {
            const out = actionProc.buffer.trim().replace(/^IMPORTANT:.*Call fetch\(url\).*$/gm, "").trim();
            // hyprctl retorna exit 0 mesmo quando o dispatch falha — detecta pelo output
            const hasError = /can't|error|not found|failed/i.test(out);
            const effectiveExitCode = hasError ? Math.max(exitCode, 1) : exitCode;
            root.actionResults = [...root.actionResults, `[${actionProc.actionName}] exit code ${effectiveExitCode}\n${out.slice(0, actionProc.maxChars)}`];
            Qt.callLater(root.runNext);
        }
    }

    // ---------------------------------------------------------------
    // Tool calling (native)
    // ---------------------------------------------------------------
    function executeToolCall(assistantMessage, functionCall) {
        if (root.toolCallDepth >= root.maxToolCallDepth) {
            root.addToolResult(functionCall.id,
                `Error: max tool call depth (${root.maxToolCallDepth}) reached. Stop calling tools and respond to the user.`);
            return;
        }
        root.toolCallDepth++;

        const def = root.systemActions[functionCall.name];
        if (!def) {
            root.addToolResult(functionCall.id, `Error: unknown tool "${functionCall.name}".`);
            return;
        }
        if (def.risk !== "safe") {
            root.addToolResult(functionCall.id,
                `Error: tool "${functionCall.name}" has risk="${def.risk}" and cannot be called via tool calling. ` +
                `Use the \`\`\`action block format if you need to perform it.`);
            return;
        }

        let argv;
        try {
            argv = def.build(functionCall.args ?? {});
        } catch (e) {
            root.addToolResult(functionCall.id, `Error: invalid arguments for "${functionCall.name}": ${e.message}`);
            return;
        }

        if (!Array.isArray(argv) || argv.length === 0) {
            root.addToolResult(functionCall.id, `Error: empty command for "${functionCall.name}".`);
            return;
        }

        if (def.untrusted) root.chainTainted = true;

        root.toolQueue.push({ call: functionCall, argv: argv, def: def });
        if (!toolProc.running) Qt.callLater(root.processNextTool);
    }

    function processNextTool() {
        if (root.toolQueue.length === 0) return;
        const item = root.toolQueue.shift();
        toolProc.toolCallId = item.call.id;
        toolProc.toolName = item.call.name;
        toolProc.def = item.def;
        toolProc.buffer = "";
        toolProc.command = item.argv;
        toolProc.running = true;
    }

    function addToolResult(toolCallId, resultText) {
        const toolMessage = root.aiMessageComponent.createObject(root, {
            "role": "tool",
            "content": resultText,
            "rawContent": resultText,
            "tool_call_id": toolCallId,
            "thinking": false,
            "done": true,
            "visibleToUser": false,
        });
        root.registerMessage(idForMessage(toolMessage), toolMessage);
    }

    Process {
        id: toolProc
        property string toolCallId: ""
        property string toolName: ""
        property var def: null
        property string buffer: ""
        stdout: SplitParser { onRead: data => { toolProc.buffer += data + "\n"; } }
        stderr: SplitParser { onRead: data => { toolProc.buffer += data + "\n"; } }
        onExited: (exitCode, exitStatus) => {
            const out = toolProc.buffer.trim().replace(/^IMPORTANT:.*Call fetch\(url\).*$/gm, "").trim();
            const maxChars = toolProc.def?.maxChars ?? 1500;
            // hyprctl retorna exit 0 mesmo quando o dispatch falha — detecta pelo output
            const hasError = /can't|error|not found|failed/i.test(out);
            const effectiveExitCode = hasError ? Math.max(exitCode, 1) : exitCode;
            const resultText = `[${toolProc.toolName}] exit code ${effectiveExitCode}\n${out.slice(0, maxChars)}`;
            root.addToolResult(toolProc.toolCallId, resultText);

            if (root.toolQueue.length > 0) {
                Qt.callLater(root.processNextTool);
            } else {
                requester.makeRequest();
            }
        }
    }

    // --------------------------------------------------------------
    // Chat management
    // ---------------------------------------------------------------
    function setWebSearchEnabled(enabled) {
        root.webSearchEnabled = enabled;
        Persistent.states.ai.webSearchEnabled = enabled;
    }

    function idForMessage(message) {
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    // IMPORTANTE: messageByID é mutado in-place (sem notificação de binding).
    // Quem notifica é a REATRIBUIÇÃO de messageIDs, então a mensagem precisa
    // estar em messageByID ANTES de messageIDs mudar. Use sempre esta função.
    function registerMessage(id, message) {
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-").toLowerCase()
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${new Date().toISOString().slice(0, 10)} (${DateTime.time}, ${DateTime.collapsedCalendarFormat})`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`
    }

    property var models: (Config.options?.policies?.ai === 2) ? {} : {
        "gemini-2.5-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 2.5 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent",
            "model": "gemini-2.5-flash",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training."),
            "api_format": "gemini",
        }),
        "gemini-3-flash": aiModelComponent.createObject(this, {
            "name": "Gemini 3 Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model"),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: free. Data used for training."),
            "api_format": "gemini",
        }),
        "mistral-medium-3": aiModelComponent.createObject(this, {
            "name": "Mistral Medium 3",
            "icon": "mistral-symbolic",
            "description": Translation.tr("Online | Mistral's model"),
            "homepage": "https://mistral.ai/news/mistral-medium-3",
            "endpoint": "https://api.mistral.ai/v1/chat/completions",
            "model": "mistral-medium-2505",
            "requires_key": true,
            "key_id": "mistral",
            "key_get_link": "https://console.mistral.ai/api-keys",
            "key_get_description": Translation.tr("**Instructions**: Log into Mistral account, go to Keys on the sidebar, click Create new key"),
            "api_format": "mistral",
        }),
    }
    property var modelList: Object.keys(root.models ?? {})
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
            root.ensureValidModel()
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""
    property bool ollamaModelsLoaded: false

    function ensureValidModel() {
        if (!root.ollamaModelsLoaded || !Config.ready) return;
        if (root.models && root.models[root.currentModelId]) return;
        const fallback = Object.keys(root.models ?? {})[0];
        if (fallback) {
            root.currentModelId = fallback;
            Persistent.states.ai.model = fallback;
            root.setModel(fallback, false, false);
        }
    }

    Component.onCompleted: {
        setModel(currentModelId, false, false);
        root.addUserModels()
        root.ensureValidModel()
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const hfMatch = model.match(/^hf\.co\/([^\/]+)\/([^:]+):(.+)$/);
        if (hfMatch) {
            let base = hfMatch[2].replace(/-GGUF$/i, "").replace(/-/g, " ");
            base = base.replace(/(\d+)b/i, (_, n) => `${n}B`);
            base = base.split(" ").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");
            return `${base} (${hfMatch[3]})`;
        }
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => word.charAt(0).toUpperCase() + word.slice(1));
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`;
        return words.join(' ');
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
        root.modelList = Object.keys(root.models);
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                            "extraParams": { "num_ctx": 16384 }
                        })
                    });
                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.ollamaModelsLoaded = true;
            root.ensureValidModel();
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = ""
        promptLoader.path = filePath;
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        root.registerMessage(idForMessage(aiMessage), aiMessage);
    }

    function addHiddenMessage(message) {
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": "user",
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
            "visibleToUser": false,
        });
        root.registerMessage(idForMessage(aiMessage), aiMessage);
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"),
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId] ?? { name: "—", description: "", icon: "neurology" };
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        const list = root.modelList ?? [];
        if (list.indexOf(modelId) !== -1) {
            const model = models[modelId]
            if (!model) {
                if (feedback) root.addMessage(Translation.tr("Model '%1' exists in list but has no data").arg(modelId), root.interfaceRole);
                return;
            }
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name ?? modelId), root.interfaceRole);
            if (model.requires_key) {
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + list.join("\n```\n```\n") + "\n```", Ai.interfaceRole)
        }
    }

    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (isNaN(value) || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            if (requester.message.done) return;
            requester.message.done = true;
            root.saveChat("lastSession")
            root.responseFinished()
            if (requester.message.tool_calls?.length > 0) return;
            const actions = root.extractActions(requester.message.rawContent);
            if (actions.length > 0) root.handleActions(actions, requester.message);
        }

        function makeRequest() {
            const model = models[currentModelId];

            if (!model) {
                console.log("[AI] No model selected. Aborting request.");
                return;
            }

            if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();

            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset();

            requester.environment[`${root.apiKeyEnvVarName}`] = model.requires_key
                ? (root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "")
                : ""

            const endpoint = requester.currentStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter((message, i) => {
                if (message.role === Ai.interfaceRole) return false;
                if (message.role === "tool") return true;
                return message.visibleToUser !== false || i === messageArray.length - 1;
            });

            const apiFormat = model.api_format ?? "openai";
            const toolsForRequest = apiFormat === "gemini" ? [] : root.toolDefinitions;

            const data = requester.currentStrategy.buildRequestData(
                model, filteredMessageArray, root.systemPrompt, root.temperature,
                toolsForRequest, root.pendingFilePath
            );

            let requestHeaders = { "Content-Type": "application/json" }

            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            root.registerMessage(idForMessage(requester.message), requester.message);

            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            const scriptShebang = "#!/usr/bin/env bash\n";

            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            let scriptRequestContent = `curl --no-buffer "${endpoint}" ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"

            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;

                // Guard contra thinking loops
                if (!requester.message.done && requester.message.rawContent.length > root.maxRawContentLength) {
                    requester.message.rawContent += "\n\n[Response truncated: exceeded length limit without completing. Try a simpler prompt, lower temperature, or a more capable model.]";
                    requester.message.done = true;
                    requester.markDone();
                    return;
                }

                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);

                    const fcList = result.functionCalls
                        ?? (result.functionCall ? [result.functionCall] : []);
                    if (fcList.length > 0) {
                        // Reatribui o array (em vez de push in-place) para notificar bindings
                        // — assim o chip de ação aparece na bolha assim que a chamada chega.
                        const newCalls = fcList.map(fc => ({
                            id: fc.id || ("call_" + Date.now() + "_" + Math.random().toString(36).slice(2, 8)),
                            type: "function",
                            function: {
                                name: fc.name,
                                arguments: JSON.stringify(fc.args ?? {})
                            }
                        }));
                        requester.message.tool_calls = [...(requester.message.tool_calls ?? []), ...newCalls];
                        for (const fc of fcList) {
                            root.executeToolCall(requester.message, fc);
                        }
                        return;
                    }

                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }

                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }
            if (requester.message.content.includes("API key not valid")) {
                const failedModel = models[requester.message.model];
                if (failedModel) root.addApiKeyAdvice(failedModel);
            }
        }
    }

    Process {
        id: preSearchProc
        property string originalMessage: ""
        property string buffer: ""
        command: []
        stdout: SplitParser {
            onRead: data => { preSearchProc.buffer += data + "\n"; }
        }
        stderr: SplitParser {
            onRead: data => { preSearchProc.buffer += data + "\n"; }
        }
        onExited: (exitCode, exitStatus) => {
            const hasResults = preSearchProc.buffer.trim().length > 0;
            let context = hasResults ? preSearchProc.buffer.trim() : "(no web results found)";

            preSearchTimeout.stop();

            context = context.replace(/^IMPORTANT:.*Call fetch\(url\).*$/gm, "").trim();
            if (context.length > 3000) context = context.slice(0, 3000) + "\n\n[...truncated]";

            preSearchProc.buffer = "";
            preSearchProc.originalMessage = "";

            const urlMatch = hasResults ? context.match(/^URL:\s*(\S+)/m) : null;
            if (urlMatch) {
                fetchProc.snippets = context;
                fetchProc.buffer = "";
                fetchProc.command = ["/home/skaaarlate/.local/bin/websift", "fetch", urlMatch[1]];
                fetchProc.running = true;
                fetchTimeout.restart();
                return;
            }

            root.finishPreSearch(context);
        }
    }

    Process {
        id: fetchProc
        property string snippets: ""
        property string buffer: ""
        command: []
        stdout: SplitParser {
            onRead: data => { fetchProc.buffer += data + "\n"; }
        }
        onExited: (exitCode, exitStatus) => {
            fetchTimeout.stop();
            let context = fetchProc.snippets;
            let page = fetchProc.buffer.trim();
            fetchProc.snippets = "";
            fetchProc.buffer = "";

            if (exitCode === 0 && page.length > 0) {
                if (page.length > 4000) page = page.slice(0, 4000) + "\n\n[...truncated]";
                context += "\n\n---\n\n[Full text of the first result above]\n\n" + page;
            }
            root.finishPreSearch(context);
        }
    }

    Timer {
        id: fetchTimeout
        interval: 20000
        repeat: false
        onTriggered: { if (fetchProc.running) fetchProc.running = false; }
    }

    function finishPreSearch(context) {
        const hidden = `[Automatic web search for the user's message above]

${context}

[End of search results]`;
        root.addHiddenMessage(hidden);
        requester.makeRequest();
    }

    Timer {
        id: preSearchTimeout
        interval: 20000
        repeat: false
        onTriggered: { if (preSearchProc.running) preSearchProc.running = false; }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.actionChainDepth = 0;
        root.chainTainted = false;
        root.pendingAction = null;
        root.toolCallDepth = 0;
        root.toolQueue = [];
        root.addMessage(message, "user");

        if (root.webSearchEnabled) {
            preSearchProc.originalMessage = message;
            preSearchProc.buffer = "";
            preSearchProc.command = ["/home/skaaarlate/.local/bin/websift", "search", message];
            preSearchProc.running = true;
            preSearchTimeout.restart();
            return;
        }

        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "visibleToUser": message.visibleToUser,
                "tool_calls": message.tool_calls ?? [],
                "tool_call_id": message.tool_call_id ?? "",
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true
    }

    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            const saveData = JSON.parse(saveContent)
            root.clearMessages()

            // Monta o dicionário completo ANTES de publicar os IDs,
            // senão os bindings (turns) rodam com messageByID vazio.
            const byID = {};
            const ids = [];
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                byID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "visibleToUser": message.visibleToUser,
                    "tool_calls": message.tool_calls ?? [],
                    "tool_call_id": message.tool_call_id ?? "",
                });
                ids.push(i);
            }
            root.messageByID = byID;
            root.messageIDs = ids;
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
