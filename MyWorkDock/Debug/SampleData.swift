import Foundation

/// Hard-coded content for the shell and the component snapshots; replaced by real data in later milestones.
/// Values come from Prototype.dc.html (`cxData()`, `renderVals()` and initial state).
enum SampleData {
    // MARK: Peek / live

    /// Prototype default: a pool member (zoya.khan) is in use.
    static let peekPool = PeekData(
        name: "zoya.khan", isPool: true,
        bars: [PeekBar(label: "5H", percent: 0, reset: nil),
               PeekBar(label: "WEEK", percent: 25, reset: "Oct 19")])

    /// `claudex switch work`: SSO account in use.
    static let peekSSO = PeekData(
        name: "work", isPool: false,
        bars: [PeekBar(label: "5H", percent: 20, reset: "2:39pm"),
               PeekBar(label: "WEEK", percent: 38, reset: "Oct 15")])

    static let bootingSim = "iPhone 16 Plus"

    // MARK: claudex (default sort: expiring soon)

    static let accounts: [AccountSample] = [
        AccountSample(id: "studio", plan: "Max 5x", session: Reading(percent: 0, reset: ""), week: Reading(percent: 100, reset: "Oct 14 12:29am")),
        AccountSample(id: "work", plan: "Max 5x", session: Reading(percent: 20, reset: "2:39pm"), week: Reading(percent: 38, reset: "Oct 15 4:29am"), active: true),
        AccountSample(id: "aditya", plan: "Max 5x", session: Reading(percent: 9, reset: "4:10pm"), week: Reading(percent: 11, reset: "Oct 18 12:30pm")),
    ]

    static let members: [MemberSample] = [
        MemberSample(id: "ira.shah", plan: "Team", net: 1408.1, session: Reading(percent: 0, reset: "12:39pm"), week: Reading(percent: 72, reset: "Oct 14 10:29am")),
        MemberSample(id: "neel.joshi", plan: "Team", net: -230.2, session: Reading(percent: 44, reset: "3:39pm"), week: Reading(percent: 80, reset: "Oct 15 11:29am")),
        MemberSample(id: "sana", plan: "Max 5x", net: 16696.5, session: Reading(percent: 16, reset: "1:59pm"), week: Reading(percent: 38, reset: "Oct 15 5:29pm")),
        MemberSample(id: "kabir.rao", plan: "Team", net: -501.5, session: Reading(percent: 37, reset: "12:39pm"), week: Reading(percent: 27, reset: "Oct 16 6:29am")),
        MemberSample(id: "tara.menon", plan: "Team", net: -13823.1, session: Reading(percent: 5, reset: "1:59pm"), week: Reading(percent: 32, reset: "Oct 16 9:29am")),
        MemberSample(id: "aditya.thummar", plan: "Max 5x", net: -3855.4, session: Reading(percent: 9, reset: "4:10pm"), week: Reading(percent: 11, reset: "Oct 18 12:30pm"), mine: true),
    ]
    static let noReadingMember = MemberSample(id: "mira.mehta", plan: "Max 5x", net: 9625, session: nil, week: nil)
    static let deniedMember = MemberSample(id: "rohan.das", plan: "Team", net: -4725.2, session: Reading(percent: 34, reset: "1:29pm"), week: Reading(percent: 56, reset: "Oct 18 6:29pm"), denied: true)

    // MARK: claudex store sample (Prototype `cxData()` at its default state)

    /// Fixed "now" so "Expiring soon" sorts the same on every run: a day before the earliest reset on the screen.
    static let now: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!

    static let usageRows: [UsageRow] = accounts.map {
        let (s, w) = ($0.session!, $0.week!) // sample accounts always have readings
        return UsageRow(account: $0.id, active: $0.active, tier: $0.plan,
                        session: Gauge(pct: s.percent, at: s.reset.isEmpty ? nil : s.reset),
                        week: Gauge(pct: w.percent, at: w.reset), updated: "live")
    }

    private static func member(_ name: String, _ plan: String, _ net: Double, _ s: (Int, String)?, _ w: (Int, String)?, marked: Bool = false) -> PoolMember {
        PoolMember(name: name, plan: plan, marked: marked, active: false, sharing: true,
                   session: s.map { Gauge(pct: $0.0, at: $0.1.isEmpty ? nil : $0.1) } ?? .none,
                   week: w.map { Gauge(pct: $0.0, at: $0.1) } ?? .none, netM: net)
    }

    static let poolMembers: [PoolMember] = [
        member("ira.shah", "Team", 1408.1, (0, "12:39pm"), (72, "Oct 14 10:29am")),
        member("neel.joshi", "Team", -230.2, (44, "3:39pm"), (80, "Oct 15 11:29am")),
        member("sana", "Max 5x", 16696.5, (16, "1:59pm"), (38, "Oct 15 5:29pm")),
        member("kabir.rao", "Team", -501.5, (37, "12:39pm"), (27, "Oct 16 6:29am")),
        member("tara.menon", "Team", -13823.1, (5, "1:59pm"), (32, "Oct 16 9:29am")),
        member("aditya.thummar", "Max 5x", -3855.4, (9, "4:10pm"), (11, "Oct 18 12:30pm")),
        member("rohan.das", "Team", -4725.2, (34, "1:29pm"), (56, "Oct 18 6:29pm")),
        member("zoya.khan", "Team", -6368.1, (0, ""), (25, "Oct 19 1:29am"), marked: true),
        member("vik.sehgal", "Max 5x", -906, (54, "2:39pm"), (26, "Oct 19 11:29am")),
        member("mira.mehta", "Max 5x", 9625, nil, nil),
        member("arjun.dhar", "Team", 2679.9, nil, nil),
    ]

    static let me: (account: String, pool: String?) = ("aditya", "aditya.thummar")

    static let access: [AccessPerson] = poolMembers.filter { $0.name != "aditya.thummar" }.map { AccessPerson(name: $0.name, allowed: true) }

    static let poolStatus = PoolStatus(consuming: (false, "token-swap OFF · on your own token · start with pool start"),
                                       sharing: (true, "your account is serving the pool · managed by your pod lead / admin"))

    static let doctor = Doctor(checks: [
        DoctorCheck(ok: true, label: "macOS", detail: ""),
        DoctorCheck(ok: true, label: "claude CLI", detail: "2.1.290 (Claude Code)"),
        DoctorCheck(ok: true, label: "claudex on PATH", detail: "~/.local/bin/claudex"),
        DoctorCheck(ok: true, label: "build channel: prod", detail: "self-updates from latest/"),
        DoctorCheck(ok: true, label: "API target", detail: "claudex-api (prod)"),
        DoctorCheck(ok: true, label: "version", detail: "v3.14.0 (latest)"),
        DoctorCheck(ok: true, label: "Keychain access", detail: "live credential present"),
        DoctorCheck(ok: true, label: "3 account(s) saved", detail: ""),
        DoctorCheck(ok: true, label: "active account", detail: "work"),
        DoctorCheck(ok: true, label: "autoswitch", detail: "disabled"),
        DoctorCheck(ok: true, label: "proxy", detail: "always-on (pid 1573) · mode passthrough · wired"),
        DoctorCheck(ok: true, label: "launchd agent", detail: "com.claudex-dash loaded"),
        DoctorCheck(ok: false, label: "studio", detail: "weekly limit reached · resets Oct 14 12:29am"),
        DoctorCheck(ok: false, label: "pool", detail: "not consuming · start the pool to fail over"),
    ], accounts: [], summary: "")

    /// Prototype `cxDetailFor` for ira.shah (the reference screenshots 13 and 14).
    static let memberDetail = MemberDetail(
        name: "ira.shah", plan: "Team", marked: false, sharing: true, state: "offline",
        flows: [MemberFlow(label: "own", in: "37.1M", out: "30.0M", cacheRead: "8385.6M", cacheWrite: "131.7M", req: "35935", note: "my token → me"),
                MemberFlow(label: "borrowed", in: "1.1M", out: "1.1M", cacheRead: "278.5M", cacheWrite: "5.9M", req: "1547", note: "from pool"),
                MemberFlow(label: "shared", in: "15.2M", out: "11.5M", cacheRead: "4127.1M", cacheWrite: "85.4M", req: "11274", note: "to pool")],
        netM: 1408.1, netDir: "giver", splitNote: nil, footnote: "shares are of observed proxy tokens, approximate",
        windows: [MemberWindow(label: "last 5h", pct: 0, resets: nil, note: "no attributed traffic this window", drivers: []),
                  MemberWindow(label: "week", pct: 72, resets: "Oct 14 10:29am", note: nil,
                               drivers: [Driver(name: "aditya.thummar", you: true, pct: 84, tokens: "192.8M"),
                                         Driver(name: "ira.shah", you: false, pct: 16, tokens: "36.7M")])])

    static let memberDetailRaw = """
    {
      "member": "ira.shah",
      "plan": "Team",
      "sharing": true,
      "online": false,
      "net_m": 1408.1,
      "own": {
        "in": 37.1,
        "out": 30,
        "cache_r": 8385.6,
        "cache_w": 131.7,
        "req": 35935
      },
      "borrowed": {
        "in": 1.1,
        "out": 1.1,
        "cache_r": 278.5,
        "cache_w": 5.9,
        "req": 1547
      },
      "shared": {
        "in": 15.2,
        "out": 11.5,
        "cache_r": 4127.1,
        "cache_w": 85.4,
        "req": 11274
      },
      "session_pct": 0,
      "week_pct": 72,
      "week_resets": "Oct 14 10:29am"
    }
    """

    static let playgroundOutput: [PlayLine] = [
        PlayLine(text: "$ claudex usage", kind: .cmd),
        PlayLine(text: "studio     session   0%   week 100%"),
        PlayLine(text: "work       session  20%   week  38%   ← active"),
        PlayLine(text: "aditya     session   9%   week  11%"),
        PlayLine(text: "$ claudex whoami", kind: .cmd),
        PlayLine(text: "work"),
    ]

    static let sortOptions = ["Default order", "Name A→Z", "Name Z→A", "Least used (week)", "Most used (week)",
                              "Least used (session)", "Most used (session)", "Expiring soon", "Least used + expiring soon"]

    // MARK: Emulator

    static let iosDevices: [DeviceSample] = [
        DeviceSample(id: "i1", name: "iPhone 17", os: "iOS 26.5", status: .running),
        DeviceSample(id: "i2", name: "iPhone 16 Plus", os: "iOS 26.5", status: .stopped),
        DeviceSample(id: "i3", name: "iPad Air 13-inch (M3)", os: "iPadOS 26.5", tablet: true, status: .stopped),
        DeviceSample(id: "i4", name: "iPhone SE (3rd gen)", os: "iOS 18.6", status: .stopped),
    ]
    /// Same list while iPhone 16 Plus boots (prototype state after pressing Play).
    static let iosDevicesBooting: [DeviceSample] = iosDevices.map {
        var d = $0
        if d.id == "i2" { d.status = .booting }
        return d
    }

    static let androidDevices: [DeviceSample] = [
        DeviceSample(id: "a1", name: "Pixel 9 Pro", os: "Android 15 · API 35", status: .stopped),
        DeviceSample(id: "a2", name: "Pixel Tablet", os: "Android 14 · API 34", tablet: true, status: .stopped),
    ]

    static let wirelessAndroid: [WirelessSample] = [
        WirelessSample(id: "a1w", name: "Pixel 8", meta: "Android 15", addr: "192.168.1.24:5555", status: .connected),
        WirelessSample(id: "a2w", name: "Galaxy S23", meta: "Android 14", addr: "192.168.1.31:5555", status: .disconnected),
    ]

    static let wirelessIOS: [WirelessSample] = [
        WirelessSample(id: "w1", name: "QA iPhone 15 Pro", meta: "iOS 26.5", addr: "00008130-001A2B3C4D5E0001", status: .connected),
        WirelessSample(id: "w2", name: "Test iPhone 16 Pro", meta: "iOS 27.0", addr: "00008140-001A2B3C4D5E0002", status: .unavailable),
        WirelessSample(id: "w3", name: "Test iPhone 15", meta: "iOS 26.6.2", addr: "00008120-001A2B3C4D5E0003", status: .unavailable),
        WirelessSample(id: "w4", name: "iPhone 15 New", meta: "iOS 26.5", addr: "00008120-001A2B3C4D5E0004", status: .disconnected),
    ]

    static let tunnels = [(host: "8081", device: "8081"), (host: "3000", device: "3000")]
    static let tunnelPresets = [("Metro", "8081"), ("API", "3000"), ("Vite", "5173"), ("Storybook", "7007")]

    // MARK: Notes, commands and prompts

    static let todos: [TodoSample] = [
        TodoSample(id: 1, title: "Ship TestFlight build 2.4.0", tag: "release", due: "Today 4 PM", hot: true),
        TodoSample(id: 2, title: "Fix cart badge not updating after checkout", tag: "bug", due: "Today", hot: true),
        TodoSample(id: 3, title: "Bump reanimated + re-run pod install", tag: "deps", due: "Tomorrow"),
        TodoSample(id: 4, title: "Update App Store screenshots (6.9\")", tag: "release", due: "Fri", done: true),
        TodoSample(id: 5, title: "Write OTA rollout notes", tag: "docs", due: "Done", done: true),
    ]

    static let commands = [
        "npx react-native run-ios --simulator \"iPhone 17\"",
        "cd ios && pod install && cd ..",
        "npx react-native start --reset-cache",
        "adb reverse tcp:8081 tcp:8081",
        "cd android && ./gradlew clean assembleRelease",
        "watchman watch-del-all && rm -rf node_modules && yarn",
    ]

    static let prompts = [
        "Review this PR like a senior RN engineer.\n1. Performance and unnecessary re-renders\n2. iOS / Android platform gotchas\n3. Missing tests\nEnd with a 3-line summary and a ship / don’t-ship call.",
        "Write release notes for this build from the commit list. Group by Features, Fixes, Chores. Keep it client-friendly and skip internal refactors unless they change behaviour.",
        "Convert this design spec into a SwiftUI view. Use only our Tokens and components; no hard-coded colours.",
        "Explain this crash log in plain words, name the likely cause, and suggest the smallest fix.",
        "Turn these meeting notes into a todo list with owners and due dates.",
    ]
}
