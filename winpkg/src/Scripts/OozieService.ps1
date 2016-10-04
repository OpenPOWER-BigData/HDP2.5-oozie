### Licensed to the Apache Software Foundation (ASF) under one or more
### contributor license agreements.  See the NOTICE file distributed with
### this work for additional information regarding copyright ownership.
### The ASF licenses this file to You under the Apache License, Version 2.0
### (the "License"); you may not use this file except in compliance with
### the License.  You may obtain a copy of the License at
###
###     http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.

param(
    [string] $serviceAction
)

# Include the common script
. './Common.ps1'

# Default timeout value to wait for until service status changes
$defaultWaitTimeout = 60
$serviceRunningStatus = "Running"
$serviceStoppedStatus = "Stopped"

# Check if the service exists
function serviceExists()
{
    $service = Get-Service $oozieServiceName -ErrorAction SilentlyContinue
    return ($service -ne $NULL)
}

# Create a windows service for oozie server
function createOozieService()
{
    # Parameter list for createOozieService
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)] $serviceCredentials,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string] $oozieServiceExe
    )
    
    # Exit if the service already exists
    if (serviceExists)
    {
        WriteWarning "Service $oozieServiceName already exists. Service creation skipped"
        return $false
    }
    
    if (! (Test-Path $oozieServiceExe))
    {
        WriteError "$oozieServiceExe does not exist. Cannot create Oozie service"
        return $false
    }

    $svcCreated = $false
    Write-Log "Creating $oozieServiceName ..."
    
    try
    {
        #serviceHost.exe will write to this log but does not create it
        #Creating the event log needs to be done from an elevated process, so we do it here
        if( -not ([Diagnostics.EventLog]::SourceExists( "$oozieServiceName" )))
        {
            [Diagnostics.EventLog]::CreateEventSource( "$oozieServiceName", "" )
        }
        
        # Create the service
        Write-Log "Adding service $oozieServiceName"
        $svc = New-Service -Name "$oozieServiceName" -BinaryPathName "$oozieServiceExe" -Credential $serviceCredentials -DisplayName "$oozieSeviceDisplayName"
        
        # Configure the service
        Write-Log "Configuring service $oozieServiceName"
        RunCmd "$ENV:WINDIR\system32\sc.exe failure $oozieServiceName reset= 30 actions= restart/5000"
        RunCmd "$ENV:WINDIR\system32\sc.exe config $oozieServiceName start= auto"
        
        # All service to be controlled by other users
        Write-Log "Adding service control permissions to authenitcated users for service $oozieServiceName"
        Set-ServiceAcl $oozieServiceName
        
        $svcCreated = $true
    }
    catch [Exception]
    {
        Write-Log $_.Exception.Message $_
        WriteError "Oozie service creation failed. Please look at the logs for details"
    }
    
    return $svcCreated
}

# Delete oozie service
function deleteOozieService()
{
    Write-Log "Deleting $oozieServiceName ..."
    
    # Get the oozie service
    $svc = Get-Service $oozieServiceName -ErrorAction SilentlyContinue 

    # Delete the service
    if( $svc -ne $null )
    {
        RunCmd "sc delete $oozieServiceName"
    }

    # Check for errors while deleting the service
    if ($LastExitCode -ne 0)
    {
        WriteError "Failed to delete Oozie service, error-code: $LastExitCode"
        return $false
    }

    # Delete Service event source
    if([Diagnostics.EventLog]::SourceExists( "$oozieServiceName" ))
    {
        [Diagnostics.EventLog]::DeleteEventSource( "$oozieServiceName" )
    }
    
    return $true
}

# Wait until the status of the service changes to the target state
function waitForStatusChange([string] $targetState)
{
    $waitTime = $defaultWaitTimeout
    $waitIncrement = 3
    
    # Wait until service status changes to the target state
    do
    {
        # Wait for one second
        Start-Sleep -Seconds $waitIncrement
        $waitTime-=$waitIncrement
        
        # Check again on the status of the service
        $foundservice = Get-Service $oozieServiceName
    }
    while (($foundservice.Status -ne "$targetState") -and ($waitTime -gt 0))
    
    return ($foundservice.Status -eq "$targetState")
}

# Start oozie service
function startOozieService()
{
    # Check if the service exists
    $svc = Get-Service $oozieServiceName -ErrorAction SilentlyContinue 
    if ($svc -eq $NULL)
    {
        WriteError "Service $oozieServiceName does not exist"
        return $false
    }
    
    # Check if the service is already started
    if ($svc.Status -eq $serviceRunningStatus)
    {
        WriteWarning "Service $oozieServiceName is already in running state. Skipping service start"
        return $true
    }

    Write-Log "Starting $oozieServiceName ..."
    
    # Start the oozie service
    Start-Service $oozieServiceName
    
    # Check for errors while starting the service
    if ($LastExitCode -ne 0)
    {
        WriteError "Failed to start Oozie service, error-code: $LastExitCode"
        return $false
    }
    
    # Wait until the service starts
    Write-Log "Waiting for service to start"
    $started = $false
    if (waitForStatusChange $serviceRunningStatus)
    {
        Write-Log "Oozie Service started succesfully"
        $started = $true
    }
    else
    {
        Write-Log "Timed-out waiting for Oozie Service to transition to running state"
        $started = $false
    }
    
    return $started
}

# Stop oozie service
function stopOozieService([string] $OozieBin)
{
    # Check if the service exists
    $svc = Get-Service $oozieServiceName -ErrorAction SilentlyContinue 
    if ($svc -eq $NULL)
    {
        WriteError "Service $oozieServiceName does not exist"
        return $false
    }
    
    # Check if the service is already started
    if ($svc.Status -ne $serviceRunningStatus)
    {
        WriteWarning "Service $oozieServiceName is not started. Skipping stop-service"
        return $true
    }
    
    # Get the bin directory where the stop script is available
    $oozieBin =  getOozieBin
    if (!(Test-Path $oozieBin))
    {
        WriteError "Oozie Bin directory not found: $oozieBin"
        return $false
    }
    
    pushd $OozieBin
    try
    {
        # Get the oozie-bin directory to call oozie-stop script
        Write-Log "Stopping $oozieServiceName ..."
        Stop-Service $oozieServiceName
        RunCmd "oozie-stop.cmd"
    }
    catch [Exception]
    {
        WriteError "Failed to stop Oozie service with exception: "
        WriteError $_.Exception.Message $_
        return $false
    }
    finally
    {
        popd
    }
    
    # Wait until the service stops
    Write-Log "Waiting for service to stop"
    $stopped = $false
    if (waitForStatusChange $serviceStoppedStatus)
    {
        Write-Log "Oozie Service stopped succesfully"
        $stopped = $true
    }
    else
    {
        Write-Log "Timed-out waiting for Oozie Service to transition to stopped state"
        $stopped = $false
    }
    
    return $stopped
}

try
{
    if (!(IsNullOrEmpty($serviceAction)))
    {
        $scriptDir = Resolve-Path (Split-Path $MyInvocation.MyCommand.Path)
        $utilsModule = Import-Module -Name "$scriptDir\..\resources\Winpkg.Utils.psm1" -ArgumentList ("OOZIE") -PassThru
        
        if ($serviceAction -ieq "start")
        {
            startOozieService
        }
        elseif ($serviceAction -ieq "stop")
        {
            stopOozieService
        }
    }
}
finally
{
    if( $utilsModule -ne $null )
    {
        Remove-Module $utilsModule
    }
}
