##############################################################################################
# HyperV.psm1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
    Required for Hyper-V test execution.

.PARAMETER
    <Parameters>

.INPUTS
	

.NOTES
    Creation Date:  
    Purpose/Change: 

.EXAMPLE


#>
###############################################################################################

Function DeployHyperVGroups ($xmlConfig, $setupType, $Distro, $getLogsIfFailed = $false, $GetDeploymentStatistics = $false)
{
    if( (!$EconomyMode) -or ( $EconomyMode -and ($xmlConfig.config.HyperV.Deployment.$setupType.isDeployed -eq "NO")))
    {
        try
        {
            $VerifiedGroups =  $NULL
            $retValue = $NULL
            $i = 0
            $role = 1
            $setupTypeData = $xmlConfig.config.$TestPlatform.Deployment.$setupType
            #DEBUGRG
            #$isAllDeployed = CreateAllHyperVGroupDeployments -setupType $setupType -xmlConfig $xmlConfig -Distro $Distro -region $region -storageAccount $storageAccount -DebugRG "ICA-RG-M1S1-SSTEST-GZBX-636621761998"
            $isAllDeployed = CreateAllHyperVGroupDeployments -setupType $setupType -xmlConfig $xmlConfig -Distro $Distro
            $isAllVerified = "False"
            $isAllConnected = "False"
            #$isAllDeployed = @("True","ICA-RG-IEndpointSingleHS-U1510-8-10-12-34-9","30")

            if($isAllDeployed[0] -eq "True")
            {
                $DeployedHyperVGroup = $isAllDeployed[1]
                $HyperVGroupCount = $isAllDeployed[2]
                $DeploymentElapsedTime = $isAllDeployed[3]
                $GroupsToVerify = $DeployedHyperVGroup.Split('^')
                $allVMData = GetAllHyperVDeployementData -HyperVGroupNames $DeployedHyperVGroup
                Set-Variable -Name allVMData -Value $allVMData -Force -Scope Global

                $isAllConnected = isAllSSHPortsEnabledRG -AllVMDataObject $allVMData
                if ($isAllConnected -eq "True")
                {
                    InjectHostnamesInHyperVVMs -allVMData $allVMData
                    $VerifiedGroups = $DeployedHyperVGroup
                    $retValue = $VerifiedGroups
                    if ( Test-Path -Path  .\Extras\UploadDeploymentDataToDB.ps1 )
                    {
                        $out = .\Extras\UploadDeploymentDataToDB.ps1 -allVMData $allVMData -DeploymentTime $DeploymentElapsedTime.TotalSeconds
                    }
                    if(!$IsWindows)
                    {
                        $KernelLogOutput= GetAndCheckKernelLogs -allDeployedVMs $allVMData -status "Initial"
                    }
                }
                else
                {
                    LogErr "Unable to connect Some/All SSH ports.."
                    $retValue = $NULL  
                }                
            }
            else
            {
                LogErr "One or More Deployments are Failed..!"
                $retValue = $NULL
            }
        }
        catch
        {
            LogMsg "Exception detected. Source : DeployVMs()"
            $line = $_.InvocationInfo.ScriptLineNumber
            $script_name = ($_.InvocationInfo.ScriptName).Replace($PWD,".")
            $ErrorMessage =  $_.Exception.Message
            LogErr "EXCEPTION : $ErrorMessage"
            LogErr "Source : Line $line in script $script_name."              
            $retValue = $NULL
        }
    }
    else
    {
        $retValue = $xmlConfig.config.$TestPlatform.Deployment.$setupType.isDeployed
        if(!$IsWindows)
        {
            $KernelLogOutput= GetAndCheckKernelLogs -allDeployedVMs $allVMData -status "Initial"
        }
    }
    if ( $GetDeploymentStatistics )
    {
        return $retValue, $DeploymentElapsedTime
    }
    else
    {
        return $retValue
    }
}

Function CreateAllHyperVGroupDeployments($setupType, $xmlConfig, $Distro, $DebugRG = "")
{
    $DeployedHyperVGroup = @()
    if ($DebugRG)
    {
        return "True", $DebugRG, 1, 180
    }
    else
    {
        $HyperVGroupCount = 0
        LogMsg $setupType
        $setupTypeData = $xmlConfig.config.HyperV.Deployment.$setupType
        if($region)
        {
          $location = $region;
        }

        $index = 0
        foreach ($HyperVGroupXML in $setupTypeData.ResourceGroup )
        {
            $HyperVHost = $xmlConfig.config.HyperV.Hosts.ChildNodes[$index].ServerName
            $SourceOsVHDPath = $xmlConfig.config.HyperV.Hosts.ChildNodes[$index].SourceOsVHDPath
            $DestinationOsVHDPath = $xmlConfig.config.HyperV.Hosts.ChildNodes[$index].DestinationOsVHDPath
            $index++
            $validateStartTime = Get-Date
            $readyToDeploy = $false
            while (!$readyToDeploy)
            {
                #TBD Verify the readiness of the HyperV Host.
                $readyToDeploy = $true
            }
            if ($readyToDeploy)
            {
                $curtime = ([string]((Get-Date).Ticks / 1000000)).Split(".")[0]
                $isHyperVGroupDeployed = "False"
                $retryDeployment = 0
                if ( $HyperVGroupXML.Tag -ne $null )
                {
                    $HyperVGroupName = "ICA-HG-" + $HyperVGroupXML.Tag + "-" + $Distro + "-" + "$shortRandomWord-" + "$curtime"
                }
                else
                {
                    $HyperVGroupName = "ICA-HG-" + $setupType + "-" + $Distro + "-" + "$shortRandomWord-" + "$curtime"
                }
                while (($isHyperVGroupDeployed -eq "False") -and ($retryDeployment -lt 1))
                {
                    if ($ExistingRG)
                    {
                        #TBD 
                        #Use existing HypeV group for test.
                    }
                    else
                    {
                        LogMsg "Creating HyperV Group : $HyperVGroupName."
                        LogMsg "Verifying that HyperV Group name is not in use."
                        $isHyperVGroupDeleted = DeleteHyperVGroup -HyperVGroupName $HyperVGroupName -HyperVHost $HyperVHost
                    }
                    if ($isHyperVGroupDeleted)
                    {
                        $CreatedHyperVGroup = CreateHyperVGroup -HyperVGroupName $HyperVGroupName -HyperVHost $HyperVHost
                        if ($CreatedHyperVGroup)
                        {
                            $DeploymentStartTime = (Get-Date)
                            $ExpectedVMs = 0
                            $HyperVGroupXML.VirtualMachine | ForEach-Object {$ExpectedVMs += 1}
                            $VMCreationStatus = CreateHyperVGroupDeployment -HyperVGroupName $HyperVGroupName -HyperVGroupXML $HyperVGroupXML -HyperVHost $HyperVHost -SourceOsVHDPath $SourceOsVHDPath -DestinationOsVHDPath $DestinationOsVHDPath
                            $DeploymentEndTime = (Get-Date)
                            $DeploymentElapsedTime = $DeploymentEndTime - $DeploymentStartTime
                            if ( $VMCreationStatus )
                            {
                                if($TestArea -eq 'Nested')
                                {
                                    LogMsg "Test Platform is $TestPlatform and Test Area is $TestArea, need to enable nested virtualization"
                                    $status = EnableHyperVNestedVirtualization -HyperVGroupName $HyperVGroupName -HyperVHost $HyperVHost
                                }
                                $StartVMStatus = StartHyperVGroupVMs -HyperVGroupName $HyperVGroupName -HyperVHost $HyperVHost

                                if ($StartVMStatus)
                                {
                                    $retValue = "True"
                                    $isHyperVGroupDeployed = "True"
                                    $HyperVGroupCount = $HyperVGroupCount + 1
                                    $DeployedHyperVGroup += $HyperVGroupName
                                }
                                else 
                                {
                                    LogErr "Unable to start one or more VM's"
                                    $retryDeployment = $retryDeployment + 1
                                    $retValue = "False"
                                    $isHyperVGroupDeployed = "False"
                                }
                            }
                            else
                            {
                                LogErr "Unable to Deploy one or more VM's"
                                $retryDeployment = $retryDeployment + 1
                                $retValue = "False"
                                $isHyperVGroupDeployed = "False"
                            }
                        }
                        else
                        {
                            LogErr "Unable to create $HyperVGroupName"
                            $retryDeployment = $retryDeployment + 1
                            $retValue = "False"
                            $isHyperVGroupDeployed = "False"
                        }
                    }    
                    else
                    {
                        LogErr "Unable to delete existing HyperV Group - $HyperVGroupName"
                        $retryDeployment += 1
                        $retValue = "False"
                        $isHyperVGroupDeployed = "False"
                    }
                }
            }
            else
            {
                LogErr "HyperV server is not ready to deploy."
                $retValue = "False"
                $isHyperVGroupDeployed = "False"
            }
        }
        return $retValue, $DeployedHyperVGroup, $HyperVGroupCount, $DeploymentElapsedTime
    }
}

Function DeleteHyperVGroup([string]$HyperVGroupName, [string]$HyperVHost)
{
    try
    {
        $AllGroups = $null
        LogMsg "Checking if HyperV VM group '$HyperVGroupName' exists in $HyperVHost..."
        $AllGroups = Get-VMGroup -Name $HyperVGroupName -ErrorAction SilentlyContinue -ComputerName $HyperVHost
    }
    catch
    {
    }
    if ($AllGroups)
    {
		if ($ExistingRG)
		{
			#TBD If user wants to use existing group, then skip the deletion of the HyperV group.
		}
		else
		{
            $CurrentGroup = $null
            foreach ( $CurrentGroup in $AllGroups )
            {
                $CurrentGroup = Get-VMGroup -Name $CurrentGroup.Name -ComputerName $HyperVHost
                if ( $CurrentGroup.VMMembers.Count -gt 0 )
                {
                    $CleanupVMList = @()
                    foreach ($CleanupVM in $CurrentGroup.VMMembers)
                    {
                        if ($VMnames)
                        {
                            if ( $VMNames.Split(",").Contains($CleanupVM.Name) )
                            {
                                $CleanupVMList += $CleanupVM
                            }
                        }
                        else
                        {
                            $CleanupVMList += $CleanupVM
                        }
                    }
                    foreach ($CleanupVM in $CleanupVMList)
                    {
                        LogMsg "Stop-VM -Name $($CleanupVM.Name) -Force -TurnOff "
                        Stop-VM -Name $CleanupVM.Name -Force -TurnOff -ComputerName $HyperVHost
                        $VM = Get-VM -Id $CleanupVM.Id -ComputerName $HyperVHost
                        foreach ($VHD in $CleanupVM.HardDrives)
                        {
                            if ( Test-Path -Path $VHD.Path )
                            {
                                Invoke-Command -ComputerName $HyperVHost -ScriptBlock { Remove-Item -Path $args[0] -Force -Verbose } -ArgumentList $VHD.Path
                                LogMsg "$($VHD.Path) Removed!"
                            }
                        }
                        Remove-VM -Name $CleanupVM.Name -ComputerName $HyperVHost -Force
                        LogMsg "$($CleanupVM.Name) Removed!"
                    }
                    Remove-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost -Force
                    LogMsg "$($HyperVGroupName) Removed!"
                    $retValue = $true
                }
                elseif ($CurrentGroup)
                {
                    LogMsg "$HyperVGroupName is empty. Removing..."
                    Remove-VMGroup -Name $HyperVGroupName -Force -ComputerName $HyperVHost
                    LogMsg "$HyperVGroupName Removed!"
                    $retValue = $true
                }
                else
                {
                    LogMsg "$HyperVGroupName does not exists."
                }
            }
        }
    }
    else
    {
        LogMsg "$HyperVGroupName does not exists."
        $retValue = $true
    }
    return $retValue
}

Function CreateHyperVGroup([string]$HyperVGroupName, [string]$HyperVHost)
{
    $FailCounter = 0
    $retValue = "False"
    While(($retValue -eq $false) -and ($FailCounter -lt 5))
    {
        try
        {
            $FailCounter++
            LogMsg "Using HyperV server : $HyperVHost"
            $CreatedHyperVGroup = New-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost -GroupType VMCollectionType
            if ($?)
            {
                LogMsg "HyperV Group $HyperVGroupName Created with Instance ID: $($CreatedHyperVGroup.InstanceId)."
                $retValue = $CreatedHyperVGroup
            }
            else 
            {
                LogErr "Failed to HyperV Group $HyperVGroupName."
                $retValue = $false
                $FailCounter += 1
            }
        }
        catch
        {
            $retValue = $false
        }
    }
    return $retValue
}

Function CreateHyperVGroupDeployment([string]$HyperVGroup, $HyperVGroupNameXML, $HyperVHost, $SourceOsVHDPath, $DestinationOsVHDPath)
{
    $HyperVMappedSizes = [xml](Get-Content .\XML\AzureVMSizeToHyperVMapping.xml)
    $CreatedVMs =  @()
    $OsVHD = $BaseOsVHD
    $InterfaceAliasWithInternet = (Get-NetIPConfiguration | where {$_.NetProfile.Name -ne 'Unidentified network'}).InterfaceAlias
    $VMSwitches = Get-VMSwitch | where {$InterfaceAliasWithInternet -match $_.Name}
    $ErrorCount = 0
    $i = 0
    $CurrentHyperVGroup = Get-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost
    if ( $CurrentHyperVGroup.Count -eq 1)
    {
        foreach ( $VirtualMachine in $HyperVGroupXML.VirtualMachine)
        {
            if ( $VirtualMachine.RoleName)
            {
                $CurrentVMName = $VirtualMachine.RoleName
                $CurrentVMOsVHDPath = "$DestinationOsVHDPath\$HyperVGroupName-$CurrentVMName-diff-OSDisk.vhd"
            }
            else 
            {
                $CurrentVMName = $HyperVGroupName + "-role-$i"
                $CurrentVMOsVHDPath = "$DestinationOsVHDPath\$HyperVGroupName-role-$i-diff-OSDisk.vhd"
                $i += 1
            }
            $Out = New-VHD -ParentPath "$SourceOsVHDPath\$OsVHD" -Path $CurrentVMOsVHDPath -ComputerName $HyperVHost
            #Convert-VHD -Path "$SourceOsVHDPath\$OsVHD" -DestinationPath $CurrentVMOsVHDPath -VHDType Dynamic 
            if ($?)
            {
                LogMsg "Prerequiste: Prepare OS Disk $CurrentVMOsVHDPath - Succeeded."
                if ($OverrideVMSize)
                {
                    $CurrentVMSize = $OverrideVMSize
                }
                else 
                {
                    $CurrentVMSize = $VirtualMachine.ARMInstanceSize
                }
                Set-Variable -Name HyperVInstanceSize -Value $CurrentVMSize -Scope Global
                $CurrentVMCpu = $HyperVMappedSizes.HyperV.$CurrentVMSize.NumberOfCores
                $CurrentVMMemory = $HyperVMappedSizes.HyperV.$CurrentVMSize.MemoryInMB
                $CurrentVMMemory = [int]$CurrentVMMemory * 1024 * 1024
                LogMsg "New-VM -Name $CurrentVMName -MemoryStartupBytes $CurrentVMMemory -BootDevice VHD -VHDPath $CurrentVMOsVHDPath -Generation 1 -Switch $($VMSwitches.Name) -ComputerName $HyperVHost"
                $NewVM = New-VM -Name $CurrentVMName -MemoryStartupBytes $CurrentVMMemory -BootDevice VHD -VHDPath $CurrentVMOsVHDPath -Generation 1 -Switch $($VMSwitches.Name) -ComputerName $HyperVHost
                if($currentTestData.AdditionalHWConfig.SwitchName)
                {
                    Add-VMNetworkAdapter -VMName $CurrentVMName -SwitchName $currentTestData.AdditionalHWConfig.SwitchName -ComputerName $HyperVHost
                }
                if ($?)
                {
                    LogMsg "Set-VM -VM $($NewVM.Name) -ProcessorCount $CurrentVMCpu -StaticMemory -CheckpointType Disabled -Notes $HyperVGroupName"

                    $Out = Set-VM -VM $NewVM -ProcessorCount $CurrentVMCpu -StaticMemory  -CheckpointType Disabled -Notes "$HyperVGroupName"
                    LogMsg "Add-VMGroupMember -Name $HyperVGroupName -VM $($NewVM.Name)"
                    $Out = Add-VMGroupMember -Name "$HyperVGroupName" -VM $NewVM -ComputerName $HyperVHost
                    $ResourceDiskPath = ".\Temp\ResourceDisk-$((Get-Date).Ticks)-sdb.vhd"
                    if($DestinationOsVHDPath -ne "VHDs_Destination_Path")
                    {
                        $ResourceDiskPath = "$DestinationOsVHDPath\ResourceDisk-$((Get-Date).Ticks)-sdb.vhd"
                    }
                    LogMsg "New-VHD -Path $ResourceDiskPath -SizeBytes 1GB -Dynamic -Verbose -ComputerName $HyperVHost"
                    $VHD = New-VHD -Path $ResourceDiskPath -SizeBytes 1GB -Dynamic -Verbose -ComputerName $HyperVHost
                    LogMsg "Add-VMHardDiskDrive -ControllerType SCSI -Path $ResourceDiskPath -VM $($NewVM.Name)"
                    $NewVM | Add-VMHardDiskDrive -ControllerType SCSI -Path $ResourceDiskPath
                    $LUNs = $VirtualMachine.DataDisk.LUN
                    if($LUNs.count -gt 0)
                    {
                        LogMsg "check the offline physical disks on host $HyperVHost"
                        $DiskNumbers = (Get-Disk | where {$_.OperationalStatus -eq 'offline'}).Number
                        if($DiskNumbers.count -ge $LUNs.count)
                        {
                            LogMsg "The offline physical disks are enough for use"
                            $ControllerType = 'SCSI'
                            $count = 0
                            foreach ( $LUN in $LUNs )
                            {
                                LogMsg "Add physical disk $($DiskNumbers[$count]) to $ControllerType controller on virtual machine $CurrentVMName."
                                $NewVM | Add-VMHardDiskDrive -DiskNumber $($DiskNumbers[$count]) -ControllerType $ControllerType
                                $count ++
                            }
                        }
                        else
                        {
                            LogErr "The offline physical disks are not enough for use"
                            $ErrorCount += 1
                        }
                    }
                }
                else 
                {
                    LogErr "Failed to create VM."
                    LogErr "Removing OS Disk : $CurrentVMOsVHDPath"
                    $Out = Remove-Item -Path $CurrentVMOsVHDPath -Force 
                    $ErrorCount += 1
                }
            }
            else 
            {
                LogMsg "Prerequiste: Prepare OS Disk $CurrentVMOsVHDPath - Failed." 
                $ErrorCount += 1   
            }
        }
    }
    else 
    {
        LogErr "There are $($CurrentHyperVGroup.Count) HyperV groups. We need 1 HyperV group."
        $ErrorCount += 1    
    }
    if ( $ErrorCount -eq 0 )
    {
        $ReturnValue = $true
    }
    else 
    {
        $ReturnValue = $false    
    }
    return $ReturnValue
}

Function EnableHyperVNestedVirtualization($HyperVGroupName, $HyperVHost)
{
    $AllVMs = Get-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost
    $CurrentErrors = @()
    foreach ( $VM in $AllVMs.VMMembers)
    {
        LogMsg "Enable nested virtualization for $($VM.Name) from $HyperVGroupName..."
        Set-VMProcessor -VMName $($VM.Name) -ExposeVirtualizationExtensions $true -ComputerName $HyperVHost
        Set-VMNetworkAdapter -VMName $($VM.Name) -MacAddressSpoofing on -ComputerName $HyperVHost
        if ( $? )
        {
            LogMsg "Succeeded."
        }
        else
        {
            LogErr "Failed"
            $CurrentErrors += "Enable nested virtualization for $($VM.Name) from $HyperVGroupName failed."
        }
    }
    if($CurrentErrors.Count -eq 0)
    {
        $ReturnValue = $true
        $CurrentErrors | ForEach-Object { LogErr "$_" }
    }
    else 
    {
        $ReturnValue = $false    
    }
    return $ReturnValue
}

Function StartHyperVGroupVMs($HyperVGroupName,$HyperVHost)
{
    $AllVMs = Get-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost
    $CurrentErrors = @()
    foreach ( $VM in $AllVMs.VMMembers)
    {
        LogMsg "Starting $($VM.Name) from $HyperVGroupName..."
        $StartVMStatus = Start-VM -VM $VM
        if ( $? )
        {
            LogMsg "Succeeded."
        }
        else
        {
            LogErr "Failed"
            $CurrentErrors += "Starting $($VM.Name) from $HyperVGroupName failed."
        }
    }
    if($CurrentErrors.Count -eq 0)
    {
        $ReturnValue = $true
        $CurrentErrors | ForEach-Object { LogErr "$_" }
    }
    else 
    {
        $ReturnValue = $false    
    }
    return $ReturnValue
}

Function StopHyperVGroupVMs($HyperVGroupName, $HyperVHost)
{
    $AllVMs = Get-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost
    $CurrentErrors = @()
    foreach ( $VM in $AllVMs.VMMembers)
    {
        LogMsg "Shutting down $($VM.Name) from $HyperVGroupName..."
        $StopVMStatus = Stop-VM -VM $VM
        if ( $? )
        {
            LogMsg "Succeeded."
        }
        else
        {
            LogErr "Shutdown failed. Turning off.."
            $StopVMStatus = Stop-VM -VM $VM  -Force -TurnOff -ComputerName $HyperVHost
            if ( $? )
            {
                LogMsg "Succeeded."
            }
            else 
            {
                LogErr "Failed"
                $CurrentErrors += "Stopping $($VM.Name) from $HyperVGroupName failed."                
            }            
        }
    }
    if($CurrentErrors.Count -eq 0)
    {
        $ReturnValue = $true
        $CurrentErrors | ForEach-Object { LogErr "$_" }
    }
    else 
    {
        $ReturnValue = $false    
    }
    return $ReturnValue
}
Function GetAllHyperVDeployementData($HyperVGroupNames,$RetryCount = 100)
{
    $allDeployedVMs = @()
    function CreateQuickVMNode()
    {
        $objNode = New-Object -TypeName PSObject
        Add-Member -InputObject $objNode -MemberType NoteProperty -Name HyperVHost -Value $HyperVHost -Force
        Add-Member -InputObject $objNode -MemberType NoteProperty -Name HyperVGroupName -Value $null -Force 
        Add-Member -InputObject $objNode -MemberType NoteProperty -Name PublicIP -Value $null -Force
        Add-Member -InputObject $objNode -MemberType NoteProperty -Name InternalIP -Value $null -Force
        Add-Member -InputObject $objNode -MemberType NoteProperty -Name RoleName -Value $null -Force
        if($IsWindows){
            Add-Member -InputObject $objNode -MemberType NoteProperty -Name SSHPort -Value 3389 -Force
        }
        else{
            Add-Member -InputObject $objNode -MemberType NoteProperty -Name SSHPort -Value 22 -Force
        }
        return $objNode
    }
    $CurrentRetryAttempt = 0
    $AllPublicIPsCollected = $false
    $ALLVMs = @{}
    $index = 0
    foreach ($HyperVGroupName in $HyperVGroupNames.Split("^"))
    {
        $HyperVHost = $xmlConfig.config.Hyperv.Hosts.ChildNodes[$index].ServerName
        $index++
        LogMsg "Collecting $HyperVGroupName data.."
        $CurrentGroupData = Get-VMGroup -Name $HyperVGroupName -ComputerName $HyperVHost
        $ALLVMs.Add($CurrentGroupData.ComputerName, $CurrentGroupData.VMMembers)
    }

    foreach ($ComputerName in $AllVMs.Keys)
    {
        foreach($property in $ALLVMs[$ComputerName]) {
            $VM = Get-VM -Name $property.Name -ComputerName $ComputerName
            $VMNicProperties =  Get-VMNetworkAdapter -ComputerName $ComputerName -VMName $property.Name

            $RetryCount = 20
            $CurrentRetryAttempt=0
            $QuickVMNode = CreateQuickVMNode
            do
            {
                $CurrentRetryAttempt++
                Start-Sleep 5
                LogMsg "    [$CurrentRetryAttempt/$RetryCount] : $($property.Name) : Waiting for IP address ..."
                $QuickVMNode.PublicIP = $VMNicProperties.IPAddresses | Where-Object {$_ -imatch "\b(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}\b"}
            }while(($CurrentRetryAttempt -lt $RetryCount) -and (!$QuickVMNode.PublicIP))

            if($QuickVMNode.PublicIP.Split("").Length -gt 1)
            {
                $QuickVMNode.PublicIP = $QuickVMNode.PublicIP[0]
            }

            $QuickVMNode.InternalIP = $QuickVMNode.PublicIP
            $QuickVMNode.HyperVHost = $ComputerName
            if ($QuickVMNode.PublicIP -notmatch "\b(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}\b")
            {
                $RecheckVMs.Add($ComputerName, $ALLVMs[$ComputerName])
                $AllPublicIPsCollected = $false
            }
            else
            {
                $QuickVMNode.RoleName = $VM.Name
                $QuickVMNode.HyperVGroupName = $VM.Groups.Name
                $allDeployedVMs += $QuickVMNode
                LogMsg "    Collected $($QuickVMNode.RoleName) from $($QuickVMNode.HyperVGroupName) data!"
            }
        }
    }
    return $allDeployedVMs
}

Function RestartAllHyperVDeployments($allVMData)
{
    foreach ( $VM in $allVMData )
    {
        $out = StopHyperVGroupVMs -HyperVGroupName $VM.HyperVGroupName -HyperVHost $VM.HyperVHost
    }
    foreach ( $VM in $allVMData )
    {
        $out = StartHyperVGroupVMs -HyperVGroupName $VM.HyperVGroupName -HyperVHost $VM.HyperVHost
    }
	$isSSHOpened = isAllSSHPortsEnabledRG -AllVMDataObject $AllVMData
	return $isSSHOpened    
}

Function InjectHostnamesInHyperVVMs($allVMData)
{
    $ErrorCount = 0
    try 
    {
        foreach ( $VM in $allVMData )
        {
            LogMsg "Injecting hostname '$($VM.RoleName)' in HyperV VM..."
            if(!$IsWindows)
            {
                $out = RunLinuxCmd -username $user -password $password -ip $VM.PublicIP -port $VM.SSHPort -command "echo $($VM.RoleName) > /etc/hostname" -runAsSudo -maxRetryCount 5
            }
            else
            {
                $cred = Get-Cred $user $password
                Invoke-Command -ComputerName $VM.PublicIP -ScriptBlock {$computerInfo=Get-ComputerInfo;if($computerInfo.CsDNSHostName -ne $args[0]){Rename-computer -computername $computerInfo.CsDNSHostName -newname $args[0] -force}} -ArgumentList $VM.RoleName -Credential $cred
            }
        }
        $RestartStatus = RestartAllHyperVDeployments -allVMData $allVMData 
    }
    catch 
    {
        $ErrorCount += 1
    }
    finally 
    {
        if ( ($ErrorCount -eq 0) -and ($RestartStatus -eq "True"))
        {
            LogMsg "Hostnames are injected successfully."
        }
        else 
        {
            LogErr "Failed to inject $ErrorCount hostnames in HyperV VMs. Continuing the tests..."    
        }
    }
}

Function Get-Cred($user, $password)
{
    $secstr = New-Object -TypeName System.Security.SecureString
    $password.ToCharArray() | ForEach-Object {$secstr.AppendChar($_)}
    $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $user, $secstr
    Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
    return $cred
}