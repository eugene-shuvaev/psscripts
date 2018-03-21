Param (
    [Parameter(Mandatory=$true)][string]$chocoPackages,
	[Parameter(Mandatory=$true)][string]$vmAdminPassword
)

# Expand OS disk
foreach($disk in Get-Disk)
{
    # Check if the disk in context is a Boot and System disk
    if((Get-Disk -Number $disk.number).IsBoot -And (Get-Disk -Number $disk.number).IsSystem)
    {
        # Get the drive letter assigned to the disk partition where OS is installed
        $driveLetter = (Get-Partition -DiskNumber $disk.Number | where {$_.DriveLetter}).DriveLetter
        Write-verbose "Current OS Drive: $driveLetter :\"

        # Get current size of the OS parition on the Disk
        $currentOSDiskSize = (Get-Partition -DriveLetter $driveLetter).Size        
        Write-verbose "Current OS Partition Size: $currentOSDiskSize"

        # Get Partition Number of the OS partition on the Disk
        $partitionNum = (Get-Partition -DriveLetter $driveLetter).PartitionNumber
        Write-verbose "Current OS Partition Number: $partitionNum"

        # Get the available unallocated disk space size
        $unallocatedDiskSize = (Get-Disk -Number $disk.number).LargestFreeExtent
        Write-verbose "Total Unallocated Space Available: $unallocatedDiskSize"

        # Get the max allowed size for the OS Partition on the disk
        $allowedSize = (Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $partitionNum).SizeMax
        Write-verbose "Total Partition Size allowed: $allowedSize"

        if ($unallocatedDiskSize -gt 0 -And $unallocatedDiskSize -le $allowedSize)
        {
            $totalDiskSize = $allowedSize
            
            # Resize the OS Partition to Include the entire Unallocated disk space
            $resizeOp = Resize-Partition -DriveLetter C -Size $totalDiskSize
            Write-verbose "OS Drive Resize Completed $resizeOp"
        }
        else {
            Write-Verbose "There is no Unallocated space to extend OS Drive Partition size"
        }
    }   
}

# Get username/password & machine name
$userName = "Administrator"
[Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
$password = $vmAdminPassword
$cn = [ADSI]"WinNT://$env:ComputerName"

# Create new user
$user = $cn.Create("User", $userName)
$user.SetPassword($password)
$user.SetInfo()
$user.description = "Local administrator"
$user.SetInfo()

# Add user to the Administrators group
$group = [ADSI]"WinNT://$env:ComputerName/Administrators,group"
$group.add("WinNT://$env:ComputerName/$userName")

# Create pwd and new $creds for remoting
$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\$($username)", $secPassword)

# Ensure that current process can run scripts. 
#"Enabling remoting" | Out-File $LogFile -Append
Enable-PSRemoting -Force -SkipNetworkProfileCheck

#"Changing ExecutionPolicy" | Out-File $LogFile -Append
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Install Choco
#"Installing Chocolatey" | Out-File $LogFile -Append
$sb = { iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')) }
Invoke-Command -ScriptBlock $sb -ComputerName $env:COMPUTERNAME -Credential $credential | Out-Null

#"Disabling UAC" | Out-File $LogFile -Append
$sb = { Set-ItemProperty -path HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System -name EnableLua -value 0 }
Invoke-Command -ScriptBlock $sb -ComputerName $env:COMPUTERNAME -Credential $credential | Out-Null

# run remoting configuration script for Ansible
$ansibleCommand = $PSScriptRoot + "\ConfigureRemotingForAnsible.ps1"
Invoke-Command -FilePath $ansibleCommand -ComputerName $env:COMPUTERNAME -Credential $credential | Out-Null

# it's weird, but it seems that the first package installation doesn't find cinst command, so slepp a while
Start-Sleep -s 10

#"Install each Chocolatey Package"
$chocoPackages.Split(";") | ForEach {
    $command = "cinst " + $_ + " -y"
    $command
    $sb = [scriptblock]::Create("$command")

    # Use the current user profile
    Invoke-Command -ScriptBlock $sb -ArgumentList $chocoPackages -ComputerName $env:COMPUTERNAME -Credential $credential | Out-Null
}
