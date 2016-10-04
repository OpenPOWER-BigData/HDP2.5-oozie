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

# Include needed script
. './Common.ps1'

# Add the local user to group if it does not already added
# If the group does not exist, a new goup will be created before the user is added
# If the user does not already exist, it does not get created
function addUserToGroup([string] $groupName, [string] $userName)
{
    # Verify the username exists
    if (![ADSI]::Exists("WinNT://$env:computername/$userName"))
    {
        WriteError "User $userName does not exist."
        return $false
    }
    
    # Get the group to the user to
    $computer = [ADSI]"WinNT://$Env:COMPUTERNAME,Computer"
    $group = $computer.psbase.children | where { $_.psbase.schemaClassName -eq 'group' -and $_.name -eq $groupName}
    if ($group -eq $Null)
    {
        # Create the local group
        $group = $computer.Create("Group", $groupName)
        $group.SetInfo()
        $group.description = "Isotope Users Group"
        $group.SetInfo()
    
        WriteSuccess "Group $groupName successfully created"
    }
    
    $user = $group.psbase.Invoke("Members") | where { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) -eq $userName}
    if ($user -eq $Null)
    {
        $group.add("WinNT://$env:computername/$userName")
    }
    else
    {
        Write-Log "User $userName already exists in group."
    }

    return $true
}

# Remove the specified local group with all its users from the machine
function removeGroup([string] $groupName)
{
    $computer = [ADSI]"WinNT://$Env:COMPUTERNAME,Computer"
    $group = $computer.psbase.children | where { $_.psbase.schemaClassName -eq 'group' -and $_.name -eq $groupName}
    
    # Verify the group exists
    if ($group -eq $NULL)
    {
        WriteError "Group $groupName does not exist."
        return $false
    }

    # Remove the group
    $computer.psbase.Children.Remove("WinNT://$Env:COMPUTERNAME/$groupName")
    
    return $true
}
