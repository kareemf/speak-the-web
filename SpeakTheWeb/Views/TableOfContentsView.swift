import SwiftUI

/// View displaying the table of contents for navigation
struct TableOfContentsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if let article = viewModel.article, !article.sections.isEmpty {
                    List {
                        ForEach(article.sections) { section in
                            Button(action: {
                                viewModel.navigateToSection(section)
                                dismiss()
                            }) {
                                HStack {
                                    // Indentation based on heading level
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(width: section.indentation)

                                    // Level indicator
                                    Text("H\(section.level)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(levelColor(for: section.level))
                                        .cornerRadius(4)

                                    // Section title
                                    Text(section.title)
                                        .font(fontForLevel(section.level))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)

                                    Spacer()

                                    // Navigation indicator
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Sections Found")
                            .font(.headline)
                        Text("This article doesn't have any heading structure to navigate.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Table of Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: .headline
        case 2: .subheadline
        default: .body
        }
    }

    private func levelColor(for level: Int) -> Color {
        switch level {
        case 1: .accentColor
        case 2: .blue
        case 3: .green
        case 4: .orange
        case 5: .purple
        default: .gray
        }
    }
}

#Preview {
    TableOfContentsView(viewModel: ReaderViewModel())
}
