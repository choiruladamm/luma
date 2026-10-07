/// Model LLM yang bisa dipilih di Pengaturan (docs bagian 9).
typedef AiModel = ({String label, String id});

const aiModels = <AiModel>[
  (label: 'GLM 5.3 Flash', id: 'z-ai/glm-5.3-flash'),
  (label: 'DeepSeek V4.1 Flash', id: 'deepseek/deepseek-v4.1-flash'),
  (label: 'Qwen 3.8 Flash', id: 'qwen/qwen3.8-flash'),
];

/// Dipake sebelum user milih. Menang evaluasi buta 50 potong (#28): paling
/// setia ke teks & hati-hati soal fakta, kata rusak sedikit.
const defaultAiModel = 'deepseek/deepseek-v4.1-flash';
