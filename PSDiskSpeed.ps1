<#
.SYNOPSIS
    Disk Speed Test Utility for PowerShell 7
.DESCRIPTION
    Tests read and write speeds of selected disk drives using safe temporary file operations.
    Uses Windows Forms for disk selection GUI.
    Supports basic sequential tests and extended real-life tests (random 4K).
.NOTES
    Author:      Michael DALLA RIVA with the help of some AI
    Website:     https://lafrenchaieti.com/
    Requires:    PowerShell 7+, Windows OS (Tested on Windows 11 and Windows Server 2025)
    Date:        08-Jan-2026
    Version:     1.0
    
    This script performs non-destructive speed tests using temporary files.
    Running PowerShell in Administrator mode is not necessary.
    
    If the script won't run due to security restrictions, run this first:
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
#>

#Requires -Version 7.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Bypasses Windows cache
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class NativeFileIO
{
    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint FILE_SHARE_READ = 0x00000001;
    public const uint FILE_SHARE_WRITE = 0x00000002;
    public const uint CREATE_ALWAYS = 2;
    public const uint OPEN_EXISTING = 3;
    public const uint FILE_FLAG_NO_BUFFERING = 0x20000000;
    public const uint FILE_FLAG_WRITE_THROUGH = 0x80000000;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);
}
"@

$TestFileSizeMB = 100 # Size of test file in MB
$BlockSizeKB = 1024 # Block size for sequential operations (1 MB)
$Random4KOperations = 1000 # Number of random 4K operations

function Get-AvailableDrives {
    $driveInfo = @()
    
    $systemDrives = [System.IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and 
        $_.DriveType -in @([System.IO.DriveType]::Fixed, [System.IO.DriveType]::Removable) -and
        $_.AvailableFreeSpace -gt ($TestFileSizeMB * 1MB * 2)
    }
    
    $driveInfo = foreach ($driveObj in $systemDrives) {
        [PSCustomObject]@{
            Letter      = $driveObj.Name.TrimEnd(':\')
            Root        = $driveObj.RootDirectory.FullName
            Label       = if ($driveObj.VolumeLabel) { $driveObj.VolumeLabel } else { "Local Disk" }
            DriveType   = $driveObj.DriveType
            TotalSizeGB = [math]::Round($driveObj.TotalSize / 1GB, 2)
            FreeSpaceGB = [math]::Round($driveObj.AvailableFreeSpace / 1GB, 2)
            DisplayName = "$($driveObj.Name.TrimEnd('\')) [$($driveObj.VolumeLabel)] - $([math]::Round($driveObj.AvailableFreeSpace / 1GB, 2)) GB Free"
        }
    }
    
    return $driveInfo
}

function Show-DriveSelectionForm {
    param(
        [array]$Drives
    )
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Disk Speed Test - Select Drive"
    $form.Size = New-Object System.Drawing.Size(500, 450)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(450, 30)
    $titleLabel.Text = "Disk Read/Write Speed Test"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)
    
    $descLabel = New-Object System.Windows.Forms.Label
    $descLabel.Location = New-Object System.Drawing.Point(20, 55)
    $descLabel.Size = New-Object System.Drawing.Size(450, 40)
    $descLabel.Text = "Select a drive to test. A temporary file will be created and deleted after the test completes."
    $descLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.Controls.Add($descLabel)
    
    $selectLabel = New-Object System.Windows.Forms.Label
    $selectLabel.Location = New-Object System.Drawing.Point(20, 100)
    $selectLabel.Size = New-Object System.Drawing.Size(100, 20)
    $selectLabel.Text = "Select Drive:"
    $selectLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($selectLabel)
    
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(20, 125)
    $listBox.Size = New-Object System.Drawing.Size(445, 100)
    $listBox.Font = New-Object System.Drawing.Font("Consolas", 10)
    
    foreach ($drive in $Drives) {
        $listBox.Items.Add($drive.DisplayName) | Out-Null
    }
    
    if ($listBox.Items.Count -gt 0) {
        $listBox.SelectedIndex = 0
    }
    $form.Controls.Add($listBox)
    
    $sizeLabel = New-Object System.Windows.Forms.Label
    $sizeLabel.Location = New-Object System.Drawing.Point(20, 235)
    $sizeLabel.Size = New-Object System.Drawing.Size(100, 20)
    $sizeLabel.Text = "Test File Size:"
    $sizeLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($sizeLabel)
    
    $sizeCombo = New-Object System.Windows.Forms.ComboBox
    $sizeCombo.Location = New-Object System.Drawing.Point(130, 232)
    $sizeCombo.Size = New-Object System.Drawing.Size(120, 25)
    $sizeCombo.DropDownStyle = "DropDownList"
    $sizeCombo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $sizeCombo.Items.AddRange(@("50 MB", "100 MB", "250 MB", "500 MB", "1000 MB"))
    $sizeCombo.SelectedIndex = 1
    $form.Controls.Add($sizeCombo)
    
    $extendedCheckbox = New-Object System.Windows.Forms.CheckBox
    $extendedCheckbox.Location = New-Object System.Drawing.Point(20, 270)
    $extendedCheckbox.Size = New-Object System.Drawing.Size(250, 25)
    $extendedCheckbox.Text = "Extended / Real-Life Tests"
    $extendedCheckbox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($extendedCheckbox)
    
    $extendedDescLabel = New-Object System.Windows.Forms.Label
    $extendedDescLabel.Location = New-Object System.Drawing.Point(40, 295)
    $extendedDescLabel.Size = New-Object System.Drawing.Size(420, 40)
    $extendedDescLabel.Text = "Includes Random 4K read/write tests (simulates real-world usage).`nThis will take significantly longer to complete."
    $extendedDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $extendedDescLabel.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($extendedDescLabel)
    
    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Location = New-Object System.Drawing.Point(280, 360)
    $startButton.Size = New-Object System.Drawing.Size(90, 35)
    $startButton.Text = "Start Test"
    $startButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $startButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $startButton.ForeColor = [System.Drawing.Color]::White
    $startButton.FlatStyle = "Flat"
    $startButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $startButton
    $form.Controls.Add($startButton)
    
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(380, 360)
    $cancelButton.Size = New-Object System.Drawing.Size(85, 35)
    $cancelButton.Text = "Cancel"
    $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $cancelButton
    $form.Controls.Add($cancelButton)
    
    $authorLabel = New-Object System.Windows.Forms.Label
    $authorLabel.Location = New-Object System.Drawing.Point(20, 365)
    $authorLabel.Size = New-Object System.Drawing.Size(200, 15)
    $authorLabel.Text = "By Michael DALLA RIVA"
    $authorLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $authorLabel.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($authorLabel)
    
    $linkLabel = New-Object System.Windows.Forms.LinkLabel
    $linkLabel.Location = New-Object System.Drawing.Point(20, 380)
    $linkLabel.Size = New-Object System.Drawing.Size(200, 15)
    $linkLabel.Text = "https://lafrenchaieti.com/"
    $linkLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $linkLabel.LinkColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
    $linkLabel.Add_LinkClicked({
        Start-Process "https://lafrenchaieti.com/"
    })
    $form.Controls.Add($linkLabel)
    
    $result = $form.ShowDialog()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedIndex -ge 0) {
        $selectedSize = [int]($sizeCombo.SelectedItem -replace ' MB', '')
        return @{
            Drive         = $Drives[$listBox.SelectedIndex]
            TestSize      = $selectedSize
            ExtendedTests = $extendedCheckbox.Checked
        }
    }
    
    return $null
}

function Test-WriteSpeed {
    param(
        [string]$TestPath,
        [int]$FileSizeMB,
        [int]$BlockSizeKB
    )
    
    $blockSize = $BlockSizeKB * 1KB
    $totalBlocks = ($FileSizeMB * 1MB) / $blockSize
    $randomData = New-Object byte[] $blockSize
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    
    try {
        # Open file with FILE_FLAG_NO_BUFFERING and FILE_FLAG_WRITE_THROUGH
        $flags = [NativeFileIO]::FILE_FLAG_NO_BUFFERING -bor [NativeFileIO]::FILE_FLAG_WRITE_THROUGH
        
        $fileHandle = [NativeFileIO]::CreateFile(
            $TestPath,
            [NativeFileIO]::GENERIC_WRITE,
            0,
            [IntPtr]::Zero,
            [NativeFileIO]::CREATE_ALWAYS,
            $flags,
            [IntPtr]::Zero
        )
        
        if ($fileHandle.IsInvalid) {
            throw "Failed to open file with unbuffered access. Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        
        $fileStream = [System.IO.FileStream]::new($fileHandle, [System.IO.FileAccess]::Write, $blockSize)
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        for ($i = 0; $i -lt $totalBlocks; $i++) {
            $rng.GetBytes($randomData)
            $fileStream.Write($randomData, 0, $blockSize)
            
            if ($i % 10 -eq 0) {
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        
        $fileStream.Flush()
        $stopwatch.Stop()
        $fileStream.Close()
        $fileHandle.Close()
        $rng.Dispose()
        
        $totalBytes = $FileSizeMB * 1MB
        $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
        $speedMBps = [math]::Round($totalBytes / 1MB / $elapsedSeconds, 2)
        
        return @{
            Success      = $true
            SpeedMBps    = $speedMBps
            ElapsedMs    = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 0)
            BytesWritten = $totalBytes
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Test-ReadSpeed {

    param(
        [string]$TestPath,
        [int]$BlockSizeKB
    )
    
    $blockSize = $BlockSizeKB * 1KB
    
    try {
        $fileHandle = [NativeFileIO]::CreateFile(
            $TestPath,
            [NativeFileIO]::GENERIC_READ,
            [NativeFileIO]::FILE_SHARE_READ,
            [IntPtr]::Zero,
            [NativeFileIO]::OPEN_EXISTING,
            [NativeFileIO]::FILE_FLAG_NO_BUFFERING,
            [IntPtr]::Zero
        )
        
        if ($fileHandle.IsInvalid) {
            throw "Failed to open file with unbuffered access. Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        
        $fileStream = [System.IO.FileStream]::new($fileHandle, [System.IO.FileAccess]::Read, $blockSize)
        $buffer = New-Object byte[] $blockSize
        
        $totalBytesRead = 0
        $blockCount = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        while (($bytesRead = $fileStream.Read($buffer, 0, $blockSize)) -gt 0) {
            $totalBytesRead += $bytesRead
            $blockCount++
            
            if ($blockCount % 10 -eq 0) {
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        
        $stopwatch.Stop()
        $fileStream.Close()
        $fileHandle.Close()
        
        $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
        $speedMBps = [math]::Round($totalBytesRead / 1MB / $elapsedSeconds, 2)
        
        return @{
            Success   = $true
            SpeedMBps = $speedMBps
            ElapsedMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 0)
            BytesRead = $totalBytesRead
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Test-Random4KWrite {

    param(
        [string]$TestPath,
        [int]$Operations = 1000
    )
    
    $blockSize = 4096  # 4KB aligned for unbuffered I/O
    $randomData = New-Object byte[] $blockSize
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    
    try {
        $fileInfo = [System.IO.FileInfo]::new($TestPath)
        $fileSize = $fileInfo.Length
        $maxPosition = [math]::Floor($fileSize / $blockSize) - 1
        
        if ($maxPosition -lt $Operations) {
            $Operations = [math]::Max(100, $maxPosition)
        }
        
        $random = [System.Random]::new()
        $positions = @()
        for ($i = 0; $i -lt $Operations; $i++) {
            $positions += $random.Next(0, $maxPosition) * $blockSize
        }
        
        $flags = [NativeFileIO]::FILE_FLAG_NO_BUFFERING -bor [NativeFileIO]::FILE_FLAG_WRITE_THROUGH
        
        $fileHandle = [NativeFileIO]::CreateFile(
            $TestPath,
            [NativeFileIO]::GENERIC_WRITE,
            0,
            [IntPtr]::Zero,
            [NativeFileIO]::OPEN_EXISTING,
            $flags,
            [IntPtr]::Zero
        )
        
        if ($fileHandle.IsInvalid) {
            throw "Failed to open file. Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        
        $fileStream = [System.IO.FileStream]::new($fileHandle, [System.IO.FileAccess]::Write, $blockSize)
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $opCount = 0
        foreach ($pos in $positions) {
            $fileStream.Seek($pos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $rng.GetBytes($randomData)
            $fileStream.Write($randomData, 0, $blockSize)
            
            $opCount++
            if ($opCount % 50 -eq 0) {
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        
        $fileStream.Flush()
        $stopwatch.Stop()
        $fileStream.Close()
        $fileHandle.Close()
        $rng.Dispose()
        
        $totalBytes = $Operations * $blockSize
        $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
        $iops = [math]::Round($Operations / $elapsedSeconds, 0)
        $speedMBps = [math]::Round($totalBytes / 1MB / $elapsedSeconds, 2)
        
        return @{
            Success   = $true
            IOPS      = $iops
            SpeedMBps = $speedMBps
            ElapsedMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 0)
            Operations = $Operations
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Test-Random4KRead {

    param(
        [string]$TestPath,
        [int]$Operations = 1000
    )
    
    $blockSize = 4096
    
    try {
        $fileInfo = [System.IO.FileInfo]::new($TestPath)
        $fileSize = $fileInfo.Length
        $maxPosition = [math]::Floor($fileSize / $blockSize) - 1
        
        if ($maxPosition -lt $Operations) {
            $Operations = [math]::Max(100, $maxPosition)
        }
        
        $random = [System.Random]::new()
        $positions = @()
        for ($i = 0; $i -lt $Operations; $i++) {
            $positions += $random.Next(0, $maxPosition) * $blockSize
        }
        
        $fileHandle = [NativeFileIO]::CreateFile(
            $TestPath,
            [NativeFileIO]::GENERIC_READ,
            [NativeFileIO]::FILE_SHARE_READ,
            [IntPtr]::Zero,
            [NativeFileIO]::OPEN_EXISTING,
            [NativeFileIO]::FILE_FLAG_NO_BUFFERING,
            [IntPtr]::Zero
        )
        
        if ($fileHandle.IsInvalid) {
            throw "Failed to open file. Error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        
        $fileStream = [System.IO.FileStream]::new($fileHandle, [System.IO.FileAccess]::Read, $blockSize)
        $buffer = New-Object byte[] $blockSize
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $opCount = 0
        foreach ($pos in $positions) {
            $fileStream.Seek($pos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $fileStream.Read($buffer, 0, $blockSize) | Out-Null
            
            $opCount++
            if ($opCount % 50 -eq 0) {
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        
        $stopwatch.Stop()
        $fileStream.Close()
        $fileHandle.Close()
        
        $totalBytes = $Operations * $blockSize
        $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
        $iops = [math]::Round($Operations / $elapsedSeconds, 0)
        $speedMBps = [math]::Round($totalBytes / 1MB / $elapsedSeconds, 2)
        
        return @{
            Success   = $true
            IOPS      = $iops
            SpeedMBps = $speedMBps
            ElapsedMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 0)
            Operations = $Operations
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Show-ResultsForm {
    param(
        [PSCustomObject]$DriveInfo,
        [hashtable]$WriteResult,
        [hashtable]$ReadResult,
        [hashtable]$Random4KWriteResult,
        [hashtable]$Random4KReadResult,
        [int]$TestSizeMB,
        [bool]$ExtendedTests
    )
    
    $formHeight = if ($ExtendedTests) { 580 } else { 420 }
    $panelHeight = if ($ExtendedTests) { 360 } else { 200 }
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Disk Speed Test - Results"
    $form.Size = New-Object System.Drawing.Size(450, $formHeight)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(400, 30)
    $titleLabel.Text = "Speed Test Results"
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($titleLabel)
    
    $driveLabel = New-Object System.Windows.Forms.Label
    $driveLabel.Location = New-Object System.Drawing.Point(20, 55)
    $driveLabel.Size = New-Object System.Drawing.Size(400, 25)
    $driveLabel.Text = "Drive: $($DriveInfo.Root) [$($DriveInfo.Label)] - $($DriveInfo.DriveType)"
    $driveLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($driveLabel)
    
    $sizeInfoLabel = New-Object System.Windows.Forms.Label
    $sizeInfoLabel.Location = New-Object System.Drawing.Point(20, 80)
    $sizeInfoLabel.Size = New-Object System.Drawing.Size(400, 25)
    $sizeInfoLabel.Text = "Test File Size: $TestSizeMB MB"
    $sizeInfoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $form.Controls.Add($sizeInfoLabel)
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(20, 115)
    $panel.Size = New-Object System.Drawing.Size(395, $panelHeight)
    $panel.BorderStyle = "FixedSingle"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $form.Controls.Add($panel)
    
    $yPos = 15
    
    $seqWriteHeader = New-Object System.Windows.Forms.Label
    $seqWriteHeader.Location = New-Object System.Drawing.Point(15, $yPos)
    $seqWriteHeader.Size = New-Object System.Drawing.Size(180, 20)
    $seqWriteHeader.Text = "Sequential Write (1MB)"
    $seqWriteHeader.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($seqWriteHeader)
    
    $yPos += 22
    $seqWriteValue = New-Object System.Windows.Forms.Label
    $seqWriteValue.Location = New-Object System.Drawing.Point(15, $yPos)
    $seqWriteValue.Size = New-Object System.Drawing.Size(360, 28)
    if ($WriteResult.Success) {
        $seqWriteValue.Text = "$($WriteResult.SpeedMBps) MB/s"
        $seqWriteValue.ForeColor = [System.Drawing.Color]::FromArgb(0, 150, 0)
    } else {
        $seqWriteValue.Text = "Error: $($WriteResult.Error)"
        $seqWriteValue.ForeColor = [System.Drawing.Color]::Red
    }
    $seqWriteValue.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($seqWriteValue)
    
    $yPos += 35
    
    $seqReadHeader = New-Object System.Windows.Forms.Label
    $seqReadHeader.Location = New-Object System.Drawing.Point(15, $yPos)
    $seqReadHeader.Size = New-Object System.Drawing.Size(180, 20)
    $seqReadHeader.Text = "Sequential Read (1MB)"
    $seqReadHeader.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($seqReadHeader)
    
    $yPos += 22
    $seqReadValue = New-Object System.Windows.Forms.Label
    $seqReadValue.Location = New-Object System.Drawing.Point(15, $yPos)
    $seqReadValue.Size = New-Object System.Drawing.Size(360, 28)
    if ($ReadResult.Success) {
        $seqReadValue.Text = "$($ReadResult.SpeedMBps) MB/s"
        $seqReadValue.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    } else {
        $seqReadValue.Text = "Error: $($ReadResult.Error)"
        $seqReadValue.ForeColor = [System.Drawing.Color]::Red
    }
    $seqReadValue.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($seqReadValue)
    
    $yPos += 40
    
    if ($ExtendedTests) {
        $separator = New-Object System.Windows.Forms.Label
        $separator.Location = New-Object System.Drawing.Point(15, $yPos)
        $separator.Size = New-Object System.Drawing.Size(365, 2)
        $separator.BorderStyle = "Fixed3D"
        $panel.Controls.Add($separator)
        
        $yPos += 15
        
        $rand4KWriteHeader = New-Object System.Windows.Forms.Label
        $rand4KWriteHeader.Location = New-Object System.Drawing.Point(15, $yPos)
        $rand4KWriteHeader.Size = New-Object System.Drawing.Size(180, 20)
        $rand4KWriteHeader.Text = "Random 4K Write"
        $rand4KWriteHeader.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $panel.Controls.Add($rand4KWriteHeader)
        
        $yPos += 22
        $rand4KWriteValue = New-Object System.Windows.Forms.Label
        $rand4KWriteValue.Location = New-Object System.Drawing.Point(15, $yPos)
        $rand4KWriteValue.Size = New-Object System.Drawing.Size(360, 28)
        if ($Random4KWriteResult.Success) {
            $rand4KWriteValue.Text = "$($Random4KWriteResult.SpeedMBps) MB/s  |  $($Random4KWriteResult.IOPS) IOPS"
            $rand4KWriteValue.ForeColor = [System.Drawing.Color]::FromArgb(180, 100, 0)
        } else {
            $rand4KWriteValue.Text = "Error: $($Random4KWriteResult.Error)"
            $rand4KWriteValue.ForeColor = [System.Drawing.Color]::Red
        }
        $rand4KWriteValue.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        $panel.Controls.Add($rand4KWriteValue)
        
        $yPos += 35
        
        $rand4KReadHeader = New-Object System.Windows.Forms.Label
        $rand4KReadHeader.Location = New-Object System.Drawing.Point(15, $yPos)
        $rand4KReadHeader.Size = New-Object System.Drawing.Size(180, 20)
        $rand4KReadHeader.Text = "Random 4K Read"
        $rand4KReadHeader.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $panel.Controls.Add($rand4KReadHeader)
        
        $yPos += 22
        $rand4KReadValue = New-Object System.Windows.Forms.Label
        $rand4KReadValue.Location = New-Object System.Drawing.Point(15, $yPos)
        $rand4KReadValue.Size = New-Object System.Drawing.Size(360, 28)
        if ($Random4KReadResult.Success) {
            $rand4KReadValue.Text = "$($Random4KReadResult.SpeedMBps) MB/s  |  $($Random4KReadResult.IOPS) IOPS"
            $rand4KReadValue.ForeColor = [System.Drawing.Color]::FromArgb(128, 0, 128)
        } else {
            $rand4KReadValue.Text = "Error: $($Random4KReadResult.Error)"
            $rand4KReadValue.ForeColor = [System.Drawing.Color]::Red
        }
        $rand4KReadValue.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
        $panel.Controls.Add($rand4KReadValue)
    }
    
    $closeButton = New-Object System.Windows.Forms.Button
    $buttonY = if ($ExtendedTests) { 495 } else { 335 }
    $closeButton.Location = New-Object System.Drawing.Point(325, $buttonY)
    $closeButton.Size = New-Object System.Drawing.Size(90, 35)
    $closeButton.Text = "Close"
    $closeButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $closeButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $closeButton
    $form.Controls.Add($closeButton)
    
    $authorY = $buttonY + 5
    $authorLabel = New-Object System.Windows.Forms.Label
    $authorLabel.Location = New-Object System.Drawing.Point(20, $authorY)
    $authorLabel.Size = New-Object System.Drawing.Size(200, 15)
    $authorLabel.Text = "By Michael DALLA RIVA"
    $authorLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $authorLabel.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($authorLabel)
    
    $linkY = $buttonY + 20
    $linkLabel = New-Object System.Windows.Forms.LinkLabel
    $linkLabel.Location = New-Object System.Drawing.Point(20, $linkY)
    $linkLabel.Size = New-Object System.Drawing.Size(200, 15)
    $linkLabel.Text = "https://lafrenchaieti.com/"
    $linkLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $linkLabel.LinkColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
    $linkLabel.Add_LinkClicked({
        Start-Process "https://lafrenchaieti.com/"
    })
    $form.Controls.Add($linkLabel)
    
    $form.ShowDialog() | Out-Null
}

function Show-ProgressForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Disk Speed Test - Testing..."
    $form.Size = New-Object System.Drawing.Size(400, 150)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ControlBox = $false
    $form.BackColor = [System.Drawing.Color]::White
    
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(20, 30)
    $statusLabel.Size = New-Object System.Drawing.Size(350, 30)
    $statusLabel.Text = "Preparing test..."
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $statusLabel.Name = "StatusLabel"
    $form.Controls.Add($statusLabel)
    
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 70)
    $progressBar.Size = New-Object System.Drawing.Size(350, 25)
    $progressBar.Style = "Marquee"
    $progressBar.MarqueeAnimationSpeed = 30
    $form.Controls.Add($progressBar)
    
    return $form
}

# Main
try {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║           " -ForegroundColor Cyan -NoNewline
    Write-Host "  DISK SPEED TEST UTILITY" -ForegroundColor White -NoNewline
    Write-Host "                       ║" -ForegroundColor Cyan
    Write-Host "  ║                 " -ForegroundColor Cyan -NoNewline
    Write-Host "                                          ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $drives = Get-AvailableDrives
    
    if ($drives.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No drives with sufficient free space found.`nAt least $($TestFileSizeMB * 2) MB of free space is required.",
            "No Drives Available",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        exit
    }
    
    $selection = Show-DriveSelectionForm -Drives $drives
    
    if ($null -eq $selection) {
        Write-Host "  Test cancelled by user." -ForegroundColor Yellow
        exit
    }
    
    $selectedDrive = $selection.Drive
    $testSizeMB = $selection.TestSize
    $extendedTests = $selection.ExtendedTests
    
    if ($selectedDrive.DriveType -eq [System.IO.DriveType]::Fixed) {
        $testFolder = Join-Path $selectedDrive.Root "DiskSpeedTest_Temp"
        try {
            if (-not (Test-Path $testFolder)) {
                New-Item -ItemType Directory -Path $testFolder -Force -ErrorAction Stop | Out-Null
            }
            $testFilePath = Join-Path $testFolder "DiskSpeedTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
        }
        catch {
            $systemDriveLetter = $env:SystemDrive.TrimEnd(':')
            if ($selectedDrive.Letter -eq $systemDriveLetter) {
                $testFilePath = Join-Path $env:TEMP "DiskSpeedTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
            } else {
                $testFilePath = Join-Path $selectedDrive.Root "DiskSpeedTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
            }
        }
    } else {
        $testFilePath = Join-Path $selectedDrive.Root "DiskSpeedTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').tmp"
    }
    
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Configuration" -ForegroundColor Yellow -NoNewline
    Write-Host "                                               │" -ForegroundColor DarkGray
    Write-Host "  ├─────────────────────────────────────────────────────────────┤" -ForegroundColor DarkGray
    
    $driveDisplay = "  │  Drive:          $($selectedDrive.Root) [$($selectedDrive.Label)]"
    Write-Host $driveDisplay.PadRight(64) -ForegroundColor White -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    
    $sizeDisplay = "  │  Test Size:      $testSizeMB MB"
    Write-Host $sizeDisplay.PadRight(64) -ForegroundColor White -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    
    $modeDisplay = "  │  Mode:           $(if ($extendedTests) { 'Extended (Sequential + Random 4K)' } else { 'Basic (Sequential only)' })"
    Write-Host $modeDisplay.PadRight(64) -ForegroundColor White -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    Write-Host ""
    
    $progressForm = Show-ProgressForm
    $progressForm.Show()
    $progressForm.Refresh()
    
    $updateStatus = {
        param($text)
        $label = $progressForm.Controls["StatusLabel"]
        $label.Text = $text
        $progressForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
    
    $writeResult = @{ Success = $false; Error = "Not run" }
    $readResult = @{ Success = $false; Error = "Not run" }
    $random4KWriteResult = @{ Success = $false; Error = "Not run" }
    $random4KReadResult = @{ Success = $false; Error = "Not run" }
    
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkGray
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Running Tests..." -ForegroundColor Yellow -NoNewline
    Write-Host "                                            │" -ForegroundColor DarkGray
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkGray
    
    try {
        & $updateStatus "Testing sequential write speed... (1/$(if ($extendedTests) { '4' } else { '2' }))"
        Write-Host "    [" -NoNewline -ForegroundColor DarkGray
        Write-Host "●" -NoNewline -ForegroundColor Yellow
        Write-Host "] Sequential Write (1MB blocks)..." -ForegroundColor White
        $writeResult = Test-WriteSpeed -TestPath $testFilePath -FileSizeMB $testSizeMB -BlockSizeKB $BlockSizeKB
        
        if ($writeResult.Success) {
            & $updateStatus "Testing sequential read speed... (2/$(if ($extendedTests) { '4' } else { '2' }))"
            Write-Host "    [" -NoNewline -ForegroundColor DarkGray
            Write-Host "●" -NoNewline -ForegroundColor Yellow
            Write-Host "] Sequential Read (1MB blocks)..." -ForegroundColor White
            $readResult = Test-ReadSpeed -TestPath $testFilePath -BlockSizeKB $BlockSizeKB
        }
        
        if ($extendedTests -and $writeResult.Success) {
            & $updateStatus "Testing random 4K write speed... (3/4)"
            Write-Host "    [" -NoNewline -ForegroundColor DarkGray
            Write-Host "●" -NoNewline -ForegroundColor Yellow
            Write-Host "] Random 4K Write ($Random4KOperations operations)..." -ForegroundColor White
            $random4KWriteResult = Test-Random4KWrite -TestPath $testFilePath -Operations $Random4KOperations
            
            & $updateStatus "Testing random 4K read speed... (4/4)"
            Write-Host "    [" -NoNewline -ForegroundColor DarkGray
            Write-Host "●" -NoNewline -ForegroundColor Yellow
            Write-Host "] Random 4K Read ($Random4KOperations operations)..." -ForegroundColor White
            $random4KReadResult = Test-Random4KRead -TestPath $testFilePath -Operations $Random4KOperations
        }
    }
    finally {
        & $updateStatus "Cleaning up..."
        if (Test-Path $testFilePath) {
            Remove-Item $testFilePath -Force -ErrorAction SilentlyContinue
        }
        if ($testFolder -and (Test-Path $testFolder)) {
            $remainingFiles = Get-ChildItem $testFolder -ErrorAction SilentlyContinue
            if ($null -eq $remainingFiles -or $remainingFiles.Count -eq 0) {
                Remove-Item $testFolder -Force -ErrorAction SilentlyContinue
            }
        }
        
        $progressForm.Close()
        $progressForm.Dispose()
    }
    
    Write-Host ""
    
    Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                      " -ForegroundColor Green -NoNewline
    Write-Host "TEST RESULTS" -ForegroundColor White -NoNewline
    Write-Host "                         ║" -ForegroundColor Green
    Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "    Sequential Write (1MB):  " -ForegroundColor White -NoNewline
    if ($writeResult.Success) {
        Write-Host "$($writeResult.SpeedMBps) MB/s" -ForegroundColor Green
    } else {
        Write-Host "FAILED" -ForegroundColor Red
    }
    
    Write-Host "    Sequential Read (1MB):   " -ForegroundColor White -NoNewline
    if ($readResult.Success) {
        Write-Host "$($readResult.SpeedMBps) MB/s" -ForegroundColor Cyan
    } else {
        Write-Host "FAILED" -ForegroundColor Red
    }
    
    if ($extendedTests) {
        Write-Host ""
        
        Write-Host "    Random 4K Write:         " -ForegroundColor White -NoNewline
        if ($random4KWriteResult.Success) {
            Write-Host "$($random4KWriteResult.SpeedMBps) MB/s" -ForegroundColor Yellow -NoNewline
            Write-Host "  ($($random4KWriteResult.IOPS) IOPS)" -ForegroundColor DarkYellow
        } else {
            Write-Host "FAILED" -ForegroundColor Red
        }
        
        Write-Host "    Random 4K Read:          " -ForegroundColor White -NoNewline
        if ($random4KReadResult.Success) {
            Write-Host "$($random4KReadResult.SpeedMBps) MB/s" -ForegroundColor Magenta -NoNewline
            Write-Host "  ($($random4KReadResult.IOPS) IOPS)" -ForegroundColor DarkMagenta
        } else {
            Write-Host "FAILED" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "  Test completed successfully!" -ForegroundColor Green
    Write-Host ""
    
    Show-ResultsForm -DriveInfo $selectedDrive `
                     -WriteResult $writeResult `
                     -ReadResult $readResult `
                     -Random4KWriteResult $random4KWriteResult `
                     -Random4KReadResult $random4KReadResult `
                     -TestSizeMB $testSizeMB `
                     -ExtendedTests $extendedTests
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "An error occurred: $($_.Exception.Message)",
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
