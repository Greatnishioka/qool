import SwiftUI

struct MemoRowView: View {
    let memo: Memo

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    Image(systemName: "note.text")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(memo.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(memo.canvas.elements.count) オブジェクト")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
