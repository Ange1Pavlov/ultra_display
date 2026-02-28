Tools Folder
============

CPU runtime binaries and sensor helper runtimes.

Used by CPU path:
- `lhm_runtime\LibreHardwareMonitorLib.dll` (library fallback)
- `ohm_runtime\OpenHardwareMonitor\OpenHardwareMonitor.exe` (background agent source)

First run note:
- Windows can show an allow/approval prompt for the monitor runtime.
- Allow it once; afterward it runs minimized in background.

Runtime behavior:
1. Try `cpu-temp-agent.ps1` cache (`cache\cpu_temp_agent.json`)
2. Fallback to bundled `lhm_runtime\LibreHardwareMonitorLib.dll`
3. Fallback to WMI thermal zone
4. If all unavailable, CPU temp is `null`
