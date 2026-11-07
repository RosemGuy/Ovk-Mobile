"""Exercise the actual IPA script's SDK selection and lipo checks without Xcode."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
script = (root / 'BuildIPA.command').read_text()
selection = script[script.index('sdk_version='):script.index("stage='device build'")]
verification = script[script.index('architectures="${architecture_info'):script.index("stage='ad-hoc signature'")]
with tempfile.TemporaryDirectory(prefix='ovk-arch-test-') as directory:
    xcrun = Path(directory) / 'xcrun'
    xcrun.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_SDK"\n')
    xcrun.chmod(0o755)
    import os
    for sdk, actual, success in [
        ('7.1', 'armv7 armv7s arm64', True),
        ('7.1', 'armv7 armv7s', False),
        ('7.1', 'arm64', False),
        ('7.1', 'armv7 armv7s arm64 x86_64', False),
        ('6.1', 'armv7 armv7s', True),
        ('invalid', 'armv7 armv7s', False),
    ]:
        env = dict(os.environ, PATH=directory+os.pathsep+os.environ['PATH'], TEST_SDK=sdk,
                   architecture_info='Architectures in the fat file: app are: '+actual)
        result = subprocess.run(['bash', '-eu', '-c', selection+'\n'+verification], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert (result.returncode == 0) == success, (sdk, actual, result.stdout)
print('PASS: SDK selection, universal device slices, missing arm64 and simulator rejection')
