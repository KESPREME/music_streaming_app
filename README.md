# 🎵 Music Streaming App

A state-of-the-art, cross-platform **Music Streaming App** built with [Flutter](https://flutter.dev/).  
Experience instant playback, beautiful glassmorphism UI, and seamless audio streaming from multiple sources.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.0-0175C2?style=for-the-badge&logo=dart)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

## 🚀 Key Features

### 🎧 High-Performance Audio Engine
*   **Hybrid Fetching System**: Prioritizes direct streams for **instant start (<500ms)** while falling back to a robust proxy (YoutubeExplode) for restricted content.
*   **Low-Latency Buffering**: Custom-tuned `AndroidLoadControl` ensures music starts playing the moment the first chunk arrives.
*   **Background Playback**: Full support for background audio and lock screen controls via `just_audio_background`.

### 🎨 Stunning UI/UX
*   **Glassmorphism Design**: Modern, translucent UI elements using `glassmorphism` and `flutter_animate`.
*   **Dynamic Theming**: Color palettes generated from album art for an immersive experience.
*   **Responsive**: Optimized for both Android and iOS devices.

### 🛠️ Core Functionality
*   **Universal Search**: Find songs, artists, and albums from YouTube.
*   **Local Playback**: Play files stored on your device with full metadata support.
*   **Playlist Management**: Create, edit, and share custom playlists.
*   **Lyrics Support**: Real-time synchronized lyrics (where available).
*   **Chromecast Support**: Cast your music to big screens.
*   **Offline Support**: Smart caching and offline mode for low-data environments.

---

## 🛠️ Tech Stack

*   **Framework**: Flutter & Dart
*   **State Management**: `provider`
*   **Audio Core**: `just_audio`, `audio_service`, `youtube_explode_dart`
*   **Backend/Sync**: Firebase (Firestore, Auth)
*   **UI Libraries**: `glassmorphism`, `flutter_animate`, `palette_generator`, `cached_network_image`
*   **Connectivity**: `connectivity_plus`, `internet_connection_checker`
*   **Storage**: `shared_preferences`, `path_provider`

---

## 📂 Project Structure

```text
lib/
├── main.dart               # App Entry Point
├── providers/              # State Management (MVVM-style Providers)
│   └── music_provider.dart # Core logic for playback, queue, and fetching
├── services/               # Backend & Hardware Services
│   ├── audio_service.dart  # Low-level audio player wrapper & config
│   ├── innertube/          # YouTube/InnerTube API handlers
│   ├── auth_service.dart   # Firebase Auth
│   └── ...
├── screens/                # UI Screens (Home, Player, Library, Search)
├── widgets/                # Reusable UI Components (Cards, Bars, Glass Containers)
├── models/                 # Data Models (Track, Album, Playlist)
└── utils/                  # Constants, Theme, Helpers
```

---

## 🚦 Getting Started

### Prerequisites
*   [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version 3.10+)
*   Dart SDK (Version 3.0+)

### Installation

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/KESPREME/music_streaming_app.git
    cd music_streaming_app
    ```

2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Run the app**:
    *   For performance testing, use Profile mode:
        ```bash
        flutter run --profile
        ```
    *   For development:
        ```bash
        flutter run
        ```

---

## 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

---

## 🙋‍♂️ Author

**Nipun Gupta**  
[GitHub](https://github.com/KESPREME) | [LinkedIn](https://www.linkedin.com/in/nipun-gupta-198b90175)

<p align="center">
  Made with ❤️ using Flutter by <a href="https://github.com/KESPREME">KESPREME</a>
</p>
