# Contributing

Thanks for your interest in DashLens for iPhone.

## Getting started

1. Fork the repository and create a branch from `main`.
2. You need a Mac with Xcode. Install XcodeGen (`brew install xcodegen`), run
   `xcodegen generate` in the project folder, then open `DashLens.xcodeproj`.
   The project file is generated and is not committed.
3. Keep changes focused. One fix or feature per pull request.
4. Describe what changed and why in the pull request.

## Reporting a build failure or a misread offer

- **Build failure:** open the failed run in the Actions tab, download the `build-log`
  artifact, and attach it to a new issue.
- **Offer misread:** in the app go to Settings > Diagnostics, copy the screenshot text,
  remove any addresses or other personal details, and attach it to a new issue.

## Guidelines

- Follow the existing Swift style. The grading model in `DashLens/Core/Analyzer.swift` mirrors
  the Android app; keep the two in step.
- Do not commit signing certificates, provisioning profiles, tokens, or personal data.
- Report security issues privately, as described in [SECURITY.md](SECURITY.md).

By contributing you agree that your work is released under the [MIT License](LICENSE).
