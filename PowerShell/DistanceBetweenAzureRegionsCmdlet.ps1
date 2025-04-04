# Function to convert degrees to radians
function ToRadians {
    param (
        [double]$degrees
    )
    return $degrees * [math]::PI / 180
}

# Function to calculate the distance between two geographical points using the Haversine formula
function Get-Distance {
    param (
        [double]$lat1,  # Latitude of the first point
        [double]$lon1,  # Longitude of the first point
        [double]$lat2,  # Latitude of the second point
        [double]$lon2   # Longitude of the second point
    )

    $earthRadius = 6371 # Radius of the Earth in kilometers

    # Calculate the differences in latitude and longitude
    $dLat = ToRadians($lat2 - $lat1)
    $dLon = ToRadians($lon2 - $lon1)

    # Apply the Haversine formula
    $a = [math]::Sin($dLat / 2) * [math]::Sin($dLat / 2) +
         [math]::Cos((ToRadians($lat1))) * [math]::Cos((ToRadians($lat2))) *
         [math]::Sin($dLon / 2) * [math]::Sin($dLon / 2)

    $c = 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))

    # Calculate the distance
    $distance = $earthRadius * $c

    return [math]::Round($distance, 2) # Round the distance to 2 decimal places
}

# Retrieve the initial data
$locations = Get-AzLocation | Where-Object {$_.RegionType -eq "Physical"} | 
    Select-Object Location, RegionType, RegionCategory, PhysicalLocation, Longitude, Latitude, @{Name="PairedRegionName";Expression={$_.PairedRegion.Name}}

# Initialize a hashtable for quick lookup of location data
$locationLookup = @{}
foreach ($location in $locations) {
    $locationLookup[$location.Location] = $location
}

# Initialize an array to hold the location data with paired region details
$rows = @()

# Process each location and calculate the distance to its paired region
foreach ($location in $locations) {
    $pairedRegionName = $location.PairedRegionName
    # Some regions don't have a paired secondary
    if($pairedRegionName -ne $null)
    {
        $pairedLocation = $locationLookup[$pairedRegionName]
        # Some regions have a secondary region listed but there's no data on it through the API, e.g. swedensouth
        if($pairedLocation) 
        {
            $distanceApart = Get-Distance -lat1 $location.Latitude -lon1 $location.Longitude -lat2 $pairedLocation.Latitude -lon2 $pairedLocation.Longitude
        }
        else
        {
            $distanceApart = 0
        }

        $rows += [pscustomobject]@{
            name = $location.Location
            regionType = $location.RegionType
            regionCategory = $location.RegionCategory
            dataCenterLocation = $location.PhysicalLocation
            longitude = $location.Longitude
            latitude = $location.Latitude
            pairedRegion = $pairedRegionName
            pairedDCLocation = $pairedLocation.PhysicalLocation
            pairedLongitude = $pairedLocation.Longitude
            pairedLatitude = $pairedLocation.Latitude
            distanceApart = $distanceApart
        }

    } else {
        # Handle the case where there isn't a paired region
        $rows += [pscustomobject]@{
            name = $location.Location
            regionType = $location.RegionType
            regionCategory = $location.RegionCategory
            dataCenterLocation = $location.PhysicalLocation
            longitude = $location.Longitude
            latitude = $location.Latitude
            pairedRegion = ""
            pairedDCLocation = ""
            pairedLongitude = 0
            pairedLatitude = 0
            distanceApart = 0
        }
    }
}



# Sort the results and format the output
$rows | Sort-Object -Property regionCategory, distanceApart -Descending |
    Format-Table -Property name, regionCategory, dataCenterLocation, longitude, latitude, pairedRegion, pairedDCLocation, pairedLongitude, pairedLatitude, distanceApart | Out-String -Width 1024
