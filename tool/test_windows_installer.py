import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def extract_function(script, name):
    match = re.search(r"(?m)^function " + re.escape(name) + r"\b", script)
    if not match:
        return ''
    end = re.search(r"(?m)^(?:function|procedure) ", script[match.end():])
    return script[match.start(): match.end() + end.start() if end else len(script)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', default=os.environ.get('INNO_SETUP_COMPILER'))
    parser.add_argument('--output-dir')
    args = parser.parse_args()
    if os.name != 'nt':
        raise RuntimeError('The compiled Inno harness requires Windows')
    compiler = args.compiler or str(Path(os.environ.get('ProgramFiles(x86)', '')) / 'Inno Setup 6' / 'ISCC.exe')
    root = Path(__file__).resolve().parent.parent
    output = Path(args.output_dir or tempfile.mkdtemp(prefix='flashco-inno-test-')).resolve()
    output.mkdir(parents=True, exist_ok=True)
    marker = output / '.flashco-installer-test'
    if any(output.iterdir()) and not marker.is_file():
        raise RuntimeError('Output directory must be empty or belong to this harness')
    marker.touch()
    source = (root / 'windows/packaging/exe/inno_setup.iss').read_text(encoding='utf-8')
    functions = ''.join(extract_function(source, name) for name in [
        'NormalizeFullPath', 'TryExtractExecutablePath', 'QueryInstalledHelper', 'IsInstalledHelperProcessPath',
        'WaitForInstalledHelper', 'WaitForInstalledHelperProcesses', 'AcquireHelperReference',
        'RemoveHeldHelper', 'StopInstalledHelper',
    ])
    functions = re.sub(r'\bDLLGetLastError\b', 'FixtureLastError', functions)
    fixture = (root / 'test/fixtures/windows_installer_cleanup.iss').read_text(encoding='utf-8')
    script = output / 'cleanup-harness.iss'
    script.write_text(fixture.replace('@@PRODUCTION@@', functions), encoding='utf-8-sig')
    compiled = subprocess.run([compiler, '/Q', str(script)], capture_output=True, text=True)
    if compiled.returncode:
        raise RuntimeError('Inno harness compilation failed: ' + compiled.stdout + compiled.stderr)
    scenarios = ['start-pending', 'missing-binary', 'absent', 'running', 'already-stopped', 'pending-delete',
        'foreign', 'replaced', 'query-failure', 'stop-failure', 'delete-failure',
        'stuck-stop', 'stuck-delete', 'command-failure', 'stuck-process', 'reference-failure',
        'manager-failure', 'open-pending-delete', 'absent-replaced', 'held-registration-missing']
    for scenario in scenarios:
        result = output / (scenario + '.txt')
        result.unlink(missing_ok=True)
        process = subprocess.run([str(output / 'cleanup-harness.exe'), '/VERYSILENT',
            '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/scenario=' + scenario,
            '/result=' + str(result)], capture_output=True, timeout=30)
        outcome = result.read_text(encoding='utf-8-sig') if result.exists() else 'NO RESULT'
        if outcome != 'PASS':
            raise RuntimeError(scenario + ': ' + outcome + ' (exit ' + str(process.returncode) + ')')
        print(json.dumps({'scenario': scenario, 'result': outcome}), flush=True)

    names = ['NormalizeFullPath', 'NormalizeInstallDirectory', 'SplitVersionParts',
        'IsVersionNumber', 'CompareVersionNumber', 'ReadInstallerVersion',
        'CompareInstallerVersions', 'ReadInstalledRegistration', 'MergeInstalledRegistration',
        'FindInstalledFlashco', 'CheckInstalledVersion', 'PrepareToInstall']
    functions = ''.join(extract_function(source, name) for name in names)
    functions = functions.replace("'{{APP_VERSION}}'", 'IncomingVersion')
    functions = functions.replace('{{EXECUTABLE_NAME}}', 'Flashco.exe')
    functions = re.sub(r'\bIsAdminInstallMode\b', 'FixtureAllUsers', functions)
    functions = re.sub(r'\bIs64BitInstallMode\b', 'Fixture64BitMode', functions)
    functions = re.sub(r'\bWizardSilent\b', 'FixtureSilent', functions)
    functions = re.sub(r'\bPrepareToInstall\b', 'TestPrepareToInstall', functions)
    functions = re.sub(r'\bRegKeyExists\b', 'FixtureRegKeyExists', functions)
    functions = re.sub(r'\bRegQueryStringValue\b', 'FixtureRegQueryStringValue', functions)
    fixture = (root / 'test/fixtures/windows_installer_versions.iss').read_text(encoding='utf-8')
    key = re.search(r"(?m)^  FlashcoUninstallKey = .+;$", source).group(0)
    key = key.replace('{{APP_ID}}', '2E1E050C-79CA-52FB-82C4-52FDC3F5D780')
    fixture = fixture.replace('@@CONSTANTS@@', 'const\n' + key)
    script = output / 'versions-harness.iss'
    script.write_text(fixture.replace('@@PRODUCTION@@', functions), encoding='utf-8-sig')
    compiled = subprocess.run([compiler, '/Q', str(script)], capture_output=True, text=True)
    if compiled.returncode:
        raise RuntimeError('Version harness compilation failed: ' + compiled.stdout + compiled.stderr)
    cases = [
        ('path-case-insensitive', {'registry': 'location-case'}),
        ('install-location-fallback', {'registry': 'location-only'}),
        ('install-location-conflict', {'registry': 'location-conflict', 'accept': '0'}),
        ('downgrade-rejected', {'installed': '0.10.0+1', 'accept': '0', 'prompts': '1'}),
        ('downgrade-accepted', {'installed': '0.10.0+1', 'confirm': '1', 'prompts': '1'}),
        ('silent-downgrade-rejected', {'installed': '0.10.0+1', 'policy-silent': '1', 'accept': '0'}),
        ('silent-downgrade-opt-in', {'installed': '0.10.0+1', 'policy-silent': '1', 'ALLOWDOWNGRADE': '1'}),
        ('silent-zero-is-not-consent', {'installed': '0.10.0+1', 'policy-silent': '1', 'ALLOWDOWNGRADE': '0', 'accept': '0'}),
        ('silent-bare-flag-is-not-consent', {'installed': '0.10.0+1', 'policy-silent': '1', 'ALLOWDOWNGRADE': None, 'accept': '0'}),
        ('silent-noncanonical-flag-is-not-consent', {'installed': '0.10.0+1', 'policy-silent': '1', 'ALLOWDOWNGRADE': '01', 'accept': '0'}),
        ('new-install', {'registry': 'absent'}),
        ('unregistered-files', {'registry': 'absent', 'orphan': '1', 'accept': '0'}),
        ('upgrade', {}),
        ('same-version-reinstall', {'installed': '0.9.0+2026101401'}),
        ('numeric-minor-version', {'installed': '0.9.9+1', 'incoming': '0.10.0+1'}),
        ('build-upgrade', {'installed': '0.9.0+999999999999999999', 'incoming': '0.9.0+1000000000000000000'}),
        ('build-downgrade', {'installed': '0.9.0+2026101402', 'accept': '0', 'prompts': '1'}),
        ('prerelease-upgrade', {'installed': '0.9.0-pre.9+1'}),
        ('prerelease-downgrade', {'installed': '0.9.0+1', 'incoming': '0.9.0-pre.10+1', 'accept': '0', 'prompts': '1'}),
        ('numeric-prerelease', {'installed': '0.9.0-pre.9+1', 'incoming': '0.9.0-pre.10+1'}),
        ('machine32-registration', {'registry': 'machine32', 'accept': '0'}),
        ('machine32-matching-mode', {'registry': 'machine32', 'mode64': '0'}),
        ('per-user-registration', {'registry': 'user', 'all-users': '0'}),
        ('scope-conflict', {'registry': 'user', 'accept': '0'}),
        ('same-path-mode-conflict', {'registry': 'duplicate', 'accept': '0'}),
        ('different-path-conflict', {'registry': 'conflict', 'accept': '0'}),
        ('registry-read-failure', {'registry': 'query-failure', 'accept': '0'}),
        ('missing-version', {'installed': '', 'accept': '0'}),
        ('invalid-version', {'installed': 'broken', 'accept': '0'}),
        ('invalid-incoming-version', {'incoming': 'broken', 'accept': '0'}),
        ('target-path-conflict', {'installed-path': 'D:\\OtherInstallation\\Flashco', 'accept': '0'}),
        ('relative-path', {'installed-path': 'relative\\Flashco', 'accept': '0'}),
        ('drive-root-path', {'installed-path': 'C:\\', 'accept': '0'}),
        ('registration-rechecked', {'recheck': '1'}),
    ]
    app = output / 'app'
    app.mkdir(exist_ok=True)
    sentinels = {'settings.json': b'{"theme":"dark","tun":false}',
        'profiles.yaml': b'user-selected-profile\n'}
    for name, content in sentinels.items():
        (app / name).write_bytes(content)
    for scenario, values in cases:
        result = output / (scenario + '.txt')
        result.unlink(missing_ok=True)
        orphan = app / 'Flashco.exe'
        if values.get('orphan') == '1':
            orphan.write_bytes(b'not an executable')
        command = [str(output / 'versions-harness.exe'), '/VERYSILENT',
            '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/DIR=' + str(app), '/result=' + str(result)]
        command.extend('/' + key + ('=' + value if value is not None else '')
            for key, value in values.items())
        try:
            process = subprocess.run(command, capture_output=True, timeout=30)
        finally:
            orphan.unlink(missing_ok=True)
        outcome = result.read_text(encoding='utf-8-sig') if result.exists() else 'NO RESULT'
        if outcome != 'PASS':
            raise RuntimeError(scenario + ': ' + outcome + ' (exit ' + str(process.returncode) + ')')
        for name, content in sentinels.items():
            if (app / name).read_bytes() != content:
                raise RuntimeError(scenario + ': user data changed: ' + name)
        print(json.dumps({'scenario': scenario, 'result': outcome}), flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
