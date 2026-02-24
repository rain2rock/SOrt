# SOrt

**SOrt** is an iOS app that helps you clean up your photo library — one day at a time. It surfaces photos and videos taken on this exact calendar date in previous years, and lets you quickly decide what to keep and what to delete with a simple swipe.

---

## How It Works

Every day, SOrt shows you memories from the same date in past years — like a personal "On This Day" feed. Swipe left to mark for deletion, swipe right to keep. Once you've reviewed everything, delete all marked photos in one tap.

---

## Features

- **On This Day** — browse all photos and videos shot on the current calendar date across every year in your library
- **Swipe to sort** — swipe left to mark for deletion, swipe right to keep
- **Videos supported** — videos play inline so you can decide before deleting
- **Location names** — reverse geocoding shows where each photo was taken
- **Batch deletion** — photos marked for deletion are queued and removed all at once
- **Undo** — made a mistake? Undo the last action instantly
- **Date picker** — tap the date pill to jump to any date in your library
- **Session persistence** — your progress is saved across app launches; already-reviewed photos won't show up again until the next day
- **Adaptive UI** — the interface detects light vs dark photo backgrounds and adjusts contrast accordingly
- **Haptic feedback** — subtle vibration when a card is swiped away

---

## Screenshots

> Add your screenshots here

---

## Requirements

- iOS 16.0+
- Xcode 15+
- Swift 5.9+
- Photo library access (read/write)

---

## Installation

1. Clone the repository
```bash
git clone https://github.com/your-username/SOrt.git
```
2. Open `SOrt.xcodeproj` in Xcode
3. Select your development team in **Signing & Capabilities**
4. Build and run on a real device (photo library access does not work in Simulator)

---

## Permissions

SOrt requires **Photos** access (read/write) to display and permanently delete photos. The app never uploads your photos anywhere — all processing happens on-device.

Add the following key to `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>SOrt needs access to your photo library to help you sort and clean it up.</string>
```

---

## Tech Stack

- **SwiftUI** — declarative UI
- **PhotoKit** — photo library access and deletion
- **AVKit** — inline video playback
- **CoreLocation / CLGeocoder** — reverse geocoding for location tags
- **UserDefaults** — lightweight session persistence

---

## License

MIT License. See [LICENSE](LICENSE) for details.
