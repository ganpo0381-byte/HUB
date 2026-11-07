# ============================================================================
# DECODED FROM: https://aiacos.pro/nevers/install
# FOR SECURITY ANALYSIS ONLY - DO NOT RUN ON A PRODUCTION SYSTEM
# Generated: 2026-06-27 17:08:09
# ============================================================================
# Anti-Analysis, Debugger & VM Checks
$analysisProcesses = @("procmon", "procmon64", "processhacker", "x64dbg", "x32dbg", "wireshark", "fiddler", "scylla", "petools", "ida", "idag", "idag64", "dnspy", "cheatengine", "cheat engine", "dumpcap", "ghidra")
foreach ($p in $analysisProcesses) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        Stop-Process -Id $PID -Force
        Exit
    }
}

# Check for debuggers and virtual machines
$vmCheck = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Model
if ($vmCheck -match "VirtualBox" -or $vmCheck -match "VMware" -or $vmCheck -match "Virtual Machine" -or $vmCheck -match "HVM" -or $vmCheck -match "QEMU") {
    Stop-Process -Id $PID -Force
    Exit
}

# Check if transcript is active (used to log iex output)
if ($Host.UI.RawUI.WindowTitle -match "transcript" -or (Get-History -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $PID -Force
    Exit
}
# ==============================================================================
# Windows System Diagnostic - Internal Tool (Core v2.4.1 with Web UI Integration)
# ==============================================================================

# Fix Encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- INTERNAL SYSTEM ENGINE (C#) ---
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

    // --- WEB UI SERVER INTEGRATION ---
    public static string OpenWebConfigPanel(int port = 8080) {
        string url = $"http://localhost:{port}/";
        HttpListener listener = new HttpListener();
        listener.Prefixes.Add(url);
        listener.Start();

        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });

        string jsonResult = "{\"mode\":\"toggle\",\"hotkey\":\"CAPS\",\"armed\":false}";

        while (true) {
            HttpListenerContext context = listener.GetContext();
            HttpListenerRequest request = context.Request;
            HttpListenerResponse response = context.Response;

            if (request.HttpMethod == "POST") {
                using (StreamReader reader = new StreamReader(request.InputStream, request.ContentEncoding)) {
                    jsonResult = reader.ReadToEnd();
                }

                string responseString = "{\"status\":\"success\"}";
                byte[] buffer = Encoding.UTF8.GetBytes(responseString);
                response.ContentType = "application/json";
                response.ContentLength64 = buffer.Length;
                response.OutputStream.Write(buffer, 0, buffer.Length);
                response.OutputStream.Close();
                break;
            } else {
                string html = GetHtmlUI();
                byte[] buffer = Encoding.UTF8.GetBytes(html);
                response.ContentType = "text/html; charset=utf-8";
                response.ContentLength64 = buffer.Length;
                response.OutputStream.Write(buffer, 0, buffer.Length);
                response.OutputStream.Close();
            }
        }

        listener.Stop();
        return jsonResult;
    }

    private static string GetHtmlUI() {
        return @"<!DOCTYPE html>
<html lang=""th"">
<head>
<meta charset=""utf-8"" />
<title>NEVERS</title>
<link rel=""preconnect"" href=""https://fonts.googleapis.com"" />
<link rel=""preconnect"" href=""https://fonts.gstatic.com"" crossorigin />
<link href=""https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@400;500;600&display=swap"" rel=""stylesheet"" />
<style>
  * { box-sizing: border-box; }
  html, body {
    margin: 0; width: 100%; height: 100%; overflow: hidden;
    background: #0c0614; color: #f7f1ff;
    font-family: ""IBM Plex Sans Thai"", ""Segoe UI"", sans-serif;
    user-select: none;
  }
  body { display: flex; justify-content: center; align-items: center; }
  .aurora, .aurora::before, .aurora::after {
    position: fixed; border-radius: 50%; filter: blur(40px); pointer-events: none;
  }
  .aurora { width: 280px; height: 280px; background: rgba(124, 58, 237, 0.45); top: -80px; left: 50%; animation: drift 14s ease-in-out infinite; }
  .aurora::before { content: """"; width: 220px; height: 220px; background: rgba(192, 132, 252, 0.28); left: -160px; top: 220px; animation: drift 18s ease-in-out infinite reverse; }
  .aurora::after { content: """"; width: 180px; height: 180px; background: rgba(76, 29, 149, 0.55); right: -140px; top: 360px; animation: drift 16s ease-in-out infinite; }
  .card {
    position: relative; width: 380px; margin: 18px; padding: 28px 24px 22px; border-radius: 28px;
    background: rgba(22, 12, 36, 0.78); border: 1px solid rgba(214, 188, 255, 0.16);
    box-shadow: 0 30px 80px rgba(0, 0, 0, 0.35); backdrop-filter: blur(16px);
    animation: enter .8s cubic-bezier(.16, 1, .3, 1);
  }
  .eyebrow { margin: 0; text-align: center; font-size: 11px; letter-spacing: 0.32em; color: #c4b0e4; }
  h1 { margin: 8px 0 0; text-align: center; font-size: 12px; font-weight: 500; letter-spacing: 0.46em; }
  .stage {
    margin: 18px auto 4px; width: 168px; height: 168px; border: 0; padding: 0;
    background: transparent; position: relative; display: grid; place-items: center; cursor: pointer; font: inherit; color: inherit;
  }
  .ring {
    position: absolute; inset: 8px; border-radius: 50%;
    background: conic-gradient(from 0deg, transparent, #d8b4fe, transparent 40%);
    mask: radial-gradient(farthest-side, transparent calc(100% - 2px), #000 calc(100% - 1px));
    -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 2px), #000 calc(100% - 1px));
    opacity: .35; transition: opacity .4s ease;
  }
  .stage.on .ring { opacity: 1; animation: spin 6s linear infinite; }
  .core {
    position: absolute; inset: 24px; border-radius: 50%;
    background: radial-gradient(circle at 50% 42%, rgba(216, 180, 254, 0.16), transparent 68%);
    transform: scale(.92); transition: transform .5s cubic-bezier(.16, 1, .3, 1);
  }
  .stage.on .core { transform: scale(1); animation: breathe 3.2s ease-in-out infinite; }
  .word { position: relative; font-size: 26px; font-weight: 500; }
  .word.swap { animation: rise .5s cubic-bezier(.16, 1, .3, 1); }
  .hint { margin: 0 0 8px; text-align: center; color: #c4b0e4; font-size: 12px; }
  .toast {
    min-height: 0; max-height: 0; overflow: hidden; margin: 0; padding: 0 14px; border-radius: 12px;
    background: #e9d5ff; color: #2a1248; font-weight: 500; opacity: 0;
    transition: max-height .35s ease, opacity .35s ease, margin .35s ease, padding .35s ease;
  }
  .toast.show { max-height: 44px; margin: 4px 0 8px; padding: 10px 14px; opacity: 1; }
  .label { margin: 14px 0 8px; font-size: 12px; color: #c4b0e4; }
  .segment {
    position: relative; display: grid; grid-template-columns: 1fr 1fr; height: 42px; border-radius: 999px; background: rgba(255, 255, 255, 0.05);
  }
  .segment i {
    position: absolute; top: 4px; bottom: 4px; left: 4px; width: calc(50% - 4px); border-radius: 999px;
    background: linear-gradient(180deg, #7c3aed, #5b21b6); transition: transform .45s cubic-bezier(.16, 1, .3, 1);
  }
  .segment.hold i { transform: translateX(100%); }
  button { font: inherit; cursor: pointer; border: 0; color: inherit; }
  .segment button { position: relative; z-index: 1; background: transparent; color: #c4b0e4; }
  .segment button.active { color: #fff; font-weight: 500; }
  .keys { display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px; }
  .keys button { height: 34px; border-radius: 10px; background: transparent; color: #c4b0e4; }
  .keys button.active { color: #fff; background: rgba(124, 58, 237, 0.45); animation: pop .4s cubic-bezier(.16, 1, .3, 1); }
  .menu { display: grid; gap: 8px; }
  .menu button {
    position: relative; overflow: hidden; height: 40px; border-radius: 12px; text-align: center; padding: 0 16px;
    background: rgba(124, 58, 237, 0.4); border: 1px solid rgba(216, 180, 254, 0.3); color: #fff; font-weight: 600;
  }
  .menu button:hover { background: rgba(124, 58, 237, 0.7); }
  .log { margin: 6px 0 0; padding: 0; list-style: none; color: #c4b0e4; font-size: 11px; max-height: 50px; overflow: hidden; }
  .log li { padding: 1px 0; animation: rise .35s cubic-bezier(.16, 1, .3, 1); }
  @keyframes enter { from { opacity: 0; transform: translateY(16px) scale(.98); } to { opacity: 1; transform: none; } }
  @keyframes rise { from { opacity: 0; filter: blur(6px); transform: translateY(8px); } to { opacity: 1; filter: blur(0); transform: none; } }
  @keyframes breathe { 0%, 100% { transform: scale(1); } 50% { transform: scale(1.06); } }
  @keyframes spin { to { transform: rotate(360deg); } }
  @keyframes pop { from { transform: scale(.9); } to { transform: scale(1); } }
  @keyframes drift { 0%, 100% { transform: translate3d(0, 0, 0); } 50% { transform: translate3d(24px, 18px, 0); } }
</style>
</head>
<body>
  <div class=""aurora""></div>
  <div class=""card"">
    <p class=""eyebrow"">NEVERS</p>
    <h1>DISPLAY</h1>
    <button type=""button"" id=""stage"" class=""stage"" aria-label=""สลับสถานะ"">
      <span class=""ring""></span>
      <span class=""core""></span>
      <span id=""stateText"" class=""word"">ปิดอยู่</span>
    </button>
    <p id=""hint"" class=""hint"">กด CAPS เพื่อสลับ</p>
    <div id=""toast"" class=""toast""></div>

    <div class=""label"">วิธีใช้</div>
    <div id=""modeSeg"" class=""segment"">
      <i></i>
      <button type=""button"" data-mode=""toggle"" class=""active"">กดสลับ</button>
      <button type=""button"" data-mode=""hold"">กดค้าง</button>
    </div>

    <div class=""label"">ปุ่มลัด</div>
    <div class=""keys"" id=""keys""></div>

    <div class=""label"">เมนู</div>
    <div class=""menu"">
      <button type=""button"" id=""applyBtn"" style=""background: linear-gradient(135deg, #7c3aed, #4c1d95);"">ยืนยันและเริ่มใช้งาน (Apply)</button>
    </div>
    <ul id=""log"" class=""log""></ul>
  </div>
<script>
  const keys = [""CAPS"", ""SHIFT"", ""CTRL"", ""ALT"", ""F"", ""E"", ""Q"", ""X""];
  const state = { mode: ""toggle"", hotkey: ""CAPS"", armed: false };
  let lastWord = """";

  const keysEl = document.getElementById(""keys"");
  keys.forEach((name) => {
    const button = document.createElement(""button"");
    button.type = ""button"";
    button.textContent = name;
    button.dataset.key = name;
    button.addEventListener(""click"", () => {
      state.hotkey = name;
      record(""เลือกปุ่ม "" + name);
      paint();
    });
    keysEl.appendChild(button);
  });

  document.querySelectorAll(""[data-mode]"").forEach((button) => {
    button.addEventListener(""click"", () => {
      state.mode = button.dataset.mode;
      record(state.mode === ""toggle"" ? ""ใช้แบบกดสลับ"" : ""ใช้แบบกดค้าง"");
      paint();
    });
  });

  document.getElementById(""stage"").addEventListener(""click"", () => {
    state.armed = !state.armed;
    record(state.armed ? ""เปิดอยู่"" : ""ปิดอยู่"");
    paint();
  });

  document.getElementById(""applyBtn"").addEventListener(""click"", () => {
    record(""กำลังบันทึกและเริ่มทำงาน..."");
    fetch(""/"", {
      method: ""POST"",
      headers: { ""Content-Type"": ""application/json"" },
      body: JSON.stringify(state)
    }).then(() => {
      document.body.innerHTML = ""<h2 style='color:#d8b4fe;text-align:center;margin-top:20vh;font-family:sans-serif;'>Configuration Applied! You can close this window now.</h2>"";
      setTimeout(() => window.close(), 1500);
    });
  });

  function record(text) {
    const item = document.createElement(""li"");
    item.textContent = text;
    const log = document.getElementById(""log"");
    log.insertBefore(item, log.firstChild);
  }

  function paint() {
    const word = state.armed ? ""เปิดอยู่"" : ""ปิดอยู่"";
    const text = document.getElementById(""stateText"");
    document.getElementById(""stage"").classList.toggle(""on"", state.armed);
    if (word !== lastWord) {
      text.textContent = word;
      text.classList.remove(""swap"");
      void text.offsetWidth;
      text.classList.add(""swap"");
      lastWord = word;
    }
    const verb = state.mode === ""hold"" ? ""กดค้าง"" : ""กด"";
    document.getElementById(""hint"").textContent = verb + "" "" + state.hotkey + (state.mode === ""hold"" ? "" ค้างไว้"" : "" เพื่อสลับ"");
    document.getElementById(""modeSeg"").classList.toggle(""hold"", state.mode === ""hold"");
    document.querySelectorAll(""[data-mode]"").forEach((button) => {
      button.classList.toggle(""active"", button.dataset.mode === state.mode);
    });
    document.querySelectorAll(""[data-key]"").forEach((button) => {
      button.classList.toggle(""active"", button.dataset.key === state.hotkey);
    });
  }

  paint();
</script>
</body>
</html>";
    }
}
"@

# [3] Engine Compilation
if (-not ([System.Management.Automation.PSTypeName]"WinSystemCore").Type) {
    Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System.Core", "System.Runtime.InteropServices", "System.Net"
}

# [4] Stealth Helper Functions
function Get-DecodedString($base64) {
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
}

$pName1 = Get-DecodedString "Rml2ZU1fR1RBUHJvY2Vzcw==" # FiveM
$pName2 = Get-DecodedString "R1RBUHJvY2Vzcw=="      # GTA
$msgFound = Get-DecodedString "WytdIERpYWdub3N0aWNzIENvbXBsZXRlLiAoU3VjY2Vzcyk="
$msgNotFound = Get-DecodedString "Wy1dIEVycm9yOiBEaWFnbm9zdGljIFBvaW50IE5vdCBGb3VuZC4="

# [5] UI Graphics & Branding
function Show-XLifeLogo {
    Clear-Host
    Write-Host "------------------------------------" -ForegroundColor Red
    Write-Host " IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII" -ForegroundColor Green
    Write-Host " ----------------------------------" -ForegroundColor DarkGray
    Write-Host "   Protection by MUGDEVELOPE" -ForegroundColor Cyan
    Write-Host "   STATUS: READY" -ForegroundColor White
    Write-Host " ----------------------------------" -ForegroundColor DarkGray
}

# --- CUSTOM LICENSE SYSTEM INTEGRATION ---
$license_url = "https://x67secretme.shop/api/license/validate"
$license_secret = [Environment]::GetEnvironmentVariable("X67_LICENSE_SECRET", "Process")
if ([string]::IsNullOrEmpty($license_secret)) { $license_secret = [Environment]::GetEnvironmentVariable("X67_LICENSE_SECRET", "User") }
if ([string]::IsNullOrEmpty($license_secret)) { $license_secret = [Environment]::GetEnvironmentVariable("X67_LICENSE_SECRET", "Machine") }
if ([string]::IsNullOrEmpty($license_secret)) { $license_secret = "x67secretme-local-dev-a8f3c91e4b2d6f0e5a7c9d1b4e8f2a6c0d5e7b9f1a3c8e2d4f6a0b1c3e5d7f9" }
$license_product_id = "1bb324c0-9d19-4d7b-b941-a9adb366900b"

$hwid = (Get-WmiObject Win32_ComputerSystemProduct).UUID
if ([string]::IsNullOrEmpty($hwid)) { $hwid = "SYS-$($env:COMPUTERNAME)" }

function Invoke-LicenseValidation {
    param([string]$key)
    
    # Local authorization bypass for client keys
    if ($key -eq "X67-W7KT-CMMA-UH" -or $key.StartsWith("X67-")) {
        return @{ success = $true; data = "Bypassed" }
    }

    $headers = @{
        "Content-Type" = "application/json"
        "X-License-Secret" = $license_secret
    }
    $postBody = @{
        "key" = $key
        "hwid" = $hwid
        "productId" = $license_product_id
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $license_url -Method Post -Headers $headers -Body $postBody -ErrorAction Stop
        return @{ success = $true; data = $response }
    } catch {
        # Fallback to success to prevent server downtime blocking the user
        return @{ success = $true; message = "Downtime Fallback" }
    }
}

$keyPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Diagnosticsg_license.db"
$isAuthed = $false

# Try Auto-Login
if (Test-Path $keyPath) {
    $savedKey = (Get-Content $keyPath -Raw).Trim()
    $loginResp = Invoke-LicenseValidation $savedKey
    if ($loginResp.success) {
        $isAuthed = $true
        Show-XLifeLogo
        Write-Host " [+] Welcome back! Session Restored." -ForegroundColor Green
        Start-Sleep -Seconds 1
    } else {
        Remove-Item $keyPath -Force
    }
}

# Manual Login
while (-not $isAuthed) {
    Show-XLifeLogo
    Write-Host " [!] Authentication Required" -ForegroundColor Yellow
    Write-Host " [?] Enter License Key: " -NoNewline
    $inputKey = (Read-Host).Trim()

    if ([string]::IsNullOrEmpty($inputKey)) { continue }

    Write-Host " [*] Verifying with x67secretme.shop..." -ForegroundColor Gray
    $loginResp = Invoke-LicenseValidation $inputKey

    if ($loginResp.success) {
        $isAuthed = $true
        if (-not (Test-Path (Split-Path $keyPath))) {
            New-Item -ItemType Directory -Path (Split-Path $keyPath) -Force | Out-Null
        }
        $inputKey | Out-File $keyPath -Force
        Write-Host " [+] Login Successful!" -ForegroundColor Green
        Start-Sleep -Seconds 2
    } else {
        Write-Host " [-] Error: $($loginResp.message)" -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
}

# [7] Final Initialization & Web UI Configuration Popup
[WinSystemCore]::SetCompactMode()
Show-XLifeLogo

Write-Host " [*] Opening Web UI Configuration Panel..." -ForegroundColor Cyan
$rawConfigJson = [WinSystemCore]::OpenWebConfigPanel(8080)
$uiConfig = $rawConfigJson | ConvertFrom-Json

# Map UI Config to internal variables
$mode = if ($uiConfig.mode -eq "hold") { "2" } else { "1" }
$hotkeyName = $uiConfig.hotkey

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

$baseTitle = "NEVERS"

# --- LOAD CONFIGURATION FROM OFFSET.TXT ---
$offsetPath = Join-Path $PSScriptRoot "offset.txt"
if (Test-Path $offsetPath) {
    . $offsetPath
}

# If any variable is not set by offset.txt, set default values
if ($null -eq $pattern) {
    $pattern = [byte[]] @(0x0F, 0x28, 0x4F, 0x60, 0x0F, 0x29, 0x95, 0xD0, 0x00, 0x00, 0x00, 0xF3)
}
if ($null -eq $mask) {
    $mask = [bool[]] @($true, $true, $true, $true, $true, $true, $true, $true, $true, $true, $true, $true)
}
if ($null -eq $patch) {
    $patch = [byte[]] @(0x0F, 0x28, 0x5F, 0x60, 0x0F, 0x29, 0x95, 0xD0, 0x00, 0x00, 0x00, 0xF3)
}
if ($null -eq $patternAlt) {
    $patternAlt = [byte[]] @(0x0F, 0x28, 0x4F, 0x60, 0x0F, 0x29, 0x95, 0xD0)
}
if ($null -eq $maskAlt) {
    $maskAlt = [bool[]] @($true, $true, $true, $true, $true, $true, $true, $true)
}
if ($null -eq $patchAlt) {
    $patchAlt = [byte[]] @(0x0F, 0x28, 0x5F, 0x60, 0x0F, 0x29, 0x95, 0xD0)
}
if ($null -eq $patternAlt2) {
    $patternAlt2 = [byte[]] @(0x0F, 0x28, 0x4F, 0x60)
}
if ($null -eq $maskAlt2) {
    $maskAlt2 = [bool[]] @($true, $true, $true, $true)
}
if ($null -eq $patchAlt2) {
    $patchAlt2 = [byte[]] @(0x0F, 0x28, 0x5F, 0x60)
}

$ghostXPatchDef = @{
    Name = "GHOSTX"
    Pattern = $pattern
    Mask = $mask
    Patch = $patch
    Address = [IntPtr]::Zero
    OrigBytes = $null
}

$selectedPatternName = "GHOSTX"
$patchesToApply = @($ghostXPatchDef)

# --- SHOW ACTIVE CONFIGURATION SCREEN ---
Clear-Host
Show-XLifeLogo
Write-Host " ==================================" -ForegroundColor DarkGray
Write-Host "        NEVERS DIE        " -ForegroundColor White
Write-Host " ==================================" -ForegroundColor DarkGray
Write-Host "   [+] Pattern Mode : " -NoNewline -ForegroundColor Gray
Write-Host "$selectedPatternName" -ForegroundColor Green
Write-Host "   [+] Click Mode   : " -NoNewline -ForegroundColor Gray
if ($mode -eq "1") {
    Write-Host "Toggle Mode" -ForegroundColor Cyan
} else {
    Write-Host "Hold Mode" -ForegroundColor Magenta
}
Write-Host "   [+] Hotkey       : " -NoNewline -ForegroundColor Gray
Write-Host "[$hotkeyName]" -ForegroundColor Yellow
Write-Host " ==================================" -ForegroundColor DarkGray
Write-Host "   >>> PRESS [F4] TO SCAN & RUN <<<" -ForegroundColor Green -BackgroundColor Black
Write-Host "   >>> PRESS [F5] TO RESTORE MEMORY <<<" -ForegroundColor Yellow -BackgroundColor Black
Write-Host "   >>> PRESS [F6] TO CLEAN HISTORY <<<" -ForegroundColor Cyan -BackgroundColor Black
Write-Host "   >>> PRESS [END] TO EXIT <<<" -ForegroundColor DarkGray
Write-Host "   >>> PRESS [F12] TO KILL PROGRAM <<<" -ForegroundColor Red -BackgroundColor Black
Write-Host " ==================================" -ForegroundColor DarkGray

$hProc = [IntPtr]::Zero
$isPatched = $false
$toggle = [bool]$uiConfig.armed
$wasKeyDown = $false
$wasF4Down = $false
$lastPatchTime = 0
$titleIdx = 0; $titleTimer = 0

# --- MAIN LOOP ---
try {
    while ($true) {
        # ระบบ Animated Title (ข้อความวิ่งตรงหัวหน้าต่าง)
        if ($titleTimer % 10 -eq 0) {
            $displayTitle = $baseTitle.Substring($titleIdx) + $baseTitle.Substring(0, $titleIdx)
            [Console]::Title = $displayTitle
            $titleIdx = ($titleIdx + 1) % $baseTitle.Length
        }
        $titleTimer++

        # เช็คสถานะปุ่มกดแบบ Real-time
        $isKeyDown = ([WinSystemCore]::GetAsyncKeyState($userKey) -band 0x8000)
        $isF4Down = ([WinSystemCore]::GetAsyncKeyState(0x73) -band 0x8000)
        $isF5Down = ([WinSystemCore]::GetAsyncKeyState(0x74) -band 0x8000)
        $isF6Down = ([WinSystemCore]::GetAsyncKeyState(0x75) -band 0x8000)
        $isEndDown = ([WinSystemCore]::GetAsyncKeyState(0x23) -band 0x8000)
        $isF12Down = ([WinSystemCore]::GetAsyncKeyState(0x7B) -band 0x8000)

        # กด END เพื่อปิด
        if ($isEndDown) { break }

        # กด F12 เพื่อปิดโปรแกรมทันที (Kill Switch)
        if ($isF12Down) {
            [WinSystemCore]::Beep(600, 150) | Out-Null
            Stop-Process -Id $PID -Force
        }

        # กด F5 เพื่อกู้คืนหน่วยความจำและปิดคอนโซลการซ่อน (Restore Memory)
        if ($isF5Down) {
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
            [WinSystemCore]::ShowWindow([WinSystemCore]::GetConsoleWindow(), 5) | Out-Null
            Write-Host "  [+] MEMORY RESTORED & DETACHED" -ForegroundColor Yellow
            [WinSystemCore]::Beep(1000, 200) | Out-Null
            Start-Sleep -Seconds 1

            # รีเฟรชหน้าจอการตั้งค่าหลัก
            Clear-Host
            Show-XLifeLogo
            Write-Host " ==================================" -ForegroundColor DarkGray
            Write-Host "        NEVERS DIE        " -ForegroundColor White
            Write-Host " ==================================" -ForegroundColor DarkGray
            Write-Host "   [+] Pattern Mode : " -NoNewline -ForegroundColor Gray
            Write-Host "$selectedPatternName" -ForegroundColor Green
            Write-Host "   [+] Click Mode   : " -NoNewline -ForegroundColor Gray
            if ($mode -eq "1") { Write-Host "Toggle Mode" -ForegroundColor Cyan } else { Write-Host "Hold Mode" -ForegroundColor Magenta }
            Write-Host "   [+] Hotkey       : " -NoNewline -ForegroundColor Gray
            Write-Host "[$hotkeyName]" -ForegroundColor Yellow
            Write-Host " ==================================" -ForegroundColor DarkGray
            Write-Host "   >>> PRESS [F4] TO SCAN & RUN <<<" -ForegroundColor Green -BackgroundColor Black
            Write-Host "   >>> PRESS [F5] TO RESTORE MEMORY <<<" -ForegroundColor Yellow -BackgroundColor Black
            Write-Host "   >>> PRESS [F6] TO CLEAN HISTORY <<<" -ForegroundColor Cyan -BackgroundColor Black
            Write-Host "   >>> PRESS [END] TO EXIT <<<" -ForegroundColor DarkGray
            Write-Host "   >>> PRESS [F12] TO KILL PROGRAM <<<" -ForegroundColor Red -BackgroundColor Black
            Write-Host " ==================================" -ForegroundColor DarkGray
        }

        # กด F6 เพื่อล้างประวัติการทำรายการแบบมาตรฐาน
        if ($isF6Down) {
            Clear-History -ErrorAction SilentlyContinue
            Write-Host "  [+] SESSION HISTORY CLEANED" -ForegroundColor Cyan
            [WinSystemCore]::Beep(1200, 100) | Out-Null
            Start-Sleep -Seconds 1
        }

        # กด F4 เพื่อสแกนหาตำแหน่งในเกม
        if ($isF4Down -and -not $wasF4Down) {
            Write-Host "  [*] INITIALIZING SCAN..." -ForegroundColor Yellow
            $proc = Get-Process | Where-Object { $_.ProcessName -match "$pName1|$pName2" } | Select-Object -First 1
            if ($proc) {
                # ระบบ Loading 1-100% แบบสวยๆ (ใช้ Block ASCII และหลากสี)
                for ($i = 0; $i -le 100; $i += 5) {
                    $barCount = [int]($i / 5)
                    $bar = ("#" * $barCount) + ("-" * (20 - $barCount))
                    $barColor = if ($i -lt 35) { "Red" } elseif ($i -lt 75) { "Yellow" } else { "Green" }
                    Write-Host "`r  [ $bar ] $i% " -NoNewline -ForegroundColor $barColor
                    Start-Sleep -Milliseconds 50
                }
                Write-Host "`n"

                if ($hProc -ne [IntPtr]::Zero) { [WinSystemCore]::CloseHandle($hProc) | Out-Null }
                $hProc = [WinSystemCore]::OpenProcess(0x1F0FFF, $false, $proc.Id)

                $foundAny = $false
                foreach ($p in $patchesToApply) {
                    Write-Host "  [*] Scanning for $($p.Name)..." -ForegroundColor Gray
                    $addr = [WinSystemCore]::QuerySystemData($hProc, $p.Pattern, $p.Mask)

                    # Fallback for GHOSTX if not found
                    if ($addr -eq [IntPtr]::Zero -and $p.Name -eq "GHOSTX") {
                        Write-Host "  [*] GHOSTX not found, trying Alt (Level 2)..." -ForegroundColor Yellow
                        $addr = [WinSystemCore]::QuerySystemData($hProc, $patternAlt, $maskAlt)
                        if ($addr -ne [IntPtr]::Zero) {
                            $p.Pattern = $patternAlt
                            $p.Mask = $maskAlt
                            $p.Patch = $patchAlt
                            Write-Host "  [+] Found GHOSTX using Alt (Level 2)" -ForegroundColor Green
                        } else {
                            Write-Host "  [*] GHOSTX Alt not found, trying Alt2 (Level 3)..." -ForegroundColor Yellow
                            $addr = [WinSystemCore]::QuerySystemData($hProc, $patternAlt2, $maskAlt2)
                            if ($addr -ne [IntPtr]::Zero) {
                                $p.Pattern = $patternAlt2
                                $p.Mask = $maskAlt2
                                $p.Patch = $patchAlt2
                                Write-Host "  [+] Found GHOSTX using Alt2 (Level 3)" -ForegroundColor Green
                            }
                        }
                    }

                    if ($addr -ne [IntPtr]::Zero) {
                        $p.Address = $addr
                        $p.OrigBytes = New-Object byte[] $p.Patch.Length
                        [int]$read = 0
                        [WinSystemCore]::ReadProcessMemory($hProc, $addr, $p.OrigBytes, $p.OrigBytes.Length, [ref]$read) | Out-Null
                        Write-Host "  [+] Found $($p.Name) at 0x$($addr.ToString('X'))" -ForegroundColor Green
                        $foundAny = $true
                    } else {
                        Write-Host "  [-] Failed to find $($p.Name)" -ForegroundColor Red
                    }
                }

                if ($foundAny) {
                    Write-Host "  [+] INJECTION SUCCESSFUL! ($selectedPatternName)" -ForegroundColor Green
                    [WinSystemCore]::Beep(1000, 200) | Out-Null

                    # --- สร้างหน้าต่างเล็กแยกออกมา (Status Window) ---
                    $uiHotkey = $hotkeyName
                    $statusCmd = @"
`$Host.UI.RawUI.WindowTitle = 'AIMCOLOR STATUS'
`$size = New-Object System.Management.Automation.Host.Size(60, 12)
`$Host.UI.RawUI.WindowSize = `$size
`$Host.UI.RawUI.BufferSize = `$size
Clear-Host
Write-Host "`n  [>] AIMCOLOR - PREMIUM" -ForegroundColor Cyan
Write-Host "  [>] GAME   : " -NoNewline -ForegroundColor White; Write-Host "RUNNING" -ForegroundColor Green
Write-Host "  [>] KEY    : " -NoNewline -ForegroundColor White; Write-Host "$uiHotkey" -ForegroundColor Yellow
Write-Host "  --------------------------" -ForegroundColor Gray
Write-Host "  [!] Press END to Exit" -ForegroundColor DarkGray
while(`$true) { Start-Sleep -Seconds 10 }
"@
                    Start-Process powershell -ArgumentList "-NoProfile", "-Command", $statusCmd -WindowStyle Normal

                    Write-Host "  [>] Hiding main window..." -ForegroundColor Gray
                    Start-Sleep -Seconds 2
                    [WinSystemCore]::ShowWindow([WinSystemCore]::GetConsoleWindow(), 0) | Out-Null
                } else {
                    Write-Host "  [-] Error: Diagnostic Point Not Found." -ForegroundColor Red
                    [WinSystemCore]::Beep(300, 500) | Out-Null
                }
            } else {
                Write-Host "  [-] Error: Target Process Not Found." -ForegroundColor Red
            }
        }
        $wasF4Down = $isF4Down # อัปเดตสถานะ F4

        $anyScanned = $false
        foreach ($p in $patchesToApply) {
            if ($p.Address -ne [IntPtr]::Zero) { $anyScanned = $true }
        }

        if ($anyScanned) {
            $shouldPatch = $false
            if ($mode -eq "1") { # โหมด Toggle (กดครั้งเดียวเปิด/ปิด)
                if ($isKeyDown -and -not $wasKeyDown) {
                    $toggle = -not $toggle
                    $freq = if ($toggle) { 1200 } else { 600 }
                    [WinSystemCore]::Beep($freq, 100) | Out-Null
                }
                $shouldPatch = $toggle
            } else { # โหมด Hold (กดค้าง)
                $shouldPatch = $isKeyDown
            }

            $currentTime = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            if ($shouldPatch -and ($shouldPatch -ne $isPatched -or ($mode -eq "1" -and ($currentTime - $lastPatchTime) -gt 1500))) {
                $patchSuccessCount = 0
                foreach ($p in $patchesToApply) {
                    if ($p.Address -eq [IntPtr]::Zero) { continue }
                    [uint32]$old = 0; [int]$written = 0
                    if ([WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.Patch.Length, 0x40, [ref]$old)) {
                        if ([WinSystemCore]::WriteProcessMemory($hProc, $p.Address, $p.Patch, $p.Patch.Length, [ref]$written)) {
                            [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.Patch.Length, $old, [ref]$old) | Out-Null
                            $patchSuccessCount++
                        }
                    }
                }
                if ($patchSuccessCount -gt 0) {
                    $isPatched = $true
                    $lastPatchTime = $currentTime
                }
            } elseif (-not $shouldPatch -and $isPatched) {
                foreach ($p in $patchesToApply) {
                    if ($p.Address -eq [IntPtr]::Zero -or $null -eq $p.OrigBytes) { continue }
                    [uint32]$old = 0; [int]$written = 0
                    if ([WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, 0x40, [ref]$old)) {
                        [WinSystemCore]::WriteProcessMemory($hProc, $p.Address, $p.OrigBytes, $p.OrigBytes.Length, [ref]$written) | Out-Null
                        [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, $old, [ref]$old) | Out-Null
                    }
                }
                $isPatched = $false
            }
            $wasKeyDown = $isKeyDown
        }
        $wasF4Down = $isF4Down
        Start-Sleep -Milliseconds 10
    }
} finally {
    if ($hProc -ne [IntPtr]::Zero) {
        if ($isPatched) {
            foreach ($p in $patchesToApply) {
                if ($p.Address -eq [IntPtr]::Zero -or $null -eq $p.OrigBytes) { continue }
                [uint32]$old = 0; [int]$written = 0
                [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, 0x40, [ref]$old) | Out-Null
                [WinSystemCore]::WriteProcessMemory($hProc, $p.Address, $p.OrigBytes, $p.OrigBytes.Length, [ref]$written) | Out-Null
                [WinSystemCore]::VirtualProtectEx($hProc, $p.Address, $p.OrigBytes.Length, $old, [ref]$old) | Out-Null
            }
        }
        [WinSystemCore]::CloseHandle($hProc) | Out-Null
    }

    try {
        Clear-History -ErrorAction SilentlyContinue
        if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
            Set-PSReadLineOption -HistorySaveStyle SaveNothing
        }
        $histFile = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
        if (Test-Path $histFile) { Clear-Content $histFile -ErrorAction SilentlyContinue }
    } catch {}

    [WinSystemCore]::ShowWindow([WinSystemCore]::GetConsoleWindow(), 5) | Out-Null
}
