# Disk Speed Test Utility

A PowerShell 7 utility for testing disk read/write speeds with a Windows Forms GUI.

## Features

- **Sequential Read/Write Tests** - Tests throughput using 1MB blocks
- **Random 4K Tests** - Simulates real-world performance with random 4KB operations (optional)
- **Windows Forms GUI** - Easy drive selection and configuration
- **Accurate Results** - Uses unbuffered I/O to bypass Windows cache
- **Non-destructive** - Uses temporary files that are automatically cleaned up

## Requirements

- Windows OS (Tested on Windows 11 and Windows Server 2025)
- PowerShell 7.0 or later

## Installation

1. Download `PSDiskSpeed.ps1`
2. If the script is blocked, run this command first:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   ```
3. Run the script:
   ```powershell
   .\PSDiskSpeed.ps1
   ```

> **Note:** Administrator mode is not required.

## Usage

1. Launch the script
2. Select a drive from the list
3. Choose test file size (50 MB - 1000 MB)
4. Optionally enable **Extended / Real-Life Tests** for Random 4K benchmarks
5. Click **Start Test**

## Test Types

| Test | Description | Best For |
|------|-------------|----------|
| Sequential Write (1MB) | Large continuous writes | File copy performance |
| Sequential Read (1MB) | Large continuous reads | File copy performance |
| Random 4K Write | Small random writes | OS/application responsiveness |
| Random 4K Read | Small random reads | OS/application responsiveness |

## Sample Results

**USB 3.0 Flash Drive:**
- Sequential Write: ~40 MB/s
- Sequential Read: ~150 MB/s
- Random 4K Write: ~0.5 MB/s (125 IOPS)
- Random 4K Read: ~5 MB/s (1,300 IOPS)

**NVMe SSD:**
- Sequential Write: ~1,100 MB/s
- Sequential Read: ~2,000 MB/s
- Random 4K Write: ~50 MB/s (12,000 IOPS)
- Random 4K Read: ~28 MB/s (7,000 IOPS)

## Author

**Michael DALLA RIVA**  
[www.yourwebsite.com](https://lafrenchaieti.com/)

## License

Free to use and modify.
