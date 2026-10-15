import SwiftUI

/// Emulator: Devices / Wireless / Tunnel sub-tabs over the real simulators, emulators and adb.
struct EmulatorScreen: View {
    var model: NotchModel

    var body: some View {
        let store = model.emulator
        let tab = model.emulatorTab
        VStack(spacing: 0) {
            SubNavRow(items: [SubTabItem("devices", "Devices", glyph: .phone), SubTabItem("wireless", "Wireless", glyph: .wifi),
                              SubTabItem("tunnel", "Tunnel", glyph: .arrows)],
                      selection: tab.rawValue,
                      onSelect: { model.setEmulatorTab(EmulatorTab(rawValue: $0) ?? .devices) }) {
                if tab == .tunnel { TunnelTargetButton(store: store) } else { EmulatorNavTrailing(store: store, tab: tab) }
            }
            .padding(.top, Geo.Chrome.subNavTop)

            Group {
                switch tab {
                case .devices: DevicesView(store: store)
                case .wireless: WirelessView(store: store)
                case .tunnel: TunnelView(store: store)
                }
            }
            .padding(.top, Geo.Chrome.contentTop)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .topTrailing) {
            if tab == .tunnel && store.targetMenuOpen && !store.targets.isEmpty { TargetMenu(store: store) }
        }
        .task(id: tab) { await store.refreshAll() }
    }
}

struct EmulatorNavTrailing: View {
    @Bindable var store: EmulatorStore
    var tab: EmulatorTab

    var body: some View {
        let wireless = tab == .wireless
        let selection = wireless ? store.wplatform : store.platform
        let count: (EmuPlatform) -> Int = { wireless ? ($0 == .ios ? store.wirelessIOS.count : store.wirelessAndroid.count) : store.devices($0).count }
        PlatformSegment(items: [SegmentItem(id: "android", label: "Android", count: count(.android)),
                                SegmentItem(id: "ios", label: "iOS", count: count(.ios))],
                        selection: selection.rawValue) { id in
            let p = EmuPlatform(rawValue: id) ?? .ios
            if wireless { store.wplatform = p } else { store.platform = p }
        }
        if wireless && store.wplatform == .android {
            IconButton(glyph: .power, label: "Restart adb server", size: 32, action: store.restartAdbServer).help("Restart adb server")
        }
        IconButton(glyph: .refresh, label: "Refresh", size: 32, action: store.refresh)
    }
}

/// Faint one-liner for an empty list (a tool is missing, or nothing is set up yet).
struct EmptyHint: View {
    var text: String
    @Environment(\.tokens) private var t

    var body: some View {
        Text(text).font(Typo.ui(12.5)).foregroundStyle(t.faint).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }
}

// MARK: Devices

struct DevicesView: View {
    var store: EmulatorStore

    var body: some View {
        let list = store.devices(store.platform)
        if list.isEmpty {
            EmptyHint(text: store.platform == .ios ? "No simulators found. Install one in Xcode › Settings › Platforms."
                                                   : "No emulators found. Create one in Android Studio › Device Manager, and make sure adb is installed.")
        } else {
            DockScroll {
                CardGrid(items: list, adaptive: true) { d in
                    DeviceCard(device: d, onPlay: { store.play(d) }, onStop: { store.stop(d) }, onCold: { store.play(d, cold: true) })
                }
            }
        }
    }
}

// MARK: Wireless

struct WirelessView: View {
    @Bindable var store: EmulatorStore

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            let list = store.wireless
            if list.isEmpty {
                EmptyHint(text: store.wplatform == .ios ? "No paired iPhones. Follow the steps on the right."
                                                        : "No wireless devices yet. Pair one with the form on the right.")
            } else {
                DockScroll {
                    CardGrid(items: list, adaptive: true, minWidth: Geo.CardMetrics.wirelessMinWidth) { d in
                        // devicectl cannot connect or disconnect, so a connected iPhone has nothing to do.
                        WirelessCard(device: d, canAct: !(store.wplatform == .ios && d.status == .connected),
                                     onAction: { store.wirelessAction(d) })
                    }
                }
            }
            Group {
                if store.wplatform == .android { PairCard(store: store) } else { CableFreeCard() }
            }
            .frame(width: 220)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct PairCard: View {
    @Bindable var store: EmulatorStore
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 18, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pair new device").font(Typo.display(20)).tracking(-0.5)
                Text("Developer options › Wireless debugging › Pair with code.")
                    .font(Typo.ui(12)).foregroundStyle(t.muted)
                    .lineSpacing(Typo.lineSpacing(size: 12, lineHeight: 1.45))
                    .fixedSize(horizontal: false, vertical: true)
                field("IP address & port", "192.168.1.24:37099", $store.pairAddress)
                field("Pairing code", "6-digit code", $store.pairCode, tracking: 2)
                Spacer(minLength: 0)
                DockButton(title: "Pair", glyph: nil, metrics: .form, tone: .tint, weight: .bold, action: store.pair)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>, tracking: CGFloat = 0) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Typo.ui(11, .semibold)).foregroundStyle(t.muted)
            DockTextField(text: text, placeholder: placeholder, font: Typo.mono(12.5), tracking: tracking)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(t.inset))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(t.border, lineWidth: 1))
        }
    }
}

struct CableFreeCard: View {
    @Environment(\.tokens) private var t
    private let steps = ["Plug the iPhone in once over USB.", "In Xcode › Devices, tick “Connect via network”.", "Unplug. It shows up here on the same Wi-Fi."]

    var body: some View {
        Card(radius: 18, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Go cable-free").font(Typo.display(20)).tracking(-0.5)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(i + 1). ").frame(width: 18, alignment: .trailing)
                            Text(steps[i]).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(Typo.ui(12))
                .foregroundStyle(t.text2)
                .lineSpacing(Typo.lineSpacing(size: 12, lineHeight: 1.45))
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: Tunnel

struct TunnelTargetButton: View {
    @Bindable var store: EmulatorStore
    @Environment(\.tokens) private var t

    var body: some View {
        Button { store.targetMenuOpen.toggle() } label: {
            HStack(spacing: 8) {
                Text("Target").foregroundStyle(t.faint).fontWeight(.medium)
                if let target = store.target {
                    Text(target.name)
                    Text(target.serial).font(Typo.mono(11.5)).foregroundStyle(t.faint)
                } else {
                    Text("No device").foregroundStyle(t.muted)
                }
                Icon(.chevronDown, size: 12, stroke: 2.4)
            }
            .font(Typo.ui(12.5, .semibold))
            .foregroundStyle(t.text)
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(height: 32)
            .background(Capsule().fill(t.ctrl))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tunnel target")
    }
}

/// Target picker under the sub-nav; a click anywhere else closes it.
struct TargetMenu: View {
    var store: EmulatorStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.contentShape(Rectangle()).onTapGesture { store.targetMenuOpen = false }
            MenuPopover(options: store.targets.map { "\($0.name)  \($0.serial)" },
                        selected: store.targets.firstIndex { $0.serial == store.target?.serial } ?? 0) { i in
                store.selectTarget(store.targets[i].serial)
            }
            .padding(.top, Geo.Chrome.subNavTop + Geo.SubTab.height + 6)
        }
    }
}

struct TunnelView: View {
    @Bindable var store: EmulatorStore
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Let your Android device hit a server running on this Mac. Metro, your API, anything.")
                    .font(Typo.ui(12.5)).foregroundStyle(t.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TunnelControls(store: store)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            ActiveTunnelsCard(store: store).frame(width: 220)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct PortCard: View {
    var glyph: Glyph
    var title: String
    var subtitle: String
    @Binding var port: String
    @Environment(\.tokens) private var t

    var body: some View {
        HStack(spacing: 10) {
            Icon(glyph, size: 18, stroke: 2).foregroundStyle(t.text2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typo.ui(13, .semibold))
                Text(subtitle).font(Typo.ui(11)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DockTextField(text: $port, placeholder: "", font: Typo.mono(15, .medium), alignment: .center)
                .frame(width: 72, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(t.inset))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(t.border, lineWidth: 1))
        }
        .padding(.leading, 15).padding(.trailing, 11)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 16).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(t.line, lineWidth: 1))
    }
}

/// Port cards, presets, command well and the run button: everything under the description.
struct TunnelControls: View {
    @Bindable var store: EmulatorStore
    @Environment(\.tokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PortCard(glyph: .monitor, title: "Host port", subtitle: "on your Mac",
                         port: Binding(get: { store.host }, set: store.setHost))
                Icon(.arrowLeft, size: 14, stroke: 2.6).foregroundStyle(Tokens.onTint)
                    .frame(width: 30, height: 30).background(Circle().fill(t.accent))
                PortCard(glyph: .phone, title: "Device port", subtitle: "on Android",
                         port: Binding(get: { store.device }, set: store.setDevice))
            }
            HStack(spacing: 6) {
                ForEach(SampleData.tunnelPresets, id: \.0) { preset in
                    PresetChip(label: preset.0, port: preset.1, on: store.host == preset.1 && store.device == preset.1) {
                        store.usePreset(preset.1)
                    }
                }
            }
            HStack(spacing: 10) {
                Text("$").font(Typo.mono(13)).foregroundStyle(t.ink)
                Text(store.tunnelCommand).font(Typo.mono(13)).foregroundStyle(t.text).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DockButton(title: store.copied ? "Copied" : "Copy", glyph: .copy, iconSize: 13, metrics: .well, tone: .ctrl,
                           action: store.copyCommand)
            }
            .padding(.leading, 15).padding(.trailing, 7)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(t.inset))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(t.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            DockButton(title: "Run reverse tunnel", glyph: .play, iconSize: 12, metrics: .run, tone: .tint, weight: .bold,
                       action: store.runTunnel)
        }
    }
}

struct ActiveTunnelsCard: View {
    var store: EmulatorStore
    @Environment(\.tokens) private var t

    var body: some View {
        Card(radius: 18, padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Active tunnels").font(Typo.ui(12, .semibold)).foregroundStyle(t.muted)
                    Spacer()
                    Text("\(store.tunnels.count)").font(Typo.display(22))
                }
                if store.tunnels.isEmpty {
                    Text("Nothing tunnelled yet. Hit run and it shows up here.")
                        .font(Typo.ui(12)).foregroundStyle(t.faint)
                        .lineSpacing(Typo.lineSpacing(size: 12, lineHeight: 1.45))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    DockScroll {
                        VStack(spacing: 6) {
                            ForEach(store.tunnels) { tn in
                                HStack(spacing: 8) {
                                    Circle().fill(Fixed.runningDot).frame(width: 7, height: 7)
                                    Text(":\(tn.host) → :\(tn.device)").font(Typo.mono(12)).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button { store.removeTunnel(tn) } label: {
                                        Icon(.close, size: 12, stroke: 2.6).foregroundStyle(t.faint).frame(width: 30, height: 30).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove tunnel \(tn.host) to \(tn.device)")
                                }
                                .padding(.leading, 10).padding(.trailing, 4)
                                .frame(height: 40)
                                .background(RoundedRectangle(cornerRadius: 12).fill(t.ctrl))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                DockButton(title: "adb reverse --remove-all", glyph: nil,
                           metrics: ButtonMetrics(height: 32, radius: 10, padLeading: 0, padTrailing: 0, font: 12),
                           tone: .ctrl, action: store.removeAllTunnels)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
