import AppKit
import AVFoundation
import Combine
import SwiftUI

enum HubIslandClockStyle: String, CaseIterable, Identifiable {
    case digitalWithSeconds
    case digitalCompact
    case analog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .digitalWithSeconds: return HubMacL10n.string("mac.clock.style.seconds")
        case .digitalCompact: return HubMacL10n.string("mac.clock.style.compact")
        case .analog: return HubMacL10n.string("mac.clock.style.analog")
        }
    }

    static let appStorageKey = "treelethub.island.clock.style"
    static let hourlyChimeKey = "treelethub.island.clock.hourlyChime"
    static let hourlyVoiceKey = "treelethub.island.clock.hourlyVoice"
}

/// 每秒更新 `now`，并按偏好触发整点铃声 / 语音。
@MainActor
final class HubIslandClockController: ObservableObject {
    @Published private(set) var now: Date = Date()

    private var tick: AnyCancellable?
    private var lastChimedHour: Int?
    private let speech = AVSpeechSynthesizer()

    init() {
        now = Date()
        tick = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.handleTick(date)
            }
    }

    func speakCurrentTime() {
        let loc = HubMacL10n.displayLocale
        if loc.identifier.hasPrefix("zh") {
            let f = DateFormatter()
            f.locale = loc
            f.dateFormat = "H点m分"
            let text = HubMacL10n.string("mac.clock.speak.prefix") + f.string(from: now)
            speak(text, language: "zh-CN")
        } else {
            let f = DateFormatter()
            f.locale = loc
            f.timeStyle = .short
            f.dateStyle = .none
            let text = HubMacL10n.string("mac.clock.speak.prefix") + f.string(from: now)
            speak(text, language: "en-US")
        }
    }

    private func handleTick(_ date: Date) {
        now = date
        let chime = UserDefaults.standard.bool(forKey: HubIslandClockStyle.hourlyChimeKey)
        let voice = UserDefaults.standard.bool(forKey: HubIslandClockStyle.hourlyVoiceKey)
        guard chime || voice else { return }

        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        guard m == 0, s == 0 else { return }
        if lastChimedHour == h { return }
        lastChimedHour = h

        if chime {
            if let tone = NSSound(named: NSSound.Name("Glass")) {
                tone.play()
            } else {
                NSSound.beep()
            }
        }
        if voice {
            let loc = HubMacL10n.displayLocale
            if loc.identifier.hasPrefix("zh") {
                speak(String(format: HubMacL10n.string("mac.clock.speak.hourly"), h), language: "zh-CN")
            } else {
                let f = DateFormatter()
                f.locale = loc
                f.timeStyle = .short
                f.dateStyle = .none
                speak("The time is \(f.string(from: date)).", language: "en-US")
            }
        }
    }

    private func speak(_ text: String, language: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speech.speak(u)
    }
}

// MARK: - Views

struct HubIslandCollapsedTimeWeatherStrip: View {
    let now: Date
    let weather: HubIslandWeatherSnapshot?

    private static func timeDigits(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = HubMacL10n.displayLocale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(verbatim: Self.timeDigits(from: now))
                .font(.system(size: 12, weight: .medium, design: .default))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            if let weather {
                collapsedMetaSeparator
                Image(systemName: weather.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.78))
                Text(verbatim: weather.temperatureLine)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 3)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var collapsedMetaSeparator: some View {
        Text(verbatim: "|")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.white.opacity(0.28))
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }
}

/// 自定义三段样式切换（避免系统 `Picker.segmented` 在深色胶囊上对比度过低）。
struct HubIslandClockStyleSegmentControl: View {
    @Binding var selectionRaw: String

    private var selection: HubIslandClockStyle {
        HubIslandClockStyle(rawValue: selectionRaw) ?? .digitalWithSeconds
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(HubIslandClockStyle.allCases) { style in
                HubIslandClockStyleSegmentCell(
                    title: style.title,
                    selected: selection == style,
                    action: { selectionRaw = style.rawValue }
                )
            }
        }
    }
}

private struct HubIslandClockStyleSegmentCell: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? Color.black.opacity(0.88) : Color.white.opacity(0.94))
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(bg)
                .overlay(outline)
        }
        .buttonStyle(.plain)
    }

    private var bg: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.14))
    }

    private var outline: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.white.opacity(selected ? 0 : 0.22), lineWidth: 1)
    }
}

struct HubIslandClockFaceView: View {
    let now: Date
    let style: HubIslandClockStyle

    private func formatHM(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = HubMacL10n.displayLocale
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func formatHMS(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = HubMacL10n.displayLocale
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    var body: some View {
        Group {
            switch style {
            case .digitalWithSeconds:
                Text(formatHMS(now))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.96))
            case .digitalCompact:
                Text(formatHM(now))
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.96))
            case .analog:
                HubIslandAnalogClockFace(date: now)
                    .frame(width: 156, height: 156)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 8)
    }
}

private struct HubIslandAnalogClockFace: View {
    let date: Date

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2

            let face = Path { p in
                p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            context.fill(face, with: .color(.white.opacity(0.08)))
            context.stroke(face, with: .color(.white.opacity(0.35)), lineWidth: 1.2)

            let cal = Calendar.current
            let hour = cal.component(.hour, from: date) % 12
            let minute = cal.component(.minute, from: date)
            let second = cal.component(.second, from: date)

            let hourAngle = (Double(hour) + Double(minute) / 60) / 12 * 2 * .pi - .pi / 2
            let minuteAngle = (Double(minute) + Double(second) / 60) / 60 * 2 * .pi - .pi / 2
            let secondAngle = Double(second) / 60 * 2 * .pi - .pi / 2

            func hand(length: CGFloat, width: CGFloat, angle: Double, color: Color) {
                var seg = Path()
                seg.move(to: center)
                seg.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
                context.stroke(
                    seg,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
            }

            hand(length: radius * 0.52, width: 3.2, angle: hourAngle, color: .white.opacity(0.92))
            hand(length: radius * 0.72, width: 2.2, angle: minuteAngle, color: .white.opacity(0.85))
            hand(length: radius * 0.78, width: 1.1, angle: secondAngle, color: Color.orange.opacity(0.95))

            let dot = Path { p in
                p.addEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
            }
            context.fill(dot, with: .color(.white.opacity(0.95)))
        }
    }
}
