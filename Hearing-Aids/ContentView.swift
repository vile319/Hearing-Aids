//
//  ContentView.swift
//  Hearing-Aids
//
//  Created by tannery on 4/14/25.
//

import SwiftUI
import AVFoundation
import AudioToolbox

// Manager class to handle audio processing
class AudioManager: NSObject, ObservableObject {
    // Audio Processing State
    @Published var isNoiseReductionEnabled: Bool = false {
        didSet {
            updateNoiseReduction()
        }
    }
    @Published var masterGain: Float = 0.0 { // dB, range -90 to 20
        didSet {
            if let paramTree = dynamicsProcessor?.auAudioUnit.parameterTree {
                paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_OverallGain))?.value = masterGain
            }
        }
    }
    @Published var hearingProfile: [Int: Float] = [:] { // Store hearing test results [Hz: Threshold dB]
        didSet {
            print("Hearing profile updated: \(hearingProfile)")
        }
    }
    
    @Published var audioRouteDescription: String = "Checking audio route..."
    @Published var isAudioActive: Bool = false

    private var audioEngine: AVAudioEngine!
    private var mixerNode: AVAudioMixerNode!
    private var eqNode: AVAudioUnitEQ?
    private var dynamicsProcessor: AVAudioUnitEffect?
    
    // Test Tone Generator
    private var sourceNode: AVAudioSourceNode?
    private var toneFrequency: Float = 440.0 // Hz
    private var toneAmplitude: Float = 0.0   // Linear amplitude (0-1)
    private var tonePhase: Float = 0.0
    private var toneSampleRate: Double = 44100.0

    override init() {
        super.init()
        setupAudioEngine()
        setupNotifications()
    }
    
    private func setupNotifications() {
        // Monitor for audio route changes (like connecting/disconnecting Bluetooth headphones)
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(handleRouteChange),
                                              name: AVAudioSession.routeChangeNotification, 
                                              object: nil)
        updateAudioRouteInfo()
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        updateAudioRouteInfo()
        
        // If we're already running, restart audio engine to adapt to the new route
        if isAudioActive {
            stopAudioEngine()
            startAudioEngine()
        }
    }
    
    private func updateAudioRouteInfo() {
        // Get current audio route info
        let currentRoute = AVAudioSession.sharedInstance().currentRoute
        let outputs = currentRoute.outputs
        
        if outputs.isEmpty {
            audioRouteDescription = "No audio output connected"
        } else {
            // Show information about all outputs (usually just one)
            let outputDescriptions = outputs.map { output -> String in
                let portType = output.portType
                let portName = output.portName
                
                // Convert port type to human-readable format
                var typeString = "Unknown"
                switch portType {
                case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                    typeString = "Bluetooth"
                case .headphones:
                    typeString = "Wired Headphones"
                case .builtInSpeaker:
                    typeString = "Built-in Speaker"
                case .builtInReceiver:
                    typeString = "Phone Speaker"
                default:
                    typeString = portType.rawValue
                }
                
                return "\(typeString): \(portName)"
            }
            
            audioRouteDescription = "Audio Output: " + outputDescriptions.joined(separator: ", ")
        }
    }

    // MARK: - Audio Engine Setup
    func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()

        // Increase EQ bands for hearing profile
        let numberOfBands = 7 // Match common audiogram frequencies
        eqNode = AVAudioUnitEQ(numberOfBands: numberOfBands)
        
        // Create dynamics processor using component description
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        dynamicsProcessor = AVAudioUnitEffect(audioComponentDescription: componentDescription)

        guard let eqNode = eqNode, let dynamicsProcessor = dynamicsProcessor else {
            print("Error: Could not initialize audio units.")
            return
        }

        // Configure Dynamics Processor
        if let paramTree = dynamicsProcessor.auAudioUnit.parameterTree {
            // Set initial values for dynamics processor
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_OverallGain))?.value = masterGain
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_Threshold))?.value = -20.0
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_HeadRoom))?.value = 5.0
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_AttackTime))?.value = 0.001
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ReleaseTime))?.value = 0.05
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_CompressionAmount))?.value = 6.0
            
            // Disable expansion
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionRatio))?.value = 1.0
            paramTree.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionThreshold))?.value = -100.0
        }

        // Set initial EQ bands (flat)
        eqNode.globalGain = 1.0
        let freqs: [Float] = [125, 250, 500, 1000, 2000, 4000, 8000]
        for i in 0..<numberOfBands {
            if i < eqNode.bands.count {
                eqNode.bands[i].filterType = .parametric
                eqNode.bands[i].frequency = freqs[i]
                eqNode.bands[i].gain = 0 // Flat gain initially
                eqNode.bands[i].bandwidth = 0.5
                eqNode.bands[i].bypass = false
            }
        }

        // Create tone generator node with a simpler implementation
        let sampleRate: Double = 44100.0 // Standard sample rate
        toneSampleRate = sampleRate
        
        // Define format for the source node - explicit stereo format
        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )
        
        guard let sourceFormat = sourceFormat else {
            print("Failed to create source format")
            return
        }
        
        // Create source node with explicit format
        sourceNode = AVAudioSourceNode { [weak self] (_, timeStamp, frameCount, audioBufferList) -> OSStatus in
            guard let self = self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            if abl.count == 0 { return noErr }
            
            // Calculate sine wave sample for this buffer
            let twoPi = 2.0 * Float.pi
            
            for frame in 0..<Int(frameCount) {
                // Generate sine wave
                let phaseIncrement = twoPi * self.toneFrequency / Float(self.toneSampleRate)
                let value = sin(self.tonePhase) * self.toneAmplitude
                self.tonePhase += phaseIncrement
                if self.tonePhase >= twoPi {
                    self.tonePhase -= twoPi
                }
                
                // Fill all available channels with the same value
                for bufferIndex in 0..<abl.count {
                    let buf = abl[bufferIndex]
                    let bufferPointer = UnsafeMutableBufferPointer<Float>(
                        start: buf.mData?.assumingMemoryBound(to: Float.self),
                        count: Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                    )
                    
                    if frame < bufferPointer.count {
                        bufferPointer[frame] = value
                    }
                }
            }
            
            return noErr
        }
        
        guard let sourceNode = sourceNode else {
            print("ERROR: Could not create source node")
            return
        }

        // Attach all nodes to the engine
        audioEngine.attach(mixerNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(dynamicsProcessor)
        audioEngine.attach(sourceNode)

        // Get nodes and formats
        let inputNode = audioEngine.inputNode
        let outputNode = audioEngine.outputNode
        
        // Get valid formats
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
        
        // Create a proper output format with matching sample rate
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: outputNode.outputFormat(forBus: 0).channelCount,
            interleaved: false
        )
        
        if let outputFormat = outputFormat {
            print("Output format: \(outputFormat.sampleRate) Hz, \(outputFormat.channelCount) channels")
            
            // IMPORTANT: Connect the COMPLETE processing chain with all nodes
            // Input → Dynamics Processor → EQ → Mixer → Output
            audioEngine.connect(inputNode, to: dynamicsProcessor, format: inputFormat)
            audioEngine.connect(dynamicsProcessor, to: eqNode, format: inputFormat)
            audioEngine.connect(eqNode, to: mixerNode, format: inputFormat)
            audioEngine.connect(mixerNode, to: outputNode, format: outputFormat)
            
            // Add the tone generator separately to the mixer (for hearing test)
            audioEngine.connect(sourceNode, to: mixerNode, format: sourceFormat)
            
            print("Connected full processing chain: Input → Dynamics → EQ → Mixer → Output")
        } else {
            print("ERROR: Could not create valid output format")
            return
        }
        
        // Set mixer output volume to a moderate level to prevent feedback
        mixerNode.outputVolume = 0.5
        
        audioEngine.prepare()
        print("Audio engine prepared with full processing chain")
    }

    func startAudioEngine() {
        guard !audioEngine.isRunning else { return }
         
        do {
            // Configure and activate the audio session first
            let audioSession = AVAudioSession.sharedInstance()
            
            // Use voiceProcessing mode to help with feedback cancellation
            try audioSession.setCategory(.playAndRecord, 
                                        mode: .voiceChat,  // Changed to valid mode for feedback reduction
                                        options: [.allowBluetoothA2DP, .allowBluetooth, .defaultToSpeaker])
            
            // Use a lower buffer duration for lower latency
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms
            
            try audioSession.setActive(true)
            print("Audio Session Activated")

            // After activating session, start the engine
            try audioEngine.start()
            isAudioActive = true
            print("Audio Engine Started")
            
            // Update audio route info after starting
            updateAudioRouteInfo()
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
            isAudioActive = false
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    func stopAudioEngine() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.reset()
        isAudioActive = false
        print("Audio Engine Stopped")
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio Session Deactivated")
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Audio Processing Control
    private func updateNoiseReduction() {
        guard let eqNode = eqNode else { return }
        let lowBandGain: Float = isNoiseReductionEnabled ? -15.0 : 0.0
        if eqNode.bands.count > 0 {
            eqNode.bands[0].gain = lowBandGain // Assumes band 0 is low frequency
        }
        print("Noise Reduction \(isNoiseReductionEnabled ? "Enabled" : "Disabled"). Low Band Gain: \(lowBandGain)")
    }

    func applyHearingProfile() {
        guard let eqNode = eqNode else { return }

        print("Applying hearing profile: \(hearingProfile)")
        let standardFrequencies: [Int] = [125, 250, 500, 1000, 2000, 4000, 8000]

        for i in 0..<eqNode.bands.count {
            let band = eqNode.bands[i]
            let targetFrequency = standardFrequencies[i]
            band.frequency = Float(targetFrequency)

            if let threshold = hearingProfile[targetFrequency] {
                // Simple mapping: Higher threshold means more hearing loss,
                // so apply positive gain. Clamp gain to a reasonable range.
                // This mapping is simplified and needs clinical validation/refinement.
                let gain = min(max(threshold, 0), 30.0) // Apply gain based on threshold, capped 0 to 30 dB
                band.gain = gain
                print("  - Freq: \(targetFrequency) Hz, Threshold: \(threshold) dB, Applied Gain: \(gain) dB")
            } else {
                // If frequency not in profile, keep gain flat
                band.gain = 0
                print("  - Freq: \(targetFrequency) Hz, Not in profile, Gain: 0 dB")
            }
            band.bandwidth = 0.5 // Keep bandwidth relatively narrow
            band.bypass = false
        }
    }

    // MARK: - Test Tone Control
    func playTestTone(frequency: Float, dBHL: Float) {
        guard let sourceNode = sourceNode, audioEngine.isRunning else {
            print("Cannot play tone: SourceNode nil or engine not running.")
            return
        }
        // Convert dB HL to linear amplitude (0-1)
        // This conversion is complex and needs calibration based on device output & HL definition.
        // VERY Simplified Example: Assume 0 dB HL is -60 dBFS, and max output (0 dBFS) is 90 dB HL
        // So, amplitude = 10^((dBHL - 90) / 20)
        // Clamp dBHL to a reasonable range, e.g., 0 to 90 dB HL for this formula
        let clamped_dBHL = min(max(dBHL, 0), 90)
        let dBFSCorresponding = clamped_dBHL - 90.0 // dBFS value for the target dB HL
        let linearAmplitude = pow(10.0, dBFSCorresponding / 20.0)

        print("Playing tone: Freq=\(frequency) Hz, dBHL=\(dBHL), Target Amplitude=\(linearAmplitude)")
        self.toneFrequency = frequency
        self.toneAmplitude = linearAmplitude // Set amplitude for source node block
        self.tonePhase = 0 // Reset phase
    }

    func stopTestTone() {
        // Simply set amplitude to 0 to stop the tone
        print("Stopping tone (setting amplitude to 0)")
        self.toneAmplitude = 0.0
    }

    func saveHearingProfile(results: [Int: Float]) {
        self.hearingProfile = results
        // Optionally auto-apply
        // applyHearingProfile()
    }
}

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Audio Route Information
                Text(audioManager.audioRouteDescription)
                    .padding(.horizontal)
                    .padding(.top)
                
                Divider()
                
                // Audio Controls Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Audio Controls")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    // Start/Stop Button
                    Button(audioManager.isAudioActive ? "Stop Audio" : "Start Audio") {
                        if audioManager.isAudioActive {
                            audioManager.stopAudioEngine()
                        } else {
                            audioManager.startAudioEngine()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(audioManager.isAudioActive ? .red : .green)
                    .padding(.horizontal)
                    
                    // Audio Processing Controls (only show when audio is active)
                    if audioManager.isAudioActive {
                        // Noise Reduction Toggle
                        Toggle("Noise Reduction", isOn: $audioManager.isNoiseReductionEnabled)
                            .padding(.horizontal)
                        
                        // Master Gain Slider
                        HStack {
                            Text("Master Gain (dB):")
                            Slider(value: $audioManager.masterGain, in: -60...10, step: 1.0)
                            Text(String(format: "%.0f", audioManager.masterGain))
                                .frame(width: 40, alignment: .trailing)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Divider()
                
                // Hearing Profile Section (only show when audio is active)
                if audioManager.isAudioActive {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Hearing Profile")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        NavigationLink(destination: HearingTestView().environmentObject(audioManager)) {
                            Text("Perform Hearing Test")
                        }
                        .padding(.horizontal)
                        
                        Button("Apply Hearing Profile") {
                            audioManager.applyHearingProfile()
                        }
                        .disabled(audioManager.hearingProfile.isEmpty)
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Hearing Aid")
        }
        .onDisappear {
            // audioManager.stopAudioEngine()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            print("App resigning active, stopping engine.")
            // audioManager.stopAudioEngine() // Or let background modes handle it?
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            print("App became active.")
            // Restart engine if needed
            if audioManager.isAudioActive {
                // audioManager.startAudioEngine()
            }
        }
    }
}

#Preview {
    ContentView()
}
