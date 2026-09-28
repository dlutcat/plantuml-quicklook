#!/usr/bin/env python3
"""Build a native app + Quick Look appex using macOS Command Line Tools only."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'
APP = ROOT / 'dist' / 'PlantUML Preview.app'
EXT = APP / 'Contents/PlugIns/PlantUMLPreview.appex'
BUNDLE_ID = 'io.github.dlutcat.PlantUMLPreview'

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)

def plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value, sort_keys=False))

def metadata(name, identifier, executable, package):
    return dict(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=identifier,
                CFBundleExecutable=executable, CFBundlePackageType=package,
                CFBundleInfoDictionaryVersion='6.0', CFBundleShortVersionString='1.0.0', CFBundleVersion='1',
                CFBundleSupportedPlatforms=['MacOSX'], LSMinimumSystemVersion='13.0',
                NSHumanReadableCopyright='PlantUML Preview contributors; see bundled third-party notices.')

def main():
    # Verify pinned third-party resources before producing an executable.
    lock = json.loads((ROOT / 'vendor-lock.json').read_text())
    for name, digest in lock['files'].items():
        actual = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        if actual != digest:
            raise SystemExit('Vendor checksum mismatch: ' + name)
    BUILD.mkdir(exist_ok=True)
    if APP.exists():
        shutil.rmtree(APP)  # Only our generated build product, never an installed app.
    for bundle in (APP, EXT):
        (bundle / 'Contents/MacOS').mkdir(parents=True)
        resources = bundle / 'Contents/Resources'
        shutil.copytree(ROOT / 'Resources', resources)
        shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', resources)
        shutil.copy2(ROOT / 'LICENSE', resources)
        # TeaVM's export is mechanically wrapped as a classic script. This avoids
        # module-origin quirks in WKURLSchemeHandler without changing the engine.
        original = (resources / 'Web/vendor/plantuml.js').read_text()
        export = 'export{C as render,D as renderToString};'
        if original.count(export) != 1:
            raise SystemExit('Unexpected upstream export; review engine adapter.')
        adapted = '(function(){\n' + original.replace(export, 'globalThis.PlantUMLEngine={render:C,renderToString:D};') + '\n})();\n'
        (resources / 'Web/vendor/plantuml.classic.js').write_text(adapted)
        (resources / 'Web/vendor/plantuml.js').unlink()

    uti = 'org.plantuml.source'
    app_info = metadata('PlantUML Preview', BUNDLE_ID, 'PlantUMLPreview', 'APPL')
    app_info.update(NSPrincipalClass='NSApplication', NSHighResolutionCapable=True,
                    LSApplicationCategoryType='public.app-category.developer-tools',
                    CFBundleDocumentTypes=[dict(CFBundleTypeName='PlantUML Source', CFBundleTypeRole='Viewer',
                        LSHandlerRank='Alternate', LSItemContentTypes=[uti])],
                    UTImportedTypeDeclarations=[dict(UTTypeIdentifier=uti, UTTypeDescription='PlantUML Source',
                        UTTypeConformsTo=['public.plain-text'], UTTypeTagSpecification={
                            'public.filename-extension': ['puml', 'plantuml', 'pu', 'wsd', 'iuml']})])
    plist(APP / 'Contents/Info.plist', app_info)
    ext_info = metadata('PlantUML Preview', BUNDLE_ID + '.Preview', 'PlantUMLPreviewExtension', 'XPC!')
    ext_info['NSExtension'] = dict(NSExtensionPointIdentifier='com.apple.quicklook.preview',
        NSExtensionPrincipalClass='PreviewViewController', NSExtensionAttributes=dict(
            QLSupportedContentTypes=[uti], QLSupportsSearchableItems=False, QLIsDataBasedPreview=False))
    plist(EXT / 'Contents/Info.plist', ext_info)
    entitlements = BUILD / 'extension.entitlements'
    # WebKit's XPC services require the network-client entitlement even for a
    # private in-memory origin. CSP + a WebKit rule list block HTTP(S) requests.
    plist(entitlements, {'com.apple.security.app-sandbox': True, 'com.apple.security.network.client': True,
                         'com.apple.security.files.user-selected.read-write': True})
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    arch = os.environ.get('ARCH', 'arm64')
    if arch != 'arm64':
        raise SystemExit('Unsupported architecture: ' + arch)
    common = ['xcrun', 'swiftc', '-swift-version', '5', '-O', '-sdk', sdk,
              '-target', arch + '-apple-macosx13.0', '-module-cache-path', BUILD / 'ModuleCache',
              '-file-prefix-map', str(ROOT) + '=.',
              '-framework', 'AppKit', '-framework', 'WebKit']
    run(*common, '-module-name', 'PlantUMLPreviewApp', ROOT / 'Sources/RendererViewController.swift',
        ROOT / 'Sources/App.swift', '-o', APP / 'Contents/MacOS/PlantUMLPreview')
    run(*common, '-module-name', 'PlantUMLPreviewExtension', '-application-extension', '-parse-as-library',
        '-framework', 'QuickLookUI', ROOT / 'Sources/RendererViewController.swift',
        ROOT / 'Sources/PreviewViewController.swift', '-Xlinker', '-e', '-Xlinker', '_NSExtensionMain',
        '-o', EXT / 'Contents/MacOS/PlantUMLPreviewExtension')
    identity = os.environ.get('SIGN_IDENTITY', '-')
    run('codesign', '--force', '--sign', identity, '--entitlements', entitlements, EXT)
    run('codesign', '--force', '--sign', identity, APP)
    run('codesign', '--verify', '--deep', '--strict', APP)
    print('Built:', APP)

if __name__ == '__main__':
    main()
