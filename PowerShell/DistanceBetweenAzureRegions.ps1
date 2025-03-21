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

# Get the current Azure subscription ID
$subscriptionId = (Get-AzContext).Subscription.ID

# Get the list of Azure locations for the current subscription
$response = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$subscriptionId/locations?api-version=2022-12-01"
$locations = ($response.Content | ConvertFrom-Json).value

# Initialize an array to hold the location data
$rows = @()

# Filter the locations to include only physical regions
foreach($_ in $locations)
{
   if($_.metadata.regionType -eq "Physical")
   {
        $rows += [pscustomobject]@{
            name= $_.Name; 
            regionType=$_.metadata.regionType; 
            regionCategory= $_.metadata.regionCategory;  
            dataCenterLocation = $_.metadata.physicalLocation; 
            numZones = $_.availabilityZoneMappings.count; 
            physicalZones=($_.availabilityZoneMappings.physicalZone -join ","); 
            longitude=$_.metadata.longitude; 
            latitude=$_.metadata.latitude; 
            pairedRegion = $_.metadata.pairedRegion.name; 
            pairedDCLocation=""; 
            pairedLongitude=0; 
            pairedLatitude=0; 
            distanceApart=0
            }
   }
}

# Calculate the distance between paired regions
foreach($row in $rows)
{
    # Look up and set paired longitude & latitude
    $paired = $rows.where({$_.name -eq $row.pairedRegion})
    if($paired -ne $null)
    {
        $row.pairedDCLocation = $paired.dataCenterLocation
        $row.pairedLongitude = $paired.longitude
        $row.pairedLatitude = $paired.latitude

        # Compute and set the distance apart
        $row.distanceApart = Get-Distance -lat1 $row.latitude -lon1 $row.longitude -lat2 $row.pairedLatitude -lon2 $row.pairedLongitude
    }
}

# Sort the results and format the output
$rows | Sort-Object -Property regionCategory, distanceApart -Descending |
    Format-Table -Property name,regionCategory,dataCenterLocation,numZones,longitude,latitude,pairedRegion,pairedDCLocation,pairedLongitude,pairedLatitude,distanceApart | Out-String -Width 1024
