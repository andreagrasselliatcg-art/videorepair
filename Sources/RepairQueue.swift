import Foundation
import SwiftUI

enum JobStatus: Equatable {
    case waiting
    case working(String)
    case done(URL, String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .waiting, .working: return true
        default: return false
        }
    }
}

struct RepairJob: Identifiable {
    let id = UUID()
    let input: URL
    var status: JobStatus = .waiting
    var log: String = ""
}

/// Coda dei video da riparare. Tutti i metodi vanno chiamati sul main thread.
final class RepairQueue: ObservableObject {
    static let shared = RepairQueue()

    @Published var jobs: [RepairJob] = []
    @Published var referenceURL: URL?
    @Published var outputFolder: URL?
    @Published var forceReencode = false
    @Published private(set) var isRunning = false

    private let engine = RepairEngine()
    private let worker = DispatchQueue(label: "it.videorepair.worker", qos: .userInitiated)

    var ffmpegAvailable: Bool { Tools.find("ffmpeg") != nil && Tools.find("ffprobe") != nil }

    func add(_ urls: [URL]) {
        for url in urls where !url.hasDirectoryPath {
            if !jobs.contains(where: { $0.input == url && $0.status.isActive }) {
                jobs.append(RepairJob(input: url))
            }
        }
        processNext()
    }

    func retry(_ id: UUID) {
        update(id) { $0.status = .waiting; $0.log = "" }
        processNext()
    }

    func clearFinished() {
        jobs.removeAll { !$0.status.isActive }
    }

    private func processNext() {
        guard !isRunning, let idx = jobs.firstIndex(where: { $0.status == .waiting }) else { return }
        isRunning = true
        let id = jobs[idx].id
        let input = jobs[idx].input
        jobs[idx].status = .working("Avvio…")
        let options = RepairOptions(reference: referenceURL,
                                    forceReencode: forceReencode,
                                    outputFolder: outputFolder)
        let engine = self.engine

        worker.async { [weak self] in
            let result = engine.repair(input: input, options: options) { msg in
                DispatchQueue.main.async { self?.update(id) { $0.status = .working(msg) } }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.update(id) { job in
                    job.log = result.log
                    if result.success, let out = result.output {
                        job.status = .done(out, result.method)
                    } else {
                        job.status = .failed(result.message)
                    }
                }
                self.isRunning = false
                self.processNext()
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout RepairJob) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }
}
