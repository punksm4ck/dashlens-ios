# Security Policy

## Reporting a vulnerability

Please do not open a public issue for security problems.

Report privately through GitHub: **Security tab -> Report a vulnerability**
(https://github.com/punksm4ck/dashlens-ios/security/advisories/new).

Include the affected version, steps to reproduce, and the impact you observed.
You can expect an acknowledgement within 7 days.

## Scope

DashLens for iPhone stores its data on the device and has no account and no servers.
Reports about data exposure, location or camera permission misuse, or unintended network
access are in scope. See the README for how screenshots are handled: they are read on the
phone with Apple's text recognition and are not uploaded.

## DashLens Live (screen broadcast)

The broadcast extension sees the lower part of the screen while you run it. It reads text with Apple's Vision framework
and sends only the recognised text lines to the DashLens app over loopback UDP (127.0.0.1), never over a network. Because
any app on the same phone can send to a loopback port, the receiver validates every message (size, JSON shape, line count
and length, one per second) and the worst a forged message can do is show a fake offer card. A paid developer account would
allow an App Group instead, which removes this. Screen frames are never saved or uploaded.
