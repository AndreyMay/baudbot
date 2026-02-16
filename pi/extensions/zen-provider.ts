import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerProvider("opencode-zen", {
    baseUrl: "https://opencode.ai/zen",
    apiKey: "OPENCODE_ZEN_API_KEY",
    api: "anthropic-messages",
    models: [
      {
        id: "claude-opus-4-6",
        name: "Claude Opus 4.6 (Zen)",
        reasoning: true,
        input: ["text", "image"],
        cost: {
          input: 5.0,
          output: 25.0,
          cacheRead: 0.5,
          cacheWrite: 6.25,
        },
        contextWindow: 200000,
        maxTokens: 16384,
      },
      {
        id: "claude-haiku-4-5",
        name: "Claude Haiku 4.5 (Zen)",
        reasoning: true,
        input: ["text", "image"],
        cost: {
          input: 1.0,
          output: 5.0,
          cacheRead: 0.1,
          cacheWrite: 1.25,
        },
        contextWindow: 200000,
        maxTokens: 16384,
      },
    ],
  });
}
