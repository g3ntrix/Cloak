import SwiftUI
import MapKit

// MARK: - Connection route diagram

/// One dot traveling along a link. `link` indexes which connector it belongs to
/// (0 = Mac→Cloudflare, 1 = Cloudflare→proxy, 2 = proxy→Internet).
struct RoutePacket: Identifiable {
    let id = UUID()
    let link: Int
    let birth: TimeInterval
    let life: TimeInterval     // seconds to cross the link
    let reverse: Bool          // true = right→left (download)
    let size: CGFloat
}

/// Visualizes the tunnel path: This Mac → Cloudflare edge (Fake SNI) → proxy
/// server → Internet (egress). Dots flow along the links while connected.
///
/// A single 10 Hz clock owned here schedules pulses for all three links; each
/// connector only runs a per-frame `TimelineView` while it actually holds a
/// packet, so idle gaps (and a backgrounded window) cost no continuous redraw.
struct ConnectionRouteCard: View {
    @EnvironmentObject var app: AppState
    @Environment(\.controlActiveState) private var controlActive

    private var active: Bool { app.status.isRunning }

    @State private var packets: [RoutePacket] = []
    @State private var lastSpawn: [TimeInterval] = [0, 0, 0]
    @State private var gap: [TimeInterval] = [0.6, 0.6, 0.6]

    private static let linkTints: [Color] = [.blue, .indigo, .mint]

    private let spawnClock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Connection route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(active ? "Active" : "Idle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(active ? Color.green : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill((active ? Color.green : Color.secondary).opacity(0.15))
                        )
                }
                HStack(alignment: .top, spacing: 4) {
                    routeNode(icon: "laptopcomputer", primary: "This Mac", secondary: "Origin", tint: .secondary)
                    connector(0)
                    routeNode(icon: "cloud.fill", primary: "Cloudflare",
                              secondary: app.listenerProject.FAKE_SNI, tint: .orange)
                    connector(1)
                    routeNode(icon: "server.rack", primary: app.activeProfile?.name ?? "Server",
                              secondary: "Proxy node", tint: .purple)
                    connector(2)
                    routeNode(icon: "globe", primary: internetPrimary,
                              secondary: app.egressIP ?? "—", tint: .mint)
                }
            }
        }
        .onReceive(spawnClock) { date in tick(now: date.timeIntervalSinceReferenceDate) }
        .onChange(of: active) { if !$0 { packets.removeAll() } }
        .onChange(of: app.settings.reduceAnimations) { if $0 { packets.removeAll() } }
    }

    private func connector(_ link: Int) -> some View {
        RouteFlowConnector(tint: Self.linkTints[link],
                           packets: packets.filter { $0.link == link })
    }

    // MARK: - Spawning (single shared clock)

    /// Whether pulses should be generated: connected, window focused, and the
    /// user hasn't opted into reduced animations.
    private var animating: Bool {
        active && controlActive != .inactive && !app.settings.reduceAnimations
    }

    private func tick(now: TimeInterval) {
        guard animating else {
            if !packets.isEmpty { packets.removeAll() }
            return
        }
        var next = packets.filter { now - $0.birth <= $0.life }
        var changed = next.count != packets.count
        for link in 0 ..< 3 {
            if lastSpawn[link] == 0 { lastSpawn[link] = now; gap[link] = nextGap() }
            if now - lastSpawn[link] >= gap[link] {
                next.append(makePacket(link: link, now: now))
                lastSpawn[link] = now
                gap[link] = nextGap()
                changed = true
            }
        }
        // Only touch @State when something actually changed, so idle gaps don't
        // trigger 10×/s re-renders.
        if changed { packets = next }
    }

    private func makePacket(link: Int, now: TimeInterval) -> RoutePacket {
        let base = 1.7 - intensity * 1.1                 // ~1.7s idle → ~0.6s busy
        let life = base * Double.random(in: 0.82 ... 1.18)
        let reverse = Double.random(in: 0 ... 1) < downRatio
        let size = CGFloat(Double.random(in: 4.0 ... 5.5))
        return RoutePacket(link: link, birth: now, life: life, reverse: reverse, size: size)
    }

    /// Time until the next packet on a link — short under load, a slow heartbeat when idle.
    private func nextGap() -> TimeInterval {
        if intensity <= 0 {
            return Double.random(in: 2.4 ... 4.0)        // idle heartbeat
        }
        let lo = 0.75 - intensity * 0.47                 // busy → ~0.28–0.7s
        let hi = 1.8 - intensity * 1.1                   // light → ~0.8–1.8s
        return Double.random(in: lo ... max(lo + 0.05, hi))
    }

    /// 0 (idle) … 1 (heavy traffic) on a log scale — drives pulse cadence.
    private var intensity: Double {
        guard active else { return 0 }
        let rate = app.downloadBytesPerSec + app.uploadBytesPerSec
        if rate < 1_000 { return 0 }
        let scaled = log10(rate / 1_000) / log10(4_000)  // ~1KB/s → 0, ~4MB/s → 1
        return min(1, max(0.04, scaled))
    }

    /// Share of traffic that is download — biases pulse direction.
    private var downRatio: Double {
        let total = app.downloadBytesPerSec + app.uploadBytesPerSec
        return total > 0 ? app.downloadBytesPerSec / total : 0.5
    }

    private var internetPrimary: String {
        if active, let cc = app.egressCountry, !cc.isEmpty {
            return "\(flagEmoji(cc)) \(cc.uppercased())"
        }
        return "Internet"
    }

    private func routeNode(icon: String, primary: String, secondary: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill((active ? tint : Color.secondary).opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? tint : Color.secondary)
            }
            Text(primary)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(secondary)
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 74)
    }
}

/// A dashed link that renders the packets handed to it by `ConnectionRouteCard`.
/// It owns no timer: when there are no packets it draws a static track, and it
/// only spins up a per-frame `TimelineView` while packets are actually in
/// flight. Each packet eases across the link and fades in/out, with direction
/// already baked in (download flows right→left back toward the Mac).
struct RouteFlowConnector: View {
    var tint: Color
    var packets: [RoutePacket]

    var body: some View {
        Group {
            if packets.isEmpty {
                Canvas { gc, size in drawTrack(gc, size) }
            } else {
                TimelineView(.animation) { context in
                    Canvas { gc, size in
                        drawTrack(gc, size)
                        render(gc, size, now: context.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
    }

    // MARK: - Rendering

    private func render(_ gc: GraphicsContext, _ size: CGSize, now: TimeInterval) {
        let y = size.height / 2
        for p in packets {
            let age = now - p.birth
            guard age >= 0, age <= p.life else { continue }
            let progress = age / p.life
            let eased = smoothstep(progress)
            let xFrac = p.reverse ? (1 - eased) : eased
            let x = CGFloat(xFrac) * size.width
            let alpha = envelope(progress)
            let r = p.size / 2

            // Soft glow trailing the head for a sense of motion.
            let glow = CGRect(x: x - r * 1.8, y: y - r * 1.8,
                              width: r * 3.6, height: r * 3.6)
            gc.fill(Path(ellipseIn: glow), with: .color(tint.opacity(0.18 * alpha)))

            let dot = CGRect(x: x - r, y: y - r, width: p.size, height: p.size)
            gc.fill(Path(ellipseIn: dot), with: .color(tint.opacity(alpha)))
        }
    }

    /// Fade in over the first 18% and out over the last 22% of life.
    private func envelope(_ t: Double) -> Double {
        if t < 0.18 { return t / 0.18 }
        if t > 0.78 { return max(0, (1 - t) / 0.22) }
        return 1
    }

    private func smoothstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    private func drawTrack(_ gc: GraphicsContext, _ size: CGSize) {
        let y = size.height / 2
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        gc.stroke(path, with: .color(.gray.opacity(0.3)),
                  style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }
}

// MARK: - Egress map

private struct EgressPoint: Identifiable {
    let coordinate: CLLocationCoordinate2D
    /// Stable across re-renders so MapKit keeps the same annotation (no flicker);
    /// only changes when the egress location actually moves.
    var id: String { "\(coordinate.latitude),\(coordinate.longitude)" }
}

/// A small map that drops a pulsing pin at the egress IP's location.
struct EgressMapCard: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25, longitude: 10),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120)
    )

    private var coordinate: CLLocationCoordinate2D? {
        guard app.status.isRunning, let lat = app.egressLat, let lon = app.egressLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        Card(maxHeight: .infinity, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Exit location", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if let label = locationLabel {
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ZStack {
                    if let coord = coordinate {
                        Map(coordinateRegion: $region,
                            interactionModes: [],
                            annotationItems: [EgressPoint(coordinate: coord)]) { point in
                            MapAnnotation(coordinate: point.coordinate) {
                                MapPulseDot(animated: !app.settings.reduceAnimations)
                            }
                        }
                        .allowsHitTesting(false)
                    } else {
                        placeholder
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.stroke(for: colorScheme))
                )
            }
        }
        .onAppear { updateRegion(animated: false) }
        .onChange(of: app.egressLat) { _ in updateRegion(animated: true) }
        .onChange(of: app.egressLon) { _ in updateRegion(animated: true) }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.controlFill(for: colorScheme))
            VStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(app.status.isRunning ? "Locating exit…" : "Connect to see your exit location")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var locationLabel: String? {
        guard app.status.isRunning else { return nil }
        let cc = (app.egressCountry ?? "").uppercased()
        let flag = cc.isEmpty ? "" : "\(flagEmoji(cc)) "
        if let city = app.egressCity, !city.isEmpty {
            return cc.isEmpty ? city : "\(flag)\(city), \(cc)"
        }
        return cc.isEmpty ? nil : "\(flag)\(cc)"
    }

    private func updateRegion(animated: Bool) {
        guard let coord = coordinate else { return }
        let target = MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)
        )
        if animated, !app.settings.reduceAnimations {
            withAnimation(.easeInOut(duration: 0.6)) { region = target }
        } else {
            region = target
        }
    }
}

/// A green dot for the map annotation. When `animated`, a halo pulses outward;
/// otherwise just the static dot is shown to avoid the repeating animation.
private struct MapPulseDot: View {
    var animated: Bool
    @State private var pulse = false
    var body: some View {
        ZStack {
            if animated {
                Circle()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulse ? 1.3 : 0.7)
                    .opacity(pulse ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .shadow(color: .green.opacity(0.7), radius: 5)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        }
        .onAppear { if animated { pulse = true } }
    }
}

// MARK: - Shared helpers

/// ISO 3166-1 alpha-2 code → regional-indicator flag emoji.
func flagEmoji(_ code: String) -> String {
    let cc = code.trimmingCharacters(in: .whitespaces).uppercased()
    guard cc.count == 2, cc.allSatisfy({ $0.isLetter }) else { return "" }
    return cc.unicodeScalars.reduce(into: "") { result, scalar in
        if let flagScalar = UnicodeScalar(127_397 + scalar.value) {
            result.unicodeScalars.append(flagScalar)
        }
    }
}
