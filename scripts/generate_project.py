"""Deterministically generate the checked-in Xcode project, without dependencies.

Run after adding/removing Swift sources or resources. CI uses --check to detect drift.
"""
from pathlib import Path
from hashlib import sha1
import json
import sys

ROOT = Path(__file__).resolve().parents[1]


def uid(name):
    return sha1(name.encode()).hexdigest()[:24].upper()


def encode(value, level=0):
    indent = "\t" * level
    if isinstance(value, dict):
        body = "\n".join(f"{indent}\t{json.dumps(k)} = {encode(v, level + 1)};" for k, v in value.items())
        return "{\n" + body + "\n" + indent + "}"
    if isinstance(value, list):
        return "(\n" + "\n".join(f"{indent}\t{encode(v, level + 1)}," for v in value) + "\n" + indent + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value)


def generate():
    objects = {}

    def add(identity, isa, **values):
        key = uid(identity)
        objects[key] = {"isa": isa, **values}
        return key

    app_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "OKNative").rglob("*.swift"))
    test_sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / "OKNativeTests").rglob("*.swift"))
    resources = ["OKNative/Resources/Assets.xcassets", "OKNative/Resources/PrivacyInfo.xcprivacy"]
    references = {}
    configuration_files = ["OKNative/Resources/Info.plist", "OKNative/Resources/Simulator.entitlements"]
    for path in app_sources + test_sources + resources + configuration_files:
        kind = "sourcecode.swift" if path.endswith(".swift") else "folder.assetcatalog" if path.endswith(".xcassets") else "text.xml"
        references[path] = add(path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")

    app_product = add("app-product", "PBXFileReference", explicitFileType="wrapper.application", path="OKNative.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="OKNativeTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    source_group = add("source-group", "PBXGroup", name="App", children=[references[p] for p in app_sources], sourceTree="<group>")
    test_group = add("test-group", "PBXGroup", name="Tests", children=[references[p] for p in test_sources], sourceTree="<group>")
    resource_group = add("resource-group", "PBXGroup", name="Resources", children=[references[p] for p in resources + configuration_files], sourceTree="<group>")
    products_group = add("products-group", "PBXGroup", name="Products", children=[app_product, test_product], sourceTree="<group>")
    main_group = add("main-group", "PBXGroup", children=[source_group, resource_group, test_group, products_group], sourceTree="<group>")

    def phase(name, isa, paths):
        builds = [add("build:" + p, "PBXBuildFile", fileRef=references[p]) for p in paths]
        return add(name, isa, buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)

    app_phases = [phase("app-sources", "PBXSourcesBuildPhase", app_sources),
                  phase("app-frameworks", "PBXFrameworksBuildPhase", []),
                  phase("app-resources", "PBXResourcesBuildPhase", resources)]
    test_phases = [phase("test-sources", "PBXSourcesBuildPhase", test_sources),
                   phase("test-frameworks", "PBXFrameworksBuildPhase", []),
                   phase("test-resources", "PBXResourcesBuildPhase", [])]

    def configurations(name, settings):
        configs = []
        for mode in ["Debug", "Release"]:
            values = dict(settings)
            if name == "project":
                values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                               "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym",
                               "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if mode == "Debug" else "",
                               "ENABLE_TESTABILITY": "YES" if mode == "Debug" else "NO"})
            configs.append(add(name + mode, "XCBuildConfiguration", buildSettings=values, name=mode))
        return add(name + "-configurations", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

    project_configs = configurations("project", {
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        "TARGETED_DEVICE_FAMILY": "1", "CODE_SIGN_STYLE": "Automatic",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    })
    app_configs = configurations("app", {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.erapchu.oknative",
        "INFOPLIST_FILE": "OKNative/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "SWIFT_EMIT_LOC_STRINGS": "YES", "ENABLE_PREVIEWS": "YES",
        "CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]": "OKNative/Resources/Simulator.entitlements",
    })
    test_configs = configurations("tests", {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.erapchu.oknative.tests",
        "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/OKNative.app/OKNative",
        "BUNDLE_LOADER": "$(TEST_HOST)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
    })
    app_target = add("app-target", "PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=app_phases,
                     buildRules=[], dependencies=[], name="OKNative", productName="OKNative", productReference=app_product,
                     productType="com.apple.product-type.application")
    proxy = add("test-proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
                remoteGlobalIDString=app_target, remoteInfo="OKNative")
    dependency = add("test-dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
    test_target = add("test-target", "PBXNativeTarget", buildConfigurationList=test_configs, buildPhases=test_phases,
                      buildRules=[], dependencies=[dependency], name="OKNativeTests", productName="OKNativeTests",
                      productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
    project = add("project", "PBXProject", attributes={
        "BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600",
        "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"},
                             test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}}},
        buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="ru",
        hasScannedForEncodings=0, knownRegions=["ru", "en", "Base"], mainGroup=main_group,
        productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[app_target, test_target])
    pbx = "// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56,
                                                 "objects": objects, "rootObject": project}) + "\n"

    def buildable(identifier, name):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:OKNative.xcodeproj"/>'

    app_ref = buildable(app_target, "OKNative.app")
    test_ref = buildable(test_target, "OKNativeTests.xctest")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{test_ref}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO" parallelizable="NO">{test_ref}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    return {"OKNative.xcodeproj/project.pbxproj": pbx,
            "OKNative.xcodeproj/xcshareddata/xcschemes/OKNative.xcscheme": scheme}


if __name__ == "__main__":
    for name, contents in generate().items():
        path = ROOT / name
        if "--check" in sys.argv:
            if not path.exists() or path.read_text(encoding="utf-8") != contents:
                sys.exit(f"Outdated {name}: run python3 scripts/generate_project.py")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8", newline="\n")
    print("Xcode project is up to date.")

