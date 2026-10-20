#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project with Python's standard library; no package manager needed."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OBJECTS = {}

def oid(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

def add(label, isa, **values):
    key = oid(label)
    OBJECTS[key] = dict(isa=isa, **values)
    return key

def quoted(value):
    return json.dumps(value, ensure_ascii=False)

def encode(value, level=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (level + 1) + quoted(k) + ' = ' + encode(v, level + 1) + ';\n' for k, v in value.items()) + '\t' * level + '}'
    if isinstance(value, list):
        return '(' + ', '.join(encode(v, level) for v in value) + ')'
    if isinstance(value, int):
        return str(value)
    return quoted(value)

def file_ref(path, kind='sourcecode.swift'):
    return add('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='SOURCE_ROOT')

def config_list(label, settings):
    configs = []
    for name in ('Debug', 'Release'):
        common = dict(settings)
        common.update(SWIFT_OPTIMIZATION_LEVEL='-Onone' if name == 'Debug' else '-O',
                      SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if name == 'Debug' else '',
                      DEBUG_INFORMATION_FORMAT='dwarf' if name == 'Debug' else 'dwarf-with-dsym')
        options = dict(buildSettings=common, name=name)
        if label == 'project':
            options['baseConfigurationReference'] = oid('file:Config/Project.xcconfig')
        configs.append(add(label + name, 'XCBuildConfiguration', **options))
    return add(label + 'configs', 'XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

def main():
    OBJECTS.clear()
    project = oid('project')
    phone = oid('target:phone')
    watch = oid('target:watch')
    products = []
    groups = []
    # Compile shared engine sources into each platform's app module. The root
    # Swift package is for standalone tests only; native apps need no package resolution.
    target_ids = []
    widget = oid('target:launcher')
    widget_ref = file_ref('Apps/WatchLauncher/WorkoutLauncher.swift')
    widget_build = add('launcher:build', 'PBXBuildFile', fileRef=widget_ref)
    widget_source = add('launcher:sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=[widget_build], runOnlyForDeploymentPostprocessing=0)
    widget_frameworks = add('launcher:frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    widget_privacy = add('launcher:privacy', 'PBXBuildFile', fileRef=file_ref('Apps/Shared/PrivacyInfo.xcprivacy', 'text.xml'))
    widget_resources = add('launcher:resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[widget_privacy, add('launcher:strings', 'PBXBuildFile', fileRef=file_ref('Apps/Shared/Localizable.xcstrings', 'text.json.xcstrings'))], runOnlyForDeploymentPostprocessing=0)
    widget_product = add('launcher:product', 'PBXFileReference', explicitFileType='wrapper.app-extension', includeInIndex=0, path='LittleLiftLauncher.appex', sourceTree='BUILT_PRODUCTS_DIR')
    products.append(widget_product)
    groups.append(add('launcher:group', 'PBXGroup', name='Watch launcher', children=[widget_ref, file_ref('Config/WatchLauncher-Info.plist', 'text.plist.xml')], sourceTree='<group>'))
    widget_settings = dict(PRODUCT_NAME='LittleLiftLauncher', PRODUCT_BUNDLE_IDENTIFIER='$(LITTLELIFT_WATCH_BUNDLE_ID).launcher', SDKROOT='watchos', SUPPORTED_PLATFORMS='watchos watchsimulator', TARGETED_DEVICE_FAMILY='4', INFOPLIST_FILE='Config/WatchLauncher-Info.plist', GENERATE_INFOPLIST_FILE='NO', CODE_SIGN_STYLE='Automatic', SWIFT_VERSION='5.0', SWIFT_STRICT_CONCURRENCY='targeted', MARKETING_VERSION='0.1.0', CURRENT_PROJECT_VERSION='18', WATCHOS_DEPLOYMENT_TARGET='11.0', SKIP_INSTALL='YES', APPLICATION_EXTENSION_API_ONLY='YES')
    OBJECTS[widget] = dict(isa='PBXNativeTarget', buildConfigurationList=config_list('launcher', widget_settings), buildPhases=[widget_source, widget_frameworks, widget_resources], buildRules=[], dependencies=[], name='LittleLiftLauncher', productName='LittleLiftLauncher', productReference=widget_product, productType='com.apple.product-type.app-extension')
    target_ids.append(widget)
    for label, target, folder, name, bundle, sdk, family in [
        ('phone', phone, 'iPhone', 'LittleLift', '$(LITTLELIFT_PHONE_BUNDLE_ID)', 'iphoneos', '1'),
        ('watch', watch, 'Watch', 'LittleLiftWatch', '$(LITTLELIFT_WATCH_BUNDLE_ID)', 'watchos', '4'),
    ]:
        paths = sorted([*ROOT.glob(f'Apps/{folder}/*.swift'), *ROOT.glob('Apps/Shared/*.swift'),
                        *ROOT.glob('Sources/WorkoutCore/*.swift')])
        refs = [file_ref(str(p.relative_to(ROOT))) for p in paths]
        group_refs = [ref for path, ref in zip(paths, refs) if path.parent.name == folder]
        group = add('group:' + label, 'PBXGroup', name=folder, children=group_refs, sourceTree='<group>')
        groups.append(group)
        sources = []
        for path, ref in zip(paths, refs):
            sources.append(add(label + ':build:' + path.name, 'PBXBuildFile', fileRef=ref))
        source_phase = add(label + ':sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
        frameworks = add(label + ':frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
        asset_ref = file_ref(f'Apps/{folder}/Assets.xcassets', 'folder.assetcatalog')
        OBJECTS[group]['children'].append(asset_ref)
        asset_build = add(label + ':assets', 'PBXBuildFile', fileRef=asset_ref)
        privacy_ref = file_ref('Apps/Shared/PrivacyInfo.xcprivacy', 'text.xml')
        privacy_build = add(label + ':privacy', 'PBXBuildFile', fileRef=privacy_ref)
        resources = add(label + ':resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[asset_build, privacy_build, add(label + ':strings', 'PBXBuildFile', fileRef=file_ref('Apps/Shared/Localizable.xcstrings', 'text.json.xcstrings'))], runOnlyForDeploymentPostprocessing=0)
        product = add(label + ':product', 'PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0, path=name + '.app', sourceTree='BUILT_PRODUCTS_DIR')
        products.append(product)
        settings = dict(PRODUCT_NAME=name, PRODUCT_BUNDLE_IDENTIFIER=bundle, SDKROOT=sdk,
                        SUPPORTED_PLATFORMS='iphoneos iphonesimulator' if label == 'phone' else 'watchos watchsimulator',
                        TARGETED_DEVICE_FAMILY=family, INFOPLIST_FILE=f'Config/{folder}-Info.plist',
                        GENERATE_INFOPLIST_FILE='NO', CODE_SIGN_STYLE='Automatic', SWIFT_VERSION='5.0',
                        SWIFT_STRICT_CONCURRENCY='targeted', MARKETING_VERSION='0.1.0', CURRENT_PROJECT_VERSION='18',
                        ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', ENABLE_PREVIEWS='YES',
                        SUPPORTS_MACCATALYST='NO', SKIP_INSTALL='NO' if label == 'phone' else 'YES')
        settings['IPHONEOS_DEPLOYMENT_TARGET' if label == 'phone' else 'WATCHOS_DEPLOYMENT_TARGET'] = '18.0' if label == 'phone' else '11.0'
        if label == 'watch':
            OBJECTS[resources]['files'].append(add('watch:permission-strings', 'PBXBuildFile', fileRef=file_ref('Apps/Watch/InfoPlist.xcstrings', 'text.json.xcstrings')))
        phases = [source_phase, frameworks, resources]
        dependencies = []
        if label == 'phone':
            watch_product = oid('watch:product')
            embed_file = add('embed-watch-file', 'PBXBuildFile', fileRef=watch_product, settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
            embed = add('embed-watch', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='$(CONTENTS_FOLDER_PATH)/Watch',
                        dstSubfolderSpec=16, files=[embed_file], name='Embed Watch Content', runOnlyForDeploymentPostprocessing=0)
            phases.append(embed)
            proxy = add('watch-proxy', 'PBXContainerItemProxy', containerPortal=project, proxyType=1, remoteGlobalIDString=watch, remoteInfo='LittleLiftWatch')
            dependencies.append(add('watch-dependency', 'PBXTargetDependency', target=watch, targetProxy=proxy))
        if label == 'watch':
            settings['CODE_SIGN_ENTITLEMENTS'] = 'Config/Watch.entitlements'
            embed_widget_file = add('embed-launcher-file', 'PBXBuildFile', fileRef=widget_product, settings={'ATTRIBUTES': ['RemoveHeadersOnCopy']})
            phases.append(add('embed-launcher', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='', dstSubfolderSpec=13, files=[embed_widget_file], name='Embed launcher', runOnlyForDeploymentPostprocessing=0))
            widget_proxy = add('launcher-proxy', 'PBXContainerItemProxy', containerPortal=project, proxyType=1, remoteGlobalIDString=widget, remoteInfo='LittleLiftLauncher')
            dependencies.append(add('launcher-dependency', 'PBXTargetDependency', target=widget, targetProxy=widget_proxy))
        OBJECTS[target] = dict(isa='PBXNativeTarget', buildConfigurationList=config_list(label, settings),
            buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name,
            productReference=product, productType='com.apple.product-type.application')
        target_ids.append(target)

    config_refs = [file_ref('Config/iPhone-Info.plist', 'text.plist.xml'), file_ref('Config/Watch-Info.plist', 'text.plist.xml'),
                   file_ref('Config/Project.xcconfig', 'text.xcconfig')]
    shared_refs = [file_ref(str(p.relative_to(ROOT))) for p in sorted(ROOT.glob('Apps/Shared/*.swift'))]
    shared_refs.append(file_ref('Apps/Shared/PrivacyInfo.xcprivacy', 'text.xml'))
    groups.append(add('shared-group', 'PBXGroup', name='Shared', children=shared_refs, sourceTree='<group>'))
    core_refs = [file_ref(str(p.relative_to(ROOT))) for p in sorted(ROOT.glob('Sources/WorkoutCore/*.swift'))]
    groups.append(add('core-group', 'PBXGroup', name='Workout engine', children=core_refs, sourceTree='<group>'))
    groups.append(add('config-group', 'PBXGroup', name='Config', children=config_refs, sourceTree='<group>'))
    groups.append(add('products', 'PBXGroup', name='Products', children=products, sourceTree='<group>'))
    main_group = add('main-group', 'PBXGroup', children=groups, sourceTree='<group>')
    project_settings = dict(CLANG_ENABLE_MODULES='YES', SWIFT_VERSION='5.0', IPHONEOS_DEPLOYMENT_TARGET='18.0',
                            CLANG_ANALYZER_NONNULL='YES', ENABLE_USER_SCRIPT_SANDBOXING='YES')
    OBJECTS[project] = dict(isa='PBXProject', attributes={'BuildIndependentTargetsInParallel': 'YES', 'LastUpgradeCheck': '1600'},
        buildConfigurationList=config_list('project', project_settings), compatibilityVersion='Xcode 15.0', developmentRegion='en',
        hasScannedForEncodings=0, knownRegions=['en', 'es', 'Base'], mainGroup=main_group, productRefGroup=oid('products'),
        projectDirPath='', projectRoot='', targets=target_ids)
    directory = ROOT / 'LittleLift.xcodeproj'
    directory.mkdir(exist_ok=True)
    body = dict(archiveVersion=1, classes={}, objectVersion=60, objects=OBJECTS, rootObject=project)
    (directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + encode(body) + '\n')
    for name, target in [('LittleLift', phone), ('LittleLiftWatch', watch)]:
        scheme_dir = directory / 'xcshareddata/xcschemes'
        scheme_dir.mkdir(parents=True, exist_ok=True)
        scheme = ET.Element('Scheme', LastUpgradeVersion='1600', version='1.3')
        build = ET.SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
        entries = ET.SubElement(build, 'BuildActionEntries')
        entry = ET.SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES', buildForProfiling='YES', buildForArchiving='YES', buildForAnalyzing='YES')
        def reference(parent):
            ET.SubElement(parent, 'BuildableReference', BuildableIdentifier='primary', BlueprintIdentifier=target,
                          BuildableName=name+'.app', BlueprintName=name, ReferencedContainer='container:LittleLift.xcodeproj')
        reference(entry)
        ET.SubElement(scheme, 'TestAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.DebuggerFoundation.Launcher.LLDB', shouldUseLaunchSchemeArgsEnv='YES')
        launch = ET.SubElement(scheme, 'LaunchAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.DebuggerFoundation.Launcher.LLDB', launchStyle='0', useCustomWorkingDirectory='NO', ignoresPersistentStateOnLaunch='NO', debugDocumentVersioning='YES', debugServiceExtension='internal', allowLocationSimulation='YES')
        reference(ET.SubElement(launch, 'BuildableProductRunnable', runnableDebuggingMode='0'))
        profile = ET.SubElement(scheme, 'ProfileAction', buildConfiguration='Release', shouldUseLaunchSchemeArgsEnv='YES', savedToolIdentifier='', useCustomWorkingDirectory='NO', debugDocumentVersioning='YES')
        reference(ET.SubElement(profile, 'BuildableProductRunnable', runnableDebuggingMode='0'))
        ET.SubElement(scheme, 'AnalyzeAction', buildConfiguration='Debug')
        ET.SubElement(scheme, 'ArchiveAction', buildConfiguration='Release', revealArchiveInOrganizer='YES')
        ET.indent(scheme)
        ET.ElementTree(scheme).write(scheme_dir / (name + '.xcscheme'), encoding='UTF-8', xml_declaration=True)
    print('Generated LittleLift.xcodeproj (iPhone + embedded watchOS app).')

if __name__ == '__main__':
    main()
