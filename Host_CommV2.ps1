<# Some Details

----------------------------------------------------------
Notes
-----------
Created By Ruan Ayres
Version 2.0
Date 06-01-2023

Prerequisites
------------------
PowerCLI module
PowerVCF Module
PowerValidatedSolutions Module
------------------
Description
------------------
This script assumes you have already created your edge netpool json spec file with details populated from the planning and prep sheet
a sample spec is in the root of this script folder
the script is interactive, asking the user to provide details for the
SDDC Manager FQDN, username, and password
a popup will ask to select the input JSON spec file prepared earlier
the script will authenticate to SDDC Manager and get a list of network pools
an input for the network pool is required
the script will then find the ID for that network pool name and populate the JSON spec file with that netpool ID
the JSON file has a placeholder field as "CLUSTER-ID" that will be replaced
a new spec file will then be saved with the network pool name appended
the script will then proceed to deploy the edge netpool using the newly prepared JSON file

#>

# Import required modules
Write-Host -ForegroundColor Yellow -BackgroundColor Gray "Importing Required Modules...."

# Import-Module -Name VMware.PowerCLI
Import-Module -Name PowerVCF
Import-Module -Name PowerValidatedSolutions

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Write-Host -ForegroundColor Green -BackgroundColor Gray "Modules Imported."

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$jsonPathDir = New-Item -ItemType Directory -Path "$scriptDir\new_json" -Force
$jsonFilename = "HostCommSpec.json"
$sddcManagerFqdn = Read-Host -Prompt 'Enter the SDDC Manager FQDN'
$sddcManagerUser = Read-Host -Prompt 'Enter the SDDC Manager username (default: administrator@vsphere.local)'
$sddcManagerPass = Read-Host -Prompt 'Enter the SDDC Manager password'

# Prompt the user to select the JSON file
Write-Host "Select Host JSON Spec File for Deployment" -ForegroundColor Yellow
$JsonFileDialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
    InitialDirectory = [Environment]::GetFolderPath('Desktop')
    Filter = 'JSON file (*.json)|*.json'
    Title = 'Select JSON file'
}
$JsonSelected = $JsonFileDialog.ShowDialog()
if ($JsonSelected -eq [System.Windows.Forms.DialogResult]::OK) {
    $Json = $JsonFileDialog.FileName
}

# ======================Authenticate to SDDC Manager=================================
Write-Host "Requesting SDDC Manager Token" -ForegroundColor Yellow
Request-VCFToken -fqdn $sddcManagerFqdn -username $sddcManagerUser -password $sddcManagerPass
Start-Sleep 3

# ======================Getting Network Pools=================================
Write-Host "Getting Network Pool Names..." -ForegroundColor Yellow
$networkPools = Get-VCFNetworkPool | Select-Object -Property Name, Id

# Display the available network pools with numbers
Write-Host "Available Network Pools:"
$networkPools | ForEach-Object { Write-Host "$($networkPools.IndexOf($_) + 1). $($_.Name)" }

# Prompt the user to select a number corresponding to the network pool from the list
$selectedNetworkPoolNumber = Read-Host "Enter the number corresponding to the Network Pool you want to select (e.g., 1, 2, 3)"

# Convert the user input to an integer
$selectedNetworkPoolNumber = $selectedNetworkPoolNumber -as [int]

# Check if the user input is a valid number within the range of available network pools
if ($selectedNetworkPoolNumber -gt 0 -and $selectedNetworkPoolNumber -le $networkPools.Count) {
    $selectedNetworkPool = $networkPools[$selectedNetworkPoolNumber - 1]  # Adjust index since the user's input starts from 1
    $NetworkPoolName = $selectedNetworkPool.Name
    $NetworkPoolId = $selectedNetworkPool.Id
    Write-Host "Selected Network Pool is... $NetworkPoolName (ID: $NetworkPoolId)" -ForegroundColor Green
} else {
    Write-Host "Invalid selection. Please enter a valid number from the list (1, 2, 3, etc.)." -ForegroundColor Red
    return
}

# ========================Update JSON with Network Pool ID
Write-Host "Writing New HostSpec Configuration file" -ForegroundColor Yellow
$outputFilename = "{0}-{1}" -f $NetworkPoolName, $jsonFilename
(Get-Content $Json) | ForEach-Object {$_ -replace "CLUSTER-ID", $NetworkPoolId} | Set-Content "$jsonPathDir\$outputFilename"

Write-Host "Press Enter to Continue with Host Commissioning." -ForegroundColor Yellow
Pause

# ========================Starting edge netpool deployment
Write-Host "Starting Host Commissioning, JSON Validation In Progress" -ForegroundColor DarkYellow -BackgroundColor Gray
$commissionHosts = New-VCFCommissionedHost -json "$jsonPathDir\$outputFilename"

Start-Sleep 5
Write-Host "Validation Done" -ForegroundColor Green -BackgroundColor Gray

Write-Host "Checking Task Status" -ForegroundColor DarkYellow -BackgroundColor Gray
Do {
    $taskStatus = Get-VCFTask -id $commissionHosts.id | Select-Object -ExpandProperty status
    Start-Sleep 5
} until ($taskStatus -match "Successful")

Write-Host "Host Commissioning Completed!" -ForegroundColor Green -BackgroundColor Gray
