//
// Renders the widget's states offscreen for the README, so the documentation
// images are reproducible instead of hand-captured.
//
//   make screenshots
//
import AppKit
import SwiftUI

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs"

/// Stands in for a desktop wallpaper behind the frosted panel. The real window
/// blurs whatever is actually on the desktop via NSVisualEffectView.
private struct Wallpaper<Content: View>: View {
    let content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.22, blue: 0.34),
                    Color(red: 0.36, green: 0.27, blue: 0.38),
                    Color(red: 0.12, green: 0.15, blue: 0.21)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            content
        }
    }
}

private struct Panel: View {
    let controller: SleepController

    var body: some View {
        ZStack {
            // Approximates the material the window gets for free at runtime.
            RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .frame(width: WidgetMetrics.size.width, height: WidgetMetrics.size.height)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            ToggleWidget(controller: controller)
        }
    }
}

@MainActor
private func write(_ view: some View, size: CGSize, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    guard
        let image = renderer.cgImage,
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            "public.png" as CFString,
            1,
            nil
        )
    else {
        FileHandle.standardError.write(Data("could not render \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(path)")
}

@main
struct MakeScreenshots {
    @MainActor
    static func main() {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDirectory),
            withIntermediateDirectories: true
        )

        let pair = Wallpaper(
            content: HStack(spacing: 44) {
                Panel(controller: .preview(blocked: false))
                Panel(controller: .preview(blocked: true))
            }
        )
        write(pair, size: CGSize(width: 560, height: 280), to: "\(outputDirectory)/states.png")

        let states: [(String, SleepController)] = [
            ("sleep-enabled", .preview(blocked: false)),
            ("sleep-blocked", .preview(blocked: true)),
            ("working", .preview(blocked: false, busy: true)),
            ("error", .preview(blocked: false, error: "pmset failed"))
        ]
        for (name, controller) in states {
            write(
                Wallpaper(content: Panel(controller: controller)),
                size: CGSize(width: 240, height: 240),
                to: "\(outputDirectory)/\(name).png"
            )
        }
    }
}
