import AVFoundation
import CoreImage
import CoreMediaIO
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads the iPhone's screen over USB. A trusted iPhone shows up as a muxed capture
/// device once screen-capture devices are allowed (the same switch QuickTime flips).
final class ScreenCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = ScreenCapture()

    private let queue = DispatchQueue(label: "iphone-use.capture")
    private let context = CIContext()
    private var session: AVCaptureSession?
    private var latest: CVPixelBuffer?
    private(set) var deviceName: String?

    func start() {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var allow: UInt32 = 1
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.queue.async { self?.connect() } }
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice else { return }
            self?.queue.async { self?.disconnect(device) }
        }

        AVCaptureDevice.requestAccess(for: .video) { granted in
            log("camera access \(granted ? "granted" : "denied")")
            self.queue.async { self.connect() }
        }
    }

    var size: CGSize? {
        queue.sync {
            latest.map { CGSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0)) }
        }
    }

    /// JPEG or PNG of the most recent frame.
    func snapshot(png: Bool, maxWidth: Int?) -> Data? {
        guard let buffer = queue.sync(execute: { latest }) else { return nil }
        var image = CIImage(cvPixelBuffer: buffer)
        if let maxWidth, image.extent.width > CGFloat(maxWidth) {
            let scale = CGFloat(maxWidth) / image.extent.width
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        let data = NSMutableData()
        let type = (png ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func connect() {
        guard session == nil else { return }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external], mediaType: .muxed, position: .unspecified
        ).devices
        guard let device = devices.first(where: { $0.modelID.contains("iOS") }) ?? devices.first else {
            log("no iPhone capture device yet (plug in and trust this Mac)")
            return
        }
        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
            session.addInput(input)
        } catch {
            log("capture input failed: \(error)")
            return
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            log("capture output rejected")
            return
        }
        session.addOutput(output)
        session.startRunning()
        self.session = session
        deviceName = device.localizedName
        log("capturing \(device.localizedName) (\(device.modelID))")
    }

    private func disconnect(_ device: AVCaptureDevice) {
        guard let session, session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device == device })
        else { return }
        session.stopRunning()
        self.session = nil
        latest = nil
        deviceName = nil
        log("iPhone capture device disconnected")
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        latest = CMSampleBufferGetImageBuffer(sampleBuffer)
    }

    enum CaptureError: Error { case cannotAddInput }
}
