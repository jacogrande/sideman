import Foundation

actor SpotifyAppleScriptNowPlayingProvider: NowPlayingProvider {
    private let script = """
    if application "Spotify" is running then
      tell application "Spotify"
        if player state is playing then
          set t to current track
          set trackNumberValue to 0
          try
            set trackNumberValue to track number of t
          end try
          return "PLAYING||" & trackNumberValue & "||" & (id of t) & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t)
        else
          return "PAUSED"
        end if
      end tell
    else
      return "NOT_RUNNING"
    end if
    """

    func fetchSnapshot() async -> PlaybackSnapshot {
        let execution = runAppleScript(script)
        if let output = execution.output {
            return SpotifyAppleScriptParser.parse(output)
        }

        return .unknown(execution.errorMessage)
    }

    private func runAppleScript(_ script: String) -> AppleScriptExecution {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return AppleScriptExecution(output: nil, errorMessage: "Failed to start osascript: \(error.localizedDescription)")
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errors = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            return AppleScriptExecution(output: output, errorMessage: nil)
        }

        if errors.isEmpty {
            return AppleScriptExecution(output: nil, errorMessage: "osascript exited with status \(process.terminationStatus)")
        }

        return AppleScriptExecution(output: nil, errorMessage: errors)
    }
}

private struct AppleScriptExecution {
    let output: String?
    let errorMessage: String?
}

enum SpotifyAppleScriptParser {
    static func parse(_ rawOutput: String) -> PlaybackSnapshot {
        if rawOutput == "NOT_RUNNING" {
            return .notRunning
        }

        if rawOutput == "PAUSED" || rawOutput.isEmpty {
            return .paused
        }

        if rawOutput.hasPrefix("PLAYING||") {
            let parts = rawOutput.components(separatedBy: "||")
            if parts.count >= 6 {
                let trackNumber = Int(parts[1]).flatMap { $0 > 0 ? $0 : nil }
                let track = NowPlayingTrack(
                    id: parts[2],
                    title: parts[3],
                    artist: parts[4],
                    album: parts[5...].joined(separator: "||"),
                    trackNumber: trackNumber
                )
                return .playing(track)
            }

            // Backward compatibility with older app payloads that did not include track number.
            if parts.count >= 5 {
                let track = NowPlayingTrack(
                    id: parts[1],
                    title: parts[2],
                    artist: parts[3],
                    album: parts[4...].joined(separator: "||")
                )
                return .playing(track)
            }

            return .unknown("Malformed PLAYING payload")
        }

        return .unknown("Unexpected AppleScript output")
    }
}
