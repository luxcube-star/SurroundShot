#!/usr/bin/env python3
"""SurroundShot.xcodeproj/project.pbxproj 를 만든다.

Xcode 없이(리눅스·클라우드에서) 프로젝트 파일을 관리하기 위한 스크립트.
폴더(App / ShareExtension / Shared)는 Xcode 16+ '동기화 폴더'라서 파일을 추가·삭제해도
이 스크립트를 다시 돌릴 필요가 없다. 타깃·빌드 설정을 바꿀 때만 고치고 다시 실행한다.

    python3 scripts/gen_xcodeproj.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "SurroundShot.xcodeproj" / "project.pbxproj"

OPENCV_URL = "https://github.com/yeatse/opencv-spm.git"
OPENCV_VERSION = "4.13.0"
BUNDLE_ID = "kr.koh0001.surroundshot"
DISPLAY_NAME = "Surround Shot"  # AltStore 규칙: 영문·숫자·공백만. 한국어 이름은 ko.lproj
VERSION = "1.0"
BUILD = "1"
DEPLOYMENT = "18.0"
PHOTO_ADD_USAGE = "합성한 주위환경 사진을 사진 앱에 저장합니다."


def oid(n: int) -> str:
    return f"5A5500000000000000{n:06X}"


P, MAIN, PRODUCTS = oid(1), oid(2), oid(3)
APP_REF, EXT_REF = oid(4), oid(5)
SG_APP, SG_EXT, SG_SHARED = oid(6), oid(7), oid(8)
EXC_EXT = oid(9)
T_APP, T_EXT = oid(0x10), oid(0x11)
APP_SRC, APP_FW, APP_RES, APP_EMBED = oid(0x12), oid(0x13), oid(0x14), oid(0x15)
EXT_SRC, EXT_FW, EXT_RES = oid(0x16), oid(0x17), oid(0x18)
BF_EMBED, BF_OCV_APP, BF_OCV_EXT = oid(0x19), oid(0x1A), oid(0x1B)
PKG, PROD_APP, PROD_EXT = oid(0x1C), oid(0x1D), oid(0x1E)
PROXY, DEP = oid(0x1F), oid(0x20)
CL_P, CFG_P_D, CFG_P_R = oid(0x21), oid(0x22), oid(0x23)
CL_APP, CFG_APP_D, CFG_APP_R = oid(0x24), oid(0x25), oid(0x26)
CL_EXT, CFG_EXT_D, CFG_EXT_R = oid(0x27), oid(0x28), oid(0x29)


def q(v: str) -> str:
    """pbxproj 문자열: 영문·숫자·일부 기호만이면 그대로, 아니면 따옴표."""
    import re
    if re.fullmatch(r"[A-Za-z0-9_./]+", v):
        return v
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings_block(d: dict, indent: str) -> str:
    lines = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            lines.append(f"{indent}{k} = (")
            for item in v:
                lines.append(f"{indent}\t{q(item)},")
            lines.append(f"{indent});")
        else:
            lines.append(f"{indent}{k} = {q(str(v))};")
    return "\n".join(lines)


PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SDKROOT": "iphoneos",
}
PROJECT_DEBUG = {
    **PROJECT_COMMON,
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}
PROJECT_RELEASE = {
    **PROJECT_COMMON,
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}

TARGET_COMMON = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": DISPLAY_NAME,
    "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription": PHOTO_ADD_USAGE,
    "MARKETING_VERSION": VERSION,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_OBJC_BRIDGING_HEADER": "Shared/SurroundShot-Bridging-Header.h",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
APP_SETTINGS = {
    **TARGET_COMMON,
    "ENABLE_PREVIEWS": "YES",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.photography",
    "INFOPLIST_KEY_NSCameraUsageDescription": "주위환경 사진을 촬영합니다.",
    "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "촬영한 사진에 촬영 위치를 기록합니다.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
}
EXT_SETTINGS = {
    **TARGET_COMMON,
    "INFOPLIST_FILE": "ShareExtension/Info.plist",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks",
                                "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".share",
    "SKIP_INSTALL": "YES",
}


def config(cid: str, name: str, settings: dict) -> str:
    return f"""\t\t{cid} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings_block(settings, chr(9) * 4)}
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""


def config_list(cid: str, label: str, d: str, r: str) -> str:
    return f"""\t\t{cid} /* Build configuration list for {label} */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{d} /* Debug */,
\t\t\t\t{r} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};"""


def phase(pid: str, isa: str, name: str, files: list[str]) -> str:
    body = "".join(f"\n\t\t\t\t{f}," for f in files)
    return f"""\t\t{pid} /* {name} */ = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({body}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};"""


text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXBuildFile section */
\t\t{BF_EMBED} /* ShareExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {EXT_REF} /* ShareExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
\t\t{BF_OCV_APP} /* OpenCV in Frameworks */ = {{isa = PBXBuildFile; productRef = {PROD_APP} /* OpenCV */; }};
\t\t{BF_OCV_EXT} /* OpenCV in Frameworks */ = {{isa = PBXBuildFile; productRef = {PROD_EXT} /* OpenCV */; }};
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t{PROXY} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {P} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {T_EXT};
\t\t\tremoteInfo = ShareExtension;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{APP_EMBED} /* Embed Foundation Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t{BF_EMBED} /* ShareExtension.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t{APP_REF} /* SurroundShot.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SurroundShot.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{EXT_REF} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
\t\t{EXC_EXT} /* Exceptions for "ShareExtension" folder in "ShareExtension" target */ = {{
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tInfo.plist,
\t\t\t);
\t\t\ttarget = {T_EXT} /* ShareExtension */;
\t\t}};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{SG_APP} /* App */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = App;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{SG_EXT} /* ShareExtension */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\texceptions = (
\t\t\t\t{EXC_EXT} /* Exceptions for "ShareExtension" folder in "ShareExtension" target */,
\t\t\t);
\t\t\tpath = ShareExtension;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{SG_SHARED} /* Shared */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = Shared;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
{phase(APP_FW, "PBXFrameworksBuildPhase", "Frameworks", [f"{BF_OCV_APP} /* OpenCV in Frameworks */"])}
{phase(EXT_FW, "PBXFrameworksBuildPhase", "Frameworks", [f"{BF_OCV_EXT} /* OpenCV in Frameworks */"])}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{MAIN} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{SG_APP} /* App */,
\t\t\t\t{SG_EXT} /* ShareExtension */,
\t\t\t\t{SG_SHARED} /* Shared */,
\t\t\t\t{PRODUCTS} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_REF} /* SurroundShot.app */,
\t\t\t\t{EXT_REF} /* ShareExtension.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{T_APP} /* SurroundShot */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CL_APP} /* Build configuration list for PBXNativeTarget "SurroundShot" */;
\t\t\tbuildPhases = (
\t\t\t\t{APP_SRC} /* Sources */,
\t\t\t\t{APP_FW} /* Frameworks */,
\t\t\t\t{APP_RES} /* Resources */,
\t\t\t\t{APP_EMBED} /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{DEP} /* PBXTargetDependency */,
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{SG_APP} /* App */,
\t\t\t\t{SG_SHARED} /* Shared */,
\t\t\t);
\t\t\tname = SurroundShot;
\t\t\tpackageProductDependencies = (
\t\t\t\t{PROD_APP} /* OpenCV */,
\t\t\t);
\t\t\tproductName = SurroundShot;
\t\t\tproductReference = {APP_REF} /* SurroundShot.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{T_EXT} /* ShareExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CL_EXT} /* Build configuration list for PBXNativeTarget "ShareExtension" */;
\t\t\tbuildPhases = (
\t\t\t\t{EXT_SRC} /* Sources */,
\t\t\t\t{EXT_FW} /* Frameworks */,
\t\t\t\t{EXT_RES} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{SG_EXT} /* ShareExtension */,
\t\t\t\t{SG_SHARED} /* Shared */,
\t\t\t);
\t\t\tname = ShareExtension;
\t\t\tpackageProductDependencies = (
\t\t\t\t{PROD_EXT} /* OpenCV */,
\t\t\t);
\t\t\tproductName = ShareExtension;
\t\t\tproductReference = {EXT_REF} /* ShareExtension.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{P} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2640;
\t\t\t\tLastUpgradeCheck = 2640;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{T_APP} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;
\t\t\t\t\t}};
\t\t\t\t\t{T_EXT} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.4;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {CL_P} /* Build configuration list for PBXProject "SurroundShot" */;
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t\tko,
\t\t\t);
\t\t\tmainGroup = {MAIN};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpackageReferences = (
\t\t\t\t{PKG} /* XCRemoteSwiftPackageReference "opencv-spm" */,
\t\t\t);
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {PRODUCTS} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{T_APP} /* SurroundShot */,
\t\t\t\t{T_EXT} /* ShareExtension */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
{phase(APP_RES, "PBXResourcesBuildPhase", "Resources", [])}
{phase(EXT_RES, "PBXResourcesBuildPhase", "Resources", [])}
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
{phase(APP_SRC, "PBXSourcesBuildPhase", "Sources", [])}
{phase(EXT_SRC, "PBXSourcesBuildPhase", "Sources", [])}
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{DEP} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {T_EXT} /* ShareExtension */;
\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
{config(CFG_P_D, "Debug", PROJECT_DEBUG)}
{config(CFG_P_R, "Release", PROJECT_RELEASE)}
{config(CFG_APP_D, "Debug", APP_SETTINGS)}
{config(CFG_APP_R, "Release", APP_SETTINGS)}
{config(CFG_EXT_D, "Debug", EXT_SETTINGS)}
{config(CFG_EXT_R, "Release", EXT_SETTINGS)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{config_list(CL_P, 'PBXProject "SurroundShot"', CFG_P_D, CFG_P_R)}
{config_list(CL_APP, 'PBXNativeTarget "SurroundShot"', CFG_APP_D, CFG_APP_R)}
{config_list(CL_EXT, 'PBXNativeTarget "ShareExtension"', CFG_EXT_D, CFG_EXT_R)}
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{PKG} /* XCRemoteSwiftPackageReference "opencv-spm" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "{OPENCV_URL}";
\t\t\trequirement = {{
\t\t\t\tkind = exactVersion;
\t\t\t\tversion = {OPENCV_VERSION};
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{PROD_APP} /* OpenCV */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {PKG} /* XCRemoteSwiftPackageReference "opencv-spm" */;
\t\t\tproductName = OpenCV;
\t\t}};
\t\t{PROD_EXT} /* OpenCV */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {PKG} /* XCRemoteSwiftPackageReference "opencv-spm" */;
\t\t\tproductName = OpenCV;
\t\t}};
/* End XCSwiftPackageProductDependency section */
\t}};
\trootObject = {P} /* Project object */;
}}
"""

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(text, encoding="utf-8")

SCHEME = OUT.parent / "xcshareddata" / "xcschemes" / "SurroundShot.xcscheme"
SCHEME.parent.mkdir(parents=True, exist_ok=True)
ref = f"""<BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{T_APP}"
               BuildableName = "SurroundShot.app"
               BlueprintName = "SurroundShot"
               ReferencedContainer = "container:SurroundShot.xcodeproj">
            </BuildableReference>"""
SCHEME.write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2640"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""", encoding="utf-8")
print("wrote", OUT, "and", SCHEME)
