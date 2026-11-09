import Flutter
import UIKit

public class FlutterPaddleOcrPlugin: NSObject, FlutterPlugin {
  private var instances: [Int: PaddleOcrEngine] = [:]
  private var nextId: Int = 1
  private let lock = NSLock()
  // Match Android: keep native inference off the platform thread.
  private let worker = DispatchQueue(label: "flutter_paddle_ocr.worker", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_paddle_ocr", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FlutterPaddleOcrPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    worker.async { [weak self] in
      guard let self else { return }
      let outcome: Result<Any?, Error>
      do {
        outcome = .success(try self.dispatch(call))
      } catch {
        outcome = .failure(error)
      }
      DispatchQueue.main.async {
        switch outcome {
        case .success(let value): result(value)
        case .failure(let err as PluginError):
          result(FlutterError(code: err.code, message: err.message, details: nil))
        case .failure(let err):
          result(FlutterError(
            code: "PADDLE_OCR_ERROR", message: err.localizedDescription, details: nil))
        }
      }
    }
  }

  private func dispatch(_ call: FlutterMethodCall) throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "create": return try handleCreate(args)
    case "recognize": return try handleRecognize(args)
    case "dispose": return try handleDispose(args)
    default: return FlutterMethodNotImplemented
    }
  }

  private func handleCreate(_ args: [String: Any]) throws -> Int {
    let det = try args.require("detModelPath") as String
    let rec = try args.require("recModelPath") as String
    let dict = try args.require("labelPath") as String
    let cls = args["clsModelPath"] as? String
    let threads = args["cpuThreadNum"] as? Int ?? 4
    let power = args["cpuPower"] as? String ?? "LITE_POWER_HIGH"
    let useSpaceChar = (args["useSpaceChar"] as? Bool) ?? true
    let useDilation = (args["useDilation"] as? Bool) ?? false
    let detDbThresh = args["detDbThresh"] as? Double ?? 0.3
    let detDbBoxThresh = args["detDbBoxThresh"] as? Double ?? 0.6
    let detDbUnclipRatio = args["detDbUnclipRatio"] as? Double ?? 1.5

    for (name, path) in [("detModelPath", det), ("recModelPath", rec), ("labelPath", dict)] {
      if !FileManager.default.fileExists(atPath: path) {
        throw PluginError(code: "ARG", message: "\(name) not found: \(path)")
      }
    }
    if let cls, !cls.isEmpty, !FileManager.default.fileExists(atPath: cls) {
      throw PluginError(code: "ARG", message: "clsModelPath not found: \(cls)")
    }

    guard let engine = PaddleOcrEngine(
      detPath: det, recPath: rec, dictPath: dict,
      clsPath: (cls?.isEmpty == false) ? cls : nil,
      threads: Int32(threads), powerMode: power,
      useSpaceChar: useSpaceChar, useDilation: useDilation,
      detDbThresh: detDbThresh, detDbBoxThresh: detDbBoxThresh,
      detDbUnclipRatio: detDbUnclipRatio
    ) else {
      throw PluginError(code: "INIT", message: "PaddleOcrEngine failed to load models")
    }

    return withLock {
      let id = nextId
      nextId += 1
      instances[id] = engine
      return id
    }
  }

  private func handleRecognize(_ args: [String: Any]) throws -> [[String: Any]] {
    let id = try args.require("instanceId") as Int
    guard let engine = withLock({ instances[id] }) else {
      throw PluginError(code: "STATE", message: "No engine for id=\(id)")
    }
    let bytes = try args.require("imageBytes") as FlutterStandardTypedData
    let maxSideLen = args["maxSideLen"] as? Int ?? 960
    let runDet = (args["runDetection"] as? Bool) ?? true
    let runCls = (args["runClassification"] as? Bool) == true
    let runRec = (args["runRecognition"] as? Bool) ?? true
    return engine.recognize(
      bytes.data,
      maxSideLen: Int32(maxSideLen),
      runDet: runDet, runCls: runCls, runRec: runRec
    ) as? [[String: Any]] ?? []
  }

  private func handleDispose(_ args: [String: Any]) throws -> Any? {
    let id = try args.require("instanceId") as Int
    withLock { instances.removeValue(forKey: id) }?.dispose()
    return nil
  }

  private func withLock<T>(_ body: () -> T) -> T {
    lock.lock(); defer { lock.unlock() }
    return body()
  }
}

private struct PluginError: Error {
  let code: String
  let message: String
}

private extension Dictionary where Key == String {
  func require<T>(_ name: String) throws -> T {
    guard let v = self[name] as? T else {
      throw PluginError(code: "ARG", message: "\(name) is required")
    }
    return v
  }
}
