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
\t\t000000000000000000000040 /* HostApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000030 /* HostApp.swift */; };
\t\t000000000000000000000041 /* SpikeWidget.swift in Sources */ = {isa = PBXBuildFile; fileRef = 000000000000000000000032 /* SpikeWidget.swift */; };
\t\t000000000000000000000042 /* SpikeWidgetExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = 000000000000000000000021 /* SpikeWidgetExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t000000000000000000000071 /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 000000000000000000000001 /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = 000000000000000000000060;
\t\t\tremoteInfo = SpikeWidgetExtension;
\t\t};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t000000000000000000000054 /* Embed Foundation Extensions */ = {
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 13;
\t\t\tfiles = (
\t\t\t\t000000000000000000000042 /* SpikeWidgetExtension.appex in Embed Foundation Extensions */,
\t\t\t);
\t\t\tname = "Embed Foundation Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
\t\t000000000000000000000020 /* HostApp.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HostApp.app; sourceTree = BUILT_PRODUCTS_DIR; };
\t\t000000000000000000000021 /* SpikeWidgetExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = SpikeWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
\t\t000000000000000000000030 /* HostApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HostApp.swift; sourceTree = "<group>"; };
\t\t000000000000000000000031 /* HostApp.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = HostApp.entitlements; sourceTree = "<group>"; };
\t\t000000000000000000000032 /* SpikeWidget.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SpikeWidget.swift; sourceTree = "<group>"; };
\t\t000000000000000000000033 /* WidgetExtension.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = WidgetExtension.entitlements; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t000000000000000000000052 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t000000000000000000000062 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t000000000000000000000010 = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000012 /* HostApp */,
\t\t\t\t000000000000000000000013 /* WidgetExtension */,
\t\t\t\t000000000000000000000011 /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000011 /* Products */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000020 /* HostApp.app */,
\t\t\t\t000000000000000000000021 /* SpikeWidgetExtension.appex */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000012 /* HostApp */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000030 /* HostApp.swift */,
\t\t\t\t000000000000000000000031 /* HostApp.entitlements */,
\t\t\t);
\t\t\tpath = HostApp;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t000000000000000000000013 /* WidgetExtension */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t000000000000000000000032 /* SpikeWidget.swift */,
\t\t\t\t000000000000000000000033 /* WidgetExtension.entitlements */,
\t\t\t);
\t\t\tpath = WidgetExtension;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t000000000000000000000050 /* HostApp */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 000000000000000000000055 /* Build configuration list for PBXNativeTarget "HostApp" */;
\t\t\tbuildPhases = (
\t\t\t\t000000000000000000000051 /* Sources */,
\t\t\t\t000000000000000000000052 /* Frameworks */,
\t\t\t\t000000000000000000000053 /* Resources */,
\t\t\t\t000000000000000000000054 /* Embed Foundation Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t000000000000000000000070 /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = HostApp;
\t\t\tproductName = HostApp;
\t\t\tproductReference = 000000000000000000000020 /* HostApp.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
\t\t000000000000000000000060 /* SpikeWidgetExtension */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 000000000000000000000064 /* Build configuration list for PBXNativeTarget "SpikeWidgetExtension" */;
\t\t\tbuildPhases = (
\t\t\t\t000000000000000000000061 /* Sources */,
\t\t\t\t000000000000000000000062 /* Frameworks */,
\t\t\t\t000000000000000000000063 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = SpikeWidgetExtension;
\t\t\tproductName = SpikeWidgetExtension;
\t\t\tproductReference = 000000000000000000000021 /* SpikeWidgetExtension.appex */;
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
\t\t\t\t\t\tDevelopmentTeam = 7P5RMM8JP7;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t};
\t\t\t\t\t000000000000000000000060 = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tDevelopmentTeam = 7P5RMM8JP7;
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = 000000000000000000000002 /* Build configuration list for PBXProject "AppGroupWidgetSpike" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = 000000000000000000000010;
\t\t\tproductRefGroup = 000000000000000000000011 /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t000000000000000000000050 /* HostApp */,
\t\t\t\t000000000000000000000060 /* SpikeWidgetExtension */,
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t000000000000000000000053 /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t000000000000000000000063 /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t000000000000000000000051 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t000000000000000000000040 /* HostApp.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t000000000000000000000061 /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t000000000000000000000041 /* SpikeWidget.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t000000000000000000000070 /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = 000000000000000000000060 /* SpikeWidgetExtension */;
\t\t\ttargetProxy = 000000000000000000000071 /* PBXContainerItemProxy */;
\t\t};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t000000000000000000000003 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t000000000000000000000004 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = "wholemodule";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t000000000000000000000056 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = HostApp/HostApp.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 7P5RMM8JP7;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = HostApp;
\t\t\t\tINFOPLIST_KEY_LSUIElement = NO;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar.HostApp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t000000000000000000000057 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = HostApp/HostApp.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 7P5RMM8JP7;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = HostApp;
\t\t\t\tINFOPLIST_KEY_LSUIElement = NO;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar.HostApp;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t000000000000000000000065 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = WidgetExtension/WidgetExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 7P5RMM8JP7;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = WidgetExtension/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = SpikeWidget;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t\t"@executable_path/../../../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar.HostApp.SpikeWidgetExtension;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t000000000000000000000066 /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCODE_SIGN_ENTITLEMENTS = WidgetExtension/WidgetExtension.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = 7P5RMM8JP7;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = WidgetExtension/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = SpikeWidget;
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t\t"@executable_path/../../../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chriswander.reporadar.HostApp.SpikeWidgetExtension;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t000000000000000000000002 /* Build configuration list for PBXProject "AppGroupWidgetSpike" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t000000000000000000000003 /* Debug */,
\t\t\t\t000000000000000000000004 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t000000000000000000000055 /* Build configuration list for PBXNativeTarget "HostApp" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t000000000000000000000056 /* Debug */,
\t\t\t\t000000000000000000000057 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t000000000000000000000064 /* Build configuration list for PBXNativeTarget "SpikeWidgetExtension" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t000000000000000000000065 /* Debug */,
\t\t\t\t000000000000000000000066 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */
\t};
\trootObject = 000000000000000000000001 /* Project object */;
}
"""
    proj_dir = "Spikes/AppGroupWidget/AppGroupWidgetSpike.xcodeproj"
    os.makedirs(proj_dir, exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
        f.write(content)
    print("Generated project.pbxproj at", proj_dir)

if __name__ == "__main__":
    generate_pbxproj()
