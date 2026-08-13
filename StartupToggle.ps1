# ============================================================
# 부각이 - 부팅 시 자동 실행 켜기/끄기
#   이 파일을 직접 실행하지 마시고 "AutoStart.bat" 을 더블클릭하세요.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

$AppDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$VbsPath = Join-Path $AppDir "고양이_실행.vbs"
$BatPath = Join-Path $AppDir "RUN.bat"
$IcoPath = Join-Path $AppDir "부각이.ico"

$StartupDir = [Environment]::GetFolderPath('Startup')
$LnkPath    = Join-Path $StartupDir "부각이.lnk"

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

# 이미 등록돼 있으면 -> 해제할지 물어봄
if (Test-Path $LnkPath) {
    $r = Ask "부각이가 이미 부팅 시 자동으로 켜지도록 등록돼 있어요.`r`n`r`n자동 실행을 끌까요?"
    if ($r -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Remove-Item $LnkPath -Force
            Say "자동 실행을 껐습니다.`r`n`r`n앞으로는 바탕화면 아이콘이나 폴더 안의`r`n고양이_실행.vbs 로 직접 켜주세요."
        } catch {
            Say "해제하지 못했습니다.`r`n$($_.Exception.Message)"
        }
    }
    return
}

# 등록
if (-not (Test-Path $VbsPath) -and -not (Test-Path $BatPath)) {
    Say "실행 파일을 찾을 수 없습니다.`r`n압축을 푼 폴더 안에서 실행해 주세요."
    return
}

try {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($LnkPath)

    if (Test-Path $VbsPath) {
        # 창이 안 뜨는 방식 (권장)
        $lnk.TargetPath = "wscript.exe"
        $lnk.Arguments  = '"' + $VbsPath + '"'
    } else {
        $lnk.TargetPath = $BatPath
    }
    $lnk.WorkingDirectory = $AppDir
    $lnk.Description      = "부각이 - 데스크탑 고양이"
    if (Test-Path $IcoPath) { $lnk.IconLocation = $IcoPath + ",0" }
    $lnk.Save()

    Say ("이제 컴퓨터를 켜면 부각이가 자동으로 나옵니다." + "`r`n`r`n" +
         "끄고 싶으면 이 파일(AutoStart.bat)을 다시 실행하세요." + "`r`n`r`n" +
         "주의: 이 폴더를 다른 곳으로 옮기면 자동 실행이 끊깁니다." + "`r`n" +
         "옮긴 뒤에는 AutoStart.bat 을 두 번 실행해서 (해제 -> 재등록) 다시 잡아주세요.")
} catch {
    Say "등록하지 못했습니다.`r`n$($_.Exception.Message)"
}
