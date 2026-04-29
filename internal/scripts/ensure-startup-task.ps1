param(
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$scriptsRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptsRoot '..\..'))
$appCmd = Join-Path $projectRoot 'app.cmd'
$startupCmd = Join-Path $projectRoot 'startup.cmd'
$taskName = 'UltraDisplayPanel Startup'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$runValueName = 'UltraDisplayPanel'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

if (-not (Test-Path $appCmd)) {
    throw "Missing launcher: $appCmd"
}
if (-not (Test-Path $startupCmd)) {
    throw "Missing startup launcher: $startupCmd"
}

$mode = 'scheduled-task'
try {
    $action = New-ScheduledTaskAction -Execute $env:ComSpec -Argument ('/c "{0}"' -f $startupCmd)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
    $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Auto start Ultra Display Panel at user logon and restart display services cleanly.'
    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
    Remove-ItemProperty -Path $runKey -Name $runValueName -ErrorAction SilentlyContinue
} catch {
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        # Keep the already-registered startup task and avoid creating a second startup path.
        $mode = 'existing-scheduled-task'
        Remove-ItemProperty -Path $runKey -Name $runValueName -ErrorAction SilentlyContinue
    } else {
        # Fallback for environments where scheduled tasks cannot be created.
        # startup.cmd delegates to app.cmd -Startup and will still request elevation when needed.
        $mode = 'run-key'
        if (-not (Test-Path $runKey)) {
            New-Item -Path $runKey -Force | Out-Null
        }
        Set-ItemProperty -Path $runKey -Name $runValueName -Value ('"{0}"' -f $startupCmd)
    }
}

if (-not $Quiet) {
    Write-Host ("Startup ensured via {0}" -f $mode)
}

