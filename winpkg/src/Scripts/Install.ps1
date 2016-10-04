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
### Install script that can be used to install Oozie as a Single-Node cluster.
### To invoke the scipt, run the following command from PowerShell:
###   install.ps1 -username <username> -password <password> or
###   install.ps1 -credentialFilePath <credentialFilePath>
###
### where:
###   <username> and <password> represent account credentials used to run
###   Oozie services as Windows services.
###   <credentialFilePath> encripted credentials file path
###
### By default, Hadoop is installed to "C:\Hadoop". To change this set
### HADOOP_NODE_INSTALL_ROOT environment variable to a location were
### you'd like Hadoop installed.
###
### Script pre-requisites:
###   JAVA_HOME must be set to point to a valid Java location.
###   HADOOP_HOME must be set to point to a valid Hadoop install location.
###
### To uninstall previously installed Single-Node cluster run:
###   uninstall.ps1
###
### NOTE: Notice @version@ strings throughout the file. First compile
### winpkg with "ant winpkg", that will replace the version string.

###

param(
    [String]
    [Parameter( ParameterSetName='UsernamePassword', Position=0, Mandatory=$true )]
    [Parameter( ParameterSetName='UsernamePasswordBase64', Position=0, Mandatory=$true )]
    $username,
    [String]
    [Parameter( ParameterSetName='UsernamePassword', Position=1, Mandatory=$true )]
    $password,
    [String]
    [Parameter( ParameterSetName='UsernamePasswordBase64', Position=1, Mandatory=$true )]
    $passwordBase64,
    [Parameter( ParameterSetName='CredentialFilePath', Mandatory=$true )]
    $credentialFilePath,
    [String]
    $OozieRoles
    )

function Main( $scriptDir )
{
    $FinalName = "oozie-@oozie.version@"
    if ( -not (Test-Path ENV:WINPKG_LOG))
    {
        $ENV:WINPKG_LOG = "$FinalName.winpkg.log"
    }

    $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"
    $nodeInstallRoot = "$ENV:HADOOP_NODE_INSTALL_ROOT"


    ###
    ### Create the Credential object from the given username and password or the provided credentials file
    ###
    $serviceCredential = Get-HadoopUserCredentials -credentialsHash @{"username" = $username; "password" = $password; `
        "passwordBase64" = $passwordBase64; "credentialFilePath" = $credentialFilePath}
    $username = $serviceCredential.UserName
    Write-Log "Username: $username"
    Write-Log "CredentialFilePath: $credentialFilePath"

    ###
    ### Install and Configure Oozie
    ###
    if ( $ENV:IS_OOZIE_SERVER -eq "yes" ) {
      $OozieRoles = "oozieservice"
    }

    # Set up data directory and set permissions
    if ( ($ENV:IS_OOZIE_SERVER -eq "yes") -and (Test-Path ENV:OOZIE_DATA) )
    {
        if ( ($ENV:OOZIE_DATA) -and (Test-Path "${ENV:OOZIE_DATA}\*") )
        {
            if ( (-not (Test-Path ENV:DESTROY_DATA)) -or ($ENV:DESTROY_DATA -eq "yes") )
            {
                Write-Log "Removing Oozie Data Directory: $ENV:OOZIE_DATA"
                $cmd = "rd /s /q $ENV:OOZIE_DATA"
                Invoke-CmdChk $cmd
            }
            else
            {
                if ( (Test-Path ENV:DESTROY_DATA) -and ($ENV:DESTROY_DATA -eq "undefined") )
                {
                    throw "Nonempty data directory: $ENV:OOZIE_DATA"
                }
            }
        }
        if (-not (Test-Path $ENV:OOZIE_DATA))
        {
            Write-Log "Creating Oozie Data Directory: $ENV:OOZIE_DATA"
            $cmd = "mkdir $ENV:OOZIE_DATA"
            Invoke-CmdChk $cmd
        }
        $username = $serviceCredential.UserName
        GiveFullPermissions $ENV:OOZIE_DATA $username
    }
    Install "oozie" $nodeInstallRoot $serviceCredential $OozieRoles

    Write-Log "Installation of Oozie completed successfully"

    $dburl = ""
    $dbdriver = ""
    $dbuser = "sa"
    $dbpasswd = "pwd"
    if ( $ENV:DB_FLAVOR -eq "mssql" )
    {
        $dburl = "jdbc:sqlserver://${ENV:DB_HOSTNAME}:${ENV:DB_PORT};database=${ENV:OOZIE_DB_NAME}"
        $dbdriver = "com.microsoft.sqlserver.jdbc.SQLServerDriver"
        $dbuser = "$ENV:OOZIE_DB_USERNAME"
        $dbpasswd = "$ENV:OOZIE_DB_PASSWORD"
    }
    else
    {
        $dburl = "jdbc:derby:`${oozie.data.dir}/`${oozie.db.schema.name}-db;create=true"
        $dbdriver = "org.apache.derby.jdbc.EmbeddedDriver"
    }
	$config = @{
        "oozie.service.JPAService.jdbc.url" = "$dburl";
        "oozie.service.JPAService.jdbc.driver" = "$dbdriver";
        "oozie.service.JPAService.jdbc.username" = "$dbuser";
        "oozie.service.JPAService.jdbc.password" = "$dbpasswd";
        "oozie.services.ext" = "org.apache.oozie.service.PartitionDependencyManagerService,org.apache.oozie.service.HCatAccessorService";
        "oozie.credentials.credentialclasses" = "hcat=org.apache.oozie.action.hadoop.HCatCredentials";
        "oozie.service.URIHandlerService.uri.handlers" = "org.apache.oozie.dependency.FSURIHandler,org.apache.oozie.dependency.HCatURIHandler";
        "oozie.service.coord.push.check.requeue.interval" = "30000";
        "oozie.service.HadoopAccessorService.hadoop.configurations" = "*=$ENV:HADOOP_CONF_DIR";
        "oozie.service.HadoopAccessorService.supported.filesystems" = "hdfs, webhdfs, swebhdfs, hftp, hsftp, wasb, s3n";
		"oozie.service.AuthorizationService.security.enabled" = "true"}
		Configure "oozie" $NodeInstallRoot $ServiceCredential $config
        if ($ENV:IS_OOZIE_SERVER -eq "yes")
        {
            Write-Log "Creating oozie db schema"
            CreateMetastore
        }
        
    $hdpLayoutLocation =  Split-Path -Parent (Resolve-Path $ENV:HDP_LAYOUT)    
    if ((Test-Path ENV:ENABLE_LZO) -and ($ENV:ENABLE_LZO -ieq "yes"))
    {
        $hadoopLzoJar = @(gci -Filter hadoop-lzo*.jar -Path $hdpLayoutLocation)[0]

        Write-Log "Copying $hadoopLzoJar.FullName to $ENV:OOZIE_HOME\..\extra_libs\"
        Copy-Item $hadoopLzoJar.FullName "$ENV:OOZIE_HOME\..\extra_libs\"

        $params = @{command="prepare-war";d="$ENV:OOZIE_HOME\..\extra_libs"}
        Invoke-Expression -command "$ENV:OOZIE_HOME/bin/oozie-setup.ps1 @params"
    }
    if ((Test-Path ENV:INSTALL_OOZIE_WEBCONSOLE ) -and ($ENV:INSTALL_OOZIE_WEBCONSOLE -ieq "yes"))
    {
        $extjszip = @(gci -Filter ext-*.zip -Path $hdpLayoutLocation)[0]

        Write-Log "Copying $extjszip.FullName to $ENV:OOZIE_HOME\..\extra_libs\"
        Copy-Item $extjszip.FullName "$ENV:OOZIE_HOME\..\extra_libs\"

        Write-Log "Creating oozie war"
        try
        {
            $out = Start-Process powershell.exe -Credential $serviceCredential -ArgumentList " -file $ENV:OOZIE_HOME\bin\oozie-setup.ps1 prepare-war" -Wait -NoNewWindow
        }
        catch
        {
            throw "Creating oozie war failed"
        }
        Remove-Item "$ENV:OOZIE_HOME\..\oozie-server\webapps" -ErrorAction SilentlyContinue -Recurse -Force

    }

    Write-Log "Done Configuring Oozie"
}

try
{
    $scriptDir = Resolve-Path (Split-Path $MyInvocation.MyCommand.Path)
    $utilsModule = Import-Module -Name "$scriptDir\..\resources\Winpkg.Utils.psm1" -ArgumentList ("OOZIE") -PassThru
    $apiModule = Import-Module -Name "$scriptDir\InstallApi.psm1" -PassThru
    Main $scriptDir
}

catch
{
	Write-Log $_.Exception.Message "Failure" $_
	exit 1
}
finally
{
    if( $apiModule -ne $null )
    {
        Remove-Module $apiModule
    }

    if( $utilsModule -ne $null )
    {

        Remove-Module $utilsModule
    }
}
