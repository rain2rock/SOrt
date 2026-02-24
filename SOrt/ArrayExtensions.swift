//
//  ArrayExtensions.swift
//  Array utility extensions
//

import Foundation

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
