"""Generate the Lazarus project files (.lpi/.lpr) for every HUD program.

Each program lives in its own folder:  <Program>/<Program>.lpi, .lpr, u<program>.pas
and uses the shared units in ../shared.  Run:  python tools/make_projects.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (program / folder name, widget unit, widget class, window title)
PROGRAMS = [
    ("OpticScanner",    "UOpticScanner",    "TOpticScannerWidget",    "Optic Scanner"),
    ("TargetLock",      "UTargetLock",      "TTargetLockWidget",      "Target Lock"),
    ("ShieldCore",      "UShieldCore",      "TShieldCoreWidget",      "Shield Core"),
    ("HUDIconSet",      "UHUDIconSet",      "THUDIconSetWidget",      "HUD Icon Set"),
    ("DataFrames",      "UDataFrames",      "TDataFramesWidget",      "Data Frames"),
    ("RadarSweep",      "URadarSweep",      "TRadarSweepWidget",      "Radar Sweep"),
    ("HexCore",         "UHexCore",         "THexCoreWidget",         "Hex Core"),
    ("TargetCrosshair", "UTargetCrosshair", "TTargetCrosshairWidget", "Target Crosshair"),
    ("ChevronLoader",   "UChevronLoader",   "TChevronLoaderWidget",   "Chevron Loader"),
    ("PillLoader",      "UPillLoader",      "TPillLoaderWidget",      "Pill Loader"),
    ("BlockLoader",     "UBlockLoader",     "TBlockLoaderWidget",     "Block Loader"),
    ("SlantLoader",     "USlantLoader",     "TSlantLoaderWidget",     "Slant Loader"),
]

# composite programs: they host the widgets above, so they need their folders
KITS = [
    ("SciFiHUDKit",     "USciFiHUDKit",     "TSciFiHUDKitWidget",     "Sci-Fi HUD Kit"),
    ("HUDSystemMonitor", "UHUDSystemMonitor", "THUDSystemMonitorWidget", "HUD System Monitor"),
    ("HUDDesigner",     "UHUDDesigner",     "THUDDesignWidget",       "HUD Designer"),
]

LPR = """program {prog};

{{ {title} - Sci-Fi HUD program.
  The UI itself is in {unitfile}; the window, the info panel and the
  render engine are shared (../shared/hudhost.pas, ../shared/hudcore.pas). }}

{{$mode objfpc}}{{$H+}}

uses
  {{$IFDEF UNIX}}
  cthreads,
  {{$ENDIF}}
  Interfaces, // this includes the LCL widgetset
  Forms, HUDCore, HUDHost, {unit};

{{$R *.res}}

begin
  Application.Scaled := True;
  RunHUDWidget({cls});
end.
"""

COMPILER = """      <Version Value="11"/>
      <Target>
        <Filename Value="{prog}"/>
      </Target>
      <SearchPaths>
        <IncludeFiles Value="$(ProjOutDir)"/>
        <OtherUnitFiles Value="{paths}"/>
        <UnitOutputDirectory Value="lib\\$(TargetCPU)-$(TargetOS)"/>
      </SearchPaths>
{extra}"""

RELEASE = """      <CodeGeneration>
        <SmartLinkUnit Value="True"/>
        <Optimizations>
          <OptimizationLevel Value="3"/>
        </Optimizations>
      </CodeGeneration>
      <Linking>
        <Debugging>
          <GenerateDebugInfo Value="False"/>
          <RunWithoutDebug Value="True"/>
        </Debugging>
        <LinkSmart Value="True"/>
        <Options>
          <Win32>
            <GraphicApplication Value="True"/>
          </Win32>
        </Options>
      </Linking>
"""

DEBUG = """      <Parsing>
        <SyntaxOptions>
          <IncludeAssertionCode Value="True"/>
        </SyntaxOptions>
      </Parsing>
      <CodeGeneration>
        <Checks>
          <IOChecks Value="True"/>
          <RangeChecks Value="True"/>
          <OverflowChecks Value="True"/>
          <StackChecks Value="True"/>
        </Checks>
        <VerifyObjMethodCallValidity Value="True"/>
      </CodeGeneration>
      <Linking>
        <Debugging>
          <DebugInfoType Value="dsDwarf3"/>
          <UseHeaptrc Value="True"/>
          <TrashVariables Value="True"/>
          <UseExternalDbgSyms Value="True"/>
        </Debugging>
        <Options>
          <Win32>
            <GraphicApplication Value="True"/>
          </Win32>
        </Options>
      </Linking>
"""

LPI = """<?xml version="1.0" encoding="UTF-8"?>
<CONFIG>
  <ProjectOptions>
    <Version Value="12"/>
    <General>
      <SessionStorage Value="InProjectDir"/>
      <Title Value="{title}"/>
      <Scaled Value="True"/>
      <ResourceType Value="res"/>
      <UseXPManifest Value="True"/>
      <XPManifest>
        <DpiAware Value="True"/>
      </XPManifest>
    </General>
    <BuildModes>
      <Item Name="Release" Default="True"/>
      <Item Name="Debug">
        <CompilerOptions>
{debug}        </CompilerOptions>
      </Item>
    </BuildModes>
    <PublishOptions>
      <Version Value="2"/>
      <UseFileFilters Value="True"/>
    </PublishOptions>
    <RunParams>
      <FormatVersion Value="2"/>
    </RunParams>
    <RequiredPackages>
      <Item>
        <PackageName Value="MultiThreadProcsLaz"/>
      </Item>
      <Item>
        <PackageName Value="BGRABitmapPack"/>
      </Item>
      <Item>
        <PackageName Value="LCL"/>
      </Item>
    </RequiredPackages>
    <Units>
      <Unit>
        <Filename Value="{prog}.lpr"/>
        <IsPartOfProject Value="True"/>
      </Unit>
      <Unit>
        <Filename Value="{unitlower}.pas"/>
        <IsPartOfProject Value="True"/>
        <UnitName Value="{unit}"/>
      </Unit>
      <Unit>
        <Filename Value="..\\shared\\hudcore.pas"/>
        <IsPartOfProject Value="True"/>
        <UnitName Value="HUDCore"/>
      </Unit>
      <Unit>
        <Filename Value="..\\shared\\hudhost.pas"/>
        <IsPartOfProject Value="True"/>
        <UnitName Value="HUDHost"/>
      </Unit>
    </Units>
  </ProjectOptions>
  <CompilerOptions>
{release}  </CompilerOptions>
</CONFIG>
"""


def indent(text, n):
    pad = " " * n
    return "".join(pad + line if line.strip() else line for line in text.splitlines(True))


def write_program(prog, unit, cls, title, paths, build):
    d = os.path.join(ROOT, prog)
    os.makedirs(d, exist_ok=True)
    unitlower = unit.lower()
    unitfile = f"{prog}\\{unitlower}.pas"
    with open(os.path.join(d, prog + ".lpr"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(LPR.format(prog=prog, unit=unit, cls=cls, title=title, unitfile=unitfile))
    release = COMPILER.format(prog=prog, extra=RELEASE, paths=paths)
    debug = indent(COMPILER.format(prog=prog, extra=DEBUG, paths=paths), 4)
    with open(os.path.join(d, prog + ".lpi"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(LPI.format(prog=prog, title=title, unit=unit, unitlower=unitlower,
                           release=release, debug=debug))
    build.append(f"echo === {prog}")
    build.append(f"%LAZBUILD% --bm=Release {prog}\\{prog}.lpi >{prog}\\build.log 2>&1 || "
                 f"(echo FAILED: see {prog}\\build.log & set FAILED=1)")


def main():
    build = ["@echo off", "rem Build every Sci-Fi HUD program (Release mode).",
             "set LAZBUILD=C:\\lazarus\\lazbuild.exe", "cd /d %~dp0", "set FAILED=0"]
    for prog, unit, cls, title in PROGRAMS:
        write_program(prog, unit, cls, title, "..\\shared", build)
    # kits are built last: they reuse the widget units of every program
    kit_paths = ";".join(["..\\shared"] + ["..\\" + p[0] for p in PROGRAMS])
    for prog, unit, cls, title in KITS:
        write_program(prog, unit, cls, title, kit_paths, build)
    build.append("if %FAILED%==1 (echo Some builds failed. & exit /b 1) else (echo All programs built.)")
    with open(os.path.join(ROOT, "build_all.cmd"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write("\n".join(build) + "\n")
    print("generated", len(PROGRAMS) + len(KITS), "projects")


if __name__ == "__main__":
    main()
