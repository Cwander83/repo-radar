#!/usr/bin/env python3
import os

def generate_pbxproj():
    content = """// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {

/* Begin PBXBuildFile section */
\t\t000000000000000000000040 /* RepoRadarApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000030 /* RepoRadarApp.swift */; };
\t\t000000000000000000000041 /* RepoRadarWidget.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000032 /* RepoRadarWidget.swift */; };
\t\t000000000000000000000042 /* RepoRadarWidget.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = 000000000000000000000021 /* RepoRadarWidget.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
\t\t000000000000000000000043 /* RepoRadarCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000091 /* RepoRadarCore */; };
\t\t000000000000000000000044 /* RepoRadarCore in Frameworks */ = {isa = PBXBuildFile; productRef = 000000000000000000000091 /* RepoRadarCore */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t000000000000000000000071 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 000000000000000000000001 /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = 000000000000000000000060;
\t\t\tremoteInfo = RepoRadarWidget;
\t\t};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t000000000000000000000054 /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t000000000000000000000042 /* RepoRadarWidget.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t000000000000000000000020 /* RepoRadar.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = RepoRadar.app; sourceTree = BUILT_PRODUCTS_DIR; };
\t\t000000000000000000000021 /* RepoRadarWidget.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = RepoRadarWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; };
\t\t000000000000000000000030 /* RepoRadarApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RepoRadarApp.swift; sourceTree = "<group>"; };
\t\t000000000000000000000031 /* RepoRadar.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = RepoRadar.entitlements; sourceTree = "<group>"; };
\t\t000000000000000000000032 /* RepoRadarWidget.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RepoRadarWidget.swift; sourceTree = "<group>"; };
\t\t000000000000000000000033 /* RepoRadarWidget.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = RepoRadarWidget.entitlements; sourceTree = "<group>"; };
\t\t000000000000000000000034 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
\t\t000000000000000000000035 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
\t\t000000000000000000000036 /* Base.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t000000000000000000000052 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t000000000000000000000043 /* RepoRadarCore in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t000000000000000000000062 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t000000000000000000000044 /* RepoRadarCore in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t000000000000000000000002 = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000010 /* RepoRadar */,
\t\t\t\t000000000000000000000011 /* RepoRadarWidget */,
\t\t\t\t000000000000000000000013 /* Configurations */,
\t\t\t\t000000000000000000000012 /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000010 /* RepoRadar */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000030 /* RepoRadarApp.swift */,
\t\t\t\t000000000000000000000031 /* RepoRadar.entitlements */,
\t\t\t\t000000000000000000000034 /* Info.plist */,
\t\t\t);
\t\t\tpath = RepoRadar;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000011 /* RepoRadarWidget */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000032 /* RepoRadarWidget.swift */,
\t\t\t\t000000000000000000000033 /* RepoRadarWidget.entitlements */,
\t\t\t\t000000000000000000000035 /* Info.plist */,
\t\t\t);
\t\t\tpath = RepoRadarWidget;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000013 /* Configurations */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000036 /* Base.xcconfig */,
\t\t\t);
\t\t\tpath = Configurations;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000012 /* Products */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000020 /* RepoRadar.app */,
\t\t\t\t000000000000000000000021 /* RepoRadarWidget.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t000000000000000000000050 /* RepoRadar */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 000000000000000000000056 /* Build configuration list for PBXNativeTarget "RepoRadar" */;
\t\t\tbuildPhases = (
\t\t\t\t000000000000000000000051 /* Sources */,
\t\t\t\t000000000000000000000052 /* Frameworks */,
\t\t\t\t000000000000000000000054 /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t000000000000000000000070 /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = RepoRadar;
\t\t\tproductName = RepoRadar;
\t\t\tproductReference = 000000000000000000000020 /* RepoRadar.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
\t\t000000000000000000000060 /* RepoRadarWidget */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 000000000000000000000066 /* Build configuration list for PBXNativeTarget "RepoRadarWidget" */;
\t\t\tbuildPhases = (
\t\t\t\t000000000000000000000061 /* Sources */,
\t\t\t\t000000000000000000000062 /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = RepoRadarWidget;
\t\t\tproductName = RepoRadarWidget;
\t\t\tproductReference = 000000000000000000000021 /* RepoRadarWidget.appex */;
\t\t\tproductType = "com.apple.product-type.app-extension";
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t000000000000000000000001 /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t000000000000000000000050 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t\t000000000000000000000060 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = 000000000000000000000005 /* Build configuration list for PBXProject "RepoRadar" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = 000000000000000000000002;
\t\t\tpackageReferences = (
\t\t\t\t000000000000000000000090 /* XCLocalSwiftPackageReference "" */,
\t\t\t);
\t\t\tproductRefGroup = 000000000000000000000012 /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t000000000000000000000050 /* RepoRadar */,
\t\t\t\t000000000000000000000060 /* RepoRadarWidget */,
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
\t\t000000000000000000000051 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t000000000000000000000040 /* RepoRadarApp.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t000000000000000000000061 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t000000000000000000000041 /* RepoRadarWidget.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t000000000000000000000070 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = 000000000000000000000060 /* RepoRadarWidget */;
\t\t\ttargetProxy = 000000000000000000000071 /* PBXContainerItemProxy */;
\t\t};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t000000000000000000000006 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 000000000000000000000036 /* Base.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t000000000000000000000007 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 000000000000000000000036 /* Base.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSWIFT_COMPILATION_MODE = "wholemodule";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t000000000000000000000057 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 000000000000000000000036 /* Base.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RepoRadar/RepoRadar.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RepoRadar/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = macosx;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t000000000000000000000058 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 000000000000000000000036 /* Base.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RepoRadar/RepoRadar.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RepoRadar/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = macosx;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t000000000000000000000067 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 000000000000000000000036 /* Base.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RepoRadarWidget/RepoRadarWidget.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RepoRadarWidget/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t\t"@executable_path/../../../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar.widget;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t000000000000000000000068 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 000000000000000000000036 /* Base.xcconfig */;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = RepoRadarWidget/RepoRadarWidget.entitlements;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RepoRadarWidget/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t\t"@executable_path/../../../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar.widget;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t000000000000000000000005 /* Build configuration list for PBXProject "RepoRadar" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t000000000000000000000006 /* Debug */,
\t\t\t\t000000000000000000000007 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t000000000000000000000056 /* Build configuration list for PBXNativeTarget "RepoRadar" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t000000000000000000000057 /* Debug */,
\t\t\t\t000000000000000000000058 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t000000000000000000000066 /* Build configuration list for PBXNativeTarget "RepoRadarWidget" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t000000000000000000000067 /* Debug */,
\t\t\t\t000000000000000000000068 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t000000000000000000000090 /* XCLocalSwiftPackageReference "." */ = {
\t\t\tisa = XCLocalSwiftPackageReference;
\t\t\trelativePath = ".";
\t\t};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t000000000000000000000091 /* RepoRadarCore */ = {
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = 000000000000000000000090 /* XCLocalSwiftPackageReference "." */;
\t\t\tproductName = RepoRadarCore;
\t\t};
/* End XCSwiftPackageProductDependency section */

\t};
\trootObject = 000000000000000000000001 /* Project object */;
}
"""
    proj_dir = "RepoRadar.xcodeproj"
    os.makedirs(proj_dir, exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
        f.write(content)
    print("Generated RepoRadar.xcodeproj/project.pbxproj")

def generate_shared_scheme():
    scheme_content = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "000000000000000000000050"
               BuildableName = "RepoRadar.app"
               BlueprintName = "RepoRadar"
               ReferencedContainer = "container:RepoRadar.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
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
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "000000000000000000000050"
            BuildableName = "RepoRadar.app"
            BlueprintName = "RepoRadar"
            ReferencedContainer = "container:RepoRadar.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "000000000000000000000050"
            BuildableName = "RepoRadar.app"
            BlueprintName = "RepoRadar"
            ReferencedContainer = "container:RepoRadar.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    scheme_dir = "RepoRadar.xcodeproj/xcshareddata/xcschemes"
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, "RepoRadar.xcscheme"), "w") as f:
        f.write(scheme_content)
    print("Generated RepoRadar.xcodeproj/xcshareddata/xcschemes/RepoRadar.xcscheme")

if __name__ == "__main__":
    generate_pbxproj()
    generate_shared_scheme()
