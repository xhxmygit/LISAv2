# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
<#
.Synopsis
    Verify the Hyper-V host logs a 18590 event in the Hyper-V-Worker-Admin
    event log when the Linux guest panics.
.Description
    The Linux kernel allows a driver to register a Panic Notifier handler
    which will be called if the Linux kernel panics.  The hv_vmbus driver
    registers a panic notifier handler.  When this handler is called, it
    will write to the Hyper-V crash MSR registers.  This results in the
    Hyper-V host logging a 18590 event in the Hyper-V-Worker-Admin event
    log.

.Parameter testParams
    Test data for this test case
#>
param([String] $TestParams)

$ErrorActionPreference = "Stop"

function Check-VMBusPanicEvent {
    param(
        $VMName,
        $HvServer,
        $Ipv4,
        $VMPort,
        $VMUsername,
        $VMPassword,
        $TestParams,
        $LogDir
    )

    LogMsg "Check minimum host build number"
    $buildNumber = Get-HostBuildNumber $hvServer
    if (!$buildNumber) {
        return "FAIL"
    }
    if ($BuildNumber -lt 9600) {
        return "ABORTED"
    }

    LogMsg "Make sure the VM is started"
    Start-VM -ComputerName $hvServer -Name $vmName
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running"

    LogMsg "Make sure kdump is configured on the VM"
    if ($TestParams.ENABLE_KDUMP -eq "true") {
        $installKdumpFile = "KDUMP-Config.sh"
        $installKdumpScript = "echo '${VMPassword}' | sudo -S -s eval `"export HOME=``pwd``;bash ${installKdumpFile} > install_kdump.log`""
        $installKdumpLog = "/home/${VMUserName}/install_kdump.log"
        RunLinuxCmd -username $VMUserName -password $VMPassword `
                    -ip $Ipv4 -port $VMPort $installKdumpScript -runAsSudo
        RemoteCopy -download -downloadFrom $Ipv4 -files $installKdumpLog `
                   -downloadTo $LogDir -port $VMPort -username $VMUserName `
                   -password $VMPassword

        Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
        Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Off"
        Start-VM -ComputerName $hvServer -Name $vmName
        Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running"
        Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer
    }

    LogMsg "Enable sysrq on VM"
    $enableSysrqScript = "echo '${VMPassword}' | sudo -S -s eval `"export HOME=``pwd``;sysctl -w kernel.sysrq=1`""
    RunLinuxCmd -username $VMUserName -password $VMPassword `
                -ip $Ipv4 -port $VMPort $enableSysrqScript

    LogMsg "Trigger kernel panic on the VM"
    $prePanicTime = [DateTime]::Now
    $triggerSysrqScript = "echo '${VMPassword}' | sudo -S -s eval `"export HOME=``pwd``;echo 'echo c > /proc/sysrq-trigger' | at now + 1 minutes`""
    RunLinuxCmd -username $VMUserName -password $VMPassword `
                -ip $Ipv4 -port $VMPort $triggerSysrqScript

    LogMsg "Check host event log for the 18590 event from the VM"
    Start-Sleep -Seconds 60
    $testPassed = Get-VMPanicEvent -VMName $VMName -HvServer $HvServer `
                                   -StartTime $prePanicTime
    if (-not $testPassed) {
        LogErr "Error: Event 18590 was not logged by VM ${vmName}"
        LogErr "Make sure KDump status is stopped on the VM"
        return "FAIL"
    } else {
        LogMsg "VM ${vmName} successfully logged an 18590 event"
    }

    LogMsg "Stop / Start VM to check the sanity"
    Stop-VM -ComputerName $hvServer -Name $vmName -Force -Confirm:$false
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Off"
    Start-VM -ComputerName $hvServer -Name $vmName
    Wait-VMState -VMName $VMName -HvServer $HvServer -VMState "Running"
    Wait-VMHeartbeatOK -VMName $VMName -HvServer $HvServer

    return "PASS"
}

try {
    Check-VMBusPanicEvent -VMName $AllVMData.RoleName `
        -HvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
        -Ipv4 $AllVMData.PublicIP -VMPort $AllVMData.SSHPort `
        -VMUserName $user -VMPassword $password `
        -TestParams (ConvertFrom-StringData $TestParams.Replace(";","`n")) `
        -LogDir $LogDir
    
} catch {
    LogErr "Error triggering VMBus panic event with error message: $_"
    return "FAIL"
}