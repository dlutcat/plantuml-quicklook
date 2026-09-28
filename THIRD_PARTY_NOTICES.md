# Third-party notices

This application is based on the client-side rendering design of
[plantuml/plantuml-for-github](https://github.com/plantuml/plantuml-for-github),
pinned to commit `6449407013230c644576753263266b44fc8d1d8d` (extension version 0.3.3).

- `Resources/Web/vendor/plantuml.js`: the unmodified TeaVM-compiled PlantUML engine from that commit's `Chrome/vendor/plantuml.js`.
- `Resources/Web/*.min.js`: all 16 unmodified stdlib bundles from that commit's `Chrome/` directory. Library metadata, attribution, and embedded license information remain in these bundles.
- The preview's DOM-settle technique is adapted from `Chrome/renderer.js`.
- Upstream's MIT license is reproduced in `Resources/Licenses/plantuml-for-github-MIT.txt`.
- PlantUML itself is an independently licensed dependency; its default distribution is GPL. See https://plantuml.com/license and https://github.com/plantuml/plantuml for engine source and licensing. The wrapper repository's MIT license does not relicense all third-party components.
- The GNU GPL v3 text is retained in `Resources/Licenses/PlantUML-GPL-3.0.txt` and the application source is provided under GPL-3.0-or-later (`LICENSE`).

The build wraps the engine in an IIFE and replaces its single ES-module export with
`globalThis.PlantUMLEngine`. No renderer algorithms are changed. This generated file
exists only in the application bundles. `vendor-lock.json` records original file hashes.

The application contains no updater, remote rendering service, telemetry, or CDN assets.

The Quick Look extension retains App Sandbox and enables the standard network-client
entitlement required for WebKit's XPC processes to start. Page network requests are
blocked with CSP (`connect-src 'none'`) and a WKContentRuleList. All rendering assets
are read from a private `puml-resource://app/` origin backed by the application bundle.
