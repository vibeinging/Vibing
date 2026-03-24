//
//  SearchBarView.swift
//  VibeTerminal
//
//  Terminal search overlay - Cmd+F search bar
//

import SwiftUI

// MARK: - Search Manager

class TerminalSearchManager: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var matches: [SearchMatch] = []
    @Published var currentMatchIndex: Int = 0
    @Published var isActive: Bool = false
    @Published var isCaseSensitive: Bool = false
    @Published var isRegexEnabled: Bool = false

    func toggle() {
        isActive.toggle()
        if !isActive {
            clearSearch()
        }
    }

    struct SearchMatch: Identifiable {
        let id = UUID()
        let row: Int
        let colStart: Int
        let colEnd: Int
    }

    var matchCountText: String {
        if searchQuery.isEmpty {
            return ""
        }
        if matches.isEmpty {
            return "No results"
        }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }

    /// 搜索功能（TODO: 集成 SwiftTerm 的搜索 API）
    func performSearch() {
        // SwiftTerm 有内置搜索（TerminalViewSearch），后续集成
        guard !searchQuery.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
    }

    private func findMatches(in line: String, row: Int) -> [SearchMatch] {
        var results: [SearchMatch] = []

        if isRegexEnabled {
            let options: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: searchQuery, options: options) else {
                return []
            }
            let nsRange = NSRange(line.startIndex..., in: line)
            let regexMatches = regex.matches(in: line, range: nsRange)
            for match in regexMatches {
                guard let range = Range(match.range, in: line) else { continue }
                let colStart = line.distance(from: line.startIndex, to: range.lowerBound)
                let colEnd = line.distance(from: line.startIndex, to: range.upperBound)
                results.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
            }
        } else {
            let compareOptions: String.CompareOptions = isCaseSensitive ? [] : [.caseInsensitive]
            var searchStart = line.startIndex
            while let range = line.range(of: searchQuery, options: compareOptions, range: searchStart..<line.endIndex) {
                let colStart = line.distance(from: line.startIndex, to: range.lowerBound)
                let colEnd = line.distance(from: line.startIndex, to: range.upperBound)
                results.append(SearchMatch(row: row, colStart: colStart, colEnd: colEnd))
                searchStart = range.upperBound
            }
        }

        return results
    }

    func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    func clearSearch() {
        searchQuery = ""
        matches = []
        currentMatchIndex = 0
    }

    func dismiss() {
        clearSearch()
        isActive = false
    }
}

// MARK: - Search Bar View

struct SearchBarView: View {
    @ObservedObject var searchManager: TerminalSearchManager
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                searchBarContent
                    .padding(.top, 8)
                    .padding(.trailing, 16)
            }
            Spacer()
        }
    }

    private var searchBarContent: some View {
        HStack(spacing: 6) {
            // Search text field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Search...", text: $searchManager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        searchManager.nextMatch()
                    }

                if !searchManager.searchQuery.isEmpty {
                    Text(searchManager.matchCountText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(SwiftUI.Color(NSColor.textBackgroundColor).opacity(0.6))
            )
            .frame(minWidth: 200, maxWidth: 320)

            // Navigation buttons
            Button(action: { searchManager.previousMatch() }) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(SearchBarButtonStyle())
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Previous Match (Cmd+Shift+G)")
            .disabled(searchManager.matches.isEmpty)

            Button(action: { searchManager.nextMatch() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(SearchBarButtonStyle())
            .keyboardShortcut("g", modifiers: [.command])
            .help("Next Match (Cmd+G)")
            .disabled(searchManager.matches.isEmpty)

            Divider()
                .frame(height: 16)

            // Case sensitivity toggle
            Button(action: {
                searchManager.isCaseSensitive.toggle()
            }) {
                Text("Aa")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(SearchBarToggleStyle(isOn: searchManager.isCaseSensitive))
            .help("Match Case")

            // Regex toggle
            Button(action: {
                searchManager.isRegexEnabled.toggle()
            }) {
                Text(".*")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .buttonStyle(SearchBarToggleStyle(isOn: searchManager.isRegexEnabled))
            .help("Use Regular Expression")

            Divider()
                .frame(height: 16)

            // Close button
            Button(action: { searchManager.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(SearchBarButtonStyle())
            .keyboardShortcut(.escape, modifiers: [])
            .help("Close (Escape)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SwiftUI.Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            isSearchFieldFocused = true
        }
    }
}

// MARK: - Button Styles

struct SearchBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .foregroundColor(configuration.isPressed ? .white : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed ? SwiftUI.Color.white.opacity(0.15) : SwiftUI.Color.clear)
            )
            .contentShape(Rectangle())
    }
}

struct SearchBarToggleStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .foregroundColor(isOn ? .accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? SwiftUI.Color.accentColor.opacity(0.2) : SwiftUI.Color.clear)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Preview

#if DEBUG
struct SearchBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.11)
                .ignoresSafeArea()
            SearchBarView(searchManager: TerminalSearchManager())
        }
        .frame(width: 600, height: 400)
    }
}
#endif
