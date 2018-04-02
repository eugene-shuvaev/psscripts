# Set up IIS applications, SSL binding and web.config
	Import-Module WebAdministration
				
	# Create site folder
	[system.io.directory]::CreateDirectory($using:siteRoot)
		
	# Create Application pool and set its identity
	New-Item -Path IIS:\AppPools\FmoPool
	Set-ItemProperty IIS:\AppPools\FmoPool -name processModel -value @{identityType=0}
		
	# Create two web applications
	New-WebApplication -Name 'fvo' -Site 'Default Web Site' -PhysicalPath $using:siteRoot -ApplicationPool FmoPool
	New-WebApplication -Name 'cdmo' -Site 'Default Web Site' -PhysicalPath $using:siteRoot -ApplicationPool FmoPool
			
	# Create redirect from Default Web Site root to fvo application
	Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\Default Web Site" -Value @{enabled="true";destination="/fvo";childOnly="true"}
	Set-WebConfiguration system.web/globalization "IIS:\sites\Default Web Site" -Value @{culture="en-GB"}
			
	# Create https binding using *.fos.transas.com certificate
	$certPath = 'cert:\LocalMachine\My'
	$certObj = Get-ChildItem -Path $certPath -DNSName fos.transas.com
	if($certObj)
		{
		New-WebBinding -Name 'Default Web Site' -IP '*' -Port 443 -Protocol https -HostHeader $using:stageHostName
		$certWThumb = $certPath + '\' + $certObj.Thumbprint 
		cd IIS:\SSLBindings
		get-item $certWThumb | new-item 0.0.0.0!443
		}
		
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