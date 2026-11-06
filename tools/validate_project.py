#!/usr/bin/env python3
"""Checks project references and bundled demo data without requiring an Apple SDK."""
from pathlib import Path
import json, plistlib, re, hashlib, xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
source = (root/'OpenVKClassic.xcodeproj/project.pbxproj').read_text()
# Parse the OpenStep property list, including nested dictionaries and arrays.
source = re.sub(r'//[^\n]*|/\*.*?\*/', '', source, flags=re.S)
tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', source)
position = 0
def consume(expected=None):
    global position
    value = tokens[position]; position += 1
    if expected is not None: assert value == expected, (value, expected)
    return value
def parse():
    token = consume()
    if token == '{':
        result = {}
        while tokens[position] != '}':
            key = consume(); consume('='); assert key not in result, key
            result[key] = parse(); consume(';')
        consume('}'); return result
    if token == '(':
        result = []
        while tokens[position] != ')':
            result.append(parse())
            if tokens[position] == ',': consume(',')
            else: break
        consume(')'); return result
    return json.loads(token) if token.startswith('"') else token
project = parse(); assert position == len(tokens)
objects = project['objects']; assert project['rootObject'] in objects
for key, obj in objects.items():
    for field in ['fileRef','mainGroup','productReference','buildConfigurationList','productRefGroup']:
        if field in obj: assert obj[field] in objects, (key, field)
    for field in ['children','files','buildPhases','buildConfigurations','targets']:
        for reference in obj.get(field, []): assert reference in objects, reference
    if obj.get('isa') == 'PBXFileReference' and obj.get('sourceTree') == '<group>':
        assert (root/'OpenVK'/obj['path']).is_file(), obj['path']
refs = {key:value for key,value in objects.items() if value.get('isa') == 'PBXFileReference'}
compiled = []
resources = []
for obj in objects.values():
    if obj.get('isa') in ['PBXSourcesBuildPhase','PBXResourcesBuildPhase']:
        paths = [refs[objects[reference]['fileRef']]['path'] for reference in obj['files']]
        (compiled if obj['isa'] == 'PBXSourcesBuildPhase' else resources).extend(paths)
assert set(compiled) == {path.name for path in (root/'OpenVK').iterdir() if path.suffix in {'.m','.c'}}
assert 'Demo.json' in resources and 'Info.plist' not in resources
for resource in resources:
    path = root/'OpenVK'/resource
    assert not path.name.startswith('.'), ('Hidden file in app resources', resource)
    assert path.suffix.lower() in {'.png','.json','.cer','.wav','.mp4'}, ('Unsupported app resource', resource)
    if path.suffix.lower()=='.png':
        assert path.read_bytes().startswith(bytes([137,80,78,71,13,10,26,10])), ('Not a PNG', resource)
assert not any(ref.get('lastKnownFileType')=='image.png' and Path(ref['path']).suffix.lower()!='.png' for ref in refs.values())
for obj in objects.values():
    if obj.get('isa') == 'XCBuildConfiguration': assert obj['buildSettings']['IPHONEOS_DEPLOYMENT_TARGET'] == '6.0'
info = plistlib.loads((root/'OpenVK/Info.plist').read_bytes()); assert info['MinimumOSVersion'] == '6.0'
scheme = ET.parse(root/'OpenVKClassic.xcodeproj/xcshareddata/xcschemes/OpenVKClassic.xcscheme')
for buildable in scheme.findall('.//BuildableReference'): assert buildable.attrib['BlueprintIdentifier'] in objects
fixtures = json.loads((root/'OpenVK/Demo.json').read_text())
assert isinstance(fixtures['users.get'],list) and fixtures['users.get'][0]['id'] > 0
for method in ['newsfeed.get','friends.get','wall.get','messages.getHistory','messages.getConversations']:
    assert isinstance(fixtures[method]['items'],list), method
for item in fixtures['messages.getConversations']['items']:
    assert isinstance(item['conversation']['peer']['id'],int) and 'last_message' in item
for path in (root/'OpenVK').glob('*.m'):
    for image in re.findall(r'imageNamed:@"([^"]+)"',path.read_text()): assert image+'.png' in resources, image
for image in ['News','Friends','Messages','Profile','DemoAlex','DemoAnna','DemoClub','DemoPhoto']:
    assert image+'.png' in resources
assert info['CFBundleIdentifier'] == '${PRODUCT_BUNDLE_IDENTIFIER}'
print('PASS: OpenStep project syntax, references, build phases, resources, target 6.0, plist, shared scheme, demo shapes')
print('Native compilation and live API are not tested by this script.')

assert "ISRG-Root-X1.cer" in resources
assert hashlib.sha256((root/"OpenVK/ISRG-Root-X1.cer").read_bytes()).hexdigest() == "96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6"
print("PASS: ISRG Root X1 bundle resource and known SHA-256 fingerprint")

framework_names = {value.get("name") for value in refs.values() if value.get("lastKnownFileType") == "wrapper.framework"}
assert {"ImageIO.framework", "MediaPlayer.framework", "AVFoundation.framework"}.issubset(framework_names)
assert {"DemoAudio.wav", "DemoClip.mp4", "Linen.png", "AudioMedia.png", "VideoMedia.png", "PhotoMedia.png"}.issubset(set(resources))
for method in ["photos.getAll", "video.get", "audio.get"]: assert isinstance(fixtures[method]["items"], list)
print("PASS: media frameworks, demo media, artwork and library fixtures")
