<# Some Details

----------------------------------------------------------
Notes
-----------
Created By Ruan Ayres
Version 6.0
Date 03-01-2023

Prerequisites
------------------
PowerCLI module
Posh-SSH Module

Description
------------------
This script automates the process of prepping VCF hosts for commissioning in SDDC manager.
The input is through a CSV file containing all hosts DNS names, IP Addresses, Username and Password
example;
IPAddress;Username;Password;NtpServers;VlanId;Hostname;Domain
192.168.0.1;root;VMware1!;1.1.1.1;200;host1;example.net
192.168.0.2;root;VMware1!;1.1.1.1;200;host2;example.net
192.168.0.3;root;VMware1!;1.1.1.1;200;host3;example.net

It then runs through the various steps to prep a VCF host
Add license
Update NTP
Change VLAN ID for standard switch
Update hostname, fqdn and DNS
Starts SSH
Connect with Posh-SSH
Regenerates local certs with esxcli command "/sbin/generate-certificates"
Disconnect and reboot host

#>
#Import-Module VMware.PowerCLI
Import-Module Posh-SSH

# Set the variables for the input file path and delimiter
# Prompt the user to select the JSON file
Add-Type -AssemblyName System.Windows.Forms

# Create an instance of the OpenFileDialog
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = "CSV Files (*.csv)|*.csv"
$openFileDialog.Title = "Select a CSV File"

# Show the file selection dialog and check if the user clicked the OK button
if ($openFileDialog.ShowDialog() -eq 'OK') {
        # Get the selected file path
        $inputFilePath = $openFileDialog.FileName
    
        # Display the selected file path
        Write-Host "Selected CSV file: $inputFilePath"
        $delimiter = Read-Host -Prompt 'What is The Delimiter for The File? ; or , (default: ;)'
        $dns1 = Read-Host -Prompt 'Enter DNS Server 1'
        $dns2 = Read-Host -Prompt 'Enter DNS Server 2'
	$ntp1 = Read-Host -Prompt 'Enter NTP Server 1'
        $ntp2 = Read-Host -Prompt 'Enter NTP Server 2'
        $license = Read-Host -Prompt 'Enter ESXi Licence Key'


        # Read the input file and loop through each row
        foreach ($row in Import-Csv $inputFilePath -Delimiter $delimiter) {
                # Extract the properties for the current row
                $ipAddress = $row.IPAddress
                $username = $row.Username
                $password = $row.Password
                $vlanId = $row.VlanId
                $hostname = $row.Hostname
                $domain = $row.Domain

                $sshpass = ConvertTo-SecureString $password -AsPlainText -Force
                $credential = New-Object System.Management.Automation.PSCredential($username, $sshpass)

                # Set error action preference to stop the script if an error occurs
                $ErrorActionPreference = "Continue"

    
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Connecting to host $ipAddress using VMware PowerCLI and the provided credentials..." 

                # Connect to the host using VMware PowerCLI and the provided credentials
                Connect-VIServer -Server $ipAddress -User $username -Password $password -ErrorAction Continue -Force
                Write-Host -ForegroundColor Green "Connected to $ipAddress"
                Start-Sleep -Seconds 2	
                #Add ESXi License key to host	
                Write-Host -Object "Adding license key on $ipAddress" -BackgroundColor Gray -ForegroundColor Yellow		
                Set-VMHost -VMHost $ipAddress -LicenseKey $license 
                Write-Host -ForegroundColor Green "License Added to $ipAddress"
                Start-Sleep -Seconds 2
                # Update the NTP server settings
                Write-Host -ForegroundColor Green "Updating NTP server settings..." 
        
                Add-VMHostNtpServer -NtpServer $ntp1 , $ntp2 -VMHost $ipAddress -ErrorAction Continue 2>&1 
                Write-Host -ForegroundColor Green "Updating NTP firewall settings..."
                Get-VMHostFirewallException | where { $_.Name -eq "NTP client" } | Set-VMHostFirewallException -Enabled:$true
                Get-VMHostService | Where-Object { $_.key -eq "ntpd" } | Start-VMHostService
                Get-VMHostService | Where-Object { $_.key -eq "ntpd" } | Set-VMHostService -policy "On" 	

                Start-Sleep -Seconds 2
                #Change the VLAN ID for the VM Network standard switch
                Write-Host -ForegroundColor Green "Changing VLAN ID for VM Network standard switch..."
        
                $vmNetwork = Get-VirtualSwitch -VMHost $ipAddress -Name "vSwitch0" | Get-VirtualPortGroup -Name "VM Network" 
                Set-VirtualPortGroup -VirtualPortGroup $vmNetwork -VLanId $vlanId
		
                Start-Sleep -Seconds 6
                # Update the Hostname,Domain and DNS	
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Updating the hostname, FQDN and DNS..."        
                Get-VMHostNetwork -VMHost $ipAddress | Set-VMHostNetwork -HostName $hostname -Confirm:$false
                Get-VMHostNetwork -VMHost $ipAddress | Set-VMHostNetwork -DomainName $domain -Confirm:$false
                Get-VMHostNetwork -VMHost $ipAddress | Set-VMHostNetwork -DNSAddress $dns1 , $dns2  -Confirm:$false
                Write-Host -ForegroundColor Green "Host updated to $hostname.$domain"
                Start-Sleep -Seconds 2
                # Start SSH	
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Checking SSH service..."         
                $sshstatus = Get-VMHostService -VMHost $ipAddress | where { $psitem.key -eq "tsm-ssh" }
                if ($sshstatus.Running -eq $False) {
                        Write-Host -ForegroundColor Magenta "SSH not enabled, enabling....."
                        Get-VMHostService | where { $psitem.key -eq "tsm-ssh" } | Start-VMHostService -Confirm:$false
                }
                else {
                        Write-Host -ForegroundColor Green "SSH Already Enabled"
                }

                Start-Sleep -Seconds 6
                # Connect to the host using Posh-SSH and the provided credentials		
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Connecting to host $ipAddress using Posh-SSH and the provided credentials..."         
                $sshSession = New-SSHSession -ComputerName $ipAddress -Credential $credential -ErrorAction Continue -AcceptKey:$true -force
                Write-Host -ForegroundColor Green "SSH Connected."	
                Start-Sleep -Seconds 2
                # Run the generate-certificates command
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Running the generate-certificates command..."         
                $generateCertsCommand = "/sbin/generate-certificates"
                Invoke-SSHCommand -SessionId $sshSession.SessionId -Command $generateCertsCommand -ErrorAction Continue
                Write-Host -ForegroundColor Green "Cert Regen Done."	
                Start-Sleep -Seconds 2
                # Disconnect from the SSH session
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Disconnecting from the SSH session..."         
                Remove-SSHSession -SessionId $sshSession.SessionId
		
                Start-Sleep -Seconds 2
                # Rebooting the host
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Rebooting the host $ipAddress..."         
                Restart-VMHost $ipAddress -Confirm:$false -Force -ErrorAction Continue        

                Start-Sleep -Seconds 2
                # Disconnecting from host
                Write-Host -BackgroundColor Gray -ForegroundColor Yellow "Disconnecting from $ipAddress..."         
                Disconnect-VIServer -Server $ipAddress -Force -Confirm:$False

			
                Start-Sleep -Seconds 10    
        }
 
        # Prompt the user with a message and wait for input
        Read-Host -Prompt 'Host Prep Completed, Please check output files for issues. Press ENTER to exit.'
}
else {
        # User canceled the file selection
        Write-Host "File selection canceled."
        Exit 1  # Exit the script with a non-zero code to indicate an error or cancellation
}
# Exit the script
Exit
