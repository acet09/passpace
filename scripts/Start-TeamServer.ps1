param(
    [ValidateRange(1, 65535)][int]$Port = 8080,
    [string]$ProjectDir = ''
)

$ErrorActionPreference = 'Stop'
# Server project lookup: -ProjectDir > PASSPACE_SERVER_DIR > sibling folder of this app > old default.
if (-not $ProjectDir) {
    $appParent = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $ProjectDir = @(
        $env:PASSPACE_SERVER_DIR
        (Join-Path $appParent 'passpace-develop')
        (Join-Path $appParent 'passpacehg')
        (Join-Path $appParent 'passpace')
        (Join-Path $env:USERPROFILE 'passpace11144')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'gradlew.bat') -PathType Leaf) } | Select-Object -First 1
    if (-not $ProjectDir) { $ProjectDir = Join-Path $appParent 'passpacehg' }
}
$baseUrl = "http://127.0.0.1:$Port"

function Test-TeamApi {
    try {
        $response = $http.GetAsync("$baseUrl/auth/user-info").GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -ne 401) { return $false }
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            return $body.code -eq 401 -and $body.data.code -eq 'FAILURE_JWT_VERIFIED'
        } finally { $response.Dispose() }
    } catch { return $false }
}

function Start-TeamDatabase {
    $db = Get-Service -Name 'MariaDB' -ErrorAction SilentlyContinue
    if (-not $db -or $db.Status -eq 'Running') { return }
    Write-Host 'MariaDB를 시작합니다.'
    if ($db.Status -eq 'StopPending') {
        $db.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    if ($db.Status -eq 'Stopped') {
        try { Start-Service -InputObject $db }
        catch {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $user = [Security.Principal.WindowsPrincipal]::new($identity)
            if ($user.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw }
            Write-Host 'DB를 켤 권한이 필요합니다. Windows 확인 창에서 [예]를 선택하세요.'
            $start = Start-Process -FilePath "$env:SystemRoot\System32\sc.exe" -ArgumentList 'start MariaDB' -Verb RunAs -WindowStyle Hidden -Wait -PassThru
            if ($start.ExitCode -notin 0, 1056) { throw "MariaDB를 시작하지 못했습니다 (서비스 오류 $($start.ExitCode))." }
        }
    }
    $db.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
}

function Find-Java21 {
    $candidates = @($env:JAVA_HOME)
    $dirs = @("$env:ProgramFiles\Java", "$env:ProgramFiles\Eclipse Adoptium")
    $candidates += @(Get-ChildItem -LiteralPath $dirs -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -ExpandProperty FullName)
    # JDKs downloaded by IntelliJ / Android Studio (the release file check below picks 21).
    $candidates += @(Get-ChildItem -LiteralPath "$env:USERPROFILE\.jdks" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -ExpandProperty FullName)
    $compiler = Get-Command javac.exe -ErrorAction SilentlyContinue
    if ($compiler) { $candidates += Split-Path -Parent (Split-Path -Parent $compiler.Source) }
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path -LiteralPath "$dir\bin\javac.exe") -and
            (Test-Path -LiteralPath "$dir\release") -and
            (Select-String -LiteralPath "$dir\release" -Pattern '^JAVA_VERSION="21([.+-]|")' -Quiet)) { return $dir }
    }
    throw 'Java 21 JDK를 찾지 못했습니다. JDK 21 설치 폴더를 JAVA_HOME으로 지정하고 다시 실행하세요.'
}

function Connect-UsbPhone {
    if ($Port -ne 8080) { return }
    $adb = Get-Command adb.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (-not $adb) {
        foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk")) {
            if ($sdk -and (Test-Path -LiteralPath "$sdk\platform-tools\adb.exe")) {
                $adb = "$sdk\platform-tools\adb.exe"
                break
            }
        }
    }
    if (-not $adb) { return }
    # adb -d selects a single USB device. An emulator or unplugged phone is normal.
    $ErrorActionPreference = 'Continue'
    $state = & $adb -d get-state 2>$null
    if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { return }
    & $adb -d reverse tcp:8080 tcp:8080 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host 'USB 휴대폰이 연결됐습니다. 앱의 서버 설정에서 [USB 연결]을 선택하세요.' }
    else { Write-Host 'USB 포트 연결을 설정하지 못했습니다. 휴대폰 연결 후 다시 눌러 주세요.' }
}

function Start-TeamServer {
    Start-TeamDatabase
    if (Test-TeamApi) {
        Connect-UsbPhone
        Write-Host "PASS PACE 서버가 이미 실행 중입니다.  $baseUrl/" -ForegroundColor Green
        return
    }

    $lock = [Threading.Mutex]::new($false, "Local\PassPaceTeamBoot_$Port")
    $ownsLock = $false
    try {
        try { $ownsLock = $lock.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $ownsLock = $true }
        if (-not $ownsLock) { Write-Host '다른 실행 창에서 서버를 시작하고 있습니다. 그 창에서 준비 안내를 확인하세요.'; return }
        if ([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port -contains $Port) {
            if (Test-TeamApi) { Connect-UsbPhone; Write-Host "PASS PACE 서버가 실행 중입니다.  $baseUrl/"; return }
            throw "$Port 포트를 이미 사용 중입니다. 다른 프로그램이나 시작 중인 서버를 확인하고 다시 눌러 주세요."
        }

        $wrapper = Join-Path $ProjectDir 'gradlew.bat'
        if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) { throw "팀 프로젝트를 찾지 못했습니다. 경로: $ProjectDir" }
        $env:JAVA_HOME = Find-Java21
        $env:Path = "$env:JAVA_HOME\bin;$env:Path"
        $env:SERVER_PORT = "$Port"
        Connect-UsbPhone
        Write-Host "PASS PACE 서버를 시작합니다. 준비되면 이 창에 주소가 표시됩니다." -ForegroundColor Cyan
        Push-Location -LiteralPath $ProjectDir
        try {
            $announced = $false
            & $wrapper --console=plain bootRun | ForEach-Object {
                Write-Host $_
                if (-not $announced -and $_ -match '\bStarted PasspaceApplication\b' -and (Test-TeamApi)) {
                    $announced = $true
                    Write-Host "서버 준비 완료  $baseUrl/" -ForegroundColor Green
                    Write-Host '이제 앱을 사용하세요. 서버를 쓰는 동안 이 창을 열어 두고, 종료하려면 Ctrl+C를 누르세요.'
                }
            }
            if ($LASTEXITCODE -ne 0) { throw "Spring Boot 실행이 종료됐습니다. 위의 Gradle 메시지를 확인하세요." }
        } finally { Pop-Location }
    } finally {
        if ($ownsLock) { $lock.ReleaseMutex() }
        $lock.Dispose()
    }
}

try {
    Add-Type -AssemblyName System.Net.Http
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.UseProxy = $false
    $handler.AllowAutoRedirect = $false
    $http = [Net.Http.HttpClient]::new($handler)
    $http.Timeout = [TimeSpan]::FromSeconds(2)
    $http.MaxResponseContentBufferSize = 65536
    try { Start-TeamServer } finally { $http.Dispose() }
    exit 0
} catch {
    Write-Host "실행 안내: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 1
}
