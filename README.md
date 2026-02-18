<div align="center">

  <img src="https://drive.google.com/uc?export=view&id=1mIuXjoW39p52KfcrZ3nyEG2JaWO8eULq" alt="DearMusic Logo" width="120" height="120">

# DearMusic 🎧

**Your Local Library, Finally Intelligent.**

A high-fidelity local music player built with **Flutter** & **Material 3**.
It doesn't just play files; it understands your listening habits, creates yearly **Recaps**, and perfects every transition with smart audio processing.

[![Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Material 3](https://img.shields.io/badge/Design-Material%203-7c4dff?style=for-the-badge&logo=material-design)](https://m3.material.io)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)

[View Features](#-key-features) • [Getting Started](#-getting-started) • [Contributing](#-contributing)

</div>

---

<h2 align="center">🎨 UI/UX Showcase</h2>

<p align="center">
  DearMusic is designed to be immersive. From the <b>Smart Mix</b> suggestions to the <b>expressive progress bar</b>.
</p>

<div align="center">
  <table border="0">
    <tr>
      <td width="33%" align="center"><b>Smart Home</b></td>
      <td width="33%" align="center"><b>Immersive Player</b></td>
      <td width="33%" align="center"><b>Synced Lyrics</b></td>
    </tr>
    <tr>
      <td align="center">
        <img src="https://drive.google.com/uc?export=view&id=1eyynX_omf8mhTHuWnq-tsLdzumiSEgRV" width="100%" alt="Home Screen">
      </td>
      <td align="center">
        <img src="https://drive.google.com/uc?export=view&id=1X5ZUAAdcJMM4AGCPwAo_Mms9mEgRSYA5" width="100%" alt="Player UI">
      </td>
      <td align="center">
        <img src="https://drive.google.com/uc?export=view&id=1iE0quYxzxossypqiYIibzydwKPV2z7E-" width="100%" alt="Lyrics UI">
      </td>
    </tr>
    <tr>
      <td width="33%" align="center"><b>Album Detail</b></td>
      <td width="33%" align="center"><b>Artist Page</b></td>
      <td width="33%" align="center"><b>DearRecap (Wrapped)</b></td>
    </tr>
    <tr>
      <td align="center">
        <img src="https://drive.google.com/uc?export=view&id=131Rm-Kzlqj9qxy-CBndNSE_-AvaRN3Sg" width="100%" alt="Album UI">
      </td>
      <td align="center">
        <img src="https://drive.google.com/uc?export=view&id=1SVhQIZe26wXoMAPJFhuaACnDj7g6TrIH" width="100%" alt="Artist UI">
      </td>
      <td align="center">
        <img src="https://drive.google.com/uc?export=view&id=1gVkKcdF_6N5zJ6sDZV6nLUIOHTIkqWLB" width="100%" alt="Recap UI">
      </td>
    </tr>
  </table>
</div>

### Design System Highlights
* **Material 3:** Utilizes dynamic colors that adapt to your wallpaper for a personalized feel.
* **Clean Typography:** Prioritizes legibility for lyrics and metadata using *Plus Jakarta Sans* and *Space Grotesk*.
* **Fluid Motion:** Transitions between the mini-player, full player, and lyrics sheet are seamless.

---

## ✨ Key Features

### 📊 DearRecap: Your Yearly Wrapped
Why should streaming services have all the fun? DearMusic tracks your local playback to generate shareable stories in a beautiful "Story" format.

* **Music Personas:** The app analyzes your habits to assign a unique persona. Are you **"The Time Traveler"**, revisiting classics? Or perhaps "The Rockstar"?
* **Detailed Insights:** Visualize your top songs, artists, and total listening hours.
* **Social Sharing:** Share your stats directly to Instagram Stories or WhatsApp Status with one tap.

### 🎧 Intelligent Audio Engine
* **Smart Silence Skipping:** Uses **FFmpeg** to automatically detect and skip silence at the start and end of tracks, keeping the energy going.
* **Loudness Normalization:** Implements **ReplayGain** logic so you don't get blasted by sudden volume jumps between old and new songs.
* **Smart Mix:** Quickly access a generated playlist based on your recent listening history directly from the Home screen.

### 🛠️ Power User Tools
* **Nerd Mode:** Flip the album art to reveal technical metadata (Bitrate, Format, Channels).
* **Lyrics Support:** Beautiful, large, synchronized lyrics display for karaoke sessions.
* **Battery Helper:** Built-in guidance to optimize battery settings for uninterrupted background playback on Android.

---

## 🛠️ Architecture & Tech Stack

Designed for performance and reliability, moving away from basic key-value storage to robust solutions.

| Category | Technology | Role |
| :--- | :--- | :--- |
| **Framework** | Flutter | Cross-platform UI toolkit. |
| **Database** | **SQLite (`sqflite`)** | Heavy lifting for library management and usage analytics. |
| **Settings** | GetStorage | Lightweight storage for user preferences. |
| **Audio Core** | `audio_service` + `just_audio` | Robust background audio & notification handling. |
| **Processing** | **`ffmpeg_kit_flutter`** | The brain behind silence detection and smart transitions. |
| **Analytics** | Firebase | Crashlytics & Performance monitoring. |

---

## 🚀 Getting Started (For Contributors)

To keep the project secure, we do not commit sensitive API keys. Follow these steps to build the app locally.

### 1. Prerequisites
* Flutter SDK (Latest Stable)
* Java 17 (Recommended for latest Gradle)

### 2. Clone & Install
```bash
git clone [https://github.com/lightbit/DearMusic.git](https://github.com/lightbit/DearMusic.git)
cd DearMusic
flutter pub get
