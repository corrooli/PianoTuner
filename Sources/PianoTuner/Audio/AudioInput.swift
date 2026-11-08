import AVFoundation
import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

// MARK: - Core Audio device discovery

enum AudioDevices {
    static func inputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannels(of: id) > 0 else { return nil }
            let name = string(kAudioObjectPropertyName, of: id) ?? "Input \(id)"
            let uid = string(kAudioDevicePropertyDeviceUID, of: id) ?? "\(id)"
            return AudioDevice(id: id, uid: uid, name: name)
        }
    }

    static func defaultInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func inputChannels(of id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Calls `handler` on the main queue whenever devices or the default input change.
    static func observeChanges(_ handler: @escaping () -> Void) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main) { _, _ in handler() }
        }
    }
}

// MARK: - Microphone capture

enum AudioInputError: LocalizedError {
    case noInput

    var errorDescription: String? { "No usable microphone input was found." }
}

/// Captures mono audio from an input device into a ring buffer that the
/// analyzer can read from any thread.
final class AudioInput: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 1 << 17)
    private var writeIndex = 0
    private var filled = 0
    private var _sampleRate: Double = 48_000
    private var _levelDb: Double = -120
    private(set) var isRunning = false

    var sampleRate: Double { lock.withLock { _sampleRate } }
    var levelDb: Double { lock.withLock { _levelDb } }

    func start(deviceID: AudioDeviceID?) throws {
        stop()
        engine = AVAudioEngine()
        let input = engine.inputNode

        if let deviceID, let unit = input.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioInputError.noInput }

        lock.withLock {
            _sampleRate = format.sampleRate
            filled = 0
            writeIndex = 0
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0 else { return }

        var mono = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channelCount)
        for c in 0..<channelCount {
            let data = channels[c]
            for i in 0..<frames { mono[i] += data[i] * scale }
        }

        var sum: Float = 0
        for v in mono { sum += v * v }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(Double(rms) + 1e-9)

        lock.withLock {
            let capacity = ring.count
            for v in mono {
                ring[writeIndex] = v
                writeIndex = (writeIndex + 1) % capacity
            }
            filled = min(capacity, filled + frames)
            // Fast attack, slow release, like a real meter.
            _levelDb = db > _levelDb ? db : _levelDb * 0.85 + db * 0.15
        }
    }

    /// Returns the most recent `count` samples, oldest first.
    func latest(count: Int) -> [Float]? {
        lock.withLock {
            guard count <= filled, count <= ring.count else { return nil }
            var out = [Float](repeating: 0, count: count)
            let capacity = ring.count
            var start = writeIndex - count
            if start < 0 { start += capacity }
            for i in 0..<count {
                out[i] = ring[(start + i) % capacity]
            }
            return out
        }
    }
}
