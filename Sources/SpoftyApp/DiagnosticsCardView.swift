import SwiftUI

struct DiagnosticsCardView: View {
    let snapshot: ResourceSnapshot

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostics")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                DiagnosticRow(label: "Resident Memory", value: String(format: "%.1f MB", snapshot.residentMB))
                DiagnosticRow(label: "Virtual Memory", value: String(format: "%.0f MB", snapshot.virtualMB))

                Divider().overlay(.white.opacity(0.08))

                DiagnosticRow(label: "CPU User", value: String(format: "%.3f s", snapshot.cpuUserTime))
                DiagnosticRow(label: "CPU System", value: String(format: "%.3f s", snapshot.cpuSystemTime))
                DiagnosticRow(label: "CPU Total", value: String(format: "%.3f s", snapshot.totalCPUTime))

                Divider().overlay(.white.opacity(0.08))

                DiagnosticRow(label: "Cache File", value: snapshot.cacheFileExists ? "Present" : "Not Found")
                if snapshot.cacheFileExists {
                    DiagnosticRow(label: "Cache Size", value: String(format: "%.1f KB", snapshot.cacheFileSizeKB))
                    DiagnosticRow(label: "Cache Entries", value: "\(snapshot.cacheEntryCount)")
                }

                Text("Captured \(snapshot.capturedAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }
}
