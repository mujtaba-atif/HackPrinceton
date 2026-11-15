# Iris: flows, voice and setup

## Flow

1. **Loading → Home.** Iris says "Hello, this is Iris…" and listens for "continue", "okay", "next", "start", "begin", "go", "yes" or "ready". You can also swipe up.
2. **Main.** Iris asks "Are you looking for something, or do you want help exploring something?"
   - Say **find** or **locate** (also "looking for", "search") to open Locate.
   - Say **understand**, **analyze** or **explore** to open Explore.
   - Say **repeat** to hear the question again, say **go back**, or tap either full-width diagonal panel.
3. **Locate**
   1. Iris asks "What do you want to find?". Your answer is matched to one of the segmentation model's 80 classes ("water bottle" → bottle, "my phone" → cell phone). If it doesn't match a class, or you say nothing for 12 s, Iris looks for a bottle.
   2. Three steps follow, each announced and marked by a chime: **reach out** (depth), **move across**, then **take hold**. A stereo tone, spoken cues, the on-screen direction and haptics steer you. Four subtle optical rails frame the camera view. Headphones are needed to hear left and right; the chime and voice work without them.
   3. The object has a translucent green highlight from its live segmentation mask. Hand landmarks and a fingertip connector share the camera crop, and both distance labels show measured meters. Missing hands suppress the measurement; unavailable depth never becomes a guessed distance. Confetti marks the moment you reach it.
   4. When you've picked the object up and brought it within about 10 inches of the camera, Iris reads the label and hands over to the ElevenLabs agent ("Let me see what you're holding").
4. **Explore**
   1. Iris says "Hold the item in front of the camera so I can read it."
   2. The pill changes from **Looking for text…** to **Reading live…** as OCR finds text. Two matching consolidated results trigger the summary; there is no visible hold timer or countdown. If nothing is readable, Iris gives a hint: at most two, first after 8 s, then every 12 s.
   3. Iris says "Text detected." and the agent summarizes the item in one or two sentences. If the agent can't be reached, or drops, Iris reads the label out itself and listens for "go back".
5. **Anywhere:** "go back" leaves the screen.
   - During a conversation, "goodbye", "go back" or "I'm done" ends it.
   - "Scan again" (or the agent's `rescan` tool) reads the label again.

The microphone only opens while Iris isn't speaking, and during a conversation it's muted while the agent talks.

## ElevenLabs setup

1. Create the agent: go to https://elevenlabs.io/app/agents, choose **New agent → Blank Agent**, and name it Iris.
2. In the **Agent** tab:
   - **First message:** `Let me see what you're holding.`
   - **System prompt** (Explore uses it as-is):
     > You are Iris, a voice guide for someone who cannot see. They are holding an item up to their phone's camera, and you are given the text read off its label. Tell them what it is and the one or two things on it that actually matter (the brand, a flavour or a strength, a warning, a date), then stop and let them ask. Answer in at most three short spoken sentences, plainly, with no lists and no markdown, and never read the whole label out unless they ask you to. Never mention text, scanning, OCR or the camera: just say what the thing is. If what you were given is garbled or empty, say so and offer to look again. rescan is a tool you can call for that, and it takes a few seconds.
   - **Voice:** pick the Primary voice. The app's own lines use the same voice.
3. In **Security**:
   - Authentication **off** (the agent is public).
   - Allow overrides for **System prompt**, **First message** and **Voice**. Locate sends its own persona, and both screens send the voice settings.
4. In **Tools**, add a **Client** tool named `rescan` with no parameters and **Wait for response** on.
5. **Publish** the agent.
6. Create an API key: **Developers → API Keys**. Copy the `sk_…` value straight away; it's only shown once. Restrict it to Text to Speech and give it a low credit limit, because it ships inside the app.
7. Copy the template and fill it in:
   ```sh
   cp Iris/Secrets.swift.example Iris/Secrets.swift   # git-ignored
   ```
   Fill in `elevenLabsAPIKey`, `elevenLabsAgentID` and `elevenLabsVoiceID`. For the voice ID, open the agent → Voices → your voice → ⋯ → **Copy voice ID**.

Without a key, every line is spoken by the on-device voice. Without an agent ID, Locate speaks what it read off the label itself, and Explore has no agent summary.

## Testing on an iPhone

You need a physical iPhone; LiDAR models get depth-based guidance, and others fall back to on-screen distance. Pick your team under Signing & Capabilities, run the `Iris` scheme, and allow the microphone, speech recognition and camera.

- **Home:** say "continue". On Main, say "locate", then "bottle".
- **Locate:** with headphones on, follow the steps to the bottle, pick it up and bring it toward the camera until the status panel says “Close enough”. Iris should talk about it.
- **Explore:** go back to Main, say "explore", and hold a label in view until recognition is ready. Iris should summarize it.
- **Voice:** all lines should be in your ElevenLabs voice. Turn on airplane mode and they should switch to the on-device voice.
- **Background:** background the app on any screen and the microphone indicator should turn off.

## Developer screens

In Debug builds, long-press the home screen for 2 seconds. This opens:
- the original Iris home
- the original Explore screen: object list, depth readout, and the **Turn to Read** label sheet that guides you to turn an item until its label faces the camera
- the hand-tracking debug screen
