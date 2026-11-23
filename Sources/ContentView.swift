import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject private var queue = RepairQueue.shared
    @State private var isTargeted = false
    @State private var logJob: RepairJob?

    var body: some View {
        VStack(spacing: 14) {
            if !queue.ffmpegAvailable { missingFFmpegBanner }

            dropZone

            options

            if !queue.jobs.isEmpty {
                List {
                    ForEach(queue.jobs) { job in
                        JobRow(job: job,
                               onLog: { logJob = job },
                               onRetry: { queue.retry(job.id) })
                    }
                }
                .listStyle(.inset)

                HStack {
                    Spacer()
                    Button("Rimuovi completati") { queue.clearFinished() }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .sheet(item: $logJob) { job in LogView(job: job) }
    }

    // MARK: Sezioni

    private var missingFFmpegBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("ffmpeg non è installato").bold()
                Text("Reinstalla VideoRepair dal pacchetto .pkg, che include ffmpeg.")
                    .font(.callout)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 40))
                .foregroundColor(isTargeted ? .accentColor : .secondary)
            Text("Trascina qui i video danneggiati").font(.title3).bold()
            Text("MP4, MOV, M4V, MKV, AVI, MTS… L'originale non viene mai modificato.")
                .font(.callout).foregroundColor(.secondary)
            Button("Scegli video…") { pickVideos() }
                .keyboardShortcut("o")
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url { DispatchQueue.main.async { RepairQueue.shared.add([url]) } }
                }
            }
            return true
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Ricodifica sempre (più lento, utile se la riparazione rapida dà ancora glitch)",
                   isOn: $queue.forceReencode)

            HStack {
                Text("Video di riferimento:")
                Text(queue.referenceURL?.lastPathComponent ?? "nessuno")
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if queue.referenceURL != nil { Button("Togli") { queue.referenceURL = nil } }
                Button("Scegli…") { pickReference() }
            }
            .help("Serve solo per file senza indice (registrazione interrotta): un video sano dello stesso dispositivo.")

            HStack {
                Text("Salva in:")
                Text(queue.outputFolder?.path ?? "stessa cartella dell'originale")
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if queue.outputFolder != nil { Button("Ripristina") { queue.outputFolder = nil } }
                Button("Scegli…") { pickOutputFolder() }
            }
        }
        .font(.callout)
    }

    // MARK: Pannelli

    private func pickVideos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .video, .data]
        if panel.runModal() == .OK { queue.add(panel.urls) }
    }

    private func pickReference() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie]
        if panel.runModal() == .OK { queue.referenceURL = panel.url }
    }

    private func pickOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { queue.outputFolder = panel.url }
    }
}

// MARK: - Riga della coda

struct JobRow: View {
    let job: RepairJob
    let onLog: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon.frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.input.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(statusText).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer()
            switch job.status {
            case .done(let out, _):
                Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([out]) }
                Button("Apri") { NSWorkspace.shared.open(out) }
            case .failed:
                Button("Riprova", action: onRetry)
            default:
                EmptyView()
            }
            if !job.log.isEmpty {
                Button(action: onLog) { Image(systemName: "doc.text.magnifyingglass") }
                    .buttonStyle(.borderless).help("Mostra log")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusIcon: some View {
        switch job.status {
        case .waiting: Image(systemName: "clock").foregroundColor(.secondary)
        case .working: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
        }
    }

    private var statusText: String {
        switch job.status {
        case .waiting: return "In attesa"
        case .working(let msg): return msg
        case .done(let out, let method): return "\(method) → \(out.lastPathComponent)"
        case .failed(let msg): return msg
        }
    }
}

// MARK: - Log

struct LogView: View {
    let job: RepairJob
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(alignment: .leading) {
            Text("Log – \(job.input.lastPathComponent)").font(.headline)
            ScrollView {
                Text(job.log)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copia") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.log, forType: .string)
                }
                Spacer()
                Button("Chiudi") { presentationMode.wrappedValue.dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 420)
    }
}
