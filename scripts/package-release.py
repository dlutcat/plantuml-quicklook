#!/usr/bin/env python3
"""Package an already-built Apple Silicon app as a DMG and ZIP for GitHub Releases."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'dist' / 'PlantUML Preview.app'
EXT = APP / 'Contents/PlugIns/PlantUMLPreview.appex'


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    # Release metadata must refer to the exact, committed sources used to build.
    run('git', '-C', ROOT, 'diff', '--exit-code', 'HEAD', '--')
    with (APP / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    version = info['CFBundleShortVersionString']
    commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    for bundle, executable in ((APP, 'PlantUMLPreview'), (EXT, 'PlantUMLPreviewExtension')):
        architectures = subprocess.check_output(
            ['xcrun', 'lipo', str(bundle / 'Contents/MacOS' / executable), '-archs'], text=True).split()
        if architectures != ['arm64']:
            raise SystemExit('Release binaries must contain only arm64: ' + executable)
    run('codesign', '--verify', '--deep', '--strict', APP)
    output = ROOT / 'dist/releases' / ('v' + version)
    output.mkdir(parents=True, exist_ok=True)
    stem = 'PlantUML-Preview-' + version + '-macOS-arm64'
    dmg, archive = output / (stem + '.dmg'), output / (stem + '.zip')
    with tempfile.TemporaryDirectory(prefix='release-', dir=ROOT / '.build') as temporary:
        stage = Path(temporary)
        package = stage / ('PlantUML Preview ' + version)
        package.mkdir()
        run('ditto', '--norsrc', '--noextattr', '--noqtn', APP, package / APP.name)
        shutil.copy2(ROOT / 'docs/INSTALL.txt', package / 'Read Me.txt')
        shutil.copy2(ROOT / 'LICENSE', package / 'LICENSE.txt')
        shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', package / 'THIRD_PARTY_NOTICES.md')
        examples = package / 'Examples'
        examples.mkdir()
        for fixture in sorted((ROOT / 'Examples').glob('*.puml')):
            shutil.copyfile(fixture, examples / fixture.name)
        (package / 'SOURCE.txt').write_text(
            'PlantUML Preview ' + version + '\n'
            'Source commit: ' + commit + '\n'
            'Project: https://github.com/dlutcat/plantuml-quicklook\n'
            'Exact sources: https://github.com/dlutcat/plantuml-quicklook/tree/' + commit + '\n'
            'License: GPL-3.0-or-later; see third-party notices for bundled components.\n', encoding='utf-8')
        run('codesign', '--verify', '--deep', '--strict', package / APP.name)
        if archive.exists():
            archive.unlink()
        run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--noqtn', '--keepParent', package, archive)
        # Drag-to-Applications shortcut belongs to the disk image, not the ZIP.
        os.symlink('/Applications', package / 'Applications')
        run('hdiutil', 'create', '-ov', '-format', 'UDZO', '-fs', 'HFS+',
            '-volname', 'PlantUML Preview', '-srcfolder', package, dmg)
    run('hdiutil', 'verify', dmg)
    checksums = ''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n'
                        for path in (dmg, archive))
    (output / 'SHA256SUMS.txt').write_text(checksums, encoding='utf-8')
    print('Release assets:', output)


if __name__ == '__main__':
    main()
