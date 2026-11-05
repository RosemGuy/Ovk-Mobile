"""Exercise the packaging script with fake Apple tools; does not compile/sign iOS code."""
from pathlib import Path
import tempfile,shutil,subprocess,os,zipfile
root=Path(__file__).resolve().parents[1]
mock=r'''#!/usr/bin/env python3
import sys,os,shutil
from pathlib import Path
name=Path(sys.argv[0]).name;args=sys.argv[1:]
if name=='xcode-select':print(os.environ['DEVELOPER_DIR'])
elif name=='xcrun':
 if '--show-sdk-path' in args:print('/fake/iPhoneOS7.1.sdk')
 elif '--find' in args:print(str(Path(sys.argv[0]).parent/'codesign_allocate'))
 elif args[:2]==['lipo','-archs']:print('armv7 armv7s')
 else:sys.exit(1)
elif name=='xcodebuild':
 if os.environ.get('FAKE_BUILD_FAIL'):print('error: test compile failure');sys.exit(65)
 directory=next(x.split('=',1)[1] for x in args if x.startswith('CONFIGURATION_BUILD_DIR='))
 app=Path(directory)/'OpenVKClassic.app';app.mkdir(parents=True,exist_ok=True)
 (app/'OpenVKClassic').write_text('fake ARM app');(app/'Info.plist').write_text('fake plist')
 print('** BUILD SUCCEEDED **')
elif name=='ditto':shutil.copytree(args[0],args[1])
elif name=='codesign':
 assert Path(os.environ['CODESIGN_ALLOCATE']).exists()
 if os.environ.get('FAKE_SIGN_FAIL'):sys.exit(1)
'''
with tempfile.TemporaryDirectory(prefix='ovk-build-test-') as tmp:
    base=Path(tmp);bin=base/'bin';bin.mkdir();developer=base/'Xcode.app/Contents/Developer';(developer/'Platforms/iPhoneOS.platform').mkdir(parents=True)
    for name in ['xcode-select','xcrun','xcodebuild','ditto','codesign','codesign_allocate']:
        p=bin/name;p.write_text(mock);p.chmod(0o755)
    for case in ['success','compile-failure','sign-failure']:
        project=base/case;project.mkdir();shutil.copyfile(root/'BuildIPA.command',project/'BuildIPA.command')
        env=os.environ.copy();env['PATH']=str(bin)+os.pathsep+env['PATH'];env['DEVELOPER_DIR']=str(developer)
        if case=='compile-failure':env['FAKE_BUILD_FAIL']='1'
        if case=='sign-failure':env['FAKE_SIGN_FAIL']='1'
        result=subprocess.run(['bash',str(project/'BuildIPA.command')],env=env,capture_output=True,text=True)
        ipa=project/'dist/Ovk-Mobile-alpha.ipa'
        if case=='success':
            assert result.returncode==0,result.stdout+result.stderr
            with zipfile.ZipFile(ipa) as z:assert z.read('Payload/OpenVKClassic.app/OpenVKClassic')==b'fake ARM app'
        else:
            assert result.returncode!=0 and not ipa.exists(),result.stdout+result.stderr
            report=(project/'Build-result.txt').read_text()
            assert ('device build' if case=='compile-failure' else 'ad-hoc signature') in report
        print('PASS:',case)
print('Fake-tool tests passed. Actual Xcode build and device signing remain untested.')
