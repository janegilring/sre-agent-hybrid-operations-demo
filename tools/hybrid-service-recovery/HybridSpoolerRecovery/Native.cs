using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading.Tasks;

namespace HybridSpoolerRecovery {
    public static class Native {
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr OpenSCManager(string machine, string database, uint access);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr OpenService(IntPtr manager, string name, uint access);
        [DllImport("advapi32.dll", SetLastError=true)]
        static extern bool CloseServiceHandle(IntPtr handle);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool QueryServiceConfig(IntPtr service, IntPtr config, uint size, out uint needed);
        [DllImport("advapi32.dll", SetLastError=true)]
        static extern bool QueryServiceStatus(IntPtr service, out Status status);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern bool StartService(IntPtr service, uint count, IntPtr arguments);
        [StructLayout(LayoutKind.Sequential)]
        struct Status { public uint Type, State, Controls, ExitCode, SpecificExitCode, CheckPoint, WaitHint; }
        public sealed class Snapshot { public string State; public bool Disabled; }
        static IntPtr Open(uint access) {
            IntPtr manager = OpenSCManager(null, null, 1); // SC_MANAGER_CONNECT, local only.
            if (manager == IntPtr.Zero) throw new Win32Exception();
            try {
                IntPtr service = OpenService(manager, "Spooler", access);
                if (service == IntPtr.Zero) throw new Win32Exception();
                return service;
            } finally { CloseServiceHandle(manager); }
        }
        public static Task<Snapshot> BeginRead() { return Task.Factory.StartNew<Snapshot>(Read); }
        static Snapshot Read() {
            IntPtr service = Open(0x5); // QUERY_CONFIG | QUERY_STATUS.
            IntPtr buffer = IntPtr.Zero;
            try {
                uint needed;
                if (QueryServiceConfig(service, IntPtr.Zero, 0, out needed) ||
                    Marshal.GetLastWin32Error() != 122) throw new Win32Exception();
                buffer = Marshal.AllocHGlobal(checked((int)needed));
                if (!QueryServiceConfig(service, buffer, needed, out needed)) throw new Win32Exception();
                bool disabled = Marshal.ReadInt32(buffer, 4) == 4; // QUERY_SERVICE_CONFIG.dwStartType.
                Status status;
                if (!QueryServiceStatus(service, out status)) throw new Win32Exception();
                string[] states = { "Unknown", "Stopped", "StartPending", "StopPending", "Running",
                    "ContinuePending", "PausePending", "Paused" };
                return new Snapshot { State = status.State < states.Length ? states[status.State] : "Unknown",
                    Disabled = disabled };
            } finally {
                if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
                CloseServiceHandle(service);
            }
        }
        public static Task BeginStart() {
            // SCM may block StartService for 30 seconds. Do not block the PowerShell deadline.
            return Task.Factory.StartNew(delegate {
                IntPtr service = Open(0x10); // START only; no arguments, no dependency enumeration.
                try {
                    if (!StartService(service, 0, IntPtr.Zero)) {
                        int error = Marshal.GetLastWin32Error();
                        if (error != 1056) throw new Win32Exception(error); // Already running: verify separately.
                    }
                } finally { CloseServiceHandle(service); }
            });
        }
    }
}
