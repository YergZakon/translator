import SwiftUI

struct ResultView: View {
    let duration: TimeInterval
    var segments: [TranscriptSegment] = []
    @State private var rating = 0
    @State private var selectedTags: Set<String> = []
    @State private var copied = false
    @Environment(\.presentationMode) var presentationMode

    private let strings = EasyTalkStrings.current

    private var tags: [(key: String, label: String)] {
        [
            ("bad", strings.tagBad),
            ("err", strings.tagErr),
            ("int", strings.tagInt)
        ]
    }

    var body: some View {
        ZStack {
            EasyTalkBackground()

            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 8)

                    statsRow
                        .padding(.top, 16)

                    EasyTalkSectionLabel(strings.fullLog)
                        .padding(.top, 20)
                        .padding(.bottom, 9)
                    logList

                    actionsRow
                        .padding(.top, 15)

                    ratingCard
                        .padding(.top, 16)

                    Button(action: dismiss) {
                        Text(strings.newSession)
                    }
                    .buttonStyle(EasyTalkPrimaryButtonStyle())
                    .padding(.top, 15)
                    .accessibilityLabel(strings.newSession)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(strings.resultTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(EasyTalk.fg)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(EasyTalk.fg)
                    .frame(width: 38, height: 38)
                    .easyTalkCard(cornerRadius: 12)
            }
            .accessibilityLabel("Close")
        }
    }

    private var statsRow: some View {
        HStack(spacing: 9) {
            statCard(value: formatDuration(duration), label: strings.duration)
            statCard(value: "\(segments.count)", label: strings.replicas)
            statCard(value: "RU·EN", label: strings.langs)
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(EasyTalk.fg)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(EasyTalk.fg2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .easyTalkCard(cornerRadius: 15)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var logList: some View {
        VStack(spacing: 8) {
            if segments.isEmpty {
                Text("—")
                    .font(.system(size: 14))
                    .foregroundColor(EasyTalk.fg3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .easyTalkCard(cornerRadius: 14)
            } else {
                ForEach(segments) { segment in
                    logRow(for: segment)
                }
            }
        }
    }

    private func logRow(for segment: TranscriptSegment) -> some View {
        let isRussian = segment.side == .russianSpeaker
        let sideColor = EasyTalk.side(segment.side)
        return HStack(alignment: .top, spacing: 10) {
            Text(isRussian ? "RU" : "EN")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(sideColor)
                .padding(.vertical, 3)
                .padding(.horizontal, 7)
                .background(sideColor.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.top, 1)
            Text(segment.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(EasyTalk.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .easyTalkCard(cornerRadius: 14)
    }

    private var actionsRow: some View {
        HStack(spacing: 9) {
            Button(action: copyAll) {
                HStack(spacing: 7) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                    Text(copied ? strings.copied : strings.copy)
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundColor(EasyTalk.fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(EasyTalk.card2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(EasyTalk.stroke, lineWidth: 1)
                )
            }
            .accessibilityLabel(strings.copy)

            ShareLink(item: transcriptText) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text(strings.share)
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundColor(EasyTalk.fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(EasyTalk.card2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(EasyTalk.stroke, lineWidth: 1)
                )
            }
            .accessibilityLabel(strings.share)
        }
    }

    private var ratingCard: some View {
        VStack(spacing: 0) {
            Text(strings.rate)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(EasyTalk.fg)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: { withAnimation { rating = star } }) {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 27))
                            .foregroundColor(star <= rating ? EasyTalk.star : EasyTalk.fg3)
                    }
                    .accessibilityLabel("\(star)")
                }
            }
            .padding(.top, 13)
            .padding(.bottom, 14)

            HStack(spacing: 7) {
                ForEach(tags, id: \.key) { tag in
                    tagChip(key: tag.key, label: tag.label)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .easyTalkCard(cornerRadius: 18)
    }

    private func tagChip(key: String, label: String) -> some View {
        let isSelected = selectedTags.contains(key)
        return Button(action: { toggleTag(key) }) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .white : EasyTalk.fg2)
                .padding(.vertical, 8)
                .padding(.horizontal, 13)
                .background(isSelected ? EasyTalk.accent : EasyTalk.card2)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : EasyTalk.stroke, lineWidth: 1)
                )
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var transcriptText: String {
        segments
            .map { "\($0.side == .russianSpeaker ? "RU" : "EN"): \($0.text)" }
            .joined(separator: "\n")
    }

    private func toggleTag(_ key: String) {
        if selectedTags.contains(key) {
            selectedTags.remove(key)
        } else {
            selectedTags.insert(key)
        }
    }

    private func copyAll() {
        UIPasteboard.general.string = transcriptText
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copied = false
        }
    }

    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
