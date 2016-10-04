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

###
### A set of basic PowerShell routines that can be used to install and
### manage Hadoop services on a single node. For use-case see install.ps1.
###

###
### Global variables
###
$ScriptDir = Resolve-Path (Split-Path $MyInvocation.MyCommand.Path)

$FinalName = "oozie-@oozie.version@"
$OozieDistroName = "oozie-win-distro"
$hadoop_version = "@hadoop.version@"


###############################################################################
###
### Installs oozie.
###
### Arguments:
###     component: Component to be installed, it can be "core, "hdfs" or "mapreduce"
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###     serviceCredential: Credential object used for service creation
###     role: Space separated list of roles that should be installed.
###           (for example, "jobtracker historyserver" for mapreduce)
###
###############################################################################
function Install(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $nodeInstallRoot,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=2, Mandatory=$true )]
    $serviceCredential,
    [String]
    [Parameter( Position=3, Mandatory=$false )]
    $roles
    )
{
    if ( $component -eq "oozie" )
    {
        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

        ### $oozieInstallDir: the directory that contains the appliation, after unzipping
        $oozieInstallToDir = Join-Path "$nodeInstallRoot" "$FinalName"
        $oozieDistroHome = Join-Path "$oozieInstallToDir" "$OozieDistroName"
        $oozieDistroBin = Join-Path "$oozieDistroHome" "bin"
        $oozieServiceFolder = Join-Path "$oozieInstallToDir" "Service"
        Write-Log "oozieInstallToDir: $oozieInstallToDir"

        InstallBinaries $nodeInstallRoot $serviceCredential
        if ($roles) {

	  ###
	  ### Create oozie Windows Services and grant user ACLS to start/stop
	  ###
	  Write-Log "Node oozie Role Services: $roles"

	  ### Verify that roles are in the supported set
	  CheckRole $roles @("oozieservice")

	  $service = "oozieservice"
	  CreateAndConfigureHadoopService $service $HDP_RESOURCES_DIR $oozieServiceFolder $serviceCredential
	  Write-Log "Configuring service config ${oozieServiceFolder}\$service.xml"
	  $OozieServiceXml = "$oozieServiceFolder\$service.xml"
        $OozieServiceExe = "$oozieDistroBin\oozied.cmd"

	  # Update the service.xml file to point to the service executable
	  if (! (updateServiceXml $OozieServiceXml $OozieServiceExe))
	  {
	      Write-Log "Failed to update $OozieServiceXmlwith oozie servuce executable" "Failure"
	      throw "Install: Failed to update $OozieServiceXmlwith oozie servuce executable"
	  }
        }

        # Append extra_libs to the jarPath by default
        $oozieExtraJars = @("$oozieInstallToDir\extra_libs\*.jar")
        $oozieShare = "$oozieDistroHome\share"
        $oozieShareOozie = Join-Path $oozieShare "lib\oozie"

        # Copy additional Jars
        Write-Log "Copy Oozie additional Jars"
        $oozieExtraJars | % {
            Copy-Item $_ $oozieShareOozie -force
        }

        # Call Setup script to add Hadoop libs to the generated oozie.war file
        Write-Log "Calling Setup script to add Hadoop libs to the generated oozie.war file"
        $params = @{command="prepare-war";d="$oozieInstallToDir\extra_libs"}

        Invoke-Expression -command "$oozieDistroBin\oozie-setup.ps1 @params"
    }
    else
    {
        throw "Install: Unsupported compoment argument."
    }
}

###############################################################################
###
### Uninstalls Hadoop component.
###
### Arguments:
###     component: Component to be uninstalled, it can be "core, "hdfs" or "mapreduce"
###     nodeInstallRoot: Install folder (for example "C:\Hadoop")
###
###############################################################################
function Uninstall(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $nodeInstallRoot
    )
{
    if ( $component -eq "oozie" )
    {

        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

        ### $oozieInstallDir: the directory that contains the appliation, after unzipping
        $oozieInstallToDir = Join-Path "$nodeInstallRoot" "$FinalName"
        Write-Log "oozieInstallToDir: $oozieInstallToDir"

        ###
        ### Stop and delete services
        ###
        foreach( $service in ("oozieservice"))
        {
            StopAndDeleteHadoopService $service
        }

        ###
        ### Delete the oozie directory
        ###
        Write-Log "Deleting $oozieInstallToDir"
        $cmd = "rd /s /q `"$oozieInstallToDir`""
        Invoke-Cmd $cmd

        ###
        ### Removing OOZIE_ROOT environment variable
        ###
        Write-Log "Removing ENV:OOZIE_ROOT at machine scope"
        [Environment]::SetEnvironmentVariable( "OOZIE_ROOT", $null, [EnvironmentVariableTarget]::Machine )

    }
    else
    {
        throw "Uninstall: Unsupported component argument."
    }
}

###############################################################################
###
### Alters the configuration of the component.
###
### Arguments:
###     component: Component to be configured, e.g "core, "hdfs" or "mapreduce"
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###     serviceCredential: Credential object used for service creation
###     configs: Configuration that should be applied.
###              For example, @{"fs.checkpoint.edits.dir" = "C:\Hadoop\hdfs\2nne"}
###              Some configuration parameter are aliased, see ProcessAliasConfigOptions
###              for details.
###     aclAllFolders: If true, all folders defined in config file will be ACLed
###                    If false, only the folders listed in $configs will be ACLed.
###
###############################################################################
function Configure(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $nodeInstallRoot,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=2, Mandatory=$true )]
    $serviceCredential,
    [hashtable]
    [parameter( Position=3 )]
    $configs = @{},
    [bool]
    [parameter( Position=4 )]
    $aclAllFolders = $True
    )
{
    if ( $component -eq "oozie" )
    {
        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

        ### $oozieInstallDir: the directory that contains the appliation, after unzipping
        $oozieInstallToDir = Join-Path "$nodeInstallRoot" "$FinalName"
        Write-Log "oozieInstallToDir: $oozieInstallToDir"

        if( -not (Test-Path $oozieInstallToDir ))
        {
            throw "Configureoozie: Install the oozie before configuring it"
        }

        $additionalConfig = @{
            "oozie.service.HadoopAccessorService.hadoop.configurations" = "*=$ENV:HADOOP_CONF_DIR";}

        $configs = UpdateConfigWithAdditionalProperties($configs)($additionalConfig)

        ###
        ### Apply configuration changes to oozie-site.xml
        ###
        $xmlFile = Join-Path $oozieInstallToDir "$OozieDistroName\conf\oozie-site.xml"
        UpdateXmlConfig $xmlFile $configs

        ###
        ### Updating admin file
        ###
        $adminFile = Join-Path $oozieInstallToDir "$OozieDistroName\conf\adminusers.txt"
        Add-Content -Path $adminFile -Value "hadoop" -ErrorAction Stop 
        
        ###
        ### Apply HA
        ###
        if ((Test-Path ENV:IS_OOZIE_HA) -and ($ENV:IS_OOZIE_HA -eq "yes"))
        {
            Write-Log "Configuring HA"
            $lines = Get-Content "$ENV:OOZIE_HOME\bin\oozie-sys.cmd"
            $pos = [array]::indexof($lines, $lines -match "@echo off")
            $newLines = $lines[0..($pos +1)], "set OOZIE_BASE_URL=$ENV:OOZIE_BASE_URL", $lines[$pos..($lines.Length + 1)]
            $newLines | Set-Content "$ENV:OOZIE_HOME\bin\oozie-sys.cmd"
        }
        
        ###
        ### Copying hive-site and tez-site xmls to etc\action-conf\hive
        ###
        Write-Log "Copying hive-site and tez-site xmls to etc\action-conf\hive"
        if (-not (Test-Path "$ENV:OOZIE_HOME\conf\action-conf\hive"))
        {
            New-Item -Path "$ENV:OOZIE_HOME\conf\action-conf\hive" -ItemType Directory -Force -ErrorAction Stop
        }
        Copy-Item -Path "$ENV:HIVE_HOME\conf\hive-site.xml" -Destination "$ENV:OOZIE_HOME\conf\action-conf\hive\hive-site.xml" -Force -ErrorAction Stop
        if (Test-Path "$ENV:TEZ_HOME\conf\tez-site.xml")
        {
            Copy-Item -Path "$ENV:TEZ_HOME\conf\tez-site.xml" -Destination "$ENV:OOZIE_HOME\conf\action-conf\hive\tez-site.xml" -Force -ErrorAction Stop
        }
    }
    else
    {
        throw "Configure: Unsupported compoment argument."
    }
}


### Helper function that adds the given properties to config if not already present
Function UpdateConfigWithAdditionalProperties([hashtable] $configs, [hashtable] $additionalConfig)
{
    $additionalConfig.GetEnumerator() | ForEach-Object {
        if( -not ($configs.ContainsKey($_.Key)))
        {
            $configs.Add($_.Key, $_.Value)
        }
    }
    return $configs
}


###############################################################################
###
### Start component services.
###
### Arguments:
###     component: Component name
###     roles: List of space separated service to start
###
###############################################################################
function StartService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $roles
    )
{
    Write-Log "Starting `"$component`" `"$roles`" services"

    if ( $component -eq "oozie" )
    {
        ### Verify that roles are in the supported set
        CheckRole $roles @("oozieservice")

        foreach ( $role in $roles.Split(" ") )
        {
            Write-Log "Starting $role service"
            Start-Service $role
        }
    }
    else
    {
        throw "StartService: Unsupported compoment argument."
    }
}

###############################################################################
###
### Stop component services.
###
### Arguments:
###     component: Component name
###     roles: List of space separated service to stop
###
###############################################################################
function StopService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $component,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $roles
    )
{
    Write-Log "Stopping `"$component`" `"$roles`" services"

    if ( $component -eq "oozie" )
    {
        ### Verify that roles are in the supported set
        CheckRole $roles @("oozieservice")
        foreach ( $role in $roles.Split(" ") )
        {
            try
            {
                Write-Log "Stopping $role "
                if (Get-Service "$role" -ErrorAction SilentlyContinue)
                {
                    Write-Log "Service $role exists, stopping it"
                    Stop-Service $role
                }
                else
                {
                    Write-Log "Service $role does not exist, moving to next"
                }
            }
            catch [Exception]
            {
                Write-Host "Can't stop service $role"
            }

        }
    }
    else
    {
        throw "StartService: Unsupported compoment argument."
    }
}

###############################################################################
###
### Installs oozie binaries.
###
### Arguments:
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###
###############################################################################
function InstallBinaries(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $nodeInstallRoot,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=2, Mandatory=$true )]
    $serviceCredential
    )
{
    $username = $serviceCredential.UserName

    $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

    ### $oozieInstallDir: the directory that contains the appliation, after unzipping
    $oozieInstallToDir = Join-Path "$nodeInstallRoot" "$FinalName"
    $oozieBin = Join-Path "$oozieInstallToDir" "$OozieDistroName\bin"


    Write-Log "Checking the JAVA Installation."
    if( -not (Test-Path $ENV:JAVA_HOME\bin\java.exe))
    {
      Write-Log "JAVA_HOME not set properly; $ENV:JAVA_HOME\bin\java.exe does not exist" "Failure"
      throw "Install: JAVA_HOME not set properly; $ENV:JAVA_HOME\bin\java.exe does not exist."
    }

    Write-Log "Checking the Hadoop Installation."
    if( -not (Test-Path $ENV:HADOOP_HOME\bin\winutils.exe))
    {
      Write-Log "HADOOP_HOME not set properly; $ENV:HADOOP_HOME\bin\winutils.exe does not exist" "Failure"
      throw "Install: HADOOP_HOME not set properly; $ENV:HADOOP_HOME\bin\winutils.exe does not exist."
    }

    ###
    ### Set OOZIE_ROOT environment variable
    ###
    Write-Log "Setting the OOZIE_ROOT environment variable at machine scope to `"$oozieInstallToDir`""
    [Environment]::SetEnvironmentVariable("OOZIE_ROOT", $oozieInstallToDir, [EnvironmentVariableTarget]::Machine)
    $ENV:OOZIE_ROOT = $oozieInstallToDir

    ### oozie Binaries must be installed before creating the services
    ###
    ### Begin install
    ###
    Write-Log "Installing Apache oozie $FinalName to $oozieInstallToDir"

    ### Create Node Install Root directory
    if( -not (Test-Path "$oozieInstallToDir"))
    {
        Write-Log "Creating Node Install Root directory: `"$oozieInstallToDir`""
        New-Item -Path "$oozieInstallToDir" -type directory | Out-Null
    }

    ###
    ###  Copy Oozie distribution from winpkg to install target
    ###
    Write-Log "Copy install oozie into $oozieInstallToDir"
    Copy-Item "$HDP_RESOURCES_DIR\$FinalName\*" $oozieInstallToDir -recurse -force

    ###
    ### Grant Hadoop user access to $oozieInstallToDir
    ###
    GiveFullPermissions $oozieInstallToDir $username


    Write-Log "Installation of Apache oozie binaries completed"
}


### Helper routing that converts a $null object to nothing. Otherwise, iterating over
### a $null object with foreach results in a loop with one $null element.
function empty-null($obj)
{
   if ($obj -ne $null) { $obj }
}

### Gives full permissions on the folder to the given user
function GiveFullPermissions(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $folder,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $username,
    [bool]
    [Parameter( Position=2, Mandatory=$false )]
    $recursive = $false)
{
    Write-Log "Giving user/group `"$username`" full permissions to `"$folder`""
    $cmd = "icacls `"$folder`" /grant ${username}:(OI)(CI)F"
    if ($recursive) {
        $cmd += " /T"
    }
    Invoke-CmdChk $cmd
}

### Checks if the given space separated roles are in the given array of
### supported roles.
function CheckRole(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $roles,
    [array]
    [parameter( Position=1, Mandatory=$true )]
    $supportedRoles
    )
{
    foreach ( $role in $roles.Split(" ") )
    {
        if ( -not ( $supportedRoles -contains $role ) )
        {
            throw "CheckRole: Passed in role `"$role`" is outside of the supported set `"$supportedRoles`""
        }
    }
}

### Creates and configures the service.
function CreateAndConfigureHadoopService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $service,
    [String]
    [Parameter( Position=1, Mandatory=$true )]
    $hdpResourcesDir,
    [String]
    [Parameter( Position=2, Mandatory=$true )]
    $serviceBinDir,
    [System.Management.Automation.PSCredential]
    [Parameter( Position=3, Mandatory=$true )]
    $serviceCredential
)
{
    if ( -not ( Get-Service "$service" -ErrorAction SilentlyContinue ) )
    {
        #Creating the event log needs to be done from an elevated process, so we do it here
        if( -not ([Diagnostics.EventLog]::SourceExists( "$service" )))
        {
            [Diagnostics.EventLog]::CreateEventSource( "$service", "" )
        }

        Write-Log "Adding service $service"
        if ($serviceCredential.Password.get_Length() -ne 0)
        {
            $s = New-Service -Name "$service" -BinaryPathName "$serviceBinDir\$service.exe" -Credential $serviceCredential -DisplayName "Apache Hadoop $service"
            if ( $s -eq $null )
            {
                throw "CreateAndConfigureHadoopService: Service `"$service`" creation failed"
            }
        }
        else
        {
            # Separately handle case when password is not provided
            # this path is used for creating services that run under (AD) Managed Service Account
            # for them password is not provided and in that case service cannot be created using New-Service commandlet
            $serviceUserName = $serviceCredential.UserName
            $cred = $serviceCredential.UserName.Split("\")

            # Throw exception if domain is not specified
            if (($cred.Length -lt 2) -or ($cred[0] -eq "."))
            {
                throw "Environment is not AD or domain is not specified"
            }

            $cmd="$ENV:WINDIR\system32\sc.exe create `"$service`" binPath= `"$serviceBinDir\$service.exe`" obj= $serviceUserName DisplayName= `"Apache Hadoop $service`" "
            try
            {
                Invoke-CmdChk $cmd
            }
            catch
            {
                throw "CreateAndConfigureHadoopService: Service `"$service`" creation failed"
            }
        }

        $cmd="$ENV:WINDIR\system32\sc.exe failure $service reset= 30 actions= restart/5000"
        Invoke-CmdChk $cmd

        $cmd="$ENV:WINDIR\system32\sc.exe config $service start= demand"
        Invoke-CmdChk $cmd

        Set-ServiceAcl $service
    }
    else
    {
        Write-Log "Service `"$service`" already exists, Removing `"$service`""
        StopAndDeleteHadoopService $service
        CreateAndConfigureHadoopService $service $hdpResourcesDir $serviceBinDir $serviceCredential
    }
}

### Stops and deletes the Hadoop service.
function StopAndDeleteHadoopService(
    [String]
    [Parameter( Position=0, Mandatory=$true )]
    $service
)
{
    Write-Log "Stopping $service"
    $s = Get-Service $service -ErrorAction SilentlyContinue

    if( $s -ne $null )
    {
        Stop-Service $service
        $cmd = "sc.exe delete $service"
        Invoke-Cmd $cmd
    }
}

### Returns the value of the given propertyName from the given xml file.
###
### Arguments:
###     xmlFileName: Xml file full path
###     propertyName: Name of the property to retrieve
function FindXmlPropertyValue(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $xmlFileName,
    [string]
    [parameter( Position=1, Mandatory=$true )]
    $propertyName)
{
    $value = $null

    if ( Test-Path $xmlFileName )
    {
        $xml = [xml] (Get-Content $xmlFileName)
        $xml.SelectNodes('/configuration/property') | ? { $_.name -eq $propertyName } | % { $value = $_.value }
        $xml.ReleasePath
    }

    $value
}

### Helper routine that updates the given fileName XML file with the given
### key/value configuration values. The XML file is expected to be in the
### Hadoop format. For example:
### <configuration>
###   <property>
###     <name.../><value.../>
###   </property>
### </configuration>
function UpdateXmlConfig(
    [string]
    [parameter( Position=0, Mandatory=$true )]
    $fileName,
    [hashtable]
    [parameter( Position=1 )]
    $config = @{} )
{
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($fileName)

    foreach( $key in empty-null $config.Keys )
    {
        $value = $config[$key]
        $found = $False
        $xml.SelectNodes('/configuration/property') | ? { $_.name -eq $key } | % { $_.value = $value; $found = $True }
        if ( -not $found )
        {
            $newItem = $xml.CreateElement("property")
            $newItem.AppendChild($xml.CreateElement("name")) | Out-Null
            $newItem.AppendChild($xml.CreateElement("value")) | Out-Null
            $newItem.name = $key
            $newItem.value = $value
            $xml["configuration"].AppendChild($newItem) | Out-Null
        }
    }

    $xml.Save($fileName)
    $xml.ReleasePath
}

# Update the oozieservice.xml to point to the corrext oozie exe path to start
# This is needed because the install location is not fixed
function UpdateServiceXml($serviceXmlPath, $oozieServerExePath)
{
    Write-Log "Updating file $serviceXmlPath to point to executable $oozieServerExePath"

    if (! (Test-Path $serviceXmlPath))
    {
        Write-Log "XML Service file $serviceXmlPath does not exist" "Failure"
        return $false
    }

    # Load the XML file to edit
    $xmlObj = New-Object XML
    $xmlObj.Load($serviceXmlPath)

    # Get the "executable" node
    $executableNode = $xmlObj.SelectSingleNode("service/executable")

    # Validate the "executable" node exists
    if ($executableNode -eq $NULL)
    {
        Write-Log "Invalid service XML file [$serviceXmlPath]. No 'executable' entry found" "Failure"
        return $false
    }
    else
    {
        # Update the executable entry to point to the correct exe path
        $executableNode.InnerText = $oozieServerExePath
    }

    # Get the "stopexecutable" node
    $stopExecutableNode = $xmlObj.SelectSingleNode("service/stopexecutable")

    # Validate the "stopexecutable" node exists
    if ($stopExecutableNode -eq $NULL)
    {
        Write-Log "Invalid service XML file [$serviceXmlPath]. No 'stopexecutable' entry found" "Failure"
        return $false
    }
    else
    {
        # Update the stop-executable entry to point to the correct exe path
        $stopExecutableNode.InnerText = $oozieServerExePath
    }

    $xmlObj.Save($serviceXmlPath)
    return $true
}

# Create the database schema for Oozie metastore DB using the connection
# settings in oozie-site.xml
# This API assumes Oozie configuration is already set, so it needs to be called
# after the call to Configure with database connection settings
#
# The API first tries to create the schema. If the metastore schema is already
# created, it will try to upgrade the schema. Finally, we verify the schema is
# valid. If schema could not be verified to be valid an exception is thrown
function CreateMetastore()
{
    # Get the Oozie root from environment variable
    $oozieRoot = [Environment]::GetEnvironmentVariable("OOZIE_ROOT","Machine")
    $ooziedbScript = Join-Path "$oozieRoot" "$OozieDistroName\bin\ooziedb.cmd"

    if ( -not ( Test-Path $ooziedbScript) )
    {
        throw "CreateMetastore: ooziedb not found"
    }

    # Copy sqljdbc.jar file to libtools folder. This is a prerequisite for ooziedb script
    $libtoolsDir = Join-Path "$oozieRoot" "$OozieDistroName\libtools"
    $sqlJdbcFile = Join-Path "$oozieRoot" "extra_libs\sqljdbc4.jar"
    if ( -not ( Test-Path $sqlJdbcFile) )
    {
        throw "CreateMetastore: $sqlJdbcFile not found"
    }
    Copy-Item $sqlJdbcFile $libtoolsDir -force

    # Create the database schema
    Write-Log "Creating Oozie metastore DB schema. This should fail if schema is already available"
    $cmd = "$ooziedbScript create -run"
    $out = Invoke-Cmd $cmd
    if (-not ($LastExitCode  -eq 0))
    {
        Write-Log "Oozie metastore DB schema not created! Check if it is already created, and should be upgraded"
        Write-Log "Create output`: $out"

        # DB schema could be previously created, try to Upgrade it
        Write-Log "Upgrading Oozie metastore DB schema. This should fail if schema is already up-to-date"
        $cmd="$ooziedbScript upgrade -run"
        $out = Invoke-Cmd $cmd
        if (-not ($LastExitCode  -eq 0))
        {
            Write-Log "Oozie metastore DB schema can not be upgraded!"
        }
        else
        {
            # Check if the upgrade is successful, if not fail with an exception
            Write-Log "Validating Oozie Upgrade."
            $cmd="$ooziedbScript postupgrade -run"
            $out = Invoke-Cmd $cmd
            if (-not ($LastExitCode  -eq 0))
            {
                $errMsg = "Oozie metastore DB postupgrade validation failed"
                Write-Log "$errMsg"
                Write-Log "Output`: $out"
                throw "$errMsg"
            }
            else
            {
                Write-Log "Oozie postupgrade validated!"
            }

            Write-Log "Oozie metastore DB schema successfully upgraded!"
        }
        Write-Log "Upgrade output`: $out"
    }
    else
    {
        Write-Log "Oozie metastore DB schema created successfully!"
    }

    # Check if the database schema is valid, if not fail with an exception
    Write-Log "Checking Oozie metastore DB schema."
    $cmd="$ooziedbScript version"
    $out = Invoke-Cmd $cmd
    if (-not ($LastExitCode  -eq 0))
    {
        $errMsg = "Oozie metastore DB schema cannot not be validated, or not up-to-date"
        Write-Log "$errMsg"
        Write-Log "Output`: $out"
        throw "$errMsg"
    }
    else
    {
        Write-Log "Oozie metastore DB schema is ready!"
    }
}

###
### Public API
###
Export-ModuleMember -Function Install
Export-ModuleMember -Function Uninstall
Export-ModuleMember -Function Configure
Export-ModuleMember -Function StartService
Export-ModuleMember -Function StopService
Export-ModuleMember -Function CreateMetastore
Export-ModuleMember -Function GiveFullPermissions
