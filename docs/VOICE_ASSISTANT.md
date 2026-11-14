# Voice assistant, OCR, and speech

Code:

- `Iris/Features/OCR/`: text recognition (Apple Vision)
- `Iris/Features/Speech/`: on-device speech output
- `Iris/Features/Voice/`: on-device voice commands
- `Iris/Features/Assistant/`: the ElevenLabs agent, grounded answers, and the UI

## How it works

- **ElevenLabs first, always.** The mic button starts a live ElevenLabs conversation with Iris. Iris answers from real data, which reaches it three ways:
  - client tools that it calls
  - silent scene updates (`updateContext`) sent about every 2 s while the detected objects change
  - label text the app reads itself and sends as a message when you tap **Read Label**
- **Ending:** say "goodbye", "I'm done", "end conversation" or similar (5 words or fewer), or tap the mic again. **Stop Speaking** interrupts Iris mid-sentence without hanging up.
- **Automatic fallback.** If no agent ID is set, the service can't be reached, or it drops, that turn uses basic on-device commands (Apple Speech plus on-device voice). A "Basic mode" label shows while this happens. The next mic tap tries ElevenLabs again.
- If the agent rejects the prompt overrides (it connects, then drops before speaking), Iris reconnects once using the dashboard prompt.

## Configuration (ElevenLabs)

1. Go to https://elevenlabs.io/app/agents (or switch from ElevenCreative to **ElevenAgents** at the bottom-left), click **New agent**, then **Blank Agent**, and name it Iris. Make it **public**, which means authentication is off. The app sends only the agent ID and never an API key.
2. In **Security**, turn on overrides for **System prompt** and **First message**. Iris sends `AssistantConfiguration.agentPrompt`. Paste that same prompt into the dashboard as well, so the rules still apply if overrides are turned off.
3. Add these **client tools**. Turn on "Wait for response" for each one.

   | Tool | Parameters | Description to give the agent |
   |---|---|---|
   | `get_visible_objects` | none | Lists the objects the camera detects right now, with where each one is |
   | `read_label` | none | Reads printed text on the selected object, or in the middle of the camera view |
   | `find_object` | `name` (string, required) | Finds and selects a named object, if it is detected |
   | `describe_selected_object` | none | Describes the object the user selected |

4. Copy the ID:
   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Then set `ELEVENLABS_AGENT_ID = agent_...` in that file. Git ignores it.

## Testing on a physical iPhone

1. Open `Iris.xcodeproj`, choose your team under Signing, select your iPhone, and run.
2. Go to Home → **Voice assistant debug**. This link only appears in Debug builds. Allow the camera, microphone, and speech recognition when asked.
3. Tap the mic and talk naturally. Try each of these:
   - "What am I looking at?"
   - "What objects are nearby?"
   - "Find my water bottle". It should select the bottle box.
   - "What does this say?", or tap **Read Label** with a medication or food package.
   - "Summarize these instructions"
   - "Is this safe to eat?". The answer should include a refusal and advice to check with someone.
4. Tap **Stop Speaking** while Iris is talking: she should stop but keep listening. Then say "goodbye": the conversation should end. With airplane mode on, the mic should fall back to "Basic mode".
5. Background the app while it is listening or in a conversation. The microphone indicator should turn off.

## Integrating into ExploreView

ExploreView is shared, so this branch doesn't change it. Making these exact edits in `Iris/UI/Exploration/ExploreView.swift` adds the assistant:

```swift
// 1. Add the property, next to the other @StateObjects:
@StateObject private var assistant = VoiceAssistantCoordinator()

// 2. In the bottom .safeAreaInset VStack, above `controls`:
if camera.state == .running {
    VoiceAssistantPanel(assistant: assistant)
        .padding(.horizontal, 12)
}

// 3. Add to the body's modifier chain (for example after .toolbar):
.onAppear {
    assistant.attach(
        frames: { [camera] in camera.makeFrameStream() },
        detection: { [detection] in detection.snapshot },
        select: { [detection] id in detection.select(id) },
        isCameraRunning: { [camera] in camera.state == .running }
    )
}

// 4. In .onChange(of: camera.state), inside the `else` branch (camera not running):
assistant.shutdown()

// 5. In .onChange(of: scenePhase), in the .inactive/.background cases, before pausing the camera:
assistant.shutdown()

// 6. In .onDisappear and exitExplore(), before camera.stop():
assistant.shutdown()
```

The panel is tall. If space is tight, consider limiting `DetectedObjectsList`'s height while the panel is shown, or putting the panel in a sheet.

## Safety and privacy

- The agent sees the camera only through tool results, and those come only from real detections and OCR. Every result states plainly what is uncertain or missing.
- `AssistantFacts.withSafetyNote` adds a fixed "can't confirm it's safe" line to any offline answer or tool result that mentions food, drink, medication, dosage, or allergens. The agent's prompt also forbids saying anything is safe.
- No secret keys are in the client. If you later need a private agent, mint a conversation token on a backend and use `ElevenLabs.startConversation(conversationToken:)`.
