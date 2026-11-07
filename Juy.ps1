# ==============================================================================
# Windows System Diagnostic - Internal Tool (3D Web UI Control Center v2.8)
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- INTERNAL SYSTEM ENGINE & 3D WEB SERVER (C#) ---
$cSharpCode = @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.IO;
using System.Net;
using System.Text;
using System.Diagnostics;

public class WinSystemCore {
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("kernel32.dll")] public static extern bool ReadProcessMemory(IntPtr hProc, IntPtr baseAddr, byte[] buffer, int size, out int read);
    [DllImport("kernel32.dll")] public static extern bool WriteProcessMemory(IntPtr hProc, IntPtr baseAddr, byte[] buffer, int size, out int written);
    [DllImport("kernel32.dll")] public static extern bool VirtualProtectEx(IntPtr hProc, IntPtr addr, int size, uint newProt, out uint oldProt);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] public static extern int VirtualQueryEx(IntPtr hProc, IntPtr addr, out MEM_INFO info, int len);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("kernel32.dll")] public static extern void Beep(int freq, int dur);
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    public struct MEM_INFO { public IntPtr Base; public IntPtr AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State; public uint Protect; public uint Type; }

    public static IntPtr SystemStatus = IntPtr.Zero;

    // Web UI Synchronized State
    public static string webAction = "none";
    public static string webMode = "toggle";
    public static string webHotkey = "CAPS";
    public static bool webArmed = false;
    public static bool dataUpdated = false;

    private static void BuildPatternBuffer(byte[] pattern, bool[] mask, int[] last) {
        for (int i = 0; i < 256; i++) last[i] = -1;
        for (int i = 0; i < pattern.Length; i++) if (mask[i]) last[pattern[i]] = i;
    }

    private static IntPtr QueryBuffer(byte[] buf, int bufSize, IntPtr baseAddr, byte[] pat, bool[] mask, int[] last) {
        int m = pat.Length;
        if (bufSize < m) return IntPtr.Zero;
        int i = 0;
        while (i <= bufSize - m) {
            int j = m - 1;
            for (; j >= 0; j--) {
                if (!mask[j]) continue;
                if (buf[i + j] != pat[j]) break;
            }
            if (j < 0) return new IntPtr(baseAddr.ToInt64() + i);
            int lo = last[buf[i + j]];
            int shift = j - lo;
            i += (shift < 1) ? 1 : shift;
        }
        return IntPtr.Zero;
    }

    public static IntPtr QuerySystemData(IntPtr hProc, byte[] pattern, bool[] mask) {
        SystemStatus = IntPtr.Zero;
        var regions = new List<MEM_INFO>();
        IntPtr addr = IntPtr.Zero;
        while (true) {
            MEM_INFO mbi;
            if (VirtualQueryEx(hProc, addr, out mbi, Marshal.SizeOf(typeof(MEM_INFO))) == 0) break;
            if (mbi.State == 0x1000 && (mbi.Protect & 0x100) == 0 && (mbi.Protect & 0x66) != 0) regions.Add(mbi);
            long next = mbi.Base.ToInt64() + mbi.RegionSize.ToInt64();
            if (next <= addr.ToInt64()) break;
            addr = new IntPtr(next);
        }

        int[] last = new int[256];
        BuildPatternBuffer(pattern, mask, last);
        int blockSize = 1024 * 1024;

        Parallel.ForEach(regions, (r, state) => {
            if (SystemStatus != IntPtr.Zero) state.Stop();
            byte[] buffer = new byte[blockSize + pattern.Length];
            long regionSize = r.RegionSize.ToInt64();
            for (long offset = 0; offset < regionSize; offset += blockSize) {
                if (SystemStatus != IntPtr.Zero) break;
                int toRead = (int)Math.Min(blockSize + pattern.Length, regionSize - offset);
                int read;
                if (ReadProcessMemory(hProc, new IntPtr(r.Base.ToInt64() + offset), buffer, toRead, out read)) {
                    IntPtr found = QueryBuffer(buffer, read, new IntPtr(r.Base.ToInt64() + offset), pattern, mask, last);
                    if (found != IntPtr.Zero) { SystemStatus = found; state.Stop(); }
                }
            }
        });
        return SystemStatus;
    }

    public static void SetCompactMode() {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd == IntPtr.Zero) return;
        SetWindowPos(hWnd, new IntPtr(-1), 0, 0, 800, 600, 0x0002);
    }

    // --- 3D WEB CONTROL CENTER SERVER ---
    public static void StartControlPanelServer(int port = 8080) {
        string url = "http://localhost:" + port + "/";
        HttpListener listener = new HttpListener();
        listener.Prefixes.Add(url);
        listener.Start();

        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });

        Task.Run(() => {
            try {
                while (true) {
                    HttpListenerContext context = listener.GetContext();
                    HttpListenerRequest request = context.Request;
                    HttpListenerResponse response = context.Response;

                    if (request.HttpMethod == "POST") {
                        using (StreamReader reader = new StreamReader(request.InputStream, request.ContentEncoding)) {
                            string json = reader.ReadToEnd();
                            ParseAndUpdateConfig(json);
                        }

                        byte[] buffer = Encoding.UTF8.GetBytes("{\"status\":\"ok\"}");
                        response.ContentType = "application/json";
                        response.ContentLength64 = buffer.Length;
                        response.OutputStream.Write(buffer, 0, buffer.Length);
                        response.OutputStream.Close();
                    } else {
                        byte[] buffer = Encoding.UTF8.GetBytes(GetHtmlUI());
                        response.ContentType = "text/html; charset=utf-8";
                        response.ContentLength64 = buffer.Length;
                        response.OutputStream.Write(buffer, 0, buffer.Length);
                        response.OutputStream.Close();
                    }
                }
            } catch {}
        });
    }

    private static void ParseAndUpdateConfig(string json) {
        if (json.Contains("\"action\":\"scan\"")) webAction = "scan";
        else if (json.Contains("\"action\":\"restore\"")) webAction = "restore";
        else if (json.Contains("\"action\":\"clear\"")) webAction = "clear";
        else webAction = "none";

        if (json.Contains("\"mode\":\"hold\"")) webMode = "hold";
        else webMode = "toggle";

        foreach (string k in new[] { "CAPS", "SHIFT", "CTRL", "ALT", "F", "E", "Q", "X" }) {
            if (json.Contains("\"hotkey\":\"" + k + "\"")) webHotkey = k;
        }

        webArmed = json.Contains("\"armed\":true");
        dataUpdated = true;
    }

    private static string GetHtmlUI() {
        return @"<!DOCTYPE html>
<html lang=""th"">
<head>
<meta charset=""utf-8""/>
<title>NEVERS - 3D Control Center</title>
<link href=""https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@400;500;600&display=swap"" rel=""stylesheet""/>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh; background: #0A001A; color: #f7f1ff;
    font-family: 'IBM Plex Sans Thai', sans-serif;
    display: flex; justify-content: center; align-items: center; overflow: hidden;
    perspective: 1200px;
  }
  .aurora {
    position: fixed; width: 450px; height: 450px; background: rgba(51, 0, 85, 0.6);
    border-radius: 50%; filter: blur(90px); top: -120px; left: -120px; animation: float 10s infinite alternate;
  }
  .aurora2 {
    position: fixed; width: 450px; height: 450px; background: rgba(76, 29, 149, 0.45);
    border-radius: 50%; filter: blur(90px); bottom: -120px; right: -120px; animation: float 12s infinite alternate-reverse;
  }
  @keyframes float { 0% { transform: translate(0,0); } 100% { transform: translate(60px, 60px); } }
  
  .card3d {
    position: relative; width: 420px; background: rgba(22, 12, 36, 0.85);
    border: 1px solid rgba(216, 180, 254, 0.25); border-radius: 32px; padding: 30px;
    box-shadow: 0 35px 100px rgba(0,0,0,0.85), inset 0 1px 0 rgba(255,255,255,0.15);
    backdrop-filter: blur(25px); transform-style: preserve-3d; transition: transform 0.1s ease;
  }
  h1 { text-align: center; font-size: 13px; letter-spacing: 0.4em; color: #c4b0e4; margin: 0 0 20px; text-shadow: 0 0 10px rgba(196,176,228,0.5); }
  
  .stage-btn {
    width: 150px; height: 150px; margin: 0 auto 15px; border-radius: 50%;
    background: radial-gradient(circle, rgba(51, 0, 85, 0.7) 0%, rgba(10, 0, 26, 0.95) 70%);
    border: 2px solid rgba(216, 180, 254, 0.4); display: flex; flex-direction: column;
    justify-content: center; align-items: center; cursor: pointer; position: relative;
    box-shadow: 0 15px 35px rgba(51, 0, 85, 0.6); transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  }
  .stage-btn:hover { transform: scale(1.06) translateZ(20px); border-color: #d8b4fe; box-shadow: 0 20px 45px rgba(51, 0, 85, 0.8); }
  .stage-btn.on { background: radial-gradient(circle, rgba(107, 33, 168, 0.9) 0%, rgba(35, 10, 65, 0.98) 70%); border-color: #c084fc; box-shadow: 0 0 40px rgba(107,33,168,0.9); }
  .word { font-size: 24px; font-weight: 600; color: #fff; text-shadow: 0 0 10px rgba(255,255,255,0.6); }
  .hint { font-size: 11px; color: #c4b0e4; margin-top: 4px; }

  .label { font-size: 12px; color: #c4b0e4; margin: 15px 0 8px; font-weight: 500; }
  .segment { display: grid; grid-template-columns: 1fr 1fr; background: rgba(255,255,255,0.05); border-radius: 99px; padding: 4px; border: 1px solid rgba(255,255,255,0.05); }
  .segment button { background: transparent; border: none; color: #c4b0e4; padding: 8px; font-weight: 500; border-radius: 99px; cursor: pointer; transition: 0.3s; font-family: inherit; }
  .segment button.active { background: linear-gradient(135deg, #330055, #6b21a8); color: #fff; box-shadow: 0 4px 15px rgba(51,0,85,0.7); }

  .keys { display: grid; grid-template-columns: repeat(4, 1fr); gap: 6px; }
  .keys button { background: rgba(255,255,255,0.04); border: 1px solid rgba(216,180,254,0.1); color: #c4b0e4; padding: 8px; border-radius: 10px; cursor: pointer; font-size: 12px; transition: 0.2s; font-family: inherit; }
  .keys button.active { background: #330055; color: #fff; border-color: #d8b4fe; box-shadow: 0 0 15px rgba(51,0,85,0.8); }

  .actions { display: grid; grid-template-columns: 1fr; gap: 8px; margin-top: 20px; }
  .action-btn {
    padding: 12px; border-radius: 14px; border: none; font-weight: 600; cursor: pointer; font-size: 13px;
    transition: all 0.2s; display: flex; align-items: center; justify-content: center; gap: 8px; font-family: inherit;
  }
  .btn-scan { background: linear-gradient(135deg, #10b981, #059669); color: #fff; box-shadow: 0 5px 20px rgba(16, 185, 129, 0.35); }
  .btn-restore { background: linear-gradient(135deg, #f59e0b, #d97706); color: #fff; box-shadow: 0 5px 20px rgba(245, 158, 11, 0.35); }
  .btn-clear { background: rgba(255,255,255,0.08); color: #c4b0e4; border: 1px solid rgba(255,255,255,0.1); }
  .action-btn:hover { transform: translateY(-2px) translateZ(10px); filter: brightness(1.15); }
  .toast { margin-top: 12px; text-align: center; font-size: 12px; color: #a78bfa; min-height: 18px; font-weight: 500; }
</style>
</head>
<body>
  <div class=""aurora""></div>
  <div class=""aurora2""></div>
  <div class=""card3d"" id=""card"">
    <h1>NEVERS 3D CONTROL CENTER</h1>
    
    <div id=""stageBtn"" class=""stage-btn"">
      <div id=""stateText"" class=""word"">ปิดอยู่</div>
      <div id=""hintText"" class=""hint"">คลิกเพื่อสลับ</div>
    </div>

    <div class=""label"">โหมดการทำงาน</div>
    <div class=""segment"" id=""modeSeg"">
      <button type=""button"" data-mode=""toggle"" class=""active"">กดสลับ (Toggle)</button>
      <button type=""button"" data-mode=""hold"">กดค้าง (Hold)</button>
    </div>

    <div class=""label"">ปุ่มลัด (Hotkey)</div>
    <div class=""keys"" id=""keys""></div>

    <div class=""actions"">
      <button type=""button"" class=""action-btn btn-scan"" onclick=""sendAction('scan')"">🚀 รันระบบ (Scan & Run)</button>
      <button type=""button"" class=""action-btn btn-restore"" onclick=""sendAction('restore')"">🔄 คืนค่าแรมเดิม (Restore)</button>
      <button type=""button"" class=""action-btn btn-clear"" onclick=""sendAction('clear')"">🗑️ ล้างประวัติ (Clear History)</button>
    </div>
    <div id=""toast"" class=""toast""></div>
  </div>

<script>
  const state = { mode: ""toggle"", hotkey: ""CAPS"", armed: false };
  const keys = [""CAPS"", ""SHIFT"", ""CTRL"", ""ALT"", ""F"", ""E"", ""Q"", ""X""];

  const keysContainer = document.getElementById(""keys"");
  keys.forEach(k => {
    const btn = document.createElement(""button"");
    btn.textContent = k;
    if(k === state.hotkey) btn.classList.add(""active"");
    btn.onclick = () => {
      state.hotkey = k;
      updateUI();
      syncState();
    };
    keysContainer.appendChild(btn);
  });

  document.querySelectorAll(""#modeSeg button"").forEach(b => {
    b.onclick = () => {
      document.querySelectorAll(""#modeSeg button"").forEach(x => x.classList.remove(""active""));
      b.classList.add(""active"");
      state.mode = b.dataset.mode;
      updateUI();
      syncState();
    };
  });

  document.getElementById(""stageBtn"").onclick = () => {
    state.armed = !state.armed;
    updateUI();
    syncState();
  };

  function updateUI() {
    const stage = document.getElementById(""stageBtn"");
    const txt = document.getElementById(""stateText"");
    const hint = document.getElementById(""hintText"");
    if(state.armed) {
      stage.classList.add(""on"");
      txt.textContent = ""เปิดอยู่"";
    } else {
      stage.classList.remove(""on"");
      txt.textContent = ""ปิดอยู่"";
    }
    hint.textContent = (state.mode === ""hold"" ? ""กดค้าง "" : ""กด "") + state.hotkey;

    document.querySelectorAll("".keys button"").forEach(b => {
      b.classList.toggle(""active"", b.textContent === state.hotkey);
    });
  }

  function syncState(action = ""none"") {
    fetch(""/"", {
      method: ""POST"",
      headers: { ""Content-Type"": ""application/json"" },
      body: JSON.stringify({ ...state, action: action })
    }).catch(err => console.log(err));
  }

  function sendAction(act) {
    syncState(act);
    const toast = document.getElementById(""toast"");
    if(act === ""scan"") toast.textContent = ""[*] ส่งคำสั่งสแกนและรันระบบแล้ว (Scan)..."";
    if(act === ""restore"") toast.textContent = ""[+] ส่งคำสั่งคืนค่าแรมแล้ว (Restore)..."";
    if(act === ""clear"") toast.textContent = ""[+] ส่งคำสั่งล้างประวัติแล้ว (Clear)..."";
    setTimeout(() => toast.textContent = """", 3500);
  }

  const card = document.getElementById(""card"");
  document.addEventListener(""mousemove"", (e) => {
    const rect = card.getBoundingClientRect();
    const x = e.clientX - (rect.left + rect.width/2);
    const y = e.clientY - (rect.top + rect.height/2);
    card.style.transform = `rotateX(${-y/22}deg) rotateY(${x/22}deg)`;
  });
  document.addEventListener(""mouseleave"", () => {
    card.style.transform = ""rotateX(0) rotateY(0)"";
  });
</script>
</body>
</html>";
    }
}
"@

# [3] Safe Compile C# Class with Valid Assembly References
try {
    if (-not ([System.Management.Automation.PSTypeName]"WinSystemCore").Type) {
        Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System", "System.Core", "System.Runtime.InteropServices" -ErrorAction Stop
    }
} catch {
    Write-Host "[-] Error compiling C# Engine: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Exit
}

# [4] Stealth Helper Functions
function Get-DecodedString($base64) {
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
}

$pName1 = Get-DecodedString "Rml2ZU1fR1RBUHJvY2Vzcw==" # FiveM
$pName2 = Get-DecodedString "R1RBUHJvY2Vzcw=="      # GTA

# [5] Start 3D Web UI Server Immediately
try {
    [WinSystemCore]::SetCompactMode()
    [WinSystemCore]::StartControlPanelServer(8080)
} catch {
    Write-Host "[-] Failed to start Web Server: $_" -ForegroundColor Red
}

Clear-Host
Write-Host "------------------------------------" -ForegroundColor Red
Write-Host " IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" -ForegroundColor Green
Write-Host " ----------------------------------" -ForegroundColor DarkGray
Write-Host "   Protection by MUGDEVELOPE" -ForegroundColor Cyan
Write-Host "   STATUS: 3D WEB CONTROL CENTER READY" -ForegroundColor White
Write-Host " ----------------------------------" -ForegroundColor DarkGray
Write-Host " [+] 3D Web UI opened in browser automatically!" -ForegroundColor Green
Write-Host " [+] Control everything smoothly from the browser." -ForegroundColor Cyan
Write-Host " [+] Press [END] or [F12] to exit." -ForegroundColor DarkGray

# [6] Robust Path Resolution (Fixing PSScriptRoot empty bug)
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptDir)) {
    if ($MyInvocation.MyCommand.Definition) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    }
}
if ([string]::IsNullOrEmpty($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

$offsetPath = Join-Path $scriptDir "offset.txt"
if ($offsetPath -and (Test-Path $offsetPath)) {
    . $offsetPath
}

if ($null -eq $pattern) { $pattern = [byte[]] @(0x0F, 0x28, 0x4F, 0x60, 0x0F, 0x29, 0x95, 0xD0, 0x00, 0x00, 0x00, 0xF3) }
if ($null -eq $mask) { $mask = [bool[]] @($true, $true, $true, $true, $true, $true, $true, $true, $true, $true, $true, $true) }
if ($null -eq $patch) { $patch = [byte[]] @(0x0F, 0x28, 0x5F, 0x60, 0x0F, 0x29, 0x95, 0xD0, 0x00, 0x00, 0x00, 0xF3) }

$ghostXPatchDef = @{ Name = "GHOSTX"; Pattern = $pattern; Mask = $mask; Patch = $patch; Address = [IntPtr]::Zero; OrigBytes = $null }
$patchesToApply = @($ghostXPatchDef)

$hProc = [IntPtr]::Zero
$isPatched = $false
$toggle = $false
$wasKeyDown = $false
$mode = "1"
$userKey = 0x14
$hotkeyName = "CAPS"

# --- MAIN LOOP ---
try {
    while ($true) {
        if ([WinSystemCore]::dataUpdated) {
            [WinSystemCore]::dataUpdated = $false
            $action = [WinSystemCore]::webAction
            $mode = if ([WinSystemCore]::webMode -eq "hold") { "2" } else { "1" }
            $hotkeyName = [WinSystemCore]::webHotkey
            $toggle = [bool][WinSystemCore]::webArmed

            switch ($hotkeyName) {
                "CAPS"  { $userKey = 0x14 }
                "SHIFT" { $userKey = 0xA0 }
                "CTRL"  { $userKey = 0xA2 }
                "ALT"   { $userKey = 0xA4 }
                "F"     { $userKey = 70 }
                "E"     { $userKey = 69 }
                "Q"     { $userKey = 81 }
                "X"     { $userKey = 88 }
                default { $userKey = 0x14; $hotkeyName = "CAPS" }
            }

            if ($action -eq "scan") {
                [WinSystemCore]::webAction = "none"
                Write-Host "  [*] [WEB UI] INITIALIZING SCAN & RUN..." -ForegroundColor Yellow
                $proc = Get-Process | Where-Object { $_.ProcessName -match "$pName1|$pName2" } | Select-Object -First 1
                if ($proc) {
                    if ($hProc -ne [IntPtr]::Zero) { [WinSystemCore]::CloseHandle($hProc) | Out-Null }
                    $hProc = [WinSystemCore]::OpenProcess(0x1F0FFF, $false, $proc.Id)

                    $foundAny = $false
                    foreach ($p in $patchesToApply) {
                        Write-Host "  [*] Scanning for $($p.Name)..." -ForegroundColor Gray
                        $addr = [WinSystemCore]::QuerySystemData($hProc, $p.Pattern, $p.Mask)
                        if ($addr -ne [IntPtr]::Zero) {
                            $p.Address = $addr
                            $p.OrigBytes = New-Object byte[] $p.Patch.Length
                            [int]$read = 0
                            [WinSystemCore]::ReadProcessMemory($hProc, $addr, $p.OrigBytes, $p.OrigBytes.Length, [ref]$read) | Out-Null
                            Write-Host "  [+] Found $($p.Name) at 0x$($addr.ToString('X'))" -ForegroundColor Green
                            $foundAny = $true
                        }
                    }

                    if ($foundAny) {
                        Write-Host "  [+] INJECTION SUCCESSFUL!" -ForegroundColor Green
                        [WinSystemCore]::Beep(1000, 200) | Out-Null
                    } else {
                        Write-Host "  [-] Error: Diagnostic Point Not Found." -ForegroundColor Red
                        [WinSystemCore]::Beep(300, 500) | Out-Null
                    }
                } else {
                    Write-Host "  [-] Error: Target Process Not Found." -ForegroundColor Red
                }
            }
            elseif ($action -eq "restore") {
                [WinSystemCore]::webAction = "none"
                if ($hProc -ne [IntPtr]::Zero) {
                    if ($isPatched) {
                        foreach ($p in $patchesToApply) {
                            if ($p.Address -eq [IntPtr]::Zero -or $null -eq $p.OrigBytes) { continue }
                            [uint32]$old = 0; [int]$written = 0
                            [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, 0x40, [ref]$old) | Out-Null
                            [WinSystemCore]::WriteProcessMemory($hProc, $p.Address, $p.OrigBytes, $p.OrigBytes.Length, [ref]$written) | Out-Null
                            [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, $old, [ref]$old) | Out-Null
                        }
                        $isPatched = $false
                    }
                    [WinSystemCore]::CloseHandle($hProc) | Out-Null
                    $hProc = [IntPtr]::Zero
                    foreach ($p in $patchesToApply) {
                        $p.Address = [IntPtr]::Zero
                        $p.OrigBytes = $null
                    }
                }
                Write-Host "  [+] [WEB UI] MEMORY RESTORED & DETACHED" -ForegroundColor Yellow
                [WinSystemCore]::Beep(1000, 200) | Out-Null
            }
            elseif ($action -eq "clear") {
                [WinSystemCore]::webAction = "none"
                Clear-History -ErrorAction SilentlyContinue
                Write-Host "  [+] [WEB UI] SESSION HISTORY CLEANED" -ForegroundColor Cyan
                [WinSystemCore]::Beep(1200, 100) | Out-Null
            }
        }

        $isKeyDown = ([WinSystemCore]::GetAsyncKeyState($userKey) -band 0x8000)
        $isEndDown = ([WinSystemCore]::GetAsyncKeyState(0x23) -band 0x8000)
        $isF12Down = ([WinSystemCore]::GetAsyncKeyState(0x7B) -band 0x8000)

        if ($isEndDown -or $isF12Down) { break }

        $anyScanned = $false
        foreach ($p in $patchesToApply) {
            if ($p.Address -ne [IntPtr]::Zero) { $anyScanned = $true }
        }

        if ($anyScanned) {
            $shouldPatch = $false
            if ($mode -eq "1") {
                if ($isKeyDown -and -not $wasKeyDown) {
                    $toggle = -not $toggle
                    $freq = if ($toggle) { 1200 } else { 600 }
                    [WinSystemCore]::Beep($freq, 100) | Out-Null
                }
                $shouldPatch = $toggle
            } else {
                $shouldPatch = $isKeyDown
            }

            if ($shouldPatch -and -not $isPatched) {
                foreach ($p in $patchesToApply) {
                    if ($p.Address -eq [IntPtr]::Zero) { continue }
                    [uint32]$old = 0; [int]$written = 0
                    if ([WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.Patch.Length, 0x40, [ref]$old)) {
                        if ([WinSystemCore]::WriteProcessMemory($hProc, $p.Address, $p.Patch, $p.Patch.Length, [ref]$written)) {
                            [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.Patch.Length, $old, [ref]$old) | Out-Null
                            $isPatched = $true
                        }
                    }
                }
            } elseif (-not $shouldPatch -and $isPatched) {
                foreach ($p in $patchesToApply) {
                    if ($p.Address -eq [IntPtr]::Zero -or $null -eq $p.OrigBytes) { continue }
                    [uint32]$old = 0; [int]$written = 0
                    if ([WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, 0x40, [ref]$old)) {
                        [WinSystemCore]::WriteProcessMemory($hProc, $p.Address, $p.OrigBytes, $p.OrigBytes.Length, [ref]$written) | Out-Null
                        [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, $old, [ref]$old) | Out-Null
                        $isPatched = $false
                    }
                }
            }
            $wasKeyDown = $isKeyDown
        }

        Start-Sleep -Milliseconds 10
    }
} finally {
    if ($hProc -ne [IntPtr]::Zero) {
        [WinSystemCore]::CloseHandle($hProc) | Out-Null
    }
}
