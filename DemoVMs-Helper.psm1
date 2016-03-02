Function New-DemoVMs
{
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$VirtualSwitchName,

        [Parameter(Mandatory = $true)]
        [int]$ProcessorCount,

        [Parameter(Mandatory = $true)]
        [int]$Generation,

        [Parameter(Mandatory = $false)]
        [string]$ImagesLocation = 'D:\Hyper-V\Images',

        [Parameter(Mandatory = $false)]
        [string]$VMsLocation = 'D:\Hyper-V\VMs',

        [Parameter(Mandatory = $false)]
        [int]$Datadisks = 0,

        [Parameter(Mandatory = $false)]
        [System.Int64]$Datadisksize = 40GB,

        [Parameter(Mandatory = $false)]
        [System.Int64]$Memory = 2GB,

        [Parameter(Mandatory = $false)]
        [switch]$Snapshot,

        [Parameter(Mandatory = $false)]
        [string]$Snapshotname = 'Clean Build'
    )

    #region runas administrator
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] 'Administrator'))
    {
        Write-Warning -Message "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
        Break
    }
    #endregion

    #region check Hyper-V Role Installed
    if (((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).state) -ne 'Enabled')
    {
        Write-Warning -Message 'Hyper-V: Hyper-V Role has not yet been enabled!'

        if ((Read-Question -Question 'Would you like to Enable Hyper-V?') -eq '0')
        {
            $null = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

            if ((Read-Question -Question 'Would you like to restart your computer to finish the Hyper-V Installation?') -eq '0')
            {
                Restart-Computer -Force
                break
            }
            else
            {
                Write-Warning -Message 'Hyper-V: Hyper-V Role has now been installed, however a reboot is required!'
                Pause
                break
            }
        }
        else
        {
            Write-Warning -Message 'Hyper-V: Hyper-V Role is required to continue. Exiting Script.'
            Pause
            break
        }
    }
    elseif (((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).RestartNeeded) -eq $true)
    {
        Write-Warning -Message 'Hyper-V: Hyper-V Role has already been installed, however a reboot is required!'
        if ((Read-Question -Question 'Would you like to restart your computer to finish the Hyper-V Installation?') -eq '0')
        {
            Restart-Computer -Force
            break
        }
        else
        {
            Pause
            break
        }
    }
    else
    {
        Write-Verbose -Message 'Hyper-V: Hyper-V Role was found' -Verbose
    }
    #endregion

    #region check hyper-v switch
    if (!(Get-VMSwitch | Where-Object -FilterScript {
                $_.name -eq $VirtualSwitchName
    }))
    {
        Write-Warning -Message "Hyper-V: Switch [$($VirtualSwitchName)] could not be found!"
        if ((Read-Question -Question "Would you like to create the virtual switch [$($VirtualSwitchName)]?") -eq '0')
        {
            $null = New-VMSwitch -Name $VirtualSwitchName -SwitchType Private
        }
        else
        {
            Pause
            break
        }
    }
    else
    {
        Write-Verbose -Message "Hyper-V: Switch [$($VirtualSwitchName)] was found." -Verbose
    }

    #endregion

    #region scanning images from imagelocation
    try
    {
        # Get image name
        $Imagename = Show-Dropdownbox -Question 'Pick an Image' -Answers (((Get-Item -Path "$ImagesLocation\*.vhd*" -ErrorAction SilentlyContinue)).name)
    }
    catch
    {

    }

    $imageextension = $Imagename.Split('.') | Select-Object -Last 1
    #endregion

    #region create virtual machines
    if (!$Imagename)
    {
        Write-Warning -Message "No images could be found in location $ImagesLocation, please select a different location using [DeployDemoVMs.ps1 -ImagesLocation 'Your Images Location']"
        break
    }

    else
    {
        foreach ($VM in $VMName)
        {
            if (Get-VM -Name $VM -ErrorAction SilentlyContinue)
            {
                Write-Warning -Message "$($VM): Virtual Machine already exists!"
                break
            }
        
            Write-Verbose -Message "$($VM): Creating Virtual Machine" -Verbose
            $null = New-VM -Name $VM -Generation $Generation -Path $VMsLocation -SwitchName $VirtualSwitchName -NoVHD
 
            Write-Verbose -Message "$($VM): Creating differencing disk" -Verbose
            $null = New-VHD -Path "$VMsLocation\$VM\C-Drive.$($imageextension)" -ParentPath "$ImagesLocation\$Imagename" -Differencing
 
            Write-Verbose -Message "$($VM): Adding differencing disk to Virtual Machine" -Verbose
            $null = Get-VM -name $VM | Add-VMHardDiskDrive -Path "$VMsLocation\$VM\C-Drive.$($imageextension)"

            if ($Generation -eq 2)
            {
                Write-Verbose -Message "$($VM): Changing Harddisk to first boot device" -Verbose
                $null = Get-VM $VM | Set-VMFirmware -FirstBootDevice (Get-VMHardDiskDrive -VMName $VM)
            }

            if ($Datadisks -ne 0)
            {
                $i = 0
                do
                {
                    $i++
                    Write-Verbose -Message "$($VM): Creating data disk $i" -Verbose
                    $null = New-VHD -Path "$VMsLocation\$VM\DataDisk$($i).$($imageextension)" -Dynamic -SizeBytes $Datadisksize

                    Write-Verbose -Message "$($VM): Adding data disk $i to Virtual Machine" -Verbose
                    $null = Get-VM -name $VM | Add-VMHardDiskDrive -Path "$VMsLocation\$VM\DataDisk$($i).$($imageextension)"
                }
                until ($Datadisks -eq $i)
            }
 
            Write-Verbose -Message "$($VM): Changing configuration to $ProcessorCount vCPUs and $($Memory/1gb)GB Memory" -Verbose
            $null = Get-VM -name $VM |
            Set-VM -ProcessorCount $ProcessorCount -DynamicMemory -MemoryMaximumBytes $Memory -Passthru |
            Start-VM
 
            if ($Snapshot)
            {
                Write-Verbose -Message "$($VM): Creating '$Snapshotname' Snapshot" -Verbose
                $null = Get-VM -name $VM | Checkpoint-VM -SnapshotName $Snapshotname
            }
        }
    }

    Write-Verbose -Message 'Deploy Completed!' -Verbose
    #endregion
}

Function Remove-DemoVMs
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMNames
    )

    #region runas administrator
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] 'Administrator'))
    {
        Write-Warning -Message "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
        Break
    }
    #endregion

    Foreach ($VMName in $VMNames)
    {
        $VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($VM -eq $null)
        {
            Write-Warning -Message "$($VMName): Virtual Machine could not be found!"
            Break
        }

        Write-Verbose -Message "$($VMName): Virtual Machine was found with state [$($VM.state)]!" -Verbose

        if ($VM.state -eq 'Running')
        {
            Write-Warning -Message "$($VMName): Virtual Machine was found in state [$($VM.state)]!"
            if ((Read-Question -Question "Would you like to continue to remove $VMName ?") -eq 1)
            {
                Write-Warning -Message "$($VMName): Virtual Machine removal was aborted!"
                break
            }
        }

        if ($VM.state -ne 'Off')
        {
            Write-Verbose -Message "$($VMName): Attempting to stop Virtual Machine! Previous state [$($VM.state)]" -Verbose
            $null = Stop-VM -Name $VMName -Force
        }

        if ($VM.state -ne 'Off')
        {
            Write-Warning -Message "$($VMName): Virtual Machine is still running! Please resolve the issues and then try again!"
            Break
        }

        $VMLocation = $VM.Path

        Write-Verbose -Message "$($VMName): Removing Virtual Machine Configuration" -Verbose
        $null = Remove-VM -Name $VMName -Force

        Write-Verbose -Message "$($VMName): Removing Virtual Machine Directory" -Verbose
        $null = Remove-Item $VMLocation -Recurse -Force

        Write-Verbose -Message "$($VMName): Remove Completed!" -Verbose
    }
}

Function Show-Dropdownbox 
{
    <#
            .SYNOPSIS
            Gives a pop-up to select data, that can be used in other scripts
            .DESCRIPTION
            The Show-Dropdownbox function is used to provide a friendly way for users to input data into script variables.
            This script is for example used during the postbuild script, so that information can be injected in a friendly way.
            .PARAMETER Question
            The question you want to have displayed on screen.
            .PARAMETER Answers
            The answers you would like the users to have as options. (Static list)
            .EXAMPLE
            $variable1 = Show-Dropdownbox -question "Select one of the following:" -answers "A","B","C"
            Create a question and write the output to variable $variable1
            .NOTES
            This function was created for friendly input into scripts that are performed manually.
            Do not use this function in scripts that should run in the background.
            This script was written by Danny den Braver @2013, for questions please contact danny@denbraver.com
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Question,
        [Parameter(Mandatory = $true)]
        [array]$Answers
    )

    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Drawing') 

    $objForm = New-Object -TypeName System.Windows.Forms.Form 
    $objForm.Text = 'Take your selection'
    $objForm.Size = New-Object -TypeName System.Drawing.Size -ArgumentList (300, 275) 
    $objForm.StartPosition = 'CenterScreen'
    $objForm.KeyPreview = $true
    $objForm.Add_KeyDown({
            if ($_.KeyCode -eq 'Enter') 
            {
                $objForm.Close()
            }
    })
    $objForm.Add_KeyDown({
            if ($_.KeyCode -eq 'Escape') 
            {
                $objForm.Close()
            }
    })
    
    $OKButton = New-Object -TypeName System.Windows.Forms.Button
    $OKButton.Location = New-Object -TypeName System.Drawing.Size -ArgumentList (75, 200)
    $OKButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList (75, 23)
    $OKButton.Text = 'OK'
    $OKButton.Add_Click({
            $objForm.Close()
    })
    $objForm.Controls.Add($OKButton)

    $CancelButton = New-Object -TypeName System.Windows.Forms.Button
    $CancelButton.Location = New-Object -TypeName System.Drawing.Size -ArgumentList (150, 200)
    $CancelButton.Size = New-Object -TypeName System.Drawing.Size -ArgumentList (75, 23)
    $CancelButton.Text = 'Cancel'
    $CancelButton.Add_Click({
            $objForm.Close()
    })
    $objForm.Controls.Add($CancelButton)

    $objLabel = New-Object -TypeName System.Windows.Forms.Label
    $objLabel.Location = New-Object -TypeName System.Drawing.Size -ArgumentList (10, 20) 
    $objLabel.Size = New-Object -TypeName System.Drawing.Size -ArgumentList (280, 20) 
    $objLabel.Text = $Question
    $objForm.Controls.Add($objLabel) 

    $objListBox = New-Object -TypeName System.Windows.Forms.ListBox 
    $objListBox.Location = New-Object -TypeName System.Drawing.Size -ArgumentList (10, 40) 
    $objListBox.Size = New-Object -TypeName System.Drawing.Size -ArgumentList (275, 20) 
    $objListBox.Height = 150
    foreach ($answer in $Answers) 
    {
        [void]$objListBox.Items.Add($answer)
    }

    $objListBox.SelectedItem = $objListBox.Items[0]
    $objForm.Controls.Add($objListBox) 
    $objForm.Topmost = $true
    $objForm.Add_Shown({
            $objForm.Activate()
    })
    [void]$objForm.ShowDialog()

    $objListBox.SelectedItem
}

Function Read-Question
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Question
    )

    $subject = 'Read-Question'
    $yes = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes', ''
    $no = New-Object -TypeName System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No', ''
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $Host.UI.PromptForChoice($subject,$Question,$choices,1)
}