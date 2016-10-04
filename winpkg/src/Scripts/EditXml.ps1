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

$configXPath = "/configuration"
$propertyXPath = "$configXPath/property"

# Edit the value of the property whose name is given
# Return true if the a property has been updated, and false otherwise
function editProperty($xmlPropRoot, $propName, $propValue)
{
    $found = $false
    
    # Iterate over all "property" elements
    $propNodes = $xmlPropRoot.SelectNodes($propertyXPath)
    $propNodes | ForEach-Object {

        # Check the name of the current property
        $_.SelectSingleNode('name') | ? {
            $_.InnerText -eq $propName
        } | % {
            # A property with the specified name has been found
            $found = $true
        }
    
        # If the property has been found, edit its value
        if ($found)
        {
            # Update the property value
            $_.SelectSingleNode('value').InnerText = $propValue
            return $true
        }
    }
    
    # insicate no items were edited
    return $false
}

# Set a property with the given name value pair.
# If a property with the same name already exists, its value is modified
# otherwise, a new property is created with the given name/value
function setProperty($xmlPropRoot, $propName, $propValue)
{
    # Edit the property if it already exists
    if (! (editProperty $xmlPropRoot $propName $propValue))
    {
        # Create a property with the name/value pair

        # Create the 'name' element
        $nameElem = $xmlPropRoot.CreateElement('name')
        $nameElem.InnerText = $propName

        # Create the 'value' element
        $valueElem = $xmlPropRoot.CreateElement('value')
        $valueElem.InnerText = $propValue
    
        # Create the property element
        $propElem = $xmlPropRoot.CreateElement('property')
        [void] $propElem.AppendChild($nameElem)
        [void] $propElem.AppendChild($valueElem)
    
        # Add the property element to the configuration block
        $configElem = $xmlPropRoot.SelectSingleNode($configXPath)
        [void] $configElem.AppendChild($propElem)
    
        WriteSuccess "Property '$propName' added"
    }
    else
    {
        WriteSuccess "Property '$propName' changed to '$propValue'"
    }
}
