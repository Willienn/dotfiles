import QtQuick

ApiStrategy {
    property bool isReasoning: false
    property var pendingToolCalls: ({})

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        const convertedMessages = messages.map(message => {
            const msg = {
                "role": message.role,
                "content": message.rawContent ?? "",
            };

            // Assistant message that requested tool calls
            if (message.role === "assistant" && message.tool_calls && message.tool_calls.length > 0) {
                msg.tool_calls = message.tool_calls;
                // OpenAI: content must be null when tool_calls is present (if no text)
                if (!msg.content || msg.content.length === 0) msg.content = null;
            }

            // Tool result message
            if (message.role === "tool") {
                msg.tool_call_id = message.tool_call_id ?? "";
                // content already set from rawContent
            }

            return msg;
        });

        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...convertedMessages,
            ],
            "stream": true,
            "temperature": temperature,
        };

        // Only include tools if non-empty (some servers reject empty arrays)
        if (tools && tools.length > 0) {
            baseData.tools = tools;
        }

        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            return { finished: true };
        }

        try {
            const dataJson = JSON.parse(cleanData);

            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            const delta = dataJson.choices[0]?.delta;
            const responseContent = delta?.content || dataJson.message?.content;
            const responseReasoning = delta?.reasoning || delta?.reasoning_content;

            // ---- Tool calls: accumulate all parallel calls ----
            if (delta?.tool_calls && delta.tool_calls.length > 0) {
                for (const tc of delta.tool_calls) {
                    const idx = tc.index ?? 0;
                    if (!pendingToolCalls[idx]) {
                        pendingToolCalls[idx] = { id: "", name: "", args: "" };
                    }
                    if (tc.id) pendingToolCalls[idx].id = tc.id;
                    if (tc.function?.name) pendingToolCalls[idx].name = tc.function.name;
                    if (tc.function?.arguments) pendingToolCalls[idx].args += tc.function.arguments;
                }
            }

            const finishReason = dataJson.choices[0]?.finish_reason;
            if (finishReason === "tool_calls"
                || (pendingToolCalls && Object.keys(pendingToolCalls).length > 0 && finishReason === "stop")) {
                const keys = Object.keys(pendingToolCalls).sort();
                if (keys.length > 0) {
                    const calls = keys.map(k => {
                        const tc = pendingToolCalls[k];
                        let argsParsed = {};
                        try { argsParsed = JSON.parse(tc.args || "{}"); } catch (e) { argsParsed = {}; }
                        return { id: tc.id, name: tc.name, args: argsParsed };
                    });
                    pendingToolCalls = ({});
                    return {
                        functionCalls: calls,
                        finished: true
                    };
                }
            }

            let newContent = "";

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            message.content += newContent;
            message.rawContent += newContent;

            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }

        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }

        return {};
    }

    function onRequestFinished(message) {
        return {};
    }

    function reset() {
        isReasoning = false;
        pendingToolCalls = ({});
    }
}