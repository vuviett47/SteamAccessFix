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
#  SteamAccessFix v1.1.4 - All-In-One Game & Store Fix (Windows)
#  Pure User-Mode  |  No Drivers  |  Anti-Cheat Safe
# ================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
$Host.UI.RawUI.WindowTitle = 'SteamAccessFix v1.1.4'

# --- Cau hinh ---
$script:AppVersion  = '1.1.4'
$script:GitHubRepo  = 'vuviett47/SteamAccessFix'
$script:AutoUpdate  = $false

# Dam bao duong dan SELF luon chinh xac khi chay tu file
if (-not $env:SELF -or -not (Test-Path $env:SELF)) {
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $env:SELF = $PSCommandPath }
    elseif ($MyInvocation.MyCommand.Path -and (Test-Path $MyInvocation.MyCommand.Path)) { $env:SELF = $MyInvocation.MyCommand.Path }
}

# Kiem tra quyen Administrator khi chay truc tiep tu PowerShell (irm | iex)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "`n  [!] Dang yeu cau quyen Administrator..." -ForegroundColor Yellow
    if ($env:SELF -and (Test-Path $env:SELF)) {
        Start-Process -FilePath $env:SELF -Verb RunAs
    } else {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/$($script:GitHubRepo)/main/SteamAccessFix.cmd | iex`"" -Verb RunAs
    }
    return
}

# --- Duong dan luu tru ---
$ThuMucLuu     = Join-Path $env:ProgramData 'SteamAccessFix'
$FileDns       = Join-Path $ThuMucLuu 'dns-backup.json'
$FileProxy     = Join-Path $ThuMucLuu 'proxy-backup.json'
$FileHosts     = Join-Path $ThuMucLuu 'hosts-backup.txt'
$FileNetTweaks = Join-Path $ThuMucLuu 'net-tweaks-backup.json'
$FileHostsSys  = "$env:SystemRoot\System32\drivers\etc\hosts"
$RegIE         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$CongProxy     = 18080

# --- Domain dinh tuyen qua proxy (chi Web/Lobby/GC, UDP tran dau di DIRECT) ---
$AllGameDomains = @(
    'steampowered.com', 'steamcommunity.com', 'steamstatic.com',
    'steam-chat.com', 'steamusercontent.com', 'steamgames.com', 'steamcontent.com', 'steamserver.net',
    'counter-strike.net', 'dota2.com', 'valvesoftware.com',
    'playbattlegrounds.com', 'pubg.com', 'krafton.com', 'pubgapp.com', 'pubgesports.com',
    'narakathegame.com', '24entertainment.net',
    'playdeltaforce.com', 'levelinfinite.com'
)

# --- Trang thai ---
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
#  GIAO DIEN UI/UX (TIENG VIET KHONG DAU - CHONG LOI FONT 100%)
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

# ================================================================
#  MA C# SPLITPROXY NHUNG SAN
# ================================================================
$MaProxy = @'
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32;

public class SplitProxy
{
    public int Port;
    public int Mode = 2;
    public int Connections = 0;
    public string Pac = "";
    public bool HasDirect443 = false;
    private TcpListener listenerProxy;
    private TcpListener listenerDirect;
    private volatile bool running;
    private byte[] pacBytes;

    private class DnsEntry {
        public IPAddress Ip;
        public long ExpireTick;
    }
    private static ConcurrentDictionary<string, DnsEntry> dnsCache = new ConcurrentDictionary<string, DnsEntry>();

    public static IPAddress ResolveSafe(string host)
    {
        IPAddress parsedIp;
        if (IPAddress.TryParse(host, out parsedIp)) return parsedIp;

        long now = Environment.TickCount;
        DnsEntry entry;
        if (dnsCache.TryGetValue(host, out entry)) {
            if ((now - entry.ExpireTick) < 0) return entry.Ip;
        }

        IPAddress resolved = null;
        try {
            IPAddress[] addrs = Dns.GetHostAddresses(host);
            foreach (var a in addrs) {
                if (a.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a)) {
                    resolved = a;
                    break;
                }
            }
        } catch { }

        if (resolved == null) {
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
                                resolved = parsed;
                                break;
                            }
                        }
                        idx = json.IndexOf("\"data\":\"", end);
                    }
                }
            } catch { }
        }

        if (resolved == null) {
            try {
                using (var wc = new WebClient()) {
                    wc.Headers[HttpRequestHeader.Accept] = "application/dns-json";
                    string json = wc.DownloadString("https://cloudflare-dns.com/dns-query?name=" + host + "&type=A");
                    int idx = json.IndexOf("\"data\":\"");
                    while (idx > 0) {
                        int end = json.IndexOf("\"", idx + 8);
                        if (end > idx) {
                            string ipStr = json.Substring(idx + 8, end - idx - 8);
                            IPAddress parsed;
                            if (IPAddress.TryParse(ipStr, out parsed) && !IPAddress.IsLoopback(parsed)) {
                                resolved = parsed;
                                break;
                            }
                        }
                        idx = json.IndexOf("\"data\":\"", end);
                    }
                }
            } catch { }
        }

        if (resolved != null) {
            dnsCache[host] = new DnsEntry { Ip = resolved, ExpireTick = now + 60000 };
            return resolved;
        }

        if (entry != null) return entry.Ip;
        return null;
    }

    public SplitProxy(int port) { Port = port; }

    public void Start()
    {
        pacBytes = Encoding.UTF8.GetBytes(Pac == null ? "" : Pac);
        running = true;

        listenerProxy = new TcpListener(IPAddress.Loopback, Port);
        listenerProxy.Start();
        Thread tProxy = new Thread(new ThreadStart(AcceptLoopProxy));
        tProxy.IsBackground = true;
        tProxy.Start();

        try {
            listenerDirect = new TcpListener(IPAddress.Loopback, 443);
            listenerDirect.Start();
            HasDirect443 = true;
            Thread tDirect = new Thread(new ThreadStart(AcceptLoopDirect));
            tDirect.IsBackground = true;
            tDirect.Start();
        } catch {
            HasDirect443 = false;
        }
    }

    public void Stop()
    {
        running = false;
        try { if (listenerProxy != null) listenerProxy.Stop(); } catch { }
        try { if (listenerDirect != null) listenerDirect.Stop(); } catch { }
    }

    private void AcceptLoopProxy()
    {
        while (running)
        {
            try { TcpClient c = listenerProxy.AcceptTcpClient(); ThreadPool.QueueUserWorkItem(new WaitCallback(HandleProxy), c); }
            catch (Exception) { if (!running) return; }
        }
    }

    private void AcceptLoopDirect()
    {
        while (running)
        {
            try { TcpClient c = listenerDirect.AcceptTcpClient(); ThreadPool.QueueUserWorkItem(new WaitCallback(HandleDirect), c); }
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

    private static int FindSni(byte[] d, int len, out string sniHost, out int nameLen)
    {
        sniHost = null; nameLen = 0;
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
                if (type == 0) {
                    int q = p + 4 + 2 + 1;
                    nameLen = (d[q] << 8) | d[q + 1];
                    if (q + 2 + nameLen <= len) {
                        sniHost = Encoding.ASCII.GetString(d, q + 2, nameLen);
                    }
                    return q + 2;
                }
                p += 4 + el;
            }
        } catch { }
        return -1;
    }

    private void SendSplit(NetworkStream ss, byte[] d, int len, int mode)
    {
        string sniHost; int nameLen;
        int sni   = FindSni(d, len, out sniHost, out nameLen);
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
            Thread.Sleep(20);
            pos = c;
        }
        ss.Write(d, pos, len - pos); ss.Flush();
    }

    private static void Pump(Stream from, Stream to, TcpClient a, TcpClient b)
    {
        byte[] buf = new byte[32768];
        try { int n; while ((n = from.Read(buf, 0, buf.Length)) > 0) to.Write(buf, 0, n); } catch { }
        try { a.Close(); } catch { }
        try { b.Close(); } catch { }
    }

    private void HandleDirect(object state)
    {
        TcpClient client = (TcpClient)state;
        TcpClient server = null;
        try {
            client.NoDelay = true;
            try { client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true); } catch { }
            client.ReceiveTimeout = 10000;
            NetworkStream cs = client.GetStream();
            byte[] first = new byte[16384];
            int fl = cs.Read(first, 0, first.Length);
            if (fl <= 0) return;

            string sniHost; int nameLen;
            int sniPos = FindSni(first, fl, out sniHost, out nameLen);
            if (string.IsNullOrEmpty(sniHost)) return;

            IPAddress targetIp = ResolveSafe(sniHost);
            if (targetIp == null) return;

            server = new TcpClient();
            server.NoDelay = true;
            try { server.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true); } catch { }

            IAsyncResult ar = server.BeginConnect(targetIp, 443, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(5000, false)) { server.Close(); return; }
            server.EndConnect(ar);

            NetworkStream ss = server.GetStream();
            if (first[0] == 0x16 && fl >= 5) {
                int need = 5 + ((first[3] << 8) | first[4]);
                while (fl < need && fl < first.Length) { int n2 = cs.Read(first, fl, first.Length - fl); if (n2 <= 0) break; fl += n2; }
                SendSplit(ss, first, fl, Mode);
            } else {
                ss.Write(first, 0, fl);
            }
            client.ReceiveTimeout = 0;

            TcpClient sv = server, cl = client;
            Thread t = new Thread(delegate() { Pump(ss, cs, sv, cl); });
            t.IsBackground = true; t.Start();
            Pump(cs, ss, cl, sv);
        } catch { }
        finally {
            try { client.Close(); } catch { }
            try { if (server != null) server.Close(); } catch { }
        }
    }

    private void HandleProxy(object state)
    {
        TcpClient client = (TcpClient)state;
        TcpClient server = null;
        try {
            client.NoDelay = true;
            try { client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true); } catch { }
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
                string targetHost = "";
                int targetPort = 80;
                Uri uri;
                if (Uri.TryCreate(parts[1], UriKind.Absolute, out uri)) {
                    targetHost = uri.Host;
                    targetPort = uri.Port;
                } else {
                    int hi = head.IndexOf("Host: ", StringComparison.OrdinalIgnoreCase);
                    if (hi >= 0) {
                        int he2 = head.IndexOf("\r\n", hi);
                        string hp = (he2 > hi) ? head.Substring(hi + 6, he2 - (hi + 6)).Trim() : head.Substring(hi + 6).Trim();
                        SplitHostPort(hp, out targetHost, out targetPort);
                        if (targetPort == 443) targetPort = 80;
                    }
                }
                if (string.IsNullOrEmpty(targetHost)) return;

                IPAddress targetIp = ResolveSafe(targetHost);
                server = new TcpClient();
                server.NoDelay = true;
                try { server.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true); } catch { }

                IAsyncResult ar = (targetIp != null) ? server.BeginConnect(targetIp, targetPort, null, null) : server.BeginConnect(targetHost, targetPort, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(5000, false)) { server.Close(); return; }
                server.EndConnect(ar);

                NetworkStream ss = server.GetStream();
                ss.Write(buf, 0, len); ss.Flush();

                TcpClient sv = server, cl = client;
                Thread t = new Thread(delegate() { Pump(ss, cs, sv, cl); });
                t.IsBackground = true; t.Start();
                Pump(cs, ss, cl, sv);
                return;
            }

            string host; int port;
            SplitHostPort(parts[1], out host, out port);
            IPAddress targetIpConnect = ResolveSafe(host);

            server = new TcpClient();
            server.NoDelay = true;
            try { server.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true); } catch { }

            IAsyncResult arConnect = (targetIpConnect != null) ? server.BeginConnect(targetIpConnect, port, null, null) : server.BeginConnect(host, port, null, null);
            if (!arConnect.AsyncWaitHandle.WaitOne(5000, false)) {
                server.Close();
                return;
            }
            server.EndConnect(arConnect);

            byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
            cs.Write(ok, 0, ok.Length);
            Interlocked.Increment(ref Connections);

            NetworkStream ssConnect = server.GetStream();
            byte[] first = new byte[16384];
            client.ReceiveTimeout = 8000;
            int fl = cs.Read(first, 0, first.Length);
            if (fl <= 0) return;
            if (first[0] == 0x16 && fl >= 5) {
                int need = 5 + ((first[3] << 8) | first[4]);
                while (fl < need && fl < first.Length) { int n2 = cs.Read(first, fl, first.Length - fl); if (n2 <= 0) break; fl += n2; }
                SendSplit(ssConnect, first, fl, Mode);
            } else ssConnect.Write(first, 0, fl);
            client.ReceiveTimeout = 0;

            TcpClient svConnect = server, clConnect = client;
            Thread tConnect = new Thread(delegate() { Pump(ssConnect, cs, svConnect, clConnect); });
            tConnect.IsBackground = true; tConnect.Start();
            Pump(cs, ssConnect, clConnect, svConnect);
        } catch (Exception) { }
        finally {
            try { client.Close(); } catch { }
            try { if (server != null) server.Close(); } catch { }
        }
    }
}

public class NativeCleanup
{
    [DllImport("Kernel32")]
    public static extern bool SetConsoleCtrlHandler(HandlerRoutine Handler, bool Add);

    [DllImport("wininet.dll")]
    public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l);

    public delegate bool HandlerRoutine(int CtrlType);
    private static HandlerRoutine _routine;
    public static volatile bool IsActive = false;

    public static void Register()
    {
        if (_routine == null) {
            _routine = new HandlerRoutine(OnConsoleCtrl);
            SetConsoleCtrlHandler(_routine, true);
        }
    }

    public static void Unregister()
    {
        IsActive = false;
    }

    private static bool OnConsoleCtrl(int ctrlType)
    {
        if (IsActive) {
            DoEmergencyCleanup();
        }
        return false;
    }

    public static void DoEmergencyCleanup()
    {
        try {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings", true)) {
                if (key != null) {
                    key.SetValue("ProxyEnable", 0, RegistryValueKind.DWord);
                    try { key.DeleteValue("ProxyServer", false); } catch { }
                    try { key.DeleteValue("AutoConfigURL", false); } catch { }
                }
            }
        } catch { }

        try {
            using (RegistryKey connKey = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections", true)) {
                if (connKey != null) {
                    string[] names = new string[] { "DefaultConnectionSettings", "SavedLegacySettings" };
                    foreach (string n in names) {
                        byte[] b = connKey.GetValue(n) as byte[];
                        if (b != null && b.Length >= 9) {
                            b[8] = 1;
                            connKey.SetValue(n, b, RegistryValueKind.Binary);
                        }
                    }
                }
            }
        } catch { }

        try {
            InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
            InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
        } catch { }

        try {
            string hosts = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"drivers\etc\hosts");
            if (File.Exists(hosts)) {
                string[] lines = File.ReadAllLines(hosts);
                var keep = new System.Collections.Generic.List<string>();
                bool changed = false;
                foreach (var line in lines) {
                    if (line.IndexOf("SteamAccessFix", StringComparison.OrdinalIgnoreCase) >= 0) {
                        changed = true;
                    } else {
                        keep.Add(line);
                    }
                }
                if (changed) {
                    File.WriteAllLines(hosts, keep.ToArray());
                }
            }
        } catch { }

        try {
            ProcessStartInfo psi = new ProcessStartInfo("netsh", "winhttp reset proxy");
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;
            using (Process p = Process.Start(psi)) {
                if (p != null) p.WaitForExit(1000);
            }
        } catch { }
    }
}
'@

# ================================================================
#  QUAN LY DNS
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
    Start-Sleep -Milliseconds 300
}

# ================================================================
#  QUAN LY PROXY (PAC + SplitProxy)
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
    $cu = Get-ItemProperty $RegIE -EA SilentlyContinue
    $proxyServer = $cu.ProxyServer
    $autoConfig  = $cu.AutoConfigURL
    $proxyEnable = $cu.ProxyEnable

    # Loc sach neu registry dang bi ton dong proxy tu phien cu (v1.1.3 tro ve truoc)
    if ($proxyServer -match '127\.0\.0\.1|localhost' -or $autoConfig -match '127\.0\.0\.1|localhost|proxy\.pac') {
        $proxyServer = $null
        $autoConfig  = $null
        $proxyEnable = 0
    }

    [pscustomobject]@{
        AutoConfigURL = $autoConfig
        ProxyEnable   = $proxyEnable
        ProxyServer   = $proxyServer
        ProxyOverride = $cu.ProxyOverride
    } | ConvertTo-Json | Set-Content -Path $FileProxy -Encoding ASCII
}

function Restore-ProxyCfg {
    if (Test-Path $FileProxy) {
        try {
            $b = Get-Content $FileProxy -Raw | ConvertFrom-Json
            if ($b.AutoConfigURL -and $b.AutoConfigURL -notmatch '127\.0\.0\.1|localhost|proxy\.pac') {
                Set-ItemProperty -Path $RegIE -Name AutoConfigURL -Value $b.AutoConfigURL -EA SilentlyContinue
            } else {
                Remove-ItemProperty -Path $RegIE -Name AutoConfigURL -EA SilentlyContinue
            }

            if ($null -ne $b.ProxyEnable -and $b.ProxyServer -notmatch '127\.0\.0\.1|localhost') {
                Set-ItemProperty -Path $RegIE -Name ProxyEnable -Value $b.ProxyEnable -EA SilentlyContinue
            } else {
                Set-ItemProperty -Path $RegIE -Name ProxyEnable -Value 0 -EA SilentlyContinue
            }

            if ($b.ProxyServer -and $b.ProxyServer -notmatch '127\.0\.0\.1|localhost') {
                Set-ItemProperty -Path $RegIE -Name ProxyServer -Value $b.ProxyServer -EA SilentlyContinue
            } else {
                Remove-ItemProperty -Path $RegIE -Name ProxyServer -EA SilentlyContinue
            }

            if ($b.ProxyOverride) {
                Set-ItemProperty -Path $RegIE -Name ProxyOverride -Value $b.ProxyOverride -EA SilentlyContinue
            } else {
                Remove-ItemProperty -Path $RegIE -Name ProxyOverride -EA SilentlyContinue
            }
            Remove-Item $FileProxy -Force -EA SilentlyContinue
        } catch { }
    } else {
        Set-ItemProperty -Path $RegIE -Name ProxyEnable -Value 0 -EA SilentlyContinue
        Remove-ItemProperty -Path $RegIE -Name ProxyServer -EA SilentlyContinue
        Remove-ItemProperty -Path $RegIE -Name AutoConfigURL -EA SilentlyContinue
    }

    # Luon dong bo DefaultConnectionSettings & SavedLegacySettings de Chrome/Edge luon ve Direct
    $regConn = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections'
    foreach ($val in @('DefaultConnectionSettings', 'SavedLegacySettings')) {
        $bytes = (Get-ItemProperty $regConn -EA SilentlyContinue).$val
        if ($bytes -and $bytes.Length -ge 9) {
            $bytes[8] = 1
            Set-ItemProperty -Path $regConn -Name $val -Value $bytes -EA SilentlyContinue
        }
    }

    try { netsh winhttp reset proxy 2>&1 | Out-Null } catch { }
    Notify-Inet
    if ('NativeCleanup' -as [type]) { [NativeCleanup]::IsActive = $false }
    $script:DaThayDoiProxy = $false
    $script:CongDangDung   = 0
}

function Stop-ProxyMode {
    if ($script:Proxy) { try { $script:Proxy.Stop() } catch { } ; $script:Proxy = $null }
    Restore-Hosts
    Restore-ProxyCfg
}

function Build-PacContent($port) {
    $domainsJs = ($AllGameDomains | ForEach-Object { "`"$_`"" }) -join ', '
    return @"
function FindProxyForURL(url, host) {
  host = host.toLowerCase();
  var d = [$domainsJs];
  for (var i = 0; i < d.length; i++) {
    if (host == d[i] || dnsDomainIs(host, "." + d[i])) return "PROXY 127.0.0.1:$port; DIRECT";
  }
  return "DIRECT";
}
"@
}

function Start-ProxyMode([int]$mode = 2) {
    if (-not ('SplitProxy' -as [type])) {
        try { Add-Type -TypeDefinition $MaProxy -Language CSharp -EA Stop }
        catch { Err "Khong khoi tao duoc proxy: $($_.Exception.Message)"; return $false }
    }
    if ('NativeCleanup' -as [type]) { [NativeCleanup]::Register() }

    if ($script:Proxy) {
        $script:Proxy.Mode = $mode
        $script:MoTa = "SplitProxy Mode $mode (cong $($script:CongDangDung))"
        return $true
    }

    $px = $null; $cong = 0
    foreach ($p in $CongProxy..($CongProxy + 10)) {
        try {
            $x = New-Object SplitProxy -ArgumentList $p
            $x.Pac  = Build-PacContent $p
            $x.Mode = $mode
            $x.Start()
            $px = $x; $cong = $p; break
        } catch { }
    }
    if (-not $px) { Err 'Khong mo duoc cong proxy nao.'; return $false }

    $script:Proxy        = $px
    $script:CongDangDung = $cong
    Save-ProxyCfg

    # Chi dung AutoConfigURL de phan luong domain Game/Steam qua PAC.
    # ProxyEnable giu = 0 de tranh ep toan bo traffic mang (Facebook, YouTube) vao localhost!
    Set-ItemProperty -Path $RegIE -Name AutoConfigURL -Value "http://127.0.0.1:$cong/proxy.pac" -EA SilentlyContinue
    Set-ItemProperty -Path $RegIE -Name ProxyEnable   -Value 0 -EA SilentlyContinue
    Remove-ItemProperty -Path $RegIE -Name ProxyServer -EA SilentlyContinue
    try { netsh winhttp reset proxy 2>&1 | Out-Null } catch { }
    Notify-Inet

    if ('NativeCleanup' -as [type]) { [NativeCleanup]::IsActive = $true }
    $script:DaThayDoiProxy = $true
    $script:MoTa           = "SplitProxy Mode $mode (cong $cong)"
    Ok "Proxy noi bo dang chay tai cong $cong (PAC loc domain Game)"

    if ($px.HasDirect443) {
        if (Apply-PubgHosts) {
            Ok 'PUBG Direct Sniper (Port 443 + Hosts) da duoc kich hoat!'
        }
    }
    return $true
}

# ================================================================
#  QUAN LY FILE HOSTS
# ================================================================
function Apply-PubgHosts {
    Save-Hosts
    $domainsToMap = @(
        'prod-live-front.playbattlegrounds.com',
        'prod-live-xenuine.playbattlegrounds.com',
        'api.pubg.com'
    )
    $linesToAdd = $domainsToMap | ForEach-Object { "127.0.0.1 $_ # SteamAccessFix" }
    try {
        $cur = if (Test-Path $FileHostsSys) { @(Get-Content $FileHostsSys -Encoding ASCII -EA SilentlyContinue) } else { @() }
        $filtered = @($cur | Where-Object { $_ -notmatch '#\s*SteamAccessFix' })
        $newContent = ($filtered + $linesToAdd) -join "`r`n"
        [IO.File]::WriteAllText($FileHostsSys, $newContent + "`r`n", [Text.Encoding]::ASCII)
        ipconfig /flushdns 2>&1 | Out-Null
        $script:DaThayDoiHosts = $true
        return $true
    } catch {
        return $false
    }
}

function Save-Hosts {
    if (Test-Path $FileHosts) { return }
    if (Test-Path $FileHostsSys) { Copy-Item -Path $FileHostsSys -Destination $FileHosts -Force }
}

function Restore-Hosts {
    if (Test-Path $FileHostsSys) {
        try {
            $lines = @(Get-Content $FileHostsSys -EA SilentlyContinue | Where-Object { $_ -notmatch '#\s*SteamAccessFix' })
            [IO.File]::WriteAllLines($FileHostsSys, [string[]]$lines, [Text.Encoding]::ASCII)
            ipconfig /flushdns 2>&1 | Out-Null
        } catch { }
    }
    if (Test-Path $FileHosts) {
        Remove-Item $FileHosts -Force -EA SilentlyContinue
    }
    $script:DaThayDoiHosts = $false
}

# ================================================================
#  TOI UU MANG GAME (FPT / VNPT / VIETTEL)
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
    Info 'Dang khoi phuc toan bo cai dat ve trang thai goc...'
    Stop-ProxyMode
    Restore-GamingNetworkTweaks
    Restore-Hosts
    Restore-Dns
    Ok 'He thong da duoc khoi phuc sach se.'
}

# ================================================================
#  KIEM TRA CAP NHAT GITHUB
# ================================================================
function Check-GitHubUpdate {
    if ([string]::IsNullOrWhiteSpace($script:GitHubRepo) -or $script:GitHubRepo -eq 'USERNAME/REPOSITORY') { return }
    if (-not $env:SELF -or -not (Test-Path $env:SELF)) { return }
    try {
        Info "Kiem tra cap nhat tu GitHub..."
        $tNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $remoteVer = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$($script:GitHubRepo)/main/VERSION.txt?t=$tNow" -Headers @{ 'Cache-Control' = 'no-cache' } -TimeoutSec 4 -EA Stop).ToString().Trim()

        if (-not $remoteVer) { return }
        if ($remoteVer -eq $script:AppVersion) {
            Ok "Dang dung phien ban moi nhat (v$script:AppVersion)."
            return
        }

        Say ''
        Ve-Khung "  CO PHIEN BAN CHINH THUC: v$remoteVer  (hien tai: v$script:AppVersion)" '' 'Green'
        Say '    [1]  Cap nhat / Dong bo ngay' 'Yellow'
        Say '    [2]  Bo qua, chay ban hien tai' 'Gray'
        Say ''

        $choice = '1'
        if (-not $script:AutoUpdate) {
            while ($true) {
                Write-Host '  Chon 1 hoac 2 [Enter = 1]: ' -ForegroundColor DarkGray -NoNewline
                $r = Read-Host
                if ($r -eq '' -or $r -eq '1') { $choice = '1'; break }
                elseif ($r -eq '2')            { $choice = '2'; break }
            }
        }

        if ($choice -eq '1') {
            Info 'Dang tai ban cap nhat tu GitHub...'
            $tmp = Join-Path $env:TEMP ("SAF_update_" + [guid]::NewGuid().ToString('N') + ".cmd")
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($script:GitHubRepo)/main/SteamAccessFix.cmd?t=$tNow" -Headers @{ 'Cache-Control' = 'no-cache' } -OutFile $tmp -TimeoutSec 15 -EA Stop
            $content = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
            if ($content.Contains('#PSBEGIN#') -and $content.Length -gt 2000) {
                Ok 'Xac thuc goi cap nhat hop le.'
                Ok "Da ghi de cap nhat vao: $env:SELF"
                Copy-Item -Path $tmp -Destination $env:SELF -Force
                Remove-Item $tmp -Force -EA SilentlyContinue
                Info 'Dang khoi dong lai phien ban moi...'
                Start-Sleep -Milliseconds 600
                Start-Process -FilePath $env:SELF -WorkingDirectory (Split-Path $env:SELF)
                exit
            } else {
                Err 'Goi cap nhat khong hop le. Da huy.'
                Remove-Item $tmp -Force -EA SilentlyContinue
            }
        } else {
            Info 'Bo qua cap nhat. Tiep tuc chay ban hien tai...'
            Start-Sleep -Milliseconds 600
        }
    } catch { }
}

# ================================================================
#  MAN HINH TRANG THAI & PHIM TAT RUNTIME
# ================================================================
function Show-StatusBar {
    $lvlText = switch ($script:CurrentLevel) {
        1 { 'Cap do 1 - DNS Google (8.8.8.8) + Toi uu Ping' }
        2 { "Cap do 2 - SplitProxy SNI (Phan manh TLS) | Port $($script:CongDangDung)" }
        default { "Cap do $($script:CurrentLevel)" }
    }
    Say ''
    Ve-Khung "  HE THONG HOAT DONG  -  SAN SANG VAO GAME" "  $lvlText" 'Green'
    Say '  Pham vi ho tro: Steam, PUBG, CS2, Dota 2, Naraka, Delta Force' 'DarkGreen'
    if ($script:DaThayDoiHosts) {
        Say '  PUBG Direct Sniper: Kich hoat (Port 443 + Hosts bypass chong rot mang)' 'Green'
    }
    Say '  Luu luong tran dau UDP di TRUC TIEP (0ms overhead, anti-cheat safe)' 'DarkGray'
    Say ''
    Sep
    Say '  Huong dan:' 'Cyan'
    Say '  - Mo Steam / Game de choi binh thuong.' 'White'
    Say '  - GIU CUA SO NAY MO trong suot qua trinh choi game neu dung SplitProxy.' 'Yellow'
    Sep
    Say '  Phim tat dieu khien:' 'DarkCyan'
    Say '  [1]      Chay Cap do 1 - DNS Google only (tat Proxy)' 'White'
    Say '  [2]      Chay Cap do 2 - SplitProxy SNI (vuot chan manh hon)' 'White'
    Say '  [K]      Giu lai DNS & toi uu Ping vinh vien roi thoat' 'White'
    Say '  [R]      KHOI PHUC MANG SACH 100% & thoat ngay' 'Yellow'
    Say '  [Enter]  Khoi phuc cai dat va thoat an toan (hoac go Q)' 'White'
    Sep
    Say ''
}

# ================================================================
#  DON DEP & TU PHUC HOI SU CO (SELF-HEALING)
# ================================================================
function Sanitize-Environment {
    $hasIssue = $false

    # 1. Kiem tra Registry ton dong proxy cu (127.0.0.1 hoac port 18080)
    $cu = Get-ItemProperty $RegIE -EA SilentlyContinue
    if ($cu.ProxyServer -match '127\.0\.0\.1|18080' -or $cu.AutoConfigURL -match '127\.0\.0\.1|18080|proxy\.pac') {
        $hasIssue = $true
    }

    # 2. Kiem tra WinHTTP
    $winhttp = netsh winhttp show proxy 2>&1 | Out-String
    if ($winhttp -match '127\.0\.0\.1|18080') {
        $hasIssue = $true
    }

    # 3. Kiem tra file hosts con sot lai domain PUBG cua SAF khong
    if (Test-Path $FileHostsSys) {
        $hLines = Get-Content $FileHostsSys -EA SilentlyContinue
        if ($hLines -match '#\s*SteamAccessFix') {
            $hasIssue = $true
        }
    }

    # 4. Kiem tra file backup cu bi nhiem doc
    if (Test-Path $FileProxy) {
        try {
            $b = Get-Content $FileProxy -Raw | ConvertFrom-Json
            if ($b.ProxyServer -match '127\.0\.0\.1|18080' -or $b.AutoConfigURL -match '127\.0\.0\.1|18080') {
                $hasIssue = $true
                Remove-Item $FileProxy -Force -EA SilentlyContinue
            }
        } catch { }
    }

    if ($hasIssue -or (Test-Path $FileDns) -or (Test-Path $FileProxy) -or (Test-Path $FileHosts) -or (Test-Path $FileNetTweaks)) {
        Warn 'Phat hien cai dat mang chua dong dung cach (hoac ton dong tu ban cu) - dang tu dong khoi phuc...'
        Restore-All
        Start-Sleep -Milliseconds 600
        Ok 'He thong da duoc lam sach va san sang!'
        Say ''
    }
}

# ================================================================
#  CHUONG TRINH CHINH (KHONG CHAY TEST - KHOI DONG TRUC TIEP 0.5s)
# ================================================================
try {
    Ve-Khung "  SteamAccessFix v$script:AppVersion  -  Game Connectivity Fix"

    # Don dep phien truoc neu bi tat dot ngot & Tu chua lanh neu dinh loi ban cu v1.1.3
    Sanitize-Environment

    # Khoi tao C# va dang ky Exit Handler som de bat tat ca cac su kien dong cua so [X]
    if (-not ('NativeCleanup' -as [type])) {
        try { Add-Type -TypeDefinition $MaProxy -Language CSharp -EA Stop } catch { }
    }
    if ('NativeCleanup' -as [type]) {
        [NativeCleanup]::Register()
    }

    Check-GitHubUpdate
    Sep

    # 1. Gan DNS Google
    Info 'Dang gan DNS Google (8.8.8.8 & IPv6)...'
    Set-GoogleDns
    Ok 'Da gan DNS: 8.8.8.8  &  2001:4860:4860::8888'

    # 2. Toi uu Network Stack cho Game
    Info 'Dang ap dung toi uu network stack cho game...'
    Apply-GamingNetworkTweaks
    Ok 'Da toi uu NetworkThrottling & TCP AutoTuning.'

    # 3. Kich hoat SplitProxy Mode 2
    Info 'Dang kich hoat SplitProxy (Phan manh TLS SNI Mode 2)...'
    if (Start-ProxyMode 2) {
        $script:CurrentLevel = 2
        Ok 'Cap do 2 thanh cong! SplitProxy vuot qua bo loc SNI.'
    } else {
        $script:CurrentLevel = 1
        Warn 'Khong khoi dong duoc proxy. Dang chay Cap do 1 (DNS Google).'
    }

    Show-StatusBar

    while ($true) {
        Write-Host '  Lua chon [1 / 2 / K / R / Enter=Thoat]: ' -ForegroundColor Yellow -NoNewline
        $k = Read-Host

        if ($k -eq '2') {
            Say ''
            Info 'Dang kich hoat Cap do 2 (SplitProxy)...'
            if (Start-ProxyMode 2) {
                $script:CurrentLevel = 2
                Ok 'SplitProxy dang hoat dong!'
            } else {
                Err 'Khong khoi dong duoc SplitProxy.'
            }
            Say ''
            Show-StatusBar
        }
        elseif ($k -eq '1') {
            Say ''
            Info 'Dang chuyen ve Cap do 1 (DNS Google only)...'
            Stop-ProxyMode
            $script:CurrentLevel = 1
            $script:MoTa = 'DNS Google (8.8.8.8) + Toi uu Ping Game'
            Ok 'Da tat Proxy. Dang chay Cap do 1 (DNS Google only).'
            Say ''
            Show-StatusBar
        }
        elseif ($k -match '^[kK]') {
            Say ''
            Info 'Da chon giu lai DNS Google va toi uu Ping.'
            $script:DaThayDoiDns    = $false
            $script:DaThayDoiTweaks = $false
            if (Test-Path $FileDns)       { Remove-Item $FileDns       -Force -EA SilentlyContinue }
            if (Test-Path $FileNetTweaks) { Remove-Item $FileNetTweaks -Force -EA SilentlyContinue }
            Stop-ProxyMode
            Ok 'DNS Google & toi uu Ping da duoc luu vinh vien tren may.'
            break
        }
        elseif ($k -match '^[rR]') {
            Say ''
            Info 'Dang khoi phuc mang he thong sach 100% va go bo moi thiet lap...'
            Restore-All
            Remove-Item -Path (Join-Path $ThuMucLuu '*') -Force -Recurse -EA SilentlyContinue
            Ok 'He thong da duoc khoi phuc sach se hoan toan!'
            Start-Sleep -Seconds 1
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
finally {
    if ($script:DaThayDoiDns -or $script:DaThayDoiProxy -or $script:DaThayDoiHosts -or $script:DaThayDoiTweaks) {
        Say ''
        Sep
        Restore-All
        Start-Sleep -Seconds 1
    }
    if ('NativeCleanup' -as [type]) {
        [NativeCleanup]::Unregister()
    }
}
