# Scope

Scope is a modern native code editor for macOS.

> Extremely fast native Mac code editor. No Electron. No IDE. No accounts. No clutter.

Scope is inspired by the philosophy that made TextMate exceptional: fast, focused, powerful text editing without turning the editor into a full IDE.

The goal is simple:

> Build an exceptionally good code editor. Nothing more.

## Status

Scope is in early development. The name **Scope** is currently a working/technical project name and may change before a public release.

## Principles

- Native macOS application built with Swift, SwiftUI/AppKit, and modern Apple text infrastructure.
- Performance is a product feature: typing, opening files, and navigating code should feel immediate.
- Editor-first and local-first.
- Projects are folders; no proprietary workspace format is required.
- Code navigation is a core capability, including TextMate-style Go to Definition and navigation history.
- Tree-sitter is the preferred foundation for syntax parsing and highlighting.
- Universal Ctags is the preferred initial foundation for project-wide symbol indexing and navigation.
- Native macOS Settings instead of user-facing JSON/YAML/TOML configuration.
- Limited language support by design, with a small initial set implemented well.
- No built-in terminal, debugger, extension marketplace, accounts, cloud dependency, or IDE ambitions.
- AI integrations may be explored later, but they must remain optional and non-structural.

## Initial Product Scope

The first useful version should prove the core editing loop:

```text
Open project
    ↓
Find file
    ↓
Read/edit code
    ↓
Navigate to definition
    ↓
Navigate further
    ↓
Go back
    ↓
Edit
    ↓
Save
```

## Technology Direction

- Swift
- SwiftUI and AppKit where appropriate
- TextKit 2
- Tree-sitter
- Universal Ctags
- Native macOS APIs and conventions

Dependencies are expected to be small, focused, actively maintained, and justified by a clear architectural benefit.

## Non-Goals

Scope is not intended to become a replacement for Xcode, Visual Studio Code, or JetBrains IDEs feature-for-feature.

The initial product intentionally excludes LSP, debugger UI, integrated terminal, heavy Git tooling, build-system UI, database tooling, cloud synchronization, collaboration, accounts, AI chat, and broad language support.

## License

Source code is intended to be licensed under the Mozilla Public License 2.0 (MPL-2.0).

The project name, application icon, logo, and other official branding are not granted for use by the source-code license. See `TRADEMARKS.md` for the project's branding policy.

## Guiding Question

> Does this make editing and navigating code faster or better without making the editor heavier?
=======
Scope is a native macOS code editor. This repository currently contains only its minimal SwiftUI application foundation.

## Development configuration

- Deployment target: macOS 13.0
- Temporary bundle identifier: `com.example.Scope`

The bundle identifier is intentionally a replaceable development value until a final reverse-DNS identifier is chosen.
