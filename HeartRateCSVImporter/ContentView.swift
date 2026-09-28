import SwiftUI
import HealthKit
import UniformTypeIdentifiers

struct HeartRateRow {
    let epoch: TimeInterval
    let bpm: Double
}

enum ImportError: LocalizedError {
    case badHeader, badRow(Int), unavailable
    var errorDescription: String? {
        switch self {
        case .badHeader: return "CSV must contain epoch_seconds and bpm columns."
        case .badRow(let line): return "Could not parse CSV row \(line)."
        case .unavailable: return "Heart Rate is unavailable on this device."
        }
    }
}

struct ContentView: View {
    @State private var showingImporter = false
    @State private var status = "Select your WHOOP CSV to begin."
    @State private var isImporting = false
    private let healthStore = HKHealthStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Heart Rate CSV Importer").font(.title2.bold())
                Text("Imports epoch_seconds + bpm into Apple Health. Your CSV stays on this iPhone.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Select CSV") { showingImporter = true }
                    .buttonStyle(.borderedProminent).disabled(isImporting)
                if isImporting { ProgressView() }
                Text(status).font(.footnote).multilineTextAlignment(.center).padding()
                Spacer()
            }.padding().navigationTitle("Health Import")
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.commaSeparatedText, .text],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { importCSV(url) }
                case .failure(let error):
                    status = error.localizedDescription
                }
            }
        }
    }

    private func importCSV(_ url: URL) {
        isImporting = true
        status = "Reading CSV…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let rows = try parse(url)
                guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                    throw ImportError.unavailable
                }
                healthStore.requestAuthorization(toShare: [type], read: []) { ok, error in
                    guard ok else {
                        DispatchQueue.main.async {
                            isImporting = false
                            status = error?.localizedDescription ?? "Health permission denied."
                        }
                        return
                    }
                    save(rows, type: type)
                }
            } catch {
                DispatchQueue.main.async {
                    isImporting = false
                    status = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func parse(_ url: URL) throws -> [HeartRateRow] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let header = lines.first else { throw ImportError.badHeader }
        let columns = header.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let ei = columns.firstIndex(of: "epoch_seconds"),
              let bi = columns.firstIndex(of: "bpm") else {
            throw ImportError.badHeader
        }
        return try lines.dropFirst().enumerated().map { n, line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard ei < fields.count, bi < fields.count,
                  let epoch = TimeInterval(fields[ei]),
                  let bpm = Double(fields[bi]),
                  epoch > 0, bpm > 0, bpm < 400 else {
                throw ImportError.badRow(n + 2)
            }
            return HeartRateRow(epoch: epoch, bpm: bpm)
        }
    }

    private func save(_ rows: [HeartRateRow], type: HKQuantityType) {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = rows.map {
            let d = Date(timeIntervalSince1970: $0.epoch)
            return HKQuantitySample(type: type,
                                    quantity: HKQuantity(unit: unit, doubleValue: $0.bpm),
                                    start: d, end: d)
        }
        let size = 500
        var batches: [[HKQuantitySample]] = []
        for start in stride(from: 0, to: samples.count, by: size) {
            batches.append(Array(samples[start..<min(start + size, samples.count)]))
        }
        saveBatches(batches, index: 0, imported: 0, total: samples.count)
    }

    private func saveBatches(_ batches: [[HKQuantitySample]], index: Int, imported: Int, total: Int) {
        guard index < batches.count else {
            DispatchQueue.main.async {
                isImporting = false
                status = "Finished. Imported \(imported) of \(total) samples."
            }
            return
        }
        healthStore.save(batches[index]) { ok, error in
            guard ok else {
                DispatchQueue.main.async {
                    isImporting = false
                    status = "Stopped after \(imported): \(error?.localizedDescription ?? "HealthKit error")"
                }
                return
            }
            let count = imported + batches[index].count
            DispatchQueue.main.async { status = "Imported \(count) of \(total)…" }
            saveBatches(batches, index: index + 1, imported: count, total: total)
        }
    }
}
