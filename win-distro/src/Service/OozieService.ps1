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
    [Parameter(Mandatory=$true)] [string] $serviceAction
)

# Default log file and Oozie service names
$logFileName = "OozieService.log"
$oozieServiceName = "oozieservice"
$oozieVersion = "@oozie.version@"
$oozieDistro = "oozie-win-distro"

# Default timeout value to wait for until service status changes
$defaultWaitTimeout = 60
$serviceRunningStatus = "Running"
$serviceStoppedStatus = "Stopped"

$scriptDir = Resolve-Path (Split-Path $MyInvocation.MyCommand.Path)
$logFile = Join-Path $scriptDir $logFileName

# Write a message to the log file and display it to the user.
function Write-Log()
{
    param([Parameter(Mandatory=$true)] [string] $message)

    # Display the message
    Write-Host $message

    # Get the current date-time
    $logTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss,fff")

    # Prepare the log message
    $logMessage = "$logTime`: $message"
    Add-Content $logFile $logMessage
}

function Invoke-Cmd ($command)
{
    Write-Log $command
    $out = cmd.exe /C "$command" 2>&1

    if($lastExitCode -ne 0)
    {
        # Show CMD error
        Write-Log "CMD $command exited with error code $lastExitCode"
    }
    else
    {
        # The command succeeded
        Write-Log "CMD $command returned error code 0"
    }

    return $out
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
    $LastExitCode = 0
    # Check if the service exists
    $svc = Get-Service $oozieServiceName -ErrorAction SilentlyContinue
    if ($svc -eq $NULL)
    {
        Write-Log "Service $oozieServiceName does not exist"
        return $false
    }

    # Check if the service is already started
    if ($svc.Status -eq $serviceRunningStatus)
    {
        Write-Log "Service $oozieServiceName is already in running state. Skipping service start"
        return $true
    }

    Write-Log "Starting $oozieServiceName ..."

    # Start the oozie service
    Start-Service $oozieServiceName

    # Check for errors while starting the service
    if ($LastExitCode -ne 0)
    {
        Write-Log "Failed to start Oozie service, error-code: $LastExitCode"
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
    $LastExitCode = 0
    # Check if the service exists
    $svc = Get-Service $oozieServiceName -ErrorAction SilentlyContinue
    if ($svc -eq $NULL)
    {
        Write-Log "Service $oozieServiceName does not exist"
        return $false
    }

    # Check if the service is already started
    if ($svc.Status -ne $serviceRunningStatus)
    {
        Write-Log "Service $oozieServiceName is not started. Skipping stop-service"
        return $true
    }

    # Get the bin directory where the stop script is available
    $oozieRoot = [Environment]::GetEnvironmentVariable("OOZIE_ROOT","Machine")
    $oozieBin = Join-Path $oozieRoot "$oozieDistro\bin"
    if (!(Test-Path $oozieBin))
    {
        Write-Log "Oozie Bin directory not found: $oozieBin"
        return $false
    }

    pushd $OozieBin
    try
    {
        # Get the oozie-bin directory to call oozie-stop script
        Write-Log "Stopping $oozieServiceName ..."
        Stop-Service $oozieServiceName
        Invoke-Cmd "oozie-stop.cmd"
    }
    catch [Exception]
    {
        Write-Log "Failed to stop Oozie service with exception: "
        Write-Log $_.Exception.Message $_
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
    # Mark a new action log in the log file
    Add-Content $logFile "---------------------------------------------------------------------"
    Add-Content $logFile "Executing service action`: $serviceAction"
    Add-Content $logFile "---------------------------------------------------------------------"

    # Validate/Execute the service action
    $done = $false
    if ($serviceAction -ieq "start")
    {
        $done = startOozieService
    }
    elseif ($serviceAction -ieq "stop")
    {
        $done = stopOozieService
    }
    else
    {
        Write-Log "Unrecognized Service Action $serviceAction"
    }
}
finally
{
    if (! $done)
    {
        Write-Log "Failed to execute action: $serviceAction"
    }
}
