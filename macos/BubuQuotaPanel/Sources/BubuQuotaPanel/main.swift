import AppKit
import CoreGraphics
import Foundation

private let refreshInterval: TimeInterval = 5 * 60
private let btcRefreshInterval: TimeInterval = 5
private let taskProgressRefreshInterval: TimeInterval = 2
private let panelVersion = "20"
private let panelEdition = "blue-bubu"
private let bluePetID = "bubu-office"
private let bluePetAvatarID = "custom:\(bluePetID)"
private let marketPricesEnabled: Bool = {
    guard let rawValue = ProcessInfo.processInfo.environment["BUBU_SHOW_MARKET_PRICES"] else {
        return true
    }
    return !["0", "false", "no", "off"].contains(rawValue.lowercased())
}()
// Track fast enough that the panel preserves its 14 px visual gap while the
// pet window is moving between animation positions.
private let followInterval: TimeInterval = 0.03
private let desktopClientCheckInterval: TimeInterval = 0.20
private let taskProgressRowHeight: CGFloat = 23
private let maximumVisibleTaskRows = 5
// The blue Bubu panel keeps the original 93 pt quota header, followed by the
// task rows and (in the Web3 build) one BTC row.
private let baseExpandedPanelHeight: CGFloat = marketPricesEnabled ? 137 : 116
private func panelSizeForTaskRows(_ count: Int) -> NSSize {
    let safeCount = max(1, min(maximumVisibleTaskRows, count))
    return NSSize(
        width: 224,
        height: baseExpandedPanelHeight + taskProgressRowHeight * CGFloat(safeCount)
    )
}
private let expandedPanelSize = panelSizeForTaskRows(1)
private let panelPetGap: CGFloat = 14
private let panelScreenMargin: CGFloat = 8
private let pointerTipBottomInset: CGFloat = 1
private let pointerHorizontalSafeInset: CGFloat = 18
private let canonicalPetSpriteSize = NSSize(width: 163, height: 177)
private let petAtlasFrameSize = NSSize(width: 192, height: 208)
// Alpha bounds (threshold 20) of every distinct visible frame in the 8x11
// office atlas. Matching both width and height lets us recover the zoom factor
// without mistaking coffee/singing/guitar animation padding for a resize.
private let petFrameVisiblePixelSizes: [NSSize] = [
    NSSize(width: 109, height: 166), NSSize(width: 109, height: 186),
    NSSize(width: 110, height: 172), NSSize(width: 110, height: 185),
    NSSize(width: 110, height: 186), NSSize(width: 110, height: 187),
    NSSize(width: 111, height: 186), NSSize(width: 113, height: 153),
    NSSize(width: 113, height: 181), NSSize(width: 114, height: 181),
    NSSize(width: 116, height: 182), NSSize(width: 116, height: 185),
    NSSize(width: 118, height: 187), NSSize(width: 118, height: 189),
    NSSize(width: 118, height: 192), NSSize(width: 118, height: 193),
    NSSize(width: 118, height: 194), NSSize(width: 119, height: 152),
    NSSize(width: 119, height: 155), NSSize(width: 119, height: 167),
    NSSize(width: 119, height: 194), NSSize(width: 120, height: 185),
    NSSize(width: 120, height: 189), NSSize(width: 120, height: 192),
    NSSize(width: 120, height: 194), NSSize(width: 121, height: 190),
    NSSize(width: 121, height: 192), NSSize(width: 121, height: 196),
    NSSize(width: 121, height: 198), NSSize(width: 122, height: 190),
    NSSize(width: 122, height: 191), NSSize(width: 122, height: 192),
    NSSize(width: 122, height: 194), NSSize(width: 123, height: 185),
    NSSize(width: 123, height: 196), NSSize(width: 123, height: 198),
    NSSize(width: 124, height: 191), NSSize(width: 124, height: 194),
    NSSize(width: 124, height: 198), NSSize(width: 125, height: 198),
    NSSize(width: 132, height: 198), NSSize(width: 133, height: 198),
    NSSize(width: 136, height: 198), NSSize(width: 138, height: 196),
    NSSize(width: 141, height: 196), NSSize(width: 144, height: 198),
    NSSize(width: 153, height: 198), NSSize(width: 154, height: 198),
    NSSize(width: 155, height: 198), NSSize(width: 157, height: 198),
    NSSize(width: 161, height: 198),
]
private let visualScaleTolerance: CGFloat = 0.12
private let minimumPanelScale: CGFloat = 0.20
private let maximumPanelScale: CGFloat = 8
// The v2 sprite has a small transparent top padding inside Codex's stored
// mascot anchor. Add it so the panel measures from Bubu's visible top tuft.
private let petSpriteTopPaddingInsideAnchor: CGFloat = 7

private final class BluePetSelectionStore {
    private let configURL: URL

    init(configURL: URL? = nil) {
        if let configURL {
            self.configURL = configURL
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let codexHome = environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true).path
        self.configURL = URL(fileURLWithPath: codexHome, isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    func bluePetIsSelected() -> Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return false
        }
        var section = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let sectionName = Self.sectionName(in: line) {
                section = sectionName
                continue
            }
            guard section == "desktop", Self.isSelectedAvatarLine(line),
                  let quoteStart = line.firstIndex(of: "\"")
            else { continue }
            let remainder = line[line.index(after: quoteStart)...]
            guard let quoteEnd = remainder.firstIndex(of: "\"") else { continue }
            return String(remainder[..<quoteEnd]) == bluePetAvatarID
        }
        return false
    }

    @discardableResult
    func selectBluePet() -> Bool {
        do {
            let original = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            let updated = Self.updatingDesktopSelection(in: original, avatarID: bluePetAvatarID)
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = updated.data(using: .utf8) else { return false }
            try data.write(to: configURL, options: .atomic)
            return bluePetIsSelected()
        } catch {
            return false
        }
    }

    static func updatingDesktopSelection(in text: String, avatarID: String) -> String {
        let selectionLine = "selected-avatar-id = \"\(avatarID)\""
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        var output: [String] = []
        var section = ""
        var desktopSeen = false
        var desktopSelectionWritten = false

        func appendDesktopSelectionIfNeeded() {
            guard section == "desktop", !desktopSelectionWritten else { return }
            output.append(selectionLine)
            desktopSelectionWritten = true
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if let sectionName = sectionName(in: trimmed) {
                appendDesktopSelectionIfNeeded()
                section = sectionName
                if section == "desktop" {
                    desktopSeen = true
                    desktopSelectionWritten = false
                }
                output.append(rawLine)
                continue
            }

            if (section.isEmpty || section == "desktop"), isSelectedAvatarLine(trimmed) {
                if section == "desktop", !desktopSelectionWritten {
                    output.append(selectionLine)
                    desktopSelectionWritten = true
                }
                continue
            }
            output.append(rawLine)
        }

        appendDesktopSelectionIfNeeded()
        if !desktopSeen {
            if let last = output.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                output.append("")
            }
            output.append("[desktop]")
            output.append(selectionLine)
        }
        return output.joined(separator: "\n") + "\n"
    }

    private static func sectionName(in line: String) -> String? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        return String(line[line.index(after: line.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isSelectedAvatarLine(_ line: String) -> Bool {
        guard let equals = line.firstIndex(of: "=") else { return false }
        return line[..<equals].trimmingCharacters(in: .whitespaces) == "selected-avatar-id"
    }
}

private struct PanelPlacement {
    let origin: NSPoint
    let pointerCenterX: CGFloat
    let actualGap: CGFloat
    let centerError: CGFloat
}

/// Places the pointer tip on Bubu's visible horizontal center and keeps its
/// tip exactly 14 logical points above the visible top tuft. All calculations
/// use AppKit points, so Retina and scaled displays preserve the same spacing.
private func panelPlacement(
    petVisibleRect: NSRect,
    panelSize: NSSize,
    panelScale: CGFloat,
    screenVisibleFrame: NSRect
) -> PanelPlacement {
    let minX = screenVisibleFrame.minX + panelScreenMargin
    let maxX = max(minX, screenVisibleFrame.maxX - panelSize.width - panelScreenMargin)
    let desiredX = petVisibleRect.midX - panelSize.width / 2
    let x = min(max(desiredX, minX), maxX)

    let desiredTipY = petVisibleRect.maxY + panelPetGap
    let desiredY = desiredTipY - pointerTipBottomInset * panelScale
    // Keep the pointer attached even near a display's top edge. Vertically
    // clamping the panel to the work area creates the large pet/panel split
    // reported on short or heavily scaled displays.
    let y = desiredY

    let originX = x
    let originY = y
    let rawPointerCenterX = petVisibleRect.midX - originX
    let safeMinX = min(pointerHorizontalSafeInset * panelScale, panelSize.width / 2)
    let safeMaxX = max(safeMinX, panelSize.width - safeMinX)
    let pointerCenterX = min(max(rawPointerCenterX, safeMinX), safeMaxX)
    let actualPointerX = originX + pointerCenterX
    let actualPointerTipY = originY + pointerTipBottomInset * panelScale

    return PanelPlacement(
        origin: NSPoint(x: originX, y: originY),
        pointerCenterX: pointerCenterX,
        actualGap: actualPointerTipY - petVisibleRect.maxY,
        centerError: actualPointerX - petVisibleRect.midX
    )
}

private func normalizedPanelScale(_ value: CGFloat) -> CGFloat {
    guard value.isFinite else { return 1 }
    return min(max(value, minimumPanelScale), maximumPanelScale)
}

private func scaledPanelSize(_ baseSize: NSSize, scale: CGFloat) -> NSSize {
    let safeScale = normalizedPanelScale(scale)
    return NSSize(width: baseSize.width * safeScale, height: baseSize.height * safeScale)
}

private func isCodexDesktopApplication(
    bundleIdentifier: String?,
    localizedName: String?,
    bundleURL: URL?,
    activationPolicy: NSApplication.ActivationPolicy
) -> Bool {
    guard activationPolicy == .regular else { return false }

    let normalizedIdentifier = bundleIdentifier?.lowercased() ?? ""
    if ["com.openai.codex", "com.openai.chatgpt", "com.openai.chat"].contains(normalizedIdentifier) {
        return true
    }

    let normalizedName = localizedName?.lowercased() ?? ""
    let normalizedBundleName = bundleURL?
        .deletingPathExtension()
        .lastPathComponent
        .lowercased() ?? ""
    let knownName = normalizedName == "codex" || normalizedName == "chatgpt"
    let knownBundle = normalizedBundleName == "codex" || normalizedBundleName == "chatgpt"
    return knownName && knownBundle
}

private func isCodexDesktopRunning() -> Bool {
    NSWorkspace.shared.runningApplications.contains { application in
        isCodexDesktopApplication(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            bundleURL: application.bundleURL,
            activationPolicy: application.activationPolicy
        )
    }
}

private func shouldPresentPanel(
    codexDesktopRunning: Bool,
    hiddenByUser: Bool,
    hasPetLocation: Bool
) -> Bool {
    codexDesktopRunning && !hiddenByUser && hasPetLocation
}

private func shouldTogglePanelForPetDoubleClick(
    clickCount: Int,
    clickLocation: NSPoint,
    petVisibleRect: NSRect
) -> Bool {
    clickCount == 2 && petVisibleRect.contains(clickLocation)
}

private final class RuntimeHealthWriter {
    private let fileURL: URL = {
        if let override = ProcessInfo.processInfo.environment["BUBU_PANEL_HEALTH_FILE"],
           !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/io.github.mayday-materials.bubu-quota-panel/panel-health.json")
    }()
    private var lastSignature = ""
    private var lastWriteAt: CFAbsoluteTime = 0

    func write(
        status: String,
        panelVisible: Bool,
        locationSource: String?,
        gap: CGFloat? = nil,
        centerError: CGFloat? = nil,
        panelScale: CGFloat = 1,
        panelSize: NSSize? = nil,
        force: Bool = false
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let safeScale = normalizedPanelScale(panelScale)
        let livePanelSize = panelSize ?? scaledPanelSize(expandedPanelSize, scale: safeScale)
        // Do not turn a live resize into 30 disk writes per second. Scale and
        // dimensions are included in the periodic payload, while the signature
        // remains limited to meaningful visibility/source changes.
        let signature = "\(status)|\(panelVisible)|\(locationSource ?? "none")"
        guard force || signature != lastSignature || now - lastWriteAt >= 15 else { return }

        var payload: [String: Any] = [
            "version": panelVersion,
            "edition": panelEdition,
            "petID": bluePetID,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "status": status,
            "panelVisible": panelVisible,
            "marketPricesEnabled": marketPricesEnabled,
            "panelBaseHeightPoints": expandedPanelSize.height,
            "panelWidthPoints": livePanelSize.width,
            "panelHeightPoints": livePanelSize.height,
            "panelScale": safeScale,
            "locationSource": locationSource ?? NSNull(),
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if let gap { payload["petGapPoints"] = gap }
        if let centerError { payload["pointerCenterErrorPoints"] = centerError }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            lastSignature = signature
            lastWriteAt = now
        } catch {
            // The panel must remain usable even if a managed Mac blocks cache writes.
        }
    }
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int64?
    let resetsAt: Int64?
}

private struct SpendControlLimit: Decodable {
    let remainingPercent: Int
    let resetsAt: Int64
}

private struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let individualLimit: SpendControlLimit?
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

private struct RPCError: Decodable {
    let message: String
}

private struct RPCResponse: Decodable {
    let id: Int?
    let result: RateLimitsResult?
    let error: RPCError?
}

private struct QuotaRow {
    let name: String
    let remainingPercent: Int
    let resetsAt: Date?
}

private enum TaskProgressKind: String, Equatable {
    case reading
    case running
    case waitingForInput
    case completed
    case failed
    case idle
}

private struct TaskProgressItem: Equatable {
    let title: String
    let kind: TaskProgressKind
    let startedAt: Date
    let statusOverride: String?

    init(
        title: String,
        kind: TaskProgressKind,
        startedAt: Date = .distantPast,
        statusOverride: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.startedAt = startedAt
        self.statusOverride = statusOverride
    }

    var statusText: String {
        if let statusOverride { return statusOverride }
        switch kind {
        case .reading:
            return "读取中"
        case .running:
            return "正在执行"
        case .waitingForInput:
            return "等你确认"
        case .completed:
            return "已完成"
        case .failed:
            return "执行失败"
        case .idle:
            return "等待"
        }
    }
}

private struct TaskProgressSnapshot: Equatable {
    let items: [TaskProgressItem]

    var kind: TaskProgressKind { items.first?.kind ?? .idle }
    var text: String {
        items.first?.statusText ?? "等待任务"
    }

    var rowCount: Int { max(1, items.count) }

    static let reading = TaskProgressSnapshot(items: [TaskProgressItem(
        title: "正在读取任务",
        kind: .reading
    )])

    static let idle = TaskProgressSnapshot(items: [TaskProgressItem(
        title: "暂无进行中的任务",
        kind: .idle
    )])

    static func displaying(_ sourceItems: [TaskProgressItem]) -> TaskProgressSnapshot {
        guard !sourceItems.isEmpty else { return .idle }

        // Recurring Codex tasks create a new thread on every run. Multiple
        // rows with the same title are indistinguishable in this compact view,
        // so show the highest-priority/newest sorted instance only.
        var seenTitles = Set<String>()
        let deduplicated = sourceItems.filter { item in
            let key = item.title
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .lowercased()
            return seenTitles.insert(key).inserted
        }
        guard !deduplicated.isEmpty else { return .idle }
        return TaskProgressSnapshot(items: Array(deduplicated.prefix(maximumVisibleTaskRows)))
    }
}

private final class CodexTaskProgressReader {
    struct UnreadThreadState {
        let ids: Set<String>
        let isAvailable: Bool
    }

    private struct RolloutCandidate {
        let url: URL
        let modificationDate: Date
    }

    private struct ParsedCacheEntry {
        let modificationDate: Date
        let snapshot: TaskProgressSnapshot
    }

    private let fileManager = FileManager.default
    private let maximumTailBytes: UInt64 = 1_048_576
    private let rolloutRescanInterval: TimeInterval = 5
    private let activeTaskFreshness: TimeInterval = 30 * 60
    private let completedTaskVisibility: TimeInterval = 2 * 60
    private var cachedRollouts: [RolloutCandidate] = []
    private var cachedRolloutVisibility: [String: Bool] = [:]
    private var parsedCache: [String: ParsedCacheEntry] = [:]
    private var cachedThreadTitles: [String: String] = [:]
    private var cachedThreadIndexModificationDate: Date?
    private var cachedUnreadThreadIDs = Set<String>()
    private var cachedUnreadStateModificationDate: Date?
    private var hasCachedUnreadState = false
    private var nextRolloutScanAt = Date.distantPast

    func read() -> TaskProgressSnapshot {
        let now = Date()
        let threadTitles = readThreadTitleIndex()
        let unreadState = readUnreadThreadState()
        var items: [TaskProgressItem] = []
        for candidate in recentRollouts(at: now, unreadThreadIDs: unreadState.ids) {
            let cacheKey = candidate.url.path
            let snapshot: TaskProgressSnapshot
            if let cached = parsedCache[cacheKey],
               cached.modificationDate == candidate.modificationDate
            {
                snapshot = cached.snapshot
            } else {
                guard let lines = readTailLines(from: candidate.url) else { continue }
                snapshot = Self.parse(
                    lines: lines,
                    modificationDate: candidate.modificationDate,
                    now: now
                )
                parsedCache[cacheKey] = ParsedCacheEntry(
                    modificationDate: candidate.modificationDate,
                    snapshot: snapshot
                )
            }
            guard var item = snapshot.items.first, item.kind != .idle else { continue }
            let resolvedTitle = Self.resolvedTitle(
                for: candidate.url,
                indexedTitles: threadTitles,
                fallback: item.title
            )
            if resolvedTitle != item.title {
                item = TaskProgressItem(
                    title: resolvedTitle,
                    kind: item.kind,
                    startedAt: item.startedAt,
                    statusOverride: item.statusOverride
                )
            }
            let threadID = Self.threadID(from: candidate.url)
            guard Self.shouldDisplay(
                kind: item.kind,
                threadID: threadID,
                modificationDate: candidate.modificationDate,
                now: now,
                unreadState: unreadState,
                fallbackVisibility: completedTaskVisibility
            ) else { continue }
            items.append(item)
        }

        items.sort {
            let leftTerminal = $0.kind == .completed || $0.kind == .failed
            let rightTerminal = $1.kind == .completed || $1.kind == .failed
            if leftTerminal != rightTerminal { return !leftTerminal }
            if $0.startedAt == $1.startedAt { return $0.title < $1.title }
            if leftTerminal { return $0.startedAt > $1.startedAt }
            return $0.startedAt < $1.startedAt
        }
        return .displaying(items)
    }

    static func parse(
        lines: [String],
        modificationDate: Date,
        now: Date
    ) -> TaskProgressSnapshot {
        var lifecycle: TaskProgressKind?
        var pendingUserInputCalls = Set<String>()
        var latestUserTitle: String?
        var activeTaskTitle: String?
        var taskStartedAt = modificationDate

        for line in lines {
            guard line.contains("task_started")
                || line.contains("task_complete")
                || line.contains("task_failed")
                || line.contains("turn_aborted")
                || line.contains(#""type":"error""#)
                || line.contains("user_message")
                || line.contains("request_user_input")
                || line.contains("function_call_output")
                || line.contains("custom_tool_call_output")
            else { continue }

            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = record["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String
            else { continue }

            if record["type"] as? String == "event_msg" {
                if payloadType == "user_message",
                   let message = payload["message"] as? String,
                   let title = taskTitle(from: message)
                {
                    latestUserTitle = title
                } else if payloadType == "task_started" {
                    lifecycle = .running
                    pendingUserInputCalls.removeAll()
                    activeTaskTitle = latestUserTitle ?? activeTaskTitle
                    taskStartedAt = timestamp(from: record) ?? modificationDate
                } else if payloadType == "task_complete" {
                    lifecycle = .completed
                    pendingUserInputCalls.removeAll()
                } else if ["task_failed", "turn_aborted", "error"].contains(payloadType) {
                    lifecycle = .failed
                    pendingUserInputCalls.removeAll()
                }
                continue
            }

            if ["function_call", "custom_tool_call"].contains(payloadType),
               payload["name"] as? String == "request_user_input",
               let callID = payload["call_id"] as? String
            {
                pendingUserInputCalls.insert(callID)
                continue
            }

            if ["function_call_output", "custom_tool_call_output"].contains(payloadType),
               let callID = payload["call_id"] as? String
            {
                pendingUserInputCalls.remove(callID)
            }
        }

        let title = activeTaskTitle ?? latestUserTitle ?? "Codex 任务"
        if lifecycle == .running, !pendingUserInputCalls.isEmpty {
            return TaskProgressSnapshot(items: [TaskProgressItem(
                title: title,
                kind: .waitingForInput,
                startedAt: taskStartedAt
            )])
        }
        if let lifecycle {
            return TaskProgressSnapshot(items: [TaskProgressItem(
                title: title,
                kind: lifecycle,
                startedAt: taskStartedAt
            )])
        }
        if !pendingUserInputCalls.isEmpty {
            return TaskProgressSnapshot(items: [TaskProgressItem(
                title: title,
                kind: .waitingForInput,
                startedAt: taskStartedAt
            )])
        }
        if now.timeIntervalSince(modificationDate) <= 30 * 60 {
            return TaskProgressSnapshot(items: [TaskProgressItem(
                title: title,
                kind: .running,
                startedAt: taskStartedAt
            )])
        }
        return .idle
    }

    private static func taskTitle(from rawMessage: String) -> String? {
        var value = rawMessage
        if let marker = value.range(
            of: "## My request for Codex:",
            options: [.caseInsensitive]
        ) {
            value = String(value[marker.upperBound...])
        }
        if let imageTag = value.range(of: "<image", options: [.caseInsensitive]) {
            value = String(value[..<imageTag.lowerBound])
        }

        let lines = value.components(separatedBy: .newlines).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("# Files mentioned"),
                  !trimmed.hasPrefix("## My request"),
                  !trimmed.hasPrefix("/")
            else { return nil }
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#*- "))
        }
        let title = lines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return String(title.prefix(80))
    }

    private static func timestamp(from record: [String: Any]) -> Date? {
        guard let raw = record["timestamp"] as? String else { return nil }
        return iso8601WithFractional.date(from: raw) ?? iso8601.date(from: raw)
    }

    static func threadID(from rolloutURL: URL) -> String? {
        let filename = rolloutURL.deletingPathExtension().lastPathComponent
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let range = filename.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(filename[range]).lowercased()
    }

    static func resolvedTitle(
        for rolloutURL: URL,
        indexedTitles: [String: String],
        fallback: String
    ) -> String {
        guard let threadID = threadID(from: rolloutURL),
              let indexedTitle = indexedTitles[threadID],
              !indexedTitle.isEmpty
        else { return fallback }
        return indexedTitle
    }

    static func isUserVisibleSessionMetadata(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any]
        else {
            return true
        }

        let threadSource = (payload["thread_source"] as? String)?.lowercased()
        if threadSource == "subagent" || threadSource == "automation" {
            return false
        }
        if let source = payload["source"] as? [String: Any], source["subagent"] != nil {
            return false
        }
        return true
    }

    static func shouldDisplay(
        kind: TaskProgressKind,
        threadID: String?,
        modificationDate: Date,
        now: Date,
        unreadState: UnreadThreadState,
        fallbackVisibility: TimeInterval = 2 * 60
    ) -> Bool {
        guard kind == .completed || kind == .failed else { return true }
        if unreadState.isAvailable, let threadID {
            return unreadState.ids.contains(threadID)
        }
        return now.timeIntervalSince(modificationDate) <= fallbackVisibility
    }

    private func codexHomeURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    private func readThreadTitleIndex() -> [String: String] {
        let indexURL = codexHomeURL().appendingPathComponent("session_index.jsonl")
        guard let values = try? indexURL.resourceValues(
            forKeys: [.contentModificationDateKey, .isRegularFileKey]
        ),
        values.isRegularFile == true,
        let modificationDate = values.contentModificationDate
        else {
            return cachedThreadTitles
        }

        if cachedThreadIndexModificationDate == modificationDate {
            return cachedThreadTitles
        }
        guard let data = try? Data(contentsOf: indexURL),
              let text = String(data: data, encoding: .utf8)
        else {
            return cachedThreadTitles
        }

        var titles: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let rawID = record["id"] as? String,
                  let rawTitle = record["thread_name"] as? String
            else { continue }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            titles[rawID.lowercased()] = String(title.prefix(80))
        }

        cachedThreadTitles = titles
        cachedThreadIndexModificationDate = modificationDate
        return titles
    }

    private func readUnreadThreadState() -> UnreadThreadState {
        let stateURL: URL
        if let override = ProcessInfo.processInfo.environment["BUBU_CODEX_STATE_FILE"],
           !override.isEmpty
        {
            stateURL = URL(fileURLWithPath: override)
        } else {
            stateURL = codexHomeURL().appendingPathComponent(".codex-global-state.json")
        }

        guard let values = try? stateURL.resourceValues(
            forKeys: [.contentModificationDateKey, .isRegularFileKey]
        ),
        values.isRegularFile == true,
        let modificationDate = values.contentModificationDate
        else {
            return UnreadThreadState(
                ids: cachedUnreadThreadIDs,
                isAvailable: hasCachedUnreadState
            )
        }
        if cachedUnreadStateModificationDate == modificationDate {
            return UnreadThreadState(
                ids: cachedUnreadThreadIDs,
                isAvailable: hasCachedUnreadState
            )
        }

        guard let data = try? Data(contentsOf: stateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atomState = root["electron-persisted-atom-state"] as? [String: Any],
              let unreadByHost = atomState["unread-thread-ids-by-host-v1"] as? [String: Any]
        else {
            return UnreadThreadState(
                ids: cachedUnreadThreadIDs,
                isAvailable: hasCachedUnreadState
            )
        }

        var ids = Set<String>()
        for value in unreadByHost.values {
            guard let hostIDs = value as? [String] else { continue }
            ids.formUnion(hostIDs.map { $0.lowercased() })
        }
        cachedUnreadThreadIDs = ids
        cachedUnreadStateModificationDate = modificationDate
        hasCachedUnreadState = true
        return UnreadThreadState(ids: ids, isAvailable: true)
    }

    private func recentRollouts(
        at now: Date,
        unreadThreadIDs: Set<String>
    ) -> [RolloutCandidate] {
        if let override = ProcessInfo.processInfo.environment["BUBU_TASK_ROLLOUT_FILE"],
           !override.isEmpty
        {
            let url = URL(fileURLWithPath: override)
            guard isUserVisibleRollout(url) else { return [] }
            let modified = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? now
            return [RolloutCandidate(url: url, modificationDate: modified)]
        }

        if now < nextRolloutScanAt, !cachedRollouts.isEmpty {
            return cachedRollouts.filter { fileManager.fileExists(atPath: $0.url.path) }
        }

        nextRolloutScanAt = now.addingTimeInterval(rolloutRescanInterval)
        let codexHome = codexHomeURL()
        let sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            cachedRollouts = []
            return []
        }

        var candidates: [RolloutCandidate] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.hasPrefix("rollout-"),
                  let values = try? url.resourceValues(
                      forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            let threadID = Self.threadID(from: url)
            let isUnread = threadID.map { unreadThreadIDs.contains($0) } ?? false
            guard now.timeIntervalSince(modified) <= activeTaskFreshness || isUnread,
                  isUserVisibleRollout(url)
            else {
                continue
            }
            candidates.append(RolloutCandidate(url: url, modificationDate: modified))
        }

        cachedRollouts = Array(candidates.sorted {
            $0.modificationDate > $1.modificationDate
        }.prefix(12))
        let activePaths = Set(cachedRollouts.map { $0.url.path })
        parsedCache = parsedCache.filter { activePaths.contains($0.key) }
        return cachedRollouts
    }

    private func isUserVisibleRollout(_ url: URL) -> Bool {
        if let cached = cachedRolloutVisibility[url.path] { return cached }

        var isVisible = true
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let data = try? handle.read(upToCount: 262_144),
               let text = String(data: data, encoding: .utf8),
               let firstLine = text.split(separator: "\n", maxSplits: 1).first
            {
                isVisible = Self.isUserVisibleSessionMetadata(line: String(firstLine))
            }
        }
        cachedRolloutVisibility[url.path] = isVisible
        return isVisible
    }

    private func readTailLines(from url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let startOffset = fileSize > maximumTailBytes ? fileSize - maximumTailBytes : 0
        do {
            try handle.seek(toOffset: startOffset)
            guard var data = try handle.readToEnd(), !data.isEmpty else { return [] }
            if startOffset > 0, let firstNewline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(...firstNewline)
            }
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            return text.split(whereSeparator: \.isNewline).map(String.init)
        } catch {
            return nil
        }
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}

private struct BinanceTickerResponse: Decodable {
    let symbol: String
    let price: String
}

private func codexSnapshot(from response: RateLimitsResult) -> RateLimitSnapshot {
    if let snapshots = response.rateLimitsByLimitId {
        if let exactMatch = snapshots["codex"] {
            return exactMatch
        }
        if let idMatch = snapshots.values.first(where: { $0.limitId == "codex" }) {
            return idMatch
        }
    }
    return response.rateLimits
}

private enum PointerSide: Equatable {
    case left
    case right
    case bottom
}

private enum QuotaClientError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case noResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "没有找到 Codex 本机服务"
        case .launchFailed(let detail):
            return "无法启动 Codex 本机服务：\(detail)"
        case .noResponse:
            return "Codex 暂未返回额度数据"
        case .server(let detail):
            return detail
        }
    }
}

private final class CodexQuotaClient {
    private let decoder = JSONDecoder()

    func fetch(completion: @escaping (Result<RateLimitsResult, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            completion(self.fetchSynchronously())
        }
    }

    private func fetchSynchronously() -> Result<RateLimitsResult, Error> {
        guard let codexURL = locateCodex() else {
            return .failure(QuotaClientError.codexNotFound)
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.executableURL = codexURL
        process.arguments = ["app-server", "--stdio"]
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        do {
            try process.run()
        } catch {
            return .failure(QuotaClientError.launchFailed(error.localizedDescription))
        }

        func writeLines(_ lines: [String]) {
            let text = lines.joined(separator: "\n") + "\n"
            if let data = text.data(using: .utf8) {
                stdin.fileHandleForWriting.write(data)
            }
        }

        writeLines([
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"bubu-quota-panel\",\"version\":\"\(panelVersion)\"},\"capabilities\":{\"experimentalApi\":true}}}",
        ])

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) {
            if process.isRunning {
                process.terminate()
            }
        }

        var buffer = Data()
        var didSendReadRequest = false
        var finalResponse: RPCResponse?

        readLoop: while process.isRunning {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int
                else { continue }

                if id == 1 && !didSendReadRequest {
                    didSendReadRequest = true
                    writeLines([
                        #"{"jsonrpc":"2.0","method":"initialized"}"#,
                        #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":null}"#,
                    ])
                    continue
                }

                if id == 2 {
                    finalResponse = try? decoder.decode(RPCResponse.self, from: line)
                    break readLoop
                }
            }
        }

        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()

        if let result = finalResponse?.result {
            return .success(result)
        }
        if let error = finalResponse?.error {
            return .failure(QuotaClientError.server(error.message))
        }

        return .failure(QuotaClientError.noResponse)
    }

    private func locateCodex() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_BIN"],
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".codex/packages/standalone/current/bin/codex").path,
            home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path,
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ].compactMap { $0 }

        return candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }).map(URL.init(fileURLWithPath:))
    }
}

private struct MarketPriceClientError: LocalizedError {
    enum Kind {
        case invalidResponse
        case server(Int)
        case invalidPrice
    }

    let symbol: String
    let kind: Kind

    var errorDescription: String? {
        switch kind {
        case .invalidResponse:
            return "\(symbol) 价格暂时无法读取"
        case .server(let statusCode):
            return "\(symbol) 接口返回 \(statusCode)"
        case .invalidPrice:
            return "\(symbol) 价格格式异常"
        }
    }
}

private final class MarketPriceClient {
    private let decoder = JSONDecoder()
    private let symbol: String
    private let endpoint: URL

    init(symbol: String) {
        self.symbol = symbol
        self.endpoint = URL(
            string: "https://data-api.binance.vision/api/v3/ticker/price?symbol=\(symbol)"
        )!
    }

    func fetch(completion: @escaping (Result<Double, Error>) -> Void) {
        var request = URLRequest(url: endpoint)
        let requestedSymbol = symbol
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [decoder] data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(MarketPriceClientError(symbol: requestedSymbol, kind: .invalidResponse)))
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                completion(.failure(MarketPriceClientError(symbol: requestedSymbol, kind: .server(httpResponse.statusCode))))
                return
            }
            guard let data,
                  let ticker = try? decoder.decode(BinanceTickerResponse.self, from: data),
                  ticker.symbol == requestedSymbol,
                  let price = Double(ticker.price),
                  price > 0
            else {
                completion(.failure(MarketPriceClientError(symbol: requestedSymbol, kind: .invalidPrice)))
                return
            }
            completion(.success(price))
        }.resume()
    }
}

private final class QuotaPanelView: NSView {
    var rows: [QuotaRow] = [] { didSet { needsDisplay = true } }
    var statusText = "正在读取额度…" { didSet { needsDisplay = true } }
    var errorText: String? { didSet { needsDisplay = true } }
    var taskProgress = TaskProgressSnapshot.reading {
        didSet {
            if taskProgress != oldValue {
                needsDisplay = true
                updateRunningArrowTimer()
            }
        }
    }
    var btcPrice: Double? { didSet { needsDisplay = true } }
    var btcPriceDirection = 0 { didSet { needsDisplay = true } }
    var btcStatusText = "读取中…" { didSet { needsDisplay = true } }
    var pointerSide: PointerSide = .left {
        didSet {
            guard pointerSide != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var pointerCenterX: CGFloat? {
        didSet {
            guard pointerCenterX != oldValue else { return }
            needsDisplay = true
        }
    }
    var onRequestHide: (() -> Void)?
    private var hideButtonTrackingArea: NSTrackingArea?
    private var isHideButtonHovered = false
    private var runningArrowTimer: Timer?

    private lazy var backgroundImage: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("quota-panel-background.png")
        else { return nil }
        return NSImage(contentsOf: resourceURL)
    }()

    private lazy var completedTaskIcon: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("task-completed-icon.png")
        else { return nil }
        return NSImage(contentsOf: resourceURL)
    }()

    private lazy var runningTaskIcon: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("task-running-icon.png")
        else { return nil }
        return NSImage(contentsOf: resourceURL)
    }()

    private lazy var waitingTaskIcon: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("task-waiting-icon.png")
        else { return nil }
        return NSImage(contentsOf: resourceURL)
    }()

    private lazy var failedTaskIcon: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("task-failed-icon.png")
        else { return nil }
        return NSImage(contentsOf: resourceURL)
    }()

    override var isFlipped: Bool { true }

    deinit {
        runningArrowTimer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRunningArrowTimer()
    }

    private func updateRunningArrowTimer() {
        let shouldAnimate = window != nil && taskProgress.items.contains { $0.kind == .running }
        if shouldAnimate, runningArrowTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
            RunLoop.main.add(timer, forMode: .common)
            runningArrowTimer = timer
        } else if !shouldAnimate {
            runningArrowTimer?.invalidate()
            runningArrowTimer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .high

        let bodyRect = panelBodyRect()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.set()

        let background = NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.085, alpha: 0.97)
        let border = NSColor.white.withAlphaComponent(0.22)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 17, yRadius: 17)
        background.setFill()
        bodyPath.fill()

        if let backgroundImage {
            NSGraphicsContext.saveGraphicsState()
            bodyPath.addClip()
            drawFiveBallBand(backgroundImage, in: bodyRect)
            NSColor.black.withAlphaComponent(0.08).setFill()
            bodyPath.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        border.setStroke()
        bodyPath.lineWidth = 1
        bodyPath.stroke()

        let arrow = NSBezierPath()
        switch pointerSide {
        case .left:
            let centerY = bodyRect.midY
            arrow.move(to: NSPoint(x: bodyRect.minX + 1, y: centerY - 8))
            arrow.line(to: NSPoint(x: 1, y: centerY))
            arrow.line(to: NSPoint(x: bodyRect.minX + 1, y: centerY + 8))
        case .right:
            let centerY = bodyRect.midY
            arrow.move(to: NSPoint(x: bodyRect.maxX - 1, y: centerY - 8))
            arrow.line(to: NSPoint(x: bounds.maxX - 1, y: centerY))
            arrow.line(to: NSPoint(x: bodyRect.maxX - 1, y: centerY + 8))
        case .bottom:
            let requestedCenterX = pointerCenterX ?? bodyRect.midX
            let centerX = min(
                max(requestedCenterX, bodyRect.minX + 12),
                bodyRect.maxX - 12
            )
            arrow.move(to: NSPoint(x: centerX - 8, y: bodyRect.maxY - 1))
            arrow.line(to: NSPoint(x: centerX, y: bounds.maxY - 1))
            arrow.line(to: NSPoint(x: centerX + 8, y: bodyRect.maxY - 1))
        }
        arrow.close()
        background.setFill()
        arrow.fill()
        border.setStroke()
        arrow.lineWidth = 1
        arrow.stroke()

        NSShadow().set()

        let contentX = bodyRect.minX + 14
        let contentWidth = bodyRect.width - 28
        let hideButton = hideButtonRect(in: bodyRect)
        let hideButtonPath = NSBezierPath(roundedRect: hideButton, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(isHideButtonHovered ? 0.20 : 0.11).setFill()
        hideButtonPath.fill()
        NSColor.white.withAlphaComponent(isHideButtonHovered ? 0.38 : 0.20).setStroke()
        hideButtonPath.lineWidth = 0.75
        hideButtonPath.stroke()
        drawText(
            "隐藏",
            in: NSRect(x: hideButton.minX, y: hideButton.minY + 2, width: hideButton.width, height: 15),
            font: .systemFont(ofSize: 9.5, weight: .medium),
            color: NSColor.white.withAlphaComponent(isHideButtonHovered ? 1.0 : 0.86),
            alignment: .center
        )

        if let errorText {
            drawText(
                errorText,
                in: NSRect(x: contentX, y: 14, width: contentWidth - 48, height: 38),
                font: .systemFont(ofSize: 12, weight: .medium),
                color: NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.38, alpha: 1)
            )
        } else if rows.isEmpty {
            drawText(
                "正在向 Codex 本机服务查询…",
                in: NSRect(x: contentX, y: 14, width: contentWidth - 48, height: 20),
                font: .systemFont(ofSize: 11.5, weight: .medium),
                color: NSColor.white.withAlphaComponent(0.68)
            )
        } else {
            for (index, row) in rows.prefix(1).enumerated() {
                draw(row: row, index: index, x: contentX, width: contentWidth)
            }
        }

        drawText(
            statusText,
            in: NSRect(
                x: contentX + 96,
                y: 77,
                width: contentWidth - 96,
                height: 14
            ),
            font: .systemFont(ofSize: 9.2, weight: .regular),
            color: NSColor.white.withAlphaComponent(0.72),
            alignment: .right
        )

        let taskItems = taskProgress.items.isEmpty
            ? TaskProgressSnapshot.idle.items
            : taskProgress.items
        for (index, item) in taskItems.enumerated() {
            drawTaskProgressItem(
                item,
                index: index,
                y: 103 + CGFloat(index) * taskProgressRowHeight,
                separatorY: 96 + CGFloat(index) * taskProgressRowHeight,
                contentX: contentX,
                contentWidth: contentWidth
            )
        }
        let taskProgressSectionHeight = taskProgressRowHeight * CGFloat(max(1, taskItems.count))

        if marketPricesEnabled {
            drawMarketPriceRow(
                symbol: "BTC/USDT",
                iconText: "₿",
                iconColor: NSColor(calibratedRed: 0.97, green: 0.58, blue: 0.11, alpha: 1),
                price: btcPrice,
                direction: btcPriceDirection,
                statusText: btcStatusText,
                y: 103 + taskProgressSectionHeight,
                separatorY: 96 + taskProgressSectionHeight,
                contentX: contentX,
                contentWidth: contentWidth
            )
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hideButtonTrackingArea {
            removeTrackingArea(hideButtonTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: hideButtonRect(in: panelBodyRect()),
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hideButtonTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHideButtonHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHideButtonHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let bodyRect = panelBodyRect()
        if hideButtonRect(in: bodyRect).contains(point) {
            onRequestHide?()
            return
        }
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(hideButtonRect(in: panelBodyRect()), cursor: .pointingHand)
    }

    private func panelBodyRect() -> NSRect {
        let arrowWidth: CGFloat = 10
        switch pointerSide {
        case .left:
            return NSRect(x: arrowWidth, y: 3, width: bounds.width - arrowWidth, height: bounds.height - 6)
        case .right:
            return NSRect(x: 0, y: 3, width: bounds.width - arrowWidth, height: bounds.height - 6)
        case .bottom:
            return NSRect(x: 3, y: 3, width: bounds.width - 6, height: bounds.height - arrowWidth - 3)
        }
    }

    private func hideButtonRect(in bodyRect: NSRect) -> NSRect {
        NSRect(x: bodyRect.maxX - 48, y: 10, width: 38, height: 18)
    }

    private func draw(row: QuotaRow, index: Int, x: CGFloat, width: CGFloat) {
        let top = CGFloat(13 + index * 43)
        let remaining = max(0, min(100, row.remainingPercent))
        let valueStart = x + 68
        let valueRight = x + width - 48

        drawText(
            row.name,
            in: NSRect(x: x, y: top, width: 64, height: 16),
            font: .systemFont(ofSize: 10.8, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.88)
        )
        drawText(
            "剩余 \(remaining)%",
            in: NSRect(x: valueStart, y: top, width: valueRight - valueStart, height: 16),
            font: .monospacedDigitSystemFont(ofSize: 10.8, weight: .semibold),
            color: progressColor(for: remaining),
            alignment: .right
        )

        let trackRect = NSRect(x: x, y: top + 55, width: width, height: 4)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2, yRadius: 2)
        NSColor.black.withAlphaComponent(0.30).setFill()
        track.fill()

        let fillWidth = max(3, width * CGFloat(remaining) / 100)
        let fill = NSBezierPath(
            roundedRect: NSRect(x: x, y: top + 55, width: fillWidth, height: 4),
            xRadius: 2,
            yRadius: 2
        )
        progressColor(for: remaining).setFill()
        fill.fill()

        let resetText: String
        if let date = row.resetsAt {
            resetText = "\(Self.resetFormatter.string(from: date)) 重置"
        } else {
            resetText = "重置时间未知"
        }
        drawText(
            resetText,
            in: NSRect(x: x, y: top + 64, width: 94, height: 14),
            font: .systemFont(ofSize: 9.2, weight: .regular),
            color: NSColor.white.withAlphaComponent(0.72)
        )
    }

    private func drawFiveBallBand(_ image: NSImage, in destinationRect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        // The poster's central band contains the five balls without either
        // MAYDAY text stripe. Restrict it to the fixed quota header.
        let sourceRect = NSRect(
            x: 0,
            y: imageSize.height * 0.34,
            width: imageSize.width,
            height: imageSize.height * 0.32
        )
        let imageRect = NSRect(
            x: destinationRect.minX,
            y: destinationRect.minY,
            width: destinationRect.width,
            height: min(93, destinationRect.height)
        )

        image.draw(
            in: imageRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawTaskProgressItem(
        _ item: TaskProgressItem,
        index: Int,
        y: CGFloat,
        separatorY: CGFloat,
        contentX: CGFloat,
        contentWidth: CGFloat
    ) {
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: contentX, y: separatorY))
        separator.line(to: NSPoint(x: contentX + contentWidth, y: separatorY))
        NSColor.white.withAlphaComponent(0.13).setStroke()
        separator.lineWidth = 0.75
        separator.stroke()

        let color = taskProgressColor(for: item.kind)
        let taskIcon: NSImage?
        switch item.kind {
        case .running:
            taskIcon = runningTaskIcon
        case .waitingForInput:
            taskIcon = waitingTaskIcon
        case .completed:
            taskIcon = completedTaskIcon
        case .failed:
            taskIcon = failedTaskIcon
        case .reading, .idle:
            taskIcon = nil
        }
        let usesStatusIcon = taskIcon != nil
        if let taskIcon {
            let iconRect = NSRect(x: contentX - 2, y: y, width: 20, height: 15)
            taskIcon.draw(
                in: iconRect,
                from: NSRect(origin: .zero, size: taskIcon.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            drawTaskStatusBadge(for: item.kind, iconRect: iconRect)
        } else {
            let dot = NSBezierPath(ovalIn: NSRect(x: contentX, y: y + 4, width: 7, height: 7))
            color.setFill()
            dot.fill()
        }

        let titleOffset: CGFloat = usesStatusIcon ? 22 : 13
        let titleReservedWidth: CGFloat = usesStatusIcon ? 89 : 80

        drawText(
            item.title,
            in: NSRect(
                x: contentX + titleOffset,
                y: y,
                width: contentWidth - titleReservedWidth,
                height: 15
            ),
            font: .systemFont(ofSize: 9.4, weight: index == 0 ? .semibold : .medium),
            color: NSColor.white.withAlphaComponent(0.84)
        )
        drawText(
            item.statusText,
            in: NSRect(x: contentX + contentWidth - 66, y: y, width: 66, height: 15),
            font: .systemFont(ofSize: 9.2, weight: .semibold),
            color: color,
            alignment: .right
        )
    }

    private func drawTaskStatusBadge(for kind: TaskProgressKind, iconRect: NSRect) {
        // Completed and failed artwork already contains its status badge.
        guard kind != .completed && kind != .failed else { return }

        let badgeRect = NSRect(
            x: iconRect.minX + 10.6,
            y: iconRect.minY + 0.4,
            width: 8.4,
            height: 8.4
        )
        let badge = NSBezierPath(ovalIn: badgeRect)
        switch kind {
        case .running:
            NSColor(calibratedRed: 0.12, green: 0.46, blue: 0.96, alpha: 1).setFill()
            badge.fill()
            drawRunningArrow(in: badgeRect)
        case .waitingForInput:
            NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.10, alpha: 1).setFill()
            badge.fill()
            drawText(
                "?",
                in: badgeRect.offsetBy(dx: 0, dy: -0.4),
                font: .systemFont(ofSize: 7.2, weight: .heavy),
                color: .white,
                alignment: .center
            )
        case .failed:
            NSColor(calibratedRed: 0.91, green: 0.20, blue: 0.12, alpha: 1).setFill()
            badge.fill()
            let inset = badgeRect.insetBy(dx: 2.1, dy: 2.1)
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: inset.minX, y: inset.minY))
            cross.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
            cross.move(to: NSPoint(x: inset.maxX, y: inset.minY))
            cross.line(to: NSPoint(x: inset.minX, y: inset.maxY))
            NSColor.white.setStroke()
            cross.lineWidth = 1.15
            cross.lineCapStyle = .round
            cross.stroke()
        case .reading, .completed, .idle:
            break
        }
    }

    private func drawRunningArrow(in badgeRect: NSRect) {
        let center = NSPoint(x: badgeRect.midX, y: badgeRect.midY)
        let radius = badgeRect.width * 0.31
        let progress = Date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 1.2) / 1.2
        let rotation = CGFloat(progress) * 2 * .pi
        let start: CGFloat = rotation - .pi * 0.40
        let sweep: CGFloat = .pi * 1.56
        let segments = 18
        let arc = NSBezierPath()
        for index in 0...segments {
            let angle = start + sweep * CGFloat(index) / CGFloat(segments)
            let point = NSPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 { arc.move(to: point) } else { arc.line(to: point) }
        }
        NSColor.white.setStroke()
        arc.lineWidth = 1.05
        arc.lineCapStyle = .round
        arc.stroke()

        let end = start + sweep
        let tip = NSPoint(
            x: center.x + cos(end) * radius,
            y: center.y + sin(end) * radius
        )
        let tangent = NSPoint(x: -sin(end), y: cos(end))
        let normal = NSPoint(x: -tangent.y, y: tangent.x)
        let base = NSPoint(x: tip.x - tangent.x * 1.6, y: tip.y - tangent.y * 1.6)
        let head = NSBezierPath()
        head.move(to: tip)
        head.line(to: NSPoint(x: base.x + normal.x * 0.72, y: base.y + normal.y * 0.72))
        head.line(to: NSPoint(x: base.x - normal.x * 0.72, y: base.y - normal.y * 0.72))
        head.close()
        NSColor.white.setFill()
        head.fill()
    }

    private func drawMarketPriceRow(
        symbol: String,
        iconText: String,
        iconColor: NSColor,
        price: Double?,
        direction: Int,
        statusText: String,
        y: CGFloat,
        separatorY: CGFloat,
        contentX: CGFloat,
        contentWidth: CGFloat
    ) {
        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: contentX, y: separatorY))
        separator.line(to: NSPoint(x: contentX + contentWidth, y: separatorY))
        NSColor.white.withAlphaComponent(0.13).setStroke()
        separator.lineWidth = 0.75
        separator.stroke()

        let iconRect = NSRect(x: contentX, y: y, width: 15, height: 15)
        let icon = NSBezierPath(ovalIn: iconRect)
        iconColor.setFill()
        icon.fill()
        drawText(
            iconText,
            in: NSRect(x: iconRect.minX, y: iconRect.minY + 0.5, width: iconRect.width, height: 14),
            font: .systemFont(ofSize: 10.2, weight: .bold),
            color: .white,
            alignment: .center
        )

        drawText(
            symbol,
            in: NSRect(x: contentX + 20, y: y, width: 62, height: 15),
            font: .systemFont(ofSize: 9.6, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.78)
        )

        if let price {
            let formattedPrice = Self.btcPriceFormatter.string(from: NSNumber(value: price)) ?? "--"
            drawText(
                formattedPrice,
                in: NSRect(x: contentX + 78, y: y - 1.5, width: 76, height: 17),
                font: .monospacedDigitSystemFont(ofSize: 11.4, weight: .bold),
                color: marketPriceColor(direction: direction),
                alignment: .right
            )
        } else {
            drawText(
                "--",
                in: NSRect(x: contentX + 78, y: y - 1.5, width: 76, height: 17),
                font: .monospacedDigitSystemFont(ofSize: 11.4, weight: .bold),
                color: NSColor.white.withAlphaComponent(0.70),
                alignment: .right
            )
        }

        drawText(
            statusText,
            in: NSRect(x: contentX + 158, y: y + 1, width: contentWidth - 158, height: 14),
            font: .systemFont(ofSize: 8.3, weight: .regular),
            color: NSColor.white.withAlphaComponent(0.54),
            alignment: .right
        )
    }

    private func marketPriceColor(direction: Int) -> NSColor {
        switch direction {
        case 1:
            return NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 1)
        case -1:
            return NSColor(calibratedRed: 1.0, green: 0.39, blue: 0.43, alpha: 1)
        default:
            return NSColor.white.withAlphaComponent(0.94)
        }
    }

    private func taskProgressColor(for kind: TaskProgressKind) -> NSColor {
        switch kind {
        case .reading:
            return NSColor.white.withAlphaComponent(0.56)
        case .running:
            return NSColor(calibratedRed: 0.22, green: 0.68, blue: 1.0, alpha: 1)
        case .waitingForInput:
            return NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.22, alpha: 1)
        case .completed:
            return NSColor(calibratedRed: 0.24, green: 0.86, blue: 0.58, alpha: 1)
        case .failed:
            return NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.30, alpha: 1)
        case .idle:
            return NSColor.white.withAlphaComponent(0.56)
        }
    }

    private func progressColor(for remaining: Int) -> NSColor {
        if remaining <= 20 {
            return NSColor(calibratedRed: 1.0, green: 0.34, blue: 0.39, alpha: 1)
        }
        if remaining <= 45 {
            return NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.22, alpha: 1)
        }
        return NSColor(calibratedRed: 0.22, green: 0.60, blue: 1.0, alpha: 1)
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .shadow: Self.textShadow,
            ]
        )
    }

    private static let textShadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(
            calibratedRed: 0.0,
            green: 0.20,
            blue: 0.23,
            alpha: 0.84
        )
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        return shadow
    }()

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static let btcPriceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}

private struct LocatedPet {
    let overlayRect: NSRect
    let visibleRect: NSRect
    let panelScale: CGFloat
    let screen: NSScreen
    let source: String
}

private final class PetWindowLocator {
    private struct StoredMascotMetrics {
        let left: CGFloat
        let top: CGFloat
        let width: CGFloat
        let height: CGFloat
        let topPadding: CGFloat
        let source: String
    }

    private struct StoredOverlayLocation {
        let rect: CGRect
        let mascot: StoredMascotMetrics?
        let isPrimary: Bool
    }

    private struct MatchedMascotMetrics {
        let metrics: StoredMascotMetrics
        let referenceSize: CGSize
    }

    private var cachedWindowID: CGWindowID?
    private var cachedMascotMetrics: StoredMascotMetrics?
    private var cachedOverlaySize: CGSize?
    private var cachedVisualMetrics: StoredMascotMetrics?
    private var cachedVisualOverlaySize: CGSize?
    private var cachedVisualWindowID: CGWindowID?
    private var lastVisualProbeAt: CFAbsoluteTime = 0
    private var lastOverlayStateReadAt: CFAbsoluteTime = 0
    private var storedOverlayLocations: [StoredOverlayLocation] = []
    private(set) var overlayOpen: Bool?

    func locate() -> LocatedPet? {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastOverlayStateReadAt >= 0.05 {
            lastOverlayStateReadAt = now
            refreshStoredOverlayState()
        }

        if let cachedWindowID,
           let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, cachedWindowID) as? [[String: Any]],
           let window = windows.first,
           let candidate = candidate(from: window),
           let location = makeLocation(from: candidate.rect, windowID: cachedWindowID)
        {
            return location
        }

        cachedWindowID = nil
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return storedOverlayLocation()
        }

        let candidates: [(id: CGWindowID, rect: CGRect, score: Double)] = windows.compactMap { window in
            guard let number = window[kCGWindowNumber as String] as? NSNumber,
                  let candidate = candidate(from: window)
            else { return nil }
            return (number.uint32Value, candidate.rect, candidate.score)
        }

        guard let best = candidates.min(by: { $0.score < $1.score }) else {
            return storedOverlayLocation()
        }
        cachedWindowID = best.id
        return makeLocation(from: best.rect, windowID: best.id) ?? storedOverlayLocation()
    }

    func locateSavedState() -> LocatedPet? {
        refreshStoredOverlayState()
        return storedOverlayLocation()
    }

    private func makeLocation(from quartzRect: CGRect, windowID: CGWindowID) -> LocatedPet? {
        guard let converted = convertToAppKit(quartzRect) else { return nil }
        let visualMetrics = currentVisualMetrics(
            windowID: windowID,
            overlayRect: quartzRect
        )

        if let matched = bestStoredMetrics(matching: quartzRect),
           let quartzMetrics = scaledMetrics(matched.metrics, from: matched.referenceSize, to: quartzRect.size),
           let appMetrics = scaledMetrics(quartzMetrics, from: quartzRect.size, to: converted.0.size)
        {
            cachedMascotMetrics = quartzMetrics
            cachedOverlaySize = quartzRect.size
            if let visualMetrics,
               let appVisualMetrics = scaledMetrics(
                   visualMetrics,
                   from: quartzRect.size,
                   to: converted.0.size
               )
            {
                return LocatedPet(
                    overlayRect: converted.0,
                    visibleRect: visibleRect(in: converted.0, metrics: appVisualMetrics),
                    panelScale: reconciledPanelScale(
                        anchorMetrics: quartzMetrics,
                        visualMetrics: visualMetrics
                    ),
                    screen: converted.1,
                    source: "window-visual-probe"
                )
            }
            return LocatedPet(
                overlayRect: converted.0,
                visibleRect: visibleRect(in: converted.0, metrics: appMetrics),
                panelScale: panelScale(for: quartzMetrics),
                screen: converted.1,
                source: "window-\(quartzMetrics.source)"
            )
        }

        // Keep the last verified relative anchor during the few milliseconds
        // between the live window moving and Codex persisting its new bounds.
        if let cachedMascotMetrics,
           let cachedOverlaySize,
           let quartzMetrics = scaledMetrics(cachedMascotMetrics, from: cachedOverlaySize, to: quartzRect.size),
           let appMetrics = scaledMetrics(quartzMetrics, from: quartzRect.size, to: converted.0.size)
        {
            self.cachedMascotMetrics = quartzMetrics
            self.cachedOverlaySize = quartzRect.size
            if let visualMetrics,
               let appVisualMetrics = scaledMetrics(
                   visualMetrics,
                   from: quartzRect.size,
                   to: converted.0.size
               )
            {
                return LocatedPet(
                    overlayRect: converted.0,
                    visibleRect: visibleRect(in: converted.0, metrics: appVisualMetrics),
                    panelScale: reconciledPanelScale(
                        anchorMetrics: quartzMetrics,
                        visualMetrics: visualMetrics
                    ),
                    screen: converted.1,
                    source: "window-visual-probe-cached-anchor"
                )
            }
            return LocatedPet(
                overlayRect: converted.0,
                visibleRect: visibleRect(in: converted.0, metrics: appMetrics),
                panelScale: panelScale(for: quartzMetrics),
                screen: converted.1,
                source: "window-cached-anchor"
            )
        }

        if let visualMetrics,
           let appVisualMetrics = scaledMetrics(
               visualMetrics,
               from: quartzRect.size,
               to: converted.0.size
           )
        {
            return LocatedPet(
                overlayRect: converted.0,
                visibleRect: visibleRect(in: converted.0, metrics: appVisualMetrics),
                panelScale: visualPanelScale(for: visualMetrics),
                screen: converted.1,
                source: "window-visual-probe-only"
            )
        }

        return nil
    }

    private func refreshStoredOverlayState() {
        let stateURL: URL
        if let override = ProcessInfo.processInfo.environment["BUBU_CODEX_STATE_FILE"],
           !override.isEmpty
        {
            stateURL = URL(fileURLWithPath: override)
        } else {
            stateURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/.codex-global-state.json")
        }
        guard let data = try? Data(contentsOf: stateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let containers: [[String: Any]] = [
            root,
            root["electron-persisted-atom-state"] as? [String: Any],
            root["state"] as? [String: Any],
            root["settings"] as? [String: Any],
        ].compactMap { $0 }
        guard let container = containers.first(where: {
            $0["electron-avatar-overlay-bounds"] is [String: Any]
        }) else {
            storedOverlayLocations = []
            return
        }
        overlayOpen = container["electron-avatar-overlay-open"] as? Bool
        guard let overlay = container["electron-avatar-overlay-bounds"] as? [String: Any] else {
            storedOverlayLocations = []
            return
        }

        var locations: [StoredOverlayLocation] = []

        func addEntry(_ entry: [String: Any], isPrimary: Bool = false) {
            guard let x = entry["x"] as? NSNumber,
                  let y = entry["y"] as? NSNumber
            else { return }

            // Some Codex builds update x/y and placement immediately but omit
            // width, height and mascot while the overlay is on an external
            // display. Retain that current-display entry with the canonical
            // reference size; it will be scaled against the live Quartz window.
            let width = (entry["width"] as? NSNumber)?.doubleValue ?? 356
            let height = (entry["height"] as? NSNumber)?.doubleValue ?? 320
            guard width > 0, height > 0 else { return }

            let rect = CGRect(
                x: x.doubleValue,
                y: y.doubleValue,
                width: width,
                height: height
            )
            let mascot = mascotMetrics(from: entry, overlayRect: rect)
                ?? centeredFallbackMetrics(for: rect.size)
            locations.append(StoredOverlayLocation(rect: rect, mascot: mascot, isPrimary: isPrimary))
        }

        // The root entry is the most recently active display and is the best fallback.
        addEntry(overlay, isPrimary: true)
        if let byDisplayID = overlay["byDisplayId"] as? [String: Any] {
            for value in byDisplayID.values {
                if let entry = value as? [String: Any] {
                    addEntry(entry)
                }
            }
        }
        // Older Codex releases sometimes only retain a resolution-keyed copy.
        if let byResolution = overlay["byResolution"] as? [String: Any] {
            for value in byResolution.values {
                if let entry = value as? [String: Any] {
                    addEntry(entry)
                }
            }
        }

        storedOverlayLocations = locations
    }

    private func centeredFallbackMetrics(for overlaySize: CGSize) -> StoredMascotMetrics {
        let width = min(canonicalPetSpriteSize.width, overlaySize.width)
        let height = min(canonicalPetSpriteSize.height, overlaySize.height)
        return StoredMascotMetrics(
            left: max(0, (overlaySize.width - width) / 2),
            top: petSpriteTopPaddingInsideAnchor,
            width: width,
            height: height,
            topPadding: petSpriteTopPaddingInsideAnchor,
            source: "state-centered-fallback"
        )
    }

    private func mascotMetrics(
        from entry: [String: Any],
        overlayRect: CGRect
    ) -> StoredMascotMetrics? {
        if let mascot = entry["mascot"] as? [String: Any],
           let left = mascot["left"] as? NSNumber,
           let top = mascot["top"] as? NSNumber,
           let width = mascot["width"] as? NSNumber
        {
            let derivedHeight = width.doubleValue * 177 / 163
            let height = (mascot["height"] as? NSNumber)?.doubleValue ?? derivedHeight
            let mascotScale = normalizedPanelScale(
                CGFloat(width.doubleValue) / canonicalPetSpriteSize.width
            )
            let metrics = StoredMascotMetrics(
                left: CGFloat(left.doubleValue),
                top: CGFloat(top.doubleValue),
                width: CGFloat(width.doubleValue),
                height: CGFloat(height),
                topPadding: petSpriteTopPaddingInsideAnchor * mascotScale,
                source: "state-mascot"
            )
            if metricsAreValid(metrics, for: overlayRect.size) { return metrics }
        }

        // Compatibility with Codex builds that persisted only an absolute
        // anchor rectangle instead of relative `mascot` metrics.
        if let anchor = entry["anchor"] as? [String: Any],
           let x = anchor["x"] as? NSNumber,
           let y = anchor["y"] as? NSNumber,
           let width = anchor["width"] as? NSNumber,
           let height = anchor["height"] as? NSNumber
        {
            let anchorScale = normalizedPanelScale(
                CGFloat(width.doubleValue) / canonicalPetSpriteSize.width
            )
            let metrics = StoredMascotMetrics(
                left: CGFloat(x.doubleValue - overlayRect.minX),
                top: CGFloat(y.doubleValue - overlayRect.minY),
                width: CGFloat(width.doubleValue),
                height: CGFloat(height.doubleValue),
                topPadding: petSpriteTopPaddingInsideAnchor * anchorScale,
                source: "state-anchor"
            )
            if metricsAreValid(metrics, for: overlayRect.size) { return metrics }
        }
        return nil
    }

    private func metricsAreValid(_ metrics: StoredMascotMetrics, for size: CGSize) -> Bool {
        metrics.left.isFinite
            && metrics.top.isFinite
            && metrics.width.isFinite
            && metrics.height.isFinite
            && metrics.topPadding.isFinite
            && metrics.width >= 24
            && metrics.height >= 40
            && metrics.left >= -2
            && metrics.top >= -2
            && metrics.left + metrics.width <= size.width + 2
            && metrics.top + metrics.height <= size.height + 2
    }

    private func scaledMetrics(
        _ metrics: StoredMascotMetrics,
        from referenceSize: CGSize,
        to liveSize: CGSize
    ) -> StoredMascotMetrics? {
        guard referenceSize.width > 0,
              referenceSize.height > 0,
              liveSize.width > 0,
              liveSize.height > 0
        else { return nil }

        let scaleX = liveSize.width / referenceSize.width
        let scaleY = liveSize.height / referenceSize.height
        guard scaleX.isFinite,
              scaleY.isFinite,
              scaleX >= 0.20,
              scaleX <= 8,
              scaleY >= 0.20,
              scaleY <= 8,
              abs(log(scaleX / scaleY)) <= 0.30
        else { return nil }

        let scaled = StoredMascotMetrics(
            left: metrics.left * scaleX,
            top: metrics.top * scaleY,
            width: metrics.width * scaleX,
            height: metrics.height * scaleY,
            topPadding: metrics.topPadding * scaleY,
            source: metrics.source
        )
        return metricsAreValid(scaled, for: liveSize) ? scaled : nil
    }

    private func bestStoredMetrics(matching liveRect: CGRect) -> MatchedMascotMetrics? {
        let matches = storedOverlayLocations.compactMap { stored -> (MatchedMascotMetrics, Double)? in
            guard let metrics = stored.mascot else { return nil }
            let scaleX = liveRect.width / stored.rect.width
            let scaleY = liveRect.height / stored.rect.height
            guard scaleX.isFinite,
                  scaleY.isFinite,
                  scaleX >= 0.20,
                  scaleX <= 8,
                  scaleY >= 0.20,
                  scaleY <= 8,
                  abs(log(scaleX / scaleY)) <= 0.30,
                  scaledMetrics(metrics, from: stored.rect.size, to: liveRect.size) != nil
            else { return nil }

            // Electron display IDs are not guaranteed to equal CGDirectDisplayID.
            // Match the live Quartz rectangle to the nearest persisted rectangle
            // instead; this remains stable across Retina scale and monitor order.
            let centerDistance = hypot(stored.rect.midX - liveRect.midX, stored.rect.midY - liveRect.midY)
            let primaryBonus = stored.isPrimary ? -1.0 : 0.0
            let uniformityPenalty = abs(log(scaleX / scaleY)) * 2_000
            let scalePenalty = abs(log(scaleX)) * 4
            let score = Double(uniformityPenalty + scalePenalty + centerDistance * 0.08) + primaryBonus
            return (
                MatchedMascotMetrics(metrics: metrics, referenceSize: stored.rect.size),
                score
            )
        }
        return matches.min(by: { $0.1 < $1.1 })?.0
    }

    private func panelScale(for metrics: StoredMascotMetrics) -> CGFloat {
        let widthScale = metrics.width / canonicalPetSpriteSize.width
        let heightScale = metrics.height / canonicalPetSpriteSize.height
        guard widthScale.isFinite,
              heightScale.isFinite,
              widthScale > 0,
              heightScale > 0
        else { return 1 }

        // Use both axes so a temporarily rounded Electron window dimension
        // cannot make the panel pulse by one pixel while Bubu is zooming.
        return normalizedPanelScale(sqrt(widthScale * heightScale))
    }

    private func visualScaleCandidates(
        for metrics: StoredMascotMetrics
    ) -> [(scale: CGFloat, distortion: CGFloat)] {
        guard metrics.width.isFinite,
              metrics.height.isFinite,
              metrics.width > 0,
              metrics.height > 0
        else { return [] }

        let candidates = petFrameVisiblePixelSizes.compactMap { frameSize
            -> (scale: CGFloat, distortion: CGFloat)? in
            let expectedWidth = frameSize.width
                * canonicalPetSpriteSize.width / petAtlasFrameSize.width
            let expectedHeight = frameSize.height
                * canonicalPetSpriteSize.height / petAtlasFrameSize.height
            let widthScale = metrics.width / expectedWidth
            let heightScale = metrics.height / expectedHeight
            guard widthScale.isFinite,
                  heightScale.isFinite,
                  widthScale > 0,
                  heightScale > 0
            else { return nil }
            return (
                normalizedPanelScale(sqrt(widthScale * heightScale)),
                abs(log(widthScale / heightScale))
            )
        }
        guard let bestDistortion = candidates.map(\.distortion).min(),
              bestDistortion <= 0.15
        else { return [] }
        // One-pixel antialiasing differences matter at very small scales. Keep
        // all atlas frames whose aspect fit is within 2% of the best match.
        return candidates.filter { $0.distortion <= bestDistortion + 0.02 }
    }

    private func visualPanelScale(for metrics: StoredMascotMetrics) -> CGFloat {
        let scales = visualScaleCandidates(for: metrics)
            .map(\.scale)
            .sorted()
        guard !scales.isEmpty else { return 1 }
        return scales[scales.count / 2]
    }

    private func reconciledPanelScale(
        anchorMetrics: StoredMascotMetrics,
        visualMetrics: StoredMascotMetrics
    ) -> CGFloat {
        let anchorScale = panelScale(for: anchorMetrics)
        let candidates = visualScaleCandidates(for: visualMetrics)
        guard let visualScale = candidates.min(by: {
            abs(log($0.scale / anchorScale)) < abs(log($1.scale / anchorScale))
        })?.scale else { return anchorScale }
        guard anchorScale > 0, visualScale > 0 else { return anchorScale }

        // Ordinary sprite rows vary slightly in visible height. Keep the
        // persisted anchor scale for that small variation, but trust the real
        // pixels when Codex shrinks the rendered pet inside a stale anchor.
        let relativeDifference = abs(log(visualScale / anchorScale))
        return relativeDifference > visualScaleTolerance ? visualScale : anchorScale
    }

    private func visibleRect(in overlayRect: NSRect, metrics: StoredMascotMetrics) -> NSRect {
        let visibleHeight = max(1, metrics.height - metrics.topPadding)
        return NSRect(
            x: overlayRect.minX + metrics.left,
            y: overlayRect.maxY - metrics.top - metrics.height,
            width: metrics.width,
            height: visibleHeight
        )
    }

    private func storedOverlayLocation() -> LocatedPet? {
        guard overlayOpen != false else { return nil }

        for stored in storedOverlayLocations.sorted(by: { $0.isPrimary && !$1.isPrimary }) {
            guard let mascot = stored.mascot else { continue }
            guard let converted = convertToAppKit(stored.rect) else { continue }
            cachedMascotMetrics = mascot
            cachedOverlaySize = stored.rect.size
            guard let appMetrics = scaledMetrics(mascot, from: stored.rect.size, to: converted.0.size) else {
                continue
            }
            return LocatedPet(
                overlayRect: converted.0,
                visibleRect: visibleRect(in: converted.0, metrics: appMetrics),
                panelScale: panelScale(for: mascot),
                screen: converted.1,
                source: "saved-\(mascot.source)"
            )
        }
        return nil
    }

    private func currentVisualMetrics(
        windowID: CGWindowID,
        overlayRect: CGRect
    ) -> StoredMascotMetrics? {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastVisualProbeAt >= 0.12 {
            lastVisualProbeAt = now
            if let metrics = probeVisibleMascotMetrics(
                windowID: windowID,
                overlaySize: overlayRect.size
            ) {
                cachedVisualMetrics = metrics
                cachedVisualOverlaySize = overlayRect.size
                cachedVisualWindowID = windowID
                return metrics
            }
        }

        // A live pixel probe can occasionally fail while macOS is compositing
        // the transparent Electron overlay. The persisted mascot rectangle may
        // already be stale after a move, so keep the last verified pixels for
        // this exact window ID until a newer successful probe replaces them.
        guard cachedVisualWindowID == windowID,
              let cachedVisualMetrics,
              let cachedVisualOverlaySize
        else { return nil }
        return scaledMetrics(
            cachedVisualMetrics,
            from: cachedVisualOverlaySize,
            to: overlayRect.size
        )
    }

    private func probeVisibleMascotMetrics(
        windowID: CGWindowID,
        overlaySize: CGSize
    ) -> StoredMascotMetrics? {
        // Never trigger the macOS Screen Recording consent dialog just to
        // position this companion panel. Pixel probing is an optional accuracy
        // enhancement only when the user has already granted that permission.
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming]
        ), image.width >= 80, image.height >= 80,
        let data = image.dataProvider?.data,
        let bytes = CFDataGetBytePtr(data)
        else { return nil }

        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let bytesPerRow = image.bytesPerRow
        guard bytesPerPixel >= 4,
              overlaySize.width > 0,
              overlaySize.height > 0
        else { return nil }

        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1
        var visiblePixels = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                var isVisible = false
                for channel in 0..<min(bytesPerPixel, 4) where bytes[offset + channel] > 20 {
                    isVisible = true
                    break
                }
                guard isVisible else { continue }
                visiblePixels += 1
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        let totalPixels = image.width * image.height
        guard visiblePixels >= 64,
              visiblePixels < Int(Double(totalPixels) * 0.80),
              maxX >= minX,
              maxY >= minY
        else { return nil }

        // Window captures use backing pixels on Retina displays. Width is
        // always complete even when macOS clips transparent rows, so use it as
        // the uniform backing scale for both axes.
        let backingScale = CGFloat(image.width) / overlaySize.width
        guard backingScale.isFinite, backingScale > 0 else { return nil }
        let metrics = StoredMascotMetrics(
            left: CGFloat(minX) / backingScale,
            top: CGFloat(minY) / backingScale,
            width: CGFloat(maxX - minX + 1) / backingScale,
            height: CGFloat(maxY - minY + 1) / backingScale,
            topPadding: 0,
            source: "visual-pixels"
        )
        return metricsAreValid(metrics, for: overlaySize) ? metrics : nil
    }

    private func candidate(from window: [String: Any]) -> (rect: CGRect, score: Double)? {
        guard let ownerName = window[kCGWindowOwnerName as String] as? String,
              let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
              layer >= 0,
              layer < 50,
              let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
              alpha > 0.05,
              let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: rawBounds),
              bounds.width >= 160,
              bounds.width <= 900,
              bounds.height >= 120,
              bounds.height <= 1_000
        else { return nil }

        let normalizedOwner = ownerName.lowercased()
        guard normalizedOwner.contains("codex") || normalizedOwner.contains("chatgpt") else {
            return nil
        }

        let name = window[kCGWindowName as String] as? String ?? ""
        var score = Double(abs(bounds.width - 356) + abs(bounds.height - 320) * 0.35)
        score += Double(abs(layer - 3) * 50)
        if name == "ChatGPT" || name == "Codex" { score -= 80 }

        if let distance = storedOverlayLocations.map({ stored in
            hypot(bounds.midX - stored.rect.midX, bounds.midY - stored.rect.midY)
        }).min() {
            score += Double(distance * 0.08)
        }
        return (bounds, score)
    }

    private func convertToAppKit(_ quartzRect: CGRect) -> (NSRect, NSScreen)? {
        let center = CGPoint(x: quartzRect.midX, y: quartzRect.midY)

        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard displayBounds.contains(center) || displayBounds.intersects(quartzRect) else {
                continue
            }

            guard displayBounds.width > 0, displayBounds.height > 0 else { continue }
            let scaleX = screen.frame.width / displayBounds.width
            let scaleY = screen.frame.height / displayBounds.height
            let x = screen.frame.minX + (quartzRect.minX - displayBounds.minX) * scaleX
            let y = screen.frame.maxY
                - (quartzRect.minY - displayBounds.minY) * scaleY
                - quartzRect.height * scaleY
            return (
                NSRect(
                    x: x,
                    y: y,
                    width: quartzRect.width * scaleX,
                    height: quartzRect.height * scaleY
                ),
                screen
            )
        }
        return nil
    }

    func scalingSelfTest() -> Bool {
        let baseSize = CGSize(width: 356, height: 320)
        let base = StoredMascotMetrics(
            left: 165,
            top: 8,
            width: 163,
            height: 177,
            topPadding: petSpriteTopPaddingInsideAnchor,
            source: "self-test"
        )
        let centeredFallback = centeredFallbackMetrics(for: baseSize)
        guard abs(centeredFallback.left + centeredFallback.width / 2 - baseSize.width / 2) <= 0.01,
              let scaledFallback = scaledMetrics(
                  centeredFallback,
                  from: baseSize,
                  to: CGSize(width: 408, height: 400)
              ),
              abs(scaledFallback.left + scaledFallback.width / 2 - 204) <= 0.01
        else { return false }
        for factor in [0.25, 0.5, 1.0, 1.25, 2.0, 3.0] as [CGFloat] {
            let liveSize = CGSize(width: baseSize.width * factor, height: baseSize.height * factor)
            guard let scaled = scaledMetrics(base, from: baseSize, to: liveSize),
                  abs(scaled.left - base.left * factor) <= 0.01,
                  abs(scaled.top - base.top * factor) <= 0.01,
                  abs(scaled.width - base.width * factor) <= 0.01,
                  abs(scaled.height - base.height * factor) <= 0.01,
                  abs(scaled.topPadding - base.topPadding * factor) <= 0.01,
                  abs(panelScale(for: scaled) - factor) <= 0.01
            else { return false }
        }
        guard scaledMetrics(
            base,
            from: baseSize,
            to: CGSize(width: baseSize.width * 2, height: baseSize.height * 0.5)
        ) == nil else { return false }

        // The Electron overlay may retain its old transparent bounds while
        // the pet itself is zoomed inside them. In that case the visible
        // pixels, not the stale anchor, must drive the whole panel scale.
        let visualCases: [(
            anchor: CGFloat,
            visual: CGFloat,
            expected: CGFloat,
            frame: NSSize
        )] = [
            (1.0, 0.4, 0.4, NSSize(width: 161, height: 198)),
            (1.0, 0.7, 0.7, NSSize(width: 161, height: 198)),
            (0.5, 0.5, 0.5, NSSize(width: 161, height: 198)),
            (1.0, 0.94, 1.0, NSSize(width: 161, height: 198)),
            (1.0, 1.0, 1.0, NSSize(width: 119, height: 152)),
            (1.0, 0.4, 0.4, NSSize(width: 119, height: 152)),
        ]
        for test in visualCases {
            let anchor = StoredMascotMetrics(
                left: 0,
                top: 0,
                width: canonicalPetSpriteSize.width * test.anchor,
                height: canonicalPetSpriteSize.height * test.anchor,
                topPadding: 0,
                source: "self-test-anchor"
            )
            let visual = StoredMascotMetrics(
                left: 0,
                top: 0,
                width: test.frame.width * canonicalPetSpriteSize.width
                    / petAtlasFrameSize.width * test.visual,
                height: test.frame.height * canonicalPetSpriteSize.height
                    / petAtlasFrameSize.height * test.visual,
                topPadding: 0,
                source: "self-test-visual"
            )
            guard abs(reconciledPanelScale(anchorMetrics: anchor, visualMetrics: visual)
                - test.expected) <= 0.01
            else { return false }
        }
        return true
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let quotaClient = CodexQuotaClient()
    private let taskProgressReader = CodexTaskProgressReader()
    private let btcPriceClient = MarketPriceClient(symbol: "BTCUSDT")
    private let locator = PetWindowLocator()
    private let healthWriter = RuntimeHealthWriter()
    private let petSelectionStore = BluePetSelectionStore()
    private let quotaView = QuotaPanelView(frame: NSRect(origin: .zero, size: expandedPanelSize))
    private var panel: NSPanel!
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var taskProgressTimer: Timer?
    private var btcRefreshTimer: Timer?
    private var followTimer: Timer?
    private var globalMouseMonitor: Any?
    private var isRefreshing = false
    private var isRefreshingTaskProgress = false
    private var isRefreshingBTCPrice = false
    private var lastBTCPrice: Double?
    private var lastLocatedPet: LocatedPet?
    private var lastLocatedAt: CFAbsoluteTime = 0
    private var currentPanelScale: CGFloat = 1
    private var currentBasePanelSize = expandedPanelSize
    private var isPanelHiddenByUser = false
    private var cachedCodexDesktopRunning = false
    private var lastCodexDesktopCheckAt: CFAbsoluteTime = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // This executable is blue-only. Always restore the matching pet after
        // replacing an older mixed experimental build.
        _ = petSelectionStore.selectBluePet()
        makePanel()
        makeStatusItem()
        startPetDoubleClickMonitor()
        healthWriter.write(status: "started", panelVisible: false, locationSource: nil, force: true)
        followPet()
        refreshQuota()
        refreshTaskProgress()
        if marketPricesEnabled {
            refreshBTCPrice()
        }

        followTimer = Timer.scheduledTimer(withTimeInterval: followInterval, repeats: true) { [weak self] _ in
            self?.followPet()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshQuota()
        }
        taskProgressTimer = Timer.scheduledTimer(
            withTimeInterval: taskProgressRefreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refreshTaskProgress()
        }
        if marketPricesEnabled {
            btcRefreshTimer = Timer.scheduledTimer(withTimeInterval: btcRefreshInterval, repeats: true) { [weak self] _ in
                self?.refreshBTCPrice()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        taskProgressTimer?.invalidate()
        btcRefreshTimer?.invalidate()
        followTimer?.invalidate()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        healthWriter.write(status: "terminated", panelVisible: false, locationSource: nil, force: true)
    }

    private func makePanel() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: expandedPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = quotaView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        quotaView.onRequestHide = { [weak self] in
            self?.hidePanelByUser()
        }
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "卜卜"
        item.button?.toolTip = "显示卜卜额度面板"
        item.button?.target = self
        item.button?.action = #selector(showPanelFromStatusItem)
        item.isVisible = false
        statusItem = item
    }

    private func startPetDoubleClickMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] event in
            guard event.clickCount == 2 else { return }
            let clickCount = event.clickCount
            let clickLocation = NSEvent.mouseLocation
            DispatchQueue.main.async {
                self?.handlePetDoubleClick(at: clickLocation, clickCount: clickCount)
            }
        }
    }

    private func handlePetDoubleClick(at location: NSPoint, clickCount: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        guard codexDesktopRunning(at: now), let pet = locator.locate() else { return }
        guard shouldTogglePanelForPetDoubleClick(
            clickCount: clickCount,
            clickLocation: location,
            petVisibleRect: pet.visibleRect
        ) else { return }

        lastLocatedPet = pet
        lastLocatedAt = now
        if isPanelHiddenByUser {
            showPanelFromStatusItem()
        } else {
            hidePanelByUser()
        }
    }

    private func hidePanelByUser() {
        isPanelHiddenByUser = true
        panel.orderOut(nil)
        statusItem?.isVisible = true
        healthWriter.write(
            status: "hidden-by-user",
            panelVisible: false,
            locationSource: nil,
            panelScale: currentPanelScale,
            panelSize: scaledPanelSize(currentBasePanelSize, scale: currentPanelScale),
            force: true
        )
    }

    @objc private func showPanelFromStatusItem() {
        isPanelHiddenByUser = false
        statusItem?.isVisible = false
        followPet()
    }

    private func codexDesktopRunning(at now: CFAbsoluteTime) -> Bool {
        if lastCodexDesktopCheckAt == 0
            || now - lastCodexDesktopCheckAt >= desktopClientCheckInterval
        {
            lastCodexDesktopCheckAt = now
            cachedCodexDesktopRunning = isCodexDesktopRunning()
        }
        return cachedCodexDesktopRunning
    }

    private func followPet() {
        let now = CFAbsoluteTimeGetCurrent()
        guard codexDesktopRunning(at: now) else {
            lastLocatedPet = nil
            lastLocatedAt = 0
            panel.orderOut(nil)
            healthWriter.write(
                status: "waiting-for-codex",
                panelVisible: false,
                locationSource: nil,
                panelScale: currentPanelScale,
                panelSize: scaledPanelSize(currentBasePanelSize, scale: currentPanelScale)
            )
            return
        }

        let pet: LocatedPet
        if let located = locator.locate() {
            lastLocatedPet = located
            lastLocatedAt = now
            pet = located
        } else if let recent = lastLocatedPet, now - lastLocatedAt <= 0.50 {
            // Preserve the last exact attachment only across a brief window-list
            // transition. Never leave the panel at an unrelated screen corner.
            pet = recent
        } else {
            panel.orderOut(nil)
            healthWriter.write(
                status: "waiting-for-pet-location",
                panelVisible: false,
                locationSource: nil,
                panelScale: currentPanelScale,
                panelSize: scaledPanelSize(currentBasePanelSize, scale: currentPanelScale)
            )
            return
        }

        let basePanelSize = currentBasePanelSize
        currentPanelScale = normalizedPanelScale(pet.panelScale)
        if isPanelHiddenByUser {
            panel.orderOut(nil)
            return
        }

        let currentPanelSize = scaledPanelSize(basePanelSize, scale: currentPanelScale)
        let placement = panelPlacement(
            petVisibleRect: pet.visibleRect,
            panelSize: currentPanelSize,
            panelScale: currentPanelScale,
            screenVisibleFrame: pet.screen.visibleFrame
        )

        quotaView.pointerSide = .bottom
        quotaView.pointerCenterX = placement.pointerCenterX / currentPanelScale
        let targetOrigin = placement.origin
        let targetFrame = NSRect(origin: targetOrigin, size: currentPanelSize)
        if abs(panel.frame.origin.x - targetOrigin.x) > 0.1
            || abs(panel.frame.origin.y - targetOrigin.y) > 0.1
            || abs(panel.frame.size.width - currentPanelSize.width) > 0.1
            || abs(panel.frame.size.height - currentPanelSize.height) > 0.1
        {
            panel.setFrame(targetFrame, display: false)
        }
        // Keep the view's design coordinate system at the current task-list
        // height while its frame follows the scaled window. AppKit then scales
        // every visual and hit target together without changing proportions.
        quotaView.frame = NSRect(origin: .zero, size: currentPanelSize)
        quotaView.bounds = NSRect(origin: .zero, size: basePanelSize)
        quotaView.needsDisplay = true
        panel.invalidateCursorRects(for: quotaView)
        if shouldPresentPanel(
            codexDesktopRunning: true,
            hiddenByUser: isPanelHiddenByUser,
            hasPetLocation: true
        ), !panel.isVisible {
            panel.orderFrontRegardless()
        }
        healthWriter.write(
            status: "following-pet",
            panelVisible: true,
            locationSource: pet.source,
            gap: placement.actualGap,
            centerError: placement.centerError,
            panelScale: currentPanelScale,
            panelSize: currentPanelSize
        )
    }

    private func refreshQuota() {
        guard !isRefreshing else { return }
        isRefreshing = true
        if quotaView.rows.isEmpty {
            quotaView.errorText = nil
            quotaView.statusText = "正在读取额度…"
        } else {
            quotaView.statusText = "正在更新…"
        }

        quotaClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .success(let response):
                    let rows = Self.makeRows(from: response)
                    self.quotaView.rows = rows
                    self.quotaView.errorText = nil
                    self.quotaView.statusText = "\(Self.timeFormatter.string(from: Date())) 更新 · 5分钟"
                case .failure(let error):
                    self.quotaView.errorText = error.localizedDescription
                    self.quotaView.statusText = "5 分钟后自动重试"
                }
            }
        }
    }

    private func refreshTaskProgress() {
        guard !isRefreshingTaskProgress else { return }
        isRefreshingTaskProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let snapshot = self.taskProgressReader.read()
            DispatchQueue.main.async {
                self.isRefreshingTaskProgress = false
                self.quotaView.taskProgress = snapshot
                let nextBaseSize = panelSizeForTaskRows(snapshot.rowCount)
                if nextBaseSize != self.currentBasePanelSize {
                    self.currentBasePanelSize = nextBaseSize
                    self.followPet()
                }
            }
        }
    }

    private func refreshBTCPrice() {
        guard !isRefreshingBTCPrice else { return }
        isRefreshingBTCPrice = true

        btcPriceClient.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshingBTCPrice = false
                switch result {
                case .success(let price):
                    if let previousPrice = self.lastBTCPrice {
                        self.quotaView.btcPriceDirection = price > previousPrice ? 1 : (price < previousPrice ? -1 : 0)
                    } else {
                        self.quotaView.btcPriceDirection = 0
                    }
                    self.lastBTCPrice = price
                    self.quotaView.btcPrice = price
                    self.quotaView.btcStatusText = "5秒"
                case .failure:
                    self.quotaView.btcStatusText = self.quotaView.btcPrice == nil ? "重试中" : "暂离线"
                }
            }
        }
    }

    private static func makeRows(from response: RateLimitsResult) -> [QuotaRow] {
        let snapshot = codexSnapshot(from: response)

        if let window = snapshot.primary {
            return [QuotaRow(
                name: "Codex",
                remainingPercent: max(0, 100 - window.usedPercent),
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )]
        }

        if let individual = snapshot.individualLimit {
            return [QuotaRow(
                name: "Codex",
                remainingPercent: individual.remainingPercent,
                resetsAt: Date(timeIntervalSince1970: TimeInterval(individual.resetsAt))
            )]
        }

        return [QuotaRow(name: "Codex", remainingPercent: 0, resetsAt: nil)]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

}

private func printQuotaOnce() -> Never {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 1
    CodexQuotaClient().fetch { result in
        switch result {
        case .success(let response):
            let snapshot = codexSnapshot(from: response)
            let remaining = snapshot.primary.map { max(0, 100 - $0.usedPercent) }
                ?? snapshot.individualLimit?.remainingPercent
                ?? 0
            print("codex: remaining=\(remaining)%")
            exitCode = 0
        case .failure(let error):
            fputs("\(error.localizedDescription)\n", stderr)
        }
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 20) == .timedOut {
        fputs("读取额度超时\n", stderr)
    }
    exit(exitCode)
}

private func printMarketPriceOnce(symbol: String, label: String) -> Never {
    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 1
    MarketPriceClient(symbol: symbol).fetch { result in
        switch result {
        case .success(let price):
            print(String(format: "\(label): %.2f", price))
            exitCode = 0
        case .failure(let error):
            fputs("\(error.localizedDescription)\n", stderr)
        }
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + 12) == .timedOut {
        fputs("读取 \(label) 价格超时\n", stderr)
    }
    exit(exitCode)
}

private func printPanelConfiguration() -> Never {
    print(
        "panel-config: version=\(panelVersion) "
            + "edition=\(panelEdition) petID=\(bluePetID) "
            + "marketPricesEnabled=\(marketPricesEnabled) "
            + "width=\(Int(expandedPanelSize.width)) "
            + "height=\(Int(expandedPanelSize.height))"
    )
    exit(0)
}

private func printTaskProgressOnce() -> Never {
    let snapshot = CodexTaskProgressReader().read()
    let details = snapshot.items.enumerated().map { index, item in
        "\(index + 1):\(item.title)[\(item.kind.rawValue)]"
    }.joined(separator: " | ")
    print("task-progress: count=\(snapshot.items.count) \(details)")
    exit(0)
}

private func printPanelPlacementOnce(savedStateOnly: Bool = false) -> Never {
    let locator = PetWindowLocator()
    let result = savedStateOnly ? locator.locateSavedState() : locator.locate()
    guard let location = result else {
        fputs("没有找到已打开的卜卜窗口或已保存的位置\n", stderr)
        exit(1)
    }

    let livePanelSize = scaledPanelSize(expandedPanelSize, scale: location.panelScale)
    let placement = panelPlacement(
        petVisibleRect: location.visibleRect,
        panelSize: livePanelSize,
        panelScale: location.panelScale,
        screenVisibleFrame: location.screen.visibleFrame
    )
    print(
        "panel-location: source=\(location.source) "
            + "overlayX=\(Int(location.overlayRect.minX.rounded())) "
            + "overlayY=\(Int(location.overlayRect.minY.rounded())) "
            + "petCenterX=\(Int(location.visibleRect.midX.rounded())) "
            + "petTop=\(Int(location.visibleRect.maxY.rounded())) "
            + "panelX=\(Int(placement.origin.x)) "
            + "panelY=\(Int(placement.origin.y)) "
            + "panelScale=\(String(format: "%.3f", location.panelScale)) "
            + "panelWidth=\(String(format: "%.1f", livePanelSize.width)) "
            + "panelHeight=\(String(format: "%.1f", livePanelSize.height)) "
            + "gap=\(String(format: "%.1f", placement.actualGap)) "
            + "centerError=\(String(format: "%.1f", placement.centerError))"
    )
    exit(0)
}

private func runPlacementSelfTest() -> Never {
    struct TestCase {
        let name: String
        let petRect: NSRect
        let panelSize: NSSize
        let panelScale: CGFloat
        let screenRect: NSRect
    }

    let cases = [
        TestCase(
            name: "built-in-display",
            petRect: NSRect(x: 1_110, y: 318, width: 163, height: 170),
            panelSize: expandedPanelSize,
            panelScale: 1,
            screenRect: NSRect(x: 0, y: 0, width: 1_512, height: 982)
        ),
        TestCase(
            name: "external-negative-origin",
            petRect: NSRect(x: -554, y: 500, width: 163, height: 170),
            panelSize: expandedPanelSize,
            panelScale: 1,
            screenRect: NSRect(x: -1_920, y: -98, width: 1_920, height: 1_080)
        ),
        TestCase(
            name: "scaled-pet",
            petRect: NSRect(x: 420, y: 260, width: 203.75, height: 212.5),
            panelSize: scaledPanelSize(expandedPanelSize, scale: 1.25),
            panelScale: 1.25,
            screenRect: NSRect(x: 0, y: 0, width: 1_920, height: 1_080)
        ),
        TestCase(
            name: "three-quarter-scale",
            petRect: NSRect(x: 280, y: 210, width: 122.25, height: 127.5),
            panelSize: scaledPanelSize(expandedPanelSize, scale: 0.75),
            panelScale: 0.75,
            screenRect: NSRect(x: 0, y: 0, width: 1_280, height: 720)
        ),
        TestCase(
            name: "left-screen-edge",
            petRect: NSRect(x: 8, y: 180, width: 81.5, height: 85),
            panelSize: scaledPanelSize(expandedPanelSize, scale: 0.5),
            panelScale: 0.5,
            screenRect: NSRect(x: 0, y: 0, width: 1_280, height: 720)
        ),
        TestCase(
            name: "right-screen-edge",
            petRect: NSRect(x: 1_050, y: 180, width: 163, height: 170),
            panelSize: scaledPanelSize(expandedPanelSize, scale: 2),
            panelScale: 2,
            screenRect: NSRect(x: 0, y: 0, width: 1_280, height: 720)
        ),
    ]

    for test in cases {
        let placement = panelPlacement(
            petVisibleRect: test.petRect,
            panelSize: test.panelSize,
            panelScale: test.panelScale,
            screenVisibleFrame: test.screenRect
        )
        guard abs(placement.actualGap - panelPetGap) <= 0.01 else {
            fputs("\(test.name): gap=\(placement.actualGap), expected=\(panelPetGap)\n", stderr)
            exit(1)
        }
        let baseSize = expandedPanelSize
        guard abs(test.panelSize.width - baseSize.width * test.panelScale) <= 0.01,
              abs(test.panelSize.height - baseSize.height * test.panelScale) <= 0.01
        else {
            fputs("\(test.name): panel did not scale proportionally\n", stderr)
            exit(1)
        }
        guard abs(placement.centerError) <= 0.01 else {
            fputs("\(test.name): centerError=\(placement.centerError)\n", stderr)
            exit(1)
        }
    }

    guard PetWindowLocator().scalingSelfTest() else {
        fputs("mascot scaling self-test failed\n", stderr)
        exit(1)
    }

    print("placement-self-test: 6/6 passed; mascot-scaling=6/6; visual-scaling=6/6; panel-scaling=6/6; gap=14.0; centerError=0.0")
    exit(0)
}

private func runLifecycleSelfTest() -> Never {
    struct DesktopCase {
        let bundleIdentifier: String?
        let localizedName: String?
        let bundlePath: String?
        let activationPolicy: NSApplication.ActivationPolicy
        let expected: Bool
    }

    let desktopCases = [
        DesktopCase(
            bundleIdentifier: "com.openai.codex",
            localizedName: "ChatGPT",
            bundlePath: "/Applications/ChatGPT.app",
            activationPolicy: .regular,
            expected: true
        ),
        DesktopCase(
            bundleIdentifier: "com.openai.chatgpt",
            localizedName: "ChatGPT",
            bundlePath: "/Applications/ChatGPT.app",
            activationPolicy: .regular,
            expected: true
        ),
        DesktopCase(
            bundleIdentifier: nil,
            localizedName: "Codex",
            bundlePath: "/Applications/Codex.app",
            activationPolicy: .regular,
            expected: true
        ),
        DesktopCase(
            bundleIdentifier: "io.github.mayday-materials.bubu-quota-panel",
            localizedName: "卜卜额度面板",
            bundlePath: "/Applications/卜卜额度面板.app",
            activationPolicy: .accessory,
            expected: false
        ),
        DesktopCase(
            bundleIdentifier: nil,
            localizedName: "codex",
            bundlePath: "/usr/local/bin/codex",
            activationPolicy: .prohibited,
            expected: false
        ),
    ]

    for (index, test) in desktopCases.enumerated() {
        let actual = isCodexDesktopApplication(
            bundleIdentifier: test.bundleIdentifier,
            localizedName: test.localizedName,
            bundleURL: test.bundlePath.map { URL(fileURLWithPath: $0) },
            activationPolicy: test.activationPolicy
        )
        guard actual == test.expected else {
            fputs("desktop lifecycle case \(index + 1) failed\n", stderr)
            exit(1)
        }
    }

    let visibilityCases = [
        (true, false, true, true),
        (false, false, true, false),
        (true, true, true, false),
        (true, false, false, false),
    ]
    for (index, test) in visibilityCases.enumerated() {
        let actual = shouldPresentPanel(
            codexDesktopRunning: test.0,
            hiddenByUser: test.1,
            hasPetLocation: test.2
        )
        guard actual == test.3 else {
            fputs("panel visibility case \(index + 1) failed\n", stderr)
            exit(1)
        }
    }

    let petRect = NSRect(x: 400, y: 260, width: 163, height: 177)
    let doubleClickCases = [
        shouldTogglePanelForPetDoubleClick(
            clickCount: 2,
            clickLocation: NSPoint(x: petRect.midX, y: petRect.midY),
            petVisibleRect: petRect
        ),
        !shouldTogglePanelForPetDoubleClick(
            clickCount: 1,
            clickLocation: NSPoint(x: petRect.midX, y: petRect.midY),
            petVisibleRect: petRect
        ),
        !shouldTogglePanelForPetDoubleClick(
            clickCount: 2,
            clickLocation: NSPoint(x: petRect.maxX + 1, y: petRect.midY),
            petVisibleRect: petRect
        ),
    ]
    guard doubleClickCases.allSatisfy({ $0 }) else {
        fputs("pet double-click hit testing failed\n", stderr)
        exit(1)
    }

    print("lifecycle-self-test: desktop-app=5/5 visibility=4/4 pet-double-click=3/3 hidden-window=orderOut status-item=restore")
    exit(0)
}

private func runTaskProgressSelfTest() -> Never {
    let now = Date()
    let started = #"{"type":"event_msg","payload":{"type":"task_started"}}"#
    let completed = #"{"type":"event_msg","payload":{"type":"task_complete"}}"#
    let failed = #"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#
    let request = #"{"type":"response_item","payload":{"type":"function_call","name":"request_user_input","call_id":"call-1"}}"#
    let response = #"{"type":"response_item","payload":{"type":"function_call_output","call_id":"call-1"}}"#
    let cases: [(String, [String], Date, TaskProgressKind)] = [
        ("running", [started], now, .running),
        ("waiting", [started, request], now, .waitingForInput),
        ("resumed", [started, request, response], now, .running),
        ("completed", [started, completed], now, .completed),
        ("failed", [started, failed], now, .failed),
        ("fresh-tail-fallback", [], now, .running),
        ("idle", [], now.addingTimeInterval(-31 * 60), .idle),
    ]

    for test in cases {
        let result = CodexTaskProgressReader.parse(
            lines: test.1,
            modificationDate: test.2,
            now: now
        )
        guard result.kind == test.3 else {
            fputs("task progress case \(test.0) failed: \(result.kind.rawValue)\n", stderr)
            exit(1)
        }
    }

    let titledUserMessage = ##"{"type":"event_msg","payload":{"type":"user_message","message":"# Files mentioned by the user:\n/a.png\n## My request for Codex:\n列出具体任务名称"}}"##
    let titled = CodexTaskProgressReader.parse(
        lines: [titledUserMessage, started],
        modificationDate: now,
        now: now
    )
    guard titled.items.first?.title == "列出具体任务名称" else {
        fputs("task title extraction failed\n", stderr)
        exit(1)
    }

    let indexedThreadID = "12345678-1234-4abc-8def-1234567890ab"
    let indexedRollout = URL(fileURLWithPath:
        "/tmp/rollout-2026-07-16T16-52-47-\(indexedThreadID).jsonl"
    )
    let indexedTitle = CodexTaskProgressReader.resolvedTitle(
        for: indexedRollout,
        indexedTitles: [indexedThreadID: "正式任务名称"],
        fallback: "Codex 任务"
    )
    guard indexedTitle == "正式任务名称" else {
        fputs("task index title mapping failed\n", stderr)
        exit(1)
    }

    let unreadState = CodexTaskProgressReader.UnreadThreadState(
        ids: [indexedThreadID],
        isAvailable: true
    )
    let readState = CodexTaskProgressReader.UnreadThreadState(
        ids: [],
        isAvailable: true
    )
    let unavailableState = CodexTaskProgressReader.UnreadThreadState(
        ids: [],
        isAvailable: false
    )
    let completedVisibilityCases = [
        CodexTaskProgressReader.shouldDisplay(
            kind: .completed,
            threadID: indexedThreadID,
            modificationDate: now.addingTimeInterval(-3600),
            now: now,
            unreadState: unreadState
        ),
        !CodexTaskProgressReader.shouldDisplay(
            kind: .completed,
            threadID: indexedThreadID,
            modificationDate: now,
            now: now,
            unreadState: readState
        ),
        CodexTaskProgressReader.shouldDisplay(
            kind: .completed,
            threadID: indexedThreadID,
            modificationDate: now,
            now: now,
            unreadState: unavailableState,
            fallbackVisibility: 120
        ),
        CodexTaskProgressReader.shouldDisplay(
            kind: .failed,
            threadID: indexedThreadID,
            modificationDate: now.addingTimeInterval(-3600),
            now: now,
            unreadState: unreadState
        ),
        !CodexTaskProgressReader.shouldDisplay(
            kind: .failed,
            threadID: indexedThreadID,
            modificationDate: now,
            now: now,
            unreadState: readState
        ),
        !CodexTaskProgressReader.shouldDisplay(
            kind: .completed,
            threadID: indexedThreadID,
            modificationDate: now.addingTimeInterval(-180),
            now: now,
            unreadState: unavailableState,
            fallbackVisibility: 120
        ),
    ]
    guard completedVisibilityCases.allSatisfy({ $0 }),
          CodexTaskProgressReader.shouldDisplay(
            kind: .running,
            threadID: indexedThreadID,
            modificationDate: now,
            now: now,
            unreadState: readState
          )
    else {
        fputs("completed task filtering failed\n", stderr)
        exit(1)
    }

    let topLevelMetadata = #"{"type":"session_meta","payload":{"thread_source":"user","source":{"cli":{}}}}"#
    let subagentMetadata = #"{"type":"session_meta","payload":{"thread_source":"subagent","source":{"subagent":{"thread_spawn":{}}}}}"#
    let automationMetadata = #"{"type":"session_meta","payload":{"thread_source":"automation","source":"vscode"}}"#
    let sourceOnlySubagentMetadata = #"{"type":"session_meta","payload":{"source":{"subagent":{"thread_spawn":{}}}}}"#
    let rolloutVisibilityCases = [
        CodexTaskProgressReader.isUserVisibleSessionMetadata(line: topLevelMetadata),
        !CodexTaskProgressReader.isUserVisibleSessionMetadata(line: subagentMetadata),
        !CodexTaskProgressReader.isUserVisibleSessionMetadata(line: automationMetadata),
        !CodexTaskProgressReader.isUserVisibleSessionMetadata(line: sourceOnlySubagentMetadata),
        CodexTaskProgressReader.isUserVisibleSessionMetadata(line: started),
    ]
    guard rolloutVisibilityCases.allSatisfy({ $0 }) else {
        fputs("task non-user session filtering failed\n", stderr)
        exit(1)
    }

    let truncated = TaskProgressSnapshot.displaying((0..<7).map { index in
        TaskProgressItem(title: "任务 \(index + 1)", kind: .running, startedAt: now)
    })
    guard truncated.items.count == maximumVisibleTaskRows,
          truncated.items.last?.title == "任务 5"
    else {
        fputs("task list truncation failed\n", stderr)
        exit(1)
    }

    let completedPresentation = TaskProgressSnapshot.displaying([
        TaskProgressItem(
            title: "AI 观点运营台 · Codex Chrome 单条发布与回复",
            kind: .completed,
            startedAt: now,
            statusOverride: "最新"
        ),
        TaskProgressItem(
            title: "  AI 观点运营台 · Codex Chrome 单条发布与回复  ",
            kind: .completed,
            startedAt: now.addingTimeInterval(-300),
            statusOverride: "旧记录"
        ),
        TaskProgressItem(title: "相同标题的实时任务", kind: .running, startedAt: now),
        TaskProgressItem(title: "相同标题的实时任务", kind: .running, startedAt: now),
    ])
    guard completedPresentation.items.count == 2,
          completedPresentation.items[0].kind == .completed,
          completedPresentation.items[0].statusText == "最新",
          completedPresentation.items[1].kind == .running,
          completedPresentation.items[1].title == "相同标题的实时任务"
    else {
        fputs("task presentation deduplication failed\n", stderr)
        exit(1)
    }

    let taskIconNames = [
        "task-running-icon.png",
        "task-waiting-icon.png",
        "task-completed-icon.png",
        "task-failed-icon.png",
    ]
    guard let resourceURL = Bundle.main.resourceURL,
          taskIconNames.allSatisfy({
              NSImage(contentsOf: resourceURL.appendingPathComponent($0)) != nil
          })
    else {
        fputs("task status icon assets failed\n", stderr)
        exit(1)
    }

    print("task-progress-self-test: lifecycle=7/7; title=1/1; index=1/1; completed-unread=pass; read-state=6/6; top-level-filter=5/5; list=5-truncated; task-dedup=pass; status-icons=4/4")
    exit(0)
}

private func runBlueEditionSelfTest() -> Never {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bubu-blue-edition-\(UUID().uuidString)", isDirectory: true)
    let config = directory.appendingPathComponent("config.toml")
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let initial = """
        selected-avatar-id = "codex"
        [general]
        model = "gpt"
        [desktop]
        avatar-overlay-mascot-width-px = 163
        selected-avatar-id = "custom:old-pet"
        [features]
        test = true
        """
        try initial.data(using: .utf8)?.write(to: config, options: .atomic)
        let store = BluePetSelectionStore(configURL: config)
        guard store.selectBluePet(), store.bluePetIsSelected() else {
            throw NSError(domain: "BubuBlueEditionSelfTest", code: 1)
        }
        let blueText = try String(contentsOf: config, encoding: .utf8)
        guard blueText.components(separatedBy: "selected-avatar-id").count - 1 == 1,
              blueText.contains("selected-avatar-id = \"custom:bubu-office\"")
        else {
            throw NSError(domain: "BubuBlueEditionSelfTest", code: 2)
        }
        let missingDesktop = BluePetSelectionStore.updatingDesktopSelection(
            in: "[general]\nmodel = \"gpt\"\n",
            avatarID: bluePetAvatarID
        )
        guard missingDesktop.contains("[desktop]\nselected-avatar-id = \"custom:bubu-office\"") else {
            throw NSError(domain: "BubuBlueEditionSelfTest", code: 3)
        }
    } catch {
        fputs("blue edition self-test failed: \(error)\n", stderr)
        exit(1)
    }

    print("blue-edition-self-test: edition=blue-bubu pet=bubu-office persistence=pass duplicate-key=pass")
    exit(0)
}

private func renderPreviewOnce(to outputPath: String) -> Never {
    _ = NSApplication.shared
    var previewTaskTemplates = [
        TaskProgressItem(title: "修复 Windows 宠物替换", kind: .running, startedAt: Date()),
        TaskProgressItem(title: "整理 macOS 分享包", kind: .waitingForInput, startedAt: Date()),
        TaskProgressItem(title: "检查运行结果", kind: .running, startedAt: Date()),
        TaskProgressItem(title: "检查额度面板比例", kind: .running, startedAt: Date()),
        TaskProgressItem(title: "生成发布包", kind: .waitingForInput, startedAt: Date()),
    ]
    if CommandLine.arguments.contains("--preview-completed") {
        previewTaskTemplates[0] = TaskProgressItem(
            title: "检查完成状态图标",
            kind: .completed,
            startedAt: Date()
        )
    } else if CommandLine.arguments.contains("--preview-waiting") {
        previewTaskTemplates[0] = TaskProgressItem(
            title: "等待用户确认",
            kind: .waitingForInput,
            startedAt: Date()
        )
    } else if CommandLine.arguments.contains("--preview-failed") {
        previewTaskTemplates[0] = TaskProgressItem(
            title: "检查失败状态图标",
            kind: .failed,
            startedAt: Date()
        )
    }
    let countFlag = "--preview-task-count"
    let requestedPreviewCount: Int
    if let flagIndex = CommandLine.arguments.firstIndex(of: countFlag),
       CommandLine.arguments.indices.contains(flagIndex + 1),
       let parsedCount = Int(CommandLine.arguments[flagIndex + 1]) {
        requestedPreviewCount = parsedCount
    } else {
        requestedPreviewCount = 3
    }
    let previewCount = max(1, min(maximumVisibleTaskRows, requestedPreviewCount))
    let previewTasks = TaskProgressSnapshot(
        items: Array(previewTaskTemplates.prefix(previewCount))
    )
    let previewPanelSize = panelSizeForTaskRows(previewTasks.rowCount)
    let view = QuotaPanelView(frame: NSRect(origin: .zero, size: previewPanelSize))
    view.pointerSide = .bottom
    view.rows = [QuotaRow(
        name: "Codex",
        remainingPercent: 94,
        resetsAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())
    )]
    view.statusText = "12:43 更新 · 5分钟"
    view.taskProgress = previewTasks
    view.btcPrice = 64_169.97
    view.btcPriceDirection = 1
    view.btcStatusText = "5秒"
    view.layoutSubtreeIfNeeded()

    let scale: CGFloat = 2
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(previewPanelSize.width * scale),
        pixelsHigh: Int(previewPanelSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("无法创建预览画布\n", stderr)
        exit(1)
    }
    bitmap.size = previewPanelSize

    view.cacheDisplay(in: view.bounds, to: bitmap)

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("无法编码预览图片\n", stderr)
        exit(1)
    }

    do {
        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print(outputPath)
        exit(0)
    } catch {
        fputs("写入预览失败：\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--print-quota") {
    printQuotaOnce()
}

if CommandLine.arguments.contains("--print-btc") {
    printMarketPriceOnce(symbol: "BTCUSDT", label: "BTC/USDT")
}

if CommandLine.arguments.contains("--print-panel-location") {
    printPanelPlacementOnce()
}

if CommandLine.arguments.contains("--print-saved-panel-location") {
    printPanelPlacementOnce(savedStateOnly: true)
}

if CommandLine.arguments.contains("--self-test-placement") {
    runPlacementSelfTest()
}

if CommandLine.arguments.contains("--self-test-lifecycle") {
    runLifecycleSelfTest()
}

if CommandLine.arguments.contains("--self-test-task-progress") {
    runTaskProgressSelfTest()
}

if CommandLine.arguments.contains("--self-test-blue-edition") {
    runBlueEditionSelfTest()
}

if CommandLine.arguments.contains("--print-panel-config") {
    printPanelConfiguration()
}

if CommandLine.arguments.contains("--print-task-progress") {
    printTaskProgressOnce()
}

if let previewFlag = CommandLine.arguments.firstIndex(of: "--render-preview"),
   CommandLine.arguments.indices.contains(previewFlag + 1)
{
    renderPreviewOnce(to: CommandLine.arguments[previewFlag + 1])
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
