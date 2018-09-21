# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Description
    This script compares the host provided information with the ones
    detected on a Linux guest VM.
    Pushes a script to identify the information inside the VM
    and compares the results.
    To work accordingly we have to disable dynamic memory first.
#>

param([string] $TestParams)

# Main script body
function Main {
    param (
        $VMName,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUserName,
        $VMPassword,
        $RootDir
    )
    # Checking the mandatory testParams. New parameters must be validated here.
    $remoteScript = "NUMA_check.sh"
    $stateFile = "${LogDir}\state.txt"

    $params = $TestParams.Split(";")
    foreach ($p in $params) {
        $fields = $p.Split("=")
        if ($fields[0].Trim() -eq "VCPU") {
            $numCPUs = $fields[1].Trim()
        }
        if ($fields[0].Trim() -eq "NumaNodes") {
            $vcpuOnNode = $fields[1].Trim()
        }
    }

    # Change the working directory to where we need to be
    if (-not (Test-Path $RootDir)) {
        LogErr "Error: The directory `"${RootDir}`" does not exist!"
        return "FAIL"
    }
    Set-Location $rootDir

    $kernel = RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 `
        -port $VMPort -command "uname -r" -runAsSudo
    if ($? -eq $false){
        LogWarn "WARNING: Could not get kernel version of $VMName"
    }

    $numaVal = Get-NumaSupportStatus $kernel
    if (-not $numaVal) {
        LogWarn "WARNING: NUMA not suported for kernel:`n $kernel"
        return "ABORTED"
    }

    # Extracting the node and port name values for the VM attached HBA
    $GetNumaNodes = Get-VM -Name $VMName -ComputerName $hvServer | Select-Object `
        -ExpandProperty NumaNodesCount

    # Send the Numa Nodes value to the guest if it matches with the number of CPUs
    if ($GetNumaNodes -eq $numCPUs/$vcpuOnNode) {
        LogMsg "Info: NumaNodes and the number of CPU are matched."
    } else {
        LogErr "Error: NumaNodes and the number of CPU does not match."
        return "FAIL"
    }
    $cmdAddConstants = "echo `"expected_number=$($numCPUs/$vcpuOnNode)`" >> /home/${VMUserName}/constants.sh"
    RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port `
        $VMPort -command $cmdAddConstants -runAsSudo
    if (-not $?) {
        LogErr "Error: Unable to submit command ${cmd} to VM!"
        return "FAIL"
    }

    $cmdRunNuma = "echo '${VMPassword}' | sudo -S -s eval `"export HOME=``pwd``;bash ${remoteScript} > NUMA-Test.log`""
    RunLinuxCmd -username $VMUserName -password $VMPassword -ip $Ipv4 -port $VMPort $cmdRunNuma -runAsSudo
    RemoteCopy -download -downloadFrom $Ipv4 -files "/home/${VMUserName}/state.txt" `
        -downloadTo $LogDir -port $VmPort -username $VMUserName -password $VMPassword
    RemoteCopy -download -downloadFrom $Ipv4 -files "/home/${VMUserName}/NUMA-Test.log" `
        -downloadTo $LogDir -port $VmPort -username $VMUserName -password $VMPassword
    $contents = Get-Content -Path $stateFile
    if (($contents -eq "TestAborted") -or ($contents -eq "TestFailed")) {
        LogErr "Error: Running $remoteScript script failed on VM!"
        return "FAIL"
    } else {
        LogMsg "Matching values for NumaNodes: $vcpuOnNode has been found on the VM!"
    }

    return "PASS"
}

Main -VMName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
         -ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
         -VMUserName $user -VMPassword $password -RootDir $WorkingDirectory