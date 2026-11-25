import Foundation

enum Action: String, CaseIterable {
    case downscale, optimiseClipboard, optimiseAggressively
}

let defaultKeys: [Action: String] = [.downscale: "minus", .optimiseClipboard: "c", .optimiseAggressively: "a"]
let resizeKeys: Set<String> = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

func describe(_ bindings: [Action: ActionKey<String>]) -> String {
    Action.allCases.map { action in
        bindings[action].map { "\(action.rawValue)=\($0.key):\($0.enabled ? "on" : "off")" } ?? "\(action.rawValue)=missing"
    }.joined(separator: " ")
}

func enabledKeys(_ argument: String) -> [String] {
    argument.split(separator: ",").map(String.init)
}

@main
enum ActionKeysDriver {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "migrate":
            print(describe(ActionKeys.migrated(enabledKeys: enabledKeys(arguments[1]), defaultKeys: defaultKeys)))
        case "assign":
            var bindings = ActionKeys.migrated(enabledKeys: enabledKeys(arguments[1]), defaultKeys: defaultKeys)
            guard let action = Action(rawValue: arguments[2]) else { exit(2) }
            switch ActionKeys.assign(arguments[3], to: action, in: &bindings, resizeKeys: resizeKeys) {
            case .action(let other)?: print("taken by \(other.rawValue)")
            case .resizeKey?: print("taken by resize")
            case nil: print(describe(bindings))
            }
        case "press":
            let bindings = ActionKeys.migrated(enabledKeys: enabledKeys(arguments[1]), defaultKeys: defaultKeys)
            print(ActionKeys.action(for: arguments[2], in: bindings)?.rawValue ?? "nothing")
        default:
            print("unknown command")
            exit(2)
        }
    }
}
