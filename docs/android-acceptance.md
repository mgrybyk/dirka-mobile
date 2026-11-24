# Android device acceptance

The test device was an ARM64 Android 16 tablet using wireless ADB. The
device runs used the local debug-key-signed release build. GitHub release
signing was verified separately with a temporary certificate.

## 24 November 2026

| Check | Result |
| --- | --- |
| Install and update | ADB installed the ARM64 APK. The non-streaming installer completed the update after the streamed install was rejected. |
| Native integration | Five device tests passed. They covered package and engine metadata, app startup, encrypted storage, occupied ports, and service reattachment and cleanup. |
| Saved entries | A saved client survived a process restart and stayed disconnected until started explicitly. |
| Forwarding in another app | Brave loaded a page through a loopback port while Dirka ran in the background. Each of two clients passed a 65,536-byte binary echo and returned the server greeting. |
| Reconnect in background | Both clients resumed forwarding after the LAN relay restarted while Brave was in the foreground. |
| Notification | One notification showed two clients. Tapping it returned to both running clients. Stopping one reduced the count to one. The last disconnect removed the notification and stopped the service. |
| Port ownership | Device integration verified both an external port conflict and a conflict with another active client. The released port could be rebound. |
| Physical Wi-Fi change | Pending. Relay restart was tested on the tablet, and the Rust host test exercised the default-network signal during backoff. |
| Screen off and unlock | Pending. Sustained forwarding with the display off depends on the device. |

Follow the [physical-device procedure](../README.md#physical-device) to
repeat the browser and binary checks. For a network-change check, keep
Dirka backgrounded, change or briefly disconnect the tablet's Wi-Fi,
restore connectivity to the fixture, and repeat the binary test. USB ADB
keeps the host connected to the tablet during a Wi-Fi change.
