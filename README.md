<div align="center">

  <img src="https://drive.google.com/uc?export=view&id=1mIuXjoW39p52KfcrZ3nyEG2JaWO8eULq" alt="DearMusic Logo" width="120" height="120">

# DearMusic 🎧

**Your Music, Your Rules, Your Story.**

Most local players treat your files like data. **DearMusic** treats them like memories.
Built with **Flutter** & **Material 3**, it’s a high-fidelity experience with a sophisticated **UsageTracker engine** that learns your rituals, predicts your cravings, and builds your musical identity—all 100% offline.

[![Flutter](https://img.shields.io/badge/Made%20with-Flutter-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Material 3](https://img.shields.io/badge/Design-Material%203-7c4dff?style=for-the-badge&logo=material-design)](https://m3.material.io)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)

[Try the APK](#-try-the-app) • [View Features](#-key-features) • [The Roadmap](#-road-to-play-store)

</div>

---

<h2 align="center">🎨 Designed for Immersion</h2>

<p align="center">
  DearMusic isn't just about utility; it's about the feel. From the <b>adaptive dynamic colors</b> that breathe with your wallpaper to the <b>expressive wave progress bar</b> that dances with your mood.
</p>

<div align="center">
  <table border="0">
    <tr>
      <td width="33%" align="center"><b>Personalized Home</b></td>
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
      <td width="33%" align="center"><b>Deep Dive Albums</b></td>
      <td width="33%" align="center"><b>Artist Universe</b></td>
      <td width="33%" align="center"><b>DearRecap Stories</b></td>
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

### ✨ The Personal Touch
* **Adaptive Aesthetics:** Using `dynamic_color`, the UI reflects you literally by pulling tones from your wallpaper.
* **Meaningful Typography:** A mix of *Plus Jakarta Sans* for warmth and *Space Grotesk* for technical precision.
* **Fluid Experience:** Every transition is calculated to keep you in the flow, from the mini-player to the full-screen lyrics.

---

## ✨ Key Features

### 🧠 Algorithmic Soul (Usage Tracking)
Unlike basic players, DearMusic uses a complex **scoring engine** to understand your library:
* **Ritual Detection:** It knows if you're a "Night Owl" or a "Morning Bird" by tracking your hourly listening patterns.
* **Fatigue Prevention:** Uses exponential decay and artist cooldowns so your favorites stay fresh and don't get overplayed.
* **Loyalty vs. Skip Scoring:** Your skips actually matter. The engine penalizes "Quick Skips" and boosts songs you listen to until the very last second.

### 📊 DearRecap: Discover Your Musical Persona
Uncover who you really are as a listener. DearMusic analyzes local data to assign you a unique **Musical Persona**.
* **Personas:** Are you **"The Enigma"**, **"The Wordsmith"**, or **"The Explorer"**?
* **Explorer Spirit:** Tracks how many new songs you've discovered and integrated into your daily rotation.
* **Social Sharing:** Generate beautiful, personalized story cards for Instagram or WhatsApp.

### 🎧 Pro Audio Engine
* **Smart Silence Skipping:** Powered by **FFmpeg** to detect and jump over silent gaps at the start/end of tracks.
* **Loudness Normalization:** Uses **EBU R128 (ReplayGain)** to normalize volume so every song hits just right.
* **Smart Mix:** Not a random shuffle a calculated recommendation based on your current vibe and historical scoring.

---

## 📲 Try The App

Get the production-ready APK directly. No data tracking, no accounts, just pure music.

### **[Download Latest APK](https://github.com/lightbit/DearMusic/releases/latest)**

> [!TIP]
> **Pro Tip:** When you first install, allow **Audio Access** and give the app a few minutes to index your library and start learning your vibe!

---

## 🚀 Road to Play Store

We’re on a mission to bring the best local player to the **Google Play Store**. This is a community effort, and we need your help to polish the final edges!

* **How you can help:**
    - **Theming:** Help us refine the Material 3 motion.
    - **Localization:** Bring DearMusic to your language.
    - **Testing:** Help us hunt bugs on various Android devices.
    - **Cloud Sync:** Help us implement a privacy-first sync for listening stats.

---

## 🛠️ Tech Stack

| Category | Technology |
| :--- | :--- |
| **Framework** | Flutter (Dart) |
| **Database** | **SQLite (`sqflite`)** for deep usage tracking |
| **Audio** | `audio_service`, `just_audio`, & `ffmpeg_kit_flutter` |
| **Theming** | `dynamic_color` & `Google Fonts` |

---

## 🤝 Contributing

We love PRs! Fork the repo, create a branch, and let's build the future of local music together.

<div align="center">
  <p><b>Join the movement. Let's make local music premium again.</b></p>
  <sub>Designed & Developed with ❤️ by <a href="https://github.com/lightbit">lighbit</a></sub>
</div>
