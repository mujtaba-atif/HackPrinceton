# Iris: flows, voice and setup

## Flow

1. **Loading → Home.** Iris says "Hello, this is Iris…" and listens for "continue", "okay", "start" and similar. You can also swipe up.
2. **Main.** Iris asks, "Do you want to locate something, or explore something you're holding?" Say **locate**/**find** or **explore**/**read**, or tap a card. "Repeat" asks the question again.
3. **Locate**
   1. Iris asks what you're looking for ("my water bottle"). If you say nothing within 12 s, it guides to the most prominent detected object.
      - **Things the detector doesn't know.** The detector has 80 classes. For anything else (pills, keys, a wallet, a pill bottle among other bottles), Iris works out what it looks like and searches by sight. The description comes from a built-in catalog of everyday items first. Failing that, Apple's on-device language model describes it, on phones with Apple Intelligence, with no network or key. The search uses Apple's on-device image classifier (about 1,300 labels) plus color, texture (shiny, matte, patterned, smooth, translucent), shape and size. Colors or sizes you say ("the small orange bottle") always count. A match needs two agreeing passes. If only color and texture agree, Iris says "this might be…" and asks you to check by touch. If Iris can't picture the item at all, it asks you to describe it.
   2. Once the object is detected, a stereo tone, a water ripple and spoken steps guide you. Step 1 is reaching out (depth), step 2 is moving across, and step 3 is taking hold. Headphones are needed to hear left and right; the chime and voice work without them.
      - **Measuring the reach.** The object's distance is read around your hand, never through it. While the object is clearly visible, Iris stores where it is in the room, and uses that position once your hand covers the object. If nothing was stored, it reads the parts of the object still showing. On LiDAR phones, a hand that only overlaps the object on screen counts as touching it only if depth showed the hand within about 12 cm of the object in the last second, which covers a closing grip that hides the fingertips.
      - **Spoken distance.** In step 1, Iris says how far to go ("Reach about 8 inches further"), says when your hand is in front of the object but not at it yet, and says "You've gone past it" if you overshoot. If it can't measure, it asks you to open your hand, or to move it aside so it can see the object. It speaks at most every 2.5 seconds after anything else it says. Without headphones it also says left or right in step 2. Phones without LiDAR get no distances, only "reach out slowly until you touch it."
   3. When you hold the object close enough, Iris reads its label and hands over to the ElevenLabs agent ("Let me see what you're holding").
4. **Explore**
   1. **Turn to Read** says "turn it left", "turn it right", "move it closer" or "hold it steady", while the scan-area ring fills.
   2. After the read, Iris says "Text detected" and the ElevenLabs agent summarizes the item.
   3. Say "try again" to read again.
5. **Anywhere.** "Go back" leaves the screen. During a conversation, "goodbye" or "go back" ends it, and "scan again" (or the agent's `rescan` tool) reads the label again.

The voice for scripted lines is on-device speech (`Speaker`). Only the conversation uses ElevenLabs, and no API key ships in the app.

## ElevenLabs setup

1. Go to https://elevenlabs.io/app/agents, or switch from ElevenCreative to **ElevenAgents** at the bottom left. Choose **New agent → Blank Agent** and name it Iris.
2. In the **Agent** tab:
   - **First message:** `Let me see what you're holding.`
   - **System prompt:** paste `AssistantConfiguration.agentPrompt` from `Iris/Features/Assistant/AssistantConfiguration.swift`.
3. In **Security**:
   - Turn **authentication off**, so the agent is public and needs only its ID.
   - Allow overrides for **System prompt** and **First message**. Each screen sends its own persona. If overrides are refused, Iris reconnects with the dashboard prompt.
4. In **Tools**, add a **Client** tool named `rescan` with no parameters and **Wait for response** on. Description: "Reads the label in front of the camera again. Takes a few seconds."
5. Run `cp Config/Local.xcconfig.example Config/Local.xcconfig`, then set `ELEVENLABS_AGENT_ID = agent_...` in that file. Git ignores it.

Without an agent ID, Locate speaks what it read off the label, and Explore speaks Turn to Read's offline summary.

## Testing on an iPhone

Use a physical iPhone; LiDAR models give the best depth. Pick your team under Signing & Capabilities and run the `Iris` scheme. Allow the microphone, speech recognition and camera when asked.

- **Home:** say "continue". On Main, say "locate".
- **Locate:**
  1. Say "bottle". With headphones on, follow the tone to the bottle and pick it up.
  2. Bring it toward the camera until the status shows the read distance. Iris should talk about it.
- **Explore:** go back to Main and say "explore". Hold a medication or food label and turn it as told. Iris should summarize it, and must not say it's safe.
- Background the app on any screen. The microphone indicator should turn off.

## Developer screens

In Debug builds, long-press the home screen for 2 seconds. This opens the original Iris home with the old Explore screen (object list, depth readout, Read Label sheet) and the hand-tracking debug screen.
