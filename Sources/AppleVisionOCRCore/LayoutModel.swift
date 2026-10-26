import CoreGraphics
import CoreML
import Foundation
import Vision

protocol LayoutAnalyzing {
    func regions(for image: CGImage) throws -> [LayoutRegion]
}

public final class LayoutModel: LayoutAnalyzing {
    private let model: MLModel
    private let lock = NSLock()
    public static let missingMessage = "layout model not found: set APPLE_VISION_OCR_LAYOUT_MODEL to PPDocLayoutV3.mlmodelc (from a source checkout: eval \"$(scripts/fetch-layout-model.sh)\"), or run the CLI installed with VOCR.app"

    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                       executableURL: URL? = Bundle.main.executableURL) -> URL? {
        let url: URL
        if let override = environment["APPLE_VISION_OCR_LAYOUT_MODEL"] {
            url = URL(fileURLWithPath: override)
        } else {
            guard let executableURL else { return nil }
            url = executableURL.resolvingSymlinksInPath().deletingLastPathComponent()
                .appendingPathComponent("../Resources/PPDocLayoutV3.mlmodelc").standardizedFileURL
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment,
                     executableURL: URL? = Bundle.main.executableURL) throws -> LayoutModel {
        guard let url = locate(environment: environment, executableURL: executableURL) else {
            throw AppleVisionOCRError.visionFailure(missingMessage)
        }
        do {
            let configuration = MLModelConfiguration()
            // Observed 2026-10-27 during a 10-worker OCR run: first prediction 10.0 s with .all vs 0.2 s with .cpuAndGPU, same per-page time.
            configuration.computeUnits = .cpuAndGPU
            return LayoutModel(model: try MLModel(contentsOf: url, configuration: configuration))
        } catch {
            throw AppleVisionOCRError.visionFailure("failed to load layout model: \(error.localizedDescription)")
        }
    }

    private init(model: MLModel) { self.model = model }

    func regions(for image: CGImage) throws -> [LayoutRegion] {
        do {
            let input = try Self.input(image)
            let provider = try MLDictionaryFeatureProvider(dictionary: ["pixel_values": MLFeatureValue(multiArray: input)])
            lock.lock()
            defer { lock.unlock() }
            let prediction = try model.prediction(from: provider)
            let logits = try Self.values(prediction, name: "logits", shape: [1, 300, 25])
            let boxes = try Self.values(prediction, name: "pred_boxes", shape: [1, 300, 4])
            let order = try Self.values(prediction, name: "order_logits", shape: [1, 300, 300])
            return LayoutDecoder.regions(logits: logits, boxes: boxes, orderLogits: order)
        } catch {
            throw AppleVisionOCRError.visionFailure(error.localizedDescription)
        }
    }

    static func input(_ image: CGImage) throws -> MLMultiArray {
        let size = 800
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { throw AppleVisionOCRError.visionFailure("failed to resize layout image") }
        let input = try MLMultiArray(shape: [1, 3, 800, 800], dataType: .float16)
        let pointer = input.dataPointer.assumingMemoryBound(to: Float16.self)
        let strides = input.strides.map(\.intValue)
        for channel in 0..<3 {
            for y in 0..<size {
                for x in 0..<size {
                    pointer[channel * strides[1] + y * strides[2] + x * strides[3]] = Float16(Float(pixels[(y * size + x) * 4 + channel]) / 255)
                }
            }
        }
        return input
    }

    private static func values(_ prediction: any MLFeatureProvider, name: String, shape: [Int]) throws -> [Float] {
        guard let array = prediction.featureValue(for: name)?.multiArrayValue,
              array.shape.map(\.intValue) == shape else {
            throw AppleVisionOCRError.visionFailure("invalid layout output: \(name)")
        }
        return (0..<array.count).map { index in
            var remainder = index
            var coordinates = [NSNumber](repeating: 0, count: shape.count)
            for axis in shape.indices.reversed() {
                coordinates[axis] = NSNumber(value: remainder % shape[axis])
                remainder /= shape[axis]
            }
            return array[coordinates].floatValue
        }
    }
}

protocol TableRecognizing {
    func markdown(for image: CGImage, languages: [String], usesLanguageCorrection: Bool) throws -> String?
}

struct DocumentTableRecognizer: TableRecognizing {
    func markdown(for image: CGImage, languages: [String], usesLanguageCorrection: Bool) throws -> String? {
        guard #available(macOS 26.0, *) else {
            throw AppleVisionOCRError.visionFailure("Markdown table recognition requires macOS 26 or later")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String?, Error>?
        Task.detached {
            defer { semaphore.signal() }
            do {
                var request = RecognizeDocumentsRequest()
                request.textRecognitionOptions.recognitionLanguages = VisionLanguageResolver.resolve(languages).map { Locale.Language(identifier: $0) }
                request.textRecognitionOptions.useLanguageCorrection = usesLanguageCorrection
                let observations = try await request.perform(on: image)
                let tables = observations.first?.document.tables ?? []
                let rendered = tables.map { table in
                    MarkdownTable.render(cells: table.rows.flatMap { $0 }.map {
                        MarkdownTable.Cell(rows: $0.rowRange, columns: $0.columnRange, text: $0.content.text.transcript)
                    })
                }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                result = .success(rendered.isEmpty ? nil : rendered)
            } catch { result = .failure(AppleVisionOCRError.visionFailure(error.localizedDescription)) }
        }
        semaphore.wait()
        return try result!.get()
    }
}
