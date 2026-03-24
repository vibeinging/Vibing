//
//  CommandPaletteView.swift
//  VibeTerminal
//
//  Spotlight-style command palette - Cmd+K
//

import SwiftUI

// MARK: - Palette Command

struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String
    let action: () -> Void

    static func defaultCommands(onAction: @escaping (String) -> Void) -> [PaletteCommand] {
        [
            PaletteCommand(
                title: "New Tab",
                subtitle: "Open a new terminal tab",
                icon: "plus.square",
                shortcut: "Cmd+T",
                action: { onAction("newTab") }
            ),
            PaletteCommand(
                title: "Close Tab",
                subtitle: "Close the current tab",
                icon: "xmark.square",
                shortcut: "Cmd+W",
                action: { onAction("closeTab") }
            ),
            PaletteCommand(
                title: "Split Horizontal",
                subtitle: "Split terminal pane horizontally",
                icon: "rectangle.split.1x2",
                shortcut: "Cmd+D",
                action: { onAction("splitHorizontal") }
            ),
            PaletteCommand(
                title: "Split Vertical",
                subtitle: "Split terminal pane vertically",
                icon: "rectangle.split.2x1",
                shortcut: "Cmd+Shift+D",
                action: { onAction("splitVertical") }
            ),
            PaletteCommand(
                title: "Find",
                subtitle: "Search in terminal output",
                icon: "magnifyingglass",
                shortcut: "Cmd+F",
                action: { onAction("find") }
            ),
            PaletteCommand(
                title: "Settings",
                subtitle: "Open preferences",
                icon: "gearshape",
                shortcut: "Cmd+,",
                action: { onAction("settings") }
            ),
            PaletteCommand(
                title: "Clear Terminal",
                subtitle: "Clear all terminal output",
                icon: "trash",
                shortcut: "Cmd+K",
                action: { onAction("clearTerminal") }
            ),
            PaletteCommand(
                title: "Toggle Theme",
                subtitle: "Switch between light and dark theme",
                icon: "moon.circle",
                shortcut: "Cmd+Shift+T",
                action: { onAction("toggleTheme") }
            ),
            PaletteCommand(
                title: "Show All Sessions",
                subtitle: "View and manage terminal sessions",
                icon: "list.bullet.rectangle",
                shortcut: "",
                action: { onAction("showSessions") }
            ),
            PaletteCommand(
                title: "Copy Selection",
                subtitle: "Copy selected text to clipboard",
                icon: "doc.on.doc",
                shortcut: "Cmd+C",
                action: { onAction("copy") }
            ),
            PaletteCommand(
                title: "Paste",
                subtitle: "Paste from clipboard",
                icon: "doc.on.clipboard",
                shortcut: "Cmd+V",
                action: { onAction("paste") }
            ),
            PaletteCommand(
                title: "Next Pane",
                subtitle: "Navigate to the next split pane",
                icon: "arrow.right.square",
                shortcut: "Cmd+]",
                action: { onAction("nextPane") }
            ),
            PaletteCommand(
                title: "Previous Pane",
                subtitle: "Navigate to the previous split pane",
                icon: "arrow.left.square",
                shortcut: "Cmd+[",
                action: { onAction("previousPane") }
            ),
            PaletteCommand(
                title: "Maximize Pane",
                subtitle: "Toggle maximize for the active pane",
                icon: "arrow.up.left.and.arrow.down.right",
                shortcut: "Shift+Cmd+Enter",
                action: { onAction("maximizePane") }
            ),
            PaletteCommand(
                title: "Save Launch Configuration",
                subtitle: "Save current window layout for quick restore",
                icon: "square.and.arrow.down",
                shortcut: "",
                action: { onAction("saveLaunchConfig") }
            ),
        ]
    }
}

// MARK: - Command Palette Manager

class CommandPaletteManager: ObservableObject {
    @Published var isVisible: Bool = false
    @Published var commands: [PaletteCommand] = []
    @Published var filteredCommands: [PaletteCommand] = []
    @Published var searchText: String = "" {
        didSet { filterCommands() }
    }
    @Published var selectedIndex: Int = 0

    func setup(onAction: @escaping (String) -> Void) {
        commands = PaletteCommand.defaultCommands(onAction: onAction)
        filteredCommands = commands
    }

    func toggle() {
        isVisible.toggle()
        if isVisible {
            searchText = ""
            selectedIndex = 0
            filteredCommands = commands
        }
    }

    func dismiss() {
        isVisible = false
        searchText = ""
        selectedIndex = 0
    }

    func executeSelected() {
        guard !filteredCommands.isEmpty, selectedIndex < filteredCommands.count else { return }
        let command = filteredCommands[selectedIndex]
        dismiss()
        command.action()
    }

    func moveSelectionUp() {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + filteredCommands.count) % filteredCommands.count
    }

    func moveSelectionDown() {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % filteredCommands.count
    }

    private func filterCommands() {
        if searchText.isEmpty {
            filteredCommands = commands
        } else {
            filteredCommands = commands.filter { fuzzyMatch(query: searchText, target: $0.title) }
        }
        selectedIndex = 0
    }

    private func fuzzyMatch(query: String, target: String) -> Bool {
        let query = query.lowercased()
        let target = target.lowercased()

        // Direct substring match
        if target.contains(query) {
            return true
        }

        // Fuzzy: all query characters appear in order within target
        var targetIndex = target.startIndex
        for char in query {
            guard let found = target[targetIndex...].firstIndex(of: char) else {
                return false
            }
            targetIndex = target.index(after: found)
        }
        return true
    }
}

// MARK: - Command Palette View

private let paletteAccent = SwiftUI.Color(red: 222/255, green: 172/255, blue: 92/255)

struct CommandPaletteView: View {
    @ObservedObject var manager: CommandPaletteManager
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed background
            SwiftUI.Color(red: 0.02, green: 0.02, blue: 0.01).opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    manager.dismiss()
                }

            // Palette card
            VStack(spacing: 0) {
                searchField

                Rectangle()
                    .fill(SwiftUI.Color.white.opacity(0.06))
                    .frame(height: 0.5)

                commandList
            }
            .frame(width: 480)
            .frame(maxHeight: 380)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(SwiftUI.Color(red: 28/255, green: 27/255, blue: 25/255).opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SwiftUI.Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.6), radius: 40, y: 12)
            .padding(.top, 70)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            isSearchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.white.opacity(0.3))

            TextField("Search commands...", text: $manager.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFocused)
                .onSubmit {
                    manager.executeSelected()
                }

            if !manager.searchText.isEmpty {
                Button(action: { manager.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.25))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var commandList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(manager.filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(
                            command: command,
                            isSelected: index == manager.selectedIndex
                        )
                        .id(index)
                        .onTapGesture {
                            manager.selectedIndex = index
                            manager.executeSelected()
                        }
                        .onHover { hovering in
                            if hovering {
                                manager.selectedIndex = index
                            }
                        }
                    }

                    if manager.filteredCommands.isEmpty {
                        Text("No matching commands")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: manager.selectedIndex) { newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    scrollProxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Command Row

struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? paletteAccent : .white.opacity(0.3))
                .frame(width: 20, height: 20)

            Text(command.title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white.opacity(0.95) : .white.opacity(0.65))

            Spacer()

            if !command.shortcut.isEmpty {
                Text(command.shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? paletteAccent.opacity(0.12) : SwiftUI.Color.clear)
                .padding(.horizontal, 5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Keyboard Handling View Modifier

struct CommandPaletteKeyHandler: ViewModifier {
    @ObservedObject var manager: CommandPaletteManager

    func body(content: Content) -> some View {
        content
            .background(
                // Hidden buttons for keyboard handling (macOS 13 compatible)
                Group {
                    Button("") { manager.moveSelectionUp() }
                        .keyboardShortcut(.upArrow, modifiers: [])
                        .opacity(0)
                    Button("") { manager.moveSelectionDown() }
                        .keyboardShortcut(.downArrow, modifiers: [])
                        .opacity(0)
                    Button("") { manager.dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .opacity(0)
                    Button("") { manager.executeSelected() }
                        .keyboardShortcut(.return, modifiers: [])
                        .opacity(0)
                }
            )
    }
}

extension View {
    func commandPaletteKeyHandler(manager: CommandPaletteManager) -> some View {
        modifier(CommandPaletteKeyHandler(manager: manager))
    }
}

// MARK: - Preview

#if DEBUG
struct CommandPaletteView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = CommandPaletteManager()
        ZStack {
            SwiftUI.Color(red: 0.11, green: 0.11, blue: 0.11)
                .ignoresSafeArea()
            CommandPaletteView(manager: manager)
        }
        .frame(width: 700, height: 500)
        .onAppear {
            manager.setup(onAction: { _ in })
            manager.isVisible = true
        }
    }
}
#endif
