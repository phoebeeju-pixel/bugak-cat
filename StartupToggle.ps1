# ============================================================
# 부각이 - 부팅(로그인) 시 자동 실행 켜기/끄기
#   이 파일을 직접 실행하지 마시고 "AutoStart.bat" 을 더블클릭하세요.
#
#   작업 스케줄러에 등록합니다. 시작프로그램 폴더보다 튼튼해요:
#     · 작업관리자에서 실수로 비활성화될 일이 없음
#     · 로그인 후 20초 뒤에 실행해서 바탕화면이 준비된 뒤에 뜸
#     · 폴더를 옮겨도 여기서 다시 잡아줄 수 있음
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

$AppDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$VbsPath = Join-Path $AppDir "고양이_실행.vbs"
$Ps1Path = Join-Path $AppDir "CatPet.ps1"
$TaskName = "BugakCat"

$StartupDir = [Environment]::GetFolderPath('Startup')
$OldLnk     = Join-Path $StartupDir "부각이.lnk"

function Say([string]$msg, [string]$title = "부각이 자동 실행") {
    [System.Windows.Forms.MessageBox]::Show($msg, $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
function Ask([string]$msg, [string]$title = "부각이 자동 실행") {
    return [System.Windows.Forms.MessageBox]::Show($msg, $title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
}

# ---------- 현재 등록 상태 ----------
function Get-Task {
    try { return Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { return $null }
}
function Get-TaskPath {
    $t = Get-Task
    if ($null -eq $t) { return "" }
    try { return ($t.Actions | Select-Object -First 1).Arguments.Trim('"') } catch { return "" }
}

# ---------- 등록 ----------
function Register-Autostart {
    # 예전 방식(시작프로그램 폴더)이 남아 있으면 정리
    if (Test-Path $OldLnk) { try { Remove-Item $OldLnk -Force } catch { } }

    $action = New-ScheduledTaskAction -Execute "wscript.exe" `
                -Argument ('"' + $VbsPath + '"') -WorkingDirectory $AppDir

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    try { $trigger.Delay = "PT20S" } catch { }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                  -DontStopIfGoingOnBatteries -StartWhenAvailable `
                  -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Description "부각이 - 데스크탑 고양이 자동 실행" -Force -ErrorAction Stop | Out-Null
}

# 작업 스케줄러가 막혀 있을 때를 위한 예비책
function Register-Fallback {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($OldLnk)
    $lnk.TargetPath       = "wscript.exe"
    $lnk.Arguments        = '"' + $VbsPath + '"'
    $lnk.WorkingDirectory = $AppDir
    $lnk.Description      = "부각이 - 데스크탑 고양이"
    $ico = Join-Path $AppDir "부각이.ico"
    if (Test-Path $ico) { $lnk.IconLocation = $ico + ",0" }
    $lnk.Save()
}

function Unregister-Autostart {
    $ok = $true
    try { if ($null -ne (Get-Task)) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop } }
    catch { $ok = $false }
    if (Test-Path $OldLnk) { try { Remove-Item $OldLnk -Force } catch { $ok = $false } }
    return $ok
}

# ============================================================
# 시작
# ============================================================
if (-not (Test-Path $VbsPath)) {
    Say "실행 파일(고양이_실행.vbs)을 찾을 수 없습니다.`r`n압축을 푼 폴더 안에서 AutoStart.bat 을 실행해 주세요."
    return
}

$task     = Get-Task
$oldLnkOn = Test-Path $OldLnk
$registered = ($null -ne $task) -or $oldLnkOn

if ($registered) {
    # 지금 어디를 가리키고 있는지 (작업 스케줄러 우선, 없으면 시작프로그램 바로가기)
    $curPath = ""
    if ($null -ne $task) {
        $curPath = Get-TaskPath
    } elseif ($oldLnkOn) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $curPath = $ws.CreateShortcut($OldLnk).Arguments.Trim('"')
        } catch { }
    }

    # 폴더를 옮겨서 연결이 끊긴 경우에만 다시 등록을 권한다
    $needFix = ($curPath -ne $VbsPath)

    if ($needFix) {
        $r = Ask ("자동 실행이 등록돼 있는데 연결이 어긋나 있어요." + "`r`n`r`n" +
                  "지금 위치: " + $AppDir + "`r`n" +
                  "등록된 곳: " + $(if ($curPath -eq "") { "(옛날 방식)" } else { $curPath }) + "`r`n`r`n" +
                  "지금 이 폴더 기준으로 다시 등록할까요?")
        if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Register-Autostart
                Say "다시 등록했습니다.`r`n이제 컴퓨터를 켜면 부각이가 나옵니다."
            } catch {
                try { Register-Fallback; Say "작업 스케줄러가 막혀 있어 예비 방식으로 등록했습니다." }
                catch { Say "등록하지 못했습니다.`r`n$($_.Exception.Message)" }
            }
        }
        return
    }

    $r = Ask "부각이가 이미 부팅 시 자동으로 켜지도록 등록돼 있어요.`r`n`r`n자동 실행을 끌까요?"
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
        if (Unregister-Autostart) {
            Say "자동 실행을 껐습니다.`r`n`r`n앞으로는 폴더 안의 고양이_실행.vbs 로 직접 켜주세요."
        } else {
            Say "일부를 지우지 못했습니다. 다시 시도해 주세요."
        }
    }
    return
}

# ---------- 새로 등록 ----------
try {
    Register-Autostart
    $check = Get-Task
    if ($null -eq $check) { throw "등록 확인 실패" }
    Say ("이제 컴퓨터를 켜면 부각이가 자동으로 나옵니다." + "`r`n" +
         "(로그인하고 20초쯤 뒤에 나타나요)" + "`r`n`r`n" +
         "끄고 싶으면 AutoStart.bat 을 다시 실행하세요." + "`r`n`r`n" +
         "폴더를 옮겼다면 옮긴 폴더에서 AutoStart.bat 을 한 번 실행하면 다시 잡힙니다.")
} catch {
    try {
        Register-Fallback
        Say ("작업 스케줄러 등록이 막혀 있어 예비 방식(시작프로그램 폴더)으로 등록했습니다." + "`r`n`r`n" +
             "끄고 싶으면 AutoStart.bat 을 다시 실행하세요.")
    } catch {
        Say "등록하지 못했습니다.`r`n$($_.Exception.Message)"
    }
}
