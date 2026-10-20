<#
.SYNOPSIS
    Keeps a WSL distribution running so Perpetua's systemd timer keeps firing.

.DESCRIPTION
    Windows shuts a WSL distribution down once no WSL client is attached, which stops
    every systemd timer inside it. This script holds one invisible client open
    (`sleep infinity`) and restarts it if it ever exits. A global mutex guarantees a
    single instance per Windows session.

    Installed at logon by install-keepalive.ps1. Documentation:
    https://koffih.github.io/perpetua/guides/wsl/

.PARAMETER Distro
    The WSL distribution to keep alive. Defaults to the default distribution.
#>
param(
    [string]$Distro = ""
)

$ErrorActionPreference = "Stop"
$mutex = New-Object System.Threading.Mutex($false, "Global\PerpetuaWslKeepalive")
if (-not $mutex.WaitOne(0)) { exit 0 }   # already running

$wslArgs = @()
if ($Distro) { $wslArgs += @("-d", $Distro) }
$wslArgs += @("--exec", "/bin/sleep", "infinity")

try {
    while ($true) {
        & wsl.exe @wslArgs
        Start-Sleep -Seconds 30
    }
}
finally {
    $mutex.ReleaseMutex()
}
