/// The AI layer of rehoboam_neural_ui: provider-agnostic models (Claude,
/// OpenAI-compatible, Gemini, Genkit flows, any custom SDK), a streaming
/// tool-using agent, generative UI, voice (STT / TTS) and a complete chat
/// view. Also exported by `rehoboam_neural_ui.dart`.
library;

export 'src/ai/gen_ui.dart'
    show
        NeuralUiCatalog,
        NeuralUiComponent,
        NeuralUiBuilder,
        NeuralUiContext,
        NeuralUiProps,
        NeuralUiSurface;
export 'src/ai/neural_agent.dart' show NeuralAgent, NeuralAgentPhase;
export 'src/ai/neural_chat_view.dart'
    show
        NeuralChatView,
        NeuralChatStrings,
        NeuralMarkdownText,
        NeuralShimmerText;
export 'src/ai/neural_message.dart';
export 'src/ai/neural_model.dart'
    show
        NeuralModel,
        NeuralRequest,
        NeuralCancelToken,
        NeuralModelEvent,
        NeuralTextDelta,
        NeuralReasoningDelta,
        NeuralToolCallEvent,
        NeuralUsageEvent,
        NeuralFinishEvent,
        NeuralFinishReason,
        NeuralModelException,
        SseEvent,
        parseSse;
export 'src/ai/neural_tool.dart'
    show NeuralTool, NeuralToolContext, validateJson;
export 'src/ai/providers/claude_model.dart' show ClaudeModel;
export 'src/ai/providers/flow_models.dart'
    show GenkitFlowModel, CallbackModel, ScriptedModel, ScriptedTurn;
export 'src/ai/providers/gemini_model.dart' show GeminiModel;
export 'src/ai/providers/openai_compatible_model.dart'
    show OpenAICompatibleModel;
export 'src/ai/rehoboam_controller.dart' show RehoboamController, RehoboamHud;
export 'src/ai/voice/neural_voice.dart'
    show
        NeuralSpeechToText,
        NeuralTextToSpeech,
        NeuralTranscript,
        NeuralSpeechProgress,
        CallbackSpeechToText,
        CallbackTextToSpeech,
        WebSpeechToText,
        WebTextToSpeech,
        SimulatedSpeech;
