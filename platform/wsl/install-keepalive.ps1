<#
.SYNOPSIS
    Registers (or removes) the Perpetua WSL keep-alive at Windows logon.

.DESCRIPTION
    Copies keepalive.ps1 to %LOCALAPPDATA%\Perpetua and creates a hidden-window shortcut
    in the user's Startup folder, then starts it immediately. Run from PowerShell on the
    Windows side, no administrator rights required.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install-keepalive.ps1 -Distro Ubuntu-24.04

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install-keepalive.ps1 -Uninstall
#>
param(
    [string]$Distro = "",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$home_dir = Join-Path $env:LOCALAPPDATA "Perpetua"
$script = Join-Path $home_dir "keepalive.ps1"
$startup = [Environment]::GetFolderPath("Startup")
$shortcut = Join-Path $startup "Perpetua WSL keep-alive.lnk"

if ($Uninstall) {
    Remove-Item -Force -ErrorAction SilentlyContinue $shortcut
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*Perpetua\keepalive.ps1*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $home_dir
    Write-Host "Perpetua WSL keep-alive removed."
    exit 0
}

New-Item -ItemType Directory -Force -Path $home_dir | Out-Null
Copy-Item -Force (Join-Path $PSScriptRoot "keepalive.ps1") $script

$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
if ($Distro) { $arguments += " -Distro `"$Distro`"" }

$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
$link.TargetPath = "powershell.exe"
$link.Arguments = $arguments
$link.WindowStyle = 7
$link.Description = "Keeps WSL running for Perpetua"
$link.Save()

Start-Process powershell.exe -ArgumentList $arguments -WindowStyle Hidden
Write-Host "Perpetua WSL keep-alive installed and started."
Write-Host "Recommended in %USERPROFILE%\.wslconfig, then run: wsl --shutdown"
Write-Host "  [wsl2]"
Write-Host "  vmIdleTimeout=-1"
Write-Host "  [general]"
Write-Host "  instanceIdleTimeout=-1"
