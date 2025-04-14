import SwiftUI

struct HearingTestView: View {
    // Use AudioManager from the environment
    @EnvironmentObject var audioManager: AudioManager
    @StateObject private var testViewModel = HearingTestViewModel()

    var body: some View {
        VStack {
            Text("Hearing Test")
                .font(.largeTitle)
                .padding()

            if testViewModel.isTesting {
                Text("Playing tone at \(testViewModel.currentFrequency) Hz")
                Text("Level: \(String(format: "%.1f", testViewModel.currentLevel)) dB HL") // dB HL
                Button("I Hear It") {
                    testViewModel.recordResponse(heard: true)
                }
                .padding()
                .buttonStyle(.borderedProminent)
                Button("I Don\'t Hear It") {
                     testViewModel.recordResponse(heard: false)
                 }
                 .padding()
                 .buttonStyle(.bordered)
            } else {
                Text(testViewModel.testStatus)
                    .padding()
                Button(testViewModel.testResults.isEmpty ? "Start Test" : "Restart Test") {
                    testViewModel.startTest()
                }
                .padding()
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            // Display Results
            if !testViewModel.testResults.isEmpty {
                Text("Test Results (Threshold in dB HL):")
                 List { ForEach(testViewModel.testResults.sorted(by: { $0.key < $1.key }), id: \.key) { freq, threshold in
                     Text("\(freq) Hz: \(threshold == 999.0 ? "N/A" : String(format: "%.0f", threshold))")
                     }
                 }
                 .frame(maxHeight: 200) // Limit height of results list
            }
        }
        .navigationTitle("Hearing Test")
        // Pass the audioManager to the ViewModel when the view appears
        .onAppear {
            testViewModel.audioManager = audioManager
        }
        .onDisappear {
             // Ensure tone is stopped when leaving the view
             testViewModel.stopTone()
             if testViewModel.isTesting {
                 testViewModel.isTesting = false // Reset testing state
                 testViewModel.testStatus = "Test cancelled."
             }
         }
    }
}

// Simple ViewModel for Hearing Test Logic
class HearingTestViewModel: ObservableObject {
    // Keep track of the audio manager
    var audioManager: AudioManager? // Weak reference not strictly needed for EnvObj

    @Published var isTesting = false
    @Published var currentFrequency: Int = 125
    @Published var currentLevel: Float = 30.0 // dB HL
    @Published var testStatus = "Press Start to begin the hearing test."
    @Published var testResults = [Int: Float]()

    private let testFrequencies = [125, 250, 500, 1000, 2000, 4000, 8000]
    private var currentFrequencyIndex = 0
    private let maxLevel: Float = 90.0 // Max dB HL
    private let minLevel: Float = 0.0 // Min dB HL
    private let levelStep: Float = 5.0 // dB step

    // Use AudioManager for audio interaction
    func playTone(frequency: Int, level: Float) {
        guard let audioManager = audioManager else {
            print("ViewModel Error: AudioManager not set.")
            testStatus = "Error: Audio Manager unavailable."
            isTesting = false
            return
        }
        print("ViewModel: Requesting tone - Freq=\(frequency) Hz, Level=\(level) dB HL")
        audioManager.playTestTone(frequency: Float(frequency), dBHL: level)
    }

    func stopTone() {
        print("ViewModel: Requesting stop tone.")
        audioManager?.stopTestTone()
    }

    func startTest() {
        guard audioManager != nil else {
            testStatus = "Cannot start: Audio Manager unavailable."
            return
        }
        testResults.removeAll()
        currentFrequencyIndex = 0
        currentFrequency = testFrequencies[currentFrequencyIndex]
        currentLevel = 30.0
        isTesting = true
        testStatus = "Testing... Find the quietest level you can hear."
        playTone(frequency: currentFrequency, level: currentLevel)
    }

    // More robust threshold finding logic (Ascending Method - Simplified)
     func recordResponse(heard: Bool) {
         stopTone()

         if heard {
             // They heard it. This is their threshold for this frequency.
             print("Heard at \(currentLevel) dB HL for \(currentFrequency) Hz")
             testResults[currentFrequency] = currentLevel
             goToNextFrequency()
         } else {
             // They didn't hear it. Increase level.
             currentLevel += levelStep
             if currentLevel > maxLevel {
                 // Reached max level without hearing
                 print("Not heard up to max level (\(maxLevel) dB HL) for \(currentFrequency) Hz")
                 testResults[currentFrequency] = 999.0 // Mark as not heard
                 goToNextFrequency()
             } else {
                 // Try again at the higher level
                 print("Not heard at \(currentLevel - levelStep) dB HL. Trying \(currentLevel) dB HL.")
                 playTone(frequency: currentFrequency, level: currentLevel)
             }
         }
     }

    private func goToNextFrequency() {
        currentFrequencyIndex += 1
        if currentFrequencyIndex < testFrequencies.count {
            currentFrequency = testFrequencies[currentFrequencyIndex]
            currentLevel = 30.0 // Reset starting level for next frequency
            print("--- Moving to next frequency: \(currentFrequency) Hz ---")
            playTone(frequency: currentFrequency, level: currentLevel)
        } else {
            // Test finished
            isTesting = false
            testStatus = "Test Complete!"
            print("--- Test Finished --- Final Results: \(testResults)")
            // Save results to AudioManager
             if let audioManager = audioManager {
                 audioManager.saveHearingProfile(results: testResults)
             }
        }
    }
}


#Preview {
    NavigationView {
        HearingTestView()
           .environmentObject(AudioManager()) // Provide mock for preview
    }
} 