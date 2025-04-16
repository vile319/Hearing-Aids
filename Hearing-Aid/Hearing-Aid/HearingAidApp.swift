import CoreBluetooth
import AVFoundation
import Combine

class HearingAidApp: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    // MARK: - Audio Processing Profiles
    enum AudioProfile: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case voiceIsolation = "Voice Isolation"
        case wideSpectrum = "Wide Spectrum"
        var id: String { rawValue }
    }

    // Published property to allow UI selection of audio profile
    @Published var selectedProfile: AudioProfile = .standard {
        didSet {
            configureProfile(selectedProfile)
        }
    }

    var centralManager: CBCentralManager!
    var audioPlayer: AVAudioPlayer?
    var connectedPeripheral: CBPeripheral?
    
    // Expose audio engine running state for UI
    var isAudioEngineRunning: Bool {
        return audioEngine.isRunning
    }

    // Audio Engine Properties
    private let audioEngine = AVAudioEngine()
    private let audioEnvironmentNode = AVAudioEnvironmentNode() // For potential spatial audio features
    private var inputNode: AVAudioInputNode!
    private var mainMixer: AVAudioMixerNode!
    private var outputNode: AVAudioOutputNode!

    // Audio Processing Nodes (Placeholders for now)
    private var eqNode: AVAudioUnitEQ!
    private var dynamicsNode: AVAudioUnitDynamicsProcessor!
    // Add more nodes as needed (e.g., for noise reduction, custom effects)

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupAudioSession()
        setupAudioEngine()
        // Apply the initial profile
        configureProfile(selectedProfile)
    }

    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set category for simultaneous input/output and Bluetooth playback
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            // Set audio session mode for low latency and real-time communication
            try audioSession.setMode(.voiceChat)
            try audioSession.setActive(true)
            print("Audio session setup complete with mode voiceChat.")

            // If needed, override output to default (system chooses best route, e.g., Bluetooth)
            try audioSession.overrideOutputAudioPort(.none)

            // Add observer for route changes (e.g., Bluetooth connection/disconnection)
            NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRouteChange),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)

        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }

     @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        print("Audio route changed: \(reason)")

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            // Reconfigure or restart engine if necessary, especially for Bluetooth connections
             print("Audio device change detected. Consider reconfiguring audio engine if needed.")
             // Example: If a preferred Bluetooth device connects, you might restart streaming.
             // If the current output device disconnects, handle gracefully.
             Task { // Use Task for async context if needed
                 await restartAudioEngineIfNeeded()
             }

        default: ()
        }
    }


    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        inputNode = audioEngine.inputNode
        outputNode = audioEngine.outputNode
        mainMixer = audioEngine.mainMixerNode

        // Initialize processing nodes
        eqNode = AVAudioUnitEQ(numberOfBands: 8) // Example: 8-band EQ
        dynamicsNode = AVAudioUnitDynamicsProcessor()
        dynamicsNode.threshold = -20 // Example AGC threshold
        dynamicsNode.headRoom = 5
        dynamicsNode.masterGain = 0
        dynamicsNode.compressionAmount = 5 // Example compression ratio


        // Attach nodes to the engine
        audioEngine.attach(eqNode)
        audioEngine.attach(dynamicsNode)
        // Attach other custom nodes if you have them

        // Connect nodes: Input -> EQ -> Dynamics -> MainMixer -> Output
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let outputFormat = outputNode.inputFormat(forBus: 0) // Use output node's format

        audioEngine.connect(inputNode, to: eqNode, format: inputFormat)
        audioEngine.connect(eqNode, to: dynamicsNode, format: inputFormat) // Assuming format doesn't change drastically
        audioEngine.connect(dynamicsNode, to: mainMixer, format: inputFormat)
        audioEngine.connect(mainMixer, to: outputNode, format: outputFormat) // Connect mixer to output


        audioEngine.prepare()
        print("Audio engine setup complete.")
    }

    // Function to restart the engine (e.g., after route change)
    // Needs careful implementation to avoid crashes
     private func restartAudioEngineIfNeeded() async {
        guard await checkMicrophonePermission() else {
             print("Microphone permission not granted.")
             return
         }

        if audioEngine.isRunning {
            print("Stopping audio engine for reconfiguration...")
            audioEngine.stop()
        }

         // Re-setup or re-connect nodes if necessary based on the new route
         // This might involve checking AVAudioSession.currentRoute outputs
         print("Checking audio routes and reconfiguring nodes if needed...")
         // (Add logic here if specific reconfiguration is needed based on device type)

         do {
             print("Starting audio engine again...")
             try audioEngine.start()
             print("Audio engine restarted successfully.")
         } catch {
             print("Error restarting audio engine: \(error.localizedDescription)")
         }
     }


    // MARK: - Microphone Permission
    private func checkMicrophonePermission() async -> Bool {
         switch AVAudioSession.sharedInstance().recordPermission {
         case .granted:
             return true
         case .denied:
             print("Microphone permission denied.")
             // Optionally guide user to settings
             return false
         case .undetermined:
             print("Requesting microphone permission...")
             let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
             if granted {
                 print("Microphone permission granted.")
             } else {
                 print("Microphone permission denied.")
             }
             return granted
         @unknown default:
             print("Unknown microphone permission state.")
             return false
         }
     }


    // MARK: - CBCentralManagerDelegate Methods

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on. Starting scan...")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        case .poweredOff:
            print("Bluetooth is powered off.")
        case .unsupported:
            print("Bluetooth is not supported on this device.")
        default:
            print("Bluetooth state is unknown.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Filter for specific devices if needed, e.g., by name
        if let name = peripheral.name, name.contains("Dime 3") { // Example: Filter for "Dime 3"
             print("Discovered compatible device: \(name)")
             connectedPeripheral = peripheral
             centralManager.stopScan()
             print("Stopping scan and attempting to connect.")
             centralManager.connect(peripheral, options: nil)
        } else if peripheral.name != nil {
            print("Discovered other device: \(peripheral.name!)")
        } else {
            print("Discovered unnamed device")
        }

    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "unknown device")")
        peripheral.delegate = self
        // Discover services relevant to audio streaming (e.g., A2DP, HFP)
        // You might need specific service UUIDs depending on the device
        peripheral.discoverServices(nil) // Discover all services for now
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "unknown device"): \(error?.localizedDescription ?? "unknown error")")
        // Optionally restart scanning
        // centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from \(peripheral.name ?? "unknown device")")
        connectedPeripheral = nil
        // Optionally restart scanning
         print("Restarting scan...")
         centralManager.scanForPeripherals(withServices: nil, options: nil)
    }


    // MARK: - CBPeripheralDelegate Methods

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }
        print("Discovered services for \(peripheral.name ?? "unknown device"):")
        for service in services {
            print("- Service UUID: \(service.uuid)")
            // Discover characteristics for relevant services (e.g., audio control)
            peripheral.discoverCharacteristics(nil, for: service) // Discover all characteristics for now
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics for service \(service.uuid): \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }
         print("Discovered characteristics for service \(service.uuid):")
        for characteristic in characteristics {
            print("- Characteristic UUID: \(characteristic.uuid), Properties: \(characteristic.properties)")
            // Interact with characteristics based on properties (read, write, notify)
            // For audio control, you might need to find specific characteristics
            // Example: Enable notifications if characteristic supports it
             if characteristic.properties.contains(.notify) {
                 print("   Subscribing to notifications for characteristic \(characteristic.uuid)")
                 peripheral.setNotifyValue(true, for: characteristic)
             }
        }
    }

     func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
         if let error = error {
             print("Error receiving notification for characteristic \(characteristic.uuid): \(error.localizedDescription)")
             return
         }

         if let data = characteristic.value {
             // Process the received data (e.g., status updates, audio control responses)
             print("Received data from characteristic \(characteristic.uuid): \(data.count) bytes")
             // Example: Convert data to string
             // if let stringValue = String(data: data, encoding: .utf8) {
             //     print("   Data as string: \(stringValue)")
             // }
         }
     }

     func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
         if let error = error {
             print("Error writing value to characteristic \(characteristic.uuid): \(error.localizedDescription)")
             return
         }
         print("Successfully wrote value to characteristic \(characteristic.uuid)")
     }

     func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error updating notification state for characteristic \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        print("Notification state updated for \(characteristic.uuid): \(characteristic.isNotifying ? "Enabled" : "Disabled")")
    }


    // MARK: - Audio Streaming Control
    func startAudioStreaming() async {
        guard await checkMicrophonePermission() else {
            print("Cannot start audio streaming without microphone permission.")
            return
        }

        // Ensure the audio session is active and configured
        do {
             let audioSession = AVAudioSession.sharedInstance()
             // Ensure correct category and options are set, especially for Bluetooth A2DP output
             try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .allowBluetooth])
             // Set preferred output to Bluetooth if available and connected
             // Note: This is a hint; the system decides the final route.
             let bluetoothRoutes = audioSession.availableInputs?.filter { $0.portType == .bluetoothA2DP }
             if bluetoothRoutes?.first != nil {
                 print("Bluetooth A2DP output available. System should prioritize it.")
             }

             try audioSession.setActive(true)
        } catch {
             print("Failed to activate audio session for streaming: \(error.localizedDescription)")
             return
        }


        // Start the engine if it's not already running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Audio engine started successfully for streaming.")
                // Apply initial audio processing settings if needed
                // configureEQ(profile: .default) // Example
                // configureDynamics(enabled: true) // Example
            } catch {
                print("Could not start audio engine: \(error.localizedDescription)")
                return
            }
        } else {
             print("Audio engine already running.")
        }

        // TODO: Implement actual streaming to the connected Bluetooth peripheral if needed.
        // Currently, this setup routes microphone input through effects to the *default* output (which should be Bluetooth if connected).
        // Direct streaming to a *specific* peripheral characteristic requires more complex handling (e.g., encoding audio data and writing to a characteristic).
        // For many hearing aids/earbuds, simply routing to the system output via AVAudioEngine while they are the active Bluetooth route is sufficient.
        print("Audio streaming setup complete. Mic input is being processed and routed to the default output.")

    }

    func stopAudioStreaming() {
        if audioEngine.isRunning {
            audioEngine.stop()
            print("Audio engine stopped.")
        }
        // Deactivate audio session if no longer needed? Consider carefully.
        // do {
        //     try AVAudioSession.sharedInstance().setActive(false)
        // } catch {
        //     print("Failed to deactivate audio session: \(error.localizedDescription)")
        // }
    }

    // MARK: - Audio Processing Configuration (Examples)

     func configureEQ(bands: [Int: Float]) { // Example: bands is [frequency: gain]
         guard let inputFormat = eqNode?.outputFormat(forBus: 0) else { return }
         let sampleRate = Float(inputFormat.sampleRate)

         for bandIndex in 0..<eqNode.bands.count {
             let band = eqNode.bands[bandIndex]
             if let gain = bands[Int(band.frequency)] { // Match frequency roughly
                 band.gain = gain
                 band.bypass = false
             } else {
                 // Reset or bypass unused bands
                 band.gain = 0
                 band.bypass = true // Bypass if no gain specified for this band
             }
             // Configure other band parameters if needed (bandwidth, filter type)
         }
         print("EQ configured.")
     }

     func configureDynamics(enabled: Bool, threshold: Float = -20, ratio: Float = 5) {
         if enabled {
             dynamicsNode.threshold = threshold
             dynamicsNode.compressionAmount = ratio
             // Configure other dynamics parameters (attack, release, masterGain)
             print("Dynamics Processor enabled with threshold: \(threshold), ratio: \(ratio)")
         } else {
             // Bypassing dynamics might be tricky; often better to set neutral parameters
             dynamicsNode.threshold = 0 // Effectively disable compression
             dynamicsNode.masterGain = 0
             print("Dynamics Processor set to neutral.")
             // Alternatively, disconnect/reconnect nodes to bypass, but more complex
         }
     }

     // TODO: Add functions for Noise Reduction, Voice Enhancement configuration

    // MARK: - Audio Processing Profile Configuration
    /// Configure the EQ and dynamics based on the selected audio profile
    func configureProfile(_ profile: AudioProfile) {
        switch profile {
        case .standard:
            // Bypass all EQ bands for flat response
            eqNode.bands.forEach { $0.bypass = true }
            // Reset dynamics to neutral
            dynamicsNode.threshold = 0
            dynamicsNode.masterGain = 0
        case .wideSpectrum:
            // Allow all frequencies, flat gain
            eqNode.bands.forEach {
                $0.filterType = .parametric
                $0.bypass = false
                $0.gain = 0
                $0.bandwidth = 1.0
            }
            // Neutral dynamics
            dynamicsNode.threshold = 0
            dynamicsNode.masterGain = 0
        case .voiceIsolation:
            // Voice isolation: band-pass around speech frequencies (e.g., 150Hz to 6000Hz)
            // Configure first band as high-pass
            if eqNode.bands.count >= 2 {
                let highPass = eqNode.bands[0]
                highPass.filterType = .highPass
                highPass.bypass = false
                highPass.frequency = 150
                highPass.bandwidth = 0.5
                // Configure second band as low-pass
                let lowPass = eqNode.bands[1]
                lowPass.filterType = .lowPass
                lowPass.bypass = false
                lowPass.frequency = 6000
                lowPass.bandwidth = 0.5
                // Bypass remaining bands
                for bandIndex in 2..<eqNode.bands.count {
                    eqNode.bands[bandIndex].bypass = true
                }
            }
            // Slight compression for voice clarity
            dynamicsNode.threshold = -20
            dynamicsNode.compressionAmount = 3
            dynamicsNode.masterGain = 2
        }
        print("Audio profile set to \(profile.rawValue)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print("HearingAidApp deinitialized.")
    }
}

// MARK: - Helper for RouteChangeReason Description
extension AVAudioSession.RouteChangeReason: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .newDeviceAvailable: return "NewDeviceAvailable"
        case .oldDeviceUnavailable: return "OldDeviceUnavailable"
        case .categoryChange: return "CategoryChange"
        case .override: return "Override"
        case .wakeFromSleep: return "WakeFromSleep"
        case .noSuitableRouteForCategory: return "NoSuitableRouteForCategory"
        case .routeConfigurationChange: return "RouteConfigurationChange"
        @unknown default: return "UnknownFutureCase"
        }
    }
} 