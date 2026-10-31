# 第7回ライブ「商談カンペAI」事前準備
# 受講生は Claude Code に頼んで実行してもらう：  powershell -NoProfile -Command "irm <このファイルのURL> | iex"
#
# 上から順に確認して、足りないものだけ入れる（初回3〜5分。2回目以降はすぐ終わる）
#   ① Python        … 無ければ入れる（このユーザーだけに入れるので、管理者の許可は要らない）
#   ② 部品          … faster-whisper（文字起こし）と PyAudioWPatch（パソコンの音を拾う）
#   ③ 文字起こしAI  … small（約480MB）を先にダウンロードし、短い日本語で試す
#   ④ パソコンの音  … スピーカーの音を拾えるか
#   ⑤ ターミナル版の Claude Code … 作るアプリが中で claude -p を呼ぶので要る（デスクトップアプリとは別物・ログインも別）
#                    無ければ公式の方法で入れ、ログインがまだならログイン用の画面を開く。できなければライブで一緒にやる
# パソコンの設定は変えない。途中で止まったら、その画面を撮って講師に送ってもらう。

& {
    $start = Get-Date
    $tmp = Join-Path $env:TEMP 'live7-setup'
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $env:HF_HUB_DISABLE_SYMLINKS_WARNING = '1'

    function Step($text) { Write-Host ''; Write-Host "■ $text" -ForegroundColor Cyan }
    function Ok($text) { Write-Host "  [OK] $text" -ForegroundColor Green }
    function Ng($what, $how) {
        Write-Host ''
        Write-Host "  [NG] $what で止まりました" -ForegroundColor Red
        Write-Host "  $how" -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Claude Code に「どうすればいい？」と聞いてください。直らなければ、この画面のスクリーンショットを撮って、LMSの質問から講師に送ってください。' -ForegroundColor Yellow
    }
    function Find-Python {
        foreach ($cmd in 'py', 'python') {
            if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { continue }
            $ver = & $cmd -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver) { return @{ Cmd = $cmd; Ver = "$ver".Trim() } }
        }
    }

    Write-Host '第7回ライブ（商談カンペAI）の事前準備を始めます。初めてなら3〜5分かかります。' -ForegroundColor Cyan

    # ---- ① Python ----
    Step '① Python'
    $py = Find-Python
    if (-not $py) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Ng 'Python' 'Python を自動で入れられませんでした。https://www.python.org/downloads/ から入れて（最初の画面で「Add python.exe to PATH」にチェック）、もう一度この1行を実行してください。'
            return
        }
        Write-Host '  Python が入っていないので入れます（1〜2分）'
        winget install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements --override 'InstallAllUsers=0 InstallLauncherAllUsers=0 PrependPath=1 Include_test=0 /quiet'
        # 入れた Python をこの画面でもすぐ使えるようにする
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        $py = Find-Python
        if (-not $py) {
            Ng 'Python' 'Python を入れたあと見つけられませんでした。ターミナルを閉じて開き直し、もう一度この1行を実行してください。'
            return
        }
    }
    Ok "Python $($py.Ver)"

    # ---- ② 部品 ----
    Step '② 部品（文字起こし・パソコンの音を拾う）を入れます…1〜3分'
    Write-Host '  画面が止まって見えても動いています。そのまま待ってください'
    & $py.Cmd -m pip install -q --disable-pip-version-check faster-whisper pyaudiowpatch
    if ($LASTEXITCODE -ne 0) {
        Ng '部品のインストール' "Python $($py.Ver) に部品を入れられませんでした。上の英語のエラーも写るようにスクリーンショットを撮ってください。"
        return
    }
    Ok '部品'

    # ---- ③ 文字起こしAI ----
    Step '③ 文字起こしAI（small・約480MB）をダウンロードして試します…1〜5分'
    # 試し用の日本語音声を、Windows の読み上げ機能で作る（読み上げの声が無いPCでは、ダウンロードだけ確かめる）
    $wav = Join-Path $tmp 'test.wav'
    Remove-Item $wav -ErrorAction SilentlyContinue
    try {
        Add-Type -AssemblyName System.Speech
        $tts = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $voice = $tts.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq 'ja-JP' } | Select-Object -First 1
        if ($voice) {
            $tts.SelectVoice($voice.VoiceInfo.Name)
            $tts.SetOutputToWaveFile($wav)
            $tts.Speak('本日はよろしくお願いします。予算は50万円以内です。')
        }
        $tts.Dispose()
    } catch { }

    $check = Join-Path $tmp 'check.py'
    Set-Content -Path $check -Encoding UTF8 -Value @'
import sys, time

if sys.argv[1] == 'model':
    t = time.time()
    from faster_whisper import WhisperModel
    model = WhisperModel('small', device='cpu', compute_type='int8')
    print('  文字起こしAIを読み込みました（%.0f秒）' % (time.time() - t))
    try:
        import wave
        with wave.open(sys.argv[2]) as w:
            sec = w.getnframes() / w.getframerate()
    except Exception:
        sys.exit(0)   # 試し用の音声が無いときは、読み込めたことだけ確かめる
    segs, _ = model.transcribe(sys.argv[2], language='ja')
    text = ''.join(s.text for s in segs).strip()
    print('  試しに文字にした結果：' + text)
    if not text:
        sys.exit(3)

elif sys.argv[1] == 'loopback':
    import pyaudiowpatch as pyaudio
    p = pyaudio.PyAudio()
    try:
        dev = p.get_default_wasapi_loopback()
    except Exception as e:
        print('  ' + str(e))
        sys.exit(4)
    print('  音を拾う場所：' + dev['name'])
    p.terminate()
'@

    & $py.Cmd $check model $wav
    if ($LASTEXITCODE -ne 0) {
        Ng '文字起こしAI' 'ダウンロードか試しの文字起こしに失敗しました。ネットにつながっているか確かめて、もう一度この1行を実行してください。'
        return
    }
    Ok '文字起こしAI'

    # ---- ④ パソコンの音 ----
    Step '④ パソコンの音を拾えるか確かめます'
    & $py.Cmd $check loopback
    if ($LASTEXITCODE -ne 0) {
        Ng 'パソコンの音' 'スピーカー（またはイヤホン）が見つかりませんでした。音が出る機器をつないでから、もう一度この1行を実行してください。'
        return
    }
    Ok 'パソコンの音'

    # ---- ⑤ ターミナル版の Claude Code ----
    # 作るアプリは中で「claude -p」を呼ぶので、デスクトップアプリとは別にターミナル版が要る。ログインも別。
    # ここで止めずに、できなかったものは「ライブで一緒にやる」に回す
    Step '⑤ ターミナル版の Claude Code（作るアプリが中で使います）'
    $later = $null
    $env:Path = $env:Path + ';' + (Join-Path $HOME '.local\bin')
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Host '  ターミナル版が入っていないので、公式の方法で入れます（1分ほど）'
        powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://claude.ai/install.ps1 | iex"
    }
    function Ask-Claude {
        Push-Location $tmp
        $out = & claude -p 'Reply with just OK' --model haiku --output-format json --setting-sources project --strict-mcp-config --tools Read 2>&1 | Out-String
        Pop-Location
        return $out
    }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        $later = 'ターミナル版の Claude Code を入れる'
    } else {
        $out = Ask-Claude
        if ($out -match 'git-bash|git bash') {
            $later = 'ターミナル版の Claude Code に必要な Git を入れる'
        } elseif ($out -notmatch '"is_error"\s*:\s*false') {
            # ログイン済みになったら認証ファイルが書き換わるので、それを待つ
            $cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
            $cred = Join-Path $cfg '.credentials.json'
            $before = if (Test-Path $cred) { (Get-Item $cred).LastWriteTime } else { $null }
            Write-Host '  ターミナル版のログインがまだなので、ログイン用の画面を開きます。' -ForegroundColor Yellow
            Write-Host '    1. 新しく開いた黒い画面で、聞かれたことに Enter で答えていく'
            Write-Host '    2. ログイン方法は「Claude account with subscription」を選ぶ'
            Write-Host '    3. ブラウザが開いたら「承認（Authorize）」を押す'
            Write-Host '    4. ログインできたら、その黒い画面は閉じてOK'
            Start-Process powershell -WorkingDirectory $tmp -ArgumentList '-NoExit', '-Command', 'claude'
            $wait = if ($env:LIVE7_LOGIN_WAIT) { [int]$env:LIVE7_LOGIN_WAIT } else { 300 }
            $deadline = (Get-Date).AddSeconds($wait)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 3
                if ((Test-Path $cred) -and ((Get-Item $cred).LastWriteTime -ne $before)) { Start-Sleep -Seconds 2; break }
            }
            if ((Ask-Claude) -notmatch '"is_error"\s*:\s*false') { $later = 'ターミナル版の Claude Code にログインする' }
        }
    }
    if ($later) {
        Write-Host "  [あとで] $later（ライブで一緒にやるので、このままで大丈夫です）" -ForegroundColor Yellow
    } else {
        Ok 'ターミナル版の Claude Code'
    }

    $took = (Get-Date) - $start
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Green
    Write-Host '  準備OK！ ライブ当日はこのままで大丈夫です' -ForegroundColor Green
    if ($later) { Write-Host "  （「$later」だけは、ライブで一緒にやります）" -ForegroundColor Green }
    Write-Host ('  （かかった時間：{0}分{1}秒）' -f [int][math]::Floor($took.TotalMinutes), $took.Seconds) -ForegroundColor Green
    Write-Host '========================================' -ForegroundColor Green
}
