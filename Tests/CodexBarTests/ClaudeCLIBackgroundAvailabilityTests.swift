import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ClaudeCLIBackgroundAvailabilityTests {
    @Test
    func `disabled Keychain allows cold background Auto usage without an established marker`() async throws {
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            await KeychainAccessGate.withTaskOverrideForTesting(true) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `enabled Keychain allows cold prompt-free background Auto usage`() async throws {
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            await KeychainAccessGate.withTaskOverrideForTesting(false) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `disabled Keychain allows background Auto after foreground availability is established`() async throws {
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            ClaudeCLIBackgroundAvailability.establish(binary: "/bin/echo", environment: context.env)
            await KeychainAccessGate.withTaskOverrideForTesting(true) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.never) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `background Auto usage remains available with user action prompt policy`() async throws {
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            ClaudeCLIBackgroundAvailability.establish(binary: "/bin/echo", environment: context.env)
            await KeychainAccessGate.withTaskOverrideForTesting(false) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `background Auto CLI uses foreground availability with explicit prompt opt in`() async throws {
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            ClaudeCLIBackgroundAvailability.establish(binary: "/bin/echo", environment: context.env)
            await KeychainAccessGate.withTaskOverrideForTesting(false) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test(arguments: ClaudeOAuthKeychainPromptMode.allCases)
    func `background explicit OAuth never reaches interactive CLI`(promptMode: ClaudeOAuthKeychainPromptMode) async {
        let strategy = self.makeStrategy()
        let context = self.makeContext(sourceMode: .oauth)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            await KeychainAccessGate.withTaskOverrideForTesting(true) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(promptMode) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await !strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `failed prompt-free background usage revokes later timer attempts`() async throws {
        ClaudeCLIRateLimitGate.resetForTesting()
        defer { ClaudeCLIRateLimitGate.resetForTesting() }
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)
        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            await KeychainAccessGate.withTaskOverrideForTesting(false) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await strategy.isAvailable(context))
                            await #expect(throws: (any Error).self) {
                                try await strategy.fetch(context)
                            }
                            #expect(await !strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `background Auto fetch runs only the prompt-free usage command`() async throws {
        ClaudeCLIRateLimitGate.resetForTesting()
        defer { ClaudeCLIRateLimitGate.resetForTesting() }
        let profile = try self.makeProfile(accountID: "account-a")
        let invocationLog = profile.root.appendingPathComponent("invocations.log")
        let cliPath = try self.makeDirectUsageCLI(root: profile.root, invocationLog: invocationLog)
        defer { try? FileManager.default.removeItem(at: profile.root) }

        var environment = profile.environment
        environment["CLAUDE_CLI_PATH"] = cliPath
        let strategy = self.makeStrategy()
        let context = self.makeContext(environment: environment)

        try await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            try await KeychainAccessGate.withTaskOverrideForTesting(false) {
                try await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.onlyOnUserAction) {
                    try await ProviderInteractionContext.$current.withValue(.background) {
                        #expect(await strategy.isAvailable(context))
                        let result = try await strategy.fetch(context)
                        #expect(result.sourceLabel == "claude")
                        #expect(result.usage.primary?.usedPercent == 12)
                        #expect(result.usage.secondary?.usedPercent == 40)
                    }
                }
            }
        }

        let invocations = try String(contentsOf: invocationLog, encoding: .utf8)
            .split(whereSeparator: \Character.isNewline)
            .map(String.init)
        #expect(invocations == ["/usage"])
    }

    @Test
    func `rate limit cooldown skips launch without revoking background Auto`() async throws {
        ClaudeCLIRateLimitGate.resetForTesting()
        defer { ClaudeCLIRateLimitGate.resetForTesting() }
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)
        ClaudeCLIRateLimitGate.recordRateLimit()

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                await ProviderInteractionContext.$current.withValue(.background) {
                    #expect(await strategy.isAvailable(context))
                    await #expect(throws: ClaudeBackgroundDirectCLIError.self) {
                        try await strategy.fetch(context)
                    }
                    #expect(await strategy.isAvailable(context))
                }
            }
        }
    }

    @Test
    func `live rate limit response records cooldown without revoking background Auto`() async throws {
        ClaudeCLIRateLimitGate.resetForTesting()
        defer { ClaudeCLIRateLimitGate.resetForTesting() }
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        var environment = profile.environment
        environment["CLAUDE_CLI_PATH"] = try self.makeRateLimitedCLI(root: profile.root)
        let strategy = self.makeStrategy()
        let context = self.makeContext(environment: environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            await ProviderInteractionContext.$current.withValue(.background) {
                #expect(await strategy.isAvailable(context))
                await #expect(throws: (any Error).self) {
                    try await strategy.fetch(context)
                }
                #expect(ClaudeCLIRateLimitGate.blockedUntil() != nil)
                #expect(await strategy.isAvailable(context))
            }
        }
    }

    @Test
    func `user initiated explicit OAuth retains interactive CLI recovery`() async {
        let strategy = self.makeStrategy()
        let context = self.makeContext(sourceMode: .oauth)

        await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                #expect(await strategy.isAvailable(context))
            }
        }
    }

    @Test
    func `background Auto failure revocation does not cross config profiles`() async throws {
        let strategy = self.makeStrategy()
        let profileA = try self.makeProfile(accountID: "account-a")
        let profileB = try self.makeProfile(accountID: "account-b")
        defer {
            try? FileManager.default.removeItem(at: profileA.root)
            try? FileManager.default.removeItem(at: profileB.root)
        }
        let contextA = self.makeContext(environment: profileA.environment)
        let contextB = self.makeContext(environment: profileB.environment)

        await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            guard let marker = ClaudeCLIBackgroundAvailability.captureMarker(
                binary: "/bin/echo",
                environment: contextA.env)
            else {
                Issue.record("Expected account-scoped background marker")
                return
            }
            ClaudeCLIBackgroundAvailability.revoke(marker)
            await KeychainAccessGate.withTaskOverrideForTesting(false) {
                await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await !strategy.isAvailable(contextA))
                            #expect(await strategy.isAvailable(contextB))
                        }
                    }
                }
            }
        }
    }

    @Test
    func `background Auto allows one fresh attempt after active account changes`() async throws {
        let strategy = self.makeStrategy()
        let profile = try self.makeProfile(accountID: "account-a")
        defer { try? FileManager.default.removeItem(at: profile.root) }
        let context = self.makeContext(environment: profile.environment)

        try await ClaudeCLIBackgroundAvailability.withIsolatedStoreForTesting {
            let marker = try #require(ClaudeCLIBackgroundAvailability.captureMarker(
                binary: "/bin/echo",
                environment: context.env))
            ClaudeCLIBackgroundAvailability.revoke(marker)
            try await KeychainAccessGate.withTaskOverrideForTesting(false) {
                try await ClaudeOAuthKeychainPromptPreference.withTaskOverrideForTesting(.always) {
                    try await ClaudeCLIResolver.withResolvedBinaryPathOverrideForTesting("/bin/echo") {
                        try await ProviderInteractionContext.$current.withValue(.background) {
                            #expect(await !strategy.isAvailable(context))
                            try Data(#"{"oauthAccount":{"accountUuid":"account-b"}}"#.utf8)
                                .write(to: profile.configURL, options: .atomic)
                            #expect(await strategy.isAvailable(context))
                            try FileManager.default.removeItem(at: profile.configURL)
                            #expect(await !strategy.isAvailable(context))
                        }
                    }
                }
            }
        }
    }

    private func makeStrategy() -> ClaudeCLIFetchStrategy {
        ClaudeCLIFetchStrategy(
            useWebExtras: false,
            includePrepaidBalance: false,
            manualCookieHeader: nil,
            browserDetection: BrowserDetection(cacheTTL: 0),
            hasWebFallback: false)
    }

    private func makeContext(
        sourceMode: ProviderSourceMode = .auto,
        environment: [String: String] = [:]) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: nil,
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection, environment: environment),
            browserDetection: browserDetection)
    }

    private func makeProfile(accountID: String) throws -> (
        root: URL,
        configURL: URL,
        environment: [String: String])
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-claude-background-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent(".config.json")
        try Data(#"{"oauthAccount":{"accountUuid":"\#(accountID)"}}"#.utf8)
            .write(to: configURL, options: .atomic)
        return (
            root: root,
            configURL: configURL,
            environment: ["CLAUDE_CONFIG_DIR": root.path])
    }

    private func makeDirectUsageCLI(root: URL, invocationLog: URL) throws -> String {
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> '\(invocationLog.path)'
        if [ "$1" != "/usage" ]; then
          exit 99
        fi
        cat <<'EOF'
        Current session
        12% used (Resets 11am)
        Current week (all models)
        40% used (Resets Nov 21)
        EOF
        """
        let url = root.appendingPathComponent("claude-direct-usage-stub")
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func makeRateLimitedCLI(root: URL) throws -> String {
        let script = """
        #!/bin/sh
        if [ "$1" = "/usage" ]; then
          printf '%s\\n' 'Failed to load usage data: rate_limit_error'
          exit 0
        fi
        exit 99
        """
        let url = root.appendingPathComponent("claude-rate-limit-stub")
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}
