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


#--------------------------------------------------------------------------
# Used version for oozie and its dependencies
$oozieVersion = "@oozie.version@"
$hadoop_version = "@hadoop.version@"

# Oozie setup default values
$oozieRootName = "oozie"
$defaultInstallRoot = Resolve-Path "$ENV:HADOOP_HOME\.."
$defaultIsotopeGroup = "hadoopusers"
$defaultCoreSiteXmlPath = "$ENV:HADOOP_HOME\etc\hadoop\core-site.xml"
$oozieDistro = "oozie-win-distro"

# Oozie Service configuration
$defaultServiceDir = "Service"
$oozieServiceName = "oozieservice"
$oozieSeviceDisplayName = "Apache Oozie Service"

$ErrorActionPreference = "stop"
#--------------------------------------------------------------------------


# Check whether the given string is Null or empty
function IsNullOrEmpty($str)
{
    return (($str -eq $Null) -or ($str -eq ""));
}

# Write the error message to the console
function WriteError($error_message)
{
    Write-Host $error_message -foregroundcolor red
    Write-Log $error_message
}

# Write the success message to the console
function WriteSuccess($success_message)
{
    Write-Host $success_message -foregroundcolor green
    Write-Log $success_message
}

# Write the warning message to the console
function WriteWarning($message)
{
    Write-Host $message -foregroundcolor yellow
    Write-Log "WARNING: $message"
}

# Validate path arguments
function validatePath($path)
{
    $valid = $false
    if (!(IsNullOrEmpty($path)))
    {
        $valid = $true
    }

    return $valid
}

# Get the installation directory, using the following order:
# - Use the proposed path provided if it is valid
# - Use the path set in Environment variable HADOOP_NODE_INSTALL_ROOT if it is available and valid
# - Use the default path
function getInstallRoot([string] $install_root)
{
    # Resolve the Install root directory
    if (! (validatePath($install_root)))
    {
        Write-Log "install_root is not provided. Checking HADOOP_NODE_INSTALL_ROOT environment variable"

        # Check if the environment variable is set
        if(! (validatePath($ENV:HADOOP_NODE_INSTALL_ROOT)))
        {
            Write-Log "Using default install path: $defaultInstallRoot"
            if (! (validatePath($defaultInstallRoot)))
            {
                WriteError "$defaultInstallRoot is not a valid path"
                throw "Invalid install directory"
            }

            $install_root = $defaultInstallRoot
        }
        else
        {
            # Use install path set in HADOOP_NODE_INSTALL_ROOT
            $install_root = $ENV:HADOOP_NODE_INSTALL_ROOT
        }
    }

    return $install_root
}

# Get the oozie-bin dorectory
function getOozieBin()
{
    if (!(Test-Path $ENV:OOZIE_ROOT))
    {
        WriteError "Oozie Root not set"
        return $null
    }

    $oozieBin = Join-Path $ENV:OOZIE_ROOT "$oozieDistro\bin"
    if (! (Test-Path $oozieBin))
    {
        WriteWarning "Oozie bin path - [$OozieBin] does not exist"
    }

    return $oozieBin
}

# Invoke cmd with the given command. This is mainly needed to
function RunCmd()
{
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string] $command
    )

    Write-Log "Executing command - $command"

    # Run the given command
    $ret = cmd.exe /c "$command"
    if($lastExitCode -ne 0)
    {
        # Show warning
        WriteWarning "CMD $command exited with error code $lastExitCode"
    }
    else
    {
        # The command succeeded
        Write-Log "CMD $command returned error code 0"
    }

   return $ret
}
