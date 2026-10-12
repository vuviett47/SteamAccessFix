<# :
@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SteamAccessFix
set "SELF=%~f0"

:: Tu nang quyen Administrator neu chua co
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

:: Chay phan PowerShell ben duoi file
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $i=$s.IndexOf('#PSBEGIN'+'#'); iex $s.Substring($i)"
exit /b
: end batch / begin powershell #>

#PSBEGIN#
# ================================================================
#  SteamAccessFix v1.1.0 - All-In-One Game & Store Fix (Windows)
#  Pure User-Mode  |  No Drivers  |  Anti-Cheat Safe
# ================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# Fix hien thi tieng Viet co dau trong console Windows
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
try { chcp 65001 | Out-Null } catch { }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
$Host.UI.RawUI.WindowTitle = 'SteamAccessFix v1.1.0'

# --- Cấu hình ---
$script:AppVersion  = '1.1.0'
$script:GitHubRepo  = 'vuviett47/SteamAccessFix'
$script:AutoUpdate  = $false

# Đảm bảo đường dẫn SELF luôn chính xác khi chạy từ file
if (-not $env:SELF -or -not (Test-Path $env:SELF)) {
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $env:SELF = $PSCommandPath }
    elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { $env:SELF = $MyInvocation.MyCommand.Path }
}

# Kiểm tra quyền Administrator khi chạy trực tiếp từ PowerShell (irm | iex)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n  [!] Đang yêu cầu quyền Administrator..." -ForegroundColor Yellow
    if ($env:SELF -and (Test-Path $env:SELF)) {
        Start-Process -FilePath $env:SELF -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/$($script:GitHubRepo)/main/SteamAccessFix.cmd | iex`"" -Verb RunAs
    }
    return
}

# --- Đường dẫn lưu trữ ---
$ThuMucLuu     = Join-Path $env:ProgramData 'SteamAccessFix'
$FileDns       = Join-Path $ThuMucLuu 'dns-backup.json'
$FileProxy     = Join-Path $ThuMucLuu 'proxy-backup.json'
$FileHosts     = Join-Path $ThuMucLuu 'hosts-backup.txt'
$FileNetTweaks = Join-Path $ThuMucLuu 'net-tweaks-backup.json'
$FileHostsSys  = "$env:SystemRoot\System32\drivers\etc\hosts"
$RegIE         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$CongProxy     = 18080

# --- Danh sách dịch vụ kiểm tra kết nối ---
$CacTrang = @(
    @{ Ten = 'Steam Store';      Url = 'https://store.steampowered.com/' },
    @{ Ten = 'Steam CDN';        Url = 'https://shared.fastly.steamstatic.com/' },
    @{ Ten = 'CS2 Official';     Url = 'https://www.counter-strike.net/' },
    @{ Ten = 'Dota 2 Official';  Url = 'https://www.dota2.com/' },
    @{ Ten = 'PUBG Lobby';       Url = 'https://prod-live-front.playbattlegrounds.com/' },
    @{ Ten = 'Naraka Official';  Url = 'https://www.narakathegame.com/' },
    @{ Ten = 'Delta Force';      Url = 'https://www.playdeltaforce.com/' }
)

# --- Domain định tuyến qua proxy (chỉ Web/Lobby/GC, UDP trận đấu đi DIRECT) ---
$AllGameDomains = @(
    'steampowered.com', 'steamcommunity.com', 'steamstatic.com',
    'steam-chat.com', 'steamusercontent.com', 'steamgames.com', 'steamcontent.com',
    'counter-strike.net', 'dota2.com', 'valvesoftware.com',
    'playbattlegrounds.com', 'pubg.com', 'krafton.com',
    'narakathegame.com', '24entertainment.net',
    'playdeltaforce.com', 'levelinfinite.com'
)

# --- Trạng thái ---
$script:DaThayDoiDns    = $false
$script:DaThayDoiProxy  = $false
$script:DaThayDoiHosts  = $false
$script:DaThayDoiTweaks = $false
$script:Proxy           = $null
$script:CongDangDung    = 0
$script:MoTa            = ''
$script:CurrentLevel    = 0

New-Item -ItemType Directory -Force -Path $ThuMucLuu | Out-Null

# ================================================================
#  GIAO DIỆN UI/UX
# ================================================================
function Say($m, $mau = 'Gray') { Write-Host $m -ForegroundColor $mau }
function Ok($m)   { Say "  [OK]   $m" 'Green' }
function Warn($m) { Say "  [!]    $m" 'Yellow' }
function Err($m)  { Say "  [X]    $m" 'Red' }
function Info($m) { Say "  [~]    $m" 'Cyan' }
function Sep()    { Say '  ---------------------------------------------------------------' 'DarkGray' }

function Ve-Khung($tieuDe, $phuDe = '', $mau = 'Cyan') {
    Say ''
    Say '  ===============================================================' $mau
    Say "   $tieuDe" $mau
    if ($phuDe) {
        Say "   $phuDe" 'DarkGray'
    }
    Say '  ===============================================================' $mau
    Say ''
}

function Ve-KhungNho($tieuDe, $mau = 'Yellow') {
    Say '  ---------------------------------------------------------------' $mau
    Say "   $tieuDe" $mau
    Say '  ---------------------------------------------------------------' $mau
}

function Buoc($n, $m) {
    Say ''
    Sep
    Say "  [ Cấp độ $n ]  $m" 'Cyan'
    Sep
}

function Hoi-CoKhong($cauHoi, $macDinhCo = $true) {
    $hint = if ($macDinhCo) { 'C/Y=Có  K/N=Không  Enter=Có' } else { 'C/Y=Có  K/N=Không  Enter=Không' }
    while ($true) {
        Write-Host "  $cauHoi " -ForegroundColor Yellow -NoNewline
        Write-Host "[$hint] " -ForegroundColor DarkGray -NoNewline
        $r = Read-Host
        if ($r -eq '') { return $macDinhCo }
        if ($r -match '^[cCyY]') { return $true }
        if ($r -match '^[kKnN]') { return $false }
    }
}

function Hoi-Menu($tieuDe, [string[]]$mucChon) {
    Say ''
    Say "  $tieuDe" 'Yellow'
    Say ''
    for ($i = 0; $i -lt $mucChon.Length; $i++) {
        Write-Host "    " -NoNewline
        Write-Host " $($i + 1) " -ForegroundColor Black -BackgroundColor DarkCyan -NoNewline
        Write-Host "  $($mucChon[$i])" -ForegroundColor White
    }
    Say ''
    while ($true) {
        Write-Host "  Chọn số (1-$($mucChon.Length)): " -ForegroundColor DarkGray -NoNewline
        $r = Read-Host
        if ($r -match '^\d+$') {
            $idx = [int]$r - 1
            if ($idx -ge 0 -and $idx -lt $mucChon.Length) { return $idx }
        }
        Err "Chỉ nhập số từ 1 đến $($mucChon.Length)."
    }
}

# ================================================================
#  MÃ C# SPLITPROXY NHÚNG SẴN
# ================================================================
$MaProxy = @'
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class SplitProxy
{
    public int Port;
    public int Mode = 2;
    public int Connections = 0;
    public string Pac = "";
    private TcpListener listener;
    private volatile bool running;
    private byte[] pacBytes;
    private static ConcurrentDictionary<string, IPAddress> dnsCache = new ConcurrentDictionary<string, IPAddress>();

    public static IPAddress ResolveSafe(string host)
    {
        IPAddress cached;
        if (dnsCache.TryGetValue(host, out cached)) return cached;

        try {
            IPAddress[] addrs = Dns.GetHostAddresses(host);
            foreach (var a in addrs) {
                if (a.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a)) {
                    dnsCache[host] = a;
                    return a;
                }
            }
        } catch { }

        try {
            using (var wc = new WebClient()) {
                wc.Headers[HttpRequestHeader.Accept] = "application/dns-json";
                string json = wc.DownloadString("https://dns.google/resolve?name=" + host + "&type=A");
                int idx = json.IndexOf("\"data\":\"");
                while (idx > 0) {
                    int end = json.IndexOf("\"", idx + 8);
                    if (end > idx) {
                        string ipStr = json.Substring(idx + 8, end - idx - 8);
                        IPAddress parsed;
                        if (IPAddress.TryParse(ipStr, out parsed) && !IPAddress.IsLoopback(parsed)) {
                            dnsCache[host] = parsed;
                            return parsed;
                        }
                    }
                    idx = json.IndexOf("\"data\":\"", end);
                }
            }
        } catch { }

        return null;
    }

    public SplitProxy(int port) { Port = port; }

    public void Start()
    {
        pacBytes = Encoding.UTF8.GetBytes(Pac == null ? "" : Pac);
        listener = new TcpListener(IPAddress.Loopback, Port);
        listener.Start();
        running = true;
        Thread t = new Thread(new ThreadStart(AcceptLoop));
        t.IsBackground = true;
        t.Start();
    }

    public void Stop()
    {
        running = false;
        try { listener.Stop(); } catch (Exception) { }
    }

    private void AcceptLoop()
    {
        while (running)
        {
            try { TcpClient c = listener.AcceptTcpClient(); ThreadPool.QueueUserWorkItem(new WaitCallback(Handle), c); }
            catch (Exception) { if (!running) return; }
        }
    }

    private static int HeaderEnd(byte[] b, int len)
    {
        for (int i = 0; i + 3 < len; i++)
            if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
        return -1;
    }

    private static void SplitHostPort(string hp, out string host, out int port)
    {
        port = 443;
        int idx = hp.LastIndexOf(':');
        if (hp.StartsWith("[")) {
            int close = hp.IndexOf(']');
            if (close > 1) {
                host = hp.Substring(1, close - 1);
                if (idx > close && idx + 1 < hp.Length) int.TryParse(hp.Substring(idx + 1), out port);
                return;
            }
        }
        if (idx > 0 && idx + 1 < hp.Length) { host = hp.Substring(0, idx); int.TryParse(hp.Substring(idx + 1), out port); }
        else host = hp;
    }

    private static int FindSni(byte[] d, int len, out int nameLen)
    {
        nameLen = 0;
        try {
            if (len < 43 || d[0] != 0x16 || d[5] != 0x01) return -1;
            int p = 5 + 4 + 2 + 32;
            p += 1 + d[p];
            p += 2 + ((d[p] << 8) | d[p + 1]);
            p += 1 + d[p];
            int extEnd = p + 2 + ((d[p] << 8) | d[p + 1]);
            p += 2;
            while (p + 4 <= extEnd && p + 4 <= len) {
                int type = (d[p] << 8) | d[p + 1];
                int el   = (d[p + 2] << 8) | d[p + 3];
                if (type == 0) { int q = p + 4 + 2 + 1; nameLen = (d[q] << 8) | d[q + 1]; return q + 2; }
                p += 4 + el;
            }
        } catch (Exception) { }
        return -1;
    }

    private void SendSplit(NetworkStream ss, byte[] d, int len, int mode)
    {
        int nameLen;
        int sni   = FindSni(d, len, out nameLen);
        int mid   = (sni > 0 && nameLen > 1) ? sni + nameLen / 2 : 1;
        int first = (sni > 0) ? sni + 1 : 1;
        int[] cuts;
        if      (mode == 2) cuts = new int[] { 1 };
        else if (mode == 3) cuts = new int[] { 1, mid };
        else if (mode == 4) cuts = new int[] { first };
        else                cuts = new int[] { mid };
        int pos = 0;
        foreach (int c in cuts) {
            if (c <= pos || c >= len) continue;
            ss.Write(d, pos, c - pos); ss.Flush();
            Thread.Sleep(25);
            pos = c;
        }
        ss.Write(d, pos, len - pos); ss.Flush();
    }

    private static void Pump(Stream from, Stream to, TcpClient a, TcpClient b)
    {
        byte[] buf = new byte[32768];
        try { int n; while ((n = from.Read(buf, 0, buf.Length)) > 0) to.Write(buf, 0, n); } catch (Exception) { }
        try { a.Close(); } catch (Exception) { }
        try { b.Close(); } catch (Exception) { }
    }

    private void Handle(object state)
    {
        TcpClient client = (TcpClient)state;
        TcpClient server = null;
        try {
            client.NoDelay = true;
            client.ReceiveTimeout = 15000;
            NetworkStream cs = client.GetStream();
            byte[] buf = new byte[16384];
            int len = 0, he = -1;
            while (he < 0) {
                if (len >= buf.Length) return;
                int n = cs.Read(buf, len, buf.Length - len);
                if (n <= 0) return;
                len += n;
                he = HeaderEnd(buf, len);
            }
            string head    = Encoding.ASCII.GetString(buf, 0, he);
            string line    = head.Split('\n')[0].Trim();
            string[] parts = line.Split(' ');
            if (parts.Length < 2) return;
            string method  = parts[0].ToUpperInvariant();

            if (method == "GET" && parts[1].StartsWith("/proxy.pac")) {
                string h = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\nContent-Length: " + pacBytes.Length + "\r\nConnection: close\r\n\r\n";
                byte[] hb = Encoding.ASCII.GetBytes(h);
                cs.Write(hb, 0, hb.Length);
                cs.Write(pacBytes, 0, pacBytes.Length);
                return;
            }
            if (method != "CONNECT") {
                byte[] r = Encoding.ASCII.GetBytes("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                cs.Write(r, 0, r.Length); return;
            }

            string host; int port;
            SplitHostPort(parts[1], out host, out port);
            IPAddress targetIp = ResolveSafe(host);

            server = new TcpClient();
            server.NoDelay = true;
            if (targetIp != null) server.Connect(targetIp, port);
            else server.Connect(host, port);
            byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
            cs.Write(ok, 0, ok.Length);
            Interlocked.Increment(ref Connections);

            NetworkStream ss = server.GetStream();
            byte[] first = new byte[16384];
            client.ReceiveTimeout = 8000;
            int fl = cs.Read(first, 0, first.Length);
            if (fl <= 0) return;
            if (first[0] == 0x16 && fl >= 5) {
                int need = 5 + ((first[3] << 8) | first[4]);
                while (fl < need && fl < first.Length) { int n2 = cs.Read(first, fl, first.Length - fl); if (n2 <= 0) break; fl += n2; }
                SendSplit(ss, first, fl, Mode);
            } else ss.Write(first, 0, fl);
            client.ReceiveTimeout = 0;

            TcpClient sv = server, cl = client;
            Thread t = new Thread(delegate() { Pump(ss, cs, sv, cl); });
            t.IsBackground = true; t.Start();
            Pump(cs, ss, cl, sv);
        } catch (Exception) { }
        finally {
            try { client.Close(); } catch (Exception) { }
            try { if (server != null) server.Close(); } catch (Exception) { }
        }
    }
}
'@

# ================================================================
#  QUẢN LÝ DNS
# ================================================================
function Save-Dns {
    if (Test-Path $FileDns) { return }
    $ds = foreach ($a in (Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{
            Index = $a.ifIndex
            NS4   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)"  -EA SilentlyContinue).NameServer
            NS6   = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$($a.InterfaceGuid)" -EA SilentlyContinue).NameServer
        }
    }
    @($ds) | ConvertTo-Json -Depth 3 | Set-Content -Path $FileDns -Encoding ASCII
}

function Restore-Dns {
    if (Test-Path $FileDns) {
        try {
            foreach ($a in @(Get-Content $FileDns -Raw | ConvertFrom-Json)) {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -EA SilentlyContinue
                $cds = @($a.NS4, $a.NS6) | Where-Object { $_ }
                if ($cds.Count -gt 0) { Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses $cds -EA SilentlyContinue }
            }
            Remove-Item $FileDns -Force -EA SilentlyContinue
        } catch { }
    }
    ipconfig /flushdns | Out-Null
    $script:DaThayDoiDns = $false
}

function Set-GoogleDns {
    Save-Dns
    $script:DaThayDoiDns = $true
    $adapters = @(Get-NetAdapter -Physical -EA SilentlyContinue | Where-Object Status -eq 'Up')
    if ($adapters.Count -eq 0) { $adapters = @(Get-NetAdapter -EA SilentlyContinue | Where-Object Status -eq 'Up') }
    foreach ($a in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses '8.8.8.8','8.8.4.4','2001:4860:4860::8888','2001:4860:4860::8844' -EA SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    Start-Sleep -Milliseconds 600
}

# ================================================================
#  QUẢN LÝ PROXY (PAC + SplitProxy)
# ================================================================
function Notify-Inet {
    if (-not ('Win.Inet' -as [type])) {
        try { Add-Type -Namespace Win -Name Inet -MemberDefinition '[System.Runtime.InteropServices.DllImport("wininet.dll")] public static extern bool InternetSetOption(System.IntPtr h, int o, System.IntPtr b, int l);' -EA SilentlyContinue } catch { }
    }
    try {
        [Win.Inet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [Win.Inet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch { }
}

function Save-ProxyCfg {
    if (Test-Path $FileProxy) { return }
    $cu = (Get-ItemProperty $RegIE -EA SilentlyContinue).AutoConfigURL
    [pscustomobject]@{ Co = [bool]$cu; Url = $cu } | ConvertTo-Json | Set-Content -Path $FileProxy -Encoding ASCII
}

function Restore-ProxyCfg {
    if (Test-Path $FileProxy) {
        try {
            $b = Get-Content $FileProxy -Raw | ConvertFrom-Json
            if ($b.Co) { Set-ItemProperty -Path $RegIE -Name AutoConfigURL -Value $b.Url }
            else        { Remove-ItemProperty -Path $RegIE -Name AutoConfigURL -EA SilentlyContinue }
            Remove-Item $FileProxy -Force -EA SilentlyContinue
            Notify-Inet
        } catch { }
    }
    $script:DaThayDoiProxy = $false
    $script:CongDangDung   = 0
}

function Stop-ProxyMode {
    if ($script:Proxy) { try { $script:Proxy.Stop() } catch { } ; $script:Proxy = $null }
    Restore-ProxyCfg
}

function Build-PacContent($port) {
    $domainsJs = ($AllGameDomains | ForEach-Object { "`"$_`"" }) -join ', '
    return @"
function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  if (url.substring(0, 5) == "http:") return "DIRECT";
  var d = [$domainsJs];
  for (var i = 0; i < d.length; i++) {
    if (host == d[i] || dnsDomainIs(host, "." + d[i])) return "PROXY 127.0.0.1:$port";
  }
  return "DIRECT";
}
"@
}

function Test-Canary([int]$Port = 0) {
    $ca = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--connect-timeout', '2', '--max-time', '3', '-4')
    if ($Port -gt 0) { $ca += @('--proxy', "http://127.0.0.1:$Port") }
    $cSteam = & curl.exe @ca 'https://store.steampowered.com/'
    $cPubg  = & curl.exe @ca 'https://prod-live-front.playbattlegrounds.com/'
    return (($cSteam -and $cSteam -ne '000') -and ($cPubg -and $cPubg -ne '000'))
}

function Start-ProxyMode([int]$forceMode = 0) {
    if (-not ('SplitProxy' -as [type])) {
        try { Add-Type -TypeDefinition $MaProxy -Language CSharp -EA Stop }
        catch { Err "Không khởi tạo được proxy: $($_.Exception.Message)"; return $false }
    }

    $px = $null; $cong = 0
    foreach ($p in $CongProxy..($CongProxy + 10)) {
        try {
            $x = New-Object SplitProxy -ArgumentList $p
            $x.Pac = Build-PacContent $p
            $x.Start()
            $px = $x; $cong = $p; break
        } catch { }
    }
    if (-not $px) { Err 'Không mở được cổng proxy nào.'; return $false }

    $script:Proxy        = $px
    $script:CongDangDung = $cong
    Save-ProxyCfg
    Set-ItemProperty -Path $RegIE -Name AutoConfigURL -Value "http://127.0.0.1:$cong/proxy.pac"
    Notify-Inet
    $script:DaThayDoiProxy = $true
    Ok "Proxy nội bộ đang chạy tại cổng $cong"

    # Ưu tiên Mode 2 & 3 vì đây là kiểu phân mảnh vượt được cả DPI gắt của PUBG lẫn Steam
    $modesToTry = if ($forceMode -gt 0) { @($forceMode) } else { @(2, 3, 1, 4) }
    $bestMode = 0
    foreach ($m in $modesToTry) {
        Say "       Thử kiểu cắt gói SNI #$m ..." 'DarkGray'
        $px.Mode = $m
        Start-Sleep -Milliseconds 150
        $ca = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--connect-timeout', '2', '--max-time', '3', '-4', '--proxy', "http://127.0.0.1:$cong")
        $cSteam = & curl.exe @ca 'https://store.steampowered.com/'
        $cPubg  = & curl.exe @ca 'https://prod-live-front.playbattlegrounds.com/'
        $okSteam = ($cSteam -and $cSteam -ne '000')
        $okPubg  = ($cPubg  -and $cPubg  -ne '000')

        if ($okSteam -and $okPubg) {
            Ok "Kiểu cắt gói #$m mở khóa thành công cả Steam và PUBG!"
            $script:MoTa = "SplitProxy Mode $m  (cổng $cong)"
            return $true
        }
        if ($okSteam -and $bestMode -eq 0) {
            $bestMode = $m
        }
    }
    if ($bestMode -gt 0) {
        $px.Mode = $bestMode
        Ok "Kiểu cắt gói #$bestMode mở khóa Steam thành công!"
        $script:MoTa = "SplitProxy Mode $bestMode  (cổng $cong)"
        return $true
    }
    Stop-ProxyMode
    return $false
}

# ================================================================
#  QUẢN LÝ FILE HOSTS
# ================================================================
function Save-Hosts {
    if (Test-Path $FileHosts) { return }
    if (Test-Path $FileHostsSys) { Copy-Item -Path $FileHostsSys -Destination $FileHosts -Force }
}

function Restore-Hosts {
    if (Test-Path $FileHosts) {
        try { Copy-Item -Path $FileHosts -Destination $FileHostsSys -Force; Remove-Item $FileHosts -Force -EA SilentlyContinue; ipconfig /flushdns | Out-Null } catch { }
    } elseif (Test-Path $FileHostsSys) {
        try {
            $lines = Get-Content $FileHostsSys | Where-Object { $_ -notmatch '#\s*SteamAccessFix' }
            Set-Content -Path $FileHostsSys -Value $lines -Encoding ASCII
            ipconfig /flushdns | Out-Null
        } catch { }
    }
    $script:DaThayDoiHosts = $false
}

# ================================================================
#  TỐI ƯU MẠNG GAME (FPT / VNPT)
# ================================================================
function Apply-GamingNetworkTweaks {
    if (Test-Path $FileNetTweaks) { return }
    try {
        $reg   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        $props = Get-ItemProperty $reg -EA SilentlyContinue
        [pscustomobject]@{
            NetworkThrottlingIndex = $props.NetworkThrottlingIndex
            SystemResponsiveness   = $props.SystemResponsiveness
        } | ConvertTo-Json | Set-Content -Path $FileNetTweaks -Encoding ASCII

        Set-ItemProperty -Path $reg -Name NetworkThrottlingIndex -Value 0xffffffff -EA SilentlyContinue
        Set-ItemProperty -Path $reg -Name SystemResponsiveness   -Value 0          -EA SilentlyContinue
        netsh int tcp set global autotuninglevel=normal | Out-Null
        $script:DaThayDoiTweaks = $true
    } catch { }
}

function Restore-GamingNetworkTweaks {
    if (Test-Path $FileNetTweaks) {
        try {
            $b   = Get-Content $FileNetTweaks -Raw | ConvertFrom-Json
            $reg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            if ($null -ne $b.NetworkThrottlingIndex) { Set-ItemProperty -Path $reg -Name NetworkThrottlingIndex -Value $b.NetworkThrottlingIndex -EA SilentlyContinue }
            if ($null -ne $b.SystemResponsiveness)   { Set-ItemProperty -Path $reg -Name SystemResponsiveness   -Value $b.SystemResponsiveness   -EA SilentlyContinue }
            Remove-Item $FileNetTweaks -Force -EA SilentlyContinue
        } catch { }
    }
    $script:DaThayDoiTweaks = $false
}

function Restore-All {
    Say ''
    Info 'Đang khôi phục toàn bộ cài đặt về trạng thái gốc...'
    Stop-ProxyMode
    Restore-GamingNetworkTweaks
    Restore-Hosts
    Restore-Dns
    Ok 'Hệ thống đã được khôi phục sạch sẽ.'
}

# ================================================================
#  KIỂM TRA KẾT NỐI DỊCH VỤ
# ================================================================
function Test-Connectivity([switch]$Show, [int]$Port = 0, [string]$ResolveParam = '') {
    $tatCa = $true
    foreach ($t in $CacTrang) {
        $ca = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--connect-timeout', '2', '--max-time', '3', '-4')
        if ($Port -gt 0)     { $ca += @('--proxy', "http://127.0.0.1:$Port") }
        if ($ResolveParam)   { $ca += @('--resolve', $ResolveParam) }
        $ma  = & curl.exe @ca $t.Url
        $tot = ($ma -and $ma -ne '000')
        if ($Show) {
            if ($tot) { Ok ("{0,-18}  HTTP {1}  OK" -f $t.Ten, $ma) }
            else      { Err ("{0,-18}  Bị chặn / Timeout"  -f $t.Ten) }
        }
        if (-not $tot) {
            $tatCa = $false
            if (-not $Show) { return $false }
        }
    }
    return $tatCa
}

# ================================================================
#  DOH DNS QUERY (FALLBACK)
# ================================================================
function Get-DoHIp([string]$domain) {
    foreach ($uri in @(
        "https://cloudflare-dns.com/dns-query?name=$domain&type=A",
        "https://dns.google/resolve?name=$domain&type=A"
    )) {
        try {
            $hdrs = if ($uri -match 'cloudflare') { @{ accept = 'application/dns-json' } } else { @{} }
            $ips  = @((Invoke-RestMethod -Uri $uri -Headers $hdrs -TimeoutSec 5 -EA Stop).Answer | Where-Object { $_.type -eq 1 } | Select-Object -ExpandProperty data | Where-Object { $_ -notmatch '^127\.' })
            if ($ips.Count -gt 0) { return $ips }
        } catch { }
    }
    return @()
}

# ================================================================
#  KIỂM TRA CẬP NHẬT GITHUB
# ================================================================
function Check-GitHubUpdate {
    if ([string]::IsNullOrWhiteSpace($script:GitHubRepo) -or $script:GitHubRepo -eq 'USERNAME/REPOSITORY') { return }
    # Nếu chạy trực tiếp từ bộ nhớ qua irm | iex thì không cần cập nhật file trên đĩa
    if (-not $env:SELF -or -not (Test-Path $env:SELF)) { return }
    try {
        Info "Kiểm tra cập nhật từ GitHub..."
        $tNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $remoteVer = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$($script:GitHubRepo)/main/VERSION.txt?t=$tNow" -Headers @{ 'Cache-Control' = 'no-cache' } -TimeoutSec 4 -EA Stop).ToString().Trim()

        if (-not $remoteVer) { return }
        if ($remoteVer -eq $script:AppVersion) {
            Ok "Đang dùng phiên bản mới nhất (v$script:AppVersion)."
            return
        }

        Say ''
        Ve-Khung "  CÓ PHIÊN BẢN CHÍNH THỨC: v$remoteVer  (hiện tại: v$script:AppVersion)" '' 'Green'
        Say '    [1]  Cập nhật / Đồng bộ ngay' 'Yellow'
        Say '    [2]  Bỏ qua, chạy bản hiện tại' 'Gray'
        Say ''

        $choice = '1'
        if (-not $script:AutoUpdate) {
            while ($true) {
                Write-Host '  Chọn 1 hoặc 2 [Enter = 1]: ' -ForegroundColor DarkGray -NoNewline
                $r = Read-Host
                if ($r -eq '' -or $r -eq '1') { $choice = '1'; break }
                elseif ($r -eq '2')            { $choice = '2'; break }
            }
        }

        if ($choice -eq '1') {
            Info 'Đang tải bản cập nhật từ GitHub...'
            $tmp = Join-Path $env:TEMP ("SAF_update_" + [guid]::NewGuid().ToString('N') + ".cmd")
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($script:GitHubRepo)/main/SteamAccessFix.cmd?t=$tNow" -Headers @{ 'Cache-Control' = 'no-cache' } -OutFile $tmp -TimeoutSec 15 -EA Stop
            $content = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
            if ($content.Contains('#PSBEGIN#') -and $content.Length -gt 2000) {
                Ok 'Xác thực gói cập nhật hợp lệ.'
                Ok "Đã ghi đè cập nhật vào: $env:SELF"
                Copy-Item -Path $tmp -Destination $env:SELF -Force
                Remove-Item $tmp -Force -EA SilentlyContinue
                Info 'Đang khởi động lại phiên bản mới...'
                Start-Sleep -Milliseconds 600
                Start-Process -FilePath $env:SELF -WorkingDirectory (Split-Path $env:SELF)
                exit
            } else {
                Err 'Gói cập nhật không hợp lệ. Đã hủy.'
                Remove-Item $tmp -Force -EA SilentlyContinue
            }
        } else {
            Info 'Bỏ qua cập nhật. Tiếp tục chạy bản hiện tại...'
            Start-Sleep -Milliseconds 600
        }
    } catch { }
}

# ================================================================
#  LEVEL 3 - DOH HOSTS FALLBACK
# ================================================================
function Invoke-Level3 {
    Buoc '3' 'Phân giải DoH + Ghi Hosts Tạm Thời'
    Info 'Đang truy vấn IP trực tiếp từ Cloudflare/Google DoH...'
    $storeIps = Get-DoHIp 'store.steampowered.com'
    if ($storeIps.Count -eq 0) {
        Err 'Không phân giải được IP qua DoH.'
        return $false
    }
    Info "IP phân giải DoH: $($storeIps -join '  |  ')"
    $hitIp = $null
    foreach ($ip in $storeIps) {
        if (Test-Connectivity -ResolveParam "store.steampowered.com:443:$ip") { $hitIp = $ip; break }
    }
    if (-not $hitIp) {
        Err 'Không có IP nào kết nối được qua DoH.'
        return $false
    }
    Ok "Kết nối trực tiếp tới IP $hitIp thành công!"
    Say ''
    Say '  Muốn thêm IP này tạm thời vào file hosts không?' 'Yellow'
    Say '  (Sẽ tự động gỡ khi thoát script)' 'DarkGray'
    if (Hoi-CoKhong 'Thêm vào hosts?' $true) {
        Save-Hosts
        $script:DaThayDoiHosts = $true
        $oldHosts = Get-Content $FileHostsSys | Where-Object { $_ -notmatch '#\s*SteamAccessFix' }
        Set-Content -Path $FileHostsSys -Value ($oldHosts + @(
            "$hitIp store.steampowered.com # SteamAccessFix",
            "$hitIp shared.fastly.steamstatic.com # SteamAccessFix"
        )) -Encoding ASCII
        ipconfig /flushdns | Out-Null
        if (Test-Connectivity -Show) {
            Ok 'Cấp độ 3 (Hosts DoH) hoạt động!'
            $script:MoTa = "Hosts DoH tạm thời ($hitIp)"
            return $true
        }
    }
    return $false
}

# ================================================================
#  HÀM HIỂN THỊ TRẠNG THÁI & PHÍM TẮT RUNTIME
# ================================================================
function Show-StatusBar {
    $lvlText = switch ($script:CurrentLevel) {
        0 { 'Cấp độ 0 - Kết nối bình thường' }
        1 { 'Cấp độ 1 - DNS Google (8.8.8.8) + Tối ưu Ping' }
        2 { 'Cấp độ 2 - SplitProxy SNI (Phân mảnh TLS)' }
        3 { 'Cấp độ 3 - DoH Hosts Fallback' }
        default { "Cấp độ $($script:CurrentLevel)" }
    }
    Say ''
    Ve-Khung "  HỆ THỐNG HOẠT ĐỘNG  -  SẴN SÀNG VÀO GAME" "  $lvlText  |  $($script:MoTa)" 'Green'
    Say '  Phạm vi hỗ trợ: Steam, PUBG, CS2, Dota 2, Naraka, Delta Force' 'DarkGreen'
    Say '  Lưu lượng trận đấu UDP đi TRỰC TIẾP (0ms overhead, anti-cheat safe)' 'DarkGray'
    Say ''
    Sep
    Say '  Hướng dẫn:' 'Cyan'
    Say '  - Mở Steam / Game để chơi bình thường.' 'White'
    Say '  - GIỮ CỬA SỔ NÀY MỞ trong suốt quá trình chơi game nếu dùng SplitProxy.' 'Yellow'
    Sep
    Say '  Phím tắt điều khiển:' 'DarkCyan'
    Say '  [T]      Kiểm tra lại kết nối tất cả dịch vụ' 'White'
    Say '  [1]      Chạy Cấp độ 1 - DNS Google only (tắt Proxy)' 'White'
    Say '  [2]      Chạy Cấp độ 2 - SplitProxy SNI (vượt chặn mạnh hơn)' 'White'
    Say '  [K]      Giữ lại DNS & tối ưu Ping vĩnh viễn rồi thoát' 'White'
    Say '  [Enter]  KHÔI PHỤC TOÀN BỘ về ban đầu và thoát an toàn (hoặc gõ Q)' 'White'
    Sep
    Say ''
}

# ================================================================
#  CHƯƠNG TRÌNH CHÍNH
# ================================================================
try {
    Ve-Khung "  SteamAccessFix v$script:AppVersion  -  Game Connectivity Fix"

    # Dọn dẹp phiên trước bị tắt đột ngột
    if ((Test-Path $FileDns) -or (Test-Path $FileProxy) -or (Test-Path $FileHosts) -or (Test-Path $FileNetTweaks)) {
        Warn 'Phiên trước chưa đóng đúng cách - đang dọn dẹp...'
        Restore-All
        Start-Sleep -Seconds 1
        Say ''
    }

    Check-GitHubUpdate
    Sep

    # ------------------------------------------------------------------
    # LEVEL 0: Kiểm tra kết nối hiện tại
    # ------------------------------------------------------------------
    Buoc '0' 'Kiểm tra kết nối hiện tại'
    Info 'Đang kiểm tra trạng thái các dịch vụ...'
    Say ''
    $level0Ok = Test-Connectivity -Show
    $script:CurrentLevel = 0

    if ($level0Ok) {
        Say ''
        Ok 'Tất cả dịch vụ hoạt động bình thường!'
        Say ''
        Say '  Bạn có muốn áp dụng tối ưu Ping Game không?' 'Yellow'
        Say '  (NetworkThrottlingIndex + TCP AutoTuning - không cần driver, an toàn)' 'DarkGray'
        if (Hoi-CoKhong 'Áp dụng tối ưu Ping?' $false) {
            Apply-GamingNetworkTweaks
            Ok 'Đã tối ưu mạng game (NetworkThrottling + TCP AutoTuning).'
        }
        $script:MoTa = if ($script:DaThayDoiTweaks) { 'Tối ưu Ping Game' } else { 'Kết nối bình thường' }

    } else {
        Warn 'Phát hiện kết nối bị chặn → gây lỗi Store Steam.'
        Say ''

        # ------------------------------------------------------------------
        # LEVEL 1: DNS Google + Tối ưu Network Stack
        # ------------------------------------------------------------------
        Buoc '1' 'Gán DNS Google (8.8.8.8 & IPv6) + Tối ưu Ping'
        Info 'Đang gán DNS Google trên các card mạng đang hoạt động...'
        Set-GoogleDns
        Ok 'Đã gán DNS: 8.8.8.8  &  2001:4860:4860::8888'

        Info 'Đang áp dụng tối ưu network stack cho game...'
        Apply-GamingNetworkTweaks
        Ok 'Đã tối ưu NetworkThrottling & TCP AutoTuning.'

        Say ''
        Info 'Kiểm tra lại kết nối...'
        Say ''
        $level1Ok = Test-Connectivity -Show
        $script:CurrentLevel = 1

        if ($level1Ok) {
            Say ''
            Ok 'Cấp độ 1 thành công! DNS Google đã mở khóa dịch vụ.'
            $script:MoTa = 'DNS Google (8.8.8.8) + Tối ưu Ping Game'
        } else {
            # Level 1 thất bại → Tự động nhảy Cấp độ 2 (SplitProxy) không cần hỏi
            Warn 'Cấp độ 1 chưa đủ: Nhà mạng chặn cả SNI (DPI). Tự động chuyển Cấp độ 2...'
            Buoc '2' 'Kích hoạt SplitProxy (Phân mảnh TLS ClientHello SNI)'
            Info 'Đang khởi động proxy nội bộ và thử các kiểu cắt gói...'
            if (Start-ProxyMode) {
                Ok 'Cấp độ 2 thành công! SplitProxy vượt qua bộ lọc SNI.'
                $script:CurrentLevel = 2
                Say ''
                Info 'Kiểm tra trạng thái các dịch vụ qua SplitProxy...'
                Say ''
                Test-Connectivity -Show -Port $script:CongDangDung | Out-Null
            } else {
                Warn 'Cấp độ 2 thất bại. Tự động chuyển sang Cấp độ 3 (DoH Fallback)...'
                if (Invoke-Level3) {
                    $script:CurrentLevel = 3
                } else {
                    Err 'Không kết nối được qua DoH Fallback.'
                }
            }
        }
    }

    # ------------------------------------------------------------------
    # MÀN HÌNH TRẠNG THÁI & VÒNG LẶP PHÍM TẮT
    # ------------------------------------------------------------------
    if ($script:MoTa -eq '') {
        Say ''
        Ve-Khung '  KHONG THE VUOT QUA CHAN  -  Tat ca phuong phap da that bai' '' 'Red'
        Err 'Tất cả các phương pháp user-mode đều thất bại.'
        Info 'Có thể ISP đang chặn toàn bộ IP hoặc đường truyền quốc tế gặp sự cố.'
        Say ''
        Sep
        Say '  Gợi ý:' 'Yellow'
        Say '  - Thử lại sau 30 phút (ISP có thể tự khắc phục).' 'White'
        Say '  - Dùng VPN tạm thời để vào Steam Store trước.' 'White'
        Say '  - Kiểm tra tốc độ mạng với fast.com / speedtest.net.' 'White'
        Sep
        Say ''
        Write-Host '  Nhấn Enter để khôi phục và thoát: ' -ForegroundColor DarkGray -NoNewline
        Read-Host | Out-Null
    } else {
        Show-StatusBar

        while ($true) {
            Write-Host '  Lựa chọn [T / 1 / 2 / K / Enter=Thoát]: ' -ForegroundColor Yellow -NoNewline
            $k = Read-Host

            if ($k -match '^[tT]') {
                Say ''
                Info 'Đang kiểm tra lại kết nối tất cả dịch vụ...'
                Say ''
                Test-Connectivity -Show -Port $script:CongDangDung | Out-Null
                Say ''
                Show-StatusBar
            }
            elseif ($k -eq '2') {
                Say ''
                Info 'Đang kích hoạt Cấp độ 2 (SplitProxy)...'
                if (Start-ProxyMode) {
                    Ok 'SplitProxy đang hoạt động!'
                    $script:CurrentLevel = 2
                } else {
                    Err 'Không khởi động được SplitProxy.'
                }
                Say ''
                Show-StatusBar
            }
            elseif ($k -eq '1') {
                Say ''
                Info 'Đang chuyển về Cấp độ 1 (DNS Google only)...'
                Stop-ProxyMode
                $script:CurrentLevel = 1
                $script:MoTa = 'DNS Google (8.8.8.8) + Tối ưu Ping Game'
                Ok 'Đã tắt Proxy. Đang chạy Cấp độ 1 (DNS Google only).'
                Say ''
                Show-StatusBar
            }
            elseif ($k -match '^[kK]') {
                Say ''
                Info 'Đã chọn giữ lại DNS Google và tối ưu Ping.'
                $script:DaThayDoiDns    = $false
                $script:DaThayDoiTweaks = $false
                if (Test-Path $FileDns)       { Remove-Item $FileDns       -Force -EA SilentlyContinue }
                if (Test-Path $FileNetTweaks) { Remove-Item $FileNetTweaks -Force -EA SilentlyContinue }
                Stop-ProxyMode
                Ok 'DNS Google & tối ưu Ping đã được lưu vĩnh viễn trên máy.'
                break
            }
            elseif ($k -match '^[qQ]' -or [string]::IsNullOrWhiteSpace($k)) {
                break
            }
            else {
                Show-StatusBar
            }
        }
    }
}
finally {
    if ($script:DaThayDoiDns -or $script:DaThayDoiProxy -or $script:DaThayDoiHosts -or $script:DaThayDoiTweaks) {
        Say ''
        Sep
        Restore-All
        Start-Sleep -Seconds 2
    }
}
