import Foundation

// MARK: - Strumenti esterni (ffmpeg, ffprobe, untrunc)

enum Tools {
    static func find(_ name: String) -> String? {
        var candidates: [String] = []
        if let res = Bundle.main.resourceURL?.appendingPathComponent("bin/\(name)").path {
            candidates.append(res)                       // binario incluso nell'app
        }
        candidates += [
            "/opt/homebrew/bin/\(name)",                 // Homebrew Apple Silicon
            "/usr/local/bin/\(name)",                    // Homebrew Intel
            "/opt/local/bin/\(name)",                    // MacPorts
            "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Esecuzione processi (sincrona, da chiamare in background)

enum Shell {
    struct Output { let status: Int32; let text: String }

    static func run(_ exe: String, _ args: [String]) -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch {
            return Output(status: -1, text: error.localizedDescription)
        }
        // Legge fino alla chiusura del processo (evita blocchi del buffer)
        var data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let limit = 256 * 1024
        if data.count > limit { data = data.suffix(limit) }
        return Output(status: p.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Motore di riparazione

struct RepairOptions {
    var reference: URL?
    var forceReencode: Bool
    var outputFolder: URL?
}

struct RepairResult {
    var success: Bool
    var output: URL?
    var method: String
    var message: String
    var log: String
}

final class RepairEngine {

    func repair(input: URL, options: RepairOptions, progress: (String) -> Void) -> RepairResult {
        var log = "File: \(input.path)\n"

        guard let ffmpeg = Tools.find("ffmpeg"), let ffprobe = Tools.find("ffprobe") else {
            return RepairResult(success: false, output: nil, method: "",
                                message: "ffmpeg non trovato. Reinstalla VideoRepair dal pacchetto .pkg.",
                                log: log)
        }
        log += "ffmpeg: \(ffmpeg)\n"

        let base = input.deletingPathExtension().lastPathComponent
        let dir = options.outputFolder ?? input.deletingLastPathComponent()

        // 1) Analisi
        progress("Analisi del file…")
        let probe = Shell.run(ffprobe, ["-v", "error",
                                        "-show_entries", "format=duration:stream=codec_type,codec_name",
                                        "-of", "default=nw=1", input.path])
        log += "\n== Analisi ==\n\(probe.text)\n"
        let isHEVC = probe.text.contains("codec_name=hevc")
        let moovMissing = probe.text.contains("moov atom not found")

        // 2) Indice MP4/MOV mancante (ripresa interrotta, batteria scarica…)
        if moovMissing {
            progress("Indice video mancante: ricostruzione…")
            guard let ref = options.reference else {
                return RepairResult(success: false, output: nil, method: "",
                    message: "Manca l'indice del file (moov). Scegli un \"video di riferimento\" sano, girato con lo stesso dispositivo e le stesse impostazioni, poi premi Riprova.",
                    log: log)
            }
            guard let untrunc = Tools.find("untrunc") else {
                return RepairResult(success: false, output: nil, method: "",
                    message: "Per questo tipo di danno serve lo strumento untrunc (vedi LEGGIMI).",
                    log: log)
            }
            let ext = input.pathExtension.isEmpty ? "mp4" : input.pathExtension
            let out = uniqueURL(dir, base + "_ricostruito", ext)
            let r = Shell.run(untrunc, ["-dst", out.path, ref.path, input.path])
            log += "\n== untrunc ==\n\(r.text)\n"
            let alt = URL(fileURLWithPath: input.path + "_fixed." + ext)
            let fm = FileManager.default
            let produced: URL? = fm.fileExists(atPath: out.path) ? out
                              : (fm.fileExists(atPath: alt.path) ? alt : nil)
            if let produced = produced, validate(produced, ffmpeg: ffmpeg, ffprobe: ffprobe, log: &log) {
                return RepairResult(success: true, output: produced, method: "Indice ricostruito",
                                    message: "", log: log)
            }
            return RepairResult(success: false, output: nil, method: "",
                message: "Ricostruzione non riuscita. Prova con un altro video di riferimento dello stesso dispositivo.",
                log: log)
        }

        // 3) Riparazione rapida senza perdita (remux)
        if !options.forceReencode {
            progress("Riparazione rapida (senza perdita di qualità)…")
            let out = uniqueURL(dir, base + "_riparato", "mov")
            var args = ["-y", "-hide_banner", "-nostdin", "-v", "warning",
                        "-err_detect", "ignore_err",
                        "-fflags", "+genpts+discardcorrupt+igndts",
                        "-i", input.path,
                        "-map", "0:v?", "-map", "0:a?",
                        "-c", "copy",
                        "-avoid_negative_ts", "make_zero",
                        "-movflags", "+faststart"]
            if isHEVC { args += ["-tag:v", "hvc1"] }
            args.append(out.path)
            let r = Shell.run(ffmpeg, args)
            log += "\n== Remux ==\n\(r.text)\n"
            if r.status == 0, validate(out, ffmpeg: ffmpeg, ffprobe: ffprobe, log: &log) {
                return RepairResult(success: true, output: out, method: "Riparazione rapida",
                                    message: "", log: log)
            }
            try? FileManager.default.removeItem(at: out)
        }

        // 4) Ricodifica completa con occultamento errori
        progress("Ricodifica completa (può richiedere tempo)…")
        let out = uniqueURL(dir, base + "_riparato_ricodificato", "mp4")
        let encoders = Shell.run(ffmpeg, ["-hide_banner", "-encoders"]).text
        let videoCodec: [String] = encoders.contains("libx264")
            ? ["-c:v", "libx264", "-preset", "medium", "-crf", "18"]
            : ["-c:v", "h264_videotoolbox", "-b:v", "12M"]
        let args = ["-y", "-hide_banner", "-nostdin", "-v", "warning",
                    "-err_detect", "ignore_err",
                    "-fflags", "+genpts+discardcorrupt",
                    "-ec", "favor_inter+guess_mvs+deblock",
                    "-i", input.path,
                    "-map", "0:v:0", "-map", "0:a?",
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p"]
                    + videoCodec
                    + ["-c:a", "aac", "-b:a", "192k",
                       "-max_muxing_queue_size", "9999",
                       "-movflags", "+faststart",
                       out.path]
        let r = Shell.run(ffmpeg, args)
        log += "\n== Ricodifica ==\n\(r.text)\n"
        if FileManager.default.fileExists(atPath: out.path),
           validate(out, ffmpeg: ffmpeg, ffprobe: ffprobe, log: &log) {
            return RepairResult(success: true, output: out, method: "Ricodifica completa",
                                message: "", log: log)
        }
        try? FileManager.default.removeItem(at: out)
        return RepairResult(success: false, output: nil, method: "",
            message: "Il file è troppo danneggiato per un recupero automatico. Controlla il log.",
            log: log)
    }

    private func validate(_ url: URL, ffmpeg: String, ffprobe: String, log: inout String) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 1024 else { return false }
        let p = Shell.run(ffprobe, ["-v", "error", "-select_streams", "v:0",
                                    "-show_entries", "format=duration:stream=codec_type",
                                    "-of", "default=nw=1", url.path])
        guard p.text.contains("codec_type=video") else { return false }
        let durationLine = p.text.split(separator: "\n").first { $0.hasPrefix("duration=") }
        let duration = durationLine.flatMap { Double($0.dropFirst("duration=".count)) } ?? 0
        guard duration > 0.2 else { return false }
        let d = Shell.run(ffmpeg, ["-v", "error", "-nostdin", "-t", "5", "-i", url.path, "-f", "null", "-"])
        log += "\n== Verifica ==\ndurata: \(String(format: "%.1f", duration)) s\n\(d.text)\n"
        return d.status == 0
    }

    private func uniqueURL(_ dir: URL, _ name: String, _ ext: String) -> URL {
        var url = dir.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
