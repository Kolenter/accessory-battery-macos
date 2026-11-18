import AppKit
import CoreAudio
import IOKit
import IOKit.ps
import QuartzCore
import SwiftUI

private let chargingCaseSymbol = "airpods.chargingcase"

private enum IconHighlight {
    case connected, lowBattery, charging

    var opacity: CGFloat {
        switch self {
        case .connected: 0.47
        case .lowBattery: 0.8
        case .charging: 0.85
        }
    }

    var color: CGColor {
        switch self {
        case .connected: NSColor(srgbRed: 0.24, green: 0.92, blue: 0.44, alpha: 1).cgColor
        case .lowBattery: NSColor(srgbRed: 0.98, green: 0.18, blue: 0.23, alpha: 1).cgColor
        case .charging: NSColor(srgbRed: 0.15, green: 0.55, blue: 1, alpha: 1).cgColor
        }
    }
}

private struct Indicator: Identifiable {
    let id: String
    let name: String
    var detail: String?
    let symbol: String
    let percent: Int
    let isConnected: Bool
    var isCharging = false

    var title: String {
        let status = isCharging ? " · Заряжается" : ""
        return "\(name) · \(detail ?? "\(percent)%")\(status)"
    }

    var highlight: IconHighlight? {
        if isCharging { return .charging }
        if percent < 8 { return .lowBattery }
        return isConnected ? .connected : nil
    }
}

private enum Accessory: Int, Sendable {
    case keyboard, mouse, trackpad, headphones, controller, speaker, other

    init(name: String, type: String = "") {
        let description = "\(type) \(name)".lowercased()
        if ["trackpad", "touchpad", "трекпад"].contains(where: description.contains) {
            self = .trackpad
        } else if ["keyboard", "клавиатур"].contains(where: description.contains) {
            self = .keyboard
        } else if ["mouse", "мышь"].contains(where: description.contains) {
            self = .mouse
        } else if ["headphone", "headset", "hands-free", "earbud", "airpod", "наушник"].contains(where: description.contains) {
            self = .headphones
        } else if ["gamepad", "game controller", "joystick", "dualshock", "dualsense"].contains(where: description.contains) {
            self = .controller
        } else if ["speaker", "loudspeaker", "колонка"].contains(where: description.contains) {
            self = .speaker
        } else {
            self = .other
        }
    }

    var symbol: String {
        switch self {
        case .keyboard: "keyboard"
        case .mouse: "magicmouse"
        case .trackpad: "rectangle"
        case .headphones: "headphones"
        case .controller: "gamecontroller"
        case .speaker: "hifispeaker"
        case .other: "battery.100"
        }
    }
}

private struct Reading: Equatable, Sendable {
    let name: String
    var accessory: Accessory
    var main: Int?
    var left: Int?
    var right: Int?
    var chargingCase: Int?
    var identifier: String?
    var chargingCaseName: String?
    var isConnected = false
    var isCharging = false
    var caseIsCharging = false

    var primaryPercent: Int? { [left, right].compactMap { $0 }.min() ?? main }
    var hasCharge: Bool { primaryPercent != nil || chargingCase != nil }

    private var primaryLevelText: String {
        var details: [String] = []
        if let left { details.append("Левый \(left)%") }
        if let right { details.append("Правый \(right)%") }
        if details.isEmpty, let main { details.append("\(main)%") }
        return details.joined(separator: " · ")
    }

    var levelText: String {
        var details = primaryLevelText.isEmpty ? [] : [primaryLevelText]
        if let chargingCase { details.append("Кейс \(chargingCase)%") }
        return details.joined(separator: " · ")
    }

    var title: String { "\(name) · \(levelText)" }

    var indicators: [Indicator] {
        let key = identifier.map { "id:\($0)" } ?? "name:\(name.lowercased())"
        var indicators: [Indicator] = []
        if let primaryPercent {
            indicators.append(Indicator(
                id: "device:\(key)", name: name, detail: left != nil || right != nil ? primaryLevelText : nil,
                symbol: accessory.symbol, percent: primaryPercent, isConnected: isConnected,
                isCharging: isCharging
            ))
        }
        if let chargingCase {
            let caseName = chargingCaseName ?? "Футляр «\(name)»"
            indicators.append(Indicator(
                id: "case:\(key)", name: caseName,
                symbol: chargingCaseSymbol, percent: chargingCase, isConnected: isConnected,
                isCharging: caseIsCharging
            ))
        }
        return indicators
    }
}

private func normalizedIdentifier(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    let identifier = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return identifier.isEmpty ? nil : identifier
}

private func batteryPercent(_ value: Any?) -> Int? {
    let number: Int?
    if let text = value as? String {
        number = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "%").union(.whitespacesAndNewlines)))
    } else if let numeric = value as? NSNumber, CFGetTypeID(numeric) != CFBooleanGetTypeID() {
        number = numeric as? Int
    } else {
        number = nil
    }
    guard let number, (0...100).contains(number) else { return nil }
    return number
}

private func readHIDBatteries() -> [Reading] {
    let matching = [kIOPropertyExistsMatchKey: "BatteryPercent"] as CFDictionary
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return []
    }
    defer { IOObjectRelease(iterator) }

    var readings: [String: Reading] = [:]
    while case let service = IOIteratorNext(iterator), service != 0 {
        defer { IOObjectRelease(service) }
        let builtIn = IORegistryEntryCreateCFProperty(service, "Built-In" as CFString, nil, 0)?.takeRetainedValue()
        let product = IORegistryEntryCreateCFProperty(service, "Product" as CFString, nil, 0)?.takeRetainedValue()
        let charge = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, nil, 0)?.takeRetainedValue()
        guard
            builtIn as? Bool != true,
            let name = product as? String, !name.isEmpty,
            let level = batteryPercent(charge)
        else {
            continue
        }
        let address = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, nil, 0)?.takeRetainedValue()
        let identifier = normalizedIdentifier(address)
        readings[identifier ?? name] = Reading(
            name: name, accessory: Accessory(name: name), main: level, identifier: identifier,
            isConnected: true
        )
    }
    return Array(readings.values)
}

private func systemReport(_ executable: String, _ arguments: [String]) -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return Data()
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : Data()
}

private func powerSourcePercent(_ source: [String: Any]?) -> Int? {
    guard let source, (source[kIOPSIsPresentKey] as? NSNumber)?.boolValue != false,
          let current = source["Current Capacity"] as? Int else { return nil }
    if let maximum = source["Max Capacity"] as? Int, maximum > 0 {
        guard (0...maximum).contains(current) else { return nil }
        return Int((100 * Double(current) / Double(maximum)).rounded())
    }
    return batteryPercent(current)
}

private func powerSourceIsCharging(_ source: [String: Any]?) -> Bool {
    guard let source, (source[kIOPSIsChargingKey] as? NSNumber)?.boolValue == true,
          (source[kIOPSIsChargedKey] as? NSNumber)?.boolValue != true,
          let percent = powerSourcePercent(source) else { return false }
    return percent < 100
}

private func isAudioCase(_ source: [String: Any]) -> Bool {
    source["Part Identifier"] as? String == "Case" ||
        source["Accessory Category"] as? String == "Audio Battery Case"
}

private func powerSourceReadings(_ report: Data) -> [Reading] {
    // pmset prints one XML property list per power source.
    let documents = String(decoding: report, as: UTF8.self).components(separatedBy: "</plist>")
    let sources: [[String: Any]] = documents.compactMap { document in
        guard let start = document.range(of: "<?xml") else { return nil }
        let data = Data((document[start.lowerBound...] + "</plist>").utf8)
        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let source = plist as? [String: Any],
              source["Type"] as? String != kIOPSInternalBatteryType,
              (source[kIOPSIsPresentKey] as? NSNumber)?.boolValue != false else { return nil }
        return source
    }

    // The headphones and case share a group identifier even if their names differ.
    let groups = Dictionary(grouping: sources.enumerated()) { index, source in
        if let group = source["Group Identifier"] as? String, !group.isEmpty {
            return "group:\(group)"
        }
        return "source:\(index)"
    }
    return groups.values.compactMap { group in
        let entries = group.map(\.element)
        let main = entries.first { $0["Part Identifier"] as? String == "Combined" }
            ?? entries.first {
                let part = $0["Part Identifier"] as? String
                return !isAudioCase($0) && part != "Left" && part != "Right"
            }
        let parts = entries + (main?["Combined Parts"] as? [[String: Any]] ?? [])
        let leftSource = parts.first { $0["Part Identifier"] as? String == "Left" }
        let rightSource = parts.first { $0["Part Identifier"] as? String == "Right" }
        let caseSource = parts.first(where: isAudioCase)
        let nameSource = main ?? entries.first(where: { !isAudioCase($0) }) ?? caseSource
        let name = (nameSource?["Name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || caseSource != nil else { return nil }

        let category = nameSource?["Accessory Category"] as? String ?? ""
        let identifier = normalizedIdentifier(nameSource?["Group Identifier"])
            ?? normalizedIdentifier(nameSource?["Accessory Identifier"])
        let caseName = (caseSource?["Name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let transport = nameSource?[kIOPSTransportTypeKey] as? String ?? ""
        let reading = Reading(
            name: name.isEmpty ? "Кейс наушников" : name,
            accessory: Accessory(name: name, type: category),
            main: powerSourcePercent(main),
            left: powerSourcePercent(leftSource),
            right: powerSourcePercent(rightSource),
            chargingCase: powerSourcePercent(caseSource),
            identifier: identifier,
            chargingCaseName: caseName.isEmpty ? (name.isEmpty ? "Футляр наушников" : nil) : caseName,
            isConnected: [kIOPSUSBTransportType, kIOPSSerialTransportType, kIOPSNetworkTransportType].contains(transport),
            isCharging: [main, leftSource, rightSource].contains(where: powerSourceIsCharging),
            caseIsCharging: powerSourceIsCharging(caseSource)
        )
        return reading.hasCharge ? reading : nil
    }
}

private func accessoryReadings(
    bluetoothReport: Data, powerReadings: [Reading], hidReadings: [Reading],
    connectedAudioNames: Set<String> = []
) -> [Reading] {
    let report = (try? JSONSerialization.jsonObject(with: bluetoothReport)) as? [String: Any]
    let controllers = report?["SPBluetoothDataType"] as? [[String: Any]] ?? []
    var remaining = powerReadings
    for hid in hidReadings {
        if let index = matchingReading(hid.name, identifier: hid.identifier, in: remaining) {
            remaining[index].main = hid.main
            remaining[index].identifier = remaining[index].identifier ?? hid.identifier
            remaining[index].isConnected = true
        } else {
            remaining.append(hid)
        }
    }

    var readings: [Reading] = []
    for controller in controllers {
        // Paired devices can retain old battery values in device_not_connected.
        let connected = controller["device_connected"] as? [[String: [String: Any]]] ?? []
        for device in connected {
            for (name, info) in device {
                let identifier = normalizedIdentifier(info["device_address"])
                let index = matchingReading(name, identifier: identifier, in: remaining)
                let kind = Accessory(name: name, type: info["device_minorType"] as? String ?? "")
                var reading = index.map { remaining.remove(at: $0) }
                    ?? Reading(name: name, accessory: kind, identifier: identifier)
                if reading.accessory == .other { reading.accessory = kind }
                reading.isConnected = true
                reading.identifier = reading.identifier ?? identifier
                reading.main = reading.main ?? batteryPercent(info["device_batteryLevelMain"])
                reading.left = reading.left ?? batteryPercent(info["device_batteryLevelLeft"])
                reading.right = reading.right ?? batteryPercent(info["device_batteryLevelRight"])
                reading.chargingCase = reading.chargingCase ?? batteryPercent(info["device_batteryLevelCase"])
                if reading.hasCharge { readings.append(reading) }
            }
        }
    }
    readings += remaining
    for index in readings.indices where connectedAudioNames.contains(readings[index].name.lowercased()) {
        readings[index].isConnected = true
    }
    return readings.sorted {
        if $0.accessory != $1.accessory { return $0.accessory.rawValue < $1.accessory.rawValue }
        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
}

private func matchingReading(_ name: String, identifier: String?, in readings: [Reading]) -> Int? {
    if let identifier, let index = readings.firstIndex(where: { $0.identifier == identifier }) {
        return index
    }
    let sameName = readings.indices.filter { readings[$0].name == name }
    return sameName.count == 1 ? sameName.first : nil
}

private func audioDeviceValue(_ selector: AudioObjectPropertySelector, device: AudioDeviceID) -> UInt32? {
    var property = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout.size(ofValue: value))
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
    return value
}

private func connectedBluetoothAudioNames() -> Set<String> {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var property = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var byteCount: UInt32 = 0
    let stride = MemoryLayout<AudioDeviceID>.stride
    guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &byteCount) == noErr,
          byteCount >= stride else { return [] }
    var devices = [AudioDeviceID](repeating: 0, count: Int(byteCount) / stride)
    let status = devices.withUnsafeMutableBytes {
        AudioObjectGetPropertyData(system, &property, 0, nil, &byteCount, $0.baseAddress!)
    }
    guard status == noErr else { return [] }

    property.mSelector = kAudioObjectPropertyName
    let bluetoothTransports = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE]
    var names: Set<String> = []
    for device in devices.prefix(Int(byteCount) / stride) {
        guard let transport = audioDeviceValue(kAudioDevicePropertyTransportType, device: device),
              bluetoothTransports.contains(transport),
              audioDeviceValue(kAudioDevicePropertyDeviceIsAlive, device: device) == 1 else { continue }
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: name))
        if AudioObjectGetPropertyData(device, &property, 0, nil, &size, &name) == noErr, let name {
            names.insert((name.takeRetainedValue() as String).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
    return names
}

private func readBatteries() -> [Reading] {
    let powerReport = systemReport("/usr/bin/pmset", ["-g", "accps", "-xml"])
    let bluetoothReport = systemReport("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-timeout", "5"])
    return accessoryReadings(
        bluetoothReport: bluetoothReport,
        powerReadings: powerSourceReadings(powerReport),
        hidReadings: readHIDBatteries(),
        connectedAudioNames: connectedBluetoothAudioNames()
    )
}

private typealias HighlightedSymbol = (image: NSImage, frame: NSRect, highlight: IconHighlight)

@MainActor
private final class IconHighlights: NSView {
    private(set) var symbols: [HighlightedSymbol] = []
    private var imageSize = NSSize.zero

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(symbols: [HighlightedSymbol], imageSize: NSSize = .zero) {
        self.symbols = symbols
        self.imageSize = imageSize
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !symbols.isEmpty, let context = NSGraphicsContext.current?.cgContext else { return }
        var center = NSPoint(x: bounds.midX, y: bounds.midY)
        if let button = superview as? NSStatusBarButton,
           let imageRect = button.cell?.imageRect(forBounds: button.bounds), !imageRect.isEmpty {
            center = convert(NSPoint(x: imageRect.midX, y: imageRect.midY), from: button)
        }

        let x = center.x - imageSize.width / 2
        let y = center.y - imageSize.height / 2
        // Tint the symbol silhouettes in a separate layer over the system-colored image.
        for symbol in symbols {
            let frame = symbol.frame.offsetBy(dx: x, dy: y)
            context.saveGState()
            context.clip(to: frame)
            context.setAlpha(symbol.highlight.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            symbol.image.draw(
                in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            context.setBlendMode(.sourceIn)
            context.setFillColor(symbol.highlight.color)
            context.fill(frame)
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }
}

@MainActor
private final class BatteryPanelState: ObservableObject {
    @Published var indicators: [Indicator] = []
    @Published var hidden: Set<String>

    init(hidden: Set<String>) {
        self.hidden = hidden
    }
}

private struct BatteryPanel: View {
    @ObservedObject var state: BatteryPanelState
    let setVisible: (String, Bool) -> Void
    let refresh: () -> Void
    let quit: () -> Void

    private static let width: CGFloat = 344
    private static let headerHeight: CGFloat = 56
    private static let rowHeight: CGFloat = 46
    private static let footerHeight: CGFloat = 40
    private static let listPadding: CGFloat = 5
    private static let emptyHeight: CGFloat = 68
    private static let visibleRows = 6
    private let inset: CGFloat = 15
    private let visibilityWidth: CGFloat = 43

    private static func listHeight(for count: Int) -> CGFloat {
        count == 0 ? emptyHeight : rowHeight * CGFloat(min(count, visibleRows)) + 2 * listPadding
    }

    static func size(for count: Int) -> CGSize {
        CGSize(width: width, height: headerHeight + listHeight(for: count) + footerHeight + 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            if state.indicators.isEmpty {
                Text("Нет аксессуаров с данными о заряде")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset)
                    .frame(height: Self.emptyHeight)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(state.indicators) { indicator in
                            row(for: indicator)
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, Self.listPadding)
                }
                .frame(height: Self.listHeight(for: state.indicators.count))
            }
            rule
            footer
        }
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.75")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text("Заряд аксессуаров")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !state.indicators.isEmpty {
                Text("В баре")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: visibilityWidth)
            }
        }
        .padding(.horizontal, inset)
        .frame(height: Self.headerHeight)
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
    }

    private func row(for indicator: Indicator) -> some View {
        let tint: Color = switch indicator.highlight {
        case .connected: Color(nsColor: .systemGreen)
        case .lowBattery: Color(nsColor: .systemRed)
        case .charging: Color(nsColor: .systemBlue)
        case nil: .secondary
        }

        return HStack(spacing: 10) {
            Image(systemName: indicator.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(indicator.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .help(indicator.name)
                if let detail = indicator.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if indicator.isCharging {
                    Label("Заряжается", systemImage: "bolt.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(nsColor: .systemBlue))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(indicator.percent)")
                        .font(.system(size: 15, weight: .semibold))
                    Text("%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(indicator.percent) процентов")
                if indicator.isCharging && indicator.detail != nil {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(nsColor: .systemBlue))
                        .accessibilityLabel("Заряжается")
                }
            }
            .frame(width: 42, alignment: .trailing)

            Toggle("Показывать \(indicator.name) в строке меню", isOn: Binding(
                get: { !state.hidden.contains(indicator.id) },
                set: { setVisible(indicator.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
            .frame(width: visibilityWidth)
            .help("Показывать в строке меню")
        }
        .frame(height: Self.rowHeight)
    }

    private var footer: some View {
        HStack {
            Button(action: refresh) {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            Spacer()
            Button("Выйти", action: quit)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, inset)
        .frame(height: Self.footerHeight)
    }
}

@MainActor
private final class BatteryMenu: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let panelState: BatteryPanelState
    private let iconHighlights = IconHighlights()
    private let chargingHighlights = IconHighlights()
    private let pulseKey = "chargingPulse"
    private let reader = DispatchQueue(label: "local.accessory-battery.reader", qos: .utility)
    private let preferences: UserDefaults
    private let hiddenKey = "HiddenIndicators"
    private var displayedReadings: [Reading]?
    private var isRefreshing = false
    private var timer: Timer?

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.panelState = BatteryPanelState(hidden: Set(preferences.stringArray(forKey: hiddenKey) ?? []))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        item.button?.imagePosition = .imageOnly
        item.button?.image = NSImage(systemSymbolName: Accessory.other.symbol, accessibilityDescription: "Заряд аксессуаров")
        chargingHighlights.wantsLayer = true
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            for highlights in [iconHighlights, chargingHighlights] {
                highlights.frame = button.bounds
                highlights.autoresizingMask = [.width, .height]
                button.addSubview(highlights)
            }
        }

        refresh()
        let timer = Timer(timeInterval: 15, target: self, selector: #selector(refresh(_:)), userInfo: nil, repeats: true)
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh(_:)), name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(updateChargingPulse(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        if popover.contentViewController == nil {
            let panel = BatteryPanel(
                state: panelState,
                setVisible: { [weak self] id, visible in self?.setIndicatorVisibility(id, visible: visible) },
                refresh: { [weak self] in self?.refresh() },
                quit: { NSApp.terminate(nil) }
            )
            popover.contentViewController = NSHostingController(rootView: panel)
        }
        popover.contentSize = BatteryPanel.size(for: panelState.indicators.count)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        refresh()
    }

    @objc private func refresh(_ sender: Any? = nil) {
        guard !isRefreshing else { return }
        isRefreshing = true
        reader.async { [weak self] in
            let readings = readBatteries()
            DispatchQueue.main.async { [weak self] in
                self?.isRefreshing = false
                self?.show(readings)
            }
        }
    }

    private func show(_ readings: [Reading]) {
        guard readings != displayedReadings else { return }
        displayedReadings = readings
        panelState.indicators = readings.flatMap(\.indicators)
        if popover.isShown {
            popover.contentSize = BatteryPanel.size(for: panelState.indicators.count)
        }
        updateStatusItem()
    }

    private func setIndicatorVisibility(_ id: String, visible: Bool) {
        if visible {
            panelState.hidden.remove(id)
        } else {
            panelState.hidden.insert(id)
        }
        preferences.set(panelState.hidden.sorted(), forKey: hiddenKey)
        updateStatusItem()
    }

    private func updateStatusItem() {
        let visible = panelState.indicators.filter { !panelState.hidden.contains($0.id) }
        let summary: String
        if visible.isEmpty {
            summary = panelState.indicators.isEmpty ? "Нет данных о заряде аксессуаров" : "Все показатели скрыты"
            item.button?.image = NSImage(systemSymbolName: Accessory.other.symbol, accessibilityDescription: summary)
            iconHighlights.update(symbols: [])
            chargingHighlights.update(symbols: [])
        } else {
            summary = visible.map(\.title).joined(separator: "\n")
            let status = makeStatusImage(visible)
            item.button?.image = status.image
            iconHighlights.update(
                symbols: status.highlightedSymbols.filter { $0.highlight != .charging },
                imageSize: status.image.size
            )
            chargingHighlights.update(
                symbols: status.highlightedSymbols.filter { $0.highlight == .charging },
                imageSize: status.image.size
            )
        }
        updateChargingPulse()
        item.button?.toolTip = summary
        item.button?.setAccessibilityLabel(summary)
    }

    @objc private func updateChargingPulse(_ notification: Notification? = nil) {
        guard let layer = chargingHighlights.layer else { return }
        guard !chargingHighlights.symbols.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layer.removeAnimation(forKey: pulseKey)
            return
        }
        guard layer.animation(forKey: pulseKey) == nil else { return }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.42
        pulse.toValue = 1
        pulse.duration = 1.15
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: pulseKey)
    }

    private func makeStatusImage(_ indicators: [Indicator]) -> (image: NSImage, highlightedSymbols: [HighlightedSymbol]) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let height: CGFloat = 19
        let iconGap: CGFloat = 4
        let deviceGap: CGFloat = 10
        var nextX: CGFloat = 0
        var highlightedSymbols: [HighlightedSymbol] = []
        let parts = indicators.map { indicator in
            let label = "\(indicator.percent)%"
            let text = NSAttributedString(string: label, attributes: attributes)
            let icon = (NSImage(systemSymbolName: indicator.symbol, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: Accessory.other.symbol, accessibilityDescription: nil))?
                .withSymbolConfiguration(configuration)
            let iconFrame = icon.map { icon in
                let size = icon.size
                let frame = NSRect(x: nextX, y: (height - size.height) / 2, width: size.width, height: size.height)
                nextX += ceil(size.width) + iconGap
                if let highlight = indicator.highlight {
                    highlightedSymbols.append((image: icon, frame: frame, highlight: highlight))
                }
                return frame
            }
            let size = text.size()
            let textOrigin = NSPoint(x: nextX, y: (height - size.height) / 2)
            nextX += ceil(size.width) + deviceGap
            return (text: text, textOrigin: textOrigin, icon: icon, iconFrame: iconFrame)
        }
        let width = nextX - deviceGap

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            for part in parts {
                if let icon = part.icon, let frame = part.iconFrame {
                    icon.draw(
                        in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
                    )
                }
                part.text.draw(at: part.textOrigin)
            }
            return true
        }
        image.isTemplate = true
        return (image, highlightedSymbols)
    }
}

if CommandLine.arguments.dropFirst() == ["--status"] {
    for reading in readBatteries() {
        print("\(reading.name): \(reading.levelText)")
    }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = BatteryMenu()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
