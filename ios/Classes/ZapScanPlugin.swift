import Flutter
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import Vision
import CoreImage

@objc(ZapScanPlugin)
public class ZapScanPlugin: NSObject, FlutterPlugin {
  @objc public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    #elseif os(macOS)
    let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: "zap_scan", binaryMessenger: messenger)
    let instance = ZapScanPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "getPlatformVersion" {
      #if os(iOS)
      result("iOS " + UIDevice.current.systemVersion)
      #elseif os(macOS)
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
      #endif
    } else if call.method == "recognizeText" {
      recognizeText(call: call, result: result)
    } else if call.method == "recognizeBarcode" {
      recognizeBarcode(call: call, result: result)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func recognizeText(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let requestHandler: VNImageRequestHandler?

        if let imagePath = args["imagePath"] as? String {
            let exists = FileManager.default.fileExists(atPath: imagePath)
            NSLog("ZapScan: recognizeText - imagePath=\(imagePath) exists=\(exists)")
            
            guard let imageData = FileManager.default.contents(atPath: imagePath) else {
                NSLog("ZapScan: recognizeText - Cannot read file data at path: \(imagePath)")
                result(FlutterError(code: "image_error", message: "Cannot read file at path: \(imagePath)", details: nil))
                return
            }
            NSLog("ZapScan: recognizeText - Read \(imageData.count) bytes from file")
            
            #if os(iOS)
            requestHandler = VNImageRequestHandler(data: imageData, options: [:])
            #elseif os(macOS)
            requestHandler = VNImageRequestHandler(data: imageData, options: [:])
            #endif
        } else {
            guard let flutterData = args["bytes"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "invalid_args", message: "Missing image bytes or dimensions", details: nil))
                return
            }

            let bytes = flutterData.data
            let byteCount = bytes.count
            let isGrayscale = (byteCount == width * height)

            let colorSpace: CGColorSpace
            let bitmapInfo: CGBitmapInfo
            let bytesPerRow: Int

            if isGrayscale {
                colorSpace = CGColorSpaceCreateDeviceGray()
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                bytesPerRow = width
            } else {
                colorSpace = CGColorSpaceCreateDeviceRGB()
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                bytesPerRow = width * 4
            }

            guard let provider = CGDataProvider(data: bytes as CFData),
                  let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: isGrayscale ? 8 : 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                result(FlutterError(code: "image_error", message: "Could not create image from bytes", details: nil))
                return
            }
            let rotationDeg = args["rotation"] as? Int ?? 0
            var orientation: CGImagePropertyOrientation = .up
            switch rotationDeg {
                case 90: orientation = .right
                case 180: orientation = .down
                case 270: orientation = .left
                default: orientation = .up
            }

            requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        }

        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                result(FlutterError(code: "ocr_error", message: error.localizedDescription, details: nil))
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                result("")
                return
            }

            var extractedText = ""
            for observation in observations {
                guard let topCandidate = observation.topCandidates(1).first else { continue }
                extractedText += topCandidate.string + "\n"
            }

            result(extractedText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        request.recognitionLevel = .accurate

        do {
            try requestHandler?.perform([request])
        } catch {
            result(FlutterError(code: "ocr_perform_error", message: error.localizedDescription, details: nil))
        }
    }
  }

  private func recognizeBarcode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
        return
    }

    DispatchQueue.global(qos: .userInitiated).async {
        let requestHandler: VNImageRequestHandler?

        if let imagePath = args["imagePath"] as? String {
            let exists = FileManager.default.fileExists(atPath: imagePath)
            NSLog("ZapScan: recognizeBarcode - imagePath=\(imagePath) exists=\(exists)")
            
            guard let imageData = FileManager.default.contents(atPath: imagePath) else {
                NSLog("ZapScan: recognizeBarcode - Cannot read file data at path: \(imagePath)")
                result(FlutterError(code: "image_error", message: "Cannot read file at path: \(imagePath)", details: nil))
                return
            }
            NSLog("ZapScan: recognizeBarcode - Read \(imageData.count) bytes from file")
            
            #if os(iOS)
            requestHandler = VNImageRequestHandler(data: imageData, options: [:])
            #elseif os(macOS)
            requestHandler = VNImageRequestHandler(data: imageData, options: [:])
            #endif
        } else {
            guard let flutterData = args["bytes"] as? FlutterStandardTypedData,
                  let width = args["width"] as? Int,
                  let height = args["height"] as? Int else {
                result(FlutterError(code: "invalid_args", message: "Missing image bytes or dimensions", details: nil))
                return
            }

            let bytes = flutterData.data
            let byteCount = bytes.count
            let isGrayscale = (byteCount == width * height)

            let colorSpace: CGColorSpace
            let bitmapInfo: CGBitmapInfo
            let bytesPerRow: Int

            if isGrayscale {
                colorSpace = CGColorSpaceCreateDeviceGray()
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                bytesPerRow = width
            } else {
                colorSpace = CGColorSpaceCreateDeviceRGB()
                bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                bytesPerRow = width * 4
            }

            guard let provider = CGDataProvider(data: bytes as CFData),
                  let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: isGrayscale ? 8 : 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                result(FlutterError(code: "image_error", message: "Could not create image from bytes", details: nil))
                return
            }
            let rotationDeg = args["rotation"] as? Int ?? 0
            var orientation: CGImagePropertyOrientation = .up
            switch rotationDeg {
                case 90: orientation = .right
                case 180: orientation = .down
                case 270: orientation = .left
                default: orientation = .up
            }

            requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        }

        let request = VNDetectBarcodesRequest { (request, error) in
            if let error = error {
                result(FlutterError(code: "barcode_error", message: error.localizedDescription, details: nil))
                return
            }

            guard let observations = request.results as? [VNBarcodeObservation] else {
                result([])
                return
            }

            var payloadList: [[String: String]] = []
            for observation in observations {
                if let rawValue = observation.payloadStringValue {
                    var formatStr = "UNKNOWN"
                    #if os(iOS)
                    if #available(iOS 14.0, *) {
                        formatStr = observation.symbology.rawValue
                    }
                    #elseif os(macOS)
                    if #available(macOS 11.0, *) {
                        formatStr = observation.symbology.rawValue
                    }
                    #endif
                    payloadList.append(["rawValue": rawValue, "format": formatStr])
                }
            }

            result(payloadList)
        }

        // Explicitly enable all common symbologies to increase sensitivity
        var symbologies: [VNBarcodeSymbology] = [
            .qr, .code128, .code39, .code93, .ean8, .ean13, .upce, .pdf417, .aztec, .dataMatrix, .itf14, .i2of5
        ]
        
        #if os(iOS)
        if #available(iOS 15.0, *) {
            symbologies.append(contentsOf: [.codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited, .microPDF417, .microQR])
        }
        #elseif os(macOS)
        if #available(macOS 12.0, *) {
            symbologies.append(contentsOf: [.codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited, .microPDF417, .microQR])
        }
        #endif
        
        request.symbologies = symbologies

        do {
            try requestHandler?.perform([request])
        } catch {
            result(FlutterError(code: "barcode_perform_error", message: error.localizedDescription, details: nil))
        }
    }
  }
}
