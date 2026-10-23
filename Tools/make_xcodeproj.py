#!/usr/bin/env python3
"""Generates LiveAirspace.xcodeproj (tvOS app + macOS screen saver, both using the local Swift package)."""
import hashlib, os

def uid(name): return hashlib.md5(name.encode()).hexdigest()[:24].upper()

objs = []
def add(i, body): objs.append((i, body))

# ids
pkg, prodKit, prodUI = uid("pkg"), uid("prodKit"), uid("prodUI")
prodKit2, prodUI2 = uid("prodKit2"), uid("prodUI2")
tvSrc, saverSrc = uid("tvSrc"), uid("saverSrc")
xcfgRef, plistRef = uid("xcfgRef"), uid("plistRef")
tvRef, saverRef = uid("tvRef"), uid("saverRef")
tvApp, saverBundle = uid("tvApp"), uid("saverBundle")
bfTvSrc, bfSaverSrc = uid("bfTvSrc"), uid("bfSaverSrc")
bfTvKit, bfTvUI, bfSaverKit, bfSaverUI = uid("bfTvKit"), uid("bfTvUI"), uid("bfSaverKit"), uid("bfSaverUI")
grpMain, grpTV, grpSaver, grpProducts = uid("grpMain"), uid("grpTV"), uid("grpSaver"), uid("grpProducts")
proj = uid("proj")
tvT, saverT = uid("tvT"), uid("saverT")
tvSrcPh, tvFwPh, tvResPh = uid("tvSrcPh"), uid("tvFwPh"), uid("tvResPh")
svSrcPh, svFwPh, svResPh = uid("svSrcPh"), uid("svFwPh"), uid("svResPh")
cfgProj, cfgTV, cfgSaver = uid("cfgProj"), uid("cfgTV"), uid("cfgSaver")
dProj, rProj, dTV, rTV, dSv, rSv = [uid(x) for x in ("dProj","rProj","dTV","rTV","dSv","rSv")]
# Top Shelf extension (embedded in the tvOS app)
extT, extRef, extSrc, bfExtSrc = uid("extT"), uid("extRef"), uid("extSrc"), uid("bfExtSrc")
extSrcPh, extFwPh, extResPh, cfgExt, dExt, rExt = [uid(x) for x in ("extSrcPh","extFwPh","extResPh","cfgExt","dExt","rExt")]
prodKit3, bfExtKit, grpExt = uid("prodKit3"), uid("bfExtKit"), uid("grpExt")
copyPh, bfCopyExt, depExt, proxyExt = uid("copyPh"), uid("bfCopyExt"), uid("depExt"), uid("proxyExt")

def settings(d):
    return "{\n" + "".join(f"\t\t\t\t{k} = {v};\n" for k, v in d.items()) + "\t\t\t}"

common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "SWIFT_VERSION": "5.0", "GCC_NO_COMMON_BLOCKS": "YES", "SDKROOT": "auto",
}
files = f"""
/* Begin PBXBuildFile section */
\t\t{bfTvSrc} /* LiveAirspaceTVApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {tvSrc}; }};
\t\t{bfSaverSrc} /* LiveAirspaceSaverView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {saverSrc}; }};
\t\t{bfTvKit} /* LiveAirspaceKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {prodKit}; }};
\t\t{bfTvUI} /* LiveAirspaceUI in Frameworks */ = {{isa = PBXBuildFile; productRef = {prodUI}; }};
\t\t{bfSaverKit} /* LiveAirspaceKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {prodKit2}; }};
\t\t{bfSaverUI} /* LiveAirspaceUI in Frameworks */ = {{isa = PBXBuildFile; productRef = {prodUI2}; }};
\t\t{bfExtSrc} /* ContentProvider.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {extSrc}; }};
\t\t{bfExtKit} /* LiveAirspaceKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {prodKit3}; }};
\t\t{bfCopyExt} /* Live Airspace Top Shelf.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {extRef}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{tvSrc} /* LiveAirspaceTVApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LiveAirspaceTVApp.swift; sourceTree = "<group>"; }};
\t\t{saverSrc} /* LiveAirspaceSaverView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LiveAirspaceSaverView.swift; sourceTree = "<group>"; }};
\t\t{tvRef} /* Live Airspace.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Live Airspace.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{saverRef} /* Live Airspace.saver */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = "Live Airspace.saver"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{xcfgRef} /* LiveAirspace.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/LiveAirspace.xcconfig; sourceTree = "<group>"; }};
\t\t{plistRef} /* Info-extra.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Config/Info-extra.plist; sourceTree = "<group>"; }};
\t\t{extSrc} /* ContentProvider.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentProvider.swift; sourceTree = "<group>"; }};
\t\t{extRef} /* Live Airspace Top Shelf.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = "Live Airspace Top Shelf.appex"; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXContainerItemProxy section */
\t\t{proxyExt} /* PBXContainerItemProxy */ = {{isa = PBXContainerItemProxy; containerPortal = {proj} /* Project object */; proxyType = 1; remoteGlobalIDString = {extT}; remoteInfo = "Live Airspace Top Shelf"; }};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t{copyPh} /* Embed Foundation Extensions */ = {{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({bfCopyExt}, ); name = "Embed Foundation Extensions"; runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{tvFwPh} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({bfTvKit}, {bfTvUI}, ); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{svFwPh} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({bfSaverKit}, {bfSaverUI}, ); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{extFwPh} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({bfExtKit}, ); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{grpMain} = {{isa = PBXGroup; children = ({grpTV}, {grpExt}, {grpSaver}, {xcfgRef}, {plistRef}, {grpProducts}, ); sourceTree = "<group>"; }};
\t\t{grpTV} /* LiveAirspaceTV */ = {{isa = PBXGroup; children = ({tvSrc}, ); path = LiveAirspaceTV; sourceTree = "<group>"; }};
\t\t{grpSaver} /* LiveAirspaceSaver */ = {{isa = PBXGroup; children = ({saverSrc}, ); path = LiveAirspaceSaver; sourceTree = "<group>"; }};
\t\t{grpExt} /* LiveAirspaceTopShelf */ = {{isa = PBXGroup; children = ({extSrc}, ); path = LiveAirspaceTopShelf; sourceTree = "<group>"; }};
\t\t{grpProducts} /* Products */ = {{isa = PBXGroup; children = ({tvRef}, {extRef}, {saverRef}, ); name = Products; sourceTree = "<group>"; }};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{tvT} /* Live Airspace (tvOS) */ = {{
\t\t\tisa = PBXNativeTarget; buildConfigurationList = {cfgTV}; buildPhases = ({tvSrcPh}, {tvFwPh}, {tvResPh}, {copyPh}, );
\t\t\tbuildRules = (); dependencies = ({depExt}, ); name = "Live Airspace (tvOS)"; packageProductDependencies = ({prodKit}, {prodUI}, );
\t\t\tproductName = LiveAirspaceTV; productReference = {tvRef}; productType = "com.apple.product-type.application";
\t\t}};
\t\t{saverT} /* Live Airspace (Screen Saver) */ = {{
\t\t\tisa = PBXNativeTarget; buildConfigurationList = {cfgSaver}; buildPhases = ({svSrcPh}, {svFwPh}, {svResPh}, );
\t\t\tbuildRules = (); dependencies = (); name = "Live Airspace (Screen Saver)"; packageProductDependencies = ({prodKit2}, {prodUI2}, );
\t\t\tproductName = LiveAirspaceSaver; productReference = {saverRef}; productType = "com.apple.product-type.bundle";
\t\t}};
\t\t{extT} /* Live Airspace Top Shelf */ = {{
\t\t\tisa = PBXNativeTarget; buildConfigurationList = {cfgExt}; buildPhases = ({extSrcPh}, {extFwPh}, {extResPh}, );
\t\t\tbuildRules = (); dependencies = (); name = "Live Airspace Top Shelf"; packageProductDependencies = ({prodKit3}, );
\t\t\tproductName = LiveAirspaceTopShelf; productReference = {extRef}; productType = "com.apple.product-type.tv-app-extension";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{proj} /* Project object */ = {{
\t\t\tisa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700;}};
\t\t\tbuildConfigurationList = {cfgProj}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base, ); mainGroup = {grpMain}; packageReferences = ({pkg}, ); productRefGroup = {grpProducts};
\t\t\tprojectDirPath = ""; projectRoot = ""; targets = ({tvT}, {extT}, {saverT}, );
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{tvResPh} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{svResPh} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{extResPh} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{tvSrcPh} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({bfTvSrc}, ); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{svSrcPh} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({bfSaverSrc}, ); runOnlyForDeploymentPostprocessing = 0; }};
\t\t{extSrcPh} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({bfExtSrc}, ); runOnlyForDeploymentPostprocessing = 0; }};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{depExt} /* PBXTargetDependency */ = {{isa = PBXTargetDependency; target = {extT}; targetProxy = {proxyExt}; }};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t{dProj} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {settings({**common, "ONLY_ACTIVE_ARCH": "YES", "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"', "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE"})}; name = Debug; }};
\t\t{rProj} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {settings({**common, "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"})}; name = Release; }};
"""
tv = {"SDKROOT": "appletvos", "SUPPORTED_PLATFORMS": '"appletvos appletvsimulator"', "TARGETED_DEVICE_FAMILY": "3",
      "TVOS_DEPLOYMENT_TARGET": "17.0", "PRODUCT_BUNDLE_IDENTIFIER": "com.bureau.liveairspace",
      "PRODUCT_NAME": '"Live Airspace"', "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic",
      "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
      "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": '"Centres the radar on the aircraft flying near your Apple TV."', "SWIFT_EMIT_LOC_STRINGS": "YES",
      "CODE_SIGN_ENTITLEMENTS": "Config/App.entitlements"}
ext = {"SDKROOT": "appletvos", "SUPPORTED_PLATFORMS": '"appletvos appletvsimulator"', "TARGETED_DEVICE_FAMILY": "3",
       "TVOS_DEPLOYMENT_TARGET": "17.0", "PRODUCT_BUNDLE_IDENTIFIER": "com.bureau.liveairspace.topshelf",
       "PRODUCT_NAME": '"Live Airspace Top Shelf"', "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Config/TopShelf-Info.plist",
       "CODE_SIGN_STYLE": "Automatic", "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
       "CODE_SIGN_ENTITLEMENTS": "Config/TopShelf.entitlements", "SKIP_INSTALL": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
       "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"'}
saver = {"SDKROOT": "macosx", "SUPPORTED_PLATFORMS": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0",
         "PRODUCT_BUNDLE_IDENTIFIER": "com.bureau.liveairspace.saver", "PRODUCT_NAME": '"Live Airspace"',
         "WRAPPER_EXTENSION": "saver", "MACH_O_TYPE": "mh_bundle", "GENERATE_INFOPLIST_FILE": "YES",
         "INFOPLIST_KEY_NSPrincipalClass": "LiveAirspaceSaverView", "INFOPLIST_KEY_CFBundleDisplayName": '"Live Airspace"',
         "CODE_SIGN_STYLE": "Automatic", "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
         "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @loader_path/../Frameworks"', "SKIP_INSTALL": "YES"}
for (d, r, cfg_name, s) in ((dTV, rTV, "tv", tv), (dSv, rSv, "sv", saver)):
    s = {**s, "INFOPLIST_FILE": "Config/Info-extra.plist"}
    files += f"\t\t{d} /* Debug */ = {{isa = XCBuildConfiguration; baseConfigurationReference = {xcfgRef}; buildSettings = {settings(s)}; name = Debug; }};\n"
    files += f"\t\t{r} /* Release */ = {{isa = XCBuildConfiguration; baseConfigurationReference = {xcfgRef}; buildSettings = {settings(s)}; name = Release; }};\n"
files += f"\t\t{dExt} /* Debug */ = {{isa = XCBuildConfiguration; baseConfigurationReference = {xcfgRef}; buildSettings = {settings(ext)}; name = Debug; }};\n"
files += f"\t\t{rExt} /* Release */ = {{isa = XCBuildConfiguration; baseConfigurationReference = {xcfgRef}; buildSettings = {settings(ext)}; name = Release; }};\n"
files += f"""/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{cfgProj} = {{isa = XCConfigurationList; buildConfigurations = ({dProj}, {rProj}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
\t\t{cfgTV} = {{isa = XCConfigurationList; buildConfigurations = ({dTV}, {rTV}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
\t\t{cfgExt} = {{isa = XCConfigurationList; buildConfigurations = ({dExt}, {rExt}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
\t\t{cfgSaver} = {{isa = XCConfigurationList; buildConfigurations = ({dSv}, {rSv}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
\t\t{pkg} /* XCLocalSwiftPackageReference "." */ = {{isa = XCLocalSwiftPackageReference; relativePath = .; }};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{prodKit} /* LiveAirspaceKit */ = {{isa = XCSwiftPackageProductDependency; productName = LiveAirspaceKit; }};
\t\t{prodUI} /* LiveAirspaceUI */ = {{isa = XCSwiftPackageProductDependency; productName = LiveAirspaceUI; }};
\t\t{prodKit2} /* LiveAirspaceKit */ = {{isa = XCSwiftPackageProductDependency; productName = LiveAirspaceKit; }};
\t\t{prodUI2} /* LiveAirspaceUI */ = {{isa = XCSwiftPackageProductDependency; productName = LiveAirspaceUI; }};
\t\t{prodKit3} /* LiveAirspaceKit */ = {{isa = XCSwiftPackageProductDependency; productName = LiveAirspaceKit; }};
/* End XCSwiftPackageProductDependency section */
"""
out = f"// !$*UTF8*$!\n{{\n\tarchiveVersion = 1;\n\tclasses = {{\n\t}};\n\tobjectVersion = 77;\n\tobjects = {{\n{files}\t}};\n\trootObject = {proj} /* Project object */;\n}}\n"
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
d = os.path.join(root, "LiveAirspace.xcodeproj")
os.makedirs(d, exist_ok=True)
open(os.path.join(d, "project.pbxproj"), "w").write(out)
print("wrote", d)

# Shared schemes, so Xcode lists the app targets (and their devices) without having to auto-create them.
def scheme(target_id, product, blueprint, ext):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" BuildableName = "{product}.{ext}" BlueprintName = "{blueprint}" ReferencedContainer = "container:LiveAirspace.xcodeproj"></BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES"></TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      {"<BuildableProductRunnable runnableDebuggingMode = " + chr(34) + "0" + chr(34) + "><BuildableReference BuildableIdentifier = " + chr(34) + "primary" + chr(34) + " BlueprintIdentifier = " + chr(34) + target_id + chr(34) + " BuildableName = " + chr(34) + product + "." + ext + chr(34) + " BlueprintName = " + chr(34) + blueprint + chr(34) + " ReferencedContainer = " + chr(34) + "container:LiveAirspace.xcodeproj" + chr(34) + "></BuildableReference></BuildableProductRunnable>" if ext == "app" else ""}
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
sd = os.path.join(d, "xcshareddata", "xcschemes")
os.makedirs(sd, exist_ok=True)
open(os.path.join(sd, "Live Airspace (tvOS).xcscheme"), "w").write(scheme(tvT, "Live Airspace", "Live Airspace (tvOS)", "app"))
open(os.path.join(sd, "Live Airspace (Screen Saver).xcscheme"), "w").write(scheme(saverT, "Live Airspace", "Live Airspace (Screen Saver)", "saver"))
