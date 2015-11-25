# Download Image of Windows Server (version) and save to default downloads location:
https://www.microsoft.com/en-us/evalcenter/

# Install Hyper-V on local computer
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

#region prepare switch and image (run once)

# Create VMSwitch
New-VMSwitch -Name 'Private Switch' -SwitchType Private

# Get image name
$Imagename = (Get-item ($env:HOME + '\downloads\*.vhd*')).name

# Create directory for the image at c:\Hyper-V\VMs\Images
New-Item -ItemType Directory -Path 'C:\Hyper-V\VMs' -Name 'Images' -Force

# Copy image to central location
Copy-Item ($env:HOME + "\downloads\$Imagename") -Destination "C:\Hyper-V\VMs\Images\$Imagename"

#endregion

#region Virtual Machine

# Create parameter computername
$VMName = read-host -Prompt 'VM Name'

# Create new empty VM
New-VM -Name $VMName -Generation 1 -Path 'C:\Hyper-V\VMs' -SwitchName 'Private Switch' -NoVHD

#Create new differencing VHD with the Image as a parent
New-VHD -Path "C:\Hyper-V\VMs\$VMName\C-Drive.vhd" -ParentPath "C:\Hyper-V\VMs\Images\$Imagename" -Differencing

# Attach VHD to Virtual Machine
Get-VM -name $VMName | Add-VMHardDiskDrive -Path "C:\Hyper-V\VMs\$VMName\C-Drive.vhd"

# Change additional VM properties and Start the VM 
Get-VM -name $VMName | Set-VM -ProcessorCount '4' -DynamicMemory -MemoryMaximumBytes 2GB -Passthru | start-VM

# Create Snapshot (if required)
Get-VM -name $VMName | Checkpoint-VM -SnapshotName 'Clean Build'

#endregion