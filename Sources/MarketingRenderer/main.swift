import AppBundle
import Foundation

@main
struct MarketingRendererCommand {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments.dropFirst()
        let outputPath = arguments.first ?? "resources/marketing/winmux-card-collage-swiftui.png"
        let outputURL = URL(fileURLWithPath: outputPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try renderWinMuxMarketingImage(to: outputURL)
        print(outputURL.path)
    }
}
