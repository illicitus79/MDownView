//
//  ContentView.swift
//  MdownView
//
//  Created by Pankaj Nagekar on 02/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import MarkdownUI
import AppKit

struct ContentView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    @AppStorage("preferredColorScheme") private var preferredColorScheme: ColorSchemePreference = .system
    @AppStorage("defaultEditorMode") private var defaultEditorMode: EditorMode = .split
    @AppStorage("defaultSplitVariant") private var defaultSplitVariant: SplitVariant = .standard
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
                .help("Create a new tab")

                Button(action: { isImporterPresented = true }) {
                    Label("Open", systemImage: "folder")
                }
                .keyboardShortcut("o", modifiers: .command)
                .help("Open one or more markdown files")

                Button(action: saveActiveTab) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save the current tab")

                Button(action: saveAllTabs) {
                    Label("Save All", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .help("Save all tabs with a file location")

                Button(action: saveActiveTabAs) {
                    Label("Save As", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
                .help("Save the current tab as a new file")
            }

            ToolbarItemGroup {
                Picker("Mode", selection: activeEditorModeBinding) {
                    ForEach(EditorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .help("Switch between edit, view, and split modes")

                if activeEditorMode == .split {
                    Toggle(isOn: Binding(
                        get: { activeSplitVariant == .convert },
                        set: { setActiveSplitVariant($0 ? .convert : .standard) }
                    )) {
                        Label("Convert", systemImage: "arrow.left.arrow.right")
                    }
                    .toggleStyle(.button)
                    .help("Convert rich text from the clipboard into markdown")
                }

                Picker("Tabs", selection: $tabLayout) {
                    ForEach(TabLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .help("Move tabs to the top or left")

                Picker("Theme", selection: $preferredColorScheme) {
                    ForEach(ColorSchemePreference.allCases) { preference in
                        Label(preference.label, systemImage: preference.icon)
                            .tag(preference)
                    }
                }
                .pickerStyle(.menu)
                .help("Override light or dark appearance")
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
                        .help("Create a new tab")
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
                        .help("Create a new tab")
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
            .help("Close this tab")
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
            switch tab.editorMode {
            case .edit:
                editorView(text: bindingForActiveTab(), theme: theme)
            case .view:
                previewView(text: tab.content, theme: theme)
            case .split:
                if tab.splitVariant == .standard {
                    HSplitView {
                        editorView(text: bindingForActiveTab(), theme: theme)
                            .frame(minWidth: 280)
                        previewView(text: tab.content, theme: theme)
                            .frame(minWidth: 280)
                    }
                } else {
                    VStack(spacing: 0) {
                        convertToolbar(theme: theme)
                        HSplitView {
                            if tab.isSplitSwapped {
                                markdownOutputView(text: convertedMarkdown, theme: theme)
                                    .frame(minWidth: 280)
                                richTextInputView(theme: theme)
                                    .frame(minWidth: 280)
                            } else {
                                richTextInputView(theme: theme)
                                    .frame(minWidth: 280)
                                markdownOutputView(text: convertedMarkdown, theme: theme)
                                    .frame(minWidth: 280)
                            }
                        }
                    }
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

    private func richTextInputView(theme: Theme) -> some View {
        ZStack(alignment: .topLeading) {
            RichTextEditor(
                text: richTextInputBinding(),
                baseFont: .systemFont(ofSize: 16),
                textColor: NSColor(theme.textPrimary).withAlphaComponent(1.0)
            )
                .background(theme.editorBackground)
            if richTextInput.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Paste rich text here")
                    .font(.custom(theme.uiFont, size: 13))
                    .foregroundStyle(theme.textMuted)
                    .padding(24)
                    .allowsHitTesting(false)
            }
        }
        .background(theme.editorBackground)
    }

    private func markdownOutputView(text: String, theme: Theme) -> some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Markdown output will appear here")
                    .font(.custom(theme.uiFont, size: 13))
                    .foregroundStyle(theme.textMuted)
                    .padding(24)
                    .allowsHitTesting(false)
            }

            ScrollView {
                Text(text)
                    .font(.custom(theme.editorFont, size: 14))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
        }
        .background(theme.previewBackground)
    }

    private func convertToolbar(theme: Theme) -> some View {
        HStack(spacing: 12) {
            Label("Rich Text → Markdown", systemImage: "text.alignleft")
                .font(.custom(theme.uiFont, size: 12))
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Button(action: toggleSplitSwap) {
                Label("Swap Panes", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered)
            .help("Swap the rich text and markdown panes")

            Button(action: openConvertedMarkdownInNewTab) {
                Label("Open in New Tab", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .help("Create a new tab from the converted markdown")

            Button(action: copyConvertedMarkdown) {
                Label("Copy Markdown", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .help("Copy the converted markdown to the clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.panelBackground)
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

    private var activeEditorMode: EditorMode {
        guard let index = activeTabIndex else { return defaultEditorMode }
        return tabs[index].editorMode
    }

    private var activeSplitVariant: SplitVariant {
        guard let index = activeTabIndex else { return defaultSplitVariant }
        return tabs[index].splitVariant
    }

    private var activeEditorModeBinding: Binding<EditorMode> {
        Binding<EditorMode>(
            get: { activeEditorMode },
            set: { setActiveEditorMode($0) }
        )
    }

    private var richTextInput: NSAttributedString {
        guard let index = activeTabIndex else { return NSAttributedString(string: "") }
        return tabs[index].richTextInput
    }

    private func richTextInputBinding() -> Binding<NSAttributedString> {
        Binding<NSAttributedString>(
            get: { richTextInput },
            set: { updateActiveRichText($0) }
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
        let tab = MarkdownTab.newTab(
            editorMode: defaultEditorMode,
            splitVariant: defaultSplitVariant
        )
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

    private func saveAllTabs() {
        var unsavedCount = 0

        for tab in tabs where tab.isDirty {
            if let url = tab.url {
                write(tab: tab, to: url)
            } else {
                unsavedCount += 1
            }
        }

        if unsavedCount > 0 {
            presentError("Save All skipped \(unsavedCount) tabs without a file location. Use Save As for those tabs.")
        }
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

    private var convertedMarkdown: String {
        markdown(from: richTextInput, baseFontSize: 16)
    }

    private func copyConvertedMarkdown() {
        let markdown = convertedMarkdown
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func openConvertedMarkdownInNewTab() {
        let markdown = convertedMarkdown
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var tab = MarkdownTab.newTab()
        tab.title = deriveTitle(from: markdown) ?? "Converted"
        tab.content = markdown
        tab.isDirty = true
        tab.editorMode = defaultEditorMode
        tab.splitVariant = defaultSplitVariant
        tabs.append(tab)
        selectedTabID = tab.id
        setActiveSplitVariant(.standard)
    }

    private func markdown(from attributed: NSAttributedString, baseFontSize: CGFloat) -> String {
        guard attributed.length > 0 else { return "" }

        let fullString = attributed.string as NSString
        var output: [String] = []
        var index = 0
        var orderedCounters: [ObjectIdentifier: Int] = [:]
        while index < attributed.length {
            let paragraphRange = fullString.paragraphRange(for: NSRange(location: index, length: 0))
            let paragraph = attributed.attributedSubstring(from: paragraphRange)
            let paragraphText = paragraph.string.trimmingCharacters(in: .newlines)
            if paragraphText.isEmpty {
                output.append("")
                index = paragraphRange.upperBound
                continue
            }

            var prefix = ""
            if let style = paragraph.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
               let textList = style.textLists.first {
                if textList.markerFormat == .decimal {
                    let key = ObjectIdentifier(textList)
                    let nextValue = (orderedCounters[key] ?? 0) + 1
                    orderedCounters[key] = nextValue
                    prefix = "\(nextValue). "
                } else {
                    prefix = "- "
                }
            }

            let trimmedParagraph = trimLeadingWhitespace(paragraph)
            let inlineMarkdown = markdownInline(from: trimmedParagraph)
            let listContext = listContext(for: trimmedParagraph)
            let contentForParagraph = stripListMarker(from: trimmedParagraph, context: listContext)
            let contentMarkdown = markdownInline(from: contentForParagraph)
            if let headingPrefix = headingPrefix(for: contentForParagraph, baseFontSize: baseFontSize) {
                output.append("\(headingPrefix) \(contentMarkdown)")
            } else {
                output.append(prefix + contentMarkdown)
            }
            index = paragraphRange.upperBound
        }

        return output.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownInline(from attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, range, _ in
            let substring = attributed.attributedSubstring(from: range).string
            let cleaned = escapeMarkdown(substring)

            let font = attributes[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isMonospace = font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false

            let (leadingWhitespace, coreText, trailingWhitespace) = splitWhitespace(cleaned)
            guard !coreText.isEmpty else {
                result += cleaned
                return
            }

            var decorated = coreText
            if isBold && isItalic {
                decorated = "***\(decorated)***"
            } else if isBold {
                decorated = "**\(decorated)**"
            } else if isItalic {
                decorated = "*\(decorated)*"
            }

            if isMonospace {
                decorated = "`\(decorated)`"
            }

            if let link = attributes[.link] as? URL {
                decorated = "[\(decorated)](\(link.absoluteString))"
            } else if let linkString = attributes[.link] as? String {
                decorated = "[\(decorated)](\(linkString))"
            }

            result += leadingWhitespace + decorated + trailingWhitespace
        }
        return result
    }

    private func headingPrefix(for attributed: NSAttributedString, baseFontSize: CGFloat) -> String? {
        guard let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return nil }
        let size = font.pointSize

        if size >= baseFontSize + 10 {
            return "#"
        }
        if size >= baseFontSize + 6 {
            return "##"
        }
        if size >= baseFontSize + 3 {
            return "###"
        }

        return nil
    }

    private func trimLeadingWhitespace(_ attributed: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let text = mutable.string as NSString
        var index = 0

        while index < text.length {
            guard let scalar = UnicodeScalar(text.character(at: index)) else { break }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                index += 1
            } else {
                break
            }
        }

        if index > 0 {
            mutable.deleteCharacters(in: NSRange(location: 0, length: index))
        }

        return mutable
    }

    private enum ListMarkerContext {
        case ordered
        case unordered
        case none
    }

    private func listContext(for attributed: NSAttributedString) -> ListMarkerContext {
        guard let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
              let textList = style.textLists.first else {
            return .none
        }

        return textList.markerFormat == .decimal ? .ordered : .unordered
    }

    private func stripListMarker(from attributed: NSAttributedString, context: ListMarkerContext) -> NSAttributedString {
        guard context != .none else { return attributed }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        let text = mutable.string as NSString
        var index = 0

        while index < text.length {
            guard let scalar = UnicodeScalar(text.character(at: index)) else { break }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                index += 1
            } else {
                break
            }
        }

        if index >= text.length { return mutable }

        if context == .ordered {
            var digitEnd = index
            while digitEnd < text.length {
                guard let scalar = UnicodeScalar(text.character(at: digitEnd)),
                      CharacterSet.decimalDigits.contains(scalar) else { break }
                digitEnd += 1
            }

            if digitEnd > index {
                if digitEnd < text.length {
                    let separator = text.character(at: digitEnd)
                    if separator == 46 || separator == 41 || separator == 58 { // '.', ')', ':'
                        digitEnd += 1
                    }
                }

                while digitEnd < text.length {
                    guard let scalar = UnicodeScalar(text.character(at: digitEnd)),
                          CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
                    digitEnd += 1
                }

                mutable.deleteCharacters(in: NSRange(location: 0, length: digitEnd))
                return mutable
            }
        }

        let bullet = text.character(at: index)
        if bullet == 45 || bullet == 42 || bullet == 8226 { // '-', '*', '•'
            var end = index + 1
            while end < text.length {
                guard let scalar = UnicodeScalar(text.character(at: end)),
                      CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
                end += 1
            }
            mutable.deleteCharacters(in: NSRange(location: 0, length: end))
        }

        return mutable
    }

    private func splitWhitespace(_ text: String) -> (String, String, String) {
        let scalars = text.unicodeScalars
        var startIndex = scalars.startIndex
        var endIndex = scalars.endIndex

        while startIndex < scalars.endIndex,
              CharacterSet.whitespacesAndNewlines.contains(scalars[startIndex]) {
            startIndex = scalars.index(after: startIndex)
        }

        while endIndex > startIndex {
            let before = scalars.index(before: endIndex)
            if CharacterSet.whitespacesAndNewlines.contains(scalars[before]) {
                endIndex = before
            } else {
                break
            }
        }

        let leading = String(scalars[scalars.startIndex..<startIndex])
        let core = String(scalars[startIndex..<endIndex])
        let trailing = String(scalars[endIndex..<scalars.endIndex])
        return (leading, core, trailing)
    }

    private func escapeMarkdown(_ text: String) -> String {
        let replacements: [(String, String)] = [
            ("\\", "\\\\"),
            ("`", "\\`"),
            ("[", "\\["),
            ("]", "\\]")
        ]

        return replacements.reduce(text) { partial, pair in
            partial.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    private func setActiveEditorMode(_ newValue: EditorMode) {
        guard let index = activeTabIndex else { return }
        tabs[index].editorMode = newValue
    }

    private func setActiveSplitVariant(_ newValue: SplitVariant) {
        guard let index = activeTabIndex else { return }
        tabs[index].splitVariant = newValue
    }

    private func updateActiveRichText(_ newValue: NSAttributedString) {
        guard let index = activeTabIndex else { return }
        tabs[index].richTextInput = newValue
    }

    private func toggleSplitSwap() {
        guard let index = activeTabIndex else { return }
        tabs[index].isSplitSwapped.toggle()
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    let baseFont: NSFont
    let textColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isAutomaticDataDetectionEnabled = true
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.delegate = context.coordinator
        textView.font = baseFont
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: textColor
        ]
        textView.textStorage?.setAttributedString(normalizedAttributedString(text))

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if !textView.attributedString().isEqual(to: text) {
            textView.textStorage?.setAttributedString(normalizedAttributedString(text))
        }
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: textColor
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: RichTextEditor
        private var isNormalizing = false

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if isNormalizing { return }
            isNormalizing = true
            let normalized = parent.normalizedAttributedString(textView.attributedString())
            if !textView.attributedString().isEqual(to: normalized) {
                textView.textStorage?.setAttributedString(normalized)
            }
            parent.text = normalized
            isNormalizing = false
        }
    }

    private func normalizedAttributedString(_ input: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: input)
        let fullRange = NSRange(location: 0, length: mutable.length)
        let fontManager = NSFontManager.shared

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let currentFont = (value as? NSFont) ?? baseFont
            let traits = currentFont.fontDescriptor.symbolicTraits
            var newFont = baseFont

            if traits.contains(.bold) {
                newFont = fontManager.convert(newFont, toHaveTrait: .boldFontMask)
            }
            if traits.contains(.italic) {
                newFont = fontManager.convert(newFont, toHaveTrait: .italicFontMask)
            }

            mutable.addAttribute(.font, value: newFont, range: range)
        }

        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        return mutable
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
    var editorMode: EditorMode
    var splitVariant: SplitVariant
    var isSplitSwapped: Bool
    var richTextInput: NSAttributedString

    init(id: UUID = UUID(), url: URL? = nil, title: String, content: String, isDirty: Bool) {
        self.id = id
        self.url = url
        self.title = title
        self.content = content
        self.isDirty = isDirty
        self.editorMode = .split
        self.splitVariant = .standard
        self.isSplitSwapped = false
        self.richTextInput = NSAttributedString(string: "")
    }

    static func newTab(
        editorMode: EditorMode = .split,
        splitVariant: SplitVariant = .standard
    ) -> MarkdownTab {
        var tab = MarkdownTab(
            title: "Untitled",
            content: "# Untitled\n\nStart writing your markdown here.\n\n- Add headings, lists, and code blocks\n- Toggle split view to preview\n- Save when you're ready",
            isDirty: false
        )
        tab.editorMode = editorMode
        tab.splitVariant = splitVariant
        return tab
    }

    static func == (lhs: MarkdownTab, rhs: MarkdownTab) -> Bool {
        lhs.id == rhs.id &&
            lhs.url == rhs.url &&
            lhs.title == rhs.title &&
            lhs.content == rhs.content &&
            lhs.isDirty == rhs.isDirty &&
            lhs.editorMode == rhs.editorMode &&
            lhs.splitVariant == rhs.splitVariant &&
            lhs.isSplitSwapped == rhs.isSplitSwapped &&
            lhs.richTextInput.isEqual(to: rhs.richTextInput)
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

enum SplitVariant: String, CaseIterable, Identifiable {
    case standard
    case convert

    var id: String { rawValue }
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
