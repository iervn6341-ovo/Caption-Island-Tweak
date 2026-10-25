import SwiftUI

/// The small Activity family is shared by CarPlay and Apple Watch. Keep the
/// entire width for lyrics: the system already identifies the originating app.
struct CaptionSmallActivityView: View {
    let currentLine: String
    let nextLine: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            lyrics(currentLines: 3, nextLines: 2, compact: false)
            lyrics(currentLines: 2, nextLines: 2, compact: false)
            lyrics(currentLines: 2, nextLines: 1, compact: true)
            lyrics(currentLines: 1, nextLines: 1, compact: true)
            // Some hosts allocate less than two rows. Preserve the current cue
            // instead of allowing the next cue to push it outside the card.
            currentText(lines: 1, compact: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .clipped()
    }

    private func lyrics(currentLines: Int, nextLines: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            currentText(lines: currentLines, compact: compact)
            if !nextLine.isEmpty {
                Text(nextLine)
                    .font(compact ? .caption : .subheadline)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(nextLines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func currentText(lines: Int, compact: Bool) -> some View {
        Text(currentLine)
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(.white)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}
