import Foundation

@MainActor
class RouteManager: ObservableObject {
    struct BatchRuleResult {
        let succeededRuleIDs: Set<UUID>
        let failures: [UUID: String]
    }

    private enum BatchRouteOperation {
        case add
        case delete
    }

    private let executor = PrivilegedExecutor()
    private let batchSuccessMarker = "__ROUTEFLOW_OK__"
    private let batchFailureMarker = "__ROUTEFLOW_ERR__"

    @Published var appliedRules: Set<UUID> = []
    @Published var failedRules: Set<UUID> = []
    @Published var manualRoutes: [SystemRouteEntry] = []
    @Published var lastError: String?

    /// Apply a single route rule (requires admin privileges)
    func applyRule(_ rule: RouteRule) async throws {
        let result = try await applyRules([rule])
        if let message = result.failures[rule.id] {
            throw PrivilegedExecutor.PrivilegedError.commandFailed(exitCode: 1, message: message)
        }
    }

    /// Remove a single route rule (requires admin privileges)
    func removeRule(_ rule: RouteRule) async throws {
        let result = try await removeRules([rule])
        if let message = result.failures[rule.id] {
            throw PrivilegedExecutor.PrivilegedError.commandFailed(exitCode: 1, message: message)
        }
    }

    /// Remove a route by destination (requires admin privileges)
    func removeRoute(destination: String, interfaceName: String) async throws {
        let args = RouteCommandBuilder.buildDeleteCommand(destination: destination, interfaceName: interfaceName)

        do {
            _ = try await executor.executePrivilegedCommand("/sbin/route", arguments: args)
            lastError = nil
        } catch let error as PrivilegedExecutor.PrivilegedError {
            if case .userCancelled = error {
                throw error
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Query the current route for a destination (no privileges needed)
    func queryRoute(destination: String) async throws -> RouteGetResult? {
        let args = RouteCommandBuilder.buildGetCommand(destination: destination)
        let output = try await executor.executeCommand("/sbin/route", arguments: args)
        return RouteCommandBuilder.parseRouteGetOutput(output)
    }

    /// Query `netstat -nr -f inet` and extract user-added gateway routes.
    func refreshManualRoutes() async {
        do {
            let output = try await executor.executeCommand("/usr/sbin/netstat", arguments: ["-nr", "-f", "inet"])
            manualRoutes = RouteCommandBuilder.parseManualRouteTableOutput(output)
        } catch {
            manualRoutes = []
        }
    }

    /// Apply all active rules
    func applyAllRules(_ rules: [RouteRule]) async {
        lastError = nil
        do {
            _ = try await applyRules(Self.rulesToApplyOnActivation(rules))
        } catch {
            // Batch result has already updated state; ignore to keep other app flows moving.
        }
    }

    /// Remove all configured routes.
    /// Deleting a route that is already absent is treated as success so the
    /// system can be reconciled back to the saved config state.
    func removeAllRules(_ rules: [RouteRule]) async {
        do {
            _ = try await removeRules(Self.rulesToRemoveOnGlobalDeactivate(rules))
        } catch {
            // Batch result has already updated state; ignore to keep other app flows moving.
        }
    }

    /// Check if a rule is currently applied in the system
    func isRuleApplied(_ rule: RouteRule) -> Bool {
        appliedRules.contains(rule.id)
    }

    /// Check if a rule failed to apply
    func isRuleFailed(_ rule: RouteRule) -> Bool {
        failedRules.contains(rule.id)
    }

    func syncAppliedState(with rules: [RouteRule]) {
        let matchedRuleIDs = Set(
            rules.compactMap { rule in
                manualRoutes.contains(where: { RouteCommandBuilder.routeMatches(rule: rule, entry: $0) }) ? rule.id : nil
            }
        )

        appliedRules = matchedRuleIDs
        failedRules.subtract(matchedRuleIDs)
    }

    /// Apply many route rules with a single administrator prompt.
    func applyRules(_ rules: [RouteRule]) async throws -> BatchRuleResult {
        try await executeBatch(rules, operation: .add)
    }

    /// Remove many route rules with a single administrator prompt.
    func removeRules(_ rules: [RouteRule]) async throws -> BatchRuleResult {
        try await executeBatch(rules, operation: .delete)
    }

    static func isIgnorableDeleteError(_ message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("not in table") || normalized.contains("no such process")
    }

    static func rulesToApplyOnActivation(_ rules: [RouteRule]) -> [RouteRule] {
        rules.filter(\.isActive)
    }

    static func rulesToRemoveOnGlobalDeactivate(_ rules: [RouteRule]) -> [RouteRule] {
        rules
    }

    private func executeBatch(_ rules: [RouteRule], operation: BatchRouteOperation) async throws -> BatchRuleResult {
        guard !rules.isEmpty else {
            lastError = nil
            return BatchRuleResult(succeededRuleIDs: [], failures: [:])
        }

        let script = buildBatchScript(for: rules, operation: operation)

        do {
            let output = try await executor.executePrivilegedScript(script)
            let result = parseBatchResult(output, rules: rules, operation: operation)
            updateState(with: result, for: rules, operation: operation)
            return result
        } catch let error as PrivilegedExecutor.PrivilegedError {
            if case .userCancelled = error {
                throw error
            }
            for rule in rules {
                failedRules.insert(rule.id)
            }
            lastError = error.localizedDescription
            throw error
        }
    }

    private func buildBatchScript(for rules: [RouteRule], operation: BatchRouteOperation) -> String {
        let successLiteral = PrivilegedExecutor.shellEscape(batchSuccessMarker)
        let failureLiteral = PrivilegedExecutor.shellEscape(batchFailureMarker)

        let snippets = rules.map { rule -> String in
            let args: [String]
            switch operation {
            case .add:
                args = RouteCommandBuilder.buildAddCommand(
                    destination: rule.destination,
                    interfaceName: rule.interfaceName,
                    gateway: rule.gateway
                )
            case .delete:
                args = RouteCommandBuilder.buildDeleteCommand(
                    destination: rule.destination,
                    interfaceName: rule.interfaceName
                )
            }

            let command = PrivilegedExecutor.buildShellCommand("/sbin/route", arguments: args)
            let ruleID = PrivilegedExecutor.shellEscape(rule.id.uuidString)
            let destination = PrivilegedExecutor.shellEscape(rule.destination)

            return """
            command_output=$({ \(command); } 2>&1)
            status=$?
            command_output=$(printf '%s' "$command_output" | tr '\\n' ' ' | tr '\\t' ' ')
            if [ "$status" -eq 0 ]; then
              printf '%s\\t%s\\t%s\\n' \(successLiteral) \(ruleID) \(destination)
            else
              printf '%s\\t%s\\t%s\\t%s\\n' \(failureLiteral) \(ruleID) \(destination) "$command_output"
            fi
            """
        }

        return snippets.joined(separator: "\n") + "\nexit 0"
    }

    private func parseBatchResult(
        _ output: String,
        rules: [RouteRule],
        operation: BatchRouteOperation
    ) -> BatchRuleResult {
        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id.uuidString, $0.id) })
        var succeededRuleIDs = Set<UUID>()
        var failures: [UUID: String] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 3 else { continue }
            guard let ruleID = rulesByID[columns[1]] else { continue }

            if columns[0] == batchSuccessMarker {
                succeededRuleIDs.insert(ruleID)
                continue
            }

            guard columns[0] == batchFailureMarker else { continue }
            let message = columns.count > 3
                ? columns[3].trimmingCharacters(in: .whitespacesAndNewlines)
                : L10n.tr("add.failed_add")
            if operation == .delete, Self.isIgnorableDeleteError(message) {
                succeededRuleIDs.insert(ruleID)
                continue
            }
            failures[ruleID] = message.isEmpty ? L10n.tr("add.failed_add") : message
        }

        for rule in rules where !succeededRuleIDs.contains(rule.id) && failures[rule.id] == nil {
            failures[rule.id] = L10n.tr("add.failed_add")
        }

        return BatchRuleResult(succeededRuleIDs: succeededRuleIDs, failures: failures)
    }

    private func updateState(
        with result: BatchRuleResult,
        for rules: [RouteRule],
        operation: BatchRouteOperation
    ) {
        for rule in rules {
            if result.succeededRuleIDs.contains(rule.id) {
                switch operation {
                case .add:
                    appliedRules.insert(rule.id)
                case .delete:
                    appliedRules.remove(rule.id)
                }
                failedRules.remove(rule.id)
            } else {
                failedRules.insert(rule.id)
            }
        }

        lastError = result.failures.values.first
    }
}
