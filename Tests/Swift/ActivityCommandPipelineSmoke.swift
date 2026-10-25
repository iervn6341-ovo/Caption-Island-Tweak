import Foundation

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}

private actor Values {
    private var values: [Int] = []
    private var coalesced: UInt64 = 0
    func append(_ value: Int, _ metrics: CIActivityCommandMetrics) {
        values.append(value)
        coalesced = metrics.coalesced
    }
    func check(_ expected: [Int], dropped: UInt64) {
        precondition(values == expected, "Unexpected command ordering: \(values)")
        precondition(coalesced == dropped, "Unexpected replacement count: \(coalesced)")
    }
}

@main
struct ActivityCommandPipelineSmoke {
    static func main() async {
        // A broken drain must fail CI, rather than leave it waiting indefinitely.
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            fatalError("Activity command pipeline timed out")
        }
        let pipeline = CIActivityCommandPipeline()
        let started = Gate(), release = Gate(), finished = Gate()
        let values = Values()
        pipeline.submit { metrics in
            await started.open()
            await release.wait()
            await values.append(0, metrics)
        }
        await started.wait()
        for number in 1...100 {
            pipeline.submit(kind: .lyric, coalescing: true) { await values.append(number, $0) }
        }
        pipeline.submit { await values.append(101, $0) } // Start/end cannot be replaced.
        for number in 102...201 {
            pipeline.submit(kind: .lyric, coalescing: true) { await values.append(number, $0) }
        }
        pipeline.submit { metrics in
            await values.append(202, metrics)
            await finished.open()
        }
        await release.open()
        await finished.wait()
        await values.check([0, 100, 101, 201, 202], dropped: 198)

        // A/B baseline retains FIFO; a new submission also restarts an idle drain.
        let baseline = Values(), baselineDone = Gate()
        for number in 0..<20 {
            pipeline.submit(kind: .lyric, coalescing: false) { await baseline.append(number, $0) }
        }
        pipeline.submit { _ in await baselineDone.open() }
        await baselineDone.wait()
        await baseline.check(Array(0..<20), dropped: 198)

        // A running lyric completes once; only its newest waiting successor runs.
        let inFlight = Gate(), unblock = Gate(), newestDone = Gate(), latest = Values()
        pipeline.submit(kind: .lyric, coalescing: true) { metrics in
            await inFlight.open()
            await unblock.wait()
            await latest.append(0, metrics)
        }
        await inFlight.wait()
        for number in 1...100 {
            pipeline.submit(kind: .lyric, coalescing: true) { await latest.append(number, $0) }
        }
        pipeline.submit { _ in await newestDone.open() }
        await unblock.open()
        await newestDone.wait()
        await latest.check([0, 100], dropped: 297)

        // Only adjacent commands of the same kind merge; a lyric is not lost
        // when a presentation refresh arrives on either side of it.
        let mixed = CIActivityCommandPipeline(), mixedValues = Values()
        let mixedStarted = Gate(), mixedRelease = Gate(), mixedDone = Gate()
        mixed.submit { _ in
            await mixedStarted.open()
            await mixedRelease.wait()
        }
        await mixedStarted.wait()
        mixed.submit(kind: .presentation, coalescing: true) { await mixedValues.append(1, $0) }
        mixed.submit(kind: .presentation, coalescing: true) { await mixedValues.append(2, $0) }
        mixed.submit(kind: .lyric, coalescing: true) { await mixedValues.append(3, $0) }
        mixed.submit(kind: .presentation, coalescing: true) { await mixedValues.append(4, $0) }
        mixed.submit(kind: .presentation, coalescing: true) { await mixedValues.append(5, $0) }
        mixed.submit { _ in await mixedDone.open() }
        await mixedRelease.open()
        await mixedDone.wait()
        await mixedValues.check([2, 3, 5], dropped: 2)
        print("Activity pipeline: delayed calls coalesce stale lyrics, preserve lifecycle barriers, keep FIFO baseline, and restart after draining.")
    }
}
