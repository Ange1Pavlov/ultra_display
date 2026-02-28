Tools Folder
============

CPU sensor helper runtimes (downloaded on demand).

Used by CPU path:
- `lhm_runtime\LibreHardwareMonitorLib.dll` (library fallback)
- `ohm_runtime\OpenHardwareMonitor\OpenHardwareMonitor.exe` (background agent source)

Official sources:
- LibreHardwareMonitor: `https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases`
- OpenHardwareMonitor: `https://openhardwaremonitor.org/downloads/`

Install:
- `powershell -ExecutionPolicy Bypass -File internal\scripts\install-tools.ps1`
- `start-display.ps1` also runs this automatically before starting services.
- These binaries are local runtime dependencies and should not be committed to git.

First run note:
- Windows can show an allow/approval prompt for the monitor runtime.
- Allow it once; afterward it runs minimized in background.

Runtime behavior:
1. Try `cpu-temp-agent.ps1` cache (`cache\cpu_temp_agent.json`)
2. Fallback to `lhm_runtime\LibreHardwareMonitorLib.dll`
3. Fallback to WMI thermal zone
4. If all unavailable, CPU temp is `null`
