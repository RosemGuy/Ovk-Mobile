from pathlib import Path
import hashlib
r=Path(__file__).resolve().parents[1]; a=r/'OpenVK'
def uid(s):return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objs=[]
def obj(key,body):objs.append(uid(key)+' = { '+body+' };');return uid(key)
files=[];sources=[];resources=[]
for p in sorted(a.iterdir()):
 # Only known source/resource files belong in the application. Editor backups stay on disk.
 if p.name.startswith('.') or not p.is_file():continue
 if p.name=='Info.plist':typ='text.plist.xml'
 elif p.suffix=='.m':typ='sourcecode.c.objc'
 elif p.suffix=='.c':typ='sourcecode.c.c'
 elif p.suffix=='.h':typ='sourcecode.c.h'
 elif p.suffix=='.json':typ='text.json'
 elif p.suffix in ['.cer','.wav','.mp4']:typ='file'
 elif p.suffix.lower()=='.png':typ='image.png'
 else:continue
 ref=obj('file'+p.name,f'isa = PBXFileReference; lastKnownFileType = {typ}; path = "{p.name}"; sourceTree = "<group>";');files.append(ref)
 if p.suffix in ['.m','.c'] or typ in ['folder','image.png','text.json','file']:
  build=obj('build'+p.name,f'isa = PBXBuildFile; fileRef = {ref};')
  (sources if p.suffix in ['.m','.c'] else resources).append(build)
frameworks=[];frameworkrefs=[]
for name in ['UIKit','Foundation','CoreGraphics','Security','QuartzCore','ImageIO','CoreMedia','MediaPlayer','AVFoundation','AudioToolbox']:
 ref=obj(name,f'isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {name}.framework; path = System/Library/Frameworks/{name}.framework; sourceTree = SDKROOT;');frameworkrefs.append(ref)
 frameworks.append(obj('build'+name,f'isa = PBXBuildFile; fileRef = {ref};'))
prod=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OpenVKClassic.app; sourceTree = BUILT_PRODUCTS_DIR;')
def arr(xs):return '('+','.join(xs)+',)'
obj('appgroup',f'isa = PBXGroup; children = {arr(files)}; path = OpenVK; sourceTree = "<group>";')
obj('frameworkgroup',f'isa = PBXGroup; children = {arr(frameworkrefs)}; name = Frameworks; sourceTree = "<group>";')
obj('productgroup',f'isa = PBXGroup; children = ({prod},); name = Products; sourceTree = "<group>";')
obj('main',f'isa = PBXGroup; children = ({uid("appgroup")},{uid("frameworkgroup")},{uid("productgroup")},); sourceTree = "<group>";')
for key,isa,items in [('sources','PBXSourcesBuildPhase',sources),('resources','PBXResourcesBuildPhase',resources),('frameworks','PBXFrameworksBuildPhase',frameworks)]:obj(key,f'isa = {isa}; buildActionMask = 2147483647; files = {arr(items)}; runOnlyForDeploymentPostprocessing = 0;')
for kind in ['project','target']:
 configs=[]
 for mode in ['Debug','Release']:
  common='CLANG_ENABLE_OBJC_ARC = YES; CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR; GCC_C_LANGUAGE_STANDARD = gnu99; IPHONEOS_DEPLOYMENT_TARGET = 6.0; SDKROOT = iphoneos;'
  if kind=='target':common+=' ARCHS = "$(ARCHS_STANDARD_32_BIT)"; TARGETED_DEVICE_FAMILY = "1,2"; INFOPLIST_FILE = OpenVK/Info.plist; PRODUCT_NAME = OpenVKClassic; PRODUCT_BUNDLE_IDENTIFIER = org.openvk.classic.ios6; "CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "iPhone Developer";'
  if mode=='Debug':common+=' GCC_OPTIMIZATION_LEVEL = 0; GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1","$(inherited)",); ONLY_ACTIVE_ARCH = YES;'
  else:common+=' GCC_OPTIMIZATION_LEVEL = s; ONLY_ACTIVE_ARCH = NO;'
  configs.append(obj(kind+mode,f'isa = XCBuildConfiguration; buildSettings = {{ {common} }}; name = {mode};'))
 obj(kind+'configs',f'isa = XCConfigurationList; buildConfigurations = {arr(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("targetconfigs")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},); buildRules = (); dependencies = (); name = OpenVKClassic; productName = OpenVKClassic; productReference = {prod}; productType = "com.apple.product-type.application";')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 0510; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 3.2"; developmentRegion = ru; hasScannedForEncodings = 0; knownRegions = (ru,en,Base,); mainGroup = {uid("main")}; productRefGroup = {uid("productgroup")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
(r/'OpenVKClassic.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 46; objects = {\n'+'\n'.join(objs)+'\n}; rootObject = '+uid('project')+'; }\n')
(r/'OpenVKClassic.xcodeproj/xcshareddata/xcschemes/OpenVKClassic.xcscheme').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="0510" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'''+uid('target')+'''" BuildableName="OpenVKClassic.app" BlueprintName="OpenVKClassic" ReferencedContainer="container:OpenVKClassic.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'''+uid('target')+'''" BuildableName="OpenVKClassic.app" BlueprintName="OpenVKClassic" ReferencedContainer="container:OpenVKClassic.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
