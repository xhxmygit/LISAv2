# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.

<#
.Synopsis
    Delete a KVP item from a Linux guest.
.Description
    Delete a KVP item from pool 0 on a Linux guest.
#>

param([string] $TestParams)

function Main {
    param (
        $VMName,
        $HvServer,
        $RootDir,
        $TestParams
    )

    $key = $null
    $value = $null
    $tcCovered = "unknown"

    if (-not $TestParams) {
        LogErr "Error: No TestParams provided"
        LogErr "       This script requires the Key & value test parameters"
        return "Aborted"
    }
    if (-not $RootDir) {
        LogErr "Warn : no RootDir test parameter was supplied"
    } else {
        Set-Location $RootDir
    }

    $params = $TestParams.Split(";")
    foreach ($p in $params) {
        $fields = $p.Split("=")
        
        switch ($fields[0].Trim()) {
            "key"        { $key       = $fields[1].Trim() }
            "value"      { $value     = $fields[1].Trim() }
            "tc_covered" { $tcCovered = $fields[1].Trim() }
            default   {}  # unknown param - just ignore it
        }
    }
    if (-not $key) {
        LogErr "Error: Missing testParam Key to be added"
        return "FAIL"
    }
    if (-not $value) {
        LogErr "Error: Missing testParam Value to be added"
        return "FAIL"
    }

    # Delete the Key Value pair from the Pool 0 on guest OS. If the Key is already not present, will return proper message.
    LogMsg "Info : Creating VM Management Service object"
    $vmManagementService = Get-WmiObject -ComputerName $HvServer -class "Msvm_VirtualSystemManagementService" `
                                -namespace "root\virtualization\v2"
    if (-not $vmManagementService) {
        LogErr "Error: Unable to create a VMManagementService object"
        return "FAIL"
    }

    $vmGuest = Get-WmiObject -ComputerName $HvServer -Namespace root\virtualization\v2 `
                    -Query "Select * From Msvm_ComputerSystem Where ElementName='$VMName'"
    if (-not $vmGuest) {
        LogErr "Error: Unable to create VMGuest object"
        return "FAIL"
    }

    LogMsg "Info : Creating Msvm_KvpExchangeDataItem object"
    $msvmKvpExchangeDataItemPath = "\\$HvServer\root\virtualization\v2:Msvm_KvpExchangeDataItem"
    $msvmKvpExchangeDataItem = ([WmiClass]$msvmKvpExchangeDataItemPath).CreateInstance()
    if (-not $msvmKvpExchangeDataItem) {
        LogErr "Error: Unable to create Msvm_KvpExchangeDataItem object"
        return "FAIL"
    }

    LogMsg "Info : Deleting Key '${key}' from Pool 0"
    $msvmKvpExchangeDataItem.Source = 0
    $msvmKvpExchangeDataItem.Name = $key
    $msvmKvpExchangeDataItem.Data = $value
    $result = $vmManagementService.RemoveKvpItems($vmGuest, $msvmKvpExchangeDataItem.PSBase.GetText(1))
    $job = [wmi]$result.Job
    while($job.jobstate -lt 7) {
        $job.get()
    } 
    if ($job.ErrorCode -ne 0) {
        LogErr "Error: Deleting the key value pair"
        LogErr "Error: Job error code = $($Job.ErrorCode)"

        if ($job.ErrorCode -eq 32773) {  
            LogErr "Error: Key does not exist.  Key = '${key}'"
            return "FAIL"
        } else {
            LogErr "Error: Unable to delete KVP key '${key}'"
            return "FAIL"
        }
    }
    if ($job.Status -ne "OK") {
        LogErr "Error: KVP delete job did not complete with status OK"
        return "FAIL"
    }

    # If we made it here, everything worked
    LogMsg "Info : KVP item successfully deleted"
    return "PASS"
}

Main -VMName $AllVMData.RoleName -HvServer $xmlConfig.config.Hyperv.Hosts.ChildNodes[0].ServerName `
        -RootDir $WorkingDirectory -TestParams $TestParams