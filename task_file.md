# Hearing Aid App Development Roadmap

## Research and Planning
- Investigate Bluetooth audio profiles and compatibility.
- Explore audio processing libraries and machine learning models for voice recognition.

## Design
- Create wireframes and design the user interface.
- Plan the user experience, focusing on simplicity and accessibility.

## Prototyping
- Develop a prototype to test Bluetooth connectivity and basic audio processing features.
- Implement a basic hearing test to create user profiles.

## Development
- Implement core features: noise reduction, automatic gain control, frequency equalization, and echo cancellation.
- Develop advanced features: voice enhancement and user voice recognition/removal.

## Testing
- Conduct user testing to refine features and ensure compatibility with various devices.
- Perform accessibility testing to ensure the app is usable by all users.

## Launch and Feedback
- Launch the app on the App Store.
- Gather user feedback and iterate on features and functionalities.

## Detailed Software Development Steps

### 1. Bluetooth Audio Integration
- [X] **Research**: Identify the Bluetooth audio profiles (e.g., A2DP, HFP) that are compatible with most hearing aids and earbuds.
- [X] **Implementation**: Use the CoreBluetooth framework to establish connections with Bluetooth devices.
- [ ] **Testing**: Ensure stable connections and audio streaming with various devices, including Dime 3 earbuds. (Requires user testing)

### 2. Audio Processing
- [X] **Setup**: Initialize AVAudioEngine, input/output nodes, and basic processing graph.
- [X] **Noise Reduction**: Implement basic noise reduction using AVAudioEngine and AVAudioUnitEQ. (Basic EQ/Dynamics implemented, advanced NR pending)
- [X] **Automatic Gain Control**: Use AVAudioUnitDynamicsProcessor to maintain consistent audio levels. (Implemented)
- [X] **Frequency Equalization**: Customize audio frequencies based on a predefined hearing profile using AVAudioUnitEQ. (Basic EQ node in place, configuration pending Hearing Test -> Implemented, profile application done)
- [ ] **Voice Enhancement**: Focus on enhancing speech frequencies using AVAudioUnitEQ. (Can be done via EQ, configuration pending)

### 3. User Voice Recognition and Removal
- [ ] **Research**: Explore machine learning models that can recognize and filter out the user's voice.
- [ ] **Implementation**: Integrate a basic model using CoreML or a third-party library.
- [ ] **Testing**: Evaluate the effectiveness of voice removal in different environments.

### 4. User Interface Development
- [X] **Design**: Create a simple UI with controls for volume, noise reduction, and profile management.
- [X] **Implementation**: Use SwiftUI to build the interface. (Basic structure exists, controls pending -> Implemented with controls and navigation)
- [ ] **Testing**: Ensure the UI is intuitive and responsive. (Requires user testing)

### Required Permissions
For the app to function correctly, you need to add the following permissions to the project's Info.plist file:
- **Microphone**: Add `NSMicrophoneUsageDescription` with a description of why the app needs microphone access.
- **Bluetooth**: Add `NSBluetoothAlwaysUsageDescription` with a description of why the app needs Bluetooth access.

To add these, find the Info.plist file in your Xcode project and add these entries:
```
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone to capture audio for hearing enhancement.</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to connect to your hearing aids or earbuds.</string>
```

You may also need to add the following background modes to support audio in the background:
```
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>bluetooth-central</string>
</array>
```

### Next Steps
1. Test the app with your Dime 3 earbuds
2. Implement the Hearing Test functionality
3. Refine the audio processing based on user feedback

### 5. Hearing Test Implementation
- [X] **Design**: Develop a simple hearing test to assess the user's hearing profile.
- [X] **Implementation**: Use AVFoundation to play test tones and record user responses.
- [ ] **Testing**: Validate the accuracy and reliability of the hearing test.

### 6. Prototype Testing
- **Device Compatibility**: Test the prototype with various hearing aids and earbuds.
- **Audio Quality**: Evaluate the audio processing features in different environments.
- **User Feedback**: Gather feedback from users to identify areas for improvement. 