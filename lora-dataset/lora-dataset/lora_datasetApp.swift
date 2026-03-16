//
//  lora_datasetApp.swift
//  lora-dataset
//
//  Created by Rui Holdorf on 03/08/25.
//

import SwiftUI

// FocusedValueKey for ViewModel access in menu commands
struct DatasetViewModelKey: FocusedValueKey {
    typealias Value = DatasetViewModel
}

extension FocusedValues {
    var datasetViewModel: DatasetViewModel? {
        get { self[DatasetViewModelKey.self] }
        set { self[DatasetViewModelKey.self] = newValue }
    }
}

@main
struct lora_datasetApp: App {

    init() {
        // Suprime logs de sistema desnecessários durante desenvolvimento
        #if DEBUG
        setenv("OS_ACTIVITY_MODE", "disable", 1)
        setenv("CFNETWORK_DIAGNOSTICS", "0", 1)
        setenv("OS_SIGNPOST_ENABLED", "0", 1)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenFolderCommandView()
            }
            CommandGroup(replacing: .saveItem) {
                SaveCommandView()
                Divider()
                ReloadCaptionCommandView()
            }
            TextEditingCommands()
        }
    }
}

// Separate view for the Save command to access FocusedValues
struct SaveCommandView: View {
    @FocusedValue(\.datasetViewModel) private var viewModel: DatasetViewModel?

    var body: some View {
        if let vm = viewModel {
            SaveButtonView(viewModel: vm)
        } else {
            Button("Save") {}
                .keyboardShortcut("s", modifiers: .command)
                .disabled(true)
        }
    }
}

// Child view that observes the ViewModel to react to isDirty changes
struct SaveButtonView: View {
    @ObservedObject var viewModel: DatasetViewModel

    var body: some View {
        Button("Save") {
            viewModel.saveSelected()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!viewModel.selectedIsDirty)
    }
}

// Open folder command view
struct OpenFolderCommandView: View {
    @FocusedValue(\.datasetViewModel) private var viewModel: DatasetViewModel?

    var body: some View {
        Button("Open Folder...") {
            if let vm = viewModel {
                Task { await vm.chooseDirectory() }
            }
        }
        .keyboardShortcut("o", modifiers: .command)
        .disabled(viewModel == nil)
    }
}

// Reload caption command view
struct ReloadCaptionCommandView: View {
    @FocusedValue(\.datasetViewModel) private var viewModel: DatasetViewModel?

    var body: some View {
        Button("Reload Caption") {
            viewModel?.reloadCaptionForSelected()
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(viewModel?.selectedID == nil)
    }
}
