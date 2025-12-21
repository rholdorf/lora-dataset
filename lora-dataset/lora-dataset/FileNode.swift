//
//  FileNode.swift
//  lora-dataset
//
//  Created by Claude on 20/12/25.
//

import Foundation

struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var children: [FileNode]?  // nil = not loaded, [] = empty, [items] = loaded

    var name: String { url.lastPathComponent }
    var isDirectory: Bool { children != nil }

    var icon: String {
        if children == nil { return "doc" }
        return (children?.isEmpty == true) ? "folder" : "folder.fill"
    }

    // Hashable based on id only for proper List selection
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
