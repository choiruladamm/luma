/// LLM model selectable in Pengaturan (docs/llm.md).
typedef AiModel = ({String label, String id});

const aiModels = <AiModel>[
  (label: 'GLM 5.3 Flash', id: 'z-ai/glm-5.3-flash'),
  (label: 'DeepSeek V4.1 Flash', id: 'deepseek/deepseek-v4.1-flash'),
  (label: 'Qwen 3.8 Flash', id: 'qwen/qwen3.8-flash'),
];

/// Used before the user picks one, and the model returns here on "Balik ke kuota
/// gratis" (board Kuota AI 02, 05; decision 13 Nov 2026). Cheapest per-token price,
/// but its reasoning can't be turned off: slower and more output tokens. DeepSeek V4.1
/// Flash won the blind eval #28.
const defaultAiModel = 'z-ai/glm-5.3-flash';

/// Models the free quota may use (OpenRouter workspace guardrail, docs/backend.md,
/// AI subsidy). The server is the source of truth (`/v1/ai/config`); this is a
/// fallback while the config hasn't been read.
const subsidyModelIds = <String>[
  'z-ai/glm-5.3-flash',
  'deepseek/deepseek-v4.1-flash',
  'qwen/qwen3.8-flash',
];
