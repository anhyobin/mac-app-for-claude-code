import SwiftUI

struct AgentDetailView: View {
    let data: AgentDetailData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tool Breakdown
            if !data.toolBreakdown.isEmpty {
                Text("Tools")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(sortedTools, id: \.key) { tool, count in
                        HStack(spacing: 2) {
                            Text(tool)
                                .font(.caption2)
                            Text("\(count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    }
                }
            }

            // Skills Breakdown — per-subagent skill invocations. Purple
            // tint (muted) distinguishes skills from generic tools; count
            // is only rendered when > 1 so singletons stay visually quiet.
            if !data.skillBreakdown.isEmpty {
                Text("Skills")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(sortedSkills, id: \.key) { skill, count in
                        HStack(spacing: 2) {
                            Text(skill)
                                .font(.caption2)
                            if count > 1 {
                                Text("\(count)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }

            // Files Modified
            if !data.fileChanges.isEmpty {
                Text("Files (\(data.fileChanges.count))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                ForEach(data.fileChanges) { file in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(shortPath(file.filePath))
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }

            // Recent Messages
            if !data.recentMessages.isEmpty {
                Text("Recent (\(data.recentMessages.count))")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                ForEach(data.recentMessages) { msg in
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: msg.role == "user" ? "person.fill" : "cpu")
                            .font(.caption2)
                            .foregroundStyle(msg.role == "user" ? .blue : .green)
                            .frame(width: 12)

                        VStack(alignment: .leading, spacing: 1) {
                            if !msg.contentPreview.isEmpty {
                                Text(msg.contentPreview)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            } else if msg.toolResultCount > 0 {
                                Text("↩ \(msg.toolResultCount) tool results")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if !msg.toolUses.isEmpty {
                                HStack(spacing: 2) {
                                    ForEach(msg.toolUses.prefix(3), id: \.self) { tool in
                                        Text(tool)
                                            .font(.system(size: 9))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                    if msg.toolUses.count > 3 {
                                        Text("+\(msg.toolUses.count - 3)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if data.recentMessages.isEmpty && data.fileChanges.isEmpty && data.toolBreakdown.isEmpty && data.skillBreakdown.isEmpty {
                Text("No activity data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
    }

    private var sortedTools: [(key: String, value: Int)] {
        data.toolBreakdown.sorted { $0.value > $1.value }
    }

    private var sortedSkills: [(key: String, value: Int)] {
        data.skillBreakdown.sorted { $0.value > $1.value }
    }

    private func shortPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 3 { return path }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
