function ToRadians {
    param (
        [double]$degrees
    )
    return $degrees * [math]::PI / 180
}

function Get-Distance {
    param (
        [double]$lat1,
        [double]$lon1,
        [double]$lat2,
        [double]$lon2
    )

    $earthRadius = 6371 # Radius of the Earth in kilometers

    $dLat = ToRadians($lat2 - $lat1)
    $dLon = ToRadians($lon2 - $lon1)

    $a = [math]::Sin($dLat / 2) * [math]::Sin($dLat / 2) +
         [math]::Cos((ToRadians($lat1))) * [math]::Cos((ToRadians($lat2))) *
         [math]::Sin($dLon / 2) * [math]::Sin($dLon / 2)

    $c = 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))

    $distance = $earthRadius * $c

    return [math]::Round($distance, 2)
}


$subscriptionId = (Get-AzContext).Subscription.ID
$response = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$subscriptionId/locations?api-version=2022-12-01"
$locations = ($response.Content | ConvertFrom-Json).value
$rows = @()
foreach($_ in $locations)
{
   if($_.metadata.regionType -eq "Physical")
   {
        $rows += [pscustomobject]@{name= $_.Name; regionType=$_.metadata.regionType; regionCategory= $_.metadata.regionCategory;  dataCenterLocation = $_.metadata.physicalLocation; numZones = $_.availabilityZoneMappings.count; physicalZones=($_.availabilityZoneMappings.physicalZone -join ","); longitude=$_.metadata.longitude; latitude=$_.metadata.latitude; pairedRegion = $_.metadata.pairedRegion.name; pairedDCLocation=""; pairedLongitude=0; pairedLatitude=0; distanceApart=0}
   }
}
foreach($row in $rows)
{
        #look up and set paired longitude & latitude
        $paired = $rows.where({$_.name -eq $row.pairedRegion})
        if($paired -ne $null)
        {
            $row.pairedDCLocation = $paired.dataCenterLocation
            $row.pairedLongitude = $paired.longitude
            $row.pairedLatitude = $paired.latitude

            #compute and set distance apart
            $row.distanceApart = Get-Distance -lat1 $row.latitude -lon1 $row.longitude -lat2 $row.pairedLatitude -lon2 $row.pairedLongitude
        }
}

$rows | Sort-Object -Property regionCategory, distanceApart -Descending | 
    Format-Table -Property name,regionCategory,dataCenterLocation,numZones,longitude,latitude,pairedRegion,pairedDCLocation,pairedLongitude,pairedLatitude,distanceApart | Out-String -Width 1024
