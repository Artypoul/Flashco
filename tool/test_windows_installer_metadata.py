"""Compile the production Inno version directives without installing anything."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parent.parent
    source = (root / 'windows/packaging/exe/inno_setup.iss').read_text(encoding='utf-8')
    preamble, setup = source.split('[Setup]', 1)
    setup = setup.split('[Code]', 1)[0]
    directives = [line for line in setup.splitlines()
                  if line.startswith(('AppVersion=', 'VersionInfoVersion=',
                                      'VersionInfoProductVersion=', 'VersionInfoTextVersion=',
                                      'VersionInfoProductTextVersion='))]
    if len(directives) != 5:
        raise RuntimeError('Expected the five production version directives')
    match = re.search(r'(?m)^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$',
                      (root / 'pubspec.yaml').read_text(encoding='utf-8'))
    if not match:
        raise RuntimeError('Expected a numeric semantic version and build')
    compiler = Path(os.environ.get('ProgramFiles(x86)', '')) / 'Inno Setup 6' / 'ISCC.exe'
    if not compiler.is_file():
        found = shutil.which('iscc')
        if not found:
            raise RuntimeError('Inno Setup compiler not found')
        compiler = Path(found)
    with tempfile.TemporaryDirectory(prefix='flashco-inno-version-') as folder:
        output = Path(folder)
        verifier = ['pwsh', '-NoProfile', '-File', str(root / 'tool/verify_windows_installer_version.ps1')]
        fixture_setup = ('[Setup]\nAppName=Flashco version fixture\n'
                         'DefaultDirName={#SourcePath}\\app\nCreateAppDir=no\n'
                         'Uninstallable=no\nCreateUninstallRegKey=no\nPrivilegesRequired=lowest\n'
                         'OutputDir=.\n')
        baseline = output / 'unversioned.iss'
        baseline.write_text(
            fixture_setup + 'AppVersion=' + match.group(1) +
            '\nOutputBaseFilename=unversioned\n', encoding='utf-8-sig')
        subprocess.run([str(compiler), '/Q', str(baseline)], check=True, cwd=root)
        rejected = subprocess.run(verifier + ['-InstallerPath', str(output / 'unversioned.exe'),
                                  '-OutputPath', str(output / 'unversioned.json')], cwd=root, capture_output=True, text=True)
        if rejected.returncode == 0 or 'Unexpected numeric installer version' not in (rejected.stdout + rejected.stderr):
            raise RuntimeError('Verifier did not reject an unversioned installer: ' + rejected.stdout + rejected.stderr)
        print('Unversioned installer rejected', flush=True)
        script = output / 'version.iss'
        text = preamble + fixture_setup + 'OutputBaseFilename=version-fixture\n' + '\n'.join(directives) + '\n'
        rendered = text.replace('{{APP_VERSION}}', match.group(1))
        wrong_text = output / 'wrong-text.iss'
        wrong_text.write_text(
            rendered.replace('OutputBaseFilename=version-fixture', 'OutputBaseFilename=wrong-text')
                    .replace('VersionInfoTextVersion=' + match.group(1), 'VersionInfoTextVersion=incorrect'),
            encoding='utf-8-sig')
        subprocess.run([str(compiler), '/Q', str(wrong_text)], check=True, cwd=root)
        rejected = subprocess.run(verifier + ['-InstallerPath', str(output / 'wrong-text.exe'),
                                  '-OutputPath', str(output / 'wrong-text.json')], cwd=root, capture_output=True, text=True)
        if rejected.returncode == 0 or 'Unexpected installer version strings' not in (rejected.stdout + rejected.stderr):
            raise RuntimeError('Verifier did not reject a wrong version string: ' + rejected.stdout + rejected.stderr)
        print('Wrong installer version string rejected', flush=True)
        script.write_text(rendered, encoding='utf-8-sig')
        subprocess.run([str(compiler), '/Q', str(script)], check=True, cwd=root)
        subprocess.run(verifier + ['-InstallerPath', str(output / 'version-fixture.exe'),
                        '-OutputPath', str(output / 'version.json')], check=True, cwd=root)


if __name__ == '__main__':
    main()
