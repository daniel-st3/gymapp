#!/usr/bin/env python3
"""Generate the standalone probe; no edits to the workout app's project or signing."""
from pathlib import Path
import importlib.util, plistlib
ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('project_builder', ROOT.parents[1] / 'scripts/generate_project.py')
g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
g.OBJECTS.clear()
ref = g.file_ref('Probe.swift')
file = g.add('probe-build', 'PBXBuildFile', fileRef=ref)
sources = g.add('probe-sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=[file], runOnlyForDeploymentPostprocessing=0)
product = g.add('probe-product', 'PBXFileReference', explicitFileType='wrapper.application', path='MotionProbe.app', sourceTree='BUILT_PRODUCTS_DIR')
products = g.add('probe-products', 'PBXGroup', children=[product], name='Products', sourceTree='<group>')
group = g.add('probe-main', 'PBXGroup', children=[ref, products], sourceTree='<group>')
settings = dict(PRODUCT_NAME='MotionProbe', PRODUCT_BUNDLE_IDENTIFIER='$(MOTION_PROBE_BUNDLE_ID)', SDKROOT='watchos', SUPPORTED_PLATFORMS='watchos watchsimulator', TARGETED_DEVICE_FAMILY='4', WATCHOS_DEPLOYMENT_TARGET='11.0', SWIFT_VERSION='5.0', INFOPLIST_FILE='Info.plist', GENERATE_INFOPLIST_FILE='NO', CODE_SIGN_ENTITLEMENTS='Probe.entitlements', CODE_SIGN_STYLE='Automatic', MARKETING_VERSION='0.1', CURRENT_PROJECT_VERSION='1')
target = g.add('probe-target', 'PBXNativeTarget', buildConfigurationList=g.config_list('probe-target',settings), buildPhases=[sources], buildRules=[], dependencies=[], name='MotionProbe', productName='MotionProbe', productReference=product, productType='com.apple.product-type.application')
project = g.add('probe-project', 'PBXProject', attributes={'LastUpgradeCheck':'2700'}, buildConfigurationList=g.config_list('probe-project',{'CLANG_ENABLE_MODULES':'YES'}), compatibilityVersion='Xcode 15.0', developmentRegion='en', hasScannedForEncodings=0, knownRegions=['en','Base'], mainGroup=group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[target])
folder=ROOT/'MotionProbe.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n'+g.encode(dict(archiveVersion=1,classes={},objectVersion=60,objects=g.OBJECTS,rootObject=project))+'\n')
plist={'CFBundleDisplayName':'Lift Motion Probe','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','WKApplication':True,'WKWatchOnly':True,'WKBackgroundModes':['workout-processing'],'NSMotionUsageDescription':'A future explicit diagnostic would inspect local wrist samples; this capability probe does not collect them.','NSHealthShareUsageDescription':'This signing probe does not read health data.','NSHealthUpdateUsageDescription':'This signing probe does not start or save a workout.'}
(ROOT/'Info.plist').write_bytes(plistlib.dumps(plist))
(ROOT/'Probe.entitlements').write_bytes(plistlib.dumps({'com.apple.developer.healthkit':True}))
print('Generated standalone MotionProbe.xcodeproj; no main app files changed.')
