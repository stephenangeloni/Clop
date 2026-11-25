import Defaults
import Foundation
import Lowtech
import Sauce
import SwiftUI

enum GlobalAction: String, CaseIterable, Codable, LosslessStringConvertible {
    case downscale
    case speedUpVideo
    case stopAndDismiss
    case stopAndClearAll
    case bringBack
    case quickLook
    case rename
    case restoreOriginal
    case pause
    case optimiseClipboard
    case optimiseAggressively
    case crop

    init?(_ description: String) {
        self.init(rawValue: description)
    }

    static let defaultActionKeys = Dictionary(uniqueKeysWithValues: allCases.map { ($0, ActionKey(key: $0.defaultKey, enabled: true)) })

    var description: String { rawValue }

    var defaultKey: SauceKey {
        switch self {
        case .downscale: .minus
        case .speedUpVideo: .x
        case .stopAndDismiss: .delete
        case .stopAndClearAll: .escape
        case .bringBack: .equal
        case .quickLook: .space
        case .rename: .r
        case .restoreOriginal: .z
        case .pause: .p
        case .optimiseClipboard: .c
        case .optimiseAggressively: .a
        case .crop: .k
        }
    }

    var title: String {
        switch self {
        case .downscale: "Downscale"
        case .speedUpVideo: "Speed up video"
        case .stopAndDismiss: "Stop and Dismiss"
        case .stopAndClearAll: "Stop and Clear All"
        case .bringBack: "Bring Back"
        case .quickLook: "Quick Look"
        case .rename: "Rename"
        case .restoreOriginal: "Restore original"
        case .pause: "Pause optimisations"
        case .optimiseClipboard: "Optimise current clipboard"
        case .optimiseAggressively: "Optimise aggressively"
        case .crop: "Crop"
        }
    }

    var subtitle: String {
        switch self {
        case .downscale: "Decrease resolution of the last image or video"
        case .speedUpVideo: "Make video playback faster by dropping frames"
        case .stopAndDismiss: "Stop the last running action and dismiss the floating result"
        case .stopAndClearAll: "Stop running optimisations and clear all floating results"
        case .bringBack: "Bring back the last removed floating result"
        case .quickLook: "Preview the latest image or video"
        case .rename: "Rename the file of the latest image or video"
        case .restoreOriginal: "Revert optimisations and downscaling actions done on the latest image or video"
        case .pause: "Pause or stop automatic optimisations"
        case .optimiseClipboard: "Apply optimisations on the copied image, URL or path"
        case .optimiseAggressively: "Apply aggressive optimisations on the copied image, URL or path"
        case .crop: "Open the crop window for the latest image or video"
        }
    }
}

extension ActionKey: Defaults.Serializable {}

extension [GlobalAction: ActionKey<SauceKey>] {
    var complete: Self {
        GlobalAction.defaultActionKeys.merging(self) { $1 }
    }

    var enabledKeys: [SauceKey] {
        complete.values.filter(\.enabled).map(\.key)
    }
}

extension SauceKey {
    func label(heldWith modifiers: [TriggerKey]) -> String {
        let registeredKeyCode = Sauce.shared.keyCode(for: self, modifiers: .cocoa(modifiers.sideIndependentModifiers))
        return SauceKey(QWERTYKeyCode: Int(registeredKeyCode))?.character ?? character
    }

    func keyEquivalent(heldWith modifiers: [TriggerKey]) -> KeyEquivalent? {
        switch self {
        case .space: .space
        case .delete: .delete
        case .escape: .escape
        case .return: .return
        default: label(heldWith: modifiers).lowercased().first.map { KeyEquivalent($0) }
        }
    }
}
