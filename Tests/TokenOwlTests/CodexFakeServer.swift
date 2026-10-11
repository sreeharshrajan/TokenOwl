import Foundation

struct CodexFakeServer {
    let script: String

    static func happyPath() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPercent":42,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"},"weekly":{"usedPercent":78,"windowDurationMins":10080,"resetsAt":"2026-10-19T18:00:00Z"}}}}'
            exit 0
          fi
        done
        """)
    }

    static func singleWindow() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPercent":50,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"}}}}'
            exit 0
          fi
        done
        """)
    }

    static func multiBucket() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPercent":10,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"},"weekly":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":"2026-10-19T18:00:00Z"},"daily":{"usedPercent":5,"windowDurationMins":1440,"resetsAt":"2026-10-13T00:00:00Z"}}}}'
            exit 0
          fi
        done
        """)
    }

    static func noWindows() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{}}}'
            exit 0
          fi
        done
        """)
    }

    static func apiKeyAuthError() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","error":{"code":-32000,"message":"API key authentication is not supported"}}'
            exit 0
          fi
        done
        """)
    }

    static func notLoggedInError() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","error":{"code":-32000,"message":"Not logged in. Run codex login."}}'
            exit 0
          fi
        done
        """)
    }

    static func jsonRPCError() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","error":{"code":-32600,"message":"Invalid request"}}'
            exit 0
          fi
        done
        """)
    }

    static func malformedJSON() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo 'this is not json at all'
            exit 0
          fi
        done
        """)
    }

    static func partialLines() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            printf '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPer'
            printf 'cent":42,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"}}}}'
            echo ''
            exit 0
          fi
        done
        """)
    }

    static func multipleObjectsPerChunk() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPercent":42,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"}}}}'
            echo '{"jsonrpc":"2.0","method":"account/rateLimits/updated","params":{}}'
            exit 0
          fi
        done
        """)
    }

    static func delayedResponse() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            sleep 30
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPercent":42,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"}}}}'
            exit 0
          fi
        done
        """)
    }

    static func exitsEarly() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
        exit 1
        """)
    }

    static func hangsIgnoringStdinClose() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          fi
        done
        sleep 9999
        """)
    }

    static func stderrWithTokens() -> CodexFakeServer {
        CodexFakeServer(script: """
        #!/bin/bash
        echo 'Warning: token=abc123def456' >&2
        echo 'Bearer sk-abc123def456' >&2
        while IFS= read -r line; do
          if echo "$line" | grep -q '"method":"initialize"'; then
            echo '{"jsonrpc":"2.0","id":"0","result":{"serverInfo":{"name":"codex-fake","version":"0.1.0"}}}'
          elif echo "$line" | grep -q '"method":"account/rateLimits/read"'; then
            echo '{"jsonrpc":"2.0","id":"1","result":{"rateLimitsByLimitId":{"five_hour":{"usedPercent":42,"windowDurationMins":300,"resetsAt":"2026-10-12T18:00:00Z"}}}}'
            exit 0
          fi
        done
        """)
    }

    func write(to path: String) throws {
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
}
