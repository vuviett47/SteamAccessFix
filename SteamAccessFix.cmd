<# :
@echo off
setlocal EnableExtensions EnableDelayedExpansion
title SteamAccessFix
set "SELF=%~f0"

:: -------------------------------------------------------------
::  SteamAccessFix - Standalone Steam Connectivity Tool
:: -------------------------------------------------------------

:: Tu nang quyen Administrator neu chua co
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF -Verb RunAs"
    exit /b
)

:: Chay phan PowerShell ben duoi file
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF,[Text.Encoding]::UTF8); $i=$s.IndexOf('#PSBEGIN'+'#'); iex $s.Substring($i)"
exit /b
: end batch / begin powershell #>

#PSBEGIN#
# ===============================================================
#  SteamAccessFix - Standalone Steam Connectivity Tool
#  Pure User-Mode Windows 10/11 - No Drivers / No WinDivert
# ===============================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
$Host.UI.RawUI.WindowTitle = 'SteamAccessFix'

# --- Cau hinh & Du lieu ---
$script:AppVersion     = '1.0.0'
$script:AppName        = 'SteamAccessFix'
$script:GitHubRepo     = 'vuviett47/SteamAccessFix'
$script:AutoUpdate     = $false

# Kiem tra quyen Administrator khi chay truc tiep tu PowerShell (irm | iex)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n  [i] Dang yeu cau quyen Administrator de cau hinh mang..." -ForegroundColor Cyan
    if ($env:SELF -and (Test-Path $env:SELF)) {
        Start-Process -FilePath $env:SELF -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/$($script:GitHubRepo)/main/SteamAccessFix.cmd | iex`"" -Verb RunAs
    }
    return
}

$ThuMucLuu   = Join-Path $env:ProgramData 'SteamAccessFix'
$FileDns     = Join-Path $ThuMucLuu 'dns-backup.json'
$FileProxy   = Join-Path $ThuMucLuu 'proxy-backup.json'
$FileHosts   = Join-Path $ThuMucLuu 'hosts-backup.txt'
$FileHostsSys= "$env:SystemRoot\System32\drivers\etc\hosts"
$RegIE       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

$CheDoProxy  = @(1, 2, 3, 4)
$CongProxy   = 18080

$CacTrang    = @(
    @{ Ten = 'store.steampowered.com';        Url = 'https://store.steampowered.com/' },
    @{ Ten = 'shared.fastly.steamstatic.com'; Url = 'https://shared.fastly.steamstatic.com/' }
)

$script:DaThayDoiDns   = $false
$script:DaThayDoiProxy = $false
$script:DaThayDoiHosts = $false
$script:Proxy          = $null
$script:CongDangDung   = 0
$script:MoTa           = ''

New-Item -ItemType Directory -Force -Path $ThuMucLuu | Out-Null

# --- Ham hien thi giao dien ---
function Say($m, $mau = 'Gray') { Write-Host $m -ForegroundColor $mau }
function Ok($m)   { Say "  [OK]  $m" 'Green' }
function Warn($m) { Say "  [!]   $m" 'Yellow' }
function Err($m)  { Say "  [X]   $m" 'Red' }
function Info($m) { Say "  [i]   $m" 'Cyan' }
function Buoc($n, $m) {
    Say ''
    Say "===============================================================" 'DarkCyan'
    Say " [$n] $m" 'Cyan'
    Say "===============================================================" 'DarkCyan'
}

function Hoi-CoKhong($cauHoi, $macDinhCo = $true) {
    $luaChon = if ($macDinhCo) { '[C = Co / K = Khong] (Enter = Co)' } else { '[C = Co / K = Khong] (Enter = Khong)' }
    while ($true) {
        $r = Read-Host "  $cauHoi $luaChon"
        if ($r -eq '') { return $macDinhCo }
        if ($r -match '^[cCyY]') { return $true }
        if ($r -match '^[kKnN]') { return $false }
    }
}

# --- Ma C# proxy cat nho ClientHello (khong can driver - SplitProxy) ---
$MaProxy = @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class SplitProxy
{
    public int Port;
    public int Mode = 1;          // 1: cat giua ten SNI, 2: cat sau 1 byte, 3: cat 2 cho, 4: cat sau ky tu dau cua SNI
    public int Connections = 0;
    public string Pac = "";
    private TcpListener listener;
    private volatile bool running;
    private byte[] pacBytes;

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
            try
            {
                TcpClient c = listener.AcceptTcpClient();
                ThreadPool.QueueUserWorkItem(new WaitCallback(Handle), c);
            }
            catch (Exception)
            {
                if (!running) return;
            }
        }
    }

    private static int HeaderEnd(byte[] b, int len)
    {
        for (int i = 0; i + 3 < len; i++)
        {
            if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
        }
        return -1;
    }

    private static void SplitHostPort(string hp, out string host, out int port)
    {
        port = 443;
        int idx = hp.LastIndexOf(':');
        if (hp.StartsWith("["))
        {
            int close = hp.IndexOf(']');
            if (close > 1)
            {
                host = hp.Substring(1, close - 1);
                if (idx > close && idx + 1 < hp.Length)
                {
                    int.TryParse(hp.Substring(idx + 1), out port);
                }
                return;
            }
        }
        if (idx > 0 && idx + 1 < hp.Length)
        {
            host = hp.Substring(0, idx);
            int.TryParse(hp.Substring(idx + 1), out port);
        }
        else
        {
            host = hp;
        }
    }

    // Tim vi tri ten mien trong extension SNI cua ClientHello
    private static int FindSni(byte[] d, int len, out int nameLen)
    {
        nameLen = 0;
        try
        {
            if (len < 43 || d[0] != 0x16 || d[5] != 0x01) return -1;
            int p = 5 + 4 + 2 + 32;
            p += 1 + d[p];
            p += 2 + ((d[p] << 8) | d[p + 1]);
            p += 1 + d[p];
            int extEnd = p + 2 + ((d[p] << 8) | d[p + 1]);
            p += 2;
            while (p + 4 <= extEnd && p + 4 <= len)
            {
                int type = (d[p] << 8) | d[p + 1];
                int el = (d[p + 2] << 8) | d[p + 3];
                if (type == 0)
                {
                    int q = p + 4 + 2 + 1;
                    nameLen = (d[q] << 8) | d[q + 1];
                    return q + 2;
                }
                p += 4 + el;
            }
        }
        catch (Exception) { }
        return -1;
    }

    private void SendSplit(NetworkStream ss, byte[] d, int len)
    {
        int nameLen;
        int sni = FindSni(d, len, out nameLen);
        int mid = (sni > 0 && nameLen > 1) ? sni + nameLen / 2 : 1;
        int first = (sni > 0) ? sni + 1 : 1;
        int[] cuts;
        if (Mode == 2) cuts = new int[] { 1 };
        else if (Mode == 3) cuts = new int[] { 1, mid };
        else if (Mode == 4) cuts = new int[] { first };
        else cuts = new int[] { mid };
        int pos = 0;
        for (int i = 0; i < cuts.Length; i++)
        {
            int c = cuts[i];
            if (c <= pos || c >= len) continue;
            ss.Write(d, pos, c - pos);
            ss.Flush();
            Thread.Sleep(25);
            pos = c;
        }
        ss.Write(d, pos, len - pos);
        ss.Flush();
    }

    private static void Pump(Stream from, Stream to, TcpClient a, TcpClient b)
    {
        byte[] buf = new byte[32768];
        try
        {
            int n;
            while ((n = from.Read(buf, 0, buf.Length)) > 0)
            {
                to.Write(buf, 0, n);
            }
        }
        catch (Exception) { }
        try { a.Close(); } catch (Exception) { }
        try { b.Close(); } catch (Exception) { }
    }

    private void Handle(object state)
    {
        TcpClient client = (TcpClient)state;
        TcpClient server = null;
        try
        {
            client.NoDelay = true;
            client.ReceiveTimeout = 15000;
            NetworkStream cs = client.GetStream();
            byte[] buf = new byte[16384];
            int len = 0;
            int he = -1;
            while (he < 0)
            {
                if (len >= buf.Length) return;
                int n = cs.Read(buf, len, buf.Length - len);
                if (n <= 0) return;
                len += n;
                he = HeaderEnd(buf, len);
            }
            string head = Encoding.ASCII.GetString(buf, 0, he);
            string line = head.Split('\n')[0].Trim();
            string[] parts = line.Split(' ');
            if (parts.Length < 2) return;
            string method = parts[0].ToUpperInvariant();

            if (method == "GET" && parts[1].StartsWith("/proxy.pac"))
            {
                string h = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ns-proxy-autoconfig\r\nContent-Length: " + pacBytes.Length + "\r\nConnection: close\r\n\r\n";
                byte[] hb = Encoding.ASCII.GetBytes(h);
                cs.Write(hb, 0, hb.Length);
                cs.Write(pacBytes, 0, pacBytes.Length);
                return;
            }
            if (method != "CONNECT")
            {
                byte[] r = Encoding.ASCII.GetBytes("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                cs.Write(r, 0, r.Length);
                return;
            }

            string host;
            int port;
            SplitHostPort(parts[1], out host, out port);
            server = new TcpClient();
            server.NoDelay = true;
            server.Connect(host, port);
            byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
            cs.Write(ok, 0, ok.Length);
            Interlocked.Increment(ref Connections);

            NetworkStream ss = server.GetStream();
            byte[] first = new byte[16384];
            client.ReceiveTimeout = 8000;
            int fl = cs.Read(first, 0, first.Length);
            if (fl <= 0) return;
            if (first[0] == 0x16 && fl >= 5)
            {
                int need = 5 + ((first[3] << 8) | first[4]);
                while (fl < need && fl < first.Length)
                {
                    int n2 = cs.Read(first, fl, first.Length - fl);
                    if (n2 <= 0) break;
                    fl += n2;
                }
                SendSplit(ss, first, fl);
            }
            else
            {
                ss.Write(first, 0, fl);
            }
            client.ReceiveTimeout = 0;

            TcpClient sv = server;
            TcpClient cl = client;
            Thread t = new Thread(delegate() { Pump(ss, cs, sv, cl); });
            t.IsBackground = true;
            t.Start();
            Pump(cs, ss, cl, sv);
        }
        catch (Exception) { }
        finally
        {
            try { client.Close(); } catch (Exception) { }
            try { if (server != null) server.Close(); } catch (Exception) { }
        }
    }
}
'@

# --- Quan ly DNS ---
function Get-DnsCoDinh($guid) {
    $kq = @()
    foreach ($p in 'Tcpip', 'Tcpip6') {
        $ns = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$p\Parameters\Interfaces\$guid" -ErrorAction SilentlyContinue).NameServer
        if ($ns) { $kq += @($ns -split '[,\s]+' | Where-Object { $_ }) }
    }
    return , $kq
}

function Save-Dns {
    if (Test-Path $FileDns) { return }
    $ds = foreach ($a in (Get-NetAdapter -Physical -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{ Index = $a.ifIndex; CoDinh = @(Get-DnsCoDinh $a.InterfaceGuid) }
    }
    @($ds) | ConvertTo-Json -Depth 3 | Set-Content -Path $FileDns -Encoding ASCII
}

function Restore-Dns {
    if (Test-Path $FileDns) {
        try {
            $b = @(Get-Content $FileDns -Raw | ConvertFrom-Json)
            foreach ($a in $b) {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -ErrorAction SilentlyContinue
                $cd = @($a.CoDinh)
                if ($cd.Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses $cd -ErrorAction SilentlyContinue
                }
            }
            Remove-Item $FileDns -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    ipconfig /flushdns | Out-Null
    $script:DaThayDoiDns = $false
}

function Set-GoogleDns {
    Save-Dns
    $script:DaThayDoiDns = $true
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    if ($adapters.Count -eq 0) {
        $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up')
    }
    foreach ($a in $adapters) {
        Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses '8.8.8.8', '2001:4860:4860::8888' -ErrorAction SilentlyContinue
    }
    ipconfig /flushdns | Out-Null
    Start-Sleep -Seconds 1
}

# --- Thong bao WinInet & Quan ly Proxy ---
function Notify-Inet {
    if (-not ('Win.Inet' -as [type])) {
        try {
            Add-Type -Namespace Win -Name Inet -MemberDefinition '[System.Runtime.InteropServices.DllImport("wininet.dll")] public static extern bool InternetSetOption(System.IntPtr h, int o, System.IntPtr b, int l);' -ErrorAction SilentlyContinue
        } catch { }
    }
    try {
        [Win.Inet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [Win.Inet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    } catch { }
}

function Save-ProxyCfg {
    if (Test-Path $FileProxy) { return }
    $cu = (Get-ItemProperty $RegIE -ErrorAction SilentlyContinue).AutoConfigURL
    [pscustomobject]@{ Co = [bool]$cu; Url = $cu } | ConvertTo-Json | Set-Content -Path $FileProxy -Encoding ASCII
}

function Restore-ProxyCfg {
    if (Test-Path $FileProxy) {
        try {
            $b = Get-Content $FileProxy -Raw | ConvertFrom-Json
            if ($b.Co) { Set-ItemProperty -Path $RegIE -Name AutoConfigURL -Value $b.Url }
            else       { Remove-ItemProperty -Path $RegIE -Name AutoConfigURL -ErrorAction SilentlyContinue }
            Remove-Item $FileProxy -Force -ErrorAction SilentlyContinue
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

# --- Quan ly Hosts File (Fallback) ---
function Save-Hosts {
    if (Test-Path $FileHosts) { return }
    if (Test-Path $FileHostsSys) {
        Copy-Item -Path $FileHostsSys -Destination $FileHosts -Force
    }
}

function Restore-Hosts {
    if (Test-Path $FileHosts) {
        try {
            Copy-Item -Path $FileHosts -Destination $FileHostsSys -Force
            Remove-Item $FileHosts -Force -ErrorAction SilentlyContinue
            ipconfig /flushdns | Out-Null
        } catch { }
    } else {
        if (Test-Path $FileHostsSys) {
            try {
                $lines = Get-Content $FileHostsSys | Where-Object { $_ -notmatch '#\s*SteamAccessFix' }
                Set-Content -Path $FileHostsSys -Value $lines -Encoding ASCII
                ipconfig /flushdns | Out-Null
            } catch { }
        }
    }
    $script:DaThayDoiHosts = $false
}

function Restore-All {
    Say ''
    Info 'Dang khoi phuc cai dat ban dau...'
    Stop-ProxyMode
    Restore-Hosts
    Restore-Dns
    Ok 'Da khoi phuc xong moi thiet lap mang.'
}

# --- Kiem tra ket noi toi Steam ---
function Test-Steam([switch]$Show, [int]$Port = 0, [string]$ResolveParam = '') {
    $tatCa = $true
    foreach ($t in $CacTrang) {
        $ca = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--max-time', '8')
        if ($Port -gt 0) { $ca += @('--proxy', "http://127.0.0.1:$Port") }
        if ($ResolveParam) { $ca += @('--resolve', $ResolveParam) }
        $ma = & curl.exe @ca $t.Url
        $tot = ($ma -and $ma -ne '000')
        if ($Show) {
            if ($tot) { Ok ("{0,-32} ket noi duoc (HTTP {1})" -f $t.Ten, $ma) }
            else      { Err ("{0,-32} KHONG ket noi duoc" -f $t.Ten) }
        }
        if (-not $tot) { $tatCa = $false }
    }
    return $tatCa
}

# --- DoH DNS Query ---
function Get-DoHIp([string]$domain) {
    try {
        $cf = Invoke-RestMethod -Uri "https://cloudflare-dns.com/dns-query?name=$domain&type=A" -Headers @{ accept = 'application/dns-json' } -TimeoutSec 5 -ErrorAction Stop
        $ans = ($cf.Answer | Where-Object { $_.type -eq 1 }).data
        if ($ans -and $ans.Count -gt 0) { return @($ans | Where-Object { $_ -notmatch '^127\.' }) }
    } catch { }
    try {
        $gg = Invoke-RestMethod -Uri "https://dns.google/resolve?name=$domain&type=A" -TimeoutSec 5 -ErrorAction Stop
        $ans = ($gg.Answer | Where-Object { $_.type -eq 1 }).data
        if ($ans -and $ans.Count -gt 0) { return @($ans | Where-Object { $_ -notmatch '^127\.' }) }
    } catch { }
    return @()
}

# --- Khoi dong SplitProxy ---
function Start-ProxyMode {
    if (-not ('SplitProxy' -as [type])) {
        try { Add-Type -TypeDefinition $MaProxy -Language CSharp -ErrorAction Stop }
        catch { Err "Khong khoi tao duoc proxy: $($_.Exception.Message)"; return $false }
    }
    $px = $null
    $cong = 0
    foreach ($p in $CongProxy..($CongProxy + 10)) {
        try {
            $x = New-Object SplitProxy -ArgumentList $p
            $x.Pac = @"
function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  if (url.substring(0, 5) == "http:") return "DIRECT";
  var d = ["steampowered.com", "steamcommunity.com", "steamstatic.com", "steam-chat.com", "steamusercontent.com", "steamgames.com", "steamcontent.com"];
  for (var i = 0; i < d.length; i++) {
    if (host == d[i] || dnsDomainIs(host, "." + d[i])) return "PROXY 127.0.0.1:$p";
  }
  return "DIRECT";
}
"@
            $x.Start()
            $px = $x; $cong = $p
            break
        } catch { }
    }
    if (-not $px) { Err 'Khong mo duoc cong proxy nao (cong bi chiem).'; return $false }
    $script:Proxy = $px
    $script:CongDangDung = $cong

    Save-ProxyCfg
    Set-ItemProperty -Path $RegIE -Name AutoConfigURL -Value "http://127.0.0.1:$cong/proxy.pac"
    Notify-Inet
    $script:DaThayDoiProxy = $true
    Ok "Proxy noi bo dang chay o 127.0.0.1:$cong"

    foreach ($m in $CheDoProxy) {
        Say "       Thu kieu cat goi so $m..."
        $px.Mode = $m
        Start-Sleep -Milliseconds 250
        if (Test-Steam -Show -Port $cong) {
            Ok "Kieu cat goi so $m hoat dong thanh cong!"
            $script:MoTa = "SplitProxy kieu cat goi so $m (cong $cong)"
            return $true
        }
    }
    Stop-ProxyMode
    return $false
}

# --- Tu dong kiem tra cap nhat GitHub ---
function Check-GitHubUpdate {
    if ($script:GitHubRepo -eq 'USERNAME/REPOSITORY' -or [string]::IsNullOrWhiteSpace($script:GitHubRepo)) {
        return
    }
    try {
        Info "Dang kiem tra cap nhat tu GitHub ($script:GitHubRepo)..."
        $rawVersionUrl = "https://raw.githubusercontent.com/$($script:GitHubRepo)/main/VERSION.txt"
        $remoteVerStr = (Invoke-RestMethod -Uri $rawVersionUrl -TimeoutSec 4 -ErrorAction Stop).ToString().Trim()

        if ($remoteVerStr -and ([version]$remoteVerStr -gt [version]$script:AppVersion)) {
            Say ''
            Say "  =======================================================" 'Cyan'
            Say "   CO PHIEN BAN MOI TREN GITHUB: v$remoteVerStr" 'Green'
            Say "   (Phien ban ban dang dung: v$script:AppVersion)" 'White'
            Say "  =======================================================" 'Cyan'
            Say ''
            Say '  [1] Cap nhat ngay bay gio (Tai ve, tu cai va khoi dong lai)' 'Yellow'
            Say '  [2] Bo qua va tiep tuc chay ban hien tai' 'Gray'
            Say ''

            $choice = '1'
            if (-not $script:AutoUpdate) {
                while ($true) {
                    $r = Read-Host '  Chon 1 hoac 2 roi nhan Enter (Enter = 1)'
                    if ($r -eq '' -or $r -eq '1') { $choice = '1'; break }
                    elseif ($r -eq '2') { $choice = '2'; break }
                }
            }

            if ($choice -eq '1') {
                Info 'Dang tai ban cap nhat tu GitHub...'
                $rawScriptUrl = "https://raw.githubusercontent.com/$($script:GitHubRepo)/main/SteamAccessFix.cmd"
                $tmpFile = Join-Path $env:TEMP ("SAF_update_" + [guid]::NewGuid().ToString('N') + ".cmd")
                Invoke-WebRequest -Uri $rawScriptUrl -OutFile $tmpFile -TimeoutSec 15 -ErrorAction Stop

                $content = [IO.File]::ReadAllText($tmpFile, [Text.Encoding]::UTF8)
                if ($content.Contains('#PSBEGIN#') -and $content.Contains('@echo off') -and ($content.Length -gt 2000)) {
                    Ok 'Xac thuc goi cap nhat hop le. Dang thay the...'
                    Copy-Item -Path $tmpFile -Destination $env:SELF -Force
                    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
                    Ok 'Cap nhat hoan tat! Dang khoi dong lai...'
                    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$env:SELF`""
                    exit
                } else {
                    Err 'Goi cap nhat khong hop le. Da huy cap nhat.'
                    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
                    Info 'Tiep tuc chay ban hien tai...'
                }
            } else {
                Info "Ban da chon bo qua cap nhat. Tiep tuc chay ban hien tai (v$script:AppVersion)..."
                Start-Sleep -Milliseconds 800
            }
        } else {
            Ok "Ban dang dung phien ban moi nhat (v$script:AppVersion)."
        }
    } catch { }
}

# ===============================================================
#  CHUONG TRINH CHINH
# ===============================================================
try {
    Say ''
    Say '  ===============================================================' 'Cyan'
    Say "   SteamAccessFix v$script:AppVersion - Standalone Steam Tool" 'White'
    Say '  ===============================================================' 'Cyan'
    Say ''

    # Don dep phien truoc neu bi tat dot ngot (bam nut X)
    if ((Test-Path $FileDns) -or (Test-Path $FileProxy) -or (Test-Path $FileHosts)) {
        Warn 'Phien truoc chua dong dung cach (bam X) - dang khoi phuc truoc...'
        Restore-All
        Start-Sleep -Seconds 1
    }

    # Kiem tra cap nhat GitHub
    Check-GitHubUpdate

    # -------------------------------------------------------------
    # LEVEL 0: Kiem tra ket noi hien tai
    # -------------------------------------------------------------
    Buoc '0' 'Kiem tra ket noi Steam hien tai'
    Info 'Kiem tra ket noi voi thiet lap mang hien co...'
    if (Test-Steam -Show) {
        Say ''
        Ok 'Steam da ket noi binh thuong tren mang cua ban! Khong can thay doi gi.'
        Say ''
        Read-Host '  Nhan Enter de thoat' | Out-Null
        return
    }

    Warn 'Steam hien dang bi chan hoac khong the truy cap.'
    Info 'Dang thu lan luot cac phuong phap vuot chan...'

    # -------------------------------------------------------------
    # LEVEL 1: Doi DNS sang Google (8.8.8.8 + IPv6)
    # -------------------------------------------------------------
    Buoc '1' 'Doi DNS sang Google (8.8.8.8 & IPv6) va kiem tra lai'
    Info 'Dang gan DNS Google tren cac card mang Up...'
    Set-GoogleDns
    Ok 'DNS da duoc doi sang Google (8.8.8.8 & 2001:4860:4860::8888).'

    Info 'Kiem tra lai ket noi Steam...'
    $level1Ok = Test-Steam -Show

    if ($level1Ok) {
        Say ''
        Ok 'Phuong phap Level 1 thanh cong! Chi can doi DNS la vao duoc Steam.'
        $script:MoTa = 'DNS Google (8.8.8.8 / 2001:4860:4860::8888)'
    } else {
        Warn 'Level 1 chua du: Mang van bi chan sau khi doi DNS.'

        # -------------------------------------------------------------
        # LEVEL 2: Bat SplitProxy (Cat nho goi TLS ClientHello SNI)
        # -------------------------------------------------------------
        Buoc '2' 'Bat proxy noi bo cat nho ClientHello (SplitProxy)'
        Info 'Dang khoi dong proxy noi bo va thu cac kieu cat goi...'
        $level2Ok = Start-ProxyMode

        if ($level2Ok) {
            Say ''
            Ok 'Phuong phap Level 2 thanh cong! SplitProxy da vuot qua chan SNI.'
        } else {
            Warn 'Level 2 khong thanh cong. Thu phuong phap phan giai DoH...'

            # -------------------------------------------------------------
            # LEVEL 3: DoH Resolution / Hosts Fallback
            # -------------------------------------------------------------
            Buoc '3' 'Kiem tra phan giai DoH (DNS-over-HTTPS)'
            Info 'Dang truy van IP truc tiep tu Cloudflare/Google DoH...'
            $storeIps = Get-DoHIp 'store.steampowered.com'
            $hitIp = $null

            if ($storeIps.Count -gt 0) {
                Info "IP phan giai DoH: $($storeIps -join ', ')"
                foreach ($ip in $storeIps) {
                    if (Test-Steam -ResolveParam "store.steampowered.com:443:$ip") {
                        $hitIp = $ip
                        break
                    }
                }
            }

            if ($hitIp) {
                Ok "Ket noi truc tiep toi IP $hitIp thanh cong!"
                Say ''
                Say '  Ban co muon them IP nay tam thoi vao file hosts?' 'Yellow'
                Say '  (Cai dat se duoc tu dong go bo khi script dong).' 'DarkGray'
                if (Hoi-CoKhong 'Them vao hosts tam thoi?' $true) {
                    Save-Hosts
                    $script:DaThayDoiHosts = $true
                    $steamHosts = @(
                        "$hitIp store.steampowered.com # SteamAccessFix",
                        "$hitIp shared.fastly.steamstatic.com # SteamAccessFix"
                    )
                    $oldHosts = Get-Content $FileHostsSys | Where-Object { $_ -notmatch '#\s*SteamAccessFix' }
                    Set-Content -Path $FileHostsSys -Value ($oldHosts + $steamHosts) -Encoding ASCII
                    ipconfig /flushdns | Out-Null
                    if (Test-Steam -Show) {
                        Ok 'Phuong phap Level 3 (Hosts DoH) hoat dong!'
                        $script:MoTa = "Hosts DoH tam thoi ($hitIp)"
                    }
                }
            }
        }
    }

    # -------------------------------------------------------------
    # TRANG THAI HOAT DONG
    # -------------------------------------------------------------
    if ($script:MoTa -eq '') {
        Say ''
        Say '===============================================================' 'Red'
        Say '  KHONG THE VUOT QUA CHAN' 'Red'
        Say '===============================================================' 'Red'
        Err 'Tat ca cac phuong phap user-mode deu khong the ket noi.'
        Info 'Giai thich ky thuat:'
        Say '   ISP cua ban dang chan theo dai IP hoac su dung DPI nang cao' 'DarkGray'
        Say '   yeu cuu can thiep muc goi tin (WinDivert/driver) hoac can VPN/WARP.' 'DarkGray'
        Say ''
        Read-Host '  Nhan Enter de khoi phuc va thoat' | Out-Null
    } else {
        Say ''
        Say '===============================================================' 'Green'
        Say '  STEAM ACCESS FIX DANG HOAT DONG' 'Green'
        Say "  Che do dang dung: $script:MoTa" 'Green'
        Say '  Pham vi: Chi ap dung cho cac ket noi Steam' 'Green'
        Say '===============================================================' 'Green'
        Say ''
        Say '  Huong dan:' 'Cyan'
        Say '  * Ban co the mo trinh duyet hoac Steam client de su dung.' 'White'
        Say '  * Neu trang thieu hinh / CSS, hay nhan Ctrl+F5 tren trinh duyet.' 'DarkGray'
        Say '  * HAY GIU CUA SO NAY MO trong khi choi game hoac luot Steam.' 'Yellow'
        Say ''
        Say '  Dieu khien:' 'DarkCyan'
        Say '  * Go [T] + Enter  : Kiem tra lai ket noi Steam' 'White'
        Say '  * Go [K] + Enter  : Giu lai DNS Google va thoat' 'White'
        Say '  * Nhan [Enter]    : KHOI PHUC MOI THIET LAP va thoat an toan' 'White'
        Say ''

        while ($true) {
            $k = Read-Host '  Go [T] de test lai | [K] de giu DNS | nhan [Enter] de KHOI PHUC va thoat'
            if ($k -match '^[tT]') {
                Say ''
                Info 'Dang kiem tra lai ket noi...'
                Test-Steam -Show -Port $script:CongDangDung | Out-Null
                Say ''
            }
            elseif ($k -match '^[kK]') {
                Say ''
                Info 'Ban da chon giu lai DNS Google. Proxy va hosts se duoc khoi phuc.'
                $script:DaThayDoiDns = $false
                if (Test-Path $FileDns) {
                    Remove-Item $FileDns -Force -ErrorAction SilentlyContinue
                }
                break
            }
            else {
                break
            }
        }
    }
}
finally {
    if ($script:DaThayDoiDns -or $script:DaThayDoiProxy -or $script:DaThayDoiHosts) {
        Restore-All
        Start-Sleep -Seconds 2
    }
}
