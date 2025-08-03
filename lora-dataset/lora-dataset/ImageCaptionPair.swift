//
//  ImageCaptionPair.swift
//  lora-dataset
//
//  Created by Rui Holdorf on 03/08/25.
//


import Foundation

struct ImageCaptionPair: Identifiable, Hashable {
    let id = UUID()
    let imageURL: URL
    var captionURL: URL
    var captionText: String

    // Como todos os campos usados já são Hashable, o compilador sintetiza Hashable/Equatable.
    // Se quiser garantir que só o `id` determine identidade na seleção, pode customizar:

    static func == (lhs: ImageCaptionPair, rhs: ImageCaptionPair) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
