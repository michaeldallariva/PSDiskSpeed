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
    
