import Foundation

@main
enum MergeFolders {
    static func main() {
        let arguments = CommandLine.arguments
        do {
            try FolderMerge.move(URL(fileURLWithPath: arguments[1]), into: URL(fileURLWithPath: arguments[2]))
        } catch {
            print(error)
            exit(1)
        }
    }
}
