# ===== גשר הספריות של כתיב מלא =====
# רץ במחשב העורך, מוסתר, ועולה עם הכניסה ל-Windows. כשמערכת כתיב מלא מחפשת מקורות, היא שולחת לכאן
# את ניסוחי החיפוש; הגשר מחפש באוצר החכמה ובבר אילן על שולחן עבודה נסתר שהעורך לא רואה, ומחזיר את התוצאות.
# אינו מתקין דבר, אינו משנה את ההגדרות של התוכנות, ואינו נוגע במסך, בעכבר או במקלדת של העורך.
# קבצים: %LOCALAPPDATA%\KtivBridge\ (ktiv-bridge.ps1, config.json, bridge.log, run.vbs)
# -Local: מצב התוסף לאפליקציית קלוד (ktiv/bridge/desktop). בלי שרת: משימות מגיעות בשורות JSON בקלט,
#         ותשובות יוצאות בשורות שמתחילות ב-@@KB@@. תמונות נשמרות בתיקייה ImgDir. יומן: %LOCALAPPDATA%\OtzarBarilanClaude
param([switch]$Install, [switch]$Run, [switch]$Uninstall, [string]$Server = '', [string]$Key = '', [switch]$Local, [string]$ImgDir = '')
$VERSION = '2026.11.26.1'
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

# התוצאה נשלחת דחוסה: מסנן אינטרנט במחשב (אתרוג) עצר לפעמים טקסט תורני בדרך והחזיר דף משלו (16.11).
# שרת ישן בלי הנתיב החדש – שליחה רגילה כמו קודם.
function Send-Result([string]$id, $obj) {
  $json = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 10 -Compress))
  $ms = New-Object IO.MemoryStream
  $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress)
  $gz.Write($json, 0, $json.Length); $gz.Close()
  try { [void](Api 'POST' ('/bridge-api/result-gz/' + $id) ($ms.ToArray()) 120) }
  catch { if ([string]$_ -like 'HTTP 405*' -or [string]$_ -like 'HTTP 404 {"detail":"Not Found"}*') { [void](Api 'POST' ('/bridge-api/result/' + $id) $obj 120) } else { throw } }
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
    $cl = [string]$p.CommandLine
    $kind = ''; if ($cl -match '--type=(\S+)') { $kind = $matches[1] }
    # (24.11) עותק נסתר של גשר: "שנשאר" רק אם הגשר שפתח אותו כבר לא רץ. קודם כל עותק שלא שלנו נסגר – ובמחשב עם כמה גשרים
    # (התוסף בכמה חלונות של קלוד, וגשר כתיב מלא) כל גשר סגר לאחר את אוצר החכמה באמצע חיפוש ("Send ... errors occurred").
    $br = $cl -match 'ktiv-otzar-'; $owner = 0; $port = 0
    if ($cl -match 'ktiv-otzar-(\d+)-') { $owner = [int]$matches[1] }
    if ($cl -match '--remote-debugging-port=(\d+)') { $port = [int]$matches[1] }
    $old = $false
    if ($br) {
      if ($owner) { $old = ($owner -eq $PID) -or -not [KB]::Alive($owner) }
      else { try { $old = ((Get-Date) - $p.CreationDate).TotalMinutes -gt 30 } catch { $old = $true } }   # גשר בגרסה קודמת (בלי מספר תהליך בשם)
    }
    $out += @{ pid = [int]$p.ProcessId; window = ($win -and -not $br); type = $kind; orphan = $old; bridge = $br; owner = $owner; port = $port }
  }
  return $out
}
function Editor-OtzarRunning {
  # אוצר החכמה פתוח אצל העורך = יש לו חלון. תהליך בלי חלון (שנשאר ברקע) לא נחשב פתוח (בדיקה 19: תהליך אחד בלי חלון
  # נחשב פתוח, ואוצר החכמה דולג). אם התהליך הזה בכל זאת חוסם את העותק שלנו, Oz-Ensure מדווח על כך.
  return [bool](@(Otzar-Procs | Where-Object { $_.window -and -not $_.bridge }).Count)
}

# (24.11) כמה גשרים באותו מחשב: עובדים באוצר החכמה אחד בכל פעם (נעילה משותפת), ומשתפים עותק נסתר אחד
$script:OZMTX = $null; $script:OZHELD = 0
$OZ_LAST_FILE = Join-Path $env:TEMP 'ktiv-otzar-last.txt'
function Oz-Lock([int]$ms) {
  if (-not $script:OZMTX) { $script:OZMTX = New-Object Threading.Mutex($false, 'Local\KtivBridgeOtzar') }
  $got = $false
  try { $got = $script:OZMTX.WaitOne($ms) } catch [Threading.AbandonedMutexException] { $got = $true }
  if ($got) { $script:OZHELD++ }
  return $got
}
function Oz-Unlock { if ($script:OZHELD -gt 0) { $script:OZHELD--; try { $script:OZMTX.ReleaseMutex() } catch {} } }
function Oz-Touch { $script:OZ.last = Get-Date; try { [IO.File]::WriteAllText($OZ_LAST_FILE, [string](Get-Date).Ticks) } catch {} }
function Oz-LastShared {
  $t = $script:OZ.last
  try { $x = [datetime][long]([IO.File]::ReadAllText($OZ_LAST_FILE).Trim()); if ($x -gt $t) { $t = $x } } catch {}
  return $t
}
function Oz-Shared {
  # עותק נסתר חי של גשר אחר במחשב: התהליך הראשי (בלי --type), שהגשר שפתח אותו עדיין רץ
  return (Otzar-Procs | Where-Object { $_.bridge -and -not $_.orphan -and -not $_.type -and $_.port -and $_.owner -ne $PID } | Select-Object -First 1)
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
  # מספר התוצאות לא תמיד נקרא מהכותרת (בדיקה 19): ממשיכים לדפדף עד שאין תוצאות חדשות
  while ($more -and $hits.Count -lt $maxHits -and $hits.Count -and ($null -eq $p.count -or $hits.Count -lt $p.count) -and $pages -lt 12) {
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
  $script:OZ = @{ pid = 0; port = 0; tmp = $null; desk = [IntPtr]::Zero; cdp = $null; target = $null; last = [datetime]::MinValue; books = @(); owned = $false }
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
  # (24.11) גשר אחר במחשב כבר מחזיק עותק נסתר פתוח – מתחברים אליו (חוסך פתיחה, ושני עותקים לא כותבים לאותה תיקייה)
  $sh = Oz-Shared
  if ($sh) {
    try {
      $script:OZ.pid = $sh.pid; $script:OZ.port = $sh.port; $script:OZ.owned = $false
      $t = Oz-Main
      if ($t) {
        $script:OZ.target = $t; $script:OZ.cdp = [KB+Cdp]::new($t.webSocketDebuggerUrl)
        [void]$script:OZ.cdp.Send('Emulation.setFocusEmulationEnabled', '{"enabled":true}', 5000)
        [void]$script:OZ.cdp.Send('Emulation.setDeviceMetricsOverride', '{"width":1280,"height":1700,"deviceScaleFactor":1.5,"mobile":false}', 5000)
        Oz-Touch; L ('אוצר החכמה: מתחבר לעותק הנסתר של גשר אחר במחשב (' + $sh.owner + ')'); return 'ok'
      }
    } catch { L ('אוצר החכמה: החיבור לעותק של גשר אחר נכשל: ' + $_) }
    Oz-Close
  }
  $exe = Find-Otzar
  if (-not $exe) { return 'אוצר החכמה לא מותקן במחשב' }
  $t0open = Get-Date
  $tmp = Join-Path $env:TEMP ('ktiv-otzar-' + $PID + '-' + (Get-Random))
  $script:OZ.owned = $true
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
  Oz-Touch
  L ('אוצר החכמה: עותק נסתר נפתח תוך ' + [int]((Get-Date) - $t0open).TotalSeconds + ' שנ''')
  return 'ok'
}

# (23.11) האתר הפסיק לחשוף window._store (עדכון באתר, 23.11 בצהריים) – מוצאים את המאגר דרך האפליקציה עצמה, לפני כל קריאה
$JS_STORE_SHIM = @'
(() => { try { if (window._store) return; const isS = o => { try { return !!(o && typeof o === 'object' && o.state && typeof o.commit === 'function' && typeof o.dispatch === 'function'); } catch (x) { return false; } };
 for (const k of Object.keys(window)) { let o; try { o = window[k]; } catch (x) { continue; } if (isS(o)) { window._store = o; return; } if (o && typeof o === 'object') { try { for (const k2 of Object.keys(o).slice(0, 50)) if (isS(o[k2])) { window._store = o[k2]; return; } } catch (x) {} } }
 const r = document.querySelector('#app'); const rv = r && r.__vue__;
 if (rv) { const c = [rv, rv.$root, rv.$root && rv.$root.$children && rv.$root.$children[0]]; for (const v of c) { if (!v) continue; for (const s of [v.$store, v.$options && v.$options.store, v._store]) if (isS(s)) { window._store = s; return; } } }
 const cand = [document.querySelector('#app'), ...[...document.querySelectorAll('body *')].slice(0, 400)];
 for (const e of cand) { if (!e) continue; const v = e.__vue__; if (v && v.$store) { window._store = v.$store; return; }
   const a = e.__vue_app__; if (a) { const s = (a.config && a.config.globalProperties && a.config.globalProperties.$store) || (a._context && a._context.provides && a._context.provides.store); if (s) { window._store = s; return; } } } } catch (x) {} })();
'@

function Oz-Eval([string]$expr, [int]$timeoutMs = 30000) {
  $expr = $JS_STORE_SHIM + "`n" + $expr
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
 const ins = [...document.querySelectorAll('input[type=text]')].filter(i => { const r = i.getBoundingClientRect(); return r.width > 0 && r.width < 120 && r.y < (window._store ? 160 : 320) && !i.placeholder; }).map(i => i.value);
 const t = (document.body.innerText.match(/מתוך\s+([\d,]+)/) || [])[1];
 let book = m ? +m[1] : null, p = m ? +m[2] : null, letter = '';
 // באתר המקוון הכתובת נשארת עם עמוד -1: העמוד והעמוד המודפס נמצאים במצב התוכנה (בדיקה 26)
 try { const tabs = Object.values((window._store && window._store.state.tabs) || {}).filter(x => x && x.book);
   const tb = tabs.find(x => x.book === book) || tabs[tabs.length - 1];
   if (tb) { if (!book) book = tb.book; if (!(p > 0) && tb.page > 0) p = tb.page;
     const pg = (tb.pages || []).find(x => x.position === p); letter = (pg && pg.pagedata && pg.pagedata[0] && pg.pagedata[0].letter) || ''; } } catch (e) {}
 if (!(p > 0)) { const num = ins.find(v => /^\d+$/.test(String(v).trim())); if (num) p = +num; }
 if (!(p > 0) || !letter) {   // (23.11) לפי הסימנים שבמסך: "281 מתוך 494" ו"עמוד: רלו"
   const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
   const near = (re) => { const el = [...document.querySelectorAll('body *')].find(e => vis(e) && e.children.length === 0 && re.test((e.innerText || '').trim()));
     for (let e = el, k = 0; e && k < 4; e = e.parentElement, k++) { const i = [...e.querySelectorAll('input')].filter(vis); if (i.length) return i; } return []; };
   if (!(p > 0)) { const v = near(/^מתוך\s*[\d,]*$/).map(i => String(i.value).trim()).find(v => /^\d+$/.test(v)); if (v) p = +v; }
   if (!letter) { const v = near(/^עמוד:?$/).map(i => String(i.value).trim()).find(v => v && !/^\d+$/.test(v)); if (v) letter = v; } }   // (23.11) בלי המאגר: תיבת מספר העמוד ("33 מתוך 476")
 if (!letter) { const l = ins.find(v => /^[א-ת"'׳״]{1,6}\.?$/.test(String(v).trim())); if (l) letter = l; }
 return JSON.stringify({href: location.href, book: book, p: p, letter: letter, canvas: cv, hits: dots, inputs: ins, total: t ? +t.replace(/,/g, '') : null, vh: innerHeight}); })()
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
  $res = @{ book_id = $s.book; p = $s.p; letter = [string]$s.letter; title = $title; author = $author; hits = @($s.hits); inputs = @($s.inputs); total = $s.total }
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
 const nb = e => ((e.textContent || '').match(/\[[\d,]+\]/g) || []).length;   // textContent – גם שורות שהאתר לא מצייר כרגע (מחוץ לתצוגה)
 const items = area ? [...area.querySelectorAll('.item-book')] : [];   // (24.11) מבנה חדש: שורה = .item-book, המספר בתג .fs-hit-badge (בלי סוגריים)
 const rowEls = items.length ? items : area ? [...area.querySelectorAll('*')].filter(e => nb(e) === 1 && (!e.parentElement || nb(e.parentElement) > 1)) : [];
 const books = items.length ? ((items) => items.map(e => { const t = q => ((e.querySelector(q) || {}).textContent || '').trim(); const m = /freebook_(\d+)/.exec(e.id || '');
   return {title: t('.name-book'), author: t('.name-author'), n: +(t('.fs-hit-badge .num').replace(/,/g, '') || 1), i: m ? +m[1] : null, book_id: +(e.getAttribute('book') || 0) || null}; }).sort((a, b) => (a.i ?? 0) - (b.i ?? 0)))(items) : rowEls.map(e => { const m = /\[([\d,]+)\]/.exec(e.textContent || '');
   const ls = [...e.querySelectorAll('*')].filter(x => x.children.length === 0).map(x => (x.textContent || '').replace(/\[[\d,]+\]/, '').trim()).filter(Boolean);
   return {title: ls[0] || '', author: ls[1] || '', n: +m[1].replace(/,/g, '')}; });
 return JSON.stringify({searching: st ? st.searching : null, str: st ? st.searchStr : '', desc: desc.replace(/\s+/g, ' ').trim(), href: location.href, books: books, t: window.__ktT || 0, f: window.__ktF || 0}); })()
'@

# (23.11) כל רשימת הספרים. לפי צילום מסך של אסתר: אין כפתורי עמודים – חלונית התוצאות (למעלה) נגללת ונטענת בהמשך,
# ומתחתיה חלונית "רשימה מלאה – כל הספרים" (שבה תגי מספר כמו "2" – לא עמוד). לכן: רק שורות שמעל החלונית התחתונה,
# וגלילה של חלונית התוצאות לסוף (השורה האחרונה לתצוגה + כל מיכל נגלל שמכיל אותה), עד שלא נוספים ספרים.
$JS_BOOKS_PAGE = @'
((mode) => { const area = document.querySelector('.free-search-area'); if (!area) return JSON.stringify({books: [], sig: '', clicked: false});
 const lines = area.innerText.split('\n').map(s => s.trim()).filter(Boolean);
 // (23.11) שורה = האלמנט הגדול ביותר שיש בו בדיוק מספר אחד בסוגריים ("[3]") – גם כשהמספר באותה שורה עם המחבר או עם תג (עוז והדר וכד')
 const nb = e => ((e.textContent || '').match(/\[[\d,]+\]/g) || []).length;   // textContent – גם שורות שהאתר לא מצייר כרגע (מחוץ לתצוגה)
 const items = [...area.querySelectorAll('.item-book')];   // (24.11) מבנה חדש – ראו JS_SEARCH_STATE
 const rowEls = items.length ? items.slice().sort((a, b) => (+((/freebook_(\d+)/.exec(a.id) || [])[1] || 0)) - (+((/freebook_(\d+)/.exec(b.id) || [])[1] || 0)))
   : [...area.querySelectorAll('*')].filter(e => nb(e) === 1 && (!e.parentElement || nb(e.parentElement) > 1));
 const books = items.length ? ((items) => items.map(e => { const t = q => ((e.querySelector(q) || {}).textContent || '').trim(); const m = /freebook_(\d+)/.exec(e.id || '');
   return {title: t('.name-book'), author: t('.name-author'), n: +(t('.fs-hit-badge .num').replace(/,/g, '') || 1), i: m ? +m[1] : null, book_id: +(e.getAttribute('book') || 0) || null}; }).sort((a, b) => (a.i ?? 0) - (b.i ?? 0)))(rowEls) : rowEls.map(e => { const m = /\[([\d,]+)\]/.exec(e.textContent || '');
   const ls = [...e.querySelectorAll('*')].filter(x => x.children.length === 0).map(x => (x.textContent || '').replace(/\[[\d,]+\]/, '').trim()).filter(Boolean);
   return {title: ls[0] || '', author: ls[1] || '', n: +m[1].replace(/,/g, '')}; });
 const all = [...area.querySelectorAll('*')]; const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const rows = rowEls;
 const last = rows[rows.length - 1]; const sc = [];
 if (last) for (let e = last.parentElement; e && e !== document.body; e = e.parentElement) { if (e.scrollHeight > e.clientHeight + 5 && /(auto|scroll)/.test(getComputedStyle(e).overflowY)) sc.push(e); }
 let clicked = false;
 let atEnd = null;
 if (mode === -1) { for (const e of sc) e.scrollTop = 0; }
 else if (mode === -2) { const e = sc[0]; if (e) { const b = e.scrollTop; const rh = last ? last.getBoundingClientRect().height || 30 : 30; e.scrollTop = b + Math.max(40, Math.floor(rh * 8)); e.dispatchEvent(new Event('scroll')); atEnd = e.scrollTop <= b + 1; } else atEnd = true; }
 else if (mode) {
   if (last) { last.scrollIntoView({block: 'end'}); for (const e of sc) { e.scrollTop = e.scrollHeight; e.dispatchEvent(new Event('scroll')); } }
   // מספר העמוד הבא – אחרי השורה האחרונה ברשימת התוצאות (באבחון: "... [2] / 2 / <שורת הסיכום>")
   const c = all.filter(e => vis(e) && (e.innerText || '').trim() === String(mode) && ![...e.children].some(x => (x.innerText || '').trim() === String(mode))
     && (!last || (last.compareDocumentPosition(e) & Node.DOCUMENT_POSITION_FOLLOWING)));
   const el = c[0]; if (el) { (el.closest('button, a, li, [role=button]') || el).click(); clicked = true; } }
 const sig = books.length + '|' + (books[0] ? books[0].title : '') + '|' + (books.length ? books[books.length - 1].title : '');
 return JSON.stringify({books: books, sig: sig, clicked: clicked, atEnd: atEnd, rows: rows.length, sc: sc.length, tail: lines.slice(-6).join(' / ').slice(0, 300)}); })
'@

$script:OzListDiag = $null
function Oz-AllBooks($total) {
  $map = [ordered]@{}; $t0 = Get-Date; $log = @(); $pg = 2; $steps = 0
  $cur = (Oz-Eval ($JS_BOOKS_PAGE + '(0)')) | ConvertFrom-Json; $first = $cur
  while (((Get-Date) - $t0).TotalSeconds -lt 110) {
    $before = $map.Count
    foreach ($b in @($cur.books)) {   # עמוד שמתחלף או רשימה שמתארכת – אותה שורה יכולה לחזור: המספר הגדול, לא סכום
      $k = [string]$b.title + '|' + [string]$b.author
      if ($map.Contains($k)) { if ([int]$b.n -gt [int]$map[$k].n) { $map[$k].n = [int]$b.n } } else { $map[$k] = @{ title = $b.title; author = $b.author; n = [int]$b.n; i = $b.i; book_id = $b.book_id } }
    }
    if ($map.Count -ne $before -or -not $steps) { $log += ('+' + ($map.Count - $before)) }
    if ($total -and $map.Count -ge $total) { break }
    $moved = $false
    # (23.11) הרשימה "וירטואלית": האתר מחזיק בדף רק את השורות שליד מקום הגלילה. גוללים בצעדים (כ-8 שורות; ב-30 דולגו ספרים) ואוספים בכל צעד
    $st = (Oz-Eval ($JS_BOOKS_PAGE + '(-2)')) | ConvertFrom-Json
    if (-not $st.atEnd) {
      for ($w = 0; $w -lt 4; $w++) { Start-Sleep -Milliseconds 300; $nx = (Oz-Eval ($JS_BOOKS_PAGE + '(0)')) | ConvertFrom-Json; if ($nx.sig -ne $cur.sig) { break } }
      $moved = $true; $steps++
    }
    if ($moved) { $cur = $nx; continue }
    $r = (Oz-Eval ($JS_BOOKS_PAGE + '(' + $pg + ')')) | ConvertFrom-Json
    for ($w = 0; $w -lt 20; $w++) {                    # עד 14 שניות שהרשימה תשתנה (עמוד חדש או המשך שנטען)
      Start-Sleep -Milliseconds 700
      $nx = (Oz-Eval ($JS_BOOKS_PAGE + '(0)')) | ConvertFrom-Json
      if ($nx.sig -ne $cur.sig) { $moved = $true; break }
    }
    if (-not $moved) { $log += ('עמוד ' + $pg + ': ' + $(if ($r.clicked) { 'נלחץ ולא השתנה' } else { 'אין' })); break }
    Start-Sleep -Milliseconds 800
    $cur = (Oz-Eval ($JS_BOOKS_PAGE + '(0)')) | ConvertFrom-Json
    if ($r.clicked) { $pg++ }
  }
  if ($pg -gt 2) { [void](Oz-Eval ($JS_BOOKS_PAGE + '(1)')); Start-Sleep -Milliseconds 1500 }   # חזרה לעמוד הראשון – Oz-OpenBook מחפש את הספר ברשימה המוצגת
  [void](Oz-Eval ($JS_BOOKS_PAGE + '(-1)'))
  $script:OzListDiag = @{ steps = $steps; log = ($log -join ','); rows = $first.rows; sc = $first.sc; tail = $cur.tail }
  $books = @(); $k = 0
  $vals = @($map.Values); if (@($vals | Where-Object { $null -ne $_.i }).Count -eq $vals.Count) { $vals = @($vals | Sort-Object { [int]$_.i }) }   # (24.11) סדר האתר (רלוונטיות)
  foreach ($v in $vals) { $one = @{ idx = $k; title = $v.title; author = $v.author; n = $v.n }; if ($v.book_id) { $one.book_id = $v.book_id }; $books += $one; $k++ }
  return $books
}

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
  foreach ($b in @($st.books | Select-Object -First $maxBooks)) { $one = @{ idx = $k; title = $b.title; author = $b.author; n = $b.n }; if ($b.book_id) { $one.book_id = $b.book_id }; $books += $one; $k++ }
  $script:OZ.books = $books; $script:OZ.lastq = $q
  return @{ count = $count; books_total = $nb; books = $books; desc = $st.desc }
}

function Oz-OpenBook($idx) {
  $b = $script:OZ.books | Where-Object { $_.idx -eq [int]$idx } | Select-Object -First 1
  if (-not $b) { throw 'הספר לא נמצא ברשימת התוצאות (חפשו שוב)' }
  $before = Oz-Eval 'location.href'
  $js = '((t, a) => { const area = document.querySelector(".free-search-area"); if (!area) return "noarea"; const leaves = [...area.querySelectorAll("*")].filter(e => e.children.length === 0 && (e.textContent || "").trim() === t); let el = leaves[0]; if (a && leaves.length > 1) { const w = leaves.find(e => { let r = e; for (let k = 0; k < 4 && r; k++, r = r.parentElement) if ((r.textContent || "").includes(a)) return true; return false; }); if (w) el = w; } if (!el) return "notfound"; el.scrollIntoView({block: "center"}); el.click(); return "ok"; })(' + [KB]::J($b.title) + ',' + [KB]::J([string]$b.author) + ')'
  $r = Oz-Eval $js
  if ($r -eq 'notfound') {   # (23.11) הרשימה וירטואלית: השורה לא מצוירת – גוללים מההתחלה בצעדים עד שהיא מופיעה
    [void](Oz-Eval ($JS_BOOKS_PAGE + '(-1)')); Start-Sleep -Milliseconds 600
    for ($k = 0; $k -lt 80 -and $r -eq 'notfound'; $k++) {
      $r = Oz-Eval $js; if ($r -ne 'notfound') { break }
      $st = (Oz-Eval ($JS_BOOKS_PAGE + '(-2)')) | ConvertFrom-Json; Start-Sleep -Milliseconds 450
      if ($st.atEnd) { $r = Oz-Eval $js; break }
    }
  }
  if ($r -ne 'ok') { throw ('פתיחת הספר נכשלה: ' + $r + ' (' + $b.title + ')') }
  [void](Oz-WaitRender $before 25)
  return (Oz-PageResult $b.title $b.author)
}

$JS_OCR_TEXT = @'
(() => { const a = document.querySelector('.ocr-text-area'); const st = (window._store && window._store.state.bookPopups) || {};
 return JSON.stringify({visible: st.OCRResultsVisible, text: a ? ((a.value !== undefined && a.value) || a.innerText || '') : ''}); })()
'@
$JS_OCR_ON = @'
(() => { if (window._store) { try { window._store.dispatch('bookPopups/setOCREnable', true); return 'store'; } catch (e) {} }
 // (23.11) בלי המאגר הפנימי: הכלי "זיהוי טקסט" בסרגל, כמו שמנויה לוחצת עליו
 const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const lab = e => [e.title, e.getAttribute('aria-label'), e.getAttribute('data-tooltip'), e.getAttribute('tooltip'), (e.innerText || '').trim()].filter(Boolean).join(' ');
 const c = [...document.querySelectorAll('[title], [aria-label], [data-tooltip], button, .toolbar *')].filter(vis);
 const b = c.find(e => /OCR|זיהוי\s*תווים|זיהוי\s*טקסט|העתק(ת)?\s*טקסט|בחירת\s*טקסט|סימון\s*טקסט/i.test(lab(e)));
 if (b) { (b.closest('button, a, [role=button]') || b).click(); return 'btn:' + lab(b).slice(0, 40); }
 const ic = [...document.querySelectorAll('.font-icon-bar')]; const o = ic.find(e => /ocr/i.test(String(e.className)));
 if (o) { (o.closest('.item') || o).click(); return 'icon:' + String(o.className).slice(-30); }
 const sa = ic.find(e => /icon-selectArea/.test(String(e.className)));   // (23.11) בחירת אזור – אחריה האתר מציע מה לעשות באזור (בהם זיהוי טקסט)
 if (sa) { if (!/active/.test(String(sa.className))) (sa.closest('.item') || sa).click(); return 'selectArea'; }
 const icons = ic.map(e => String(e.className).replace('font-icon-bar font-icon center-it ', '') + '@' + ((e.closest('.item') || e).getAttribute('title') || ''));
 const bar = [...document.querySelectorAll('body *')].filter(e => { if (!vis(e)) return false; const r = e.getBoundingClientRect(); return r.x < 70 && r.width < 50 && r.height < 50 && r.width > 14 && !e.closest('svg, img') ; })
   .map(e => { const r = e.getBoundingClientRect(); const im = e.querySelector('img, use'); return Math.round(r.y) + ':' + e.tagName + '.' + String(e.className && e.className.baseVal !== undefined ? e.className.baseVal : e.className).slice(0, 40) + (im ? '[' + (im.getAttribute('src') || im.getAttribute('href') || im.getAttribute('xlink:href') || '').slice(-40) + ']' : ''); });
 return 'none: ' + icons.join(' ; ') + ' || more: ' + [...document.querySelectorAll('.toolbox-more-btn, .toolbox-more-btn *')].map(e => String(e.className)).slice(0, 5).join(' ; '); })()
'@
$JS_OCR_MENU = @'
(() => { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const els = [...document.querySelectorAll('button, a, li, [role=button], [role=menuitem], div, span')].filter(e => vis(e) && e.children.length <= 2);
 const t = e => (e.innerText || e.title || '').trim();
 const b = els.find(e => /^(OCR|זיהוי\s*(תווים|טקסט)|הצג\s*טקסט|טקסט|העתק\s*טקסט|העתקת\s*טקסט)$/i.test(t(e)));
 if (b) { b.click(); return 'clicked:' + t(b); }
 return 'menu:' + [...new Set(els.map(t).filter(x => x && x.length < 25))].slice(-40).join(' | '); })()
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
    $script:OzOcrHow = Oz-Eval $JS_OCR_ON
    Start-Sleep -Milliseconds 600
    $ax = [int]$x2 - 3; $ay = [int]$y1 + 3; $bx = [int]$x1 + 3; $by = [int]$y2 - 3
    [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseMoved","x":' + $ax + ',"y":' + $ay + '}'))
    [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mousePressed","x":' + $ax + ',"y":' + $ay + ',"button":"left","buttons":1,"clickCount":1}'))
    for ($k = 1; $k -le 10; $k++) {
      $xx = [int]($ax + ($bx - $ax) * $k / 10); $yy = [int]($ay + ($by - $ay) * $k / 10)
      [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseMoved","x":' + $xx + ',"y":' + $yy + ',"button":"left","buttons":1}'))
    }
    [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseReleased","x":' + $bx + ',"y":' + $by + ',"button":"left","buttons":0,"clickCount":1}'))
    $txt = ''; $script:OzOcrMenu = ''
    for ($i = 0; $i -lt 18; $i++) {
      Start-Sleep -Milliseconds 700
      if ($script:OzOcrHow -eq 'selectArea' -and $i -in 1, 4) { $script:OzOcrMenu = Oz-Eval $JS_OCR_MENU }
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
  # (24.11) אוצר החכמה – גשר אחד בכל פעם במחשב
  if (-not (Oz-Lock 120000)) { return @{ state = 'busy'; message = 'אוצר החכמה עסוק בחיפוש של גשר אחר במחשב הזה (למשל חלון אחר של קלוד) – נסו שוב בעוד דקה' } }
  $t0 = Get-Date
  try { $r = Otzar-Auto-Inner $vars $params $start }
  finally { Oz-Touch; Oz-Unlock }
  L ('אוצר החכמה: ' + [int]((Get-Date) - $t0).TotalSeconds + ' שנ'' (' + $r.state + $(if ($r.used) { ', ניסוח ' + ($r.vi + 1) } else { '' }) + $(if ($null -ne $r.count) { ', ' + $r.count + ' תוצאות' } else { '' }) + $(if (@($r.pages).Count) { ', ' + @($r.pages).Count + ' עמודים' } else { '' }) + ')')
  return $r
}

function Otzar-Auto-Inner($vars, $params, [int]$start = 0) {
  # vars: ניסוחים מהמדויק (תחביר אוצר החכמה) לפשוט. מתחילים מ-start ועוברים לבא כשאין תוצאות (הרחבת החיפוש לפי ההדרכה)
  # עותק נסתר שלנו שנשאר מהפעלה קודמת: סוגרים
  foreach ($x in @(Otzar-Procs | Where-Object { $_.orphan })) { L ('אוצר החכמה: סוגר עותק נסתר שנשאר, ' + $x.pid); Stop-Process -Id $x.pid -Force -ErrorAction SilentlyContinue }
  # אוצר החכמה שנשאר פתוח ברקע בלי חלון (בדיקה 19: תהליך אחד כזה סגר את העותק שלנו – רק עותק אחד יכול לרוץ).
  # העורך לא עובד בו (אין חלון), ולכן סוגרים אותו תמיד, בלי קשר להגדרה (החלטת אסתר, 09.11.2026)
  $bg = @(Otzar-Procs | Where-Object { -not $_.window -and -not $_.orphan -and -not $_.type -and -not $_.bridge })
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
    try { $r = Oz-Search ([string]$vars[$j]) (List-Max $params 'otzar') } catch { L ('אוצר החכמה, ניסוח [' + $vars[$j] + ']: ' + $_); $r = $null; continue }
    $used = [string]$vars[$j]; $vi = $j
    if ($r.count -gt 0) { break }
  }
  if (-not $r) { return @{ state = 'error'; message = 'החיפוש באוצר החכמה נכשל' } }
  $out = @{ state = 'ok'; count = $r.count; books_total = $r.books_total; books = @($r.books); pages = @(); used = $used; vi = $vi }
  $mode = [string]$params.otzar_result
  $k = [int]$params.auto_books
  if ($mode -eq 'image' -and $k -lt 1) { $k = 1 }
  if ($mode -eq 'ref') { $k = 0 }
  $idx = @(); for ($i = 0; $i -lt [Math]::Min($k, @($r.books).Count); $i++) { $idx += $i }
  if ($idx.Count) { $out.pages = @(Oz-Pages $idx $mode) }
  $script:OZ.last = Get-Date
  return $out
}

# (23.11) האתר מחזיר בבחירת אזור עד כ-1,050 תווים – קוראים את העמוד בארבע רצועות ומחברים
function Oz-PageText {
  $parts = @(); $errs = @()
  foreach ($y in 0, 0.25, 0.5, 0.75) {
    $reg = Oz-Region @{ x = 0; y = $y; w = 1; h = 0.25; want = 'text' }
    if (-not $reg.text) { Start-Sleep -Milliseconds 1200; $reg = Oz-Region @{ x = 0; y = $y; w = 1; h = 0.25; want = 'text' } }
    if ($reg.text) { $parts += $reg.text } elseif ($reg.text_error) { $errs += $reg.text_error }
    if (-not $parts.Count -and $y -eq 0.25) { break }   # (23.11) שתי רצועות ראשונות ריקות – הזיהוי לא עובד בעמוד הזה; לא לתקוע את הגשר לכל השיחות
  }
  $res = @{ text = (($parts -join ' ') -replace '\s+', ' ').Trim() }
  if (-not $res.text -and $errs.Count) { $res.text_error = $errs[0] }
  return $res
}

function Oz-Pages($idxs, [string]$mode) {
  # העמוד שבו נמצא החיפוש, בכל ספר מרשימת התוצאות של החיפוש האחרון (טקסט מזיהוי התווים של אוצר החכמה, או צילום)
  $pages = @()
  foreach ($i in @($idxs)) {
    try {
      $b = $script:OZ.books | Where-Object { $_.idx -eq [int]$i } | Select-Object -First 1
      $pg = Oz-OpenBook $i
      $label = [string]$pg.letter; if (-not $label -and @($pg.inputs).Count) { $label = @($pg.inputs)[0] }
      $one = @{ idx = [int]$i; book_id = $pg.book_id; title = $b.title; author = $b.author; page = $pg.p; page_label = $label }
      if ($mode -eq 'image') { $one.image = $pg.image }
      else {
        # (23.11) התאמה לרוחב (בהתאמה לגובה הזיהוי חזר ריק); העמוד כולו נכנס בזכות חלון גבוה (Ozo-Ensure, 3400) – אחרת חזרו כ-1,000 תווים
        $fit = Oz-Eval '(() => { const e = document.querySelector(".font-icon-bar.icon-fitWidth"); if (!e) return "none"; if (/active/.test(String(e.className))) return "already"; (e.closest(".item") || e).click(); return "clicked"; })()'
        if ($fit -eq 'clicked') { Start-Sleep -Milliseconds 1800 }
        $reg = Oz-PageText   # בדיקה 26: הקריאה הראשונה חזרה ריקה – Oz-PageText מנסה שוב כל רצועה
        $one.text = $reg.text; if ($reg.text_error) { $one.text_error = $reg.text_error }
        if (-not $reg.text) { $one.text_error = ([string]$one.text_error + ' ocr=' + [string]$script:OzOcrHow + ' menu=' + [string]$script:OzOcrMenu).Trim() }   # (23.11) אבחון
      }
      $pages += $one
    } catch { L ('אוצר החכמה, ספר ' + $i + ': ' + $_); $pages += @{ idx = [int]$i; error = [string]$_ } }
  }
  return $pages
}

function Otzar-Books($p) {
  # עמודים מספרים נוספים מתוך רשימת הספרים של חיפוש: אם החיפוש האחרון היה אחר, מחפשים שוב קודם
  $q = [string]$p.query
  if (-not $q) { throw 'חסר הניסוח' }
  if (Editor-OtzarRunning) { return @{ state = 'busy'; message = 'אוצר החכמה היה פתוח במחשב, ולכן לא חיפשנו בו.' } }
  if (-not (Oz-Lock 120000)) { return @{ state = 'busy'; message = 'אוצר החכמה עסוק בחיפוש של גשר אחר במחשב הזה – נסו שוב בעוד דקה' } }
  $t0 = Get-Date
  try {
    $e = Oz-Ensure
    if ($e -ne 'ok') { return @{ state = 'error'; message = $e } }
    if ($script:OZ.lastq -ne $q -or -not $script:OZ.books.Count) { [void](Oz-Search $q 40) }   # עותק משותף: הרשימה אולי של חיפוש אחר
    $idxs = @($p.books | ForEach-Object { [int]$_ } | Select-Object -First 8)
    $out = @{ state = 'ok'; used = $q; pages = @(Oz-Pages $idxs ([string]$p.otzar_result)) }
  } finally { Oz-Touch; Oz-Unlock }
  L ('אוצר החכמה, עמודים מספרים: ' + [int]((Get-Date) - $t0).TotalSeconds + ' שנ'' (' + @($out.pages).Count + ' עמודים)')
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

function List-Max($p, [string]$prog) {
  # כמה מקומות להביא בכל חיפוש (רשימת כל המקומות; התוסף מציג טקסט מלא רק לראשונים). ברירת מחדל: 4 כמו פעם.
  $n = [int]$p.list_max; if ($n -le 0) { $n = [int]$p.max_hits }; if ($n -le 0) { $n = 4 }
  $cap = @{ otzar = 40; responsa = 40; dbs = 300 }[$prog]
  return [Math]::Min($n, $cap)
}

function Responsa-Vars($vars, $maxHits) {
  $r = $null
  foreach ($v in @($vars)) {
    $r = Responsa-Search $v $maxHits ($maxHits -gt 4)
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
    $one = @{}; $tq = @()
    $tp = Get-Date
    if ($p.programs.responsa) {
      if ($rskip) { $one.responsa = $rskip }
      else {
        try { $one.responsa = Responsa-Vars (Q-Vars $q 'responsa') (List-Max $p 'responsa') } catch { $one.responsa = @{ state = 'error'; message = [string]$_ } }
        if ($one.responsa.state -ne 'ok') { $rskip = $one.responsa; if (-not $note) { $note = $one.responsa.message } }
      }
      $tq += ('בר אילן ' + [int]((Get-Date) - $tp).TotalSeconds); $tp = Get-Date
    }
    if ($p.programs.dbs) {
      if ($dskip) { $one.dbs = $dskip }
      else {
        try { $one.dbs = Dbs-Vars (Q-Vars $q 'dbs') (List-Max $p 'dbs') } catch { $one.dbs = @{ state = 'error'; message = [string]$_ } }
        if ($one.dbs.state -ne 'ok') { $dskip = $one.dbs; if (-not $note) { $note = $one.dbs.message } }
      }
      $tq += ('התקליטור ' + [int]((Get-Date) - $tp).TotalSeconds); $tp = Get-Date
    }
    if ($p.programs.otzar) {
      if ($skip) { $one.otzar = $skip }
      else {
        try { $one.otzar = Otzar-Auto (Q-Vars $q 'otzar') $p $ozStart } catch { $one.otzar = @{ state = 'error'; message = [string]$_ } }
        if ($one.otzar.state -eq 'busy' -or $one.otzar.state -eq 'unavailable') { $skip = $one.otzar; $note = $one.otzar.message }
      }
      $tq += ('אוצר החכמה ' + [int]((Get-Date) - $tp).TotalSeconds)
    }
    L ('  ניסוח ' + $n + ' מתוך ' + $qs.Count + ' (שניות): ' + ($tq -join ', '))
    $results[$key] = $one
  }
  return @{ results = $results; note = $note; control = $control }
}

# ---------------------------------------------------------------- משימות
# ---------------------------------------------------------------- אוצר החכמה המקוון (tablet.otzar.org)
# בשביל ההכרעה מול הדפוס בהגהה (השרת: ktiv/sources/otzar_online.py, משימה 'otzar_online'). אסתר 15.11.2026:
# החיבור דרך כרום במחשב שלה, והיא נכנסת למנוי בעצמה – בלי סיסמה בשרת. כרום לא מאפשר שליטה בפרופיל הראשי
# (מגרסה 136 התעלמות מ-remote-debugging-port בפרופיל ברירת המחדל), ולכן פרופיל נפרד של הגשר: הכניסה למנוי
# נשמרת בו, במחשב בלבד. הלשוניות והחלונות של אסתר לא נוגעים.
# החיפוש: אותו קוד של אוצר החכמה שבמחשב (Oz-Search, Oz-Pages) – האתר הוא אותה תוכנה; רק הדפדפן אחר.
$script:OZO = @{ pid = 0; port = 0; tmp = $null; desk = [IntPtr]::Zero; cdp = $null; target = $null; last = [datetime]::MinValue; books = @(); login = 0; lport = 0 }
$OZO_URL = 'https://tablet.otzar.org/'
$OZO_PROFILE = Join-Path $env:LOCALAPPDATA 'KtivBridge\otzar-online'

function Find-Chrome {
  foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe')) {
    try { $p = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'(default)'; if ($p -and (Test-Path -LiteralPath $p)) { return $p } } catch {}
  }
  foreach ($p in @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
                   "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  return $null
}

function Ozo-Procs {
  # תהליכי הדפדפן שמשתמשים בפרופיל של הגשר (גם חלון הכניסה הגלוי)
  $prof = $OZO_PROFILE
  return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($prof) })
}

function Ozo-Close {
  if ($script:OZO.cdp) { try { $script:OZO.cdp.Dispose() } catch {} }
  if ($script:OZO.pid) { Ozo-Procs | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} } }
  if ($script:OZO.desk -ne [IntPtr]::Zero) { Start-Sleep -Milliseconds 800; [void][KB]::CloseDesk($script:OZO.desk) }
  $login = $script:OZO.login; $lport = $script:OZO.lport
  $script:OZO = @{ pid = 0; port = 0; tmp = $null; desk = [IntPtr]::Zero; cdp = $null; target = $null; last = [datetime]::MinValue; books = @(); login = $login; lport = $lport }
}

function Ozo-Ensure {
  if ($script:OZO.pid -and [KB]::Alive($script:OZO.pid) -and $script:OZO.cdp -and $script:OZO.cdp.Open) { return 'ok' }
  Ozo-Close
  $exe = Find-Chrome
  if (-not $exe) { return 'לא נמצא כרום או Edge במחשב' }
  if (@(Ozo-Procs).Count) {   # חלון הכניסה למנוי עדיין פתוח
    # (26.11) אחרי שנכנסו למנוי – הגשר סוגר את החלון בעצמו (קודם נשאר "פתוח" עד שסגרו אותו ידנית, וכל החיפושים חיכו)
    if (-not (Ozo-LoginDone)) { return 'login-open' }
    L 'אוצר החכמה המקוון: הכניסה למנוי הצליחה – סוגר את חלון הכניסה'
    Ozo-Procs | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force } catch {} }
    for ($i = 0; $i -lt 20 -and @(Ozo-Procs).Count; $i++) { Start-Sleep -Milliseconds 500 }
    $script:OZO.lport = 0
    if (@(Ozo-Procs).Count) { return 'login-open' }
  }
  New-Item -ItemType Directory -Force -Path $OZO_PROFILE | Out-Null
  $port = Get-Random -Minimum 9400 -Maximum 9459
  $desk = [KB]::NewDesk('ktivbridge_w')
  $script:OZO.port = $port; $script:OZO.desk = $desk
  $cl = '--remote-debugging-port=' + $port + ' --user-data-dir="' + $OZO_PROFILE + '" --no-first-run --no-default-browser-check --disable-gpu --window-size=1600,1100 ' + $OZO_URL
  $script:OZO.pid = [KB]::Launch($exe, $cl, (Split-Path -Parent $exe), 'ktivbridge_w')
  if ($script:OZO.pid -le 0) { Ozo-Close; return 'הדפדפן לא נפתח' }
  $t = $null
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 1
    try { $arr = (New-Object Net.WebClient).DownloadString('http://127.0.0.1:' + $port + '/json/list') | ConvertFrom-Json } catch { continue }
    $t = @(@($arr) | ForEach-Object { $_ } | Where-Object { $_.type -eq 'page' -and $_.url -match 'otzar\.org' -and $_.webSocketDebuggerUrl }) | Select-Object -First 1
    if ($t -and $t.url -notmatch '#/loading') { break }
  }
  if (-not $t) { Ozo-Close; return 'אוצר החכמה המקוון לא נטען' }
  $script:OZO.target = $t
  $script:OZO.cdp = [KB+Cdp]::new($t.webSocketDebuggerUrl)
  [void]$script:OZO.cdp.Send('Emulation.setFocusEmulationEnabled', '{"enabled":true}', 5000)
  [void]$script:OZO.cdp.Send('Emulation.setDeviceMetricsOverride', '{"width":1280,"height":3400,"deviceScaleFactor":1.5,"mobile":false}', 5000)
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $ok = $null; try { $ok = Ozo-Eval '!!document.querySelector("input[id^=fs_input]")' } catch {}
    if ($ok) { break }
  }
  if (-not $ok) {   # (23.11) כרום שחזר את הלשונית האחרונה מחלון הכניסה (עמוד ספר) – שם אין window._store והגשר חשב שזה אורח. חוזרים לדף הבית
    try { [void]$script:OZO.cdp.Send('Page.navigate', ('{"url":' + [KB]::J($OZO_URL) + '}'), 10000) } catch {}
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep -Milliseconds 500
      $ok = $null; try { $ok = Ozo-Eval '!!document.querySelector("input[id^=fs_input]")' } catch {}
      if ($ok) { break }
    }
    if (-not $ok) { L 'אוצר החכמה המקוון: הדף לא נטען כראוי גם אחרי מעבר לדף הבית' }
  }
  $script:OZO.last = Get-Date
  return 'ok'
}

function Ozo-Eval([string]$expr) {
  $expr = $JS_STORE_SHIM + "`n" + $expr
  $r = $script:OZO.cdp.Send('Runtime.evaluate', ('{"expression":' + [KB]::J($expr) + ',"returnByValue":true,"awaitPromise":true}'), 30000) | ConvertFrom-Json
  return $r.result.result.value
}

function Ozo-Login {
  # אורח: פותחים חלון גלוי של אותו פרופיל באתר, ואסתר נכנסת למנוי בעצמה. לכל היותר פעם ב-3 דקות.
  Ozo-Close
  if (((Get-Date) - [datetime]$script:OZO.login).TotalMinutes -lt 3 -and $script:OZO.login) { return }   # (23.11) היה פעם בשעה – אסתר סגרה חלון וחיכתה שעה לחדש
  $exe = Find-Chrome
  if (-not $exe) { return }
  # (26.11) עם פתח בקרה, כדי שהגשר יראה מתי הכניסה הצליחה ויסגור את החלון בעצמו (Ozo-LoginDone)
  $lp = Get-Random -Minimum 9460 -Maximum 9499
  Start-Process -FilePath $exe -ArgumentList @('--remote-debugging-port=' + $lp, '--user-data-dir="' + $OZO_PROFILE + '"', '--no-first-run', '--no-default-browser-check', '--new-window', $OZO_URL) | Out-Null
  $script:OZO.login = Get-Date; $script:OZO.lport = $lp
  L 'אוצר החכמה המקוון: נפתח חלון כניסה למנוי (פעם אחת; אחרי הכניסה סוגרים את החלון)'
}

function Ozo-LoginDone {
  # (26.11) האם בחלון הכניסה כבר נכנסו למנוי: בודקים בכל לשונית של אוצר החכמה בחלון (דרך פתח הבקרה שלו) שהמשתמש אינו אורח.
  # חלון שנפתח בגרסה קודמת (בלי פתח בקרה) – אי אפשר לדעת: כמו קודם, מחכים שיסגרו אותו.
  $lp = [int]$script:OZO.lport
  if (-not $lp) { return $false }
  try { $arr = (New-Object Net.WebClient).DownloadString('http://127.0.0.1:' + $lp + '/json/list') | ConvertFrom-Json } catch { return $false }
  $js = $JS_STORE_SHIM + "`n" + '(() => { const s = window._store; const u = s && s.state.user; return !!(u && u.fullname && !/אורח/.test(u.fullname)); })()'
  foreach ($t in @(@($arr) | ForEach-Object { $_ } | Where-Object { $_.type -eq 'page' -and $_.url -match 'otzar\.org' -and $_.webSocketDebuggerUrl })) {
    $c = $null
    try {
      $c = [KB+Cdp]::new($t.webSocketDebuggerUrl)
      $r = $c.Send('Runtime.evaluate', ('{"expression":' + [KB]::J($js) + ',"returnByValue":true}'), 8000) | ConvertFrom-Json
      if ($r.result.result.value -eq $true) { return $true }
    } catch {} finally { if ($c) { try { $c.Dispose() } catch {} } }
  }
  return $false
}

# 16.11 (אסתר: "לרוב די בחיפוש בתוך אותו ספר"): חיפוש רק בספרים ששמם כשם הספר שצוין – מסננים את רשימת הספרים
# בשם הספר (התיבה "חפש שם ספר או מחבר"), ובוחרים "ברשימה נוכחית" ליד תיבת החיפוש. אחרי החיפוש – חוזרים ל"בכל הספרים".
$JS_SCOPE = @'
((want) => { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const combo = [...document.querySelectorAll('.FSFilterCombo')].find(vis); if (!combo) return 'nocombo';
 const cur = (combo.querySelector('.selected-text') || {}).innerText || ''; if (cur.trim() === want) return 'ok';
 combo.click();
 const it = [...document.querySelectorAll('.combo-item')].find(e => (e.innerText || '').trim() === want); if (!it) return 'noitem';
 it.click(); return 'ok'; })
'@

function Ozo-ListFilter([string]$name) {
  $r = Ozo-Eval @'
(() => { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const e = [...document.querySelectorAll('input[id^="bs_input"]')].find(vis) || [...document.querySelectorAll('input')].find(x => vis(x) && /שם ספר או מחבר/.test(x.placeholder || ''));
 if (!e) return 'none'; e.focus(); e.select(); return 'ok'; })()
'@
  if ($r -ne 'ok') { return $false }
  if ($name) { [void]$script:OZO.cdp.Send('Input.insertText', ('{"text":' + [KB]::J($name) + '}'), 5000) }
  else { [void]$script:OZO.cdp.Send('Input.dispatchKeyEvent', '{"type":"keyDown","key":"Backspace","code":"Backspace","windowsVirtualKeyCode":8}', 5000)
         [void]$script:OZO.cdp.Send('Input.dispatchKeyEvent', '{"type":"keyUp","key":"Backspace","code":"Backspace","windowsVirtualKeyCode":8}', 5000) }
  Start-Sleep -Milliseconds 2500
  return $true
}

# (24.11) סוג החיפוש באתר (שדרוג 24.11): רגיל – לפי המילים שהוזנו (ברירת המחדל של הגשר: התחביר שלנו בנוי עליו); מורחב – שורשים והטיות;
# חכם – הבנת השאלה, נרדפות ושורשים. וגם: סוגרים את חלונית "חדש בגרסה" שמכסה את המסך.
$OZO_MODES = @{ regular = 'חיפוש רגיל'; extended = 'חיפוש מורחב'; smart = 'חיפוש חכם' }
$JS_MODE = @'
((want) => { const lab = () => ((document.querySelector('.nl-mode-label') || {}).textContent || '').trim();
 if (!document.querySelector('.nl-mode-btn')) return 'nomode'; if (lab() === want) return 'ok';
 if (document.querySelector('.nl-mode-btn.locked, .nl-mode-btn[aria-disabled="true"]')) return 'locked';   // (25.11) נעול כשספר פתוח בחלון
 const items = () => [...document.querySelectorAll('.nl-mode-menu .nl-mode-item')];
 if (!items().length) document.querySelector('.nl-mode-btn').click();
 const it = items().find(a => ((a.querySelector('.nl-mode-item-title') || a).textContent || '').trim() === want);
 if (!it) return 'noitem:' + items().map(a => (a.textContent || '').trim().slice(0, 20)).join('|'); it.click(); return 'clicked'; })
'@
function Ozo-Popups {
  try { [void](Ozo-Eval '(() => { document.querySelectorAll("button.whatsnew-close").forEach(b => b.click()); setTimeout(() => document.querySelectorAll(".whatsnew-backdrop, iframe.whatsnew-iframe, button.whatsnew-close").forEach(e => e.remove()), 300); return "ok"; })()') } catch {}
}
function Ozo-SetMode([string]$mode) {
  if (-not $mode) { $mode = 'regular' }
  $want = $OZO_MODES[$mode]; if (-not $want) { throw ('סוג חיפוש לא מוכר: ' + $mode) }
  for ($t = 0; $t -lt 3; $t++) {
    $r = Ozo-Eval ($JS_MODE + '(' + [KB]::J($want) + ')')
    if ($r -eq 'ok' -or $r -eq 'nomode') { return $r }
    if ($r -eq 'locked') {
      # (25.11) הכפתור נעול כל עוד ספר פתוח בחלון (שיחה אחרת פתחה ספר): חוזרים למסך הבית ומחכים שייפתח (עד 12 שנ')
      [void](Ozo-Eval '(() => { const h = document.querySelector(".icon-home"); if (h) (h.closest("a, button, [role=button]") || h).click(); return "ok"; })()')
      for ($w = 0; $w -lt 24; $w++) {
        Start-Sleep -Milliseconds 500
        if ((Ozo-Eval '(() => document.querySelector(".nl-mode-btn.locked, .nl-mode-btn[aria-disabled=\"true\"]") ? "locked" : "open")()') -eq 'open') { break }
      }
      continue
    }
    Start-Sleep -Milliseconds 700
  }
  $r = Ozo-Eval ($JS_MODE + '(' + [KB]::J($want) + ')')
  if ($r -ne 'ok') { throw ('לא הצלחתי לבחור "' + $want + '" (' + $r + ')') }
  return $r
}

function Otzar-Online($p) {
  $q = [string]$p.query
  if (-not $q.Trim()) { throw 'חסר הניסוח' }
  $e = Ozo-Ensure
  if ($e -eq 'login-open') { return @{ state = 'login'; message = 'חלון הכניסה לאוצר החכמה המקוון פתוח במחשב: היכנסו למנוי וסגרו אותו' } }
  if ($e -ne 'ok') { return @{ state = 'error'; message = $e } }
  # (23.11) דפדפן שנפתח הרגע (אחרי עדכון הגשר) עוד לא טען את פרטי המנוי – מחכים עד 12 שניות לפני שמחליטים שזה אורח
  for ($gi = 0; $gi -lt 24; $gi++) {
    $guest = Ozo-Eval '(() => { const s = window._store; if (!s) { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; }; return [...document.querySelectorAll("button, a, [role=button]")].some(e => vis(e) && /^(כניסה|התחבר|התחברות|כניסה למנויים)$/.test((e.innerText || "").trim())); } const u = s.state.user; return !u || !u.fullname || /אורח/.test(u.fullname); })()'
    if (-not $guest) { break }; Start-Sleep -Milliseconds 500
  }
  if ($guest) {
    $gd = ''; try { $gd = Ozo-Eval '(() => { const s = window._store; const u = s && s.state.user; return JSON.stringify({store: !!s, href: location.href.slice(0, 80), title: document.title, ready: document.readyState, body: (document.body ? document.body.innerText : "").replace(/\s+/g, " ").slice(0, 200), keys: u ? Object.keys(u).slice(0, 30) : null, fullname: u ? u.fullname : null, cookies: document.cookie.length, rootkeys: (() => { const v = document.querySelector("#app").__vue__; return v ? Object.keys(v).filter(k => k[0] === "$" || k[0] === "_").slice(0, 40) : null; })(), win: (() => { const f = document.createElement("iframe"); document.body.appendChild(f); const base = new Set(Object.keys(f.contentWindow)); f.remove(); return Object.keys(window).filter(k => !base.has(k)).slice(0, 40); })(), elprops: [...document.querySelectorAll("body > *")].slice(0, 6).map(e => e.tagName + "#" + e.id + ":" + Object.keys(e).filter(k => k.startsWith("_")).join("/"))}); })()' } catch { $gd = 'eval-error: ' + $_ }
    L ('אוצר החכמה המקוון: נראה כאורח ' + $gd)
    Ozo-Login
    return @{ state = 'login'; message = 'צריך להיכנס פעם אחת לאוצר החכמה המקוון בחלון שנפתח במחשב'; diag = $gd }
  }
  Ozo-Popups
  $mode = [string]$p.mode; $modeR = Ozo-SetMode $mode
  # אותו קוד של אוצר החכמה שבמחשב, על הדפדפן של האתר
  $saved = $script:OZ; $script:OZ = $script:OZO
  $scoped = $false
  try {
    $pref = [string]$p.prefer
    if ($pref.Trim().Length -ge 3 -and (Ozo-ListFilter $pref)) {
      $sc = Ozo-Eval ($JS_SCOPE + '(' + [KB]::J('ברשימה נוכחית') + ')')
      $scoped = ($sc -eq 'ok')
      if (-not $scoped) { [void](Ozo-ListFilter '') }
    }
    $r = Oz-Search $q 40
    if ($scoped -and -not @($r.books).Count) {               # הספר לא נמצא באתר, או המילים לא בו – חיפוש רגיל
      [void](Ozo-Eval ($JS_SCOPE + '(' + [KB]::J('בכל הספרים') + ')')); [void](Ozo-ListFilter ''); $scoped = $false
      $r = Oz-Search $q 40; $r.in_book = $false
    } elseif ($scoped) { $r.in_book = $true }
    if ($p.all) { $r.books = @(Oz-AllBooks $r.books_total); $r.list_diag = $script:OzListDiag }   # (23.11) רשימה מלאה – רק כשלא פותחים ספרים (books=0)
    $n = [Math]::Max(0, [Math]::Min([int]$p.books, 5))
    # 16.11: הספר שצוין (prefer) – קודם הוא מתוך 40 התוצאות, ורק אחר כך הראשונים ברשימה
    $idx = @(); $pref = ([string]$p.prefer) -replace '["''\u05F3\u05F4\s]', ''
    if ($pref.Length -ge 3) {
      foreach ($b in @($r.books)) {
        $tk = ([string]$b.title) -replace '["''\u05F3\u05F4\s]', ''
        if ($tk.Contains($pref) -and $idx.Count -lt $n) { $idx += [int]$b.idx }
      }
    }
    if ($pref.Length -ge 3 -and -not $idx.Count -and $n -gt 0) {   # (23.11) הספר שצוין לא בין 40 הראשונים – מחפשים אותו בכל הרשימה (גלילה)
      $all = @(Oz-AllBooks $r.books_total); $script:OZ.books = $all
      foreach ($b in $all) { $tk = ([string]$b.title) -replace '["''\u05F3\u05F4\s]', ''; if ($tk.Contains($pref) -and $idx.Count -lt $n) { $idx += [int]$b.idx } }
      if (-not $idx.Count) { $script:OZ.books = @($r.books) } else { $r.prefer_found = 'ברשימה המלאה' }
    }
    if ($pref.Length -ge 3 -and -not $idx.Count) { $r.prefer_found = 'לא נמצא ברשימה' }
    for ($i = 0; $i -lt @($script:OZ.books).Count -and $idx.Count -lt $n; $i++) { if ($idx -notcontains $i) { $idx += $i } }
    $pages = @(); if ($idx.Count) { $pages = @(Oz-Pages $idx 'text') }
    $out = @{ state = 'ok'; count = $r.count; books_total = $r.books_total; books = @($r.books); pages = $pages; in_book = [bool]$r.in_book; list_diag = $r.list_diag; prefer_found = $r.prefer_found; mode = $(if ($mode) { $mode } else { 'regular' }); mode_state = $modeR }
  } finally {
    if ($scoped) { try { [void](Ozo-Eval ($JS_SCOPE + '(' + [KB]::J('בכל הספרים') + ')')); [void](Ozo-ListFilter '') } catch {} }
    $script:OZO = $script:OZ; $script:OZ = $saved
  }
  $script:OZO.last = Get-Date
  return $out
}

$JS_GOPOS = @'
((cur) => { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const small = [...document.querySelectorAll('input')].filter(i => { const r = i.getBoundingClientRect(); return vis(i) && r.width < 120 && r.y < 260 && !i.placeholder; });
 let inp = small.find(i => String(i.value).trim() === String(cur));
 if (!inp) { const lab = [...document.querySelectorAll('*')].find(e => e.children.length === 0 && vis(e) && /מתוך/.test(e.innerText || '') && (e.innerText || '').length < 25);
   let w = lab; for (let i = 0; i < 5 && w && !inp; i++) { w = w.parentElement; if (w) inp = [...w.querySelectorAll('input')].find(vis); } }
 if (!inp) return 'none:' + small.map(i => i.value).join('|'); inp.focus(); inp.select(); return 'ok'; })
'@

function Ozo-GoPos([int]$pos) {
  # כמו אדם: מקלידים את מספר העמוד בתיבה "… מתוך N" שבסרגל הספר ולוחצים Enter (באתר המקוון הכתובת לא נושאת את העמוד)
  $cur = (Oz-PageState).p
  $r = Oz-Eval ($JS_GOPOS + '(' + [KB]::J([string]$cur) + ')')
  if ($r -ne 'ok') { throw ('תיבת מספר העמוד לא נמצאה (' + $r + ')') }
  $before = Oz-Eval 'location.href'
  [void](Oz-Send 'Input.insertText' ('{"text":"' + $pos + '"}'))
  [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"rawKeyDown","key":"Enter","code":"Enter","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13}')
  [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"char","key":"Enter","text":"\r","unmodifiedText":"\r","windowsVirtualKeyCode":13}')
  [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"keyUp","key":"Enter","code":"Enter","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13}')
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 700
    $s = Oz-PageState
    if ([int]$s.p -eq $pos -and $s.canvas) { Start-Sleep -Milliseconds 1500; return (Oz-PageState) }
  }
  return (Oz-PageState)
}

function Otzar-Online-Pages($p) {
  # 19.11 (אסתר): דפדוף – n עמודים רצופים מעמוד page בספר book_id, טקסט מזיהוי התווים של אוצר החכמה, רק בפרופיל של הגשר.
  # אם הספר לא פתוח – פותחים אותו דרך החיפוש שמצא אותו (query), ואז עוברים לעמוד בתיבת מספר העמוד.
  $book = [int]$p.book_id; $page = [int]$p.page; $n = [Math]::Max(1, [Math]::Min([int]$p.n, 10)); $q = [string]$p.query
  if ($book -le 0 -or $page -le 0) { throw 'חסר מספר ספר או עמוד' }
  $e = Ozo-Ensure
  if ($e -eq 'login-open') { return @{ state = 'login'; message = 'חלון הכניסה לאוצר החכמה המקוון פתוח במחשב: היכנסו למנוי וסגרו אותו' } }
  if ($e -ne 'ok') { return @{ state = 'error'; message = $e } }
  for ($gi = 0; $gi -lt 24; $gi++) {   # כמו בחיפוש: לחכות לפרטי המנוי בדפדפן שנפתח הרגע
    $guest = Ozo-Eval '(() => { const s = window._store; if (!s) { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; }; return [...document.querySelectorAll("button, a, [role=button]")].some(e => vis(e) && /^(כניסה|התחבר|התחברות|כניסה למנויים)$/.test((e.innerText || "").trim())); } const u = s.state.user; return !u || !u.fullname || /אורח/.test(u.fullname); })()'
    if (-not $guest) { break }; Start-Sleep -Milliseconds 500
  }
  if ($guest) { Ozo-Login; return @{ state = 'login'; message = 'צריך להיכנס פעם אחת לאוצר החכמה המקוון בחלון שנפתח במחשב' } }
  Ozo-Popups
  $saved = $script:OZ; $script:OZ = $script:OZO
  $pages = @(); $title = ''
  try {
    $cur = Oz-PageState
    if ([int]$cur.book -ne $book) {
      if (-not $q.Trim()) { return @{ state = 'error'; message = 'הספר לא פתוח – צריך את הניסוח שמצא אותו (query)' } }
      [void](Ozo-SetMode ([string]$p.mode))
      $r = Oz-Search $q 40; $ok = $false
      for ($i = 0; $i -lt [Math]::Min(8, @($r.books).Count); $i++) {
        try { $pg = Oz-OpenBook $i; if ([int]$pg.book_id -eq $book) { $ok = $true; $title = [string]$r.books[$i].title; break } } catch { L ('דפדוף: פתיחת ספר ' + $i + ': ' + $_) }
      }
      if (-not $ok) { return @{ state = 'error'; message = 'הספר לא נמצא בתוצאות החיפוש (נסו ניסוח אחר מהעמוד)' } }
    }
    for ($k = 0; $k -lt $n; $k++) {
      $pp = $page + $k
      try {
        $st = Oz-PageState
        if ([int]$st.p -ne $pp -or -not $st.canvas) { $st = Ozo-GoPos $pp }
        if ([int]$st.p -ne $pp) { throw ('לא עבר לעמוד ' + $pp + ' (נשאר ב-' + $st.p + ')') }
        $fit = Oz-Eval '(() => { const e = document.querySelector(".font-icon-bar.icon-fitWidth"); if (!e) return "none"; if (/active/.test(String(e.className))) return "already"; (e.closest(".item") || e).click(); return "clicked"; })()'
        if ($fit -eq 'clicked') { Start-Sleep -Milliseconds 1800 }   # (23.11) התאמה לרוחב, בחלון הגבוה כל העמוד בתצוגה
        $reg = Oz-PageText
        $label = [string]$st.letter; if (-not $label -and @($st.inputs).Count) { $label = @($st.inputs)[0] }
        $one = @{ page = $pp; page_label = $label; text = $reg.text }; if ($reg.text_error) { $one.text_error = $reg.text_error }
        $pages += $one
      } catch { L ('אוצר החכמה המקוון, דפדוף ' + $book + '/' + $pp + ': ' + $_); $pages += @{ page = $pp; error = [string]$_ } }
    }
  } finally { $script:OZO = $script:OZ; $script:OZ = $saved }
  $script:OZO.last = Get-Date
  return @{ state = 'ok'; book_id = $book; title = $title; pages = $pages }
}

# (24.11, שיחת אוצר-בינה) בדיקת מבנה האתר אחרי שדרוג (סוגי חיפוש, "שאל את האוצר", רשימה חדשה) – פעולות קבועות בלבד, בלי קוד חופשי:
# scan / find (ביטוי) / dump (בורר) / click (טקסט) / clicksel (בורר) / type (+ sel) / key / wait / search / shot
$JS_PROBE = @'
((st) => { const vis = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
 const cl = e => typeof e.className === 'string' ? e.className : ((e.className && e.className.baseVal) || '');
 const d = e => { if (!e) return null; const r = e.getBoundingClientRect(); const path = [];
   for (let p = e.parentElement, i = 0; p && i < 5; p = p.parentElement, i++) path.push(p.tagName.toLowerCase() + (p.id ? '#' + p.id : '') + (cl(p) ? '.' + cl(p).trim().split(/\s+/).slice(0, 3).join('.') : ''));
   return {tag: e.tagName.toLowerCase(), id: e.id || '', cls: cl(e).slice(0, 140), txt: (e.innerText || e.value || '').replace(/\s+/g, ' ').trim().slice(0, 160),
     ph: e.placeholder || '', aria: (e.getAttribute && e.getAttribute('aria-label')) || '', title: (e.getAttribute && e.getAttribute('title')) || '',
     x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), vis: vis(e), path: path}; };
 const leaf = re => [...document.querySelectorAll('body *')].filter(e => re.test(e.textContent || '') && ![...e.children].some(c => re.test(c.textContent || '')));
 const byText = t => { const all = [...document.querySelectorAll('body *')].filter(vis);
   let c = all.filter(e => (e.innerText || '').trim() === t); if (!c.length) c = all.filter(e => (e.innerText || '').includes(t) || (e.getAttribute('title') || '') === t || (e.getAttribute('aria-label') || '') === t || (e.placeholder || '') === t);
   c.sort((a, b) => (a.innerText || '').length - (b.innerText || '').length); return c[0]; };
 if (st.scan) return JSON.stringify({href: location.href, vw: innerWidth, vh: innerHeight,
   inputs: [...document.querySelectorAll('input, textarea, [contenteditable=true]')].filter(vis).slice(0, 25).map(d),
   top: [...document.querySelectorAll('button, [role=button], a, .btn, [class*=icon]')].filter(vis).filter(e => e.getBoundingClientRect().y < 340).slice(0, 80).map(d),
   modes: leaf(/חיפוש (מורחב|חכם|רגיל)/).slice(0, 12).map(d), ask: leaf(/שאל את האוצר|שאל שאלה|בשפה חופשית/).slice(0, 12).map(d),
   desc: leaf(/תוצאות ב/).slice(0, 6).map(d), area: d(document.querySelector('.free-search-area'))});
 if (st.find) return JSON.stringify(leaf(new RegExp(st.find)).slice(0, st.n || 20).map(d));
 if (st.dump) { const els = [...document.querySelectorAll(st.dump)]; const e = els.find(vis) || els[0];
   return JSON.stringify({count: els.length, el: d(e), html: e ? e.outerHTML.replace(/\s+/g, ' ').slice(0, st.n || 9000) : '', text: e ? (e.innerText || '').slice(0, st.n || 9000) : ''}); }
 if (st.click || st.clicksel) { const e = st.click ? byText(st.click) : [...document.querySelectorAll(st.clicksel)].find(vis);
   if (!e) return JSON.stringify({clicked: false}); e.scrollIntoView({block: 'center'}); (e.closest('button, a, li, [role=button], [role=option]') || e).click(); return JSON.stringify({clicked: true, el: d(e)}); }
 if (st.setval) { const e = [...document.querySelectorAll(st.setval)].find(vis) || document.querySelector(st.setval); if (!e) return JSON.stringify({set: false});
   const proto = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype; Object.getOwnPropertyDescriptor(proto, 'value').set.call(e, st.value || '');
   e.dispatchEvent(new Event('input', {bubbles: true})); e.dispatchEvent(new Event('change', {bubbles: true})); return JSON.stringify({set: true, value: e.value.length}); }
 if (st.focus) { const e = [...document.querySelectorAll(st.focus)].find(vis); if (!e) return JSON.stringify({focused: false}); e.focus(); if (e.select) e.select(); return JSON.stringify({focused: true, el: d(e)}); }
 if (st.shotrect) { const e = [...document.querySelectorAll(st.shotrect)].find(vis); if (!e) return 'null'; const r = e.getBoundingClientRect(); return JSON.stringify({x: r.x, y: r.y, w: r.width, h: r.height}); }
 return 'null'; })
'@

function Otzar-Online-Probe($p) {
  $e = Ozo-Ensure
  if ($e -ne 'ok') { return @{ state = 'error'; message = $e } }
  $saved = $script:OZ; $script:OZ = $script:OZO
  $out = @()
  try {
    foreach ($s in @($p.steps | Select-Object -First 40)) {
      try {
        if ($s.wait) { Start-Sleep -Milliseconds ([int]([Math]::Min([double]$s.wait, 120) * 1000)); $out += @{ wait = $s.wait }; continue }
        if ($s.search) { $r = Oz-Search ([string]$s.search) 40; $out += @{ search = $s.search; count = $r.count; books_total = $r.books_total; books = @($r.books).Count; desc = $r.desc }; continue }
        if ($s.drag) {   # גרירת עכבר [x1,y1,x2,y2] (בחירת אזור בעמוד)
          $d = @($s.drag); $ax = [int]$d[0]; $ay = [int]$d[1]; $bx = [int]$d[2]; $by = [int]$d[3]
          [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseMoved","x":' + $ax + ',"y":' + $ay + '}'))
          [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mousePressed","x":' + $ax + ',"y":' + $ay + ',"button":"left","buttons":1,"clickCount":1}'))
          for ($k = 1; $k -le 10; $k++) { [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseMoved","x":' + [int]($ax + ($bx - $ax) * $k / 10) + ',"y":' + [int]($ay + ($by - $ay) * $k / 10) + ',"button":"left","buttons":1}')) }
          [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"mouseReleased","x":' + $bx + ',"y":' + $by + ',"button":"left","buttons":0,"clickCount":1}'))
          $out += @{ drag = $d }; continue
        }
        if ($s.pagestate) { $out += @{ pagestate = (Oz-PageState) }; continue }
        if ($s.viewport) { $vp = @($s.viewport); [void](Oz-Send 'Emulation.setDeviceMetricsOverride' ('{"width":' + [int]$vp[0] + ',"height":' + [int]$vp[1] + ',"deviceScaleFactor":1.5,"mobile":false}')); $out += @{ viewport = $vp }; continue }
        if ($s.mouse) {   # לחיצת עכבר אמיתית במרכז האלמנט (כפתורים שלא מגיבים ל-click)
          $rj = Oz-Eval ($JS_PROBE + '(' + (@{ shotrect = [string]$s.mouse } | ConvertTo-Json -Compress) + ')')
          if (-not $rj -or $rj -eq 'null') { $out += @{ mouse = $s.mouse; found = $false }; continue }
          $rc = $rj | ConvertFrom-Json; $mx = [Math]::Round([double]$rc.x + [double]$rc.w / 2); $my = [Math]::Round([double]$rc.y + [double]$rc.h / 2)
          foreach ($t in @('mouseMoved', 'mousePressed', 'mouseReleased')) { [void](Oz-Send 'Input.dispatchMouseEvent' ('{"type":"' + $t + '","x":' + $mx + ',"y":' + $my + ',"button":"left","clickCount":1}')) }
          $out += @{ mouse = $s.mouse; x = $mx; y = $my }; continue
        }
        if ($s.type) { [void](Oz-Send 'Input.insertText' ('{"text":' + [KB]::J([string]$s.type) + '}')); $out += @{ typed = ([string]$s.type).Length }; continue }
        if ($s.key) {
          $k = [string]$s.key; $vk = $(if ($k -eq 'Enter') { 13 } elseif ($k -eq 'Escape') { 27 } else { 0 })
          [void](Oz-Send 'Input.dispatchKeyEvent' ('{"type":"rawKeyDown","key":' + [KB]::J($k) + ',"code":' + [KB]::J($k) + ',"windowsVirtualKeyCode":' + $vk + '}'))
          if ($k -eq 'Enter') { [void](Oz-Send 'Input.dispatchKeyEvent' '{"type":"char","key":"Enter","text":"\r","unmodifiedText":"\r","windowsVirtualKeyCode":13}') }
          [void](Oz-Send 'Input.dispatchKeyEvent' ('{"type":"keyUp","key":' + [KB]::J($k) + ',"code":' + [KB]::J($k) + ',"windowsVirtualKeyCode":' + $vk + '}'))
          $out += @{ key = $k }; continue
        }
        if ($s.shot) {
          $rect = $null
          if ($s.shot -is [string]) { $rj = Oz-Eval ($JS_PROBE + '(' + (@{ shotrect = [string]$s.shot } | ConvertTo-Json -Compress) + ')'); if ($rj -and $rj -ne 'null') { $rect = $rj | ConvertFrom-Json } }
          if (-not $rect) { $rect = @{ x = 0; y = 0; w = 1280; h = 1000 } }
          $b = Oz-Shot $rect 0.7; $out += @{ shot = [Convert]::ToBase64String($b) }; continue
        }
        $j = Oz-Eval ($JS_PROBE + '(' + ($s | ConvertTo-Json -Compress -Depth 4) + ')')
        $out += @{ step = $s; r = $(if ($j) { $j | ConvertFrom-Json } else { $null }) }
      } catch { $out += @{ step = $s; error = [string]$_ } }
    }
  } finally { $script:OZO = $script:OZ; $script:OZ = $saved }
  $script:OZO.last = Get-Date
  return @{ state = 'ok'; steps = $out }
}

function Run-Job($job) {
  switch ($job.kind) {
    'batch' { return (Run-Batch $job) }
    'otzar_books' { return (Otzar-Books $job.params) }
    'otzar_online' { return (Otzar-Online $job.params) }
    'otzar_online_pages' { return (Otzar-Online-Pages $job.params) }
    'otzar_online_probe' { return (Otzar-Online-Probe $job.params) }
    'close' { Oz-Close; Ozo-Close; [KB]::ResponsaClose(); [KB]::DbsClose(); return @{ ok = $true } }
    'selftest' { return @{ version = $VERSION; caps = (Caps) } }
    default { throw ('סוג משימה לא מוכר: ' + $job.kind) }
  }
}

function Housekeeping {
  # אוצר החכמה של העורך נפתח בזמן שהעותק שלנו פתוח: סוגרים את שלנו מיד, כדי שהוא לא ייחסם
  if ($script:OZ.pid) {
    if (-not [KB]::Alive($script:OZ.pid)) { Oz-Close }
    elseif (-not $script:OZ.owned) { if (((Get-Date) - $script:OZ.last).TotalSeconds -gt 300) { Oz-Close } }   # עותק של גשר אחר – רק מתנתקים
    elseif (Oz-Lock 0) {   # (24.11) לא סוגרים באמצע חיפוש של גשר אחר שמחובר לעותק שלנו
      try {
        if (Editor-OtzarRunning) { L 'אוצר החכמה נפתח אצל העורך: סוגר את העותק הנסתר'; Oz-Close }
        elseif (((Get-Date) - (Oz-LastShared)).TotalSeconds -gt 300) { L 'אוצר החכמה: סגירה אחרי 5 דקות בלי שימוש'; Oz-Close }
      } finally { Oz-Unlock }
    }
  }
  if ([KB]::RPid -and ((Get-Date) - $script:RS.last).TotalSeconds -gt 300) { L 'בר אילן: סגירה אחרי 5 דקות בלי שימוש'; [KB]::ResponsaClose() }
  if ([KB]::DPid -and ((Get-Date) - $script:DS.last).TotalSeconds -gt 300) { L 'התקליטור התורני: סגירה אחרי 5 דקות בלי שימוש'; [KB]::DbsClose() }
  if ($script:OZO.pid -and ((Get-Date) - $script:OZO.last).TotalSeconds -gt 300) { L 'אוצר החכמה המקוון: סגירה אחרי 5 דקות בלי שימוש'; Ozo-Close }
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
    Oz-Close; Ozo-Close; [KB]::ResponsaClose(); [KB]::DbsClose()
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
      $tj = Get-Date
      $res = Run-Job $job
      Out-Local @{ id = $job.id; result = $res }
      L ('משימה ' + $job.kind + ' – ' + [int]((Get-Date) - $tj).TotalSeconds + ' שנ''')   # (24.11) זמנים גם ביומן התוסף
    } catch {
      L ('שגיאה: ' + $_ + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
      Out-Local @{ id = $job.id; error = [string]$_ }
    }
  }
  try { if ($script:OZ.owned) { [void](Oz-Lock 60000) }; Oz-Close; Oz-Unlock } catch {}; try { Ozo-Close } catch {}; try { [KB]::ResponsaClose() } catch {}; try { [KB]::DbsClose() } catch {}
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
          Send-Result $job.id @{ result = $res }
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
