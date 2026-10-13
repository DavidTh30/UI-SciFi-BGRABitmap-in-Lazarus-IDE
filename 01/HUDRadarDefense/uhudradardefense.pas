unit UHUDRadarDefense;

{ HUD Radar Defense - a mouse-aim arcade game built from the Sci-Fi HUD kit.

  Drones fly in from the radar edge towards the core. Aim with the mouse
  (the crosshair locks when it is over a drone) and left-click to fire.
  Every shot costs energy, which regenerates. A drone that reaches the core
  damages the shield; when the shield is gone the game is over.
  Consecutive hits build a combo that multiplies the score.

    Drone  1 hit, normal speed            100 pts
    Dart   1 hit, fast (wave 2+)          150 pts
    Heavy  3 hits, slow, big (wave 3+)    300 pts, 2x shield damage

  The side HUD is made of kit widgets driven by the game:
    Chevron loader = energy, Pill loader = shield, Block loader = wave
    progress, Slant loader = combo, HUD Icon Set blinks when the shield is
    low, TGameReadout = score / best / wave / kills / accuracy.
  Space pauses (host key). The best score is kept in highscore.txt. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, BGRABitmap, BGRABitmapTypes, HUDCore, HUDHost,
  UHUDIconSet, UChevronLoader, UPillLoader, UBlockLoader, USlantLoader;

type
  TEnemyKind = (ekDrone, ekDart, ekHeavy);

  TEnemy = record
    Kind: TEnemyKind;
    Angle, Dist: single;      // polar position around the core (deg, units)
    Speed, Spin: single;      // units/s inwards, deg/s sideways
    HP: integer;
    HitFlash: single;         // s left of the hit flash
  end;

  TBlast = record
    X, Y, Age, Size: single;
  end;

  TGameStage = (gsReady, gsPlaying, gsOver);

  { TGameState - rules and simulation, no drawing }

  TGameState = class
  public
    Stage: TGameStage;
    Enemies: array of TEnemy;
    Blasts: array of TBlast;
    AimX, AimY: single;       // crosshair in arena units
    LockIdx: integer;         // enemy under the crosshair, -1 = none
    Score, Best, Wave, Kills, WaveKills, Shots, Hits, Combo, MaxCombo: integer;
    Shield, Energy: single;   // 0..100
    SpawnTimer, TracerAge, CoreFlash, WaveBanner: single;
    TracerX, TracerY: single;
    Difficulty, ShotCost: single;
    constructor Create;
    procedure Reset;
    procedure Update(dt: single);
    procedure Fire;
    function KillsForWave: integer;
    function EnemyXY(const E: TEnemy; out ex, ey: single): single;  // returns radius
    procedure LoadBest;
    procedure SaveBest;
  end;

  { TRadarArenaWidget - the play field }

  TRadarArenaWidget = class(THUDWidget)
  private
    FGame: TGameState;
    FSweep: single;
    procedure DrawEnemy(const E: TEnemy);
    procedure DrawCrosshair;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { TGameReadout - score panel }

  TGameReadout = class(THUDWidget)
  private
    FGame: TGameState;
  protected
    procedure DrawStatic; override;
    procedure DrawDynamic; override;
    procedure DefineDirty; override;
  public
    constructor Create; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
  end;

  { THUDRadarDefenseWidget - the game screen }

  THUDRadarDefenseWidget = class(THUDComposite)
  private
    FGame: TGameState;
    FArena: TRadarArenaWidget;
    FEnergy: TChevronLoaderWidget;
    FShieldBar: TPillLoaderWidget;
    FWaveBar: TBlockLoaderWidget;
    FComboBar: TSlantLoaderWidget;
    FIcons: THUDIconSetWidget;
    FLastT: single;
    FDifficulty, FShotCost: single;
    FAutopilot: single;
    FBotCooldown: single;
    procedure Autopilot(dt: single);
    procedure Drive(W: THUDWidget; const AParam: string; v: double);
  protected
    procedure DrawDynamic; override;
  public
    constructor Create; override;
    destructor Destroy; override;
    class function UIName: string; override;
    class function UIDescription: string; override;
    class function UnitFile: string; override;
    procedure DescribeAnatomy(L: TStrings); override;
    procedure DescribeLive(L: TStrings); override;
    procedure MouseAim(px, py: integer);
    procedure MouseClick;
    property Game: TGameState read FGame;
  end;

implementation

const
  ArenaSize = 700;
  ACX = 350;           // arena centre
  ACY = 350;
  ArenaR = 320;        // radar radius = spawn distance
  CoreR = 42;          // a drone touching this radius hits the core
  EnemyR: array[TEnemyKind] of single = (10, 8, 14);
  EnemyHP: array[TEnemyKind] of integer = (1, 1, 3);
  EnemyPts: array[TEnemyKind] of integer = (100, 150, 300);
  EnemyDmg: array[TEnemyKind] of single = (10, 10, 20);

{ ---------- TGameState ---------- }

constructor TGameState.Create;
begin
  inherited Create;
  Difficulty := 1;
  ShotCost := 8;
  LoadBest;
  Reset;
  Stage := gsReady;
end;

procedure TGameState.Reset;
begin
  Enemies := nil;
  Blasts := nil;
  Score := 0; Wave := 1; Kills := 0; WaveKills := 0; Shots := 0; Hits := 0;
  Combo := 0; MaxCombo := 0;
  Shield := 100; Energy := 100;
  SpawnTimer := 1; TracerAge := 1; CoreFlash := 0; WaveBanner := 2;
  LockIdx := -1;
  Stage := gsPlaying;
end;

function TGameState.KillsForWave: integer;
begin
  Result := 8 + Wave * 4;
end;

function TGameState.EnemyXY(const E: TEnemy; out ex, ey: single): single;
begin
  ex := ACX + E.Dist * Cos(DegToRad(E.Angle));
  ey := ACY + E.Dist * Sin(DegToRad(E.Angle));
  Result := EnemyR[E.Kind];
end;

procedure TGameState.LoadBest;
var
  L: TStringList;
  fn: string;
begin
  fn := ExtractFilePath(Application.ExeName) + 'highscore.txt';
  Best := 0;
  if not FileExists(fn) then Exit;
  L := TStringList.Create;
  try
    L.LoadFromFile(fn);
    if L.Count > 0 then Best := StrToIntDef(Trim(L[0]), 0);
  finally
    L.Free;
  end;
end;

procedure TGameState.SaveBest;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Add(IntToStr(Best));
    try
      L.SaveToFile(ExtractFilePath(Application.ExeName) + 'highscore.txt');
    except
      // read-only folder: the best score just is not kept
    end;
  finally
    L.Free;
  end;
end;

procedure AddBlast(G: TGameState; x, y, size: single);
var
  n: integer;
begin
  n := Length(G.Blasts);
  SetLength(G.Blasts, n + 1);
  G.Blasts[n].X := x;
  G.Blasts[n].Y := y;
  G.Blasts[n].Age := 0;
  G.Blasts[n].Size := size;
end;

procedure TGameState.Update(dt: single);
var
  i, n: integer;
  ex, ey, r, best_d, d, interval: single;
  E: TEnemy;
  kind: TEnemyKind;
begin
  // effects age even when not playing
  for i := High(Blasts) downto 0 do
  begin
    Blasts[i].Age += dt;
    if Blasts[i].Age > 0.6 then
    begin
      Blasts[i] := Blasts[High(Blasts)];
      SetLength(Blasts, Length(Blasts) - 1);
    end;
  end;
  TracerAge += dt;
  CoreFlash := Max(0, CoreFlash - dt);
  WaveBanner := Max(0, WaveBanner - dt);
  if Stage <> gsPlaying then Exit;

  Energy := Min(100, Energy + 12 * dt);

  // spawning: faster with every wave
  SpawnTimer -= dt;
  interval := Max(0.28, (1.5 - Wave * 0.1)) / Difficulty;
  if SpawnTimer <= 0 then
  begin
    SpawnTimer := interval * (0.6 + Random * 0.8);
    kind := ekDrone;
    if (Wave >= 2) and (Random < 0.3) then kind := ekDart;
    if (Wave >= 3) and (Random < 0.18) then kind := ekHeavy;
    E.Kind := kind;
    E.Angle := Random * 360;
    E.Dist := ArenaR;
    E.Speed := (34 + Wave * 6) * Difficulty * (0.85 + Random * 0.3);
    case kind of
      ekDart: E.Speed := E.Speed * 1.7;
      ekHeavy: E.Speed := E.Speed * 0.6;
    end;
    E.Spin := (Random - 0.5) * 30;
    E.HP := EnemyHP[kind];
    E.HitFlash := 0;
    n := Length(Enemies);
    SetLength(Enemies, n + 1);
    Enemies[n] := E;
  end;

  // movement and core hits
  for i := High(Enemies) downto 0 do
  begin
    Enemies[i].Dist -= Enemies[i].Speed * dt;
    Enemies[i].Angle += Enemies[i].Spin * dt;
    Enemies[i].HitFlash := Max(0, Enemies[i].HitFlash - dt);
    if Enemies[i].Dist <= CoreR + EnemyR[Enemies[i].Kind] then
    begin
      Shield -= EnemyDmg[Enemies[i].Kind];
      Combo := 0;
      CoreFlash := 0.35;
      EnemyXY(Enemies[i], ex, ey);
      AddBlast(Self, ex, ey, 26);
      Enemies[i] := Enemies[High(Enemies)];
      SetLength(Enemies, Length(Enemies) - 1);
    end;
  end;

  // lock: the enemy closest to the crosshair, within its radius + 12
  LockIdx := -1;
  best_d := MaxSingle;
  for i := 0 to High(Enemies) do
  begin
    r := EnemyXY(Enemies[i], ex, ey);
    d := Hypot(ex - AimX, ey - AimY);
    if (d <= r + 12) and (d < best_d) then
    begin
      best_d := d;
      LockIdx := i;
    end;
  end;

  if Shield <= 0 then
  begin
    Shield := 0;
    Stage := gsOver;
    AddBlast(Self, ACX, ACY, 80);
    if Score > Best then
    begin
      Best := Score;
      SaveBest;
    end;
  end;
end;

procedure TGameState.Fire;
var
  ex, ey: single;
  E: TEnemy;
begin
  case Stage of
    gsReady, gsOver:
      begin
        Reset;
        Exit;
      end;
  end;
  if Energy < ShotCost then Exit;   // dry click
  Energy -= ShotCost;
  Inc(Shots);
  TracerAge := 0;
  TracerX := AimX;
  TracerY := AimY;
  if LockIdx < 0 then
  begin
    Combo := 0;
    AddBlast(Self, AimX, AimY, 6);
    Exit;
  end;
  Inc(Hits);
  E := Enemies[LockIdx];
  Dec(E.HP);
  E.HitFlash := 0.12;
  EnemyXY(E, ex, ey);
  if E.HP > 0 then
  begin
    Enemies[LockIdx] := E;
    AddBlast(Self, ex, ey, 8);
    Exit;
  end;
  // destroyed
  Inc(Combo);
  MaxCombo := Max(MaxCombo, Combo);
  Score += Round(EnemyPts[E.Kind] * (1 + Min(Combo, 20) * 0.1));
  Inc(Kills);
  Inc(WaveKills);
  AddBlast(Self, ex, ey, 18 + EnemyR[E.Kind]);
  Enemies[LockIdx] := Enemies[High(Enemies)];
  SetLength(Enemies, Length(Enemies) - 1);
  LockIdx := -1;
  if WaveKills >= KillsForWave then
  begin
    Inc(Wave);
    WaveKills := 0;
    Shield := Min(100, Shield + 15);   // wave bonus
    WaveBanner := 2;
  end;
end;

{ ---------- TRadarArenaWidget ---------- }

constructor TRadarArenaWidget.Create;
begin
  inherited Create;
  SetView(ArenaSize, ArenaSize);
end;

class function TRadarArenaWidget.UIName: string;
begin
  Result := 'Radar Arena';
end;

class function TRadarArenaWidget.UIDescription: string;
begin
  Result := 'Play field: radar scope with range rings, sweep, drones, shots, explosions, the core ' +
    'and the mouse crosshair.';
end;

class function TRadarArenaWidget.UnitFile: string;
begin
  Result := 'HUDRadarDefense\uhudradardefense.pas';
end;

procedure TRadarArenaWidget.DrawStatic;
var
  i: integer;
begin
  Disc(ACX, ACY, ArenaR + 6, Navy(120));
  Ring(ACX, ACY, ArenaR + 6, 2, White(230));
  Ticks(ACX, ACY, ArenaR + 9, ArenaR + 15, 120, 0, 360, 0.8, Ice(150));
  Ticks(ACX, ACY, ArenaR + 8, ArenaR + 20, 12, 0, 360, 2, White(220));
  Arc(ACX, ACY, ArenaR + 24, 200, 250, 3, White);
  Arc(ACX, ACY, ArenaR + 24, 20, 70, 3, White);
  for i := 1 to 3 do
    Ring(ACX, ACY, ArenaR * i / 4, 0.8, Ice(110));
  Line(ACX - ArenaR, ACY, ACX + ArenaR, ACY, 0.6, Ice(80));
  Line(ACX, ACY - ArenaR, ACX, ACY + ArenaR, 0.6, Ice(80));
  for i := 0 to 7 do
    Txt(ACX + (ArenaR - 18) * Cos(DegToRad(i * 45 - 90)), ACY + (ArenaR - 18) * Sin(DegToRad(i * 45 - 90)),
      Format('%.3d', [i * 45]), 6, Ice(150), taCenter);
  // core
  Disc(ACX, ACY, CoreR, Navy(230));
  Ring(ACX, ACY, CoreR, 2, White(230));
  Ring(ACX, ACY, CoreR - 10, 1, Ice(140));
  Txt(ACX, ACY + 1, 'CORE', 7, Ice(200), taCenter);
end;

procedure TRadarArenaWidget.DrawEnemy(const E: TEnemy);
var
  ex, ey, r, a, ca, sa: single;
  i: integer;
  c: TBGRAPixel;
begin
  r := FGame.EnemyXY(E, ex, ey);
  a := DegToRad(E.Angle + 180);   // facing the core
  ca := Cos(a); sa := Sin(a);
  if E.HitFlash > 0 then c := White else c := White(235);
  case E.Kind of
    ekDrone:
      begin
        FillPoly([ex + ca * r, ey + sa * r,
                  ex - ca * r * 0.7 - sa * r * 0.8, ey - sa * r * 0.7 + ca * r * 0.8,
                  ex - ca * r * 0.3, ey - sa * r * 0.3,
                  ex - ca * r * 0.7 + sa * r * 0.8, ey - sa * r * 0.7 - ca * r * 0.8], c);
      end;
    ekDart:
      begin
        PolyLine([ex - ca * r - sa * r * 0.7, ey - sa * r + ca * r * 0.7,
                  ex + ca * r, ey + sa * r,
                  ex - ca * r + sa * r * 0.7, ey - sa * r - ca * r * 0.7], 2, Ice);
        Line(ex - ca * r * 2.2, ey - sa * r * 2.2, ex - ca * r, ey - sa * r, 1, Ice(150));
      end;
    ekHeavy:
      begin
        Disc(ex, ey, r, Steel(200));
        Ring(ex, ey, r, 2, c);
        for i := 0 to E.HP - 1 do
          Disc(ex + (i - 1) * 5, ey, 1.6, White);
      end;
  end;
end;

procedure TRadarArenaWidget.DrawCrosshair;
var
  ax, ay, ex, ey, r, a: single;
  c: TBGRAPixel;
  i: integer;
begin
  ax := FGame.AimX;
  ay := FGame.AimY;
  if FGame.Energy >= FGame.ShotCost then c := White else c := Ice(140);
  Ring(ax, ay, 16, 1.5, c);
  Line(ax - 26, ay, ax - 8, ay, 1.2, c);
  Line(ax + 8, ay, ax + 26, ay, 1.2, c);
  Line(ax, ay - 26, ax, ay - 8, 1.2, c);
  Line(ax, ay + 8, ax, ay + 26, 1.2, c);
  Disc(ax, ay, 1.5, c);
  if (FGame.LockIdx >= 0) and (FGame.LockIdx <= High(FGame.Enemies)) then
  begin
    // rotating lock brackets around the target
    r := FGame.EnemyXY(FGame.Enemies[FGame.LockIdx], ex, ey) + 8;
    a := T * 180;
    for i := 0 to 3 do
      Arc(ex, ey, r, a + i * 90, a + i * 90 + 40, 2.5, White);
    TxtCached(ex, ey - r - 9, 'LOCK', 7, taCenter);
  end;
end;

procedure TRadarArenaWidget.DrawDynamic;
var
  i: integer;
  b: TBlast;
  age, sz: single;
begin
  // radar sweep
  FSweep := Phase(0, 60);
  for i := 0 to 9 do
    Pie(ACX, ACY, ArenaR, FSweep - (i + 1) * 4, FSweep - i * 4, Ice(Round(60 * (1 - i / 10))));
  Line(ACX, ACY, ACX + ArenaR * Cos(DegToRad(FSweep)), ACY + ArenaR * Sin(DegToRad(FSweep)), 1, Ice(200));

  // shield arc around the core (length = shield %)
  if FGame.Shield > 0 then
    Arc(ACX, ACY, CoreR + 9, -90, -90 + 3.6 * FGame.Shield, 4, Ice);
  if FGame.CoreFlash > 0 then
    Ring(ACX, ACY, CoreR + 10 + (0.35 - FGame.CoreFlash) * 120, 3, White(Round(255 * FGame.CoreFlash / 0.35)));

  for i := 0 to High(FGame.Enemies) do
    DrawEnemy(FGame.Enemies[i]);

  // tracer from the core to the aim point
  if FGame.TracerAge < 0.15 then
    Line(ACX, ACY, FGame.TracerX, FGame.TracerY, 2.5 * (1 - FGame.TracerAge / 0.15) + 0.5,
      White(Round(255 * (1 - FGame.TracerAge / 0.15))));

  // explosions: expanding ring + spokes
  for i := 0 to High(FGame.Blasts) do
  begin
    b := FGame.Blasts[i];
    age := b.Age / 0.6;
    sz := b.Size * (0.4 + age);
    Ring(b.X, b.Y, sz, 2.5 * (1 - age) + 0.5, White(Round(255 * (1 - age))));
    if b.Size > 12 then
      Ticks(b.X, b.Y, sz * 0.6, sz * 1.1, 8, b.Size * 7, b.Size * 7 + 360, 1.5, Ice(Round(220 * (1 - age))));
  end;

  case FGame.Stage of
    gsReady:
      begin
        TxtCached(ACX, ACY - 110, 'RADAR DEFENSE', 26, taCenter);
        TxtCached(ACX, ACY - 70, 'AIM WITH THE MOUSE  -  CLICK TO FIRE', 9, taCenter);
        TxtCached(ACX, ACY + 90, 'CLICK TO START', 12, taCenter);
      end;
    gsOver:
      begin
        TxtCached(ACX, ACY - 110, 'SHIELD DOWN', 28, taCenter);
        TxtCached(ACX, ACY - 66, Format('SCORE %d   WAVE %d   BEST %d', [FGame.Score, FGame.Wave, FGame.Best]), 10, taCenter);
        TxtCached(ACX, ACY + 90, 'CLICK TO RESTART', 12, taCenter);
      end;
  else
    if FGame.WaveBanner > 0 then
      TxtCached(ACX, ACY - 120, Format('WAVE %d', [FGame.Wave]), 22, taCenter);
  end;

  DrawCrosshair;
end;

procedure TRadarArenaWidget.DefineDirty;
begin
  // everything inside the radar can change every frame
  AddDirty(ACX - ArenaR - 30, ACY - ArenaR - 30, ACX + ArenaR + 30, ACY + ArenaR + 30);
end;

procedure TRadarArenaWidget.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d, radar centre (%d, %d), radius %d, core radius %d.', [ArenaSize, ArenaSize, ACX, ACY, ArenaR, CoreR]));
  L.Add('');
  L.Add('STATIC     scope disc Navy, rim + 120/12 ticks, 3 range rings, cross hairs,');
  L.Add('           bearing labels 000..315, core disc with "CORE".');
  L.Add('DYNAMIC    sweep (60 deg/s, 10 slices), shield arc around the core (length =');
  L.Add('           shield %), core hit flash, drones, tracer, explosions, banners,');
  L.Add('           crosshair (dim when energy < shot cost) + rotating LOCK brackets.');
  L.Add('DRONES     Drone = filled arrow, Dart = Ice chevron with trail,');
  L.Add('           Heavy = Steel disc with one pip per remaining hit.');
end;

{ ---------- TGameReadout ---------- }

const
  GRW = 370;
  GRH = 220;

constructor TGameReadout.Create;
begin
  inherited Create;
  SetView(GRW, GRH);
end;

class function TGameReadout.UIName: string;
begin
  Result := 'Score Panel';
end;

class function TGameReadout.UIDescription: string;
begin
  Result := 'Score, best score, wave, kills, accuracy and best combo of the current game.';
end;

class function TGameReadout.UnitFile: string;
begin
  Result := 'HUDRadarDefense\uhudradardefense.pas';
end;

procedure TGameReadout.DrawStatic;
const
  Labels: array[0..4] of string = ('BEST', 'WAVE', 'KILLS', 'ACCURACY', 'MAX COMBO');
var
  i: integer;
begin
  FillPoly([0, 10, 10, 0, 250, 0, 260, 10, GRW, 10, GRW, GRH - 10, GRW - 10, GRH, 0, GRH], Steel(50));
  Polygon([0, 10, 10, 0, 250, 0, 260, 10, GRW, 10, GRW, GRH - 10, GRW - 10, GRH, 0, GRH], 1.5, Ice(200));
  for i := 0 to 5 do
    Line(205 + i * 7, 8, 212 + i * 7, 2, 2, White(200));
  Line(GRW, 40, GRW, 110, 3, White);
  Txt(14, 14, '\\SCORE', 7, White(230));
  Line(30, 82, GRW - 30, 82, 1, Ice(120));
  Line(140, 82, GRW - 140, 82, 2.5, White);
  for i := 0 to High(Labels) do
  begin
    Txt(24, 100 + i * 22, Labels[i], 8, Ice(210));
    Line(24, 100 + i * 22 + 11, GRW - 24, 100 + i * 22 + 11, 0.6, Ice(60));
  end;
end;

procedure TGameReadout.DrawDynamic;
var
  acc: string;
begin
  TxtCached(GRW / 2, 52, Format('%.7d', [FGame.Score]), 30, taCenter);
  if FGame.Shots > 0 then acc := Format('%.0f %%', [100 * FGame.Hits / FGame.Shots]) else acc := '-';
  TxtCached(GRW - 24, 100, IntToStr(FGame.Best), 9, taRightJustify);
  TxtCached(GRW - 24, 122, IntToStr(FGame.Wave), 9, taRightJustify);
  TxtCached(GRW - 24, 144, IntToStr(FGame.Kills), 9, taRightJustify);
  TxtCached(GRW - 24, 166, acc, 9, taRightJustify);
  TxtCached(GRW - 24, 188, 'x' + IntToStr(FGame.MaxCombo), 9, taRightJustify);
end;

procedure TGameReadout.DefineDirty;
begin
  AddDirty(40, 28, GRW - 40, 76);
  AddDirty(200, 90, GRW - 20, 196);
end;

procedure TGameReadout.DescribeAnatomy(L: TStrings);
begin
  L.Add(Format('View %d x %d. Frame in the Data Frames style, "\\SCORE" title.', [GRW, GRH]));
  L.Add('DYNAMIC    7-digit score size 30, then BEST / WAVE / KILLS / ACCURACY /');
  L.Add('           MAX COMBO right-aligned (cached text bitmaps).');
end;

{ ---------- THUDRadarDefenseWidget ---------- }

constructor THUDRadarDefenseWidget.Create;
var
  readout: TGameReadout;
begin
  inherited Create;
  SetView(1100, 720);
  SetParamByName('Max zoom', 2);
  Randomize;
  FGame := TGameState.Create;
  FDifficulty := 1;
  FShotCost := 8;
  AddParam('Difficulty', 'Game', 'Multiplies drone speed and spawn rate.', FDifficulty, 0.3, 3, 2, False);
  AddParam('Energy per shot', 'Game', 'Energy used by each shot (energy regenerates 12 per second).',
    FShotCost, 1, 50, 0, False);
  AddParam('Autopilot', 'Game', '1 = a bot aims and fires (demo / attract mode, also used for testing).',
    FAutopilot, 0, 1, 0, False);

  FArena := TRadarArenaWidget.Create;
  FArena.FGame := FGame;
  AddChild(FArena, 0, 10, 'Radar Arena');

  readout := TGameReadout.Create;
  readout.FGame := FGame;
  AddChild(readout, 715, 15, 'Score Panel');

  FEnergy := TChevronLoaderWidget.Create;
  FEnergy.Caption := 'ENERGY';
  FEnergy.SetParamByName('Auto progress', 0);
  AddChild(FEnergy, 735, 250, 'Energy (Chevron Loader)');
  FShieldBar := TPillLoaderWidget.Create;
  FShieldBar.Caption := 'SHIELD';
  FShieldBar.SetParamByName('Auto progress', 0);
  AddChild(FShieldBar, 735, 335, 'Shield (Pill Loader)');
  FWaveBar := TBlockLoaderWidget.Create;
  FWaveBar.Caption := 'WAVE PROGRESS';
  FWaveBar.SetParamByName('Auto progress', 0);
  AddChild(FWaveBar, 735, 420, 'Wave progress (Block Loader)');
  FComboBar := TSlantLoaderWidget.Create;
  FComboBar.Caption := 'COMBO';
  FComboBar.SetParamByName('Auto progress', 0);
  AddChild(FComboBar, 735, 505, 'Combo (Slant Loader)');
  FIcons := THUDIconSetWidget.Create;
  AddChild(FIcons, 755, 590, 'Shield alert (HUD Icon Set)');
end;

destructor THUDRadarDefenseWidget.Destroy;
begin
  inherited Destroy;
  FGame.Free;
end;

class function THUDRadarDefenseWidget.UIName: string;
begin
  Result := 'HUD Radar Defense';
end;

class function THUDRadarDefenseWidget.UIDescription: string;
begin
  Result := 'Arcade game built from the HUD kit: aim with the mouse, click to shoot the drones before ' +
    'they reach the core. Space pauses.';
end;

class function THUDRadarDefenseWidget.UnitFile: string;
begin
  Result := 'HUDRadarDefense\uhudradardefense.pas';
end;

procedure THUDRadarDefenseWidget.Drive(W: THUDWidget; const AParam: string; v: double);
begin
  W.SetParamValue(W.ParamIndex(AParam), v);
end;

procedure THUDRadarDefenseWidget.Autopilot(dt: single);
var
  i, target: integer;
  ex, ey, best, blend: single;
begin
  FBotCooldown -= dt;
  if FGame.Stage <> gsPlaying then
  begin
    if FBotCooldown <= -1.5 then begin FGame.Fire; FBotCooldown := 0; end;  // (re)start
    Exit;
  end;
  // the drone closest to the core is the most urgent
  target := -1;
  best := MaxSingle;
  for i := 0 to High(FGame.Enemies) do
    if FGame.Enemies[i].Dist < best then
    begin
      best := FGame.Enemies[i].Dist;
      target := i;
    end;
  if target < 0 then Exit;
  FGame.EnemyXY(FGame.Enemies[target], ex, ey);
  blend := Min(1, dt * 9);   // human-ish hand speed
  FGame.AimX += (ex - FGame.AimX) * blend;
  FGame.AimY += (ey - FGame.AimY) * blend;
  if (FGame.LockIdx >= 0) and (FGame.Energy >= FGame.ShotCost) and (FBotCooldown <= 0) then
  begin
    FGame.Fire;
    FBotCooldown := 0.18;
  end;
end;

procedure THUDRadarDefenseWidget.DrawDynamic;
var
  dt: single;
  low: boolean;
begin
  // game clock = animation clock: stops with Pause, follows Animation speed
  dt := EnsureRange(T - FLastT, 0, 0.05);
  FLastT := T;
  FGame.Difficulty := FDifficulty;
  FGame.ShotCost := FShotCost;
  if FAutopilot >= 1 then Autopilot(dt);
  FGame.Update(dt);

  Drive(FEnergy, 'Progress %', FGame.Energy);
  Drive(FShieldBar, 'Progress %', FGame.Shield);
  Drive(FWaveBar, 'Progress %', 100 * FGame.WaveKills / FGame.KillsForWave);
  Drive(FComboBar, 'Progress %', Min(100, FGame.Combo * 5));
  // blink rate is a static parameter: change it only when the state flips
  low := (FGame.Stage = gsPlaying) and (FGame.Shield <= 30);
  if low <> (FIcons.Params[FIcons.ParamIndex('Alert blink rate')].Value^ > 0) then
    Drive(FIcons, 'Alert blink rate', IfThen(low, 3, 0));
  inherited DrawDynamic;
end;

procedure THUDRadarDefenseWidget.MouseAim(px, py: integer);
var
  p: TPointF;
begin
  p := PixelToDesign(px, py);
  // arena child origin is (0, 10)
  FGame.AimX := p.x;
  FGame.AimY := p.y - 10;
end;

procedure THUDRadarDefenseWidget.MouseClick;
begin
  FGame.Fire;
end;

procedure THUDRadarDefenseWidget.DescribeAnatomy(L: TStrings);
var
  i: integer;
begin
  L.Add('RULES');
  L.Add('  Drones spawn on the radar edge and fly to the core (spiralling a little).');
  L.Add('  Left-click fires at the crosshair; a hit needs a LOCK (crosshair within');
  L.Add('  drone radius + 12). Each shot costs "Energy per shot"; energy refills 12/s.');
  L.Add('  Drone 1 hit 100 pts | Dart 1 hit 150 pts, fast, wave 2+ | Heavy 3 hits 300 pts,');
  L.Add('  wave 3+. Score x (1 + 0.1 x combo), combo capped at 20, reset by a miss or a');
  L.Add('  core hit. A core hit costs 10 shield (Heavy 20). Wave n needs 8 + 4n kills;');
  L.Add('  clearing a wave gives +15 shield. Spawn interval = max(0.28, 1.5 - 0.1 wave) /');
  L.Add('  Difficulty. Shield 0 = game over; best score -> highscore.txt.');
  L.Add('');
  L.Add('CONTROLS   mouse = aim, left click = fire / start / restart, Space = pause');
  L.Add('');
  L.Add('HUD BINDING');
  L.Add('  Energy -> Chevron loader   Shield -> Pill loader   Wave kills -> Block loader');
  L.Add('  Combo x5 % -> Slant loader   Shield <= 30 -> HUD Icon Set blinks 3 Hz');
  L.Add('');
  L.Add('LAYOUT (canvas 1100 x 720)');
  for i := 0 to ChildCount - 1 do
    L.Add(Format('  %-30s %-24s (%4.0f,%4.0f)', [ChildCaption(i), Children[i].ClassName,
      ChildOrigin(i).x, ChildOrigin(i).y]));
end;

procedure THUDRadarDefenseWidget.DescribeLive(L: TStrings);
const
  StageName: array[TGameStage] of string = ('ready', 'playing', 'game over');
begin
  inherited DescribeLive(L);
  L.Add('Stage               ' + StageName[FGame.Stage]);
  L.Add(Format('Score / best        %d / %d', [FGame.Score, FGame.Best]));
  L.Add(Format('Wave                %d  (%d / %d kills)', [FGame.Wave, FGame.WaveKills, FGame.KillsForWave]));
  L.Add(Format('Shield / energy     %.0f / %.0f', [FGame.Shield, FGame.Energy]));
  L.Add(Format('Drones on screen    %d', [Length(FGame.Enemies)]));
  L.Add(Format('Combo (max)         %d (%d)', [FGame.Combo, FGame.MaxCombo]));
  L.Add(Format('Aim                 (%.0f, %.0f)  lock %d', [FGame.AimX, FGame.AimY, FGame.LockIdx]));
end;

{ ---------- input wiring ---------- }

type
  TGameInput = class(TComponent)
  private
    FForm: THUDHostForm;
    procedure Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  end;

procedure TGameInput.Move(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  THUDRadarDefenseWidget(FForm.Widget).MouseAim(X, Y);
end;

procedure TGameInput.Down(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FForm.View.SetFocus;
  THUDRadarDefenseWidget(FForm.Widget).MouseAim(X, Y);
  if Button = mbLeft then
    THUDRadarDefenseWidget(FForm.Widget).MouseClick;
end;

procedure SetupGame(AForm: THUDHostForm);
var
  inp: TGameInput;
begin
  if not (AForm.Widget is THUDRadarDefenseWidget) then Exit;
  inp := TGameInput.Create(AForm);
  inp.FForm := AForm;
  AForm.View.OnMouseMove := @inp.Move;
  AForm.View.OnMouseDown := @inp.Down;
  AForm.View.Cursor := crCross;
  AForm.SetStatus('Mouse: aim   Left click: fire / start   Space: pause   Esc: exit');
end;

initialization
  HostSetupProc := @SetupGame;

end.
