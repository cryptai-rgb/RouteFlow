import SwiftUI

struct RouteRuleListView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("rules.title"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(L10n.tr("rules.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if viewModel.config.rules.isEmpty {
                Text(L10n.tr("common.no_rules_configured"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.config.rules) { rule in
                    ruleRow(rule)
                }
                .padding(.horizontal, 12)
            }

            Button(action: { viewModel.isShowingAddRouteSheet = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text(L10n.tr("common.add_routes"))
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func ruleRow(_ rule: RouteRule) -> some View {
        HStack(spacing: 6) {
            // Status
            if viewModel.routeManager.isRuleFailed(rule) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            } else if viewModel.routeManager.isRuleApplied(rule) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                Image(systemName: "circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Destination
            Text(rule.destination)
                .font(.system(size: 12, weight: .medium))

            Spacer()

            // Target interface
            Text(rule.hardwarePort)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Active toggle
            VStack(alignment: .trailing, spacing: 2) {
                Toggle("", isOn: Binding(
                    get: { rule.isActive },
                    set: { _ in viewModel.toggleRule(rule) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .font(.caption)

                Text(rule.isActive ? L10n.tr("common.restore_on_launch") : L10n.tr("common.skip_on_launch"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            // Delete
            Button(action: { viewModel.removeRule(rule) }) {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
