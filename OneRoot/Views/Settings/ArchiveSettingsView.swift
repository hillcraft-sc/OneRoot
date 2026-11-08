import SwiftUI

/// Settings > Archives: which engine/format `ArchiveService.compress` uses,
/// and where its output goes. See `ArchiveSettingsService` for persistence
/// and `ArchiveTool`/`ArchiveFormat` for what each engine can do.
struct ArchiveSettingsView: View {
    @State private var tool: ArchiveTool = .appleDitto
    @State private var format: ArchiveFormat = .zip
    @State private var outputLocation: ArchiveOutputLocation = .sameAsSource
    @State private var fixedDirectory: URL?
    @State private var showingChooseFixedDirectory = false

    private let settings = ArchiveSettingsService()
    private let installedTools = ArchiveTool.allCases.filter(\.isInstalled)

    var body: some View {
        Form {
            Section {
                Picker("Compress Using", selection: $tool) {
                    ForEach(installedTools, id: \.self) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }
                .onChange(of: tool) { _, newValue in settings.setTool(newValue) }

                if tool != .appleDitto {
                    Picker("Format", selection: $format) {
                        ForEach(ArchiveFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .onChange(of: format) { _, newValue in settings.setFormat(newValue) }
                }
            }

            Section {
                Picker("Save Archive", selection: $outputLocation) {
                    Text("Next to the Original").tag(ArchiveOutputLocation.sameAsSource)
                    Text("A Fixed Folder").tag(ArchiveOutputLocation.fixedDirectory)
                    Text("Ask Every Time").tag(ArchiveOutputLocation.askEachTime)
                }
                .onChange(of: outputLocation) { _, newValue in settings.setOutputLocation(newValue) }

                if outputLocation == .fixedDirectory {
                    LabeledContent("Folder") {
                        HStack {
                            if let fixedDirectory {
                                Text(fixedDirectory.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Not Set")
                                    .foregroundStyle(.secondary)
                            }
                            Button("Choose…") { showingChooseFixedDirectory = true }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCurrentSelection)
        .sheet(isPresented: $showingChooseFixedDirectory) {
            FileChooserView(
                startingAt: fixedDirectory ?? FileManager.default.homeDirectoryForCurrentUser,
                canChooseFiles: false,
                canChooseDirectories: true,
                chooseButtonTitle: "Choose"
            ) { url in
                settings.setFixedDirectory(url)
                fixedDirectory = url
            }
        }
    }

    private func loadCurrentSelection() {
        tool = installedTools.contains(settings.tool()) ? settings.tool() : .appleDitto
        format = settings.format()
        outputLocation = settings.outputLocation()
        fixedDirectory = settings.fixedDirectory()
    }
}
