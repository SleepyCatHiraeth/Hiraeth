import QtQuick

QtObject {
    property bool supportsStreaming: true
    // Whether this provider can be offered tools at all. False means the
    // sidebar says so rather than advertising a capability that will be
    // silently discarded on the way out.
    property bool supportsTools: true

    function getEndpoint(modelObj, apiKey) { return ""; }
    function getHeaders(apiKey) { return []; }
    function getBody(messages, model, tools) { return {}; }
    function getStreamBody(messages, model, tools) {
        let body = getBody(messages, model, tools);
        body.stream = true;
        return body;
    }
    function parseResponse(response) { return { content: "" }; }
    function parseStreamChunk(line) {
        // Override in subclasses. Returns:
        //   { content: "token", done: false, error: null }
        //
        // A chunk that carries part of a tool call adds `toolCallDelta`: an
        // array of { index, id, name, argumentsFragment }, any field of which
        // may be absent. This shape is the providers' three different wire
        // formats normalized here, so Ai.qml accumulates one way rather than
        // three: OpenAI fragments the arguments across deltas, Anthropic
        // announces the call in one event and streams its JSON in later ones,
        // and Gemini sends the whole call complete in a single part.
        //
        // `index` groups the fragments of one call. `argumentsFragment` is
        // concatenated in arrival order and parsed as JSON only once the
        // stream has finished.
        return { content: "", done: true, error: null };
    }
}
