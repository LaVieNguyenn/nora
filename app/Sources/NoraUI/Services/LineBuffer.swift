import Foundation

/// Accumulates bytes from a pipe and hands back complete lines.
///
/// `readabilityHandler` fires on an arbitrary queue, so the partial-line state
/// has to live behind a lock rather than in a captured local.
final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    /// Ceiling on the unterminated tail, so a producer that never emits a
    /// newline cannot grow this without bound.
    private let limit = 4_000_000

    /// Append a chunk and return every complete line it finished.
    func append(_ chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)
        var lines: [String] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
        }

        if buffer.count > limit { buffer.removeAll(keepingCapacity: false) }
        return lines
    }

    /// Whatever is left after the producer closes the pipe.
    func drain() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let tail = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: false)
        return tail
    }
}
