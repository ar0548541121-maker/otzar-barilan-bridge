# ===== גשר הספריות של כתיב מלא =====
# רץ במחשב העורך, מוסתר, ועולה עם הכניסה ל-Windows. כשמערכת כתיב מלא מחפשת מקורות, היא שולחת לכאן
# את ניסוחי החיפוש; הגשר מחפש באוצר החכמה ובבר אילן על שולחן עבודה נסתר שהעורך לא רואה, ומחזיר את התוצאות.
# אינו מתקין דבר, אינו משנה את ההגדרות של התוכנות, ואינו נוגע במסך, בעכבר או במקלדת של העורך.
# קבצים: %LOCALAPPDATA%\KtivBridge\ (ktiv-bridge.ps1, config.json, bridge.log, run.vbs)
# -Local: מצב התוסף לאפליקציית קלוד (ktiv/bridge/desktop). בלי שרת: משימות מגיעות בשורות JSON בקלט,
#         ותשובות יוצאות בשורות שמתחילות ב-@@KB@@. תמונות נשמרות בתיקייה ImgDir. יומן: %LOCALAPPDATA%\OtzarBarilanClaude
param([switch]$Install, [switch]$Run, [switch]$Uninstall, [string]$Server = '', [string]$Key = '', [switch]$Local, [string]$ImgDir = '')
$VERSION = '2026.11.09.8'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$HOME_DIR = Join-Path $env:LOCALAPPDATA $(if ($Local) { 'OtzarBarilanClaude' } else { 'KtivBridge' })
$SELF = Join-Path $HOME_DIR 'ktiv-bridge.ps1'
$CONF_FILE = Join-Path $HOME_DIR 'config.json'
$LOG_FILE = Join-Path $HOME_DIR 'bridge.log'
$VBS = Join-Path $HOME_DIR 'run.vbs'
$STARTUP_VBS = Join-Path ([Environment]::GetFolderPath('Startup')) 'KtivBridge.vbs'
New-Item -ItemType Directory -Force -Path $HOME_DIR | Out-Null

function L([string]$msg) {
  try {
    if ((Test-Path $LOG_FILE) -and (Get-Item $LOG_FILE).Length -gt 2MB) { Move-Item -Force $LOG_FILE ($LOG_FILE + '.old') }
    Add-Content -Path $LOG_FILE -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg) -Encoding UTF8
  } catch {}
}

# ---------------------------------------------------------------- C#: שולחן עבודה נסתר, Win32, לוח העתקה, CDP
$cs = @'
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Net.WebSockets;
using System.Runtime.InteropServices;

public static class KB {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateDesktop(string name, IntPtr dev, IntPtr devmode, int flags, uint access, IntPtr sa);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] static extern bool SetThreadDesktop(IntPtr h);
  [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr d, EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, string l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr h);
  [DllImport("user32.dll")] static extern bool CloseClipboard();
  [DllImport("user32.dll")] static extern bool EmptyClipboard();
  [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint f);
  [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint f, IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
  [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr h);
  [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint f, UIntPtr n);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct STARTUPINFO { public int cb; public string lpReserved; public string lpDesktop; public string lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

  static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Txt(IntPtr h) {
    var s = new StringBuilder(4096); IntPtr r;
    SendMessageTimeout(h, 0x000D, (IntPtr)4096, s, 2, 2000, out r);
    if (s.Length == 0) GetWindowText(h, s, 4096);
    return s.ToString();
  }
  public static IntPtr NewDesk(string name) { return CreateDesktop(name, IntPtr.Zero, IntPtr.Zero, 0, 0x10000000, IntPtr.Zero); }
  public static bool CloseDesk(IntPtr d) { return d != IntPtr.Zero && CloseDesktop(d); }
  public static int Launch(string exe, string args, string cwd, string desk) {
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si); si.lpDesktop = "WinSta0\\" + desk;
    PROCESS_INFORMATION pi;
    if (!CreateProcess(null, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, cwd, ref si, out pi)) return -Marshal.GetLastWin32Error();
    CloseHandle(pi.hThread); CloseHandle(pi.hProcess); return pi.dwProcessId;
  }
  public static bool Alive(int pid) { if (pid <= 0) return false; try { var p = Process.GetProcessById(pid); return !p.HasExited; } catch { return false; } }
  static List<IntPtr> Tops(IntPtr desk, int pid) {
    var l = new List<IntPtr>();
    EnumDesktopWindows(desk, (h, x) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) l.Add(h); return true; }, IntPtr.Zero);
    return l;
  }
  static List<IntPtr> Kids(IntPtr parent) { var l = new List<IntPtr>(); EnumChildWindows(parent, (h, x) => { l.Add(h); return true; }, IntPtr.Zero); return l; }
  static List<IntPtr> Dialogs(IntPtr desk, int pid) { var l = new List<IntPtr>(); foreach (var h in Tops(desk, pid)) if (Cls(h) == "#32770" && IsWindowVisible(h)) l.Add(h); return l; }
  static string OnDesk(IntPtr desk, Func<string> f) {
    string res = null; Exception err = null;
    var th = new Thread(() => { try { if (!SetThreadDesktop(desk)) throw new Exception("SetThreadDesktop " + Marshal.GetLastWin32Error()); res = f(); } catch (Exception e) { err = e; } });
    th.SetApartmentState(ApartmentState.STA); th.Start(); th.Join();
    if (err != null) throw err;
    return res;
  }

  // ---------- לוח ההעתקה ----------
  static string ClipText() {
    string t = null;
    for (int i = 0; i < 20 && !OpenClipboard(IntPtr.Zero); i++) Thread.Sleep(100);
    try { IntPtr h = GetClipboardData(13); if (h != IntPtr.Zero) { IntPtr p = GlobalLock(h); if (p != IntPtr.Zero) { t = Marshal.PtrToStringUni(p); GlobalUnlock(h); } } }
    finally { CloseClipboard(); }
    return t;
  }
  static void SetClip(string t) {
    for (int i = 0; i < 20 && !OpenClipboard(IntPtr.Zero); i++) Thread.Sleep(100);
    try {
      EmptyClipboard();
      if (t != null) { byte[] b = Encoding.Unicode.GetBytes(t + "\0"); IntPtr g = GlobalAlloc(0x0002, (UIntPtr)b.Length); IntPtr p = GlobalLock(g); Marshal.Copy(b, 0, p, b.Length); GlobalUnlock(g); SetClipboardData(13, g); }
    } finally { CloseClipboard(); }
  }

  // ---------- בר אילן ----------
  public static IntPtr RDesk = IntPtr.Zero; public static int RPid = 0; public static IntPtr RMain = IntPtr.Zero;
  public static string RLog = "";

  public static string ResponsaEnsure(string exe) {
    if (RPid > 0 && Alive(RPid) && RMain != IntPtr.Zero) return "ok";
    ResponsaClose();
    RDesk = NewDesk("ktivbridge_r");
    if (RDesk == IntPtr.Zero) return "CreateDesktop failed " + Marshal.GetLastWin32Error();
    return OnDesk(RDesk, () => {
      RPid = Launch(exe, "", Path.GetDirectoryName(exe), "ktivbridge_r");
      if (RPid <= 0) return "launch failed " + RPid;
      for (int i = 0; i < 90 && RMain == IntPtr.Zero; i++) {
        Thread.Sleep(500);
        foreach (var h in Tops(RDesk, RPid)) if (Cls(h) == "ResponsaProject") RMain = h;
        if (!Alive(RPid)) return "process exited";
      }
      if (RMain == IntPtr.Zero) return "main window not found";
      Thread.Sleep(4000);
      foreach (var d in Dialogs(RDesk, RPid)) PostMessage(d, 0x0111, (IntPtr)2, IntPtr.Zero);
      Thread.Sleep(800);
      return "ok";
    });
  }

  public static void ResponsaClose() {
    if (RPid > 0) { try { var p = Process.GetProcessById(RPid); p.Kill(); p.WaitForExit(5000); } catch { } }
    RPid = 0; RMain = IntPtr.Zero;
    if (RDesk != IntPtr.Zero) { CloseDesk(RDesk); RDesk = IntPtr.Zero; }
  }

  static string CopyResults() {
    // בחר הכול + העתק (פקודות MFC רגילות), עם שמירה ושחזור של לוח ההעתקה של העורך
    IntPtr r;
    string saved = ClipText(); uint s0 = GetClipboardSequenceNumber();
    SendMessageTimeout(RMain, 0x0111, (IntPtr)57642, IntPtr.Zero, 2, 8000, out r); Thread.Sleep(700);
    SendMessageTimeout(RMain, 0x0111, (IntPtr)57634, IntPtr.Zero, 2, 8000, out r); Thread.Sleep(900);
    string got = null;
    if (GetClipboardSequenceNumber() != s0) { got = ClipText(); SetClip(saved); }
    return got ?? "";
  }

  public static string ResponsaSearch(string q, int timeoutSec) {
    if (RMain == IntPtr.Zero) return "\u0001ERR\u0001not running";
    return OnDesk(RDesk, () => {
      IntPtr r;
      foreach (var d in Dialogs(RDesk, RPid)) PostMessage(d, 0x0111, (IntPtr)2, IntPtr.Zero);
      Thread.Sleep(500);
      string title0 = Txt(RMain);
      PostMessage(RMain, 0x0111, (IntPtr)32857, IntPtr.Zero);
      IntPtr dlg = IntPtr.Zero;
      for (int i = 0; i < 30 && dlg == IntPtr.Zero; i++) { Thread.Sleep(300); foreach (var d in Dialogs(RDesk, RPid)) dlg = d; }
      if (dlg == IntPtr.Zero) return "\u0001ERR\u0001search dialog did not open";
      IntPtr edit = IntPtr.Zero, go = IntPtr.Zero;
      foreach (var k in Kids(dlg)) { int id = GetDlgCtrlID(k); if (id == 1233 && Cls(k) == "Edit") edit = k; if (id == 1 && Cls(k) == "Button") go = k; }
      if (edit == IntPtr.Zero) foreach (var k in Kids(dlg)) { if (Cls(k) == "Edit" && IsWindowVisible(k) && IsWindowEnabled(k)) { edit = k; break; } }
      if (edit == IntPtr.Zero || go == IntPtr.Zero) { PostMessage(dlg, 0x0111, (IntPtr)2, IntPtr.Zero); return "\u0001ERR\u0001search box not found"; }
      SendMessageTimeout(edit, 0x000C, IntPtr.Zero, q, 2, 3000, out r);
      PostMessage(go, 0x00F5, IntPtr.Zero, IntPtr.Zero);
      string now = title0, last = ""; bool closed = false; int stable = 0;
      for (int i = 0; i < timeoutSec * 2; i++) {
        Thread.Sleep(500); now = Txt(RMain);
        var open = Dialogs(RDesk, RPid);
        if (!open.Contains(dlg)) closed = true;
        if (closed) { if (now == last) stable++; else stable = 0; last = now; if (stable >= 5 && i >= 4) break; }
        else if (i > 20 && open.Count > 0 && !open.Contains(dlg)) break;
        // הודעה מעל חלון החיפוש ("שגיאה בהגדרת השאילתה", "מידע"): לא מחכים עד הסוף (בדיקה 18: חיכינו 70 שנ')
        if (!closed && i > 2) { bool other = false; foreach (var d in open) if (d != dlg) other = true; if (other) { Thread.Sleep(300); break; } }
      }
      // הודעה שנשארה פתוחה (למשל "לא נמצאו תוצאות")
      var msgs = new StringBuilder();
      foreach (var d in Dialogs(RDesk, RPid)) { foreach (var k in Kids(d)) if (Cls(k) == "Static") { string t = Txt(k); if (t.Trim().Length > 0) msgs.Append(t.Trim()).Append(" | "); } PostMessage(d, 0x0111, (IntPtr)2, IntPtr.Zero); }
      // אחרי הודעה (שגיאה / אין תוצאות) חלון התוצאות עוד מציג את החיפוש הקודם: לא מעתיקים אותו
      string text = (msgs.Length > 0 && now == title0) ? "" : CopyResults();
      return "\u0001TITLE\u0001" + now + "\u0001MSG\u0001" + msgs + "\u0001TEXT\u0001" + text;
    });
  }

  public static string ResponsaMore(int pages) {
    if (RMain == IntPtr.Zero) return "\u0001ERR\u0001not running";
    return OnDesk(RDesk, () => {
      IntPtr mdi = IntPtr.Zero;
      foreach (var k in Kids(RMain)) if (Cls(k) == "MDIClient") { mdi = k; break; }
      if (mdi == IntPtr.Zero) return "\u0001ERR\u0001no MDI";
      IntPtr child; SendMessageTimeout(mdi, 0x0229, IntPtr.Zero, IntPtr.Zero, 2, 3000, out child);
      IntPtr view = IntPtr.Zero; int best = 0;
      foreach (var k in Kids(child)) { string c = Cls(k); if (c.StartsWith("Afx:") && IsWindowVisible(k)) { int n = c.Length; if (n > best) { best = n; view = k; } } }
      if (view == IntPtr.Zero) return "\u0001ERR\u0001no results view";
      for (int i = 0; i < pages; i++) { PostMessage(view, 0x0100, (IntPtr)0x22, (IntPtr)0x01510001); PostMessage(view, 0x0101, (IntPtr)0x22, unchecked((IntPtr)(int)0xC1510001)); Thread.Sleep(700); }
      Thread.Sleep(800);
      return "\u0001TITLE\u0001" + Txt(RMain) + "\u0001MSG\u0001\u0001TEXT\u0001" + CopyResults();
    });
  }

  // ---------- התקליטור התורני (בדיקות 20–24): תוכנת MFC, חלון שאילתה עם תיבות, חלון ספרים, חלון תוצאות ----------
  public static IntPtr DDesk = IntPtr.Zero; public static int DPid = 0; public static IntPtr DMain = IntPtr.Zero;
  public static string DBooksTitle = "";
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, ref RECT r);

  static IntPtr DDeep(IntPtr parent, int id, string cls) { foreach (var c in Kids(parent)) if (GetDlgCtrlID(c) == id && Cls(c) == cls) return c; return IntPtr.Zero; }
  static IntPtr DKid(IntPtr parent, int id, string cls) { foreach (var c in Kids(parent)) if (GetDlgCtrlID(c) == id && Cls(c) == cls && GetParent(c) == parent) return c; return IntPtr.Zero; }
  static IntPtr DPane(int btnId, string btnText, int otherId, string otherCls) {
    if (DMain == IntPtr.Zero) return IntPtr.Zero;
    foreach (var k in Kids(DMain)) {
      if (Cls(k) != "#32770") continue;
      bool a = false, b = false;
      foreach (var c in Kids(k)) { int id = GetDlgCtrlID(c); if (id == btnId && Cls(c) == "Button" && Txt(c) == btnText) a = true; if (id == otherId && Cls(c) == otherCls) b = true; }
      if (a && b) return k;
    }
    return IntPtr.Zero;
  }
  static IntPtr DQuery() { return DPane(1003, "SearchH", 1000, "ComboBox"); }
  static IntPtr DBooks() { return DPane(1005, "SelectAllH", 1012, "ListBox"); }
  static string DStatus() { foreach (var c in Kids(DMain)) if (Cls(c) == "msctls_statusbar32") return Txt(c).Trim(); return ""; }
  static IntPtr DMdi() { foreach (var c in Kids(DMain)) if (Cls(c) == "MDIClient") return c; return IntPtr.Zero; }
  static List<IntPtr> DWins() { var l = new List<IntPtr>(); IntPtr m = DMdi(); if (m != IntPtr.Zero) foreach (var k in Kids(m)) if (GetParent(k) == m) l.Add(k); return l; }
  static void DActivate(IntPtr w) { IntPtr r, m = DMdi(); if (m != IntPtr.Zero && w != IntPtr.Zero) SendMessageTimeout(m, 0x0222, w, IntPtr.Zero, 2, 3000, out r); }
  static List<IntPtr> DPopups() { var l = new List<IntPtr>(); foreach (var h in Tops(DDesk, DPid)) if (h != DMain && Cls(h) == "#32770" && IsWindowVisible(h)) l.Add(h); return l; }
  static string DStatics(IntPtr h) {
    var s = new StringBuilder(); foreach (var k in Kids(h)) if (Cls(k) == "Static") { string t = Txt(k).Trim(); if (t.Length > 0) s.Append(t).Append(" | "); }
    if (s.Length == 0) foreach (var k in Kids(h)) if (Cls(k) != "Button") { string t = Txt(k).Trim(); if (t.Length > 0) s.Append(t).Append(" | "); }
    return s.ToString().Replace("\r", " ").Replace("\n", " ");
  }
  static void DDismiss(IntPtr h) {
    // הודעה ("לא נמצאו תוצאות לחיפוש", כפתור 125 "אישור"): לוחצים על הכפתור הראשון שלה, ואם אין – ביטול
    foreach (var k in Kids(h)) if (Cls(k) == "Button" && IsWindowVisible(k)) { PostMessage(h, 0x0111, (IntPtr)GetDlgCtrlID(k), k); return; }
    PostMessage(h, 0x0111, (IntPtr)2, IntPtr.Zero);
  }
  static void DKey(IntPtr h, int vk, int times) { for (int i = 0; i < times; i++) { PostMessage(h, 0x0100, (IntPtr)vk, (IntPtr)1); PostMessage(h, 0x0101, (IntPtr)vk, unchecked((IntPtr)(int)0xC0000001)); Thread.Sleep(120); } }
  static void DSet(IntPtr c, string t) { IntPtr r; SendMessageTimeout(c, 0x000C, IntPtr.Zero, t, 2, 3000, out r); foreach (var e in Kids(c)) if (Cls(e) == "Edit") SendMessageTimeout(e, 0x000C, IntPtr.Zero, t, 2, 3000, out r); }

  static string DSelectAll() {
    // הדרך שעבדה בבדיקה 24: חיצים עד "מדור כל הספרים" + Enter, לחיצה כפולה על השורה הראשונה, ו"הכל"
    IntPtr bd = DBooks();
    if (bd == IntPtr.Zero) { PostMessage(DMain, 0x0111, (IntPtr)32772, IntPtr.Zero); for (int i = 0; i < 20 && bd == IntPtr.Zero; i++) { Thread.Sleep(300); bd = DBooks(); } }
    if (bd == IntPtr.Zero) return "אין חלון ספרים";
    DActivate(GetParent(bd));
    IntPtr lb = DDeep(bd, 1012, "ListBox"), r; if (lb == IntPtr.Zero) return "אין רשימת ספרים";   // בתוך מסגרת פס הגלילה, לא ילד ישיר (בדיקה 25)
    SendMessageTimeout(lb, 0x018B, IntPtr.Zero, IntPtr.Zero, 2, 2000, out r); int n = (int)r, all = -1;
    for (int i = 0; i < n && all < 0; i++) { var s = new StringBuilder(2048); SendMessageTimeout(lb, 0x0189, (IntPtr)i, s, 2, 2000, out r); if (s.ToString().Contains("כל הספרים")) all = i; }
    if (all < 0) return "אין שורת כל הספרים";
    DKey(lb, 36, 1); DKey(lb, 40, all); Thread.Sleep(500); DKey(lb, 13, 1); Thread.Sleep(3000);
    var rc = new RECT(); SendMessage(lb, 0x0198, IntPtr.Zero, ref rc);
    int x = (rc.L + rc.R) / 2, y = (rc.T + rc.B) / 2; IntPtr lp = (IntPtr)((y << 16) | (x & 0xFFFF));
    PostMessage(lb, 0x0201, (IntPtr)1, lp); PostMessage(lb, 0x0202, IntPtr.Zero, lp); Thread.Sleep(100);
    PostMessage(lb, 0x0203, (IntPtr)1, lp); PostMessage(lb, 0x0202, IntPtr.Zero, lp); Thread.Sleep(3000);
    IntPtr all1 = DKid(bd, 1005, "Button"); if (all1 != IntPtr.Zero) PostMessage(all1, 0x00F5, IntPtr.Zero, IntPtr.Zero);
    Thread.Sleep(2000);
    IntPtr q = DQuery(); return q == IntPtr.Zero ? "" : Txt(GetParent(q));
  }

  public static string DbsEnsure(string exe) {
    if (DPid > 0 && Alive(DPid) && DMain != IntPtr.Zero) return "ok";
    DbsClose();
    DDesk = NewDesk("ktivbridge_d");
    if (DDesk == IntPtr.Zero) return "CreateDesktop failed " + Marshal.GetLastWin32Error();
    return OnDesk(DDesk, () => {
      DPid = Launch(exe, "", Path.GetDirectoryName(exe), "ktivbridge_d");
      if (DPid <= 0) return "launch failed " + DPid;
      for (int i = 0; i < 120 && (DMain == IntPtr.Zero || DQuery() == IntPtr.Zero); i++) {
        Thread.Sleep(500);
        if (DMain == IntPtr.Zero) foreach (var h in Tops(DDesk, DPid)) if (Cls(h).StartsWith("Afx:") && IsWindowVisible(h) && Txt(h).Contains("התקליטור")) DMain = h;
        if (!Alive(DPid)) return "process exited";
        if (i > 4) foreach (var p in DPopups()) DDismiss(p);
      }
      if (DMain == IntPtr.Zero) return "main window not found";
      if (DQuery() == IntPtr.Zero) return "query window not found";
      DBooksTitle = DSelectAll();
      return "ok";
    });
  }

  public static void DbsClose() {
    if (DPid > 0) { try { var p = Process.GetProcessById(DPid); p.Kill(); p.WaitForExit(5000); } catch { } }
    DPid = 0; DMain = IntPtr.Zero;
    if (DDesk != IntPtr.Zero) { CloseDesk(DDesk); DDesk = IntPtr.Zero; }
  }

  // boxes: לכל תיבה "מילה" או "מילה/חלופה/חלופה". dist: מרחק בין המילים (0 = בלי לשנות). maxHits: כמה תוצאות להעתיק
  public static string DbsSearch(string[] boxes, int dist, int maxHits, int timeoutSec) {
    if (DMain == IntPtr.Zero) return "\u0001ERR\u0001not running";
    return OnDesk(DDesk, () => {
      IntPtr r;
      foreach (var p in DPopups()) DDismiss(p);
      foreach (var w in DWins()) if (Txt(w).Contains("תוצאות")) PostMessage(w, 0x0010, IntPtr.Zero, IntPtr.Zero);   // תוצאות קודמות
      Thread.Sleep(500);
      IntPtr q = DQuery();
      if (q == IntPtr.Zero) { PostMessage(DMain, 0x0111, (IntPtr)32771, IntPtr.Zero); for (int i = 0; i < 20 && q == IntPtr.Zero; i++) { Thread.Sleep(300); q = DQuery(); } }
      if (q == IntPtr.Zero) return "\u0001ERR\u0001query window not found";
      DActivate(GetParent(q));
      IntPtr clear = DKid(q, 1004, "Button"); if (clear != IntPtr.Zero) { PostMessage(clear, 0x00F5, IntPtr.Zero, IntPtr.Zero); Thread.Sleep(800); }
      bool alts = false; foreach (var b in boxes) if (b.Contains("/")) alts = true;
      IntPtr a1 = DKid(q, 1001, "ComboBox");
      if (alts && a1 != IntPtr.Zero && !IsWindowVisible(a1)) { PostMessage(DMain, 0x0111, (IntPtr)32782, IntPtr.Zero); Thread.Sleep(800); }   // מילים חילופיות
      var echo = new StringBuilder();
      for (int i = 0; i < 8; i++) {
        string[] ws = i < boxes.Length ? boxes[i].Split('/') : new string[0];
        for (int j = 0; j < 4; j++) {
          IntPtr c = DKid(q, 1000 + i * 5 + j, "ComboBox"); if (c == IntPtr.Zero) continue;
          string w = j < ws.Length ? ws[j].Trim() : "";
          if (w.Length > 0 || j == 0 || IsWindowVisible(c)) DSet(c, w);
          if (w.Length > 0) echo.Append(j == 0 ? (i > 0 ? " " : "") : "/").Append(Txt(c));
        }
      }
      if (dist > 0) { IntPtr d = DKid(q, 1016, "Edit"); if (d != IntPtr.Zero) { SendMessageTimeout(d, 0x000C, IntPtr.Zero, dist.ToString(), 2, 3000, out r); echo.Append(" | מרחק " + Txt(d)); } }
      var before = DWins();
      IntPtr go = DKid(q, 1003, "Button"); if (go == IntPtr.Zero) return "\u0001ERR\u0001search button not found";
      PostMessage(go, 0x00F5, IntPtr.Zero, IntPtr.Zero);
      IntPtr res = IntPtr.Zero; string msg = ""; var seen = new Dictionary<IntPtr, int>();
      for (int i = 0; i < timeoutSec * 2 && res == IntPtr.Zero && msg.Length == 0; i++) {
        Thread.Sleep(500);
        foreach (var p in DPopups()) {
          // הודעה: עם טקסט – מיד; בלי טקסט שאפשר לקרוא – אחרי 2 שנ' (בדיקה 25: חיפוש אחד חיכה 90 שנ')
          int n; seen.TryGetValue(p, out n); seen[p] = ++n;
          string t = DStatics(p);
          if (t.Length > 0 || n >= 4) { msg += t.Length > 0 ? t : "חלון קופץ: " + Txt(p); DDismiss(p); }
        }
        foreach (var w in DWins()) if (!before.Contains(w) && Txt(w).Contains("תוצאות")) res = w;
      }
      if (res == IntPtr.Zero) return "\u0001TITLE\u0001\u0001MSG\u0001" + (msg.Length > 0 ? msg : "timeout") + "\u0001TEXT\u0001\u0001Q\u0001" + echo;
      // הכותרת מתעדכנת בזמן החיפוש ("1 תוצאות", ואחר כך 259; בדיקה 25): מחכים שלא תשתנה 2 שנ' ושורת המצב Ready
      string title = Txt(res).Trim();
      for (int i = 0, same = 0; i < timeoutSec * 2 && same < 4; i++) {
        Thread.Sleep(500); string t = Txt(res).Trim(), st = DStatus();
        if (t == title && (st.Length == 0 || st.Contains("Ready") || st.Contains("מוכן"))) same++; else { same = 0; title = t; }
      }
      int count = -1; var m = System.Text.RegularExpressions.Regex.Match(title, @"-\s*([\d,]+)\s+תוצאות"); if (m.Success) count = int.Parse(m.Groups[1].Value.Replace(",", ""));
      string text = "";
      int upto = count > 0 ? Math.Min(maxHits, count) : maxHits;
      if (upto > 0) {
        DActivate(res); Thread.Sleep(300);
        string saved = ClipText(); uint s0 = GetClipboardSequenceNumber();
        PostMessage(DMain, 0x0111, (IntPtr)32790, IntPtr.Zero);   // תוצאות > העתק...
        IntPtr dlg = IntPtr.Zero;
        for (int i = 0; i < 20 && dlg == IntPtr.Zero; i++) { Thread.Sleep(250); foreach (var p in DPopups()) if (DKid(p, 1028, "Button") != IntPtr.Zero) dlg = p; }
        if (dlg != IntPtr.Zero) {
          SendMessageTimeout(DKid(dlg, 1028, "Button"), 0x00F5, IntPtr.Zero, IntPtr.Zero, 2, 3000, out r);   // ממספר תוצאה
          SendMessageTimeout(DKid(dlg, 1030, "Edit"), 0x000C, IntPtr.Zero, "1", 2, 3000, out r);
          SendMessageTimeout(DKid(dlg, 1031, "Edit"), 0x000C, IntPtr.Zero, upto.ToString(), 2, 3000, out r);
          Thread.Sleep(300);
          PostMessage(dlg, 0x0111, (IntPtr)1, DKid(dlg, 1, "Button"));
          for (int i = 0; i < 60 && GetClipboardSequenceNumber() == s0; i++) Thread.Sleep(250);
          if (GetClipboardSequenceNumber() != s0) { Thread.Sleep(500); text = ClipText() ?? ""; SetClip(saved); }
          foreach (var p in DPopups()) DDismiss(p);
        } else msg += "copy dialog did not open";
      }
      return "\u0001TITLE\u0001" + title + "\u0001MSG\u0001" + msg + "\u0001TEXT\u0001" + text + "\u0001Q\u0001" + echo;
    });
  }

  // ---------- חיבור קבוע לממשק השליטה של אוצר החכמה (CDP) ----------
  public class Cdp : IDisposable {
    ClientWebSocket ws; int next = 1; byte[] buf = new byte[1 << 20];
    public Cdp(string url) { ws = new ClientWebSocket(); ws.ConnectAsync(new Uri(url), new CancellationTokenSource(15000).Token).Wait(); }
    public bool Open { get { return ws != null && ws.State == WebSocketState.Open; } }
    public string Send(string method, string paramsJson, int timeoutMs) {
      int id = next++;
      string msg = "{\"id\":" + id + ",\"method\":\"" + method + "\",\"params\":" + (string.IsNullOrEmpty(paramsJson) ? "{}" : paramsJson) + "}";
      var cts = new CancellationTokenSource(timeoutMs);
      byte[] b = Encoding.UTF8.GetBytes(msg);
      ws.SendAsync(new ArraySegment<byte>(b), WebSocketMessageType.Text, true, cts.Token).Wait();
      string want = "\"id\":" + id + ",";
      while (true) {
        var ms = new MemoryStream(); WebSocketReceiveResult res;
        do { res = ws.ReceiveAsync(new ArraySegment<byte>(buf), cts.Token).Result; ms.Write(buf, 0, res.Count); } while (!res.EndOfMessage);
        string s = Encoding.UTF8.GetString(ms.ToArray());
        if (s.StartsWith("{" + want) || s.Contains(want)) return s;
      }
    }
    public void Dispose() { try { ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", new CancellationTokenSource(2000).Token).Wait(2000); } catch { } ws = null; }
  }
  public static string J(string s) {
    var sb = new StringBuilder("\"");
    foreach (char c in s ?? "") {
      if (c == '"') sb.Append("\\\""); else if (c == '\\') sb.Append("\\\\"); else if (c == '\n') sb.Append("\\n"); else if (c == '\r') sb.Append("\\r"); else if (c == '\t') sb.Append("\\t");
      else if (c < 32 || c > 126) sb.Append("\\u" + ((int)c).ToString("x4")); else sb.Append(c);
    }
    return sb.Append("\"").ToString();
  }
}
'@
if (-not ('KB' -as [type])) {
  try { Add-Type -TypeDefinition $cs -Language CSharp -IgnoreWarnings } catch { L ('שגיאת הידור: ' + $_); throw }
}

# ---------------------------------------------------------------- הגדרות וחיבור לשרת
function Read-Conf { try { return Get-Content -Raw -Encoding UTF8 $CONF_FILE | ConvertFrom-Json } catch { return $null } }

function Api([string]$method, [string]$path, $body = $null, [int]$timeoutSec = 60) {
  if ($Local) {   # אין שרת: התקדמות יוצאת בשורה לתוסף, וכל השאר לא קיים
    if ($path -like '/bridge-api/progress/*' -and $body) { Out-Local @{ progress = [string]$body.text } }
    return $null
  }
  $req = [Net.HttpWebRequest]::Create($script:CONF.server + $path)
  $req.Method = $method; $req.Timeout = $timeoutSec * 1000; $req.ReadWriteTimeout = $timeoutSec * 1000
  $req.Headers.Add('X-Bridge-Key', $script:CONF.key); $req.UserAgent = 'ktiv-bridge/' + $VERSION
  if ($null -ne $body) {
    if ($body -is [byte[]]) { $bytes = $body; $req.ContentType = 'application/octet-stream' }
    else { $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10 -Compress)); $req.ContentType = 'application/json; charset=utf-8' }
    $req.ContentLength = $bytes.Length
    $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
  }
  try { $resp = $req.GetResponse() } catch {
    $ex = $_.Exception; while ($ex.InnerException -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
    $r = $null; if ($ex -is [Net.WebException]) { $r = $ex.Response }
    if ($r) { $code = [int]$r.StatusCode; $txt = (New-Object IO.StreamReader($r.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd(); throw ('HTTP ' + $code + ' ' + $txt) }
    throw
  }
  $txt = (New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd(); $resp.Close()
  if ($txt) { return ($txt | ConvertFrom-Json) } else { return $null }
}

# ---------------------------------------------------------------- זיהוי התוכנות
function Find-Responsa {
  $p = Get-Process RESPONSA -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($p) { return $p.Path }
  foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $base) { continue }
    $d = Get-ChildItem -LiteralPath $base -Directory -Filter 'ResponsaCD*' -ErrorAction SilentlyContinue | Sort-Object { [int](($_.Name -replace '\D', '') + '0') } -Descending | Select-Object -First 1
    if ($d -and (Test-Path (Join-Path $d.FullName 'RESPONSA.exe'))) { return (Join-Path $d.FullName 'RESPONSA.exe') }
  }
  return $null
}
function Find-Otzar {
  foreach ($c in @('C:\OtzarApp\OtzarLocal\launcher\bin\x64\app\otzar.exe', 'D:\OtzarApp\OtzarLocal\launcher\bin\x64\app\otzar.exe')) { if (Test-Path $c) { return $c } }
  $p = Get-Process otzar -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($p) { return $p.Path }
  return $null
}
function Otzar-Procs {
  # תהליכי otzar.exe שאינם שלנו (שלנו מסומן בתיקיית הפרופיל הזמנית), ולכל אחד: האם יש לו חלון גלוי
  $mine = $script:OZ.tmp; $out = @()
  foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='otzar.exe'" -ErrorAction SilentlyContinue)) {
    if ($mine -and $p.CommandLine -and $p.CommandLine.Contains($mine)) { continue }
    $win = $false; try { $win = ((Get-Process -Id $p.ProcessId -ErrorAction Stop).MainWindowHandle -ne [IntPtr]::Zero) } catch {}
    $kind = ''; if ($p.CommandLine -match '--type=(\S+)') { $kind = $matches[1] }
    $old = [bool]($p.CommandLine -and $p.CommandLine -match 'ktiv-otzar-')   # עותק נסתר שלנו שנשאר מהפעלה קודמת
    $out += @{ pid = [int]$p.ProcessId; window = $win; type = $kind; orphan = $old }
  }
  return $out
}
function Editor-OtzarRunning {
  # אוצר החכמה פתוח אצל העורך = יש לו חלון. תהליך בלי חלון (שנשאר ברקע) לא נחשב פתוח (בדיקה 19: תהליך אחד בלי חלון
  # נחשב פתוח, ואוצר החכמה דולג). אם התהליך הזה בכל זאת חוסם את העותק שלנו, Oz-Ensure מדווח על כך.
  return [bool](@(Otzar-Procs | Where-Object { $_.window }).Count)
}
function Find-Dbs {
  # התקליטור התורני: התיקייה הרגילה, ואחרת הקיצור בשולחן העבודה או בתפריט התחל
  $p = Get-Process TaklitorTorani -ErrorAction SilentlyContinue | Where-Object { $_.Path } | Select-Object -First 1
  if ($p) { return $p.Path }
  foreach ($c in @('C:\DBS\TaklitorTorani.exe', 'D:\DBS\TaklitorTorani.exe')) { if (Test-Path -LiteralPath $c) { return $c } }
  if ($script:DBS_EXE -and (Test-Path -LiteralPath $script:DBS_EXE)) { return $script:DBS_EXE }
  if ($script:DBS_SCAN -and ((Get-Date) - $script:DBS_SCAN).TotalMinutes -lt 10) { return $null }   # חיפוש הקיצורים: פעם בעשר דקות
  $script:DBS_SCAN = Get-Date
  $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'), [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms'))
  $sh = New-Object -ComObject WScript.Shell
  foreach ($d in $dirs) {
    if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
    foreach ($l in @(Get-ChildItem -LiteralPath $d -Filter *.lnk -Recurse -Depth 2 -ErrorAction SilentlyContinue)) {
      $t = ''; try { $t = $sh.CreateShortcut($l.FullName).TargetPath } catch {}
      if ($t -match '(?i)TaklitorTorani\.exe$' -and (Test-Path -LiteralPath $t)) { $script:DBS_EXE = $t; return $t }
    }
  }
  return $null
}
function Editor-DbsRunning { return [bool](@(Get-Process TaklitorTorani -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne [KB]::DPid }).Count) }
function Caps {
  $r = Find-Responsa; $o = Find-Otzar; $d = Find-Dbs
  $drives = @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | ForEach-Object { @{ id = $_.DeviceID; label = $_.VolumeName; type = [int]$_.DriveType } })
  $rv = $null; if ($r) { $rv = (Get-Item $r).Directory.Name }
  return @{
    responsa = @{ installed = [bool]$r; version = $rv; disk = [bool]($drives | Where-Object { $_.label -match 'RESPONSA' }) }
    otzar = @{ installed = [bool]$o; disk = [bool]($drives | Where-Object { $_.label -match 'Otzar' }); editor_open = (Editor-OtzarRunning); background = @(Otzar-Procs | Where-Object { -not $_.window -and -not $_.orphan -and -not $_.type }).Count; orphans = @(Otzar-Procs | Where-Object { $_.orphan }).Count; procs = @(Otzar-Procs | ForEach-Object { [string]$_.pid + ':' + $(if ($_.type) { $_.type } else { 'main' }) + $(if ($_.window) { ':window' } else { '' }) + $(if ($_.orphan) { ':ours' } else { '' }) }) -join ' '; session = [bool]$script:OZ.pid }
    dbs = @{ installed = [bool]$d; editor_open = (Editor-DbsRunning); session = [bool][KB]::DPid }
    os = [Environment]::OSVersion.VersionString
  }
}

# ---------------------------------------------------------------- בר אילן
$script:RS = @{ last = [datetime]::MinValue }

function Parse-Responsa([string]$raw) {
  $o = @{ title = ''; msg = ''; text = '' }
  if ($raw.StartsWith([string][char]1 + 'ERR' + [char]1)) { throw ('בר אילן: ' + $raw.Substring(5)) }
  $parts = $raw -split [string][char]1
  for ($i = 1; $i -lt $parts.Count - 1; $i += 2) { $o[$parts[$i].ToLower()] = $parts[$i + 1] }
  $count = $null
  if ($o.title -match 'נמצאו\s+([\d,]+)\s+תוצאות') { $count = [int]($matches[1] -replace ',', '') }
  elseif ($o.msg -match 'לא נמצאו' -or $o.msg -match 'שגיאה') { $count = 0 }
  elseif ($o.msg.Trim(' |') -and -not $o.text) { $count = 0 }
  $hits = @(); $cur = $null
  foreach ($line in ($o.text -split "`r?`n")) {
    if ($line -match '^\s*(\d+)\.\s+(.+?)\s*$') {
      if ($cur) { $hits += $cur }
      $cur = @{ n = [int]$matches[1]; title = $matches[2].Trim(); ref = ''; text = '' }
    } elseif ($cur) { $cur.text = ($cur.text + ' ' + $line.Trim()).Trim() }
  }
  if ($cur) { $hits += $cur }
  return @{ count = $count; hits = $hits; title = $o.title; message = $o.msg.Trim(' |') }
}

function Responsa-Search($q, $maxHits, $more = $true) {
  $exe = Find-Responsa
  if (-not $exe) { return @{ state = 'unavailable'; message = 'בר אילן לא מותקן במחשב' } }
  $e = [KB]::ResponsaEnsure($exe)
  if ($e -ne 'ok') { [KB]::ResponsaClose(); return @{ state = 'error'; message = 'בר אילן לא נפתח: ' + $e } }
  $script:RS.last = Get-Date
  $p = Parse-Responsa ([KB]::ResponsaSearch($q, 60))
  $hits = @($p.hits)
  $pages = 0
  while ($more -and $hits.Count -lt $maxHits -and $p.count -and $hits.Count -lt $p.count -and $pages -lt 8) {
    $pages++
    $m = Parse-Responsa ([KB]::ResponsaMore(1))
    $new = @($m.hits | Where-Object { $n = $_.n; -not ($hits | Where-Object { $_.n -eq $n }) })
    if (-not $new.Count) { break }
    $hits += $new
  }
  $script:RS.last = Get-Date
  return @{ state = 'ok'; count = $p.count; message = $p.message; hits = @($hits | Select-Object -First $maxHits) }
}

# ---------------------------------------------------------------- התקליטור התורני
$script:DS = @{ last = [datetime]::MinValue }

function Dbs-Boxes([string]$q) {
  # "10: +סמוכה (+לחברתה/+לחבירתה)" -> מרחק ותיבות (תיבה לכל מילה, חלופות בסוגריים). עד 8 תיבות ו-4 מילים בתיבה.
  $dist = 0; $q = $q.Trim()
  if ($q -match '^(\d+)\s*:\s*(.*)$') { $dist = [int]$matches[1]; $q = $matches[2] }
  $boxes = @()
  foreach ($m in [regex]::Matches($q, '\(([^)]*)\)|(\S+)')) {
    if ($m.Groups[1].Success) { $ws = @($m.Groups[1].Value -split '/' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 4) }
    else { $ws = @($m.Groups[2].Value) }
    if ($ws.Count) { $boxes += ($ws -join '/') }
  }
  return @{ dist = $dist; boxes = @($boxes | Select-Object -First 8) }
}

function Parse-Dbs([string]$raw) {
  # הטקסט שהתוכנה מעתיקה: "(3) רש"י על ברכות דף מו/א" בשורה, ואחריה הקטע; המילים שנמצאו מסומנות *כך*
  $o = @{ title = ''; msg = ''; text = ''; q = '' }
  if ($raw.StartsWith([string][char]1 + 'ERR' + [char]1)) { throw ('התקליטור התורני: ' + $raw.Substring(5)) }
  $parts = $raw -split [string][char]1
  for ($i = 1; $i -lt $parts.Count - 1; $i += 2) { $o[$parts[$i].ToLower()] = $parts[$i + 1] }
  $count = $null
  if ($o.title -match '-\s*([\d,]+)\s+תוצאות') { $count = [int]($matches[1] -replace ',', '') }
  elseif ($o.msg -match 'לא נמצאו') { $count = 0 }
  $hits = @(); $cur = $null
  foreach ($line in ($o.text -split "`r?`n")) {
    if ($line -match '^\s*\((\d+)(?:-\d+)?\)\s+(.+?)\s*$') {
      if ($cur) { $hits += $cur }
      $cur = @{ n = [int]$matches[1]; title = $matches[2].Trim(); ref = ''; text = '' }
    } elseif ($cur -and $line.Trim()) { $cur.text = ($cur.text + ' ' + $line.Trim()).Trim() }
  }
  if ($cur) { $hits += $cur }
  return @{ count = $count; hits = $hits; title = $o.title.Trim(); message = $o.msg.Trim(' |'); typed = $o.q }
}

function Dbs-Search($q, $maxHits) {
  $exe = Find-Dbs
  if (-not $exe) { return @{ state = 'unavailable'; message = 'התקליטור התורני לא מותקן במחשב' } }
  $e = [KB]::DbsEnsure($exe)
  if ($e -ne 'ok') {
    [KB]::DbsClose()
    if (Editor-DbsRunning) { return @{ state = 'busy'; message = 'התקליטור התורני פתוח אצלכם, ולכן לא חיפשנו בו. סגרו אותו כדי שהמערכת תחפש גם בו.' } }
    return @{ state = 'error'; message = 'התקליטור התורני לא נפתח: ' + $e }
  }
  if ([KB]::DBooksTitle -notmatch 'כמה ספרים|כל הספרים') {
    # בלי בחירת כל הספרים החיפוש רץ רק על "מדור הספרים שלי" (בדיקה 25): לא מחפשים, ומדווחים
    $why = [KB]::DBooksTitle; L ('התקליטור התורני: בחירת הספרים לא הצליחה – ' + $why); [KB]::DbsClose()
    return @{ state = 'error'; message = 'התקליטור התורני: בחירת כל הספרים לא הצליחה (' + $why + ')' }
  }
  $script:DS.last = Get-Date
  $b = Dbs-Boxes $q
  if (-not $b.boxes.Count) { return @{ state = 'ok'; count = 0; hits = @(); message = 'ניסוח ריק' } }
  # חלופות: כל צירוף הוא חיפוש נפרד (עד 6), והתוצאות מאוחדות. התיבות החילופיות של התוכנה ו-"+" לא עבדו (בדיקה 25).
  $combos = @(, @())
  foreach ($box in $b.boxes) {
    $ws = @($box -split '/' | ForEach-Object { $_.Trim().TrimStart('+') } | Where-Object { $_ })
    $next = @()
    foreach ($c in $combos) { foreach ($w in $ws) { if ($next.Count -lt 6) { $next += , (@($c) + $w) } } }
    $combos = $next
  }
  $hits = @(); $count = $null; $msgs = @(); $typed = @(); $seen = @{}
  foreach ($c in $combos) {
    $p = Parse-Dbs ([KB]::DbsSearch([string[]]$c, [int]$b.dist, [int]$maxHits, 90))
    $script:DS.last = Get-Date
    $typed += $p.typed
    if ($p.message -eq 'timeout') { $msgs += 'התקליטור התורני לא סיים לחפש תוך דקה וחצי'; continue }
    if ($p.message) { $msgs += $p.message }
    if ($null -ne $p.count) { $count = [int]$count + $p.count }
    foreach ($h in $p.hits) { $k = $h.title + '|' + $h.text; if (-not $seen[$k]) { $seen[$k] = 1; $hits += $h } }
  }
  $msg = (@($msgs | Select-Object -Unique) -join ' | ')
  if ($null -eq $count -and -not $hits.Count -and $msgs.Count -and @($msgs | Where-Object { $_ -match 'לא סיים' }).Count -eq $msgs.Count) { return @{ state = 'error'; message = $msg } }
  return @{ state = 'ok'; count = $count; message = $msg; typed = ($typed -join ' ; '); hits = @($hits | Select-Object -First $maxHits) }
}

function Dbs-Vars($vars, $maxHits) {
  $r = $null
  foreach ($v in @($vars)) {
    $r = Dbs-Search $v $maxHits
    if ($r.state -ne 'ok') { return $r }
    $r.used = $v
    if ($r.count -gt 0 -or @($r.hits).Count -gt 0) { break }
  }
  return $r
}

# ---------------------------------------------------------------- אוצר החכמה
$script:OZ = @{ pid = 0; port = 0; tmp = $null; desk = [IntPtr]::Zero; cdp = $null; target = $null; last = [datetime]::MinValue; books = @() }

function Oz-Close {
  if ($script:OZ.cdp) { try { $script:OZ.cdp.Dispose() } catch {} }
  $tmp = $script:OZ.tmp
  if ($tmp) {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tmp) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
  }
  if ($script:OZ.desk -ne [IntPtr]::Zero) { Start-Sleep -Milliseconds 800; [void][KB]::CloseDesk($script:OZ.desk) }
  if ($tmp) { for ($i = 0; $i -lt 5 -and (Test-Path $tmp); $i++) { try { Remove-Item -LiteralPath $tmp -Recurse -Force } catch { Start-Sleep -Seconds 1 } } }
  $script:OZ = @{ pid = 0; port = 0; tmp = $null; desk = [IntPtr]::Zero; cdp = $null; target = $null; last = [datetime]::MinValue; books = @() }
}

function Oz-Targets {
  try { $arr = (New-Object Net.WebClient).DownloadString('http://127.0.0.1:' + $script:OZ.port + '/json/list') | ConvertFrom-Json } catch { return @() }
  return @(@($arr) | ForEach-Object { $_ } | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })
}

function Oz-Main {
  return (Oz-Targets | Where-Object { $_.url -match 'dist/index.html' -and $_.url -notmatch 'tabs_toolbar' } | Select-Object -First 1)
}

function Oz-Ensure {
  if ($script:OZ.pid -and [KB]::Alive($script:OZ.pid) -and $script:OZ.cdp -and $script:OZ.cdp.Open) { return 'ok' }
  Oz-Close
  $exe = Find-Otzar
  if (-not $exe) { return 'אוצר החכמה לא מותקן במחשב' }
  $tmp = Join-Path $env:TEMP ('ktiv-otzar-' + (Get-Random))
  if (Test-Path 'C:\OtzarApp\otzar') { $null = robocopy 'C:\OtzarApp\otzar' $tmp /E /R:0 /W:0 /NFL /NDL /NJH /NJS /NP /XD Cache 'Code Cache' GPUCache DawnCache ShaderCache Crashpad }
  else { New-Item -ItemType Directory -Force -Path $tmp | Out-Null }
  $port = Get-Random -Minimum 9340 -Maximum 9399
  $desk = [KB]::NewDesk('ktivbridge_o')
  $script:OZ.tmp = $tmp; $script:OZ.port = $port; $script:OZ.desk = $desk
  $script:OZ.pid = [KB]::Launch($exe, ('--remote-debugging-port=' + $port + ' --disable-gpu --user-data-dir="' + $tmp + '"'), (Split-Path -Parent $exe), 'ktivbridge_o')
  if ($script:OZ.pid -le 0) { Oz-Close; return 'אוצר החכמה לא נפתח' }
  for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 1
    if (-not [KB]::Alive($script:OZ.pid)) { Oz-Close; return 'אוצר החכמה נסגר בעצמו (אולי נפתח אצלכם בינתיים, או שתהליך שלו נשאר פתוח ברקע)' }
    $t = Oz-Main
    if ($i -gt 6 -and $t -and $t.url -notmatch '#/loading' -and $t.url -match '#/') { break }
  }
  $t = Oz-Main
  if (-not $t) { Oz-Close; return 'אוצר החכמה לא סיים להיטען' }
  $script:OZ.target = $t
  $script:OZ.cdp = [KB+Cdp]::new($t.webSocketDebuggerUrl)
  [void]$script:OZ.cdp.Send('Emulation.setFocusEmulationEnabled', '{"enabled":true}', 5000)
  # חלון גבוה, כדי שעמוד שלם ייכנס לצילום
  [void]$script:OZ.cdp.Send('Emulation.setDeviceMetricsOverride', '{"width":1280,"height":1700,"deviceScaleFactor":1.5,"mobile":false}', 5000)
  Start-Sleep -Seconds 3
  $script:OZ.last = Get-Date
  return 'ok'
}

function Oz-Eval([string]$expr, [int]$timeoutMs = 30000) {
  $r = $script:OZ.cdp.Send('Runtime.evaluate', ('{"expression":' + [KB]::J($expr) + ',"returnByValue":true,"awaitPromise":true}'), $timeoutMs) | ConvertFrom-Json
  if ($r.result.exceptionDetails) { throw ('JS: ' + $r.result.exceptionDetails.text + ' ' + $r.result.exceptionDetails.exception.description) }
  return $r.result.result.value
}
function Oz-Send([string]$method, [string]$p, [int]$timeoutMs = 15000) { return $script:OZ.cdp.Send($method, $p, $timeoutMs) }

function Oz-Upload([byte[]]$bytes) {
  if ($Local) {   # התוסף קורא את התמונה מהקובץ
    $f = Join-Path $script:IMG_DIR ([Guid]::NewGuid().ToString('N') + '.png'); [IO.File]::WriteAllBytes($f, $bytes); return $f
  }
  return (Api 'POST' '/bridge-api/image' $bytes 120).id
}

function Oz-Shot($rect, [double]$scale = 1.5) {
  $clip = '{"x":' + [Math]::Max(0, [double]$rect.x) + ',"y":' + [Math]::Max(0, [double]$rect.y) + ',"width":' + [double]$rect.w + ',"height":' + [double]$rect.h + ',"scale":' + $scale + '}'
  $resp = Oz-Send 'Page.captureScreenshot' ('{"format":"png","clip":' + $clip + '}') 30000
  if ($resp -match '"data":"([^"]+)"') { return [Convert]::FromBase64String($matches[1]) }
  throw 'צילום נכשל'
}

$JS_PAGE = @'
(() => { const m = /#\/b\/(\d+)\/p\/(-?\d+)/.exec(location.href);
 const cv = [...document.querySelectorAll('canvas.img-canvas')].map(c => { const r = c.getBoundingClientRect(); return {x: r.x, y: r.y, w: r.width, h: r.height}; })
   .filter(r => r.w > 100 && r.y + r.h > 0 && r.y < innerHeight).sort((a, b) => Math.abs(a.y) - Math.abs(b.y))[0] || null;
 const dots = [...document.querySelectorAll('.search-fs-results .dot .text')].map(x => parseInt(x.innerText, 10)).filter(x => !isNaN(x));
 const ins = [...document.querySelectorAll('input[type=text]')].filter(i => { const r = i.getBoundingClientRect(); return r.width > 0 && r.width < 120 && r.y < 160 && !i.placeholder; }).map(i => i.value);
 const t = (document.body.innerText.match(/מתוך\s+([\d,]+)/) || [])[1];
 return JSON.stringify({href: location.href, book: m ? +m[1] : null, p: m ? +m[2] : null, canvas: cv, hits: dots, inputs: ins, total: t ? +t.replace(/,/g, '') : null, vh: innerHeight}); })()
'@

function Oz-PageState { return ((Oz-Eval $JS_PAGE) | ConvertFrom-Json) }

function Oz-WaitRender($beforeHref, [int]$sec = 20) {
  for ($i = 0; $i -lt $sec * 2; $i++) {
    Start-Sleep -Milliseconds 500
    $s = Oz-PageState
    if ($s.canvas -and ($s.href -ne $beforeHref -or $i -gt 3)) { Start-Sleep -Milliseconds 1200; return (Oz-PageState) }
  }
  return (Oz-PageState)
}

function Oz-PageResult($title, $author, $withImage = $true) {
  $s = Oz-PageState
  $res = @{ book_id = $s.book; p = $s.p; title = $title; author = $author; hits = @($s.hits); inputs = @($s.inputs); total = $s.total }
  if ($withImage -and $s.canvas) {
    $h = [Math]::Min([double]$s.canvas.h, [double]$s.vh - [Math]::Max(0, [double]$s.canvas.y))
    $res.image = Oz-Upload (Oz-Shot @{ x = $s.canvas.x; y = $s.canvas.y; w = $s.canvas.w; h = $h } 1.5)
    $res.canvas = $s.canvas
  }
  return $res
}

$JS_SEARCH_HOOK = @'
(() => { const s = window._store; if (!s) return '0'; if (!window.__ktsub) { window.__ktseq = 0; window.__ktT = 0; window.__ktF = 0;
 window.__ktsub = s.subscribe(m => { if (m.type === 'freeSearch/SET_SEARCHING') { if (m.payload) window.__ktT = ++window.__ktseq; else window.__ktF = ++window.__ktseq; } }); }
 return String(window.__ktseq); })()
'@
$JS_SEARCH_STATE = @'
(() => { const st = window._store && window._store.state.freeSearch; const area = document.querySelector('.free-search-area');
 const desc = (document.querySelector('.results-description') || {}).innerText || '';
 const lines = area ? area.innerText.split('\n').map(s => s.trim()).filter(Boolean) : [];
 const books = [];
 for (let i = 2; i < lines.length; i++) { const m = /^\[([\d,]+)\]$/.exec(lines[i]); if (m) books.push({title: lines[i - 2], author: lines[i - 1], n: +m[1].replace(/,/g, '')}); }
 return JSON.stringify({searching: st ? st.searching : null, str: st ? st.searchStr : '', desc: desc.replace(/\s+/g, ' ').trim(), href: location.href, books: books, t: window.__ktT || 0, f: window.__ktF || 0}); })()
'@

function Oz-Search($q, $maxBooks) {
  $before = Oz-Eval 'location.href'
  $box = Oz-Eval @'
(() => { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const e = [...document.querySelectorAll('input[id^="fs_input"]')].find(vis) || [...document.querySelectorAll('input')].find(x => vis(x) && /בתוכן הספרים/.test(x.placeholder || ''));
 if (!e) return 'none'; e.focus(); e.select(); return 'ok'; })()
'@
  if ($box -ne 'ok') { throw 'תיבת החיפוש של אוצר החכמה לא נמצאה' }
  $seq0 = [int](Oz-Eval $JS_SEARCH_HOOK)
  [void](Oz-Send 'Input.insertText' ('{"text":' + [KB]::J($q) + '}'))
  [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"rawKeyDown","key":"Enter","code":"Enter","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13}')
  [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"char","key":"Enter","text":"\r","unmodifiedText":"\r","windowsVirtualKeyCode":13}')
  [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"keyUp","key":"Enter","code":"Enter","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13}')
  $st = $null; $saw = $false
  for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    $st = (Oz-Eval $JS_SEARCH_STATE) | ConvertFrom-Json
    if ($st.searching) { $saw = $true }
    # החיפוש התחיל והסתיים: לפי שינויי המצב של התוכנה (בדיקה 16: הדגל searching מתחלף מהר מדי בשביל דגימה כל שנייה,
    # ותיאור "0 תוצאות" זהה לחיפוש הקודם)
    if ($st.t -gt $seq0 -and $st.f -gt $st.t) { $saw = $true; if ($st.desc) { break } }
    if ($st.href -ne $before -and -not $st.searching -and $st.desc) { if ($i -gt 2) { break } }
    if ($saw -and -not $st.searching -and $st.desc -and $i -gt 1) { break }
    if ($st.href -ne $before -and -not $st.searching -and $i -gt 8) { break }
  }
  Start-Sleep -Milliseconds 1500
  $st = (Oz-Eval $JS_SEARCH_STATE) | ConvertFrom-Json
  $count = $null; $nb = $null
  if ($st.desc -match '([\d,]+)\s+תוצאות') { $count = [int]($matches[1] -replace ',', '') } elseif ($st.href -ne $before -or $saw) { $count = 0 }
  if ($st.desc -match '/\s*([\d,]+)\s+ספרים') { $nb = [int]($matches[1] -replace ',', '') }
  $books = @(); $k = 0
  foreach ($b in @($st.books | Select-Object -First $maxBooks)) { $books += @{ idx = $k; title = $b.title; author = $b.author; n = $b.n }; $k++ }
  $script:OZ.books = $books
  return @{ count = $count; books_total = $nb; books = $books; desc = $st.desc }
}

function Oz-OpenBook($idx) {
  $b = $script:OZ.books | Where-Object { $_.idx -eq [int]$idx } | Select-Object -First 1
  if (-not $b) { throw 'הספר לא נמצא ברשימת התוצאות (חפשו שוב)' }
  $before = Oz-Eval 'location.href'
  $r = Oz-Eval ('((t) => { const area = document.querySelector(".free-search-area"); if (!area) return "noarea"; const el = [...area.querySelectorAll("*")].find(e => e.children.length === 0 && (e.innerText || "").trim() === t); if (!el) return "notfound"; el.scrollIntoView({block: "center"}); el.click(); return "ok"; })(' + [KB]::J($b.title) + ')')
  if ($r -ne 'ok') { throw ('פתיחת הספר נכשלה: ' + $r) }
  [void](Oz-WaitRender $before 25)
  return (Oz-PageResult $b.title $b.author)
}

$JS_OCR_TEXT = @'
(() => { const a = document.querySelector('.ocr-text-area'); const st = window._store.state.bookPopups;
 return JSON.stringify({visible: st.OCRResultsVisible, text: a ? ((a.value !== undefined && a.value) || a.innerText || '') : ''}); })()
'@
$JS_OCR_CLOSE = @'
(() => { const a = document.querySelector('.ocr-text-area'); let n = 0;
 if (a) { let w = a.closest('[class*=win],[class*=popup],[class*=dialog],[class*=modal]') || a.parentElement;
   for (let i = 0; i < 6 && w; i++) { const x = [...w.querySelectorAll('*')].find(e => e.children.length === 0 && /^[×✕xX]$/.test((e.innerText || '').trim())); if (x) { x.click(); n++; break; } w = w.parentElement; } }
 try { window._store.dispatch('bookPopups/setOCREnable', false); } catch (e) {}
 return n; })()
'@

function Oz-Region($params) {
  $s = Oz-PageState
  if (-not $s.canvas) { throw 'אין עמוד מוצג' }
  $cv = $s.canvas
  $fx = [double]$params.x; $fy = [double]$params.y; $fw = [double]$params.w; $fh = [double]$params.h
  if ($fw -le 0 -or $fh -le 0) { $fx = 0; $fy = 0; $fw = 1; $fh = 1 }
  $x1 = [double]$cv.x + $fx * [double]$cv.w; $y1 = [double]$cv.y + $fy * [double]$cv.h
  $x2 = $x1 + $fw * [double]$cv.w; $y2 = $y1 + $fh * [double]$cv.h
  $y1 = [Math]::Max($y1, 2); $y2 = [Math]::Min($y2, [double]$s.vh - 2)
  $res = @{ book_id = $s.book; p = $s.p }
  $want = [string]$params.want
  if ($want -eq 'image' -or $want -eq 'both') {
    $res.image = Oz-Upload (Oz-Shot @{ x = $x1; y = $y1; w = ($x2 - $x1); h = ($y2 - $y1) } 2)
  }
  if ($want -eq 'text' -or $want -eq 'both') {
    $old = ((Oz-Eval $JS_OCR_TEXT) | ConvertFrom-Json).text
    [void](Oz-Eval "(() => { window._store.dispatch('bookPopups/setOCREnable', true); return 1; })()")
    Start-Sleep -Milliseconds 600
    $ax = [int]$x2 - 3; $ay = [int]$y1 + 3; $bx = [int]$x1 + 3; $by = [int]$y2 - 3
    [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseMoved","x":' + $ax + ',"y":' + $ay + '}'))
    [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mousePressed","x":' + $ax + ',"y":' + $ay + ',"button":"left","buttons":1,"clickCount":1}'))
    for ($k = 1; $k -le 10; $k++) {
      $xx = [int]($ax + ($bx - $ax) * $k / 10); $yy = [int]($ay + ($by - $ay) * $k / 10)
      [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseMoved","x":' + $xx + ',"y":' + $yy + ',"button":"left","buttons":1}'))
    }
    [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseReleased","x":' + $bx + ',"y":' + $by + ',"button":"left","buttons":0,"clickCount":1}'))
    $txt = ''
    for ($i = 0; $i -lt 30; $i++) {
      Start-Sleep -Milliseconds 700
      $o = (Oz-Eval $JS_OCR_TEXT) | ConvertFrom-Json
      if ($o.text -and $o.text.Trim() -and $o.text -ne $old) { Start-Sleep -Milliseconds 800; $txt = ((Oz-Eval $JS_OCR_TEXT) | ConvertFrom-Json).text; break }
    }
    [void](Oz-Eval $JS_OCR_CLOSE)
    $res.text = ($txt -replace '\s+', ' ').Trim()
    if (-not $res.text) { $res.text_error = 'ה-OCR של אוצר החכמה לא החזיר טקסט' }
  }
  return $res
}

$script:CLOSED_EDITOR = $false
function Otzar-Auto($vars, $params, [int]$start = 0) {
  # vars: ניסוחים מהמדויק (תחביר אוצר החכמה) לפשוט. מתחילים מ-start ועוברים לבא כשאין תוצאות (הרחבת החיפוש לפי ההדרכה)
  # עותק נסתר שלנו שנשאר מהפעלה קודמת: סוגרים
  foreach ($x in @(Otzar-Procs | Where-Object { $_.orphan })) { L ('אוצר החכמה: סוגר עותק נסתר שנשאר, ' + $x.pid); Stop-Process -Id $x.pid -Force -ErrorAction SilentlyContinue }
  # אוצר החכמה שנשאר פתוח ברקע בלי חלון (בדיקה 19: תהליך אחד כזה סגר את העותק שלנו – רק עותק אחד יכול לרוץ).
  # העורך לא עובד בו (אין חלון), ולכן סוגרים אותו תמיד, בלי קשר להגדרה (החלטת אסתר, 09.11.2026)
  $bg = @(Otzar-Procs | Where-Object { -not $_.window -and -not $_.orphan -and -not $_.type })
  if ($bg.Count -and -not (Editor-OtzarRunning)) {
    L ('אוצר החכמה פתוח ברקע בלי חלון: סוגרים אותו (' + (($bg | ForEach-Object { $_.pid }) -join ',') + ')')
    foreach ($x in $bg) { Stop-Process -Id $x.pid -Force -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt 10 -and @(Otzar-Procs | Where-Object { -not $_.window }).Count; $i++) { Start-Sleep -Seconds 1 }
  }
  if (Editor-OtzarRunning) {
    if ($params.otzar_busy -eq 'close' -and -not $script:CLOSED_EDITOR) {
      L 'אוצר החכמה פתוח אצל העורך; לפי ההגדרה סוגרים אותו לרגע כדי לחפש'
      Get-Process otzar -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { [void]$_.CloseMainWindow() }
      for ($i = 0; $i -lt 30 -and (Editor-OtzarRunning); $i++) { Start-Sleep -Seconds 1 }
      $script:CLOSED_EDITOR = $true
    }
    if (Editor-OtzarRunning) {
      $msg = 'אוצר החכמה היה פתוח במחשב, ולכן לא חיפשנו בו (אפשר לשנות בהגדרות הגשר).'
      if ($params.otzar_busy -eq 'tab') { $msg = 'אוצר החכמה היה פתוח במחשב. חיפוש בלשונית רקע עוד לא זמין, ולכן לא חיפשנו בו.' }
      return @{ state = 'busy'; message = $msg }
    }
  }
  if (-not (Find-Otzar)) { return @{ state = 'unavailable'; message = 'אוצר החכמה לא מותקן במחשב' } }
  $e = Oz-Ensure
  if ($e -ne 'ok') { return @{ state = 'error'; message = $e } }
  $vars = @($vars); if ($start -ge $vars.Count) { $start = $vars.Count - 1 }; if ($start -lt 0) { $start = 0 }
  $r = $null; $used = ''; $vi = -1
  for ($j = $start; $j -lt $vars.Count; $j++) {
    try { $r = Oz-Search ([string]$vars[$j]) 10 } catch { L ('אוצר החכמה, ניסוח [' + $vars[$j] + ']: ' + $_); $r = $null; continue }
    $used = [string]$vars[$j]; $vi = $j
    if ($r.count -gt 0) { break }
  }
  if (-not $r) { return @{ state = 'error'; message = 'החיפוש באוצר החכמה נכשל' } }
  $out = @{ state = 'ok'; count = $r.count; books_total = $r.books_total; books = @($r.books | Select-Object -First 5); pages = @(); used = $used; vi = $vi }
  $mode = [string]$params.otzar_result
  $k = [int]$params.auto_books
  if ($mode -eq 'image' -and $k -lt 1) { $k = 1 }
  if ($mode -eq 'ref') { $k = 0 }
  for ($i = 0; $i -lt $k -and $i -lt $r.books.Count; $i++) {
    try {
      $pg = Oz-OpenBook $i
      $label = ''; if (@($pg.inputs).Count) { $label = @($pg.inputs)[0] }
      $one = @{ idx = $i; book_id = $pg.book_id; title = $r.books[$i].title; author = $r.books[$i].author; page = $pg.p; page_label = $label }
      if ($mode -eq 'text') { $reg = Oz-Region @{ x = 0; y = 0; w = 1; h = 1; want = 'text' }; $one.text = $reg.text }
      else { $one.image = $pg.image }
      $out.pages += $one
    } catch { L ('אוצר החכמה, ספר ' + $i + ': ' + $_) }
  }
  $script:OZ.last = Get-Date
  return $out
}

function Q-Key($q) { if ($q -is [string]) { return $q }; return [string]$q.key }
function Q-Vars($q, [string]$prog) {
  # ניסוח פשוט (מחרוזת) או מובנה: {key, otzar: [מדויק..פשוט], responsa: [...], dbs: [...]}
  if ($q -is [string]) { return @($q) }
  $v = @(@($q.$prog) | Where-Object { $_ } | ForEach-Object { [string]$_ })
  if (-not $v.Count) { $v = @([string]$q.key) }
  return $v
}

function Responsa-Vars($vars, $maxHits) {
  $r = $null
  foreach ($v in @($vars)) {
    $r = Responsa-Search $v $maxHits $false
    if ($r.state -ne 'ok') { return $r }
    $r.used = $v
    if ($r.count -gt 0 -or @($r.hits).Count -gt 0) { break }
  }
  return $r
}

function Run-Batch($job) {
  $p = $job.params
  $results = @{}; $note = ''; $skip = $null; $rskip = $null; $dskip = $null; $ozStart = 0; $control = @{}
  $qs = @($p.queries); $n = 0
  $script:CLOSED_EDITOR = $false
  # בדיקת ביקורת (ההדרכה): חיפוש של דבר שבוודאות קיים. אם הניסוח המדויק לא מוצא אותו, ההגדרות קשוחות מדי:
  # בכל המשימה מתחילים מהניסוח הפשוט שכן מצא.
  if ($p.control) {
    try { [void](Api 'POST' ('/bridge-api/progress/' + $job.id) @{ text = 'בדיקת ביקורת' } 20) } catch {}
    if ($p.programs.otzar) {
      $cp = @{ otzar_busy = $p.otzar_busy; otzar_result = 'ref'; auto_books = 0 }
      try { $c = Otzar-Auto (Q-Vars $p.control 'otzar') $cp 0 } catch { $c = @{ state = 'error'; message = [string]$_ } }
      $control.otzar = @{ state = $c.state; count = $c.count; used = $c.used; vi = $c.vi }
      if ($c.state -eq 'ok' -and $c.count -gt 0 -and $c.vi -gt 0) { $ozStart = [int]$c.vi; L ('בדיקת ביקורת: הניסוח המדויק לא מצא; מתחילים מניסוח ' + $ozStart) }
      if ($c.state -eq 'busy' -or $c.state -eq 'unavailable') { $skip = $c; $note = $c.message }
    }
    if ($p.programs.responsa) {
      try { $c = Responsa-Vars (Q-Vars $p.control 'responsa') 1 } catch { $c = @{ state = 'error'; message = [string]$_ } }
      $control.responsa = @{ state = $c.state; count = $c.count; used = $c.used }
      if ($c.state -ne 'ok') { $rskip = $c; if (-not $note) { $note = $c.message } }
    }
    if ($p.programs.dbs) {
      try { $c = Dbs-Vars (Q-Vars $p.control 'dbs') 1 } catch { $c = @{ state = 'error'; message = [string]$_ } }
      $control.dbs = @{ state = $c.state; count = $c.count; used = $c.used }
      if ($c.state -ne 'ok') { $dskip = $c; if (-not $note) { $note = $c.message } }
    }
  }
  foreach ($q in $qs) {
    $n++
    $key = Q-Key $q
    try { [void](Api 'POST' ('/bridge-api/progress/' + $job.id) @{ text = ('ניסוח ' + $n + ' מתוך ' + $qs.Count + ': ' + $key) } 20) } catch {}
    $one = @{}
    if ($p.programs.responsa) {
      if ($rskip) { $one.responsa = $rskip }
      else {
        try { $one.responsa = Responsa-Vars (Q-Vars $q 'responsa') ([int]$p.max_hits) } catch { $one.responsa = @{ state = 'error'; message = [string]$_ } }
        if ($one.responsa.state -ne 'ok') { $rskip = $one.responsa; if (-not $note) { $note = $one.responsa.message } }
      }
    }
    if ($p.programs.dbs) {
      if ($dskip) { $one.dbs = $dskip }
      else {
        try { $one.dbs = Dbs-Vars (Q-Vars $q 'dbs') ([int]$p.max_hits) } catch { $one.dbs = @{ state = 'error'; message = [string]$_ } }
        if ($one.dbs.state -ne 'ok') { $dskip = $one.dbs; if (-not $note) { $note = $one.dbs.message } }
      }
    }
    if ($p.programs.otzar) {
      if ($skip) { $one.otzar = $skip }
      else {
        try { $one.otzar = Otzar-Auto (Q-Vars $q 'otzar') $p $ozStart } catch { $one.otzar = @{ state = 'error'; message = [string]$_ } }
        if ($one.otzar.state -eq 'busy' -or $one.otzar.state -eq 'unavailable') { $skip = $one.otzar; $note = $one.otzar.message }
      }
    }
    $results[$key] = $one
  }
  return @{ results = $results; note = $note; control = $control }
}

# ---------------------------------------------------------------- משימות
function Run-Job($job) {
  switch ($job.kind) {
    'batch' { return (Run-Batch $job) }
    'close' { Oz-Close; [KB]::ResponsaClose(); [KB]::DbsClose(); return @{ ok = $true } }
    'selftest' { return @{ version = $VERSION; caps = (Caps) } }
    default { throw ('סוג משימה לא מוכר: ' + $job.kind) }
  }
}

function Housekeeping {
  # אוצר החכמה של העורך נפתח בזמן שהעותק שלנו פתוח: סוגרים את שלנו מיד, כדי שהוא לא ייחסם
  if ($script:OZ.pid) {
    if (Editor-OtzarRunning) { L 'אוצר החכמה נפתח אצל העורך: סוגר את העותק הנסתר'; Oz-Close }
    elseif (((Get-Date) - $script:OZ.last).TotalSeconds -gt 300) { L 'אוצר החכמה: סגירה אחרי 5 דקות בלי שימוש'; Oz-Close }
    elseif (-not [KB]::Alive($script:OZ.pid)) { Oz-Close }
  }
  if ([KB]::RPid -and ((Get-Date) - $script:RS.last).TotalSeconds -gt 300) { L 'בר אילן: סגירה אחרי 5 דקות בלי שימוש'; [KB]::ResponsaClose() }
  if ([KB]::DPid -and ((Get-Date) - $script:DS.last).TotalSeconds -gt 300) { L 'התקליטור התורני: סגירה אחרי 5 דקות בלי שימוש'; [KB]::DbsClose() }
}

function Clean-Old {
  Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'ktiv-otzar-*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Recurse -Force } catch {} }
}

function Self-Update($want) {
  if (-not $want -or $want -eq $VERSION) { return }
  try {
    $req = [Net.HttpWebRequest]::Create($script:CONF.server + '/bridge-api/script'); $req.Headers.Add('X-Bridge-Key', $script:CONF.key)
    $resp = $req.GetResponse(); $txt = (New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd(); $resp.Close()
    if ($txt -notmatch '\$VERSION = ') { return }
    [IO.File]::WriteAllText($SELF, $txt, (New-Object Text.UTF8Encoding($true)))
    L ('עודכן לגרסה ' + $want + '; מפעיל מחדש')
    Oz-Close; [KB]::ResponsaClose(); [KB]::DbsClose()
    Start-Process wscript.exe -ArgumentList ('"' + $VBS + '"')
    exit
  } catch { L ('עדכון נכשל: ' + $_) }
}

# ---------------------------------------------------------------- התקנה / הסרה
function Write-Vbs {
  $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $SELF + '"" -Run'
  $v = 'CreateObject("WScript.Shell").Run "' + $cmd + '", 0, False'
  [IO.File]::WriteAllText($VBS, $v, [Text.Encoding]::Unicode)
  Copy-Item -Force $VBS $STARTUP_VBS
}
function Stop-Others {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains('ktiv-bridge.ps1') -and $_.CommandLine.Contains('-Run') } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
}
function Show-Msg([string]$text, [int]$icon = 64) {
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show($text, 'גשר הספריות של כתיב מלא', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]$icon, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, ([System.Windows.Forms.MessageBoxOptions]::RtlReading -bor [System.Windows.Forms.MessageBoxOptions]::RightAlign))
}

function Out-Local($obj) {
  [Console]::Out.WriteLine('@@KB@@' + ($obj | ConvertTo-Json -Depth 12 -Compress)); [Console]::Out.Flush()
}

if ($Local) {
  # מצב התוסף: משימה בכל שורה בקלט {id, kind, params}; תשובה {id, result} או {id, error}. קלט שנסגר = יציאה.
  $ProgressPreference = 'SilentlyContinue'
  [Console]::InputEncoding = New-Object Text.UTF8Encoding($false)
  [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
  $script:IMG_DIR = $(if ($ImgDir) { $ImgDir } else { Join-Path $env:TEMP 'otzar-barilan-claude' })
  New-Item -ItemType Directory -Force -Path $script:IMG_DIR | Out-Null
  L ('התוסף עלה, גרסה ' + $VERSION); Clean-Old
  Out-Local @{ ready = $true; version = $VERSION }
  $in = [Console]::In
  while ($true) {
    $t = $in.ReadLineAsync()
    while (-not $t.Wait(4000)) { try { Housekeeping } catch {} }
    $line = $t.Result
    if ($null -eq $line) { break }
    if (-not $line.Trim()) { continue }
    $job = $null
    try { $job = $line | ConvertFrom-Json } catch { Out-Local @{ error = 'שורה לא תקינה' }; continue }
    try {
      $res = Run-Job $job
      Out-Local @{ id = $job.id; result = $res }
    } catch {
      L ('שגיאה: ' + $_ + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
      Out-Local @{ id = $job.id; error = [string]$_ }
    }
  }
  try { Oz-Close } catch {}; try { [KB]::ResponsaClose() } catch {}; try { [KB]::DbsClose() } catch {}
  L 'התוסף נסגר'
  exit
}

if ($Uninstall) {
  Stop-Others; Remove-Item -Force -ErrorAction SilentlyContinue $STARTUP_VBS
  Show-Msg 'הגשר הוסר. הוא לא יעלה יותר עם המחשב.'
  exit
}

if ($Install) {
  if (-not $Server -or -not $Key) { Show-Msg 'חסרים כתובת שרת או מפתח. הורידו את קובץ ההתקנה מחדש מתוך כתיב מלא.' 16; exit 1 }
  $script:CONF = [pscustomobject]@{ server = $Server.TrimEnd('/'); key = $Key }
  ($script:CONF | ConvertTo-Json) | Set-Content -Encoding UTF8 $CONF_FILE
  try {
    $h = Api 'POST' '/bridge-api/hello' @{ version = $VERSION; caps = (Caps); status = @{ state = 'installing' } } 30
  } catch { Show-Msg ('ההתקנה לא הצליחה להתחבר לשרת:' + "`n" + $_ + "`n`n" + 'בדקו את החיבור לאינטרנט ונסו שוב.') 16; exit 1 }
  Write-Vbs; Stop-Others; Clean-Old
  Start-Process wscript.exe -ArgumentList ('"' + $VBS + '"')
  $c = Caps
  $found = @(); if ($c.responsa.installed) { $found += 'בר אילן' }; if ($c.otzar.installed) { $found += 'אוצר החכמה' }; if ($c.dbs.installed) { $found += 'התקליטור התורני' }
  $msg = 'הגשר הותקן ופועל. הוא יעלה לבד בכל הפעלה של המחשב.' + "`n`n"
  if ($found.Count) { $msg += 'נמצאו במחשב: ' + ($found -join ', ') + '.' } else { $msg += 'שימו לב: לא נמצאו במחשב בר אילן, אוצר החכמה או התקליטור התורני.' }
  $msg += "`n`n" + 'מעכשיו, כשמערכת כתיב מלא מחפשת מקורות, היא תחפש גם בתוכנות האלה.'
  Show-Msg $msg
  exit
}

if ($Run) {
  $mtx = New-Object Threading.Mutex($false, 'Local\KtivBridgeRun')
  $got = $false
  try { $got = $mtx.WaitOne(20000) } catch [Threading.AbandonedMutexException] { $got = $true }
  if (-not $got) { exit }
  $script:CONF = Read-Conf
  if (-not $script:CONF) { L 'אין config.json'; exit 1 }
  L ('הגשר עלה, גרסה ' + $VERSION)
  Clean-Old
  $nextHello = [datetime]::MinValue; $fails = 0
  while ($true) {
    try {
      if ((Get-Date) -ge $nextHello) {
        $h = Api 'POST' '/bridge-api/hello' @{ version = $VERSION; caps = (Caps); status = @{ state = 'running' } } 30
        $nextHello = (Get-Date).AddSeconds(60)
        Self-Update $h.script_version
      }
      $active = ($script:OZ.pid -or [KB]::RPid -or [KB]::DPid)
      $w = 25; if ($active) { $w = 4 }
      $r = Api 'GET' ('/bridge-api/poll?wait=' + $w) $null ($w + 30)
      $fails = 0
      if ($r.job) {
        $job = $r.job; $t0 = Get-Date
        L ('משימה ' + $job.kind + ' ' + $job.id)
        try {
          $res = Run-Job $job
          [void](Api 'POST' ('/bridge-api/result/' + $job.id) @{ result = $res } 120)
          L ('  הסתיימה תוך ' + [int]((Get-Date) - $t0).TotalSeconds + ' שניות')
        } catch {
          L ('  שגיאה: ' + $_ + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
          try { [void](Api 'POST' ('/bridge-api/result/' + $job.id) @{ error = [string]$_ } 60) } catch {}
        }
      }
      Housekeeping
    } catch {
      $fails++
      L ('שגיאת חיבור: ' + $_)
      if ([string]$_ -match 'HTTP 401') { Start-Sleep -Seconds 300 } else { Start-Sleep -Seconds ([Math]::Min(60, 5 * $fails)) }
      try { Housekeeping } catch {}
    }
  }
}
