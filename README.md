# ECHO-BREACH 
The Signal Cartel 

> *"The cartel hides their secrets in plain sight... inside the sound waves."*

<img width="819" height="428" alt="image" src="https://github.com/user-attachments/assets/dfdccc37-ee96-4923-9f37-184c3f8cbf88" />

**ECHO-BREACH** is a terminal-based, acoustic cyber-warfare simulator built with Object Pascal (Lazarus). Step into the shoes of a freelance operator utilizing the experimental `ECHO-OS`. Your mission: intercept audio frequencies, decrypt hidden carrier waves, and navigate a procedurally generated network to dismantle a dangerous underground syndicate known as *The Signal Cartel*.

## ✨ Core Features

*   **🎧 Acoustic Signal Processing:** Real-time audio DSP and FFT analysis. Scan frequencies to discover hidden network nodes broadcasting on specific Hz ranges.
*   **🌐 Procedural Network Topology:** High replayability. Every new game generates a unique network map, randomizing IPs, Honeypots, connection paths, and handshake hashes.
*   **⚠️ Active Counter-Hacking (ICE):** The cartel fights back. Defend against sudden real-time admin attacks by quickly executing firewall commands (`block_port`) before the timer runs out.
*   **🛒 Black Market Economy:** Extract *Data Fragments* from compromised Virtual File Systems (VFS) and spend them on the Dark Web to upgrade your rig (Quantum CPU, Stealth VPN, Auto-Analyzer).
*   **📺 Immersive CRT Interface:** Custom-rendered UI featuring retro CRT scanlines, phosphor glow, and fake glassmorphism effects powered by BGRABitmap.
*   **📜 Story Campaign:** A fully integrated 5-stage mission guided by your handler `[ZERO]`.

## 🛠️ Tech Stack

*   **Language:** Object Pascal (Free Pascal Compiler)
*   **IDE:** Lazarus (LCL)
*   **Audio Engine:** BASS Audio Library (`bass.dll`)
*   **Graphics:** BGRABitmap (Custom drawing & CRT Post-processing)
*   **Database:** SQLite3 (For managing target Virtual File Systems)
*   **Architecture:** Command Pattern (CLI Parser) & mORMot-style Microservices.

## 🚀 Installation & Build Instructions

### Prerequisites
1. Install [Lazarus IDE](https://www.lazarus-ide.org/).
2. Ensure you have the [BGRABitmap](https://github.com/bgrabitmap/bgrabitmap) package installed in Lazarus via the Online Package Manager (OPM).

### Compiling from Source
1. Clone the repository:
   ```bash
   git clone [https://github.com/Arsiteks/echo-breach.git](https://github.com/Arsiteks/echo-breach.git)
