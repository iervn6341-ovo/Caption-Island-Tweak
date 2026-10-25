import Foundation

enum CIActivityCommandKind: String, Sendable {
    case control, lyric, presentation
}

struct CIActivityCommandMetrics: Sendable {
    let sequence: UInt64
    let kind: CIActivityCommandKind
    let wait: TimeInterval
    let pending: Int
    let coalesced: UInt64
}

/// One operation runs at a time. Adjacent unsent lyric/presentation operations
/// can be replaced by their newest value; lifecycle controls remain barriers.
/// A slow ActivityKit call cannot be cancelled safely, but it must not create an
/// ever-growing backlog of obsolete lyric Tasks.
final class CIActivityCommandPipeline: @unchecked Sendable {
    typealias Operation = @Sendable (CIActivityCommandMetrics) async -> Void
    private struct Command {
        let sequence: UInt64
        let kind: CIActivityCommandKind
        let uptime: TimeInterval
        let operation: Operation
    }
    private let queue = DispatchQueue(label: "com.captionisland.activity.commands")
    private var pending: [Command] = []
    private var running = false
    private var sequence: UInt64 = 0
    private var coalesced: UInt64 = 0

    func submit(kind: CIActivityCommandKind = .control,
                coalescing: Bool = false, operation: @escaping Operation) {
        queue.sync {
            sequence &+= 1
            let command = Command(sequence: sequence, kind: kind,
                uptime: ProcessInfo.processInfo.systemUptime, operation: operation)
            if coalescing, kind != .control, pending.last?.kind == kind {
                pending[pending.count - 1] = command
                coalesced &+= 1
            } else {
                pending.append(command)
            }
            if !running {
                running = true
                Task { await self.drain() }
            }
        }
    }

    private func next() -> (Command, CIActivityCommandMetrics)? {
        queue.sync {
            guard !pending.isEmpty else {
                running = false
                return nil
            }
            let command = pending.removeFirst()
            return (command, CIActivityCommandMetrics(sequence: command.sequence,
                kind: command.kind, wait: max(0, ProcessInfo.processInfo.systemUptime - command.uptime),
                pending: pending.count, coalesced: coalesced))
        }
    }

    private func drain() async {
        while let (command, metrics) = next() {
            await command.operation(metrics)
        }
    }
}
