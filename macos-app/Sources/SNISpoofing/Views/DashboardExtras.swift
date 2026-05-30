import SwiftUI
import MapKit

// MARK: - Connection route diagram

/// Visualizes the tunnel path: This Mac → Cloudflare edge (Fake SNI) → proxy
/// server → Internet (egress). Dots flow along the links while connected.
struct ConnectionRouteCard: View {
    @EnvironmentObject var app: AppState

    private var active: Bool { app.status.isRunning }

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
                    RouteFlowConnector(active: active, tint: .blue)
                    routeNode(icon: "cloud.fill", primary: "Cloudflare",
                              secondary: app.listenerProject.FAKE_SNI, tint: .orange)
                    RouteFlowConnector(active: active, tint: .indigo)
                    routeNode(icon: "server.rack", primary: app.activeProfile?.name ?? "Server",
                              secondary: "Proxy node", tint: .purple)
                    RouteFlowConnector(active: active, tint: .mint)
                    routeNode(icon: "globe", primary: internetPrimary,
                              secondary: app.egressIP ?? "—", tint: .mint)
                }
            }
        }
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

/// A dashed link with dots that travel left→right while `active`.
struct RouteFlowConnector: View {
    var active: Bool
    var tint: Color

    var body: some View {
        Group {
            if active {
                TimelineView(.animation) { context in
                    Canvas { gc, size in
                        drawTrack(gc, size)
                        let t = context.date.timeIntervalSinceReferenceDate
                        let count = 3
                        for i in 0 ..< count {
                            let phase = (t * 0.55 + Double(i) / Double(count))
                                .truncatingRemainder(dividingBy: 1)
                            let x = CGFloat(phase) * size.width
                            let dot = CGRect(x: x - 2.5, y: size.height / 2 - 2.5, width: 5, height: 5)
                            gc.fill(Path(ellipseIn: dot), with: .color(tint))
                        }
                    }
                }
            } else {
                Canvas { gc, size in drawTrack(gc, size) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
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
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
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
        Card(padding: 12) {
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
                            MapAnnotation(coordinate: point.coordinate) { MapPulseDot() }
                        }
                        .allowsHitTesting(false)
                    } else {
                        placeholder
                    }
                }
                .frame(height: 150)
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
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { region = target }
        } else {
            region = target
        }
    }
}

/// A green dot with a repeating pulse halo for the map annotation.
private struct MapPulseDot: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 34, height: 34)
                .scaleEffect(pulse ? 1.3 : 0.7)
                .opacity(pulse ? 0 : 0.8)
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .shadow(color: .green.opacity(0.7), radius: 5)
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
        }
        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
        .onAppear { pulse = true }
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
