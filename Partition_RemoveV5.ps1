<#
Some Details
----------------------------------------------------------
Notes
-----------
Created By Ruan Ayres
Version 5.0
Date 05-31-2023

Prerequisites
------------------
PowerCLI module
Posh-SSH Module

Description
------------------
This script allows the deletion of left over partitions on any SSD disk.
The script runs through the inout file, lists all disks marked as SSD and their partition numbers.
You select and paste the naa ID of the disk and the partition number.
The script loops and asks multiple times if there are multiple partitions.
Choose next for the next host or finsih to break the loop.
example;
ESXiHost,Username,Password
192.168.0.1,root,VMware1!
#>
$moduleName = "Posh-SSH"
$moduleInstalled = Get-Module -ListAvailable | Where-Object { $_.Name -eq $moduleName }

if ($moduleInstalled -eq $null) {
    Write-Host "Installing $moduleName module..."
    Install-Module -Name $moduleName -Scope CurrentUser -Force
    Import-Module $moduleName
    Write-Host "$moduleName module installed successfully."
} else {
    Write-Host "$moduleName module is already installed."
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create an OpenFileDialog to prompt the user for the input CSV file
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('Desktop')
    Filter = 'CSV files (*.csv)|*.csv'
    Title = 'Select Input CSV File'
}

# Display the OpenFileDialog and check if the user clicked the OK button
if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $inputCsvFile = $openFileDialog.FileName
} else {
    Write-Host "No input CSV file selected. Exiting..."
    Exit
}

# Read the ESXi host details from the input CSV file
$esxiHostDetails = Import-Csv -Path $inputCsvFile

# Iterate through each ESXi host in the CSV file
for ($i = 0; $i -lt $esxiHostDetails.Count; $i++) {
    $esxiHostDetail = $esxiHostDetails[$i]
    $esxiHost = $esxiHostDetail.ESXiHost
    $Username = $esxiHostDetail.Username
    $Password = $esxiHostDetail.Password
    $sshpass = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($Username, $sshpass)

    Write-Host "Connecting to $esxiHost" -BackgroundColor Gray -ForegroundColor DarkYellow
    Connect-VIServer -Server $esxiHost -User $Username -Password $Password -Force

    # Get the SSD disks
    $esxcli = Get-EsxCli -VMHost $esxiHost
    $ssdDisks = $esxcli.storage.core.device.list() | Where-Object { $_.IsSSD -eq 'true' } | Select-Object Device, DisplayName, Size

    $Partitions = $esxcli.storage.core.device.partition.list() | Where-Object { $_.Device -like 'naa.*' } | Select-Object Device, Partition

    # Display the information about SSD disks
    $ssdDisks | Format-Table -AutoSize
    $Partitions | Format-Table -AutoSize

    # Start SSH service
    Write-Host -BackgroundColor Gray -ForegroundColor DarkYellow "Checking SSH service..."
    $sshStatus = Get-VMHostService | Where-Object { $_.key -eq "tsm-ssh" }

    if ($sshStatus.Running -eq $False) {
        Write-Host -ForegroundColor Magenta "SSH not enabled, enabling....."
        Get-VMHostService | Where-Object { $_.key -eq "tsm-ssh" } | Start-VMHostService -Confirm:$false
    }
    else {
        Write-Host -ForegroundColor Green "SSH Already Enabled"
    }

    # Connect using SSH
    Write-Host -BackgroundColor Gray -ForegroundColor DarkYellow "Connecting to host $esxiHost using Posh-SSH and the provided credentials..."         
    $sshSession = New-SSHSession -ComputerName $esxiHost -Credential $credential -ErrorAction Continue -AcceptKey:$true -force
    Write-Host -ForegroundColor Green "SSH Connected."

    # Loop to delete partitions
    while ($true) {
        # Ask user for disk ID
        $diskId = Read-Host "Enter disk ID to delete partitions (or 'finish' to exit, 'next' for the next host):"

        # Check if user wants to move to the next host
        if ($diskId -eq "next") {
            break
        }

        # Check if user wants to finish
        if ($diskId -eq "finish") {
            break 2
        }

        # Loop to delete specific partitions on the disk
        while ($true) {
            # Ask user for partition number
            $partitionNumber = Read-Host "Enter partition number to delete (or 'next' for the next disk ID, 'finish' to exit):"

            # Check if user wants to move to the next disk ID
            if ($partitionNumber -eq "next") {
                break
            }

            # Check if user wants to finish
            if ($partitionNumber -eq "finish") {
                break 2
            }

            # Run the partedUtil command to delete the specified partition
            Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Deleting Partition..."
            $partedUtilCommand = "/sbin/partedUtil delete /vmfs/devices/disks/$diskId $partitionNumber"
            Invoke-SSHCommand -SessionId $sshSession.SessionId -Command $partedUtilCommand -ErrorAction Continue
            Start-Sleep 2
            Write-Host -ForegroundColor Green "Partition Deleted."
        }
    }

    # Disconnect from SSH
    Remove-SSHSession -SessionId $sshSession.SessionId

    # Disconnect from the ESXi server
    Disconnect-VIServer -Server $esxiHost -Confirm:$false
}
