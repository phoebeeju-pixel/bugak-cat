# ============================================================
# 부각이 - 데스크탑 검은 고양이 + 뽀모도로
# ============================================================

# ┌──────────────────────────────────────────────────────────┐
# │  배포 / 업데이트 설정  (여기 두 줄만 고치면 됩니다)        │
# └──────────────────────────────────────────────────────────┘
# 새 버전을 낼 때마다 아래 $AppVersion 을 올리고,
# GitHub 의 version.txt 에도 같은 번호를 적어서 push 하면
# 부각이를 쓰는 사람들에게 "새 버전 나왔어요" 알림이 뜹니다.
$AppVersion = "1.0.0"

# GitHub 에 올린 version.txt 의 raw 주소.
# 예) https://raw.githubusercontent.com/내아이디/bugak-cat/main/version.txt
# 비워두면 업데이트 확인 기능이 그냥 꺼집니다.
$UpdateUrl = "https://raw.githubusercontent.com/phoebeeju-pixel/bugak-cat/main/version.txt"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- 중복 실행 방지 ----
# 자동 실행과 수동 실행이 겹치면 부각이가 두 마리 뜨므로, 이미 떠 있으면 조용히 종료한다.
$AppMutex = New-Object System.Threading.Mutex($false, "BugakCat_SingleInstance")
$gotIt = $false
try { $gotIt = $AppMutex.WaitOne(0, $false) } catch { $gotIt = $true }
if (-not $gotIt) { exit }

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SettingsPath = Join-Path $AppDir "settings.txt"
$SoundDir = Join-Path $env:TEMP "BugakCat"
if (-not (Test-Path $SoundDir)) { New-Item -ItemType Directory -Path $SoundDir | Out-Null }

# 그림을 그리는 기준 크기 (디자인 좌표). 실제 창 크기는 여기에 배율을 곱해서 정함
$catW = 264
$catH = 215

# ---- 화면 배율(DPI) 보정 ----
# Windows.Forms는 물리 픽셀, WPF는 DIP(96dpi 기준)을 쓴다.
# 섞어 쓰면 125%/150% 배율 PC에서 위치와 크기가 어긋나므로 전부 DIP로 변환해서 쓴다.
$DPI = 1.0
try {
    $gfx = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $DPI = $gfx.DpiX / 96.0
    $gfx.Dispose()
} catch { }
if ($DPI -le 0) { $DPI = 1.0 }

$scrRaw = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$ScrL = $scrRaw.Left   / $DPI
$ScrR = $scrRaw.Right  / $DPI
$ScrB = $scrRaw.Bottom / $DPI
$ScrW = $ScrR - $ScrL
# 작업표시줄까지 포함한 전체 화면 아래끝 (드래그로 더 아래에도 놓을 수 있게)
$FullB = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Bottom / $DPI

# ============================================================
# 소리
# ============================================================
function Write-Wav {
    param([string]$Path, [double[]]$Samples, [int]$Rate = 22050)
    $n = $Samples.Length
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Create)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("RIFF"))
    $bw.Write([int](36 + $n * 2))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("WAVE"))
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("fmt "))
    $bw.Write([int]16)
    $bw.Write([int16]1)
    $bw.Write([int16]1)
    $bw.Write([int]$Rate)
    $bw.Write([int]($Rate * 2))
    $bw.Write([int16]2)
    $bw.Write([int16]16)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("data"))
    $bw.Write([int]($n * 2))
    foreach ($s in $Samples) {
        $v = [int]($s * 30000)
        if ($v -gt 32767) { $v = 32767 }
        if ($v -lt -32767) { $v = -32767 }
        $bw.Write([int16]$v)
    }
    $bw.Close()
    $fs.Close()
}

function Build-MeowSamples {
    param([double]$Dur = 0.62, [double]$BaseHz = 470)
    $rate = 22050
    $n = [int]($rate * $Dur)
    $out = New-Object double[] $n
    $phase = 0.0
    $twoPi = 2 * [Math]::PI
    for ($i = 0; $i -lt $n; $i++) {
        $t = $i / $rate
        $p = $t / $Dur
        $f = $BaseHz + 330 * [Math]::Sin([Math]::PI * [Math]::Pow($p, 0.65))
        $vib = 1 + 0.035 * [Math]::Sin($twoPi * 6.2 * $t)
        $phase += $twoPi * $f * $vib / $rate
        $h2 = 0.62 * (1 - 0.55 * $p)
        $h3 = 0.42 * (1 - 0.75 * $p)
        $h4 = 0.22 * (1 - 0.95 * $p)
        $s = [Math]::Sin($phase) + $h2 * [Math]::Sin(2 * $phase) + $h3 * [Math]::Sin(3 * $phase) + $h4 * [Math]::Sin(4 * $phase)
        if ($p -lt 0.07) { $env = $p / 0.07 }
        elseif ($p -gt 0.62) { $env = (1 - $p) / 0.38 }
        else { $env = 1.0 }
        $env = $env * $env
        $out[$i] = $s * $env * 0.16
    }
    return $out
}

function Build-PurrSamples {
    $rate = 22050
    $dur = 0.95
    $n = [int]($rate * $dur)
    $out = New-Object double[] $n
    $phase = 0.0
    $twoPi = 2 * [Math]::PI
    for ($i = 0; $i -lt $n; $i++) {
        $t = $i / $rate
        $p = $t / $dur
        $phase += $twoPi * 44 / $rate
        $trill = 0.5 + 0.5 * [Math]::Sin($twoPi * 26 * $t)
        $s = ([Math]::Sin($phase) + 0.7 * [Math]::Sin(2 * $phase) + 0.4 * [Math]::Sin(3 * $phase)) * $trill
        if ($p -lt 0.12) { $env = $p / 0.12 }
        elseif ($p -gt 0.75) { $env = (1 - $p) / 0.25 }
        else { $env = 1.0 }
        $out[$i] = $s * $env * 0.22
    }
    return $out
}

$MeowPath  = Join-Path $SoundDir "meow.wav"
$Meow2Path = Join-Path $SoundDir "meow2.wav"
$PurrPath  = Join-Path $SoundDir "purr.wav"
try {
    if (-not (Test-Path $MeowPath))  { Write-Wav -Path $MeowPath  -Samples (Build-MeowSamples -Dur 0.62 -BaseHz 470) }
    if (-not (Test-Path $Meow2Path)) { Write-Wav -Path $Meow2Path -Samples (Build-MeowSamples -Dur 0.48 -BaseHz 560) }
    if (-not (Test-Path $PurrPath))  { Write-Wav -Path $PurrPath  -Samples (Build-PurrSamples) }
} catch { }

$playerMeow = $null; $playerMeow2 = $null; $playerPurr = $null
try {
    $playerMeow  = New-Object System.Media.SoundPlayer $MeowPath
    $playerMeow2 = New-Object System.Media.SoundPlayer $Meow2Path
    $playerPurr  = New-Object System.Media.SoundPlayer $PurrPath
} catch { }

function Play-Meow {
    try {
        if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { $playerMeow.Play() } else { $playerMeow2.Play() }
    } catch { }
}
function Play-Purr { try { $playerPurr.Play() } catch { } }

# ============================================================
# 그림 (옆모습, 머리가 왼쪽 / 궁댕이가 오른쪽)
# ============================================================
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Bugak" Height="$catH" Width="$catW"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        WindowStartupLocation="Manual">
  <Window.Resources>
    <RadialGradientBrush x:Key="Fur" GradientOrigin="0.4,0.2" Center="0.5,0.4" RadiusX="0.9" RadiusY="0.95">
      <GradientStop Color="#3A3A44" Offset="0.0"/>
      <GradientStop Color="#22222C" Offset="0.55"/>
      <GradientStop Color="#131319" Offset="1.0"/>
    </RadialGradientBrush>
    <RadialGradientBrush x:Key="FurDark" GradientOrigin="0.4,0.2" Center="0.5,0.4" RadiusX="0.9" RadiusY="0.95">
      <GradientStop Color="#2A2A34" Offset="0.0"/>
      <GradientStop Color="#18181F" Offset="0.6"/>
      <GradientStop Color="#0D0D12" Offset="1.0"/>
    </RadialGradientBrush>
    <RadialGradientBrush x:Key="EyeFill" GradientOrigin="0.35,0.3" Center="0.5,0.5" RadiusX="0.8" RadiusY="0.8">
      <GradientStop Color="#F6DC9C" Offset="0.0"/>
      <GradientStop Color="#E4BC5E" Offset="0.55"/>
      <GradientStop Color="#B98F35" Offset="1.0"/>
    </RadialGradientBrush>
  </Window.Resources>

  <Canvas x:Name="RootCanvas" Width="$catW" Height="$catH">
    <Canvas.RenderTransform>
      <ScaleTransform x:Name="RootScale" ScaleX="1" ScaleY="1"/>
    </Canvas.RenderTransform>

    <Ellipse x:Name="Shadow" Width="140" Height="16" Canvas.Left="100" Canvas.Top="184" Opacity="0.24">
      <Ellipse.Fill>
        <RadialGradientBrush>
          <GradientStop Color="#000000" Offset="0.0"/>
          <GradientStop Color="#00000000" Offset="1.0"/>
        </RadialGradientBrush>
      </Ellipse.Fill>
    </Ellipse>

    <Canvas x:Name="CatGroup" Width="$catW" Height="$catH" RenderTransformOrigin="0.5,0.92">
      <Canvas.RenderTransform>
        <TransformGroup>
          <ScaleTransform x:Name="FlipTransform" ScaleX="1" ScaleY="1"/>
          <RotateTransform x:Name="BodyRotate" Angle="0"/>
          <TranslateTransform x:Name="BounceTransform" X="0" Y="0"/>
        </TransformGroup>
      </Canvas.RenderTransform>

      <!-- 꼬리 (궁댕이 끝에서 이어짐) -->
      <Path x:Name="Tail" Fill="{StaticResource Fur}"
            Data="M 218,134 C 240,132 252,116 250,98 C 249,85 241,78 233,78 C 239,84 241,93 238,102 C 233,115 227,121 214,123 Z">
        <Path.RenderTransform>
          <RotateTransform x:Name="TailRotate" Angle="0" CenterX="218" CenterY="132"/>
        </Path.RenderTransform>
      </Path>

      <!-- 먼쪽 다리 (뒤에 그림) -->
      <Canvas x:Name="LegBackFar">
        <Path Fill="{StaticResource FurDark}" Data="M 202,140 C 214,140 220,150 220,162 L 219,178 C 219,184 201,184 201,178 Z"/>
        <Ellipse Width="24" Height="20" Canvas.Left="199" Canvas.Top="170" Fill="#0E0E14"/>
      </Canvas>
      <Canvas x:Name="LegFrontFar">
        <Path Fill="{StaticResource FurDark}" Data="M 138,142 C 148,142 154,150 154,160 L 153,178 C 153,184 135,184 135,178 Z"/>
        <Ellipse Width="23" Height="19" Canvas.Left="133" Canvas.Top="170" Fill="#0E0E14"/>
      </Canvas>

      <!-- 몸통 + 궁댕이: 하나의 곡선 (뱃살 슬림) -->
      <Canvas x:Name="Body">
        <Path Fill="{StaticResource Fur}"
              Data="M 88,116 C 92,94 116,86 146,86 C 181,86 209,99 217,123 C 224,145 213,164 196,167 C 164,172 128,170 110,161 C 95,153 86,132 88,116 Z"/>
        <!-- 궁디팡팡 클릭 영역 (보이지 않음) -->
        <Ellipse x:Name="RumpHit" Width="72" Height="78" Canvas.Left="156" Canvas.Top="92" Fill="Transparent" Cursor="Hand"/>
      </Canvas>

      <!-- 식빵굽기 몸통 -->
      <Canvas x:Name="LoafBody" Visibility="Collapsed">
        <Path Fill="{StaticResource Fur}"
              Data="M 28,190 C 24,146 56,112 110,110 C 164,108 202,132 208,162 C 211,176 211,186 210,190 Z"/>
        <!-- 앞으로 감아둔 꼬리 -->
        <Path Fill="{StaticResource FurDark}"
              Data="M 32,184 C 40,166 64,158 92,163 C 106,166 111,176 105,183 C 99,189 86,180 68,180 C 52,180 40,187 32,184 Z"/>
      </Canvas>

      <!-- 가까운쪽 다리 -->
      <Canvas x:Name="LegBackNear">
        <Path Fill="{StaticResource Fur}" Data="M 182,138 C 197,138 205,150 205,165 L 204,180 C 204,186 181,186 181,180 Z"/>
        <Ellipse Width="29" Height="23" Canvas.Left="178" Canvas.Top="169" Fill="#1A1A22"/>
        <Ellipse Width="19" Height="9" Canvas.Left="183" Canvas.Top="171" Fill="#33333D" Opacity="0.75"/>
      </Canvas>
      <Canvas x:Name="LegFrontNear">
        <Path Fill="{StaticResource Fur}" Data="M 118,138 C 130,138 137,148 137,160 L 136,180 C 136,186 117,186 117,180 Z"/>
        <Ellipse Width="27" Height="22" Canvas.Left="114" Canvas.Top="169" Fill="#1A1A22"/>
        <Ellipse Width="18" Height="9" Canvas.Left="119" Canvas.Top="171" Fill="#33333D" Opacity="0.75"/>
      </Canvas>

      <!-- 커서를 낚아챌 때 들어올리는 앞발 (핑크 젤리가 보임) -->
      <Canvas x:Name="SwipePaw" Visibility="Collapsed">
        <!-- 어깨(127,148)에서 늘어나는 앞다리 -->
        <Path x:Name="SwipeLeg" Fill="{StaticResource Fur}" Data="M 118,142 L 136,142 L 136,168 C 136,173 118,173 118,168 Z">
          <Path.RenderTransform>
            <TransformGroup>
              <ScaleTransform x:Name="SwipeScale" ScaleX="1" ScaleY="1" CenterX="127" CenterY="148"/>
              <RotateTransform x:Name="SwipeRotate" Angle="0" CenterX="127" CenterY="148"/>
            </TransformGroup>
          </Path.RenderTransform>
        </Path>
        <!-- 발바닥 + 핑크 젤리 -->
        <Canvas x:Name="SwipePad">
          <Canvas.RenderTransform><TranslateTransform x:Name="SwipeMove" X="0" Y="0"/></Canvas.RenderTransform>
          <Ellipse Width="28" Height="25" Canvas.Left="113" Canvas.Top="158" Fill="#1B1B23"/>
          <Path Fill="#E58E9E" Data="M 127,169 C 132,169 135,172 134,177 C 133,181 121,181 120,177 C 119,172 122,169 127,169 Z"/>
          <Ellipse Width="8" Height="7" Canvas.Left="115" Canvas.Top="161" Fill="#E58E9E"/>
          <Ellipse Width="8" Height="7" Canvas.Left="123" Canvas.Top="159" Fill="#E58E9E"/>
          <Ellipse Width="8" Height="7" Canvas.Left="131" Canvas.Top="161" Fill="#E58E9E"/>
          <Ellipse Width="7" Height="6" Canvas.Left="137" Canvas.Top="166" Fill="#E58E9E"/>
        </Canvas>
      </Canvas>

      <!-- 세수할 때 얼굴 앞으로 오는 앞발 -->
      <Canvas x:Name="GroomPaw" Visibility="Collapsed">
        <Path Fill="{StaticResource Fur}" Data="M 100,120 C 112,118 120,128 118,140 C 116,150 102,152 96,144 C 92,136 94,122 100,120 Z"/>
        <Ellipse Width="21" Height="13" Canvas.Left="96" Canvas.Top="114" Fill="#2E2E38"/>
      </Canvas>

      <!-- 머리 -->
      <Canvas x:Name="HeadGroup">
        <!-- 머리 + 두 귀를 하나의 실루엣으로 -->
        <Path Fill="{StaticResource Fur}"
              Data="M 12,80 C 12,64 18,52 30,46 L 37,8 L 52,36 C 62,31 78,31 88,36 L 103,8 L 110,46 C 122,52 128,64 128,80 C 128,105 102,125 70,125 C 38,125 12,105 12,80 Z"/>
        <!-- 귀 안쪽 -->
        <Path Fill="#6B4652" Opacity="0.75" Data="M 36,40 L 38,24 L 45,36 Z"/>
        <Path Fill="#6B4652" Opacity="0.75" Data="M 95,36 L 102,24 L 104,40 Z"/>

        <Canvas x:Name="EyesOpen">
          <Ellipse Width="34" Height="34" Canvas.Left="34" Canvas.Top="55" Fill="#D9C24F"/>
          <Ellipse Width="34" Height="34" Canvas.Left="72" Canvas.Top="55" Fill="#D9C24F"/>
          <Ellipse Width="22" Height="22" Canvas.Left="40" Canvas.Top="61" Fill="#111117" RenderTransformOrigin="0.5,0.5">
            <Ellipse.RenderTransform>
              <TransformGroup>
                <ScaleTransform x:Name="PupilScaleL" ScaleX="1" ScaleY="1"/>
                <TranslateTransform x:Name="PupilMoveL" X="0" Y="0"/>
              </TransformGroup>
            </Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse Width="22" Height="22" Canvas.Left="78" Canvas.Top="61" Fill="#111117" RenderTransformOrigin="0.5,0.5">
            <Ellipse.RenderTransform>
              <TransformGroup>
                <ScaleTransform x:Name="PupilScaleR" ScaleX="1" ScaleY="1"/>
                <TranslateTransform x:Name="PupilMoveR" X="0" Y="0"/>
              </TransformGroup>
            </Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse Width="11" Height="11" Canvas.Left="38" Canvas.Top="59" Fill="White">
            <Ellipse.RenderTransform><TranslateTransform x:Name="GlintL" X="0" Y="0"/></Ellipse.RenderTransform>
          </Ellipse>
          <Ellipse Width="11" Height="11" Canvas.Left="76" Canvas.Top="59" Fill="White">
            <Ellipse.RenderTransform><TranslateTransform x:Name="GlintR" X="0" Y="0"/></Ellipse.RenderTransform>
          </Ellipse>
        </Canvas>

        <Canvas x:Name="EyesHappy" Visibility="Collapsed">
          <Path Data="M 36,81 C 43,66 60,66 67,81" Stroke="#0E0E14" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          <Path Data="M 74,81 C 81,66 98,66 105,81" Stroke="#0E0E14" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
        </Canvas>

        <Canvas x:Name="EyesSleep" Visibility="Collapsed">
          <Path Data="M 36,70 C 43,83 60,83 67,70" Stroke="#0E0E14" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
          <Path Data="M 74,70 C 81,83 98,83 105,70" Stroke="#0E0E14" StrokeThickness="4.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
        </Canvas>

        <Path Fill="#D3868F" Data="M 63,94 C 65,91 75,91 77,94 C 77,98 71,103 70,103 C 69,103 63,98 63,94 Z"/>

        <Canvas x:Name="MouthNormal">
          <Path Data="M 70,103 L 70,107 M 70,107 C 66,112 59,111 57,107 M 70,107 C 74,112 81,111 83,107"
                Stroke="#0E0E14" StrokeThickness="2.3" StrokeStartLineCap="Round"/>
        </Canvas>
        <Canvas x:Name="MouthYawn" Visibility="Collapsed">
          <Ellipse Width="26" Height="30" Canvas.Left="58" Canvas.Top="103" Fill="#12121A"/>
          <Ellipse Width="18" Height="16" Canvas.Left="62" Canvas.Top="112" Fill="#C4707E"/>
        </Canvas>

        <Path Data="M 22,99 C 10,95 4,93 -6,91" Stroke="#E8E8E8" StrokeThickness="1.4" Opacity="0.65"/>
        <Path Data="M 22,105 C 10,105 4,107 -6,109" Stroke="#E8E8E8" StrokeThickness="1.4" Opacity="0.65"/>
        <Path Data="M 118,99 C 130,95 136,93 146,91" Stroke="#E8E8E8" StrokeThickness="1.4" Opacity="0.65"/>
        <Path Data="M 118,105 C 130,105 136,107 146,109" Stroke="#E8E8E8" StrokeThickness="1.4" Opacity="0.65"/>
      </Canvas>
    </Canvas>

    <TextBlock x:Name="ZzzText" Text="z z Z" FontSize="16" Foreground="#A8B4CC" FontStyle="Italic"
               Canvas.Left="6" Canvas.Top="8" Visibility="Collapsed"/>
    <TextBlock x:Name="NoteText" Text="&#9834; &#9835;" FontSize="19" Foreground="#8FD8FF"
               Canvas.Left="196" Canvas.Top="24" Visibility="Collapsed"/>

    <Canvas x:Name="BowlGroup" Canvas.Left="0" Canvas.Top="164" Visibility="Collapsed" Cursor="Hand">
      <Ellipse Width="50" Height="26" Canvas.Left="0" Canvas.Top="10" Fill="#8A5A32"/>
      <Ellipse Width="50" Height="17" Canvas.Left="0" Canvas.Top="5" Fill="#B5793F"/>
      <Ellipse Width="40" Height="12" Canvas.Left="5" Canvas.Top="7" Fill="#5C3A20"/>
      <!-- 사료: 그릇을 누르면 쌓이고, 먹으면 줄어든다 -->
      <Canvas x:Name="BowlFood" Visibility="Collapsed">
        <Canvas.RenderTransform>
          <ScaleTransform x:Name="FoodScale" ScaleX="1" ScaleY="1" CenterX="25" CenterY="15"/>
        </Canvas.RenderTransform>
        <Ellipse Width="33" Height="11" Canvas.Left="8" Canvas.Top="5" Fill="#E8B274"/>
        <Ellipse Width="11" Height="9" Canvas.Left="12" Canvas.Top="1" Fill="#D89A5C"/>
        <Ellipse Width="11" Height="9" Canvas.Left="20" Canvas.Top="-1" Fill="#EFC188"/>
        <Ellipse Width="10" Height="8" Canvas.Left="28" Canvas.Top="2" Fill="#D89A5C"/>
      </Canvas>
    </Canvas>

    <Border x:Name="LabelBorder" Background="#E61E1E26" CornerRadius="11" Padding="10,3"
            Canvas.Left="86" Canvas.Top="0" Visibility="Collapsed">
      <TextBlock x:Name="StatusLabel" Text="" Foreground="#F2F2F7" FontSize="12" FontFamily="Malgun Gothic"/>
    </Border>
  </Canvas>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$UI = @{}
foreach ($n in @("CatGroup","FlipTransform","BodyRotate","BounceTransform","Tail","TailRotate",
                 "Body","RumpHit","LoafBody","LegFrontNear","LegFrontFar","LegBackNear","LegBackFar",
                 "GroomPaw","SwipePaw","SwipeRotate","SwipeMove","SwipeScale","Tail",
                 "HeadGroup","EyesOpen","EyesHappy","EyesSleep",
                 "PupilScaleL","PupilScaleR","PupilMoveL","PupilMoveR","GlintL","GlintR",
                 "MouthNormal","MouthYawn",
                 "ZzzText","NoteText","BowlGroup","BowlFood","FoodScale","LabelBorder","StatusLabel","Shadow",
                 "RootScale")) {
    $UI[$n] = $window.FindName($n)
}

# 다리는 고관절을 축으로 회전(+살짝 들기)해야 몸통에서 안 떨어져 보임
$LIMBT = @{}
$LIMBR = @{}
$hips = @{
    LegFrontNear = @(127, 146)
    LegFrontFar  = @(145, 148)
    LegBackNear  = @(193, 144)
    LegBackFar   = @(211, 148)
}
foreach ($n in @("LegFrontNear","LegFrontFar","LegBackNear","LegBackFar")) {
    $rot = New-Object System.Windows.Media.RotateTransform
    $rot.CenterX = $hips[$n][0]
    $rot.CenterY = $hips[$n][1]
    $tr = New-Object System.Windows.Media.TranslateTransform
    $grp = New-Object System.Windows.Media.TransformGroup
    $grp.Children.Add($rot)
    $grp.Children.Add($tr)
    $UI[$n].RenderTransform = $grp
    $LIMBR[$n] = $rot
    $LIMBT[$n] = $tr
}
foreach ($n in @("HeadGroup","GroomPaw")) {
    $tr = New-Object System.Windows.Media.TranslateTransform
    $UI[$n].RenderTransform = $tr
    $LIMBT[$n] = $tr
}

# ============================================================
# 설정
# ============================================================
$CFG = [pscustomobject]@{ WorkMin = 25; BreakMin = 5; Scale = 0.0; UpdateCheck = 1 }

function Load-Settings {
    if (Test-Path $SettingsPath) {
        try {
            foreach ($line in (Get-Content $SettingsPath)) {
                $kv = $line -split "=", 2
                if ($kv.Count -eq 2) {
                    if ($kv[0].Trim() -eq "work")  { $CFG.WorkMin  = [int]$kv[1].Trim() }
                    if ($kv[0].Trim() -eq "break") { $CFG.BreakMin = [int]$kv[1].Trim() }
                    if ($kv[0].Trim() -eq "scale") { $CFG.Scale    = [double]$kv[1].Trim() }
                    if ($kv[0].Trim() -eq "update") { $CFG.UpdateCheck = [int]$kv[1].Trim() }
                }
            }
        } catch { }
    }
}
function Save-Settings {
    try {
        $txt = "work=" + $CFG.WorkMin + "`r`nbreak=" + $CFG.BreakMin + "`r`nscale=" + $CFG.Scale + "`r`nupdate=" + $CFG.UpdateCheck
        [System.IO.File]::WriteAllText($SettingsPath, $txt, (New-Object System.Text.UTF8Encoding $true))
    } catch { }
}
Load-Settings

# 저장된 배율이 없으면 화면 높이에 맞춰 자동으로 정한다.
# (부각이 키가 화면 높이의 약 20%가 되도록 - 어느 해상도/배율에서든 비슷하게 보임)
function Get-AutoScale {
    $target = ($ScrB - 0) * 0.20
    $s = $target / $catH
    if ($s -lt 0.55) { $s = 0.55 }
    if ($s -gt 1.15) { $s = 1.15 }
    return [Math]::Round($s, 2)
}
if ($CFG.Scale -le 0) { $CFG.Scale = Get-AutoScale }

$winW = $catW * $CFG.Scale
$winH = $catH * $CFG.Scale

function Apply-Scale {
    $UI.RootScale.ScaleX = $CFG.Scale
    $UI.RootScale.ScaleY = $CFG.Scale
    $script:winW = $catW * $CFG.Scale
    $script:winH = $catH * $CFG.Scale
    $window.Width  = $script:winW
    $window.Height = $script:winH
    $window.Top    = $ScrB - $script:winH - 2
    if ($window.Left -gt ($ScrR - $script:winW)) { $window.Left = $ScrR - $script:winW }
    if ($window.Left -lt $ScrL) { $window.Left = $ScrL }
}

$window.Left = $ScrL + ($ScrW / 2)
Apply-Scale

$settingsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="부각이 시간 설정" Height="275" Width="335"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        Background="#1E1E26" Topmost="True" FontFamily="Malgun Gothic">
  <StackPanel Margin="18">
    <TextBlock Text="뽀모도로 시간을 정해주세요" Foreground="#F2F2F7" FontSize="14" Margin="0,0,0,14"/>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
      <TextBlock Text="집중" Foreground="#C8C8D4" Width="46" VerticalAlignment="Center"/>
      <TextBox x:Name="WorkBox" Width="62" Height="26" VerticalContentAlignment="Center"/>
      <TextBlock Text="분" Foreground="#C8C8D4" Margin="7,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
      <TextBlock Text="휴식" Foreground="#C8C8D4" Width="46" VerticalAlignment="Center"/>
      <TextBox x:Name="BreakBox" Width="62" Height="26" VerticalContentAlignment="Center"/>
      <TextBlock Text="분" Foreground="#C8C8D4" Margin="7,0,0,0" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock Text="빠른 선택" Foreground="#8A8A9A" FontSize="11" Margin="0,0,0,5"/>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,16">
      <Button x:Name="P1" Content="25 / 5" Width="72" Height="26" Margin="0,0,7,0"/>
      <Button x:Name="P2" Content="50 / 10" Width="72" Height="26" Margin="0,0,7,0"/>
      <Button x:Name="P3" Content="15 / 3" Width="72" Height="26"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="OkBtn" Content="저장" Width="74" Height="30" Margin="0,0,8,0"/>
      <Button x:Name="CancelBtn" Content="취소" Width="74" Height="30"/>
    </StackPanel>
  </StackPanel>
</Window>
"@

function Show-Settings {
    $r = New-Object System.Xml.XmlNodeReader ([xml]$settingsXaml)
    $w = [Windows.Markup.XamlReader]::Load($r)
    $wb = $w.FindName("WorkBox")
    $bb = $w.FindName("BreakBox")
    $wb.Text = [string]$CFG.WorkMin
    $bb.Text = [string]$CFG.BreakMin
    $w.FindName("P1").Add_Click({ $wb.Text = "25"; $bb.Text = "5" }.GetNewClosure())
    $w.FindName("P2").Add_Click({ $wb.Text = "50"; $bb.Text = "10" }.GetNewClosure())
    $w.FindName("P3").Add_Click({ $wb.Text = "15"; $bb.Text = "3" }.GetNewClosure())
    $w.FindName("CancelBtn").Add_Click({ $w.Close() }.GetNewClosure())
    $w.FindName("OkBtn").Add_Click({
        $wv = 0; $bv = 0
        if ([int]::TryParse($wb.Text.Trim(), [ref]$wv) -and [int]::TryParse($bb.Text.Trim(), [ref]$bv)) {
            if ($wv -ge 1 -and $wv -le 180 -and $bv -ge 1 -and $bv -le 120) {
                $CFG.WorkMin = $wv
                $CFG.BreakMin = $bv
                Save-Settings
                $w.Close()
                return
            }
        }
        [System.Windows.MessageBox]::Show("집중은 1~180분, 휴식은 1~120분 사이 숫자로 넣어주세요.", "부각이") | Out-Null
    }.GetNewClosure())
    $w.ShowDialog() | Out-Null
}

# ============================================================
# 상태
# ============================================================
$S = [pscustomobject]@{
    tick       = 0
    direction  = 1
    mode       = "idle"
    modeTicks  = 40
    targetX    = $window.Left
    dilate     = 0
    noteTicks  = 0
    swipeTicks = 0
    swipeCool  = 0
    tailFlick  = 0
    nextFlick  = 300
    pomoState  = "stopped"
    remaining  = 0
    fed        = $true
    sessions   = 0
    # ---- 드래그로 위치 옮기기용 ----
    dragging    = $false
    dragMoved   = $false
    pressX      = 0.0
    pressY      = 0.0
    dragOffX    = 0.0
    dragOffY    = 0.0
    pressTarget = ""
}

# 그림이 왼쪽을 보므로 ScaleX = -dir
function Set-Facing([int]$dir) {
    $S.direction = $dir
    $UI.FlipTransform.ScaleX = (0 - $dir)
}
Set-Facing 1

function Reset-Limbs {
    foreach ($k in @("LegFrontNear","LegFrontFar","LegBackNear","LegBackFar")) {
        $LIMBT[$k].X = 0; $LIMBT[$k].Y = 0
        $LIMBR[$k].Angle = 0
    }
    $UI.SwipeScale.ScaleY = 1
    $UI.GroomPaw.Visibility = "Collapsed"
    $UI.SwipePaw.Visibility = "Collapsed"
    $UI.SwipeMove.X = 0; $UI.SwipeMove.Y = 0
    $UI.SwipeRotate.Angle = 0
    $UI.LegFrontNear.Visibility = "Visible"
    $UI.MouthYawn.Visibility = "Collapsed"
    $UI.MouthNormal.Visibility = "Visible"
    $UI.BodyRotate.Angle = 0
    $LIMBT.HeadGroup.X = 0
}

function Set-Pose([string]$pose) {
    if ($pose -eq "loaf") {
        $UI.Body.Visibility = "Collapsed"
        $UI.Tail.Visibility = "Collapsed"
        $UI.LoafBody.Visibility = "Visible"
        $UI.LegFrontNear.Visibility = "Collapsed"
        $UI.LegFrontFar.Visibility = "Collapsed"
        $UI.LegBackNear.Visibility = "Collapsed"
        $UI.LegBackFar.Visibility = "Collapsed"
    } else {
        $UI.Body.Visibility = "Visible"
        $UI.Tail.Visibility = "Visible"
        $UI.LoafBody.Visibility = "Collapsed"
        $UI.LegFrontNear.Visibility = "Visible"
        $UI.LegFrontFar.Visibility = "Visible"
        $UI.LegBackNear.Visibility = "Visible"
        $UI.LegBackFar.Visibility = "Visible"
    }
}

function Set-Eyes([string]$k) {
    $UI.EyesOpen.Visibility  = "Collapsed"
    $UI.EyesHappy.Visibility = "Collapsed"
    $UI.EyesSleep.Visibility = "Collapsed"
    if ($k -eq "happy")     { $UI.EyesHappy.Visibility = "Visible" }
    elseif ($k -eq "sleep") { $UI.EyesSleep.Visibility = "Visible" }
    else                    { $UI.EyesOpen.Visibility  = "Visible" }
}

function Go-Mode([string]$m, [int]$ticks) {
    Reset-Limbs
    Set-Pose "stand"
    $S.mode = $m
    $S.modeTicks = $ticks
}

function Start-Knead { Go-Mode "knead" 46; $S.dilate = 46 }

function Start-Pat {
    Go-Mode "pat" 70
    $S.dilate = 70
    $S.noteTicks = 70
    $UI.NoteText.Visibility = "Visible"
    Play-Purr
}

# ============================================================
# 드래그로 위치 옮기기
#  - 누른 채로 끌면 부각이가 따라오고, 놓으면 그 자리에 멈춘다
#  - 4px 미만으로 움직였으면 드래그가 아니라 "클릭"으로 보고
#    기존처럼 쓰다듬기(꾹꾹이) / 궁디팡팡을 실행한다
# ============================================================
# 커서 위치를 창이 실제로 쓰는 변환 행렬로 DIP 변환 (배율이 어떻든 정확)
function Get-CursorDip {
    $p = [System.Windows.Forms.Cursor]::Position
    try {
        $src = [System.Windows.PresentationSource]::FromVisual($window)
        if ($null -ne $src) {
            $m = $src.CompositionTarget.TransformFromDevice
            return $m.Transform((New-Object System.Windows.Point($p.X, $p.Y)))
        }
    } catch { }
    return (New-Object System.Windows.Point(($p.X / $DPI), ($p.Y / $DPI)))
}

# 누른 지점이 커서에 그대로 붙어 있도록, 창 안에서의 상대 위치를 기억한다
function Begin-Press([System.Windows.Point]$grab) {
    $S.dragOffX = $grab.X
    $S.dragOffY = $grab.Y
    $c = Get-CursorDip
    $S.pressX = $c.X
    $S.pressY = $c.Y
    $S.dragMoved = $false
    $S.dragging  = $false
    $UI.CatGroup.CaptureMouse() | Out-Null
}

# 궁댕이를 누르면 궁디팡팡, 나머지는 쓰다듬기 (판정은 버튼을 뗄 때)
$UI.RumpHit.Add_MouseLeftButtonDown({ param($snd, $ev) $S.pressTarget = "rump"; Begin-Press ($ev.GetPosition($window)); $ev.Handled = $true })
$UI.CatGroup.Add_MouseLeftButtonDown({ param($snd, $ev) $S.pressTarget = "body"; Begin-Press ($ev.GetPosition($window)) })
$UI.CatGroup.Add_MouseRightButtonDown({ Start-Pat })

$UI.CatGroup.Add_MouseMove({
    if (-not $UI.CatGroup.IsMouseCaptured) { return }
    $c = Get-CursorDip
    if (-not $S.dragMoved) {
        $mv = [Math]::Abs($c.X - $S.pressX) + [Math]::Abs($c.Y - $S.pressY)
        if ($mv -gt 4) { $S.dragMoved = $true; $S.dragging = $true }
    }
    if ($S.dragging) {
        $nl = $c.X - $S.dragOffX
        $nt = $c.Y - $S.dragOffY
        # 화면 밖으로 완전히 사라지지 않을 정도로만 느슨하게 제한
        if ($nl -lt ($ScrL - $winW * 0.6)) { $nl = $ScrL - $winW * 0.6 }
        if ($nl -gt ($ScrR - $winW * 0.4)) { $nl = $ScrR - $winW * 0.4 }
        if ($nt -lt (0 - $winH * 0.15)) { $nt = 0 - $winH * 0.15 }
        if ($nt -gt ($FullB - $winH * 0.25)) { $nt = $FullB - $winH * 0.25 }
        $window.Left = $nl
        $window.Top  = $nt
    }
})

$UI.CatGroup.Add_MouseLeftButtonUp({
    if ($UI.CatGroup.IsMouseCaptured) { $UI.CatGroup.ReleaseMouseCapture() }
    if ($S.dragMoved) {
        # 놓은 자리에서 멈춤 (바로 걸어가지 않도록 목적지도 현재 위치로)
        $S.targetX = $window.Left
        Go-Mode "sit" 90
    } else {
        if ($S.pressTarget -eq "rump") { Start-Pat } else { Start-Knead }
    }
    $S.dragging = $false
    $S.dragMoved = $false
    $S.pressTarget = ""
})
# 밥그릇을 누르면 사료가 쌓이고, 부각이가 고개를 숙여 먹는다
$UI.BowlGroup.Add_MouseLeftButtonDown({
    if (-not $S.fed) {
        $S.fed = $true
        $UI.FoodScale.ScaleX = 1
        $UI.FoodScale.ScaleY = 1
        $UI.BowlFood.Visibility = "Visible"
        Play-Meow
        Go-Mode "eat" 150
    }
})

function Pick-Idle {
    if ($S.pomoState -eq "work") { Go-Mode "loaf" 600; return }
    $r = Get-Random -Minimum 0 -Maximum 100
    if ($r -lt 42) {
        $mg = 30
        $S.targetX = Get-Random -Minimum ($ScrL + $mg) -Maximum ($ScrR - $winW - $mg)
        $d = -1
        if ($S.targetX -gt $window.Left) { $d = 1 }
        Set-Facing $d
        Go-Mode "walk" 3000
    }
    elseif ($r -lt 58) { Go-Mode "groom" 110 }
    elseif ($r -lt 70) { Go-Mode "stretch" 70 }
    elseif ($r -lt 79) { Go-Mode "yawn" 55 }
    elseif ($r -lt 90) { Start-Knead }
    else               { Go-Mode "sit" (Get-Random -Minimum 90 -Maximum 220) }
}

# ============================================================
# 애니메이션
# ============================================================
$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(33)
$animTimer.Add_Tick({
    $S.tick++
    $t = $S.tick

    # ---- 커서 (물리 픽셀 -> DIP 변환 후, 그림 좌표계 기준으로 환산) ----
    $rawCur = [System.Windows.Forms.Cursor]::Position
    $curX = $rawCur.X / $DPI
    $curY = $rawCur.Y / $DPI
    $sc = $CFG.Scale
    $sx = $UI.FlipTransform.ScaleX
    $headScreenX = $window.Left + (132 - 62 * $sx) * $sc
    $headScreenY = $window.Top + 70 * $sc
    # 거리는 그림 좌표 기준으로 재서 배율이 달라도 반응이 똑같게
    $dx = ($curX - $headScreenX) / $sc
    $dy = ($curY - $headScreenY) / $sc
    $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)

    # ---- 눈동자가 커서를 따라감 ----
    $ox = $dx / 20.0
    $oy = $dy / 20.0
    if ($ox -gt 3) { $ox = 3 }
    if ($ox -lt -3) { $ox = -3 }
    if ($oy -gt 2.5) { $oy = 2.5 }
    if ($oy -lt -2.5) { $oy = -2.5 }
    $lox = $ox * $sx
    $UI.PupilMoveL.X = $lox; $UI.PupilMoveL.Y = $oy
    $UI.PupilMoveR.X = $lox; $UI.PupilMoveR.Y = $oy
    $UI.GlintL.X = $lox * 0.3; $UI.GlintL.Y = $oy * 0.3
    $UI.GlintR.X = $lox * 0.3; $UI.GlintR.Y = $oy * 0.3

    # ---- 동공 ----
    if ($S.dilate -gt 0) { $S.dilate--; $tg = 1.22 } else { $tg = 1.0 }
    $c = $UI.PupilScaleL.ScaleX
    $nv = $c + ($tg - $c) * 0.15
    $UI.PupilScaleL.ScaleX = $nv; $UI.PupilScaleL.ScaleY = $nv
    $UI.PupilScaleR.ScaleX = $nv; $UI.PupilScaleR.ScaleY = $nv

    if ($S.noteTicks -gt 0) {
        $S.noteTicks--
        $UI.NoteText.Opacity = 0.5 + ([Math]::Sin($t * 0.25) + 1) * 0.25
        if ($S.noteTicks -le 0) { $UI.NoteText.Visibility = "Collapsed" }
    }
    if ($S.swipeCool -gt 0) { $S.swipeCool-- }

    # ---- 꼬리: 평소엔 가만히, 가끔 한 번 툭 ----
    $S.nextFlick--
    if ($S.nextFlick -le 0 -and $S.tailFlick -le 0) {
        $S.tailFlick = 34
        $S.nextFlick = Get-Random -Minimum 260 -Maximum 900
    }
    $tailAngle = [Math]::Sin($t * 0.035) * 2.5
    if ($S.tailFlick -gt 0) {
        $S.tailFlick--
        $decay = $S.tailFlick / 34.0
        $tailAngle = [Math]::Sin((34 - $S.tailFlick) * 0.55) * 20 * $decay
    }

    # ---- 커서가 가까우면 사냥 모드 ----
    $busy = @("pat","knead","groom","stretch","yawn","eat") -contains $S.mode
    if ($S.pomoState -ne "work" -and -not $busy -and -not $S.dragging) {
        if ($dist -lt 170 -and $S.mode -ne "hunt") {
            Go-Mode "hunt" 4000
            $S.dilate = 90
        } elseif ($dist -gt 240 -and $S.mode -eq "hunt") {
            Go-Mode "idle" 20
        }
    }

    switch ($S.mode) {
        "hunt" {
            Set-Eyes "open"
            $UI.ZzzText.Visibility = "Collapsed"
            $wantDir = -1
            if ($curX -gt ($window.Left + 132 * $sc)) { $wantDir = 1 }
            if ($wantDir -ne $S.direction) { Set-Facing $wantDir }

            $UI.BounceTransform.Y = 3 + [Math]::Sin($t * 0.5) * 1.4
            $LIMBT.HeadGroup.Y = [Math]::Sin($t * 0.5) * 1.2
            $UI.Shadow.Opacity = 0.3
            # 사냥할 땐 꼬리를 실제로 흔든다
            $tailAngle = [Math]::Sin($t * 0.42) * 22

            if ($S.swipeTicks -le 0 -and $S.swipeCool -le 0 -and $dist -lt 135) {
                $S.swipeTicks = 16
                $S.swipeCool = 40
            }
            if ($S.swipeTicks -gt 0) {
                $S.swipeTicks--
                $prog = (16 - $S.swipeTicks) / 16.0
                $arc = [Math]::Sin([Math]::PI * $prog)

                # 커서를 고양이 로컬 좌표로 변환해서 앞발이 그 지점까지 뻗어감
                $lcx = 132 + ((($curX - $window.Left) / $sc) - 132) * $sx
                $lcy = ($curY - $window.Top) / $sc
                $rdx = $lcx - 127
                $rdy = $lcy - 148
                $rd = [Math]::Sqrt($rdx * $rdx + $rdy * $rdy)
                if ($rd -lt 1) { $rd = 1 }
                if ($rd -gt 108) { $rdx = $rdx * 108 / $rd; $rdy = $rdy * 108 / $rd; $rd = 108 }
                $aimAng = [Math]::Atan2((0 - $rdx), $rdy) * 180 / [Math]::PI

                $curLen = 22 + ($rd - 22) * $arc
                $curAng = $aimAng * $arc
                $rad = $curAng * [Math]::PI / 180
                $UI.SwipeScale.ScaleY = $curLen / 22
                $UI.SwipeRotate.Angle = $curAng
                $UI.SwipeMove.X = (0 - [Math]::Sin($rad)) * $curLen - 0
                $UI.SwipeMove.Y = [Math]::Cos($rad) * $curLen - 22

                $UI.LegFrontNear.Visibility = "Collapsed"
                $UI.SwipePaw.Visibility = "Visible"
                $UI.BounceTransform.Y = 3 - $arc * 5
            } else {
                $UI.SwipePaw.Visibility = "Collapsed"
                $UI.LegFrontNear.Visibility = "Visible"
                $UI.SwipeMove.X = 0; $UI.SwipeMove.Y = 0
                $UI.SwipeRotate.Angle = 0
                $UI.SwipeScale.ScaleY = 1
                $LIMBR.LegFrontNear.Angle = 0
                $LIMBT.LegFrontNear.Y = [Math]::Sin($t * 0.5) * 1.5
            }
        }
        "walk" {
            Set-Eyes "open"
            $UI.ZzzText.Visibility = "Collapsed"

            # 드래그 중에는 자동 걷기로 위치를 건드리지 않는다
            if (-not $S.dragging) {
                $window.Left += (1.7 * $sc * $S.direction)
                if ($window.Left -lt $ScrL) { $window.Left = $ScrL; Set-Facing 1 }
                if ($window.Left -gt ($ScrR - $winW)) { $window.Left = $ScrR - $winW; Set-Facing -1 }
            }

            $g = $t * 0.34
            $a = [Math]::Sin($g)
            $b = [Math]::Sin($g + [Math]::PI)
            # 고관절 회전으로 대각선 짝 걸음 (몸통에서 안 떨어짐)
            $LIMBR.LegFrontNear.Angle = $a * -17
            $LIMBR.LegBackFar.Angle   = $a * -14
            $LIMBR.LegFrontFar.Angle  = $b * -14
            $LIMBR.LegBackNear.Angle  = $b * -17
            $LIMBT.LegFrontNear.Y = [Math]::Max(0, $a) * -3
            $LIMBT.LegBackFar.Y   = [Math]::Max(0, $a) * -2.5
            $LIMBT.LegFrontFar.Y  = [Math]::Max(0, $b) * -2.5
            $LIMBT.LegBackNear.Y  = [Math]::Max(0, $b) * -3

            $UI.BounceTransform.Y = [Math]::Abs([Math]::Sin($g * 2)) * -2.5
            $LIMBT.HeadGroup.Y = [Math]::Sin($g * 2 + 0.6) * 1.6
            $UI.Shadow.Opacity = 0.2 + [Math]::Abs([Math]::Cos($g * 2)) * 0.08
            $tailAngle = $tailAngle + [Math]::Sin($g) * 4

            if ([Math]::Abs($window.Left - $S.targetX) -lt 6) { Go-Mode "idle" 20 }
        }
        "sit" {
            $UI.BounceTransform.Y = [Math]::Sin($t * 0.05) * 1.2
            $LIMBT.HeadGroup.Y = [Math]::Sin($t * 0.04) * 1.0
            $UI.Shadow.Opacity = 0.24
            if (($t % 130) -lt 6) { Set-Eyes "sleep" } else { Set-Eyes "open" }
            if ((Get-Random -Minimum 0 -Maximum 280) -eq 0) { $S.dilate = 45 }
            $S.modeTicks--
            if ($S.modeTicks -le 0) { Pick-Idle }
        }
        "idle" {
            $UI.BounceTransform.Y = [Math]::Sin($t * 0.05) * 1.2
            $LIMBT.HeadGroup.Y = 0
            $UI.Shadow.Opacity = 0.24
            Set-Eyes "open"
            $S.modeTicks--
            if ($S.modeTicks -le 0) { Pick-Idle }
        }
        "groom" {
            # 앞발로 세수
            $UI.LegFrontNear.Visibility = "Collapsed"
            $UI.GroomPaw.Visibility = "Visible"
            Set-Eyes "happy"
            $UI.Shadow.Opacity = 0.24
            $LIMBT.GroomPaw.X = [Math]::Sin($t * 0.55) * 7
            $LIMBT.GroomPaw.Y = [Math]::Cos($t * 0.55) * 6 - 4
            $LIMBT.HeadGroup.Y = 3 + [Math]::Cos($t * 0.55) * 2
            $UI.BounceTransform.Y = 1
            $S.modeTicks--
            if ($S.modeTicks -le 0) { Go-Mode "idle" 25 }
        }
        "stretch" {
            # 기지개
            $p = 1 - ($S.modeTicks / 70.0)
            $amt = [Math]::Sin([Math]::PI * $p)
            $UI.BodyRotate.Angle = $amt * -9 * $S.direction
            $LIMBR.LegFrontNear.Angle = $amt * 26
            $LIMBR.LegFrontFar.Angle  = $amt * 22
            $LIMBT.HeadGroup.Y = $amt * 7
            $UI.BounceTransform.Y = $amt * 2
            $UI.Shadow.Opacity = 0.24
            if ($amt -gt 0.35) { Set-Eyes "happy" } else { Set-Eyes "open" }
            $tailAngle = $amt * -22
            $S.modeTicks--
            if ($S.modeTicks -le 0) { Go-Mode "idle" 25 }
        }
        "yawn" {
            $p = 1 - ($S.modeTicks / 55.0)
            $amt = [Math]::Sin([Math]::PI * $p)
            if ($amt -gt 0.3) {
                $UI.MouthNormal.Visibility = "Collapsed"
                $UI.MouthYawn.Visibility = "Visible"
                Set-Eyes "happy"
            } else {
                $UI.MouthNormal.Visibility = "Visible"
                $UI.MouthYawn.Visibility = "Collapsed"
                Set-Eyes "open"
            }
            $LIMBT.HeadGroup.Y = $amt * -4
            $UI.BounceTransform.Y = 0
            $UI.Shadow.Opacity = 0.24
            $S.modeTicks--
            if ($S.modeTicks -le 0) { $S.dilate = 30; Go-Mode "sit" 80 }
        }
        "loaf" {
            Set-Pose "loaf"
            $UI.ZzzText.Visibility = "Visible"
            $UI.BounceTransform.Y = [Math]::Sin($t * 0.035) * 1.4
            $LIMBT.HeadGroup.Y = [Math]::Sin($t * 0.035) * 1.1
            $UI.Shadow.Opacity = 0.28
            $UI.ZzzText.Opacity = 0.4 + ([Math]::Sin($t * 0.07) + 1) * 0.3
            $tailAngle = [Math]::Sin($t * 0.04) * 3
            if (($t % 170) -lt 120) { Set-Eyes "sleep" } else { Set-Eyes "open" }
            if ($S.pomoState -ne "work") { Go-Mode "idle" 15 }
        }
        "knead" {
            # 앞발을 45도 사선으로 뻗어 앞에 있는 걸 꾹꾹 누르는 느낌
            $ph = [Math]::Sin($t * 0.5)
            $a1 = [Math]::Max(0, $ph)
            $a2 = [Math]::Max(0, (0 - $ph))
            $LIMBR.LegFrontNear.Angle = 34 + 14 * $a1
            $LIMBR.LegFrontFar.Angle  = 34 + 14 * $a2
            $LIMBT.LegFrontNear.X = -6 * $a1
            $LIMBT.LegFrontNear.Y = 4 * $a1
            $LIMBT.LegFrontFar.X  = -6 * $a2
            $LIMBT.LegFrontFar.Y  = 4 * $a2
            $UI.BodyRotate.Angle = ($a1 - $a2) * 1.6 * $S.direction
            $UI.BounceTransform.Y = [Math]::Abs($ph) * -1.6
            $UI.Shadow.Opacity = 0.24
            $tailAngle = [Math]::Sin($t * 0.25) * 12
            if (($t % 40) -lt 26) { Set-Eyes "happy" } else { Set-Eyes "open" }
            $S.modeTicks--
            if ($S.modeTicks -le 0) { Go-Mode "sit" 60 }
        }
        "eat" {
            # 그릇(왼쪽)을 보고 고개를 숙여 오물오물
            if ($S.direction -ne -1) { Set-Facing -1 }
            $UI.ZzzText.Visibility = "Collapsed"
            $p = 1 - ($S.modeTicks / 150.0)
            $down = 24.0
            if ($p -lt 0.12) { $down = 24.0 * ($p / 0.12) }
            elseif ($p -gt 0.88) { $down = 24.0 * ((1 - $p) / 0.12) }
            $LIMBT.HeadGroup.Y = $down + [Math]::Sin($t * 0.9) * 2.5
            $LIMBT.HeadGroup.X = 0 - ($down * 0.4)
            $UI.BounceTransform.Y = $down * 0.1
            $UI.Shadow.Opacity = 0.26
            if (($t % 30) -lt 18) { Set-Eyes "happy" } else { Set-Eyes "open" }
            # 사료가 점점 줄어듦
            $left = 1.0 - $p
            if ($left -lt 0) { $left = 0 }
            $UI.FoodScale.ScaleY = $left
            $UI.FoodScale.ScaleX = 0.55 + 0.45 * $left
            $tailAngle = [Math]::Sin($t * 0.28) * 7
            $S.modeTicks--
            if ($S.modeTicks -le 0) {
                $UI.BowlFood.Visibility = "Collapsed"
                $UI.BowlGroup.Visibility = "Collapsed"
                $UI.FoodScale.ScaleX = 1; $UI.FoodScale.ScaleY = 1
                $LIMBT.HeadGroup.X = 0
                Play-Purr
                Start-Knead
            }
        }
        "pat" {
            # 궁디팡팡: 엉덩이 씰룩 + 꼬리 번쩍
            $UI.BodyRotate.Angle = [Math]::Sin($t * 0.9) * 4
            $UI.BounceTransform.Y = [Math]::Abs([Math]::Sin($t * 0.9)) * -3
            $LIMBT.HeadGroup.Y = [Math]::Sin($t * 0.9) * 1.5
            $UI.Shadow.Opacity = 0.26
            $tailAngle = -46 + [Math]::Sin($t * 1.4) * 8
            Set-Eyes "happy"
            $S.modeTicks--
            if ($S.modeTicks -le 0) { $S.dilate = 30; Go-Mode "sit" 70 }
        }
    }

    $UI.TailRotate.Angle = $tailAngle
})
$animTimer.Start()

# ============================================================
# 트레이
# ============================================================
function New-CatIcon {
    $bmp = New-Object System.Drawing.Bitmap 32,32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,28,28,38))
    $earL = [System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point 5,16),
        (New-Object System.Drawing.Point 8,2),
        (New-Object System.Drawing.Point 16,12))
    $earR = [System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point 16,12),
        (New-Object System.Drawing.Point 24,2),
        (New-Object System.Drawing.Point 27,16))
    $g.FillPolygon($dark, $earL)
    $g.FillPolygon($dark, $earR)
    $g.FillEllipse($dark, 2, 8, 28, 23)
    $eye = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,228,188,94))
    $g.FillEllipse($eye, 7, 15, 7, 8)
    $g.FillEllipse($eye, 18, 15, 7, 8)
    $g.FillEllipse([System.Drawing.Brushes]::Black, 9, 17, 4, 5)
    $g.FillEllipse([System.Drawing.Brushes]::Black, 20, 17, 4, 5)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = New-CatIcon
$notifyIcon.Text = "부각이"
$notifyIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
# 시스템 배율에 따라 메뉴가 과하게 커지는 걸 막기 위해 폰트를 고정한다
try {
    $menuFont = New-Object System.Drawing.Font("Malgun Gothic", 9.0, [System.Drawing.FontStyle]::Regular)
    $menu.Font = $menuFont
    $menu.ImageScalingSize = New-Object System.Drawing.Size(16, 16)
    $menu.AutoSize = $true
} catch { }
$miWork  = $menu.Items.Add("집중 시작")
$miBreak = $menu.Items.Add("휴식 시작")
$miStop  = $menu.Items.Add("타이머 정지")
$menu.Items.Add("-") | Out-Null
$miCfg   = $menu.Items.Add("시간 설정...")

# 크기 조절 (화면 배율/해상도가 달라도 원하는 크기로)
$miSize = New-Object System.Windows.Forms.ToolStripMenuItem("크기 조절")
$sizeOptions = @(
    @{ Label = "아주 작게"; Value = 0.55 },
    @{ Label = "작게";     Value = 0.70 },
    @{ Label = "보통";     Value = 0.85 },
    @{ Label = "크게";     Value = 1.00 },
    @{ Label = "아주 크게"; Value = 1.20 }
)
$sizeItems = @()
foreach ($opt in $sizeOptions) {
    $item = New-Object System.Windows.Forms.ToolStripMenuItem($opt.Label)
    $item.Tag = $opt.Value
    $item.Add_Click({
        param($snd, $ev)
        $CFG.Scale = [double]$snd.Tag
        Apply-Scale
        Save-Settings
        Refresh-SizeChecks
    })
    $miSize.DropDownItems.Add($item) | Out-Null
    $sizeItems += $item
}
$miSize.DropDownItems.Add("-") | Out-Null
$miAuto = New-Object System.Windows.Forms.ToolStripMenuItem("화면에 맞게 자동")
$miAuto.Add_Click({
    $CFG.Scale = Get-AutoScale
    Apply-Scale
    Save-Settings
    Refresh-SizeChecks
})
$miSize.DropDownItems.Add($miAuto) | Out-Null
try { $miSize.DropDown.Font = $menuFont; $miSize.DropDown.ImageScalingSize = New-Object System.Drawing.Size(16, 16) } catch { }
$menu.Items.Add($miSize) | Out-Null

$menu.Items.Add("-") | Out-Null
$miPat   = $menu.Items.Add("궁디팡팡 해주기")
$miPet   = $menu.Items.Add("쓰다듬기")
$menu.Items.Add("-") | Out-Null
$miExit  = $menu.Items.Add("부각이 재우기 (종료)")

# ---- 업데이트 알림용 메뉴 ----
$miGetNew = New-Object System.Windows.Forms.ToolStripMenuItem("새 버전 받기")
$miGetNew.Visible = $false
$miGetNew.Font = New-Object System.Drawing.Font("Malgun Gothic", 9.0, [System.Drawing.FontStyle]::Bold)
$menu.Items.Insert(0, $miGetNew) | Out-Null
$miCheckUpd = New-Object System.Windows.Forms.ToolStripMenuItem("업데이트 확인 (v" + $AppVersion + ")")
$menu.Items.Add($miCheckUpd) | Out-Null

$notifyIcon.ContextMenuStrip = $menu

function Refresh-SizeChecks {
    foreach ($it in $sizeItems) {
        $it.Checked = ([Math]::Abs([double]$it.Tag - $CFG.Scale) -lt 0.02)
    }
    $miSize.Text = "크기 조절 (" + [int]($CFG.Scale * 100) + "%)"
}

function Refresh-MenuText {
    $miWork.Text  = "집중 시작 (" + $CFG.WorkMin + "분)"
    $miBreak.Text = "휴식 시작 (" + $CFG.BreakMin + "분)"
}
Refresh-MenuText
Refresh-SizeChecks

function Start-Work {
    $S.pomoState = "work"
    $S.remaining = $CFG.WorkMin * 60
    $S.fed = $true
    $UI.BowlGroup.Visibility = "Collapsed"
    $UI.LabelBorder.Visibility = "Visible"
    Go-Mode "idle" 8
    $notifyIcon.ShowBalloonTip(3000, "집중 시간", "부각이가 식빵을 구우며 기다릴게요. (" + $CFG.WorkMin + "분)", [System.Windows.Forms.ToolTipIcon]::Info)
}

function Start-Break {
    $S.pomoState = "break"
    $S.remaining = $CFG.BreakMin * 60
    $S.fed = $false
    $UI.BowlGroup.Visibility = "Visible"
    $UI.BowlFood.Visibility = "Collapsed"
    $UI.LabelBorder.Visibility = "Visible"
    Go-Mode "sit" 90
    $S.dilate = 60
    $S.tailFlick = 34
    Play-Meow
    $notifyIcon.ShowBalloonTip(3000, "쉬는 시간", "야옹! 밥그릇을 눌러 밥을 주세요. (" + $CFG.BreakMin + "분)", [System.Windows.Forms.ToolTipIcon]::Info)
}

function Stop-Pomo {
    $S.pomoState = "stopped"
    $S.remaining = 0
    $UI.BowlGroup.Visibility = "Collapsed"
    $UI.LabelBorder.Visibility = "Collapsed"
    $notifyIcon.Text = "부각이"
    Go-Mode "idle" 15
}

$miWork.Add_Click({ Start-Work })
$miBreak.Add_Click({ Start-Break })
$miStop.Add_Click({ Stop-Pomo })
$miCfg.Add_Click({ Show-Settings; Refresh-MenuText })
$miPat.Add_Click({ Start-Pat })
$miPet.Add_Click({ Start-Knead })
$miExit.Add_Click({
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $animTimer.Stop()
    $pomoTimer.Stop()
    $window.Close()
})
$notifyIcon.Add_DoubleClick({ Start-Work })

# ============================================================
# 업데이트 확인 (새 버전이 있는지 "보기만" 하고 알려준다)
#   - 인터넷에서 코드를 받아 실행하지 않는다. version.txt 한 줄만 읽는다.
#   - 새 버전이면 알림 + 메뉴에 "새 버전 받기" 가 생기고, 누르면 브라우저로 이동
# ============================================================
$UPD_Task    = $null
$UPD_Manual  = $false
$UPD_NewVer  = ""
$UPD_Link    = ""

function Start-UpdateCheck([bool]$manual) {
    if ([string]::IsNullOrWhiteSpace($UpdateUrl)) {
        if ($manual) {
            $notifyIcon.ShowBalloonTip(4000, "업데이트 확인 불가",
                "배포 주소가 아직 설정되지 않았어요. (CatPet.ps1 의 `$UpdateUrl)",
                [System.Windows.Forms.ToolTipIcon]::Info)
        }
        return
    }
    if ($null -ne $script:UPD_Task -and -not $script:UPD_Task.IsCompleted) { return }
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("User-Agent", "BugakCat/" + $AppVersion)
        $script:UPD_Manual = $manual
        $script:UPD_Task = $wc.DownloadStringTaskAsync([Uri]$UpdateUrl)
    } catch {
        if ($manual) {
            $notifyIcon.ShowBalloonTip(4000, "업데이트 확인 실패",
                "인터넷 연결을 확인해 주세요.", [System.Windows.Forms.ToolTipIcon]::Warning)
        }
    }
}

function Finish-UpdateCheck {
    $task = $script:UPD_Task
    $script:UPD_Task = $null
    if ($task.IsFaulted -or $task.IsCanceled) {
        if ($script:UPD_Manual) {
            $notifyIcon.ShowBalloonTip(4000, "업데이트 확인 실패",
                "서버에 연결하지 못했어요.", [System.Windows.Forms.ToolTipIcon]::Warning)
        }
        return
    }
    $remoteVer = ""
    $remoteUrl = ""
    $remoteNote = ""
    try {
        # 파일 앞에 BOM 이 붙어 있으면 첫 키를 못 읽으므로 먼저 떼어낸다
        $body = ([string]$task.Result).TrimStart([char]0xFEFF)
        foreach ($line in ($body -split "`n")) {
            $kv = $line -split "=", 2
            if ($kv.Count -eq 2) {
                $k = $kv[0].Trim().Trim([char]0xFEFF); $v = $kv[1].Trim()
                if ($k -eq "version") { $remoteVer = $v }
                if ($k -eq "url")     { $remoteUrl = $v }
                if ($k -eq "note")    { $remoteNote = $v }
            }
        }
    } catch { }

    $isNewer = $false
    try { $isNewer = ([version]$remoteVer -gt [version]$AppVersion) } catch { $isNewer = $false }

    if ($isNewer) {
        $script:UPD_NewVer = $remoteVer
        $script:UPD_Link   = $remoteUrl
        $miGetNew.Text = "새 버전 받기 (v" + $remoteVer + ")"
        $miGetNew.Visible = $true
        $msg = "새 버전 v" + $remoteVer + " 이 나왔어요."
        if ($remoteNote -ne "") { $msg = $msg + "`r`n" + $remoteNote }
        $msg = $msg + "`r`n트레이 아이콘 우클릭 -> 새 버전 받기"
        $notifyIcon.ShowBalloonTip(6000, "부각이 새 버전", $msg, [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $miGetNew.Visible = $false
        if ($script:UPD_Manual) {
            $notifyIcon.ShowBalloonTip(3000, "최신 버전이에요",
                "지금 v" + $AppVersion + " 이 가장 최신입니다.", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
}

$miGetNew.Add_Click({
    if ($script:UPD_Link -ne "") {
        try { Start-Process $script:UPD_Link } catch { }
    }
})
$miCheckUpd.Add_Click({ Start-UpdateCheck $true })

# 결과 도착 확인용 타이머 (네트워크 때문에 애니메이션이 멈추지 않도록 비동기 처리)
$updTimer = New-Object System.Windows.Threading.DispatcherTimer
$updTimer.Interval = [TimeSpan]::FromSeconds(1)
$updTimer.Add_Tick({
    if ($null -ne $script:UPD_Task -and $script:UPD_Task.IsCompleted) { Finish-UpdateCheck }
})
$updTimer.Start()

# 켜고 나서 20초 뒤에 한 번 조용히 확인
$updFirst = New-Object System.Windows.Threading.DispatcherTimer
$updFirst.Interval = [TimeSpan]::FromSeconds(20)
$updFirst.Add_Tick({
    $updFirst.Stop()
    if ($CFG.UpdateCheck -eq 1) { Start-UpdateCheck $false }
})
$updFirst.Start()

# ============================================================
# 뽀모도로
# ============================================================
$pomoTimer = New-Object System.Windows.Threading.DispatcherTimer
$pomoTimer.Interval = [TimeSpan]::FromSeconds(1)
$pomoTimer.Add_Tick({
    if ($S.pomoState -eq "stopped") { return }

    $S.remaining--
    $m = [Math]::Floor($S.remaining / 60)
    $sec = $S.remaining % 60
    $lbl = "집중"
    if ($S.pomoState -eq "break") { $lbl = "휴식" }
    $ts = "{0:00}:{1:00}" -f $m, $sec
    $UI.StatusLabel.Text = "$lbl $ts"
    $notifyIcon.Text = "부각이 - $lbl $ts"

    if ($S.pomoState -eq "break" -and (-not $S.fed) -and $S.remaining -gt 0 -and ($S.remaining % 25) -eq 0) {
        Play-Meow
        $S.tailFlick = 34
    }

    if ($S.remaining -le 0) {
        if ($S.pomoState -eq "work") {
            $S.sessions++
            Start-Break
        } else {
            if (-not $S.fed) {
                $notifyIcon.ShowBalloonTip(3000, "부각이가 배고파요", "이번 휴식엔 밥을 못 줬어요.", [System.Windows.Forms.ToolTipIcon]::Warning)
            }
            Start-Work
        }
    }
})
$pomoTimer.Start()

$notifyIcon.ShowBalloonTip(4500, "부각이 도착!", "궁댕이를 누르면 궁디팡팡, 몸이나 머리를 누르면 쓰다듬기예요. 트레이 아이콘 우클릭으로 시간 설정을 할 수 있어요.", [System.Windows.Forms.ToolTipIcon]::Info)

$window.Add_Closed({ [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })
$window.Show()
[System.Windows.Threading.Dispatcher]::Run()
