/// Model LLM yang bisa dipilih di Pengaturan (docs/llm.md).
typedef AiModel = ({String label, String id});

const aiModels = <AiModel>[
  (label: 'GLM 5.3 Flash', id: 'z-ai/glm-5.3-flash'),
  (label: 'DeepSeek V4.1 Flash', id: 'deepseek/deepseek-v4.1-flash'),
  (label: 'Qwen 3.8 Flash', id: 'qwen/qwen3.8-flash'),
];

/// Dipake sebelum user milih, dan model balik ke sini saat "Balik ke kuota
/// gratis" (board Kuota AI 02, 05; keputusan 13 Nov 2026). Harga per token
/// termurah, tapi reasoning-nya gak bisa dimatiin: lebih lambat dan token
/// output lebih banyak. DeepSeek V4.1 Flash menang evaluasi buta #28.
const defaultAiModel = 'z-ai/glm-5.3-flash';

/// Model yang boleh dipakai kuota gratis (guardrail workspace OpenRouter,
/// docs/backend.md). Server yang jadi sumber kebenaran (`/v1/ai/config`);
/// ini cadangan saat config belum kebaca.
const subsidyModelIds = <String>[
  'z-ai/glm-5.3-flash',
  'deepseek/deepseek-v4.1-flash',
  'qwen/qwen3.8-flash',
];
