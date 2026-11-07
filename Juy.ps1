# ==============================================================================
# NEVERS CONTROL CENTER - Auto Headshot & Smart Scanner v11.1 (Fixed)
# ==============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# [1] ซ่อนหน้าต่างคอมมานด์ไลน์ (PowerShell Console) ด้านหลังทันที
$codeWindow = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
$codeWindow += '[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();'
$typeWindow = Add-Type -MemberDefinition $codeWindow -Name "Win32ShowWindow" -Namespace "Win32Utils" -PassThru -ErrorAction SilentlyContinue
$hwnd = [Win32Utils.Win32ShowWindow]::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) {
    [Win32Utils.Win32ShowWindow]::ShowWindow($hwnd, 0) | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# [2] C# NATIVE MEMORY & ADVANCED HEADSHOT SCANNER ENGINE
$cSharpCode = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Threading.Tasks;
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

    public struct MEM_INFO { public IntPtr Base; public IntPtr AllocationBase; public uint AllocationProtect; public IntPtr RegionSize; public uint State; public uint Protect; public uint Type; }

    public static IntPtr ScanHeadshotAddress(IntPtr hProc) {
        var regions = new List<MEM_INFO>();
        IntPtr addr = IntPtr.Zero;
        while (true) {
            MEM_INFO mbi;
            if (VirtualQueryEx(hProc, addr, out mbi, Marshal.SizeOf(typeof(MEM_INFO))) == 0) break;
            if (mbi.State == 0x1000 && (mbi.Protect & 0x100) == 0 && (mbi.Protect & 0x40) != 0) regions.Add(mbi);
            long next = mbi.Base.ToInt64() + mbi.RegionSize.ToInt64();
            if (next <= addr.ToInt64()) break;
            addr = new IntPtr(next);
        }

        IntPtr foundAddr = IntPtr.Zero;
        int blockSize = 1024 * 1024;

        Parallel.ForEach(regions, (r, state) => {
            if (foundAddr != IntPtr.Zero) state.Stop();
            byte[] buffer = new byte[blockSize + 16];
            long regionSize = r.RegionSize.ToInt64();
            for (long offset = 0; offset < regionSize; offset += blockSize) {
                if (foundAddr != IntPtr.Zero) break;
                int toRead = (int)Math.Min(blockSize + 16, regionSize - offset);
                int read;
                if (ReadProcessMemory(hProc, new IntPtr(r.Base.ToInt64() + offset), buffer, toRead, out read)) {
                    for (int i = 0; i < read - 4; i++) {
                        if (buffer[i] == 0x00 && buffer[i+1] == 0x00 && buffer[i+2] == 0xA0 && buffer[i+3] == 0x40) {
                            foundAddr = new IntPtr(r.Base.ToInt64() + offset + i);
                            state.Stop();
                            break;
                        }
                    }
                }
            }
        });

        return foundAddr;
    }
}
'@

try {
    if (-not ([System.Management.Automation.PSTypeName]"WinSystemCore").Type) {
        Add-Type -TypeDefinition $cSharpCode -ReferencedAssemblies "System", "System.Core", "System.Runtime.InteropServices" -ErrorAction Stop
    }
} catch {
    Exit
}

# [3] DECODED PROCESS NAMES
function Get-DecodedString($base64) {
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
}
$pName1 = Get-DecodedString "Rml2ZU1fR1RBUHJvY2Vzcw==" # FiveM
$pName2 = Get-DecodedString "R1RBUHJvY2Vzcw=="      # GTA

# [4] MODERN CYBERPUNK UI (DARK PURPLE & DEEP BLACK #0A001A / #330055)
$form = New-Object System.Windows.Forms.Form
$form.Text = "NEVERS - Headshot Control Center"
$form.Size = New-Object System.Drawing.Size(430, 610)
$form.BackColor = [System.Drawing.Color]::FromArgb(10, 0, 26)
$form.ForeColor = [System.Drawing.Color]::FromArgb(247, 241, 255)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Icon = [System.Drawing.SystemIcons]::Application

# Title Header
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "NEVERS HEADSHOT ENGINE"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblTitle.Size = New-Object System.Drawing.Size(380, 25)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($lblTitle)

# Status Badge Panel
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "สถานะ: พร้อมสแกนหาจุดหัวอัติโนมัติ (Ready)"
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblStatus.BackColor = [System.Drawing.Color]::FromArgb(35, 18, 55)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblStatus.Size = New-Object System.Drawing.Size(370, 35)
$lblStatus.Location = New-Object System.Drawing.Point(22, 48)
$form.Controls.Add($lblStatus)

# Main Circle Arm Button
$btnArm = New-Object System.Windows.Forms.Button
$btnArm.Text = "ปิดอยู่`r`n(คลิกเพื่อเปิด)"
$btnArm.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnArm.BackColor = [System.Drawing.Color]::FromArgb(51, 0, 85)
$btnArm.ForeColor = [System.Drawing.Color]::White
$btnArm.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnArm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
$btnArm.Size = New-Object System.Drawing.Size(120, 120)
$btnArm.Location = New-Object System.Drawing.Point(147, 92)
$form.Controls.Add($btnArm)

# Mode Selector Label
$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = "โหมดการทำงาน (Operation Mode)"
$lblMode.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblMode.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
$lblMode.Size = New-Object System.Drawing.Size(370, 20)
$lblMode.Location = New-Object System.Drawing.Point(22, 230)
$form.Controls.Add($lblMode)

# Mode Buttons (Toggle / Hold)
$btnToggleMode = New-Object System.Windows.Forms.Button
$btnToggleMode.Text = "กดสลับ (Toggle)"
$btnToggleMode.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnToggleMode.BackColor = [System.Drawing.Color]::FromArgb(76, 29, 149)
$btnToggleMode.ForeColor = [System.Drawing.Color]::White
$btnToggleMode.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnToggleMode.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
$btnToggleMode.Size = New-Object System.Drawing.Size(180, 32)
$btnToggleMode.Location = New-Object System.Drawing.Point(22, 255)
$form.Controls.Add($btnToggleMode)

$btnHoldMode = New-Object System.Windows.Forms.Button
$btnHoldMode.Text = "กดค้าง (Hold)"
$btnHoldMode.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnHoldMode.BackColor = [System.Drawing.Color]::FromArgb(25, 10, 45)
$btnHoldMode.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
$btnHoldMode.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHoldMode.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(75, 40, 110)
$btnHoldMode.Size = New-Object System.Drawing.Size(180, 32)
$btnHoldMode.Location = New-Object System.Drawing.Point(212, 255)
$form.Controls.Add($btnHoldMode)

# Hotkey Label & Custom Bind Button
$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "ปุ่มลัด: [ CAPS ]"
$lblKey.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblKey.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
$lblKey.Size = New-Object System.Drawing.Size(215, 25)
$lblKey.Location = New-Object System.Drawing.Point(22, 300)
$form.Controls.Add($lblKey)

$btnCustomKey = New-Object System.Windows.Forms.Button
$btnCustomKey.Text = "🎯 ตั้งปุ่มเอง (Press Key)"
$btnCustomKey.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$btnCustomKey.BackColor = [System.Drawing.Color]::FromArgb(126, 34, 206)
$btnCustomKey.ForeColor = [System.Drawing.Color]::White
$btnCustomKey.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCustomKey.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(216, 180, 254)
$btnCustomKey.Size = New-Object System.Drawing.Size(150, 28)
$btnCustomKey.Location = New-Object System.Drawing.Point(242, 296)
$form.Controls.Add($btnCustomKey)

# Preset Hotkey Buttons Grid
$keys = @("CAPS", "SHIFT", "CTRL", "ALT", "F", "E", "Q", "X")
$keyButtons = @{}
$xPos = 22; $yPos = 332
for($i=0; $i -lt $keys.Length; $i++) {
    $k = $keys[$i]
    $kb = New-Object System.Windows.Forms.Button
    $kb.Text = $k
    $kb.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $kb.Size = New-Object System.Drawing.Size(86, 30)
    $kb.Location = New-Object System.Drawing.Point($xPos, $yPos)
    $kb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    if($k -eq "CAPS") {
        $kb.BackColor = [System.Drawing.Color]::FromArgb(76, 29, 149)
        $kb.ForeColor = [System.Drawing.Color]::White
        $kb.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
    } else {
        $kb.BackColor = [System.Drawing.Color]::FromArgb(25, 10, 45)
        $kb.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
        $kb.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(75, 40, 110)
    }
    $form.Controls.Add($kb)
    $keyButtons[$k] = $kb
    $xPos += 94
    if(($i + 1) % 4 -eq 0) { $xPos = 22; $yPos += 36 }
}

# Action Buttons
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "🚀 สแกนหาจุดหัวอัติโนมัติ (Auto-Scan Headshot)"
$btnScan.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnScan.BackColor = [System.Drawing.Color]::FromArgb(16, 185, 129)
$btnScan.ForeColor = [System.Drawing.Color]::White
$btnScan.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnScan.FlatAppearance.BorderSize = 0
$btnScan.Size = New-Object System.Drawing.Size(370, 35)
$btnScan.Location = New-Object System.Drawing.Point(22, 415)
$form.Controls.Add($btnScan)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "🔄 คืนค่าแรมเดิม (Restore)"
$btnRestore.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnRestore.BackColor = [System.Drawing.Color]::FromArgb(217, 119, 6)
$btnRestore.ForeColor = [System.Drawing.Color]::White
$btnRestore.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRestore.FlatAppearance.BorderSize = 0
$btnRestore.Size = New-Object System.Drawing.Size(370, 35)
$btnRestore.Location = New-Object System.Drawing.Point(22, 455)
$form.Controls.Add($btnRestore)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "🗑️ ล้างร่องรอยความปลอดภัย (Zero-Trace)"
$btnClear.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(45, 20, 70)
$btnClear.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
$btnClear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClear.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(107, 33, 168)
$btnClear.Size = New-Object System.Drawing.Size(370, 35)
$btnClear.Location = New-Object System.Drawing.Point(22, 495)
$form.Controls.Add($btnClear)

# State Variables
$global:appState = [PSCustomObject]@{
    Armed = $false
    Mode = "toggle"
    Hotkey = 0x14
    HotkeyName = "CAPS"
    Action = "none"
    IsListeningKey = $false
}

# UI Event Handlers
$btnToggleMode.Add_Click({
    $global:appState.Mode = "toggle"
    $btnToggleMode.BackColor = [System.Drawing.Color]::FromArgb(76, 29, 149)
    $btnToggleMode.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
    $btnHoldMode.BackColor = [System.Drawing.Color]::FromArgb(25, 10, 45)
    $btnHoldMode.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(75, 40, 110)
})

$btnHoldMode.Add_Click({
    $global:appState.Mode = "hold"
    $btnHoldMode.BackColor = [System.Drawing.Color]::FromArgb(76, 29, 149)
    $btnHoldMode.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
    $btnToggleMode.BackColor = [System.Drawing.Color]::FromArgb(25, 10, 45)
    $btnToggleMode.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(75, 40, 110)
})

foreach($k in $keys) {
    $keyButtons[$k].Add_Click({
        switch ($k) {
            "CAPS"  { $global:appState.Hotkey = 0x14 }
            "SHIFT" { $global:appState.Hotkey = 0xA0 }
            "CTRL"  { $global:appState.Hotkey = 0xA2 }
            "ALT"   { $global:appState.Hotkey = 0xA4 }
            "F"     { $global:appState.Hotkey = 70 }
            "E"     { $global:appState.Hotkey = 69 }
            "Q"     { $global:appState.Hotkey = 81 }
            "X"     { $global:appState.Hotkey = 88 }
        }
        $global:appState.HotkeyName = $k
        $lblKey.Text = "ปุ่มลัด: [ $k ]"

        foreach($other in $keys) {
            if($other -eq $k) {
                $keyButtons[$other].BackColor = [System.Drawing.Color]::FromArgb(76, 29, 149)
                $keyButtons[$other].FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
            } else {
                $keyButtons[$other].BackColor = [System.Drawing.Color]::FromArgb(25, 10, 45)
                $keyButtons[$other].FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(75, 40, 110)
            }
        }
    })
}

$btnCustomKey.Add_Click({
    $global:appState.IsListeningKey = $true
    $lblKey.Text = "⏳ กดปุ่มบนคีย์บอร์ด..."
    $lblKey.ForeColor = [System.Drawing.Color]::FromArgb(244, 63, 94)
})

$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($global:appState.IsListeningKey) {
        $vkCode = [int]$e.KeyCode
        $keyName = $e.KeyCode.ToString()
        $global:appState.Hotkey = $vkCode
        $global:appState.HotkeyName = $keyName
        $global:appState.IsListeningKey = $false
        $lblKey.Text = "ปุ่มลัด: [ $keyName ]"
        $lblKey.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
        [WinSystemCore]::Beep(1500, 100)
    }
})

$btnArm.Add_Click({
    $global:appState.Armed = -not $global:appState.Armed
    if($global:appState.Armed) {
        $btnArm.Text = "เปิดอยู่`r`n(Active)"
        $btnArm.BackColor = [System.Drawing.Color]::FromArgb(126, 34, 206)
        $btnArm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(216, 180, 254)
    } else {
        $btnArm.Text = "ปิดอยู่`r`n(คลิกเพื่อเปิด)"
        $btnArm.BackColor = [System.Drawing.Color]::FromArgb(51, 0, 85)
        $btnArm.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(168, 85, 247)
    }
})

$btnScan.Add_Click({ $global:appState.Action = "scan" })
$btnRestore.Add_Click({ $global:appState.Action = "restore" })
$btnClear.Add_Click({ $global:appState.Action = "clear" })

# [5] BACKGROUND WORKER & AUTO HEADSHOT PATCH LOOP
$hProc = [IntPtr]::Zero
$headshotAddr = [IntPtr]::Zero
$isPatched = $false
$toggle = $false
$wasKeyDown = $false

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 20
$timer.Add_Tick({
    $act = $global:appState.Action
    if ($act -ne "none") {
        $global:appState.Action = "none"
        if ($act -eq "scan") {
            $lblStatus.Text = "สถานะ: กำลังสแกนหาจุดหัวในหน่วยความจำ..."
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(234, 179, 8)
            $proc = Get-Process | Where-Object { $_.ProcessName -match "$pName1|$pName2" } | Select-Object -First 1
            if ($proc) {
                if ($hProc -ne [IntPtr]::Zero) { [WinSystemCore]::CloseHandle($hProc) | Out-Null }
                $hProc = [WinSystemCore]::OpenProcess(0x1F0FFF, $false, $proc.Id)
                
                $headshotAddr = [WinSystemCore]::ScanHeadshotAddress($hProc)
                if ($headshotAddr -ne [IntPtr]::Zero) {
                    $lblStatus.Text = "สถานะ: ล็อกเป้าหมายเฉพาะจุดหัวสำเร็จ (Headshot Only Ready)"
                    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
                    [WinSystemCore]::Beep(1200, 250)
                } else {
                    $lblStatus.Text = "สถานะ: ไม่พบจุดหัว (กรุณาเข้าสู่เกมก่อนกดสแกน)"
                    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(244, 63, 94)
                }
            } else {
                $lblStatus.Text = "สถานะ: ไม่พบโปรเซสเกม (กรุณาเปิดเกมก่อนกดสแกน)"
                $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(244, 63, 94)
            }
        }
        elseif ($act -eq "restore") {
            if ($hProc -ne [IntPtr]::Zero) {
                [WinSystemCore]::CloseHandle($hProc) | Out-Null
                $hProc = [IntPtr]::Zero
                $headshotAddr = [IntPtr]::Zero
                $isPatched = $false
            }
            $lblStatus.Text = "สถานะ: คืนค่าแรมเดิมเรียบร้อย (Restored)"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
        }
        elseif ($act -eq "clear") {
            Clear-History -ErrorAction SilentlyContinue
            Clear-Clipboard
            try { Clear-EventLog -LogName "Security", "System", "Application" -ErrorAction SilentlyContinue } catch {}
            $lblStatus.Text = "สถานะ: ล้างร่องรอยและคลิปบอร์ดเกลี้ยงแล้ว"
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(196, 176, 228)
        }
    }

    if ($global:appState.Armed -and $headshotAddr -ne [IntPtr]::Zero -and -not $global:appState.IsListeningKey) {
        $targetKey = $global:appState.Hotkey
        $isKeyDown = ([WinSystemCore]::GetAsyncKeyState($targetKey) -band 0x8000)
        
        $shouldPatch = $false
        if ($global:appState.Mode -eq "toggle") {
            if ($isKeyDown -and -not $wasKeyDown) {
                $toggle = -not $toggle
                [WinSystemCore]::Beep($(if($toggle){1400}else{700}), 100)
            }
            $shouldPatch = $toggle
        } else {
            $shouldPatch = $isKeyDown
        }

        if ($shouldPatch -and -not $isPatched) {
            [uint32]$old = 0
            [int]$written = 0
            $patchData = [byte[]] @(0x00, 0x00, 0x20, 0x41)
            if ([WinSystemCore]::VirtualProtectEx($hProc, $headshotAddr, $patchData.Length, 0x40, [ref]$old)) {
                [WinSystemCore]::WriteProcessMemory($hProc, $headshotAddr, $patchData, $patchData.Length, [ref]$written) | Out-Null
                [WinSystemCore]::VirtualProtectEx($hProc, $headshotAddr, $patchData.Length, $old, [ref]$old) | Out-Null
                $isPatched = $true
            }
        } elseif (-not $shouldPatch -and $isPatched) {
            [uint32]$old = 0
            [int]$written = 0
            $origData = [byte[]] @(0x00, 0x00, 0xA0, 0x40)
            if ([WinSystemCore]::VirtualProtectEx($hProc, $headshotAddr, $origData.Length, 0x40, [ref]$old)) {
                [WinSystemCore]::WriteProcessMemory($hProc, $headshotAddr, $origData, $origData.Length, [ref]$written) | Out-Null
                [WinSystemCore]::VirtualProtectEx($hProc, $headshotAddr, $origData.Length, $old, [ref]$old) | Out-Null
                $isPatched = $false
            }
        }
        $wasKeyDown = $isKeyDown
    }
})
$timer.Start()

# [6] AUTO WIPE & UNINSTALL ON CLOSE
$form.Add_FormClosed({
    $timer.Stop()
    if ($hProc -ne [IntPtr]::Zero) {
        [WinSystemCore]::CloseHandle($hProc) | Out-Null
    }
    Clear-History -ErrorAction SilentlyContinue
    Clear-Clipboard
    try {
        Clear-EventLog -LogName "Security", "System", "Application" -ErrorAction SilentlyContinue
    } catch {}
})

[void]$form.ShowDialog()
