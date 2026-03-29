using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

/// <summary>
/// Attaches a native Win32 menu bar to the Godot window.
/// Windows-only — all public methods are silent no-ops on other platforms.
/// The menu bar lives in the non-client area (outside Godot's viewport), so
/// <c>_menu_bar_screen_height()</c> in DMWindow should report 0 when active.
/// </summary>
public partial class NativeWin32MenuBar : Node
{
    [Signal]
    public delegate void MenuItemPressedEventHandler(string menuName, int itemId);

    // ── Win32 constants ────────────────────────────────────────────────────
    private const uint WM_COMMAND = 0x0111;
    private const uint MF_STRING = 0x0000;
    private const uint MF_SEPARATOR = 0x0800;
    private const uint MF_POPUP = 0x0010;
    private const uint MF_CHECKED = 0x0008;
    private const uint MF_UNCHECKED = 0x0000;
    private const uint MF_GRAYED = 0x0001;
    private const uint MF_ENABLED = 0x0000;
    private const uint MF_BYCOMMAND = 0x0000;
    private const uint MIIM_STRING = 0x0040;

    // ── Win32 P/Invoke ─────────────────────────────────────────────────────
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CreateMenu();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool AppendMenuW(
        IntPtr hMenu, uint uFlags, nuint uIDNewItem, string lpNewItem);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetMenu(IntPtr hWnd, IntPtr hMenu);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DrawMenuBar(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyMenu(IntPtr hMenu);

    [DllImport("user32.dll")]
    private static extern uint CheckMenuItem(
        IntPtr hMenu, uint uIDCheckItem, uint uCheck);

    [DllImport("user32.dll")]
    private static extern bool EnableMenuItem(
        IntPtr hMenu, uint uIDEnableItem, uint uEnable);

    [DllImport("user32.dll")]
    private static extern bool CheckMenuRadioItem(
        IntPtr hMenu, uint first, uint last, uint check, uint flags);

    [DllImport("user32.dll")]
    private static extern uint GetMenuState(
        IntPtr hMenu, uint uId, uint uFlags);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct MENUITEMINFOW
    {
        public uint cbSize;
        public uint fMask;
        public uint fType;
        public uint fState;
        public uint wID;
        public IntPtr hSubMenu;
        public IntPtr hbmpChecked;
        public IntPtr hbmpUnchecked;
        public nuint dwItemData;
        public IntPtr dwTypeData;
        public uint cch;
        public IntPtr hbmpItem;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetMenuItemInfoW(
        IntPtr hmenu, uint item,
        [MarshalAs(UnmanagedType.Bool)] bool fByPosition,
        ref MENUITEMINFOW lpmii);

    // Safe subclassing via comctl32 (preferred over SetWindowLongPtr)
    private delegate nint SUBCLASSPROC(
        IntPtr hWnd, uint uMsg, nuint wParam, nint lParam,
        nuint uIdSubclass, nuint dwRefData);

    [DllImport("comctl32.dll", SetLastError = true)]
    private static extern bool SetWindowSubclass(
        IntPtr hWnd, SUBCLASSPROC pfnSubclass,
        nuint uIdSubclass, nuint dwRefData);

    [DllImport("comctl32.dll")]
    private static extern bool RemoveWindowSubclass(
        IntPtr hWnd, SUBCLASSPROC pfnSubclass, nuint uIdSubclass);

    [DllImport("comctl32.dll")]
    private static extern nint DefSubclassProc(
        IntPtr hWnd, uint uMsg, nuint wParam, nint lParam);

    // ── ID flat-space bases (must not overlap; each range holds 100 IDs) ──
    private readonly Dictionary<string, int> _bases = new()
    {
        ["File"] = 1000,
        ["Edit"] = 1100,
        ["View"] = 1200,
        ["GridType"] = 1300,
        ["Session"] = 1400,
        ["UITheme"] = 1500,
    };

    private const nuint SubclassId = 42;

    // ── Instance state ─────────────────────────────────────────────────────
    private IntPtr _hWnd;
    private IntPtr _hMenuBar;
    private readonly Dictionary<string, IntPtr> _popups = new();
    private readonly List<string> _order = new();
    private SUBCLASSPROC _subclassDelegate; // prevent GC of delegate
    private bool _attached;
    private readonly List<(string menu, int id)> _commandQueue = new();

    // ── Lifecycle ──────────────────────────────────────────────────────────
    public override void _Ready()
    {
        if (OS.GetName() != "Windows")
            return;

        _hWnd = (IntPtr)(long)DisplayServer.WindowGetNativeHandle(
            DisplayServer.HandleType.WindowHandle, 0);
        if (_hWnd == IntPtr.Zero)
            return;

        _hMenuBar = CreateMenu();

        // Subclass the window to intercept WM_COMMAND from menu items
        _subclassDelegate = WndProc;
        SetWindowSubclass(_hWnd, _subclassDelegate, SubclassId, 0);
    }

    public override void _ExitTree()
    {
        Detach();
    }

    public override void _Process(double delta)
    {
        if (_commandQueue.Count == 0) return;
        foreach (var (menu, id) in _commandQueue)
            EmitSignal(SignalName.MenuItemPressed, menu, id);
        _commandQueue.Clear();
    }

    // ── Menu construction ──────────────────────────────────────────────────

    public void AddMenu(string name)
    {
        if (_hMenuBar == IntPtr.Zero) return;
        _popups[name] = CreatePopupMenu();
        if (!_bases.ContainsKey(name))
            _bases[name] = (_bases.Count + 1) * 100 + 2000;
        _order.Add(name);
    }

    public void AddItem(string menuName, string label, int id)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        AppendMenuW(h, MF_STRING, (nuint)(_bases[menuName] + id), label);
    }

    public void AddCheckItem(string menuName, string label, int id,
                             bool initiallyChecked)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        uint flags = MF_STRING | (initiallyChecked ? MF_CHECKED : MF_UNCHECKED);
        AppendMenuW(h, flags, (nuint)(_bases[menuName] + id), label);
    }

    public void AddRadioCheckItem(string menuName, string label, int id,
                                  bool initiallyChecked)
    {
        // Win32 has no distinct radio type at creation time — use check item
        // and manage exclusivity via CheckMenuRadioItem later.
        AddCheckItem(menuName, label, id, initiallyChecked);
    }

    public void AddSeparator(string menuName)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        AppendMenuW(h, MF_SEPARATOR, 0, null);
    }

    public void AddSubmenu(string parentMenu, string submenuName, string label)
    {
        if (!_popups.TryGetValue(parentMenu, out var hParent)) return;
        if (!_popups.TryGetValue(submenuName, out var hSub)) return;
        AppendMenuW(hParent, MF_STRING | MF_POPUP, (nuint)hSub, label);
    }

    /// <summary>Attach the built menu bar to the window.</summary>
    public void Build()
    {
        if (_hMenuBar == IntPtr.Zero) return;
        foreach (var name in _order)
        {
            // Submenus are already wired into their parent via AddSubmenu.
            if (name == "GridType" || name == "UITheme") continue;
            if (_popups.TryGetValue(name, out var h))
                AppendMenuW(_hMenuBar, MF_STRING | MF_POPUP, (nuint)h, name);
        }
        SetMenu(_hWnd, _hMenuBar);
        DrawMenuBar(_hWnd);
        _attached = true;
    }

    // ── State management ───────────────────────────────────────────────────

    public void SetItemChecked(string menuName, int id, bool isChecked)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        uint flatId = (uint)(_bases[menuName] + id);
        CheckMenuItem(h, flatId,
            MF_BYCOMMAND | (isChecked ? MF_CHECKED : MF_UNCHECKED));
    }

    public void SetItemDisabled(string menuName, int id, bool disabled)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        uint flatId = (uint)(_bases[menuName] + id);
        EnableMenuItem(h, flatId,
            MF_BYCOMMAND | (disabled ? MF_GRAYED : MF_ENABLED));
    }

    public bool IsItemChecked(string menuName, int id)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return false;
        uint flatId = (uint)(_bases[menuName] + id);
        return (GetMenuState(h, flatId, MF_BYCOMMAND) & MF_CHECKED) != 0;
    }

    public void SetItemText(string menuName, int id, string text)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        uint flatId = (uint)(_bases[menuName] + id);
        var ptr = Marshal.StringToHGlobalUni(text);
        try
        {
            var mii = new MENUITEMINFOW
            {
                cbSize = (uint)Marshal.SizeOf<MENUITEMINFOW>(),
                fMask = MIIM_STRING,
                dwTypeData = ptr,
                cch = (uint)text.Length,
            };
            SetMenuItemInfoW(h, flatId, false, ref mii);
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    public void SetRadioChecked(string menuName, int firstId, int lastId,
                                int checkedId)
    {
        if (!_popups.TryGetValue(menuName, out var h)) return;
        int b = _bases[menuName];
        CheckMenuRadioItem(h, (uint)(b + firstId), (uint)(b + lastId),
            (uint)(b + checkedId), MF_BYCOMMAND);
    }

    // ── Teardown ───────────────────────────────────────────────────────────

    public void Detach()
    {
        if (_attached && _hWnd != IntPtr.Zero)
        {
            SetMenu(_hWnd, IntPtr.Zero);
            DrawMenuBar(_hWnd);
            _attached = false;
        }
        if (_subclassDelegate != null && _hWnd != IntPtr.Zero)
        {
            RemoveWindowSubclass(_hWnd, _subclassDelegate, SubclassId);
            _subclassDelegate = null;
        }
        if (_hMenuBar != IntPtr.Zero)
        {
            DestroyMenu(_hMenuBar);
            _hMenuBar = IntPtr.Zero;
        }
        _popups.Clear();
        _order.Clear();
    }

    // ── Window subclass procedure ──────────────────────────────────────────

    private nint WndProc(IntPtr hWnd, uint uMsg, nuint wParam, nint lParam,
                         nuint uIdSubclass, nuint dwRefData)
    {
        if (uMsg == WM_COMMAND)
        {
            // HIWORD(wParam) == 0 means the message is from a menu item
            int hiWord = (int)((wParam >> 16) & 0xFFFF);
            if (hiWord == 0)
            {
                int flatId = (int)(wParam & 0xFFFF);
                if (TryDecode(flatId, out var menuName, out var itemId))
                {
                    _commandQueue.Add((menuName, itemId));
                    return 0; // handled
                }
            }
        }
        return DefSubclassProc(hWnd, uMsg, wParam, lParam);
    }

    private bool TryDecode(int flatId, out string menuName, out int itemId)
    {
        // Walk bases from highest to lowest — must be kept in sync with _bases.
        if (flatId >= 1500) { menuName = "UITheme"; itemId = flatId - 1500; return true; }
        if (flatId >= 1400) { menuName = "Session"; itemId = flatId - 1400; return true; }
        if (flatId >= 1300) { menuName = "GridType"; itemId = flatId - 1300; return true; }
        if (flatId >= 1200) { menuName = "View"; itemId = flatId - 1200; return true; }
        if (flatId >= 1100) { menuName = "Edit"; itemId = flatId - 1100; return true; }
        if (flatId >= 1000) { menuName = "File"; itemId = flatId - 1000; return true; }
        menuName = ""; itemId = 0; return false;
    }
}
