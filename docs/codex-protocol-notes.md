# Codex connection

TokenOwl uses `codex app-server` over stdio. It waits for `initialize` before sending `initialized` and `account/rateLimits/read`. Pending requests are registered before writing; cancellation and timeout release them and terminate the process.

The decoder supports documented `rateLimitsByLimitId` buckets containing `primary` and `secondary` windows, numeric Unix-second reset times, and the backward-compatible `rateLimits` bucket. Earlier flat fixtures remain supported. Missing usage is rejected rather than displayed as 100% remaining.

VS Code uses the same Codex login. Binary discovery checks PATH, standard executable directories, Codex app, and the installed OpenAI VS Code extension. TokenOwl does not read the Codex auth file.

Reference: https://developers.openai.com/codex/app-server
