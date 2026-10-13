@echo off
rem Build every Sci-Fi HUD program (Release mode).
set LAZBUILD=C:\lazarus\lazbuild.exe
cd /d %~dp0
set FAILED=0
echo === OpticScanner
%LAZBUILD% --bm=Release OpticScanner\OpticScanner.lpi >OpticScanner\build.log 2>&1 || (echo FAILED: see OpticScanner\build.log & set FAILED=1)
echo === TargetLock
%LAZBUILD% --bm=Release TargetLock\TargetLock.lpi >TargetLock\build.log 2>&1 || (echo FAILED: see TargetLock\build.log & set FAILED=1)
echo === ShieldCore
%LAZBUILD% --bm=Release ShieldCore\ShieldCore.lpi >ShieldCore\build.log 2>&1 || (echo FAILED: see ShieldCore\build.log & set FAILED=1)
echo === HUDIconSet
%LAZBUILD% --bm=Release HUDIconSet\HUDIconSet.lpi >HUDIconSet\build.log 2>&1 || (echo FAILED: see HUDIconSet\build.log & set FAILED=1)
echo === DataFrames
%LAZBUILD% --bm=Release DataFrames\DataFrames.lpi >DataFrames\build.log 2>&1 || (echo FAILED: see DataFrames\build.log & set FAILED=1)
echo === RadarSweep
%LAZBUILD% --bm=Release RadarSweep\RadarSweep.lpi >RadarSweep\build.log 2>&1 || (echo FAILED: see RadarSweep\build.log & set FAILED=1)
echo === HexCore
%LAZBUILD% --bm=Release HexCore\HexCore.lpi >HexCore\build.log 2>&1 || (echo FAILED: see HexCore\build.log & set FAILED=1)
echo === TargetCrosshair
%LAZBUILD% --bm=Release TargetCrosshair\TargetCrosshair.lpi >TargetCrosshair\build.log 2>&1 || (echo FAILED: see TargetCrosshair\build.log & set FAILED=1)
echo === ChevronLoader
%LAZBUILD% --bm=Release ChevronLoader\ChevronLoader.lpi >ChevronLoader\build.log 2>&1 || (echo FAILED: see ChevronLoader\build.log & set FAILED=1)
echo === PillLoader
%LAZBUILD% --bm=Release PillLoader\PillLoader.lpi >PillLoader\build.log 2>&1 || (echo FAILED: see PillLoader\build.log & set FAILED=1)
echo === BlockLoader
%LAZBUILD% --bm=Release BlockLoader\BlockLoader.lpi >BlockLoader\build.log 2>&1 || (echo FAILED: see BlockLoader\build.log & set FAILED=1)
echo === SlantLoader
%LAZBUILD% --bm=Release SlantLoader\SlantLoader.lpi >SlantLoader\build.log 2>&1 || (echo FAILED: see SlantLoader\build.log & set FAILED=1)
if %FAILED%==1 (echo Some builds failed. & exit /b 1) else (echo All programs built.)
