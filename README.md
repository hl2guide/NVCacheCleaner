# NVCacheCleaner
A PowerShell script to clean up NVIDIA and shader cache files in Windows 10/11.

# How to Run

### Run the command below in PowerShell (Recommended)

```ps1
iwr "https://raw.githubusercontent.com/ltx0101/NVCacheCleaner/main/NVCacheCleaner.ps1" -OutFile "$env:TEMP\NVCacheCleaner.ps1"; powershell -ExecutionPolicy Bypass -File "$env:TEMP\NVCacheCleaner.ps1" -Force
```
## Or

### Download the file and run it (Only if you want to save and rerun later)

```ps1
iwr "https://raw.githubusercontent.com/ltx0101/NVCacheCleaner/main/NVCacheCleaner.ps1" -OutFile "$env:USERPROFILE\Desktop\NVCacheCleaner.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\NVCacheCleaner.ps1"
```
