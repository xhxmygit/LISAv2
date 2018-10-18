# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Synopsis
    Run continous Ping while disabling and enabling the SR-IOV feature

.Description
    Continuously ping a server, from a Linux client, over a SR-IOV connection. 
    Disable SR-IOV on the Linux client and observe RTT increase.  
    Re-enable SR-IOV and observe that RTT lowers. 
#>

param ([string] $TestParams)

function Main {
    param (
        $VMName,
        $HvServer,
        $VMPort,
        $VMPassword
    )
    $VMRootUser = "root"

    # Get IP
    $ipv4 = Get-IPv4ViaKVP $VMName $HvServer

    # Run Ping with SR-IOV enabled
    RunLinuxCmd -ip $ipv4 -port $VMPort -username $VMRootUser -password `
        $VMPassword -command "source sriov_constants.sh ; ping -c 600 -I eth1 `$VF_IP2 > PingResults.log" `
        -RunInBackGround

    # Wait 30 seconds and read the RTT
    Start-Sleep -s 30
    [decimal]$vfEnabledRTT = RunLinuxCmd -ip $ipv4 -port $VMPort -username $VMRootUser -password `
        $VMPassword -command "tail -5 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'" `
        -ignoreLinuxExitCode:$true
    if (-not $vfEnabledRTT){
        LogErr "No result was logged! Check if Ping was executed!"
        return "FAIL"
    }
    LogMsg "The RTT before disabling SR-IOV is $vfEnabledRTT ms"

    # Disable SR-IOV on test VM
    Start-Sleep -s 5
    LogMsg "Disabling VF on vm1"
    Set-VMNetworkAdapter -VMName $VMName -ComputerName $HvServer -IovWeight 0
    if (-not $?) {
        LogErr "Failed to disable SR-IOV on $VMName!"
        return "FAIL" 
    }

    # Read the RTT with SR-IOV disabled; it should be higher
    Start-Sleep -s 30
    [decimal]$vfDisabledRTT = RunLinuxCmd -ip $ipv4 -port $VMPort -username $VMRootUser -password `
        $VMPassword -command "tail -5 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'" `
        -ignoreLinuxExitCode:$true
    if (-not $vfDisabledRTT){
        LogErr "No result was logged after SR-IOV was disabled!"
        return "FAIL"
    }

    LogMsg "The RTT with SR-IOV disabled is $vfDisabledRTT ms"
    if ($vfDisabledRTT -le $vfEnabledRTT) {
        LogErr "The RTT was lower with SR-IOV disabled, it should be higher"
        return "FAIL" 
    }

    # Enable SR-IOV on test VM
    Set-VMNetworkAdapter -VMName $VMName -ComputerName $HvServer -IovWeight 1
    if (-not $?) {
        LogErr "Failed to enable SR-IOV on $VMName!"
        return "FAIL" 
    }

    Start-Sleep -s 30
    # Read the RTT again, it should be lower than before
    # We should see values to close to the initial RTT measured
    [decimal]$vfEnabledRTT = $vfEnabledRTT * 1.3
    [decimal]$vfFinalRTT = RunLinuxCmd -ip $ipv4 -port $VMPort -username $VMRootUser -password `
        $VMPassword -command "tail -5 PingResults.log | head -1 | awk '{print `$7}' | sed 's/=/ /' | awk '{print `$2}'" `
        -ignoreLinuxExitCode:$true
    LogMsg "The RTT after re-enabling SR-IOV is $vfFinalRTT ms"
    if ($vfFinalRTT -gt $vfEnabledRTT) {
        LogErr "After re-enabling SR-IOV, the RTT value has not lowered enough"
        return "FAIL" 
    }

    return "PASS"
}

Main -VMName $AllVMData.RoleName -hvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
    -VMPort $AllVMData.SSHPort -VMPassword $password