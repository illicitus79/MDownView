//
//  ContentView.swift
//  MdownView
//
//  Created by Pankaj Nagekar on 02/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import MarkdownUI

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    @AppStorage("preferredColorScheme") private var preferredColorScheme: ColorSchemePreference = .system
    @AppStorage("editorMode") private var editorMode: EditorMode = .split
    @AppStorage("tabLayout") private var tabLayout: TabLayout = .top

    @State private var tabs: [MarkdownTab] = [MarkdownTab.newTab()]
    @State private var selectedTabID: MarkdownTab.ID? = nil

    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var pendingExportTabID: MarkdownTab.ID? = nil
    @State private var exportDocument = MarkdownDocument(text: "")
    @State private var exportFileName = "Untitled"

    @State private var isShowingError = false
    @State private var errorMessage = ""

    private var resolvedColorScheme: ColorScheme {
        switch preferredColorScheme {
        case .system:
            return systemColorScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var preferredSchemeOverride: ColorScheme? {
        switch preferredColorScheme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private var activeTabIndex: Int? {
        guard let selectedTabID else { return nil }
        return tabs.firstIndex(where: { $0.id == selectedTabID })
    }

    private var activeTab: MarkdownTab? {
        guard let index = activeTabIndex else { return nil }
        return tabs[index]
    }

    var body: some View {
        let theme = Theme.palette(for: resolvedColorScheme)

        ZStack {
            theme.backgroundGradient
                .ignoresSafeArea()

            Group {
                if tabLayout == .left {
                    HStack(spacing: 0) {
                        tabsPane(theme: theme)
                            .frame(width: 230)
                        Divider()
                        mainPane(theme: theme)
                    }
                } else {
                    VStack(spacing: 0) {
                        tabsPane(theme: theme)
                            .frame(height: 46)
                        Divider()
                        mainPane(theme: theme)
                    }
                }
            }
            .background(theme.canvasBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(18)
        }
        .preferredColorScheme(preferredSchemeOverride)
        .onAppear {
            if selectedTabID == nil {
                selectedTabID = tabs.first?.id
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.markdownText, .plainText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                openFiles(urls: urls)
            case .failure(let error):
                presentError("Failed to open files: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .markdownText,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success(let url):
                finalizeExport(url: url)
            case .failure(let error):
                presentError("Failed to save file: \(error.localizedDescription)")
            }
        }
        .alert("Something went wrong", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: newTab) {
                    Label("New", systemImage: "plus.square")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(action: { isImporterPresented = true }) {
                    Label("Open", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(action: saveActiveTab) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(action: saveActiveTabAs) {
                    Label("Save As", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
            }

            ToolbarItemGroup {
                Picker("Mode", selection: $editorMode) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Picker("Tabs", selection: $tabLayout) {
                    ForEach(TabLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Picker("Theme", selection: $preferredColorScheme) {
                    ForEach(ColorSchemePreference.allCases) { preference in
                        Label(preference.label, systemImage: preference.icon)
                            .tag(preference)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func tabsPane(theme: Theme) -> some View {
        let background = theme.panelBackground

        return Group {
            if tabLayout == .left {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tabs) { tab in
                            tabButton(tab, theme: theme, axis: .vertical)
                        }
                        Button(action: newTab) {
                            Label("New Tab", systemImage: "plus")
                                .font(.custom(theme.uiFont, size: 12))
                                .foregroundStyle(theme.accent)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .padding(12)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            tabButton(tab, theme: theme, axis: .horizontal)
                        }
                        Button(action: newTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(theme.tabBackground, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(background)
    }

    private func tabButton(_ tab: MarkdownTab, theme: Theme, axis: Axis) -> some View {
        let isSelected = tab.id == selectedTabID
        let title = displayTitle(for: tab)

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom(theme.uiFont, size: 13))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                if let url = tab.url {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.custom(theme.uiFont, size: 10))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                } else {
                    Text(tab.isDirty ? "Unsaved" : "Draft")
                        .font(.custom(theme.uiFont, size: 10))
                        .foregroundStyle(theme.textMuted)
                }
            }

            Spacer(minLength: 8)

            if tab.isDirty {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 6, height: 6)
            }

            Button(action: { closeTab(tab.id) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(axis == .vertical ? 10 : 8)
        .frame(
            minWidth: axis == .horizontal ? 160 : nil,
            maxWidth: axis == .horizontal ? 220 : .infinity,
            alignment: .leading
        )
        .background(isSelected ? theme.tabSelectedBackground : theme.tabBackground)
        .clipShape(RoundedRectangle(cornerRadius: axis == .vertical ? 10 : 12, style: .continuous))
        .onTapGesture {
            selectedTabID = tab.id
        }
    }

    private func mainPane(theme: Theme) -> some View {
        VStack(spacing: 0) {
            if let activeTab {
                editorArea(for: activeTab, theme: theme)
                Divider()
                statusBar(for: activeTab, theme: theme)
            } else {
                emptyState(theme: theme)
            }
        }
        .background(theme.canvasBackground)
    }

    private func editorArea(for tab: MarkdownTab, theme: Theme) -> some View {
        Group {
            switch editorMode {
            case .edit:
                editorView(text: bindingForActiveTab(), theme: theme)
            case .view:
                previewView(text: tab.content, theme: theme)
            case .split:
                HSplitView {
                    editorView(text: bindingForActiveTab(), theme: theme)
                        .frame(minWidth: 280)
                    previewView(text: tab.content, theme: theme)
                        .frame(minWidth: 280)
                }
            }
        }
    }

    private func editorView(text: Binding<String>, theme: Theme) -> some View {
        TextEditor(text: text)
            .font(.custom(theme.editorFont, size: 14))
            .foregroundStyle(theme.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(20)
            .background(theme.editorBackground)
            .textSelection(.enabled)
    }

    private func previewView(text: String, theme: Theme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Markdown(text)
                    .markdownTheme(.gitHub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .background(theme.previewBackground)
        .textSelection(.enabled)
    }

    private func statusBar(for tab: MarkdownTab, theme: Theme) -> some View {
        let wordCount = tab.content.split { $0.isWhitespace || $0.isNewline }.count
        let charCount = tab.content.count
        let lineCount = tab.content.split(whereSeparator: \.isNewline).count

        return HStack(spacing: 12) {
            Label("\(wordCount) words", systemImage: "text.word.spacing")
            Text("\(charCount) chars")
            Text("\(lineCount) lines")
            Spacer()
            if let url = tab.url {
                Text(url.lastPathComponent)
            } else {
                Text("Unsaved draft")
            }
        }
        .font(.custom(theme.uiFont, size: 11))
        .foregroundStyle(theme.textMuted)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.panelBackground)
    }

    private func emptyState(theme: Theme) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Text("Open or create a markdown file to get started")
                .font(.custom(theme.previewFont, size: 16))
                .foregroundStyle(theme.textSecondary)
            Button("New Tab", action: newTab)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvasBackground)
    }

    private func bindingForActiveTab() -> Binding<String> {
        Binding<String>(
            get: { activeTab?.content ?? "" },
            set: { updateActiveTabContent($0) }
        )
    }

    private func updateActiveTabContent(_ newValue: String) {
        guard let index = activeTabIndex else { return }
        tabs[index].content = newValue
        tabs[index].isDirty = true
        if tabs[index].title == "Untitled" {
            tabs[index].title = deriveTitle(from: newValue) ?? "Untitled"
        }
    }

    private func displayTitle(for tab: MarkdownTab) -> String {
        if let url = tab.url {
            return url.deletingPathExtension().lastPathComponent
        }
        return deriveTitle(from: tab.content) ?? tab.title
    }

    private func deriveTitle(from content: String) -> String? {
        let lines = content.split(whereSeparator: \.isNewline)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            }
        }
        return nil
    }

    private func newTab() {
        let tab = MarkdownTab.newTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func closeTab(_ id: MarkdownTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let tab = MarkdownTab.newTab()
            tabs.append(tab)
            selectedTabID = tab.id
        } else if selectedTabID == id {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
        }
    }

    private func saveActiveTab() {
        guard let index = activeTabIndex else { return }
        let tab = tabs[index]
        if let url = tab.url {
            write(tab: tab, to: url)
        } else {
            saveTabAs(tab.id)
        }
    }

    private func saveActiveTabAs() {
        guard let tab = activeTab else { return }
        saveTabAs(tab.id)
    }

    private func saveTabAs(_ id: MarkdownTab.ID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        pendingExportTabID = id
        exportDocument = MarkdownDocument(text: tab.content)
        exportFileName = displayTitle(for: tab).isEmpty ? "Untitled" : displayTitle(for: tab)
        isExporterPresented = true
    }

    private func finalizeExport(url: URL) {
        guard let id = pendingExportTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].url = url
        tabs[index].isDirty = false
        pendingExportTabID = nil
    }

    private func openFiles(urls: [URL]) {
        var lastOpenedID: MarkdownTab.ID? = nil

        for url in urls {
            if let existing = tabs.first(where: { $0.url == url }) {
                lastOpenedID = existing.id
                continue
            }

            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let tab = MarkdownTab(url: url, title: url.deletingPathExtension().lastPathComponent, content: content, isDirty: false)
                tabs.append(tab)
                lastOpenedID = tab.id
            } catch {
                presentError("Failed to read \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if let lastOpenedID {
            selectedTabID = lastOpenedID
        }
    }

    private func write(tab: MarkdownTab, to url: URL) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try tab.content.write(to: url, atomically: true, encoding: .utf8)
            if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
                tabs[index].isDirty = false
            }
        } catch {
            presentError("Failed to save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}

struct Theme {
    let backgroundGradient: LinearGradient
    let canvasBackground: Color
    let panelBackground: Color
    let editorBackground: Color
    let previewBackground: Color
    let tabBackground: Color
    let tabSelectedBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let accent: Color
    let uiFont: String
    let editorFont: String
    let previewFont: String

    static func palette(for scheme: ColorScheme) -> Theme {
        switch scheme {
        case .dark:
            return Theme(
                backgroundGradient: LinearGradient(
                    colors: [Color(red: 0.08, green: 0.10, blue: 0.13), Color(red: 0.07, green: 0.16, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                canvasBackground: Color(red: 0.10, green: 0.12, blue: 0.15),
                panelBackground: Color(red: 0.12, green: 0.14, blue: 0.18),
                editorBackground: Color(red: 0.09, green: 0.11, blue: 0.14),
                previewBackground: Color(red: 0.10, green: 0.12, blue: 0.16),
                tabBackground: Color(red: 0.13, green: 0.15, blue: 0.19),
                tabSelectedBackground: Color(red: 0.20, green: 0.25, blue: 0.28),
                textPrimary: Color(red: 0.93, green: 0.94, blue: 0.96),
                textSecondary: Color(red: 0.74, green: 0.78, blue: 0.82),
                textMuted: Color(red: 0.55, green: 0.59, blue: 0.64),
                accent: Color(red: 0.36, green: 0.78, blue: 0.68),
                uiFont: "Avenir Next",
                editorFont: "Menlo",
                previewFont: "Iowan Old Style"
            )
        default:
            return Theme(
                backgroundGradient: LinearGradient(
                    colors: [Color(red: 0.99, green: 0.96, blue: 0.92), Color(red: 0.91, green: 0.96, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                canvasBackground: Color(red: 0.98, green: 0.97, blue: 0.95),
                panelBackground: Color(red: 0.94, green: 0.95, blue: 0.95),
                editorBackground: Color(red: 0.99, green: 0.98, blue: 0.97),
                previewBackground: Color(red: 0.98, green: 0.97, blue: 0.96),
                tabBackground: Color(red: 0.92, green: 0.93, blue: 0.92),
                tabSelectedBackground: Color(red: 0.86, green: 0.90, blue: 0.89),
                textPrimary: Color(red: 0.18, green: 0.20, blue: 0.22),
                textSecondary: Color(red: 0.34, green: 0.36, blue: 0.38),
                textMuted: Color(red: 0.52, green: 0.54, blue: 0.56),
                accent: Color(red: 0.12, green: 0.50, blue: 0.45),
                uiFont: "Avenir Next",
                editorFont: "Menlo",
                previewFont: "Iowan Old Style"
            )
        }
    }
}

struct MarkdownTab: Identifiable, Equatable {
    let id: UUID
    var url: URL?
    var title: String
    var content: String
    var isDirty: Bool

    init(id: UUID = UUID(), url: URL? = nil, title: String, content: String, isDirty: Bool) {
        self.id = id
        self.url = url
        self.title = title
        self.content = content
        self.isDirty = isDirty
    }

    static func newTab() -> MarkdownTab {
        MarkdownTab(
            title: "Untitled",
            content: "# Untitled\n\nStart writing your markdown here.\n\n- Add headings, lists, and code blocks\n- Toggle split view to preview\n- Save when you're ready",
            isDirty: false
        )
    }
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case edit
    case view
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .edit: return "Edit"
        case .view: return "View"
        case .split: return "Split"
        }
    }
}

enum TabLayout: String, CaseIterable, Identifiable {
    case top
    case left

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: return "Top"
        case .left: return "Left"
        }
    }
}

enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

extension UTType {
    static var markdownText: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}

#Preview {
    ContentView()
}
