import SwiftUI
import UIKit

// EasyTalk design tokens, ported from the accepted design prototype
// (claude.ai/design "Realtime Translator iOS" / EasyTalk Prototype.dc.html).
enum EasyTalk {
    // MARK: Fixed palette
    static let accent = Color(rgb: 0x6D6DFF)
    static let gradientStart = Color(rgb: 0x7B7BFF)
    static let gradientEnd = Color(rgb: 0x5142E6)
    static let russian = Color(rgb: 0x0A84FF)
    static let english = Color(rgb: 0x30D158)
    static let danger = Color(rgb: 0xFF453A)
    static let warning = Color(rgb: 0xFF9F0A)
    static let star = Color(rgb: 0xFFCC00)

    static let brandGradient = LinearGradient(
        colors: [gradientStart, gradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Adaptive palette (dark / light from the prototype themeC())
    static let card = adaptive(
        light: UIColor.white.withAlphaComponent(0.72),
        dark: UIColor.white.withAlphaComponent(0.06)
    )
    static let card2 = adaptive(
        light: UIColor.white,
        dark: UIColor.white.withAlphaComponent(0.10)
    )
    static let stroke = adaptive(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.12)
    )
    static let fg = adaptive(light: UIColor(rgb: 0x0A0B10), dark: .white)
    static let fg2 = adaptive(
        light: UIColor.black.withAlphaComponent(0.55),
        dark: UIColor.white.withAlphaComponent(0.60)
    )
    static let fg3 = adaptive(
        light: UIColor.black.withAlphaComponent(0.34),
        dark: UIColor.white.withAlphaComponent(0.38)
    )
    static let bar = adaptive(
        light: UIColor.white.withAlphaComponent(0.72),
        dark: UIColor(red: 14 / 255, green: 16 / 255, blue: 24 / 255, alpha: 0.72)
    )
    static let russianBubble = adaptive(
        light: UIColor(rgb: 0x0A84FF).withAlphaComponent(0.12),
        dark: UIColor(rgb: 0x0A84FF).withAlphaComponent(0.16)
    )
    static let englishBubble = adaptive(
        light: UIColor(rgb: 0x30D158).withAlphaComponent(0.13),
        dark: UIColor(rgb: 0x30D158).withAlphaComponent(0.15)
    )

    static func side(_ side: Side) -> Color {
        side == .russianSpeaker ? russian : english
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

// MARK: - Background

struct EasyTalkBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let colors: [Color] = colorScheme == .dark
                ? [Color(rgb: 0x1B1F30), Color(rgb: 0x0B0D15), Color(rgb: 0x06070C)]
                : [Color.white, Color(rgb: 0xEEF0F6), Color(rgb: 0xE3E6EF)]
            RadialGradient(
                colors: colors,
                center: UnitPoint(x: 0.5, y: -0.1),
                startRadius: 0,
                endRadius: proxy.size.height * 1.15
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Reusable styling

struct EasyTalkCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(EasyTalk.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(EasyTalk.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func easyTalkCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(EasyTalkCard(cornerRadius: cornerRadius))
    }
}

struct EasyTalkSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.7)
            .foregroundColor(EasyTalk.fg3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EasyTalkPrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    var cornerRadius: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(isEnabled ? .white : EasyTalk.fg3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isEnabled {
                        EasyTalk.brandGradient
                    } else {
                        EasyTalk.card
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: isEnabled ? EasyTalk.gradientEnd.opacity(0.4) : .clear,
                radius: 13, x: 0, y: 8
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Localized strings (RU/EN dictionaries from the prototype)

struct EasyTalkStrings {
    let onbTitle: String
    let onbSub: String
    let b1t: String, b1s: String
    let b2t: String, b2s: String
    let b3t: String, b3s: String
    let permTitle: String
    let critical: String
    let micPerm: String, micPermSub: String
    let speechPerm: String, speechPermSub: String
    let continueLabel: String
    let micError: String
    let hello: String
    let homeTitle: String
    let modeTitle: String
    let modeDialogue: String, modeDialogueSub: String
    let modeMono: String, modeMonoSub: String
    let langTitle: String
    let startBtn: String
    let connecting: String, connectingSub: String
    let ready: String, readySub: String
    let listening: String
    let translating: String
    let degraded: String
    let switchSpeaker: String
    let mute: String, unmute: String
    let end: String
    let resultTitle: String
    let duration: String
    let replicas: String
    let langs: String
    let fullLog: String
    let copy: String, copied: String, share: String
    let rate: String
    let tagBad: String, tagErr: String, tagInt: String
    let newSession: String
    let setTitle: String
    let connection: String
    let connected: String, reconnecting: String
    let ping: String
    let model: String
    let preferences: String
    let haptics: String
    let autoplay: String
    let about: String
    let version: String

    static let russian = EasyTalkStrings(
        onbTitle: "Синхронный голосовой перевод",
        onbSub: "Говорите свободно — EasyTalk переводит вашу речь в реальном времени.",
        b1t: "Синхронный перевод", b1s: "Речь переводится, пока вы говорите",
        b2t: "Низкая задержка", b2s: "Ответ за доли секунды через WebRTC",
        b3t: "Приватность", b3s: "Защищённая сессия, ничего не хранится",
        permTitle: "Нужен доступ",
        critical: "Обязательно",
        micPerm: "Микрофон", micPermSub: "Для захвата и перевода речи",
        speechPerm: "Распознавание речи", speechPermSub: "Для транскрипции и озвучивания",
        continueLabel: "Продолжить",
        micError: "Доступ к микрофону запрещён. Откройте «Настройки → EasyTalk → Микрофон», чтобы включить.",
        hello: "С возвращением",
        homeTitle: "Готовы говорить?",
        modeTitle: "Режим перевода",
        modeDialogue: "Диалог", modeDialogueSub: "Двусторонний перевод · Ru ↔ En",
        modeMono: "Монолог", modeMonoSub: "В одну сторону · Ru → En",
        langTitle: "Языки",
        startBtn: "Начать перевод",
        connecting: "Создаём защищённую сессию", connectingSub: "Согласование WebRTC-соединения…",
        ready: "Готово к переводу", readySub: "Начните говорить — я слушаю",
        listening: "Слушаю…",
        translating: "Перевожу…",
        degraded: "Нестабильная связь",
        switchSpeaker: "Сменить спикера",
        mute: "Микрофон", unmute: "Вкл. звук",
        end: "Завершить",
        resultTitle: "Итоги сессии",
        duration: "Длительность",
        replicas: "Реплик",
        langs: "Языки",
        fullLog: "Полный лог",
        copy: "Скопировать", copied: "Скопировано", share: "Поделиться",
        rate: "Оцените качество перевода",
        tagBad: "Плохо слышно", tagErr: "Ошибки перевода", tagInt: "Прерывания",
        newSession: "Новая сессия",
        setTitle: "Диагностика",
        connection: "Соединение",
        connected: "Подключено", reconnecting: "Переподключение",
        ping: "Задержка",
        model: "Модель",
        preferences: "Параметры",
        haptics: "Тактильный отклик",
        autoplay: "Автоозвучка перевода",
        about: "О приложении",
        version: "Версия"
    )

    static let english = EasyTalkStrings(
        onbTitle: "Real-time voice translation",
        onbSub: "Speak freely — EasyTalk translates your speech in real time.",
        b1t: "Simultaneous", b1s: "Translates as you speak",
        b2t: "Low latency", b2s: "Sub-second replies over WebRTC",
        b3t: "Private", b3s: "Secure session, nothing stored",
        permTitle: "Access needed",
        critical: "Required",
        micPerm: "Microphone", micPermSub: "To capture and translate speech",
        speechPerm: "Speech Recognition", speechPermSub: "For transcription and playback",
        continueLabel: "Continue",
        micError: "Microphone access denied. Open “Settings → EasyTalk → Microphone” to enable it.",
        hello: "Welcome back",
        homeTitle: "Ready to talk?",
        modeTitle: "Translation mode",
        modeDialogue: "Dialogue", modeDialogueSub: "Two-way translation · Ru ↔ En",
        modeMono: "One-way", modeMonoSub: "Single direction · Ru → En",
        langTitle: "Languages",
        startBtn: "Start translating",
        connecting: "Creating a secure session", connectingSub: "Negotiating WebRTC connection…",
        ready: "Ready to translate", readySub: "Start speaking — I’m listening",
        listening: "Listening…",
        translating: "Translating…",
        degraded: "Unstable connection",
        switchSpeaker: "Switch speaker",
        mute: "Mic", unmute: "Unmute",
        end: "End",
        resultTitle: "Session summary",
        duration: "Duration",
        replicas: "Turns",
        langs: "Languages",
        fullLog: "Full log",
        copy: "Copy all", copied: "Copied", share: "Share",
        rate: "Rate translation quality",
        tagBad: "Hard to hear", tagErr: "Translation errors", tagInt: "Interruptions",
        newSession: "New session",
        setTitle: "Diagnostics",
        connection: "Connection",
        connected: "Connected", reconnecting: "Reconnecting",
        ping: "Latency",
        model: "Model",
        preferences: "Preferences",
        haptics: "Haptic feedback",
        autoplay: "Auto-play translation",
        about: "About",
        version: "Version"
    )

    static var current: EasyTalkStrings {
        let language = Locale.preferredLanguages.first ?? "en"
        return language.hasPrefix("ru") ? .russian : .english
    }
}
