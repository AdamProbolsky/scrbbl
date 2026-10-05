# Contributing to Scrbbl AI

Thanks for helping. Scrbbl is a small SwiftUI + PencilKit app, so changes are usually easy to review.

## Getting set up

1. Follow **Run it** in the [README](README.md): open `Scrbbl.xcodeproj`, pick your own signing team, and run on an iPad or the iPad simulator.
2. Paste your own OpenAI API key in the app's Settings. Never commit a key.
3. In the simulator, the canvas accepts mouse input, so you can test gestures without a Pencil. `scripts/launch-with-key.command` passes a key to a Debug build.

## Where things live

- **Gestures** (triple underline, circle, and finding the text they point at): `Scrbbl/TripleUnderlineDetector.swift`
- **AI requests and streaming**: `Scrbbl/NoteCanvasModel.swift`
- **Canvas and answer box**: `Scrbbl/NoteCanvasView.swift`

## Pull requests

- Keep each pull request focused on one change, and describe how you tested it (simulator, real iPad, Pencil or finger).
- Gesture changes: say what you drew to confirm it still fires on real underlines and circles, and **doesn't** fire while writing normal cursive.
- Match the existing style: SwiftUI, small focused types, short comments that explain *why*.
- Keep the look clean and simple: black ink on white, system font for the interface, the handwriting font for answers.

## Reporting bugs

Open an issue with your iPad model, iPadOS version, what you wrote or drew, and what happened. A screenshot or short screen recording helps a lot.

## License

By contributing, you agree that your contributions are licensed under the MIT License in [LICENSE](LICENSE).
