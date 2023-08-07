# line allows UAC to configure per all users
#Requires -RunAsAdministrator

$serv

# This function make a concatination of two code blocks into one code block, to run it in one scope/context
function ConcatenateScriptBlocks {
    Param([scriptblock] $template, [scriptblock] $body)
    $ScriptBlock = [System.Management.Automation.ScriptBlock]::Create("$template ; $body")
    Return $ScriptBlock 
}

# Start template common functions block
$templateBlock = {
    #$WarningPreference = 'SilentlyContinue'
    #$VerbosePreference = 'SilentlyContinue'
    #$DebugPreference = 'SilentlyContinue'
    $ErrorActionPreference = 'Continue'
    ForEach ($keyname in $args.Keys) {
        Set-Variable -Name ${keyname} -Value $args.$keyname
    }
    Set-PowerCLIConfiguration -ParticipateInCEIP:$false -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -DisplayDeprecationWarnings $False -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds 1500 -Confirm:$false | Out-Null
    Write-Output "Connecting to $Server..."
    $serv = Connect-CIServer -Server $Server -User $User -Password $Passwd -Org $Org
    Write-Output "Connected."
    if ($? -eq $false) {Throw $error[0].exception}
}

# Old function for non-Docker agents
Function Initialize-vCloud-Scripts {
    if (Get-InstalledModule -Name VmWare.PowerCLI) {
        Update-Module -Name VmWare.PowerCLI
    } else {
        Install-Module VmWare.PowerCLI
    }
    Write-Output "Prepare-vCloud-Scripts PowerCLI configuration"
    Set-PowerCLIConfiguration -ParticipateInCEIP:$false -Confirm:$false | Out-Null
    Write-Output "Prepare-vCloud-Scripts set up invalid certificate ignoring"
    # Scope requires root/Administrator grants -Scope AllUsers
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -DisplayDeprecationWarnings $False -Confirm:$false | Out-Null
    Set-PowerCLIConfiguration -WebOperationTimeoutSeconds 1500 -Confirm:$false | Out-Null
    Write-Output "Prepare-vCloud-Scripts configuration finished"
}
# line allows UAC to configure per all users #Requires -RunAsAdministrator

Function New-vApp {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Description                          = 'Default vApp description',
        [Parameter(Mandatory=$true)][string]$Template,
        [Parameter(Mandatory=$true)][string]$Catalog,
        [Parameter(Mandatory=$true)][string]$Ovdc
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            try {
                $resolvedTemplate = Get-CIVAppTemplate -Name "${Template}" -Catalog "${Catalog}"
                if ($? -eq $false) { Throw $error[0].exception}
            }
            catch { Write-Output "The vApp template name ${Template} was not found."; Exit 1 }
            Write-Output "Creating ${Name} vapp..."
            try {
                $citask = New-CIVApp -Name "${Name}" -VAppTemplate $resolvedTemplate -OrgVdc "${Ovdc}" -Description "${Description}" -RunAsync
                Start-Sleep -seconds 10
            }
            catch {
                Write-Output "ERROR: New vApp with name ${Name} was not created"
            }    

            if (-not $citask) {
                Write-Output "$Name has not created."
            } else {
                Write-Output "Creating $citask in progess"
            }
            
            $old_Percent=''
            while ($citask.State -eq 'Running') { 
                if ($old_Percent -ne $citask.PercentComplete) {
                    Write-Output "Completed: $($citask.PercentComplete) %" 
                    $old_Percent = $citask.PercentComplete
                }
                Start-Sleep -Seconds 10
                $citask = Get-Task -Id $citask.Id
            }
            Write-Output "Status is: $($citask.State)"
            
            Write-Output "Granting FullControl access rights for Everyone in Org to vApp: ${Name}."
            $set_access = New-CIAccessControlRule -Entity "${Name}" -EveryoneInOrg -AccessLevel "FullControl" -Confirm:$false
            if (-not $set_access) {
                Write-Output "Can't share vApp ${Name} to everyone."; Exit 1
            }
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

Function Get-vApp-IPs {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Ip_Json
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            if (!(Get-CIVApp -Name "${Name}")) { Write-Output "The vApp name ${Name} was not found."; Exit 1 }
            $vms = Get-CIVM -VApp "${Name}"
            if (!$vms) { Write-Output "Can't get VMs in vApp: ${Name}."; Exit 1}
            $globalJson =@()
            
            foreach ($vm in $vms) {
	            Write-Host ( "Processing VM: '{0}'." -f $vm )
                $netAdapters = Get-CINetworkAdapter -VM $vm
                $ips = @()
	            $extip = ''
                $ip = ''
                foreach ($adapter in $netAdapters) {
                    if ($adapter.ExternalIpAddress) {
                        #Write-Output "External Ip Address is present"
    		            $extip = $adapter.ExternalIpAddress.ToString()
                        $ips += $extip
                    }
                    #else { Write-Output "Error: External Ip Address is null" }
                    if ($adapter.IPAddress) { 
                        #Write-Output "Ip Address is present"
		                $ip = $adapter.IPAddress
                        $ips += $ip.ToString()
                    }
                    #else { Write-Output "Error: Ip Address is null" }
                }
                $globalJson += ('"' + ($vm.ToString()) + '":["' + (($ips | Sort-Object | Get-Unique -AsString) -join '","') + '"]')
            }
            $out = '{' + ($globalJson -join ',') + '}'
            $out | Set-Content $Ip_Json
            #Return $out 
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        Write-Host "**** Invoke job runner"
        BGJobRunner -data $mainScript -vars $PSBoundParameters
        Write-Host "**** Job runner done"
    }
}

Function Start-vApp {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            Write-Output "Power on the vApp ${Name}..."
            try {
                # In this case, we got a vcd task object and can wait for the result without dances with tumbao
                $citask = Get-CIVapp -Name "$Name" | Start-CIVApp -RunAsync
            } catch {
                Write-Output "Can't start the vApp by $Name"
            }
            if ($null -eq $citask) {
                    Write-Output "No vCD object related to name $Name"
                    exit 1
            }
            while ($citask.State -eq 'Running') { 
                #Useful objects of task. Kept for further research
                <#    if ($old_Percent -ne $citask.PercentComplete) {
                    Write-Output "Completed: $($citask.PercentComplete) %" 
                    Write-Output "CmdletTaskInfo : $($citask.CmdletTaskInfo ) %" 
                    Write-Output "Description : $($citask.Description ) %" 
                    Write-Output "ExtensionData : $($citask.ExtensionData ) %" 
                    Write-Output "FinishTime : $($citask.FinishTime ) %" 
                    Write-Output "Href : $($citask.Href ) %" 
                    Write-Output "Id : $($citask.Id ) %" 
                    Write-Output "IsCancelable : $($citask.IsCancelable ) %" 
                    Write-Output "Name : $($citask.Name ) %" 
                    Write-Output "Result  : $($citask.Result  ) %" 
                    Write-Output "StartTime  : $($citask.StartTime  ) %" 
                    Write-Output "State  : $($citask.State  ) %" 
                    Write-Output "Uid  : $($citask.Uid  ) %" 
                    $old_Percent = $citask.PercentComplete
                } #>
                Start-Sleep -Seconds 10
                $citask = Get-Task -Id $citask.Id
            }
            Write-Output "Powered on. Status is: $($citask.State)"
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

Function Stop-vApp {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            $ErrorActionPreference = 'SilentlyContinue'
            $vApp = Get-CIVApp -Name "${Name}" 
            if ($vApp -and $vApp.Status -eq 'PoweredOn') {
                Stop-CIVApp -VApp "${Name}" -Confirm:$false -RunAsync:$false
                if ($? -eq $false) { Write-Output $error[0].exception }
            }
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

Function Remove-vApp {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            $ErrorActionPreference = 'SilentlyContinue'
            $vApp = Get-CIVApp -Name "${Name}" 
            if ($vApp -and $vApp.Status -eq 'PoweredOff') {
                Remove-CIVApp -VApp "${Name}" -Confirm:$false -RunAsync:$false
                if ($? -eq $false) { Throw $error[0].exception }
            } else { Throw "vApp is running"}
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

Function New-vAppTemplate {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$vAppName,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][string]$TemplateName,
        [Parameter(Mandatory=$true)][string]$CatalogName,
        [Parameter(Mandatory=$true)][string]$Ovdc

    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            try {
                $myCatalog = Get-Catalog -Name "${CatalogName}"
                $vApp = Get-CIVApp -Name "${vAppName}"
                New-CIVAppTemplate -Name "${TemplateName}" -VApp "${vApp}" -OrgVdc "${Ovdc}" -Catalog "${myCatalog}" -Description "${Description}" -RunAsync:$false
                if ($? -eq $false) { Throw $error[0].exception}
            }
            catch {
                Write-Output "ERROR: Create a new Template ${TemplateName} from vApp ${vAppName} failed" 
            }
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

Function Update-vAppTemplate {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$NewName,
        [string]$NewDescription,
        [int]$NewLease
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            if (Get-CIVAppTemplate -Name "${Name}") {
                if ($NewDescription) { Set-CIVAppTemplate -VAppTemplate "${Name}" -Description "${NewDescription}"
                    if ($? -eq $false) { Throw $error[0].exception }
                }
                if ($NewName) { Set-CIVAppTemplate -VAppTemplate "${Name}" -Name "${NewName}"
                    if ($? -eq $false) { Throw $error[0].exception }
                }
                if ($newLease) {
                    $timeSpan = New-Object System.Timespan $newLease,0,0,0
                    Set-CIVAppTemplate -VAppTemplate "${Name}" -StorageLease $timeSpan
                    if ($? -eq $false) { Throw $error[0].exception }
                }
            }
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}
Function Remove-vAppTemplate {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            $ErrorActionPreference = 'SilentlyContinue'
            try {
                if (Get-CIVAppTemplate -Name "${Name}") {
                    Remove-CIVAppTemplate -VAppTemplate "${Name}" -Confirm:$false -RunAsync:$false
                }
            }
            catch {
                Write-Output "Remove Template '${Name}' failed"
            }
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

Function Get-vApp-VMs {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][string]$User,
        [Parameter(Mandatory=$true)][string]$Passwd,
        [Parameter(Mandatory=$true)][string]$Org,
        [Parameter(Mandatory=$true)][string]$Name
    )
    Process {
        $codeBlock = {
            ForEach ($keyname in $PSBoundParameters.Keys) {
                Set-Variable -Name ${keyname} -Value $PSBoundParameters.$keyname
            }
            if (!(Get-CIVApp -Name "${Name}")) { Throw "The vApp name ${Name} was not found."; Exit 1 }
            Get-CIVM -VApp "${Name}"
        }
        $mainScript = ConcatenateScriptBlocks -template $templateBlock -body $codeBlock
        BGJobRunner -data $mainScript -vars $PSBoundParameters
    }
}

# Create and runs background Job and returns it results
Function BGJobRunner {

    param ([ScriptBlock] $data, $vars)

    Process {
        
        #This code should be removed. Backgroup run isn't useful and had to support.
        <#
        Start-Job -Name MyJob -ScriptBlock $data -OutVariable Test -ArgumentList $vars | Out-Null
        $log = ''
        while (Get-Job -State "Running") {
            try {
                Receive-Job MyJob -OutVariable log
            }
            catch { $log = '' }
            if ($log) { Write-Output $log } else { 
                Write-Host -NoNewline '.'
            }
            Start-Sleep 1
        }
        Start-Sleep 1
        $job = Get-Job -Name MyJob 
        if ($job.State -eq 'Failed') {
            Write-Output ($job.ChildJobs[0].JobStateInfo.Reason.Message) -ForegroundColor Red
            Exit 1
        } else {
            Write-Output (Receive-Job $job)
        }
        Receive-Job $job
        #>

        #Debug data. 
        #Write-Host "DATA: $data"
        #Write-Host "VARS: $vars"
        Invoke-Command -ScriptBlock $data -ArgumentList $vars 
    }
}
