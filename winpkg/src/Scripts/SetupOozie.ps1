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
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string] $DISTRO_HOME,
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string] $username,
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string] $isotopeGroup,
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)] [string] $coreSiteFilePath,
    [string] $proxyHost,
    [string[]] $jarPath
)

# Include needed script
. './Common.ps1'
. './SecurityGroup.ps1'
. './EditXml.ps1'

Write-Log "---------------------------------------------------------------"
Write-Log "OOZIE Home:             $DISTRO_HOME"
Write-Log "Isotope User:           $username"
Write-Log "Isotope Group:          $isotopeGroup"
Write-Log "Core-Site file path:    $coreSiteFilePath"
Write-Log "---------------------------------------------------------------"

$ErrorActionPreference = "stop"

# Print the usage of the Install script
function printUsage()
{
    Write-Host "Usage  : Install.ps1 DISTRO_HOME isotopeUser isotopeGroup coreSiteFilePath [jarPath]"
}

# Set Oozie configurations (security group and host IP) in the given XML file
function setOozieConfigs([string] $xmlFile, [string] $username, [string] $isotopeGroup, [string] $ipAddress)
{
    # Load the XML file to edit
    $xmlObj = New-Object XML
    $xmlObj.Load($xmlFile)

    # Set the hadoop.proxyuser.[USER].groups property
    setProperty $xmlObj "hadoop.proxyuser.$username.groups" $isotopeGroup

    # Set the hadoop.proxyuser.[USER].hosts property
    setProperty $xmlObj "hadoop.proxyuser.$username.hosts" $ipAddress

    $xmlObj.Save($xmlFile)
}

#Get the IP Address of the host machine
function getHostIP()
{
    $networkConfigs = Get-WmiObject Win32_NetworkAdapterConfiguration -Namespace "root\CIMV2" | where{$_.IPEnabled -eq "True"}
    $ipAddress = $NULL
    foreach($networkConfig in $networkConfigs)
    {
        if (($networkConfig -ne $NULL) -and  ($networkConfig.IPAddress -ne $NULL))
        {
            $ipAddress = $networkConfig.IPAddress[0]
        }
    }
    return $ipAddress
}

# Get the Host name/IP to use for core-site settings
function getHost()
{
    $hostVal = $NULL
    if (IsNullOrEmpty $proxyHost)
    {
        # If not Host Name/IP is provided by the user, use the machine's IP address by default
        $hostVal = getHostIP
    }
    else
    {
        # Use the host specified by the user
        $hostVal = $proxyHost
    }
    return $hostVal
}

# Validate DISTRO_HOME parameter
if (!(validatePath $DISTRO_HOME) -or !(validatePath $coreSiteFilePath))
{
    printUsage
}

# STEP 1:
# Call Setup script to add Hadoop libs to the generated oozie.war file
$params = @{jars=$jarPath;
            inputWar="$DISTRO_HOME\oozie.war";
            outputWar="$DISTRO_HOME\oozie-server\webapps\oozie.war"}

Invoke-Expression -command "$DISTRO_HOME\bin\oozie-setup.ps1 @params"

if ($LastExitCode -ne 0)
{
    WriteError "Failed to add jars to oozie.war"
    exit $LastExitCode
}
else
{
    WriteSuccess "Jars successfully added to oozie.war"
}

# STEP 2:
# Add the isotope user to the group, and create the group if it does not already exist
if(! (addUserToGroup $isotopeGroup $username))
{
    WriteError "Failed to add User $username to group $isotopeGroup"
}
else
{
    WriteSuccess "User $username successfully added to $isotopeGroup."
}

# STEP 3
# Edit the XML settings with Oozie configurations
$hostIp = getHost
setOozieConfigs $coreSiteFilePath $username $isotopeGroup $hostIp

exit 0
