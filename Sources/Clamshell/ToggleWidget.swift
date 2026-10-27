import SwiftUI

extension Color {
    /// Sleep behaves normally — the safe, default state.
    static let clamshellGreen = Color(red: 0.20, green: 0.84, blue: 0.47)
    /// Lid sleep is blocked — the Mac will not sleep when the lid closes.
    static let clamshellRed = Color(red: 1.00, green: 0.27, blue: 0.31)
    /// Something went wrong, or the state could not be read.
    static let clamshellAmber = Color(red: 1.00, green: 0.69, blue: 0.18)
}

/// The entire interface: one glowing ring, no text.
///
/// State is communicated by colour (green = sleeps normally, red = lid sleep
/// blocked) and by the glyph in the middle. Everything textual lives in the
/// tooltip, the accessibility labels and the menu, so the widget itself stays
/// clean enough to sit on a wallpaper.
struct ToggleWidget: View {
    @ObservedObject var controller: SleepController

    @State private var isHovering = false
    @State private var isSpinning = false

    private let diameter: CGFloat = 104
    private let ringWidth: CGFloat = 6

    private var isAlerting: Bool {
        controller.errorMessage != nil || !controller.isReadable
    }

    private var accent: Color {
        if isAlerting { return .clamshellAmber }
        return controller.isBlocked ? .clamshellRed : .clamshellGreen
    }

    private var symbol: String {
        if isAlerting { return "exclamationmark.triangle.fill" }
        // Moon = the Mac sleeps normally; sun = it is being kept awake.
        return controller.isBlocked ? "sun.max.fill" : "moon.zzz.fill"
    }

    var body: some View {
        ZStack {
            WidgetBackground()

            Button(action: controller.toggle) {
                ring
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(controller.isBusy)
            .onHover { isHovering = $0 }
        }
        .frame(width: WidgetMetrics.size.width, height: WidgetMetrics.size.height)
        .help(controller.statusDescription)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lid sleep")
        .accessibilityValue(controller.isBlocked ? "Blocked" : "Enabled")
        .accessibilityHint("Toggles whether the Mac sleeps when the lid is closed.")
        .accessibilityAddTraits(.isButton)
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: controller.isBlocked)
        .animation(.easeInOut(duration: 0.25), value: isAlerting)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onAppear { isSpinning = true }
    }

    private var ring: some View {
        ZStack {
            // Soft bloom spilling onto the frosted backdrop.
            Circle()
                .fill(accent)
                .frame(width: diameter, height: diameter)
                .blur(radius: 24)
                .opacity(isHovering ? 0.45 : 0.3)

            // Recessed well the ring sits in.
            Circle()
                .fill(Color.black.opacity(0.18))
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.10), .white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .frame(width: diameter, height: diameter)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: ringWidth)
                .frame(width: diameter, height: diameter)

            // The indicator itself.
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            accent.opacity(0.45), accent, accent.opacity(0.45)
                        ]),
                        center: .center,
                        angle: .degrees(-90)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: accent.opacity(0.55), radius: 12)
                .shadow(color: accent.opacity(0.30), radius: 24)
                .opacity(controller.isBusy ? 0.35 : 1)

            if controller.isBusy {
                Circle()
                    .trim(from: 0, to: 0.2)
                    .stroke(
                        Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 0.85).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
            }

            Image(systemName: symbol)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.35), radius: 5, y: 1)
                .id(symbol)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .frame(width: diameter + ringWidth, height: diameter + ringWidth)
        .scaleEffect(isHovering && !controller.isBusy ? 1.04 : 1)
        .contentShape(Circle())
    }
}

/// Frosted panel edge. The blur itself comes from the `NSVisualEffectView`
/// behind this view; this only draws the hairline and inner highlight that make
/// it read as a native widget.
private struct WidgetBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .allowsHitTesting(false)
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum WidgetMetrics {
    static let size = CGSize(width: 168, height: 168)
    static let cornerRadius: CGFloat = 28
    /// Inset from the bottom-right of the screen the first time the app runs.
    static let screenInset: CGFloat = 24
}
