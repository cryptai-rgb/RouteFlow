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
    func removeRoute(destination: String, interfaceName: String, gateway: String) async throws {
        let script = buildSingleDeleteScript(
            destination: destination,
            interfaceName: interfaceName,
            gateway: gateway
        )

        do {
            _ = try await executor.executePrivilegedScript(script)
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
        let helpers = batchShellHelpers()
        let successLiteral = PrivilegedExecutor.shellEscape(batchSuccessMarker)
        let failureLiteral = PrivilegedExecutor.shellEscape(batchFailureMarker)

        let snippets = rules.map { rule -> String in
            switch operation {
            case .add:
                return buildAddSnippet(
                    for: rule,
                    successLiteral: successLiteral,
                    failureLiteral: failureLiteral
                )
            case .delete:
                return buildDeleteSnippet(
                    for: rule,
                    successLiteral: successLiteral,
                    failureLiteral: failureLiteral
                )
            }
        }

        return ([helpers] + snippets + ["exit 0"]).joined(separator: "\n")
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

    private func buildAddSnippet(
        for rule: RouteRule,
        successLiteral: String,
        failureLiteral: String
    ) -> String {
        let addCommand = PrivilegedExecutor.buildShellCommand(
            "/sbin/route",
            arguments: RouteCommandBuilder.buildAddCommand(
                destination: rule.destination,
                interfaceName: rule.interfaceName,
                gateway: rule.gateway
            )
        )
        let legacyDeleteCommand = PrivilegedExecutor.buildShellCommand(
            "/sbin/route",
            arguments: RouteCommandBuilder.buildScopedDeleteCommand(
                destination: rule.destination,
                interfaceName: rule.interfaceName,
                gateway: rule.gateway
            )
        )
        let ruleID = PrivilegedExecutor.shellEscape(rule.id.uuidString)
        let destination = PrivilegedExecutor.shellEscape(rule.destination)

        return """
        legacy_output=$({ \(legacyDeleteCommand); } 2>&1)
        legacy_status=$?
        legacy_output=$(normalize_routeflow_output "$legacy_output")
        if [ "$legacy_status" -ne 0 ] && ! is_routeflow_ignorable_delete_error "$legacy_output"; then
          printf '%s\\t%s\\t%s\\t%s\\n' \(failureLiteral) \(ruleID) \(destination) "$legacy_output"
        else
          command_output=$({ \(addCommand); } 2>&1)
          status=$?
          command_output=$(normalize_routeflow_output "$command_output")
          if [ "$status" -eq 0 ]; then
            printf '%s\\t%s\\t%s\\n' \(successLiteral) \(ruleID) \(destination)
          else
            printf '%s\\t%s\\t%s\\t%s\\n' \(failureLiteral) \(ruleID) \(destination) "$command_output"
          fi
        fi
        """
    }

    private func buildDeleteSnippet(
        for rule: RouteRule,
        successLiteral: String,
        failureLiteral: String
    ) -> String {
        let deleteCommand = PrivilegedExecutor.buildShellCommand(
            "/sbin/route",
            arguments: RouteCommandBuilder.buildDeleteCommand(
                destination: rule.destination,
                gateway: rule.gateway
            )
        )
        let legacyDeleteCommand = PrivilegedExecutor.buildShellCommand(
            "/sbin/route",
            arguments: RouteCommandBuilder.buildScopedDeleteCommand(
                destination: rule.destination,
                interfaceName: rule.interfaceName,
                gateway: rule.gateway
            )
        )
        let ruleID = PrivilegedExecutor.shellEscape(rule.id.uuidString)
        let destination = PrivilegedExecutor.shellEscape(rule.destination)

        return """
        primary_output=$({ \(deleteCommand); } 2>&1)
        primary_status=$?
        primary_output=$(normalize_routeflow_output "$primary_output")
        legacy_output=$({ \(legacyDeleteCommand); } 2>&1)
        legacy_status=$?
        legacy_output=$(normalize_routeflow_output "$legacy_output")
        if [ "$primary_status" -eq 0 ] || [ "$legacy_status" -eq 0 ]; then
          printf '%s\\t%s\\t%s\\n' \(successLiteral) \(ruleID) \(destination)
        elif is_routeflow_ignorable_delete_error "$primary_output" && is_routeflow_ignorable_delete_error "$legacy_output"; then
          printf '%s\\t%s\\t%s\\n' \(successLiteral) \(ruleID) \(destination)
        else
          failure_message="$primary_output"
          if is_routeflow_ignorable_delete_error "$failure_message"; then
            failure_message="$legacy_output"
          fi
          printf '%s\\t%s\\t%s\\t%s\\n' \(failureLiteral) \(ruleID) \(destination) "$failure_message"
        fi
        """
    }

    private func buildSingleDeleteScript(destination: String, interfaceName: String, gateway: String) -> String {
        let deleteCommand = PrivilegedExecutor.buildShellCommand(
            "/sbin/route",
            arguments: RouteCommandBuilder.buildDeleteCommand(
                destination: destination,
                gateway: gateway
            )
        )
        let legacyDeleteCommand = PrivilegedExecutor.buildShellCommand(
            "/sbin/route",
            arguments: RouteCommandBuilder.buildScopedDeleteCommand(
                destination: destination,
                interfaceName: interfaceName,
                gateway: gateway
            )
        )

        return """
        \(batchShellHelpers())
        primary_output=$({ \(deleteCommand); } 2>&1)
        primary_status=$?
        primary_output=$(normalize_routeflow_output "$primary_output")
        legacy_output=$({ \(legacyDeleteCommand); } 2>&1)
        legacy_status=$?
        legacy_output=$(normalize_routeflow_output "$legacy_output")
        if [ "$primary_status" -eq 0 ] || [ "$legacy_status" -eq 0 ]; then
          exit 0
        fi
        if is_routeflow_ignorable_delete_error "$primary_output" && is_routeflow_ignorable_delete_error "$legacy_output"; then
          exit 0
        fi
        if is_routeflow_ignorable_delete_error "$primary_output"; then
          printf '%s\\n' "$legacy_output"
        else
          printf '%s\\n' "$primary_output"
        fi
        exit 1
        """
    }

    private func batchShellHelpers() -> String {
        """
        normalize_routeflow_output() {
          printf '%s' "$1" | tr '\\n' ' ' | tr '\\t' ' '
        }

        is_routeflow_ignorable_delete_error() {
          case "$1" in
            *"not in table"*|*"No such process"*)
              return 0
              ;;
            *)
              return 1
              ;;
          esac
        }
        """
    }
}
