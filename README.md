# Client for JetKVM

**Disclaimer: This is an independent, third-party application and is not affiliated with, endorsed by, or associated with BuildJet.**

A native iPadOS and macOS client for connecting to JetKVM devices, providing remote video, keyboard, and mouse control.

## Features

-	Input Support: Sends touches, clicks, and keystrokes to the remote machine. Supports both on-screen and external hardware keyboards.

-	macOS Keyboard Capture: Routes system-level shortcuts (like ⌘ Space) to the remote machine instead of the local Mac. This requires Accessibility permissions (System Settings → Privacy & Security → Accessibility).

-	Custom Shortcuts: Maps key combinations (e.g., Ctrl+Alt+Del) to toolbar buttons. Shortcuts are configurable per device via the sidebar.

-	Native UI: Built with SwiftUI to support standard iPadOS multitasking and macOS windowing.

## Building from Source

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`.

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open JetKVM.xcodeproj
```

Then build and run for your target (iPad or macOS) from Xcode.

Signed builds available for macos from the releases tab. 

Appstore for ipad pending review.

## License

MIT — see [LICENSE](LICENSE) for details.
