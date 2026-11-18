import ReplayKit
import AVFoundation
import CoreImage
import Darwin

/// Streams ReplayKit frames to the paired host process over an App Group socket.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "app.twist.cast.broadcast")
    private let context = CIContext()
    private var socketFD: Int32 = -1
    private var pending = 0
    private let gate = NSLock()
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "RTCAppGroupIdentifier") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            finishBroadcastWithError(NSError(domain: "app.twist.cast", code: 1))
            return
        }
        let path = directory.appendingPathComponent("rtc_SSFD").path
        queue.async {
            self.socketFD = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let capacity = MemoryLayout.size(ofValue: address.sun_path)
            guard path.utf8.count < capacity else { self.stopWithError(); return }
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                path.utf8CString.withUnsafeBytes { source in destination.copyMemory(from: source) }
            }
            let connected = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(self.socketFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else { self.stopWithError(); return }
            var noSignal: Int32 = 1
            setsockopt(self.socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(self.socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType != .audioMic else { return }
        gate.lock()
        if pending >= (sampleBufferType == .video ? 1 : 6) { gate.unlock(); return }
        pending += 1
        gate.unlock()
        queue.async {
            defer { self.gate.lock(); self.pending -= 1; self.gate.unlock() }
            guard self.socketFD >= 0 else { return }
            if sampleBufferType == .video { self.sendVideo(sampleBuffer) }
            if sampleBufferType == .audioApp { self.sendAudio(sampleBuffer) }
        }
    }

    private func sendVideo(_ sample: CMSampleBuffer) {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { return }
        let ciImage = CIImage(cvPixelBuffer: image)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let data = context.jpegRepresentation(of: ciImage, colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.75]) else { return }
        let orientation = (CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber)?.intValue ?? 1
        send(data, headers: "Buffer-Width: \(CVPixelBufferGetWidth(image))\r\nBuffer-Height: \(CVPixelBufferGetHeight(image))\r\nBuffer-Orientation: \(orientation)\r\n")
    }

    private func sendAudio(_ sample: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sample) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))) else { return }
        input.frameLength = input.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(input.frameLength), into: input.mutableAudioBufferList) == noErr else { return }
        if converter == nil || converter!.inputFormat != format {
            converter = AVAudioConverter(from: format, to: outputFormat)
        }
        guard let converter = converter,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * 48000 / format.sampleRate + 32)) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let samples = output.int16ChannelData else { return }
        send(Data(bytes: samples[0], count: Int(output.frameLength) * 2), headers: "Buffer-Type: audio\r\n")
    }

    private func send(_ data: Data, headers: String) {
        var packet = Data("HTTP/1.1 200 OK\r\nContent-Length: \(data.count)\r\n\(headers)\r\n".utf8)
        packet.append(data)
        let success = packet.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.send(socketFD, base.advanced(by: offset), raw.count - offset, 0)
                if count <= 0 { return false }
                offset += count
            }
            return true
        }
        if !success { stopWithError() }
    }

    private func stopWithError() {
        if socketFD >= 0 { Darwin.close(socketFD); socketFD = -1 }
        finishBroadcastWithError(NSError(domain: "app.twist.cast", code: 2))
    }

    override func broadcastFinished() {
        queue.async {
            if self.socketFD >= 0 { Darwin.close(self.socketFD); self.socketFD = -1 }
        }
    }
}
