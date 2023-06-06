<# Some Details

----------------------------------------------------------
Notes
-----------
Created By Ruan Ayres
VMware PSO
Version 3.0
Date 05-22-2023

Prerequisites
------------------
PowerCLI module
Posh-SSH Module

Description
------------------
This script connects to hosts from an input csv file, it then checks if SSH is enabled or not.
It then connects with Posh SSH to the hosts and runs an esxcli command to check the link ststus of each PNIC and displays it.
The input is through a CSV file containing IP Addresses, Username and Password
example;
Host,Username,Password
192.168.0.1,root,VMware1!

#>

Import-Module Posh-SSH

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#--------------------------------- Read the input CSV file containing ESXi host details (IP/Hostname, Username, Password)
Write-Host "Select Hosts CSV File" -ForegroundColor Yellow
$CsvFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('Desktop')
    Filter = 'CSV file (*.csv)|*.csv'
    Title = 'Select CSV file'
}
$CsvSelected = $CsvFileDialog.ShowDialog()
if ($CsvSelected -eq [System.Windows.Forms.DialogResult]::OK) {
    $Csv = $CsvFileDialog.FileName
}


#--------------------------------- Import the ESXi host details from the CSV file
$esxiHosts = Import-Csv -Path $Csv

#--------------------------------- Iterate through each ESXi host and enable SSH if not already enabled
foreach ($esxiHost in $esxiHosts) {
    $esxi = $esxiHost.Host
    $user = $esxiHost.Username
    $password = $esxiHost.Password

    $sshpass = ConvertTo-SecureString $password -AsPlainText -Force
	$credential = New-Object System.Management.Automation.PSCredential($username, $sshpass)

Write-Host "Connecting to ESXi Host name $esxi" -ForegroundColor DarkYellow -BackgroundColor Gray
    Connect-VIServer -Server $esxi -User $user -Password $password
Write-Host "Connected to $esxi" -ForegroundColor Green -BackgroundColor Gray

#--------------------------------- Get the SSH service on the ESXi host
    $sshService = Get-VMHostService -VMHost $esxi | Where-Object { $_.Key -eq "TSM-SSH" }

#--------------------------------- Remember the initial state of the SSH service
    $initialSshState = $sshService.Running
#--------------------------------- Check if SSH service is enabled
    if ($sshService.Running -eq $false) {
        Write-Host "SSH is not enabled on the ESXi host. Enabling SSH..." -BackgroundColor Gray -ForegroundColor DarkYellow

#--------------------------------- Start the SSH service
        $sshService | Start-VMHostService
        Write-Host "SSH has been enabled on the ESXi host." -BackgroundColor Gray -ForegroundColor DarkGreen
    } else {
        Write-Host "SSH is already enabled on the ESXi host." -ForegroundColor Green
    }

#--------------------------------- Connect to the host using Posh-SSH and the provided credentials		
    Write-Host -ForegroundColor Green "Connecting to host $esxi using Posh-SSH and the provided credentials..."
        
    $sshSession = New-SSHSession -ComputerName $esxi -Credential $credential -ErrorAction Continue -AcceptKey
    
Start-Sleep -Seconds 2
#--------------------------------- Run the generate-certificates command
Write-Host -ForegroundColor Green -BackgroundColor Gray "Checking Host Link Status...." 
    
#--------------------------------- Execute the esxcli command to list physical NICs and their link status
$nicStatusCommand = 'esxcli network nic list | awk ''/^vmnic/ {print $1, $4}'''
$nicStatusResult = Invoke-SSHCommand -SessionId $sshSession.SessionId -Command $nicStatusCommand

#--------------------------------- Store the results in the array
$result = [PSCustomObject]@{
    'ESXi Host' = $esxi
    'Link Status' = $nicStatusResult
}
$results += $result
Start-Sleep -Seconds 2
#--------------------------------- Disconnect from the SSH session
Write-Host -ForegroundColor Green -BackgroundColor Gray"Disconnecting from the SSH session..."
    Remove-SSHSession -SessionId $sshSession.SessionId

#--------------------------------- Check if SSH service was initially disabled and disable it again
    if ($initialSshState -eq $false) {
Write-Host "Disabling SSH on the ESXi host..." -BackgroundColor Gray -ForegroundColor DarkYellow

#--------------------------------- Stop the SSH service
    $sshService | Stop-VMHostService
Write-Host "SSH has been disabled on the ESXi host." -BackgroundColor Gray -ForegroundColor DarkGreen

#--------------------------------- Disconnect from the ESXi host
    Disconnect-VIServer -Server $esxi -Confirm:$false
}}

#--------------------------------- Export the results to a grid view
$results | Out-GridView

