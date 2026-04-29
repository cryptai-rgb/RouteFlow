import Foundation

enum L10n {
    private static let english: [String: String] = [
        "common.active": "Active",
        "common.inactive": "Inactive",
        "common.cancel": "Cancel",
        "common.quit": "Quit",
        "common.unavailable": "Unavailable",
        "common.via": "via %@",
        "common.netif": "netif %@",
        "common.expire": "expire %@",
        "common.default": "Default",
        "common.online": "Online",
        "common.offline": "Offline",
        "common.default_service": "Default Service",
        "common.route_target": "Route Target",
        "common.ipv4": "IPv4",
        "common.gateway": "Gateway",
        "common.subnet": "Subnet",
        "common.restore_on_launch": "Restore on launch",
        "common.skip_on_launch": "Skip on launch",
        "common.add_routes": "Add Routes",
        "common.adding": "Adding...",
        "common.config_file": "Config file",
        "common.reveal_in_finder": "Reveal in Finder",
        "common.export_config": "Export Config...",
        "common.import_config": "Import Config...",
        "common.no_rules_configured": "No rules configured",
        "common.version": "Version 1.0",
        "common.default_route": "Default Route",
        "common.network_route": "Network Route",
        "common.host_route": "Host Route",
        "common.authentication_cancelled": "Authentication was cancelled.",
        "common.command_failed": "Command failed (exit %d): %@",
        "common.unsupported_config_version": "Unsupported config version: %d",
        "count.valid": "%d valid",
        "count.invalid": "%d invalid",
        "count.routes": "%d route%@",
        "count.network_routes": "%d network route%@",
        "count.destinations_saved.one": "%d destination was already saved.",
        "count.destinations_saved.other": "%d destinations were already saved.",
        "count.added_routes": "Added %d new route%@.",
        "count.imported_routes": "Imported %d existing system route%@ into saved config.",
        "menu.title": "RouteFlow",
        "menu.interfaces": "Network Interfaces",
        "menu.no_interfaces": "No interfaces detected",
        "menu.selected_routes": "Selected Interface Routes",
        "menu.export_routes": "Export Network Routes",
        "menu.export_none": "No exportable network routes were found for %@.",
        "menu.export_title": "Export Network Routes",
        "menu.export_message": "Exports non-default CIDR routes for %@ (%@).",
        "menu.export_filename": "RouteFlow-%@-network-routes.txt",
        "menu.export_success": "Exported %d network route%@ to %@.",
        "menu.export_failed": "Export failed: %@",
        "menu.routes_empty_title": "No routes with `U`, `G`, and `S` flags are currently present on this interface.",
        "menu.routes_empty_detail": "The panel only shows `netstat -nr -f inet` entries whose flags include `U`, `G`, and `S` in any order, which is the marker used for manually added gateway routes.",
        "menu.routes_showing": "Showing `netstat -nr -f inet` routes whose flags include `U`, `G`, and `S` in any order and whose `Netif` is %@.",
        "menu.routes_export_note": "Export only includes non-`default` network routes in CIDR form, so host routes and the default route are excluded.",
        "menu.route_saved": "Saved by RouteFlow and will be restored on next launch.",
        "menu.route_unmanaged": "Detected from the system routing table only. This entry is not currently managed by RouteFlow.",
        "menu.empty_selection_title": "Select an interface from the left.",
        "menu.empty_selection_detail": "The right panel will show `netstat -nr -f inet` entries whose flags include `U`, `G`, and `S` for the selected interface.",
        "rules.title": "Saved Route Rules",
        "rules.subtitle": "These rules are persisted. The switch only controls whether RouteFlow restores them on next launch.",
        "interface.no_ipv4": "No IPv4",
        "add.destinations_title": "Destinations (IPs or CIDRs)",
        "add.destinations_detail": "One per line, or separate with spaces or commas. All entries will be bound to the selected interface.",
        "add.import_file": "Import File...",
        "add.imported_file": "Imported from %@",
        "add.import_success": "Imported %d destination(s) from file.",
        "add.import_no_valid_routes": "No valid destinations were found in the selected file.",
        "add.import_invalid_entries": "Some entries in the file are invalid: %@",
        "add.import_failed": "Failed to import file: %@",
        "add.invalid_entries": "Invalid entries: %@",
        "add.interface_title": "Network Interface",
        "add.no_valid_interfaces": "No valid interfaces available",
        "add.interface_picker": "Interface",
        "add.selected_interface": "Selected Interface",
        "add.inactive_activated": "RouteFlow was inactive and has been activated so the routes can be applied immediately.",
        "add.interface_no_gateway": "Selected interface has no gateway.",
        "add.route_exists": "Route already exists on %@ via %@.",
        "add.failed_add": "Failed to add route.",
        "settings.general": "General",
        "settings.rules": "Rules",
        "settings.about": "About",
        "settings.auto_apply": "Auto-apply rules on launch",
        "settings.clean_on_exit": "Clean routes on exit",
        "settings.launch_at_login": "Launch at login",
        "settings.summary.login_and_apply": "RouteFlow will try to apply saved routes during login. macOS may ask for an administrator password only when route changes are needed.",
        "settings.summary.apply_only": "RouteFlow applies saved routes at launch only when the current routing table differs from the saved rules.",
        "settings.summary.login_only": "Launch at login is enabled. RouteFlow starts in the background, but it will not request route authorization on startup unless auto-apply is also enabled.",
        "settings.summary.default": "Route changes require administrator access because RouteFlow updates the macOS routing table.",
        "settings.about_subtitle": "macOS Network Interface Route Manager",
        "notify.interface_down.title": "Interface Down",
        "notify.interface_down.body": "%@ (%@) has gone offline. Affected routes are suspended.",
        "notify.interface_up.title": "Interface Up",
        "notify.interface_up.body": "%@ (%@) is back online. Routes have been restored.",
        "startup.privilege.title": "RouteFlow needs administrator access",
        "startup.privilege.message": "RouteFlow needs authorization to update the macOS routing table for your saved routes.",
        "startup.privilege.continue": "Continue",
        "startup.privilege.cancelled": "Startup route changes were cancelled before administrator authentication."
    ]

    private static let simplifiedChinese: [String: String] = [
        "common.active": "已启用",
        "common.inactive": "已停用",
        "common.cancel": "取消",
        "common.quit": "退出",
        "common.unavailable": "不可用",
        "common.via": "经由 %@",
        "common.netif": "网卡 %@",
        "common.expire": "过期 %@",
        "common.default": "默认",
        "common.online": "在线",
        "common.offline": "离线",
        "common.default_service": "默认服务",
        "common.route_target": "可用于路由",
        "common.ipv4": "IPv4",
        "common.gateway": "网关",
        "common.subnet": "子网",
        "common.restore_on_launch": "启动时恢复",
        "common.skip_on_launch": "启动时跳过",
        "common.add_routes": "添加路由",
        "common.adding": "添加中...",
        "common.config_file": "配置文件",
        "common.reveal_in_finder": "在 Finder 中显示",
        "common.export_config": "导出配置...",
        "common.import_config": "导入配置...",
        "common.no_rules_configured": "暂无已配置规则",
        "common.version": "版本 1.0",
        "common.default_route": "默认路由",
        "common.network_route": "网段路由",
        "common.host_route": "主机路由",
        "common.authentication_cancelled": "已取消授权。",
        "common.command_failed": "命令执行失败（退出码 %d）：%@",
        "common.unsupported_config_version": "不支持的配置版本：%d",
        "count.valid": "有效 %d 项",
        "count.invalid": "无效 %d 项",
        "count.routes": "%d 条路由",
        "count.network_routes": "%d 条网段路由",
        "count.destinations_saved.one": "%d 个目标已保存。",
        "count.destinations_saved.other": "%d 个目标已保存。",
        "count.added_routes": "已新增 %d 条路由。",
        "count.imported_routes": "已将 %d 条现有系统路由导入到保存配置。",
        "menu.title": "RouteFlow",
        "menu.interfaces": "网络接口",
        "menu.no_interfaces": "未检测到网络接口",
        "menu.selected_routes": "所选接口路由",
        "menu.export_routes": "导出网段路由",
        "menu.export_none": "%@ 上没有可导出的网段路由。",
        "menu.export_title": "导出网段路由",
        "menu.export_message": "导出 %@（%@）上的非 default CIDR 路由。",
        "menu.export_filename": "RouteFlow-%@-network-routes.txt",
        "menu.export_success": "已导出 %d 条网段路由到 %@。",
        "menu.export_failed": "导出失败：%@",
        "menu.routes_empty_title": "当前接口上没有带 `U`、`G`、`S` 标记的路由。",
        "menu.routes_empty_detail": "这里仅显示 `netstat -nr -f inet` 中包含 `U`、`G`、`S` 标记的条目，也就是手动添加网关路由时使用的那类记录。",
        "menu.routes_showing": "当前显示 `netstat -nr -f inet` 中 `Netif` 为 %@ 且标记包含 `U`、`G`、`S` 的路由。",
        "menu.routes_export_note": "导出仅包含 CIDR 形式且非 `default` 的网段路由，因此主机路由和默认路由不会被导出。",
        "menu.route_saved": "该路由由 RouteFlow 保存，下次启动时会自动恢复。",
        "menu.route_unmanaged": "该路由仅从系统路由表中检测到，目前不受 RouteFlow 管理。",
        "menu.empty_selection_title": "请先在左侧选择一个接口。",
        "menu.empty_selection_detail": "右侧会显示所选接口中带 `U`、`G`、`S` 标记的 `netstat -nr -f inet` 路由。",
        "rules.title": "已保存路由规则",
        "rules.subtitle": "这些规则会持久化保存，开关只控制 RouteFlow 是否在下次启动时恢复它们。",
        "interface.no_ipv4": "无 IPv4",
        "add.destinations_title": "目标地址（IP 或 CIDR）",
        "add.destinations_detail": "每行一个，或使用空格、逗号分隔。所有条目都会绑定到当前选中的接口。",
        "add.import_file": "导入文件...",
        "add.imported_file": "已从 %@ 导入",
        "add.import_success": "已从文件导入 %d 个目标。",
        "add.import_no_valid_routes": "所选文件中没有可导入的有效目标。",
        "add.import_invalid_entries": "文件中有部分无效条目：%@",
        "add.import_failed": "导入文件失败：%@",
        "add.invalid_entries": "无效条目：%@",
        "add.interface_title": "网络接口",
        "add.no_valid_interfaces": "没有可用的有效接口",
        "add.interface_picker": "接口",
        "add.selected_interface": "当前接口",
        "add.inactive_activated": "RouteFlow 原本处于停用状态，现已自动启用以便立即应用这些路由。",
        "add.interface_no_gateway": "所选接口没有可用网关。",
        "add.route_exists": "路由已存在于 %@，网关为 %@。",
        "add.failed_add": "添加路由失败。",
        "settings.general": "通用",
        "settings.rules": "规则",
        "settings.about": "关于",
        "settings.auto_apply": "启动时自动应用规则",
        "settings.clean_on_exit": "退出时清理路由",
        "settings.launch_at_login": "登录时启动",
        "settings.summary.login_and_apply": "RouteFlow 会在登录后尝试恢复已保存路由，只有在确实需要变更路由表时才会向 macOS 请求管理员授权。",
        "settings.summary.apply_only": "RouteFlow 只会在当前系统路由表与已保存规则不一致时，才在启动时应用保存的路由。",
        "settings.summary.login_only": "已开启登录时启动。RouteFlow 会在后台启动，但只有同时开启自动应用时，才可能在启动时请求路由授权。",
        "settings.summary.default": "由于需要修改 macOS 路由表，路由变更必须使用管理员权限。",
        "settings.about_subtitle": "macOS 网络接口路由管理工具",
        "notify.interface_down.title": "接口已断开",
        "notify.interface_down.body": "%@（%@）已离线，相关路由已暂停。",
        "notify.interface_up.title": "接口已恢复",
        "notify.interface_up.body": "%@（%@）已恢复在线，相关路由已重新恢复。",
        "startup.privilege.title": "RouteFlow 需要管理员权限",
        "startup.privilege.message": "RouteFlow 需要授权来更新 macOS 路由表。",
        "startup.privilege.continue": "继续",
        "startup.privilege.cancelled": "启动时的路由变更已在管理员授权前取消。"
    ]

    static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func tr(_ key: String) -> String {
        let table = isChinese ? simplifiedChinese : english
        return table[key] ?? english[key] ?? key
    }

    static func fmt(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }

    static func routeCount(_ count: Int) -> String {
        if isChinese {
            return fmt("count.routes", count)
        }
        return fmt("count.routes", count, count == 1 ? "" : "s")
    }

    static func networkRouteCount(_ count: Int) -> String {
        if isChinese {
            return fmt("count.network_routes", count)
        }
        return fmt("count.network_routes", count, count == 1 ? "" : "s")
    }

    static func validCount(_ count: Int) -> String {
        fmt("count.valid", count)
    }

    static func invalidCount(_ count: Int) -> String {
        fmt("count.invalid", count)
    }

    static func addedRoutes(_ count: Int) -> String {
        if isChinese {
            return fmt("count.added_routes", count)
        }
        return fmt("count.added_routes", count, count == 1 ? "" : "s")
    }

    static func importedRoutes(_ count: Int) -> String {
        if isChinese {
            return fmt("count.imported_routes", count)
        }
        return fmt("count.imported_routes", count, count == 1 ? "" : "s")
    }

    static func destinationsAlreadySaved(_ count: Int) -> String {
        let key = count == 1 ? "count.destinations_saved.one" : "count.destinations_saved.other"
        return fmt(key, count)
    }
}
