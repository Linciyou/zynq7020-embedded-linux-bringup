if (-not ('ZynqDiskIO' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class ZynqDiskIO {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string path, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool WriteFile(SafeFileHandle handle, byte[] data, uint count,
        out uint written, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool ReadFile(SafeFileHandle handle, IntPtr data, uint count,
        out uint read, IntPtr overlapped);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool FlushFileBuffers(SafeFileHandle handle);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool DeviceIoControl(SafeFileHandle handle, uint code,
        IntPtr input, uint inputSize, IntPtr output, uint outputSize,
        out uint returned, IntPtr overlapped);
    public static void Control(FileStream volume, uint code) {
        uint returned;
        if (!DeviceIoControl(volume.SafeFileHandle, code, IntPtr.Zero, 0,
                IntPtr.Zero, 0, out returned, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public static bool Equal(byte[] a, byte[] b, int count) {
        for (int i=0; i<count; i++) if (a[i] != b[i]) return false;
        return true;
    }
    public static SafeFileHandle OpenDisk(string path, bool write) {
        var handle = CreateFile(path, write ? 0xC0000000u : 0x80000000u,
            3, IntPtr.Zero, 3, write ? 0x80000000u : 0u, IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
        return handle;
    }
    public static void Write(SafeFileHandle handle, byte[] data, int count) {
        uint written;
        if (!WriteFile(handle, data, (uint)count, out written, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        if (written != count) throw new IOException("Short physical-disk write");
    }
    public static void ReadExact(SafeFileHandle handle, byte[] data, int count) {
        var pinned = GCHandle.Alloc(data, GCHandleType.Pinned);
        try {
            int offset = 0;
            while (offset < count) {
                uint read;
                if (!ReadFile(handle, IntPtr.Add(pinned.AddrOfPinnedObject(), offset),
                        (uint)(count - offset), out read, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if (read == 0) throw new EndOfStreamException("Short physical-disk read");
                offset += (int)read;
            }
        } finally { pinned.Free(); }
    }
    public static void Flush(SafeFileHandle handle) {
        if (!FlushFileBuffers(handle)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
}

function Get-ConfirmedUsbDisk {
    param([int]$Number, [string]$Serial, [uint64]$Size)
    $disk = Get-Disk -Number $Number -ErrorAction Stop
    if ($disk.IsBoot -or $disk.IsSystem -or $disk.BusType -ne 'USB') {
        throw "Disk $Number is not a non-system USB device"
    }
    if ($Serial -and $disk.SerialNumber.Trim() -ne $Serial.Trim()) { throw 'Disk serial number changed' }
    if ($Size -and $disk.Size -ne $Size) { throw 'Disk size changed' }
    return $disk
}
