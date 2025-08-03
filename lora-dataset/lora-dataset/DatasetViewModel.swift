//
//  DatasetViewModel.swift
//  lora-dataset
//
//  Created by Rui Holdorf on 03/08/25.
//


import Foundation
import SwiftUI
import AppKit

@MainActor
class DatasetViewModel: ObservableObject {
    @Published var pairs: [ImageCaptionPair] = []
    @Published var selected: ImageCaptionPair? = nil
    @Published var directoryURL: URL? = nil
    let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "bmp", "tiff"]
    let supportedCaptionExtensions = ["txt", "caption"]

    func chooseDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Selecione o diretório do dataset"
        if panel.runModal() == .OK, let url = panel.url {
            directoryURL = url
            await scanDirectory(url)
        }
    }

    func scanDirectory(_ folder: URL) async {
        pairs = []
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }

        // Index captions by base name
        var captionMap: [String: URL] = [:]
        for file in contents {
            let ext = file.pathExtension.lowercased()
            if supportedCaptionExtensions.contains(ext) {
                let base = file.deletingPathExtension().lastPathComponent
                captionMap[base] = file
            }
        }

        var newPairs: [ImageCaptionPair] = []
        for file in contents {
            let ext = file.pathExtension.lowercased()
            if supportedImageExtensions.contains(ext) {
                let base = file.deletingPathExtension().lastPathComponent
                let captionURL: URL
                if let existing = captionMap[base] {
                    captionURL = existing
                } else {
                    // default caption file path: same name .txt
                    captionURL = folder.appendingPathComponent("\(base).txt")
                }

                var captionText = ""
                if FileManager.default.fileExists(atPath: captionURL.path) {
                    captionText = (try? String(contentsOf: captionURL, encoding: .utf8)) ?? ""
                }
                let pair = ImageCaptionPair(imageURL: file, captionURL: captionURL, captionText: captionText)
                newPairs.append(pair)
            }
        }

        // Sort alphabetically
        newPairs.sort { $0.imageURL.lastPathComponent < $1.imageURL.lastPathComponent }
        pairs = newPairs
        selected = pairs.first
    }

    func save(_ pair: ImageCaptionPair) {
        do {
            try pair.captionText.write(to: pair.captionURL, atomically: true, encoding: .utf8)
            // Update in array
            if let idx = pairs.firstIndex(of: pair) {
                pairs[idx] = pair
                selected = pairs[idx]
            }
        } catch {
            print("Erro ao salvar caption: \(error)")
        }
    }

    func reloadSelectedCaption() {
        guard var sel = selected else { return }
        if FileManager.default.fileExists(atPath: sel.captionURL.path) {
            sel.captionText = (try? String(contentsOf: sel.captionURL, encoding: .utf8)) ?? ""
            if let idx = pairs.firstIndex(of: sel) {
                pairs[idx] = sel
                selected = sel
            }
        }
    }
}