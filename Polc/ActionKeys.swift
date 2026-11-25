import Foundation

struct ActionKey<Key: Hashable & Codable>: Hashable, Codable {
    var key: Key
    var enabled: Bool
}

enum KeyClash<Action: Hashable>: Hashable {
    case action(Action)
    case resizeKey
}

enum ActionKeys {
    static func migrated<Action, Key>(enabledKeys: [Key], defaultKeys: [Action: Key]) -> [Action: ActionKey<Key>] {
        defaultKeys.mapValues { ActionKey(key: $0, enabled: enabledKeys.contains($0)) }
    }

    static func assign<Action, Key>(_ key: Key, to action: Action, in bindings: inout [Action: ActionKey<Key>], resizeKeys: Set<Key>) -> KeyClash<Action>? {
        if resizeKeys.contains(key) {
            return .resizeKey
        }
        if let other = bindings.first(where: { $0.key != action && $0.value.key == key })?.key {
            return .action(other)
        }
        bindings[action]?.key = key
        return nil
    }

    static func action<Action, Key>(for key: Key, in bindings: [Action: ActionKey<Key>]) -> Action? {
        bindings.first { $0.value.enabled && $0.value.key == key }?.key
    }
}
