# Home — Project Context

## What this app does
Track who is home by scanning the local WiFi network for household devices.
- On setup: scan network, discover devices, let user name them and assign to people
- Dashboard: shows "3 of 5 people home" with per-person home/away status
- Manual scan/rescan button triggers a re-scan
- Notifications: alert when someone arrives/leaves, and late-check alert if someone isn't home after a set time

## Developer
- **Name:** Twinkle
- **Stack:** SwiftUI, SwiftData, Swift, Xcode

## Project
- **Xcode project:** `Home.xcodeproj`
- **Entry point:** `Home/HomeApp.swift`
- **Deployment target:** iOS 26.2

## Architecture
```
Home/
  HomeApp.swift          — ModelContainer setup, app entry
  RootView.swift         — onboarding gate (checks hasCompletedOnboarding)
  MainTabView.swift      — 2-tab shell: Home, Settings (People tab removed)
  Home-Bridging-Header.h — intentionally empty, kept for build settings
  Models/
    Person.swift         — SwiftData model: name, emoji, isHome, devices[]
    Device.swift         — SwiftData model: label, lastKnownIP, hostname, person
  Views/
    DashboardView.swift  — main screen, people list, rescan button
    PersonDetailView.swift
    AddPersonView.swift
    SettingsView.swift   — subnet, household members, re-run setup (wipes all data)
  Onboarding/
    WelcomeView.swift
    ScanningView.swift
    DeviceSetupView.swift
  Scanning/
    NetworkScanner.swift — UDP sweep + ARP cache + Bonjour + TCP fallback
```

## Build stages
- [x] Stage 1 — Models, app skeleton, tab structure, onboarding welcome
- [x] Stage 2 — NetworkScanner engine (TCP knock, subnet detection, TaskGroup concurrency)
- [x] Stage 3 — Onboarding scan flow (discover + name devices)
- [x] Stage 4 — Dashboard wired to real scan results, ARP-based device detection
- [ ] Stage 5 — Notifications (arrive/leave + late check)
- [ ] Stage 6 — Background refresh

## Key technical decisions
- **Primary scan method:** UDP sweep → ARP cache via sysctl (finds ALL devices regardless of OS/firewall)
- **ARP filtering:** Only count entries where `sdl_alen > 0` (incomplete entries = no real device)
- **rt_msghdr size:** hardcoded as 92 bytes (verified from XNU source, avoids needing bridging header)
- **Bonjour/mDNS:** runs in parallel to enrich results with device names
- **TCP fallback:** used only if ARP returns nothing
- **Device identity:** IP + hostname combo (no MAC address access on iOS)
- **Persistence:** SwiftData
- **Permissions:** NSLocalNetworkUsageDescription in build settings
- **Subnet:** @AppStorage("subnetBase"), auto-detected from en0 on first launch

## Rules — MUST follow every time
- **Search the web for the latest official documentation before implementing anything.**
  Look up the current Apple Developer Docs, Swift Evolution proposals, or relevant RFCs
  for any API, framework, or system call being used. Do not rely on training data alone —
  iOS/Swift APIs change between versions.
- **Only write and deploy code you are 100% confident will compile and work correctly.**
  If there is any doubt about an API, a struct layout, a platform restriction, or behaviour
  on the specific deployment target (iOS 26.2), verify it first. Do not guess.
- Use SwiftUI only, no UIKit unless absolutely forced
- Keep code concise, no unnecessary comments or abstractions
- Re-run Setup must wipe all Person and Device records before restarting onboarding
