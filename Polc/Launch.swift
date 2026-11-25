@main
enum Launch {
    static func main() {
        RenameMigration.beforeLaunch()
        PolcApp.main()
    }
}
