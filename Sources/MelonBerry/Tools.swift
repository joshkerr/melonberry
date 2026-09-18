import Foundation

/// The Homebrew command-line tools the scan pipeline shells out to.
enum Tools {
    static let required = ["scanimage", "img2pdf", "ocrmypdf"]
    private static let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func find(_ name: String) -> URL? {
        searchDirs
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var missing: [String] { required.filter { find($0) == nil } }

    /// ocrmypdf launches tesseract, ghostscript etc. by name, so it needs Homebrew on PATH.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchDirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        return env
    }
}

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Runs a tool to completion. `onStderrLine` is called on a background thread as each line arrives.
func runProcess(_ executable: URL, _ arguments: [String],
                onStderrLine: (@Sendable (String) -> Void)? = nil) async -> ProcessResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = Tools.environment
            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ProcessResult(status: -1, stdout: "", stderr: error.localizedDescription))
                return
            }

            let out = DataBox()
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                out.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            var err = Data()
            var pending = Data()
            let errHandle = errPipe.fileHandleForReading
            while true {
                let chunk = errHandle.availableData
                if chunk.isEmpty { break }
                err.append(chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                    pending.removeSubrange(pending.startIndex...newline)
                    onStderrLine?(line)
                }
            }

            group.wait()
            process.waitUntilExit()
            continuation.resume(returning: ProcessResult(
                status: process.terminationStatus,
                stdout: String(decoding: out.data, as: UTF8.self),
                stderr: String(decoding: err, as: UTF8.self)))
        }
    }
}
