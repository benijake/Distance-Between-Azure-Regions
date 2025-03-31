# Which Azure regions offer multiple availability zones? What's the distance between each Azure region and its paired secondary?
Implementing [zonal and regional redundancy](https://learn.microsoft.com/en-us/azure/well-architected/reliability/regions-availability-zones) can significantly minimize operational impact on your business. By ensuring high availability and fault isolation, zonal redundancy reduces the risk of localized disruptions and downtime for mission-critical applications. Regional redundancy, on the other hand, provides a robust [disaster recovery](https://learn.microsoft.com/en-us/azure/well-architected/reliability/disaster-recovery) solution, ensuring that your applications remain available even in the event of a regional failure.

- How can you identify which Azure regions offer multiple availability zones? 
- Which Azure regions have a paired secondary region and what's the distance between them?

## List-Locations API
Using the [List-Locations API](https://learn.microsoft.com/en-us/rest/api/resources/subscriptions/list-locations?view=rest-resources-2022-12-01&tabs=HTTP) we can get a list of all Azure regions, their availability zones, latitude and longitude and the paired secondary region

## Havesine Formula
We can then plug latitude and longitude of the primary and secondary regions into the [Haversine Formula](https://en.wikipedia.org/wiki/Haversine_formula) to compute the distance in kilometers.

The Haversine formula is used to calculate the great-circle distance between two points on the Earth's surface, given their latitude and longitude. This formula is particularly useful for navigation and geospatial applications.

Components of the Formula:

### 1. Latitude and Longitude in Radians

First, we need to convert the latitude and longitude of both points from degrees to radians by multiplying by $$\frac{\pi}{180}$$. This is because trigonometric functions in the formula (like sine and cosine) require input in radians.

### 2. Differences in Latitude and Longitude

Next, we calculate the differences between the latitudes and longitudes of the two points:

$$
\Delta \text{lat} = \text{lat}_2 - \text{lat}_1
$$

$$
\Delta \text{long} = \text{long}_2 - \text{long}_1
$$


The Haversine formula itself consists of two main parts:

#### a. Calculation of 'a'. This part calculates the square of half the chord length between the points.

$$
a = \sin^2\left(\frac{\Delta \text{lat}}{2}\right) + \cos(\text{lat}_1) \cdot \cos(\text{lat}_2) \cdot \sin^2\left(\frac{\Delta \text{long}}{2}\right)
$$



#### b. Calculation of 'c'. This part calculates the angular distance in radians.

$$
c = 2 \cdot \text{atan2}\left(\sqrt{a}, \sqrt{1-a}\right)
$$



### 3. Distance Calculation

Finally, we calculate the distance \( d \) between the two points:

$$
d = R \cdot c
$$

Where:
- R is the Earth's radius (mean radius = 6,371 km).
- d is the distance between the two points in kilometers.

## Solutions
- [PowerShell](#powershell)
- [Databricks](#databricks-pyspark-notebook)

## PowerShell
Since the Haversine formula that computes distances based on radians not degrees, we will first create a function that converts degrees to radians
``` PowerShell
function ToRadians {
    param (
        [double]$degrees
    )
    return $degrees * [math]::PI / 180
}
```
Next, let's create a function that accepts two coordinates and applies the Haversine formula to compute the distance between them.  This function will call the one above to convert latitude and longitude from degrees to radians
``` PowerShell
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
```

Then we get the Id for our Azure subscription and call the List-Locations REST API
``` PowerShell
# Get the current Azure subscription ID
$subscriptionId = (Get-AzContext).Subscription.ID

# Get the list of Azure locations for the current subscription
$response = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$subscriptionId/locations?api-version=2022-12-01"
$locations = ($response.Content | ConvertFrom-Json).value
```

The REST API will return the locations as a bunch of json that isn't easy to read so we will use an array of custom PowerShell objects instead.  We can easily format the PowerShell object array as a table in the output to the console at the end
``` PowerShell
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
```

Now that we've got each location loaded into our array, we can loop through and add latitude and longitude for the paired secondary and calculate the distance between them by calling our Get-Distance function
``` PowerShell
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
```

Finally, we output the object array to the console as nicely formated table
``` PowerShell
# Sort the results and format the output
$rows | Sort-Object -Property regionCategory, distanceApart -Descending |
    Format-Table -Property name,regionCategory,dataCenterLocation,numZones,longitude,latitude,pairedRegion,pairedDCLocation,pairedLongitude,pairedLatitude,distanceApart | Out-String -Width 1024
```
![PowerShellScriptOutput](./PowerShell/AzureRegions.png)

### Code
You can download the full PowerShell script [here](./PowerShell/DistanceBetweenAzureRegions.ps1)

## Databricks PySpark Notebook
### Required libraries:
- azure-identity
- azure-mgmt-resource

You can either install these on your cluster (recommended unless it's a one-off exercise):
![installLibraries](./Databricks/installLibraries.png)

Or run ```%pip install azure-identity azure-mgmt-resource``` in a cell in your notebook:
![pipInstall](./Databricks/pipInstall.png)

Note: The solution below assumes that your workpace is enabled for Unity Catalog

### Solution
Databricks used to support something called [passthrough authentication](https://learn.microsoft.com/en-us/azure/databricks/archive/credential-passthrough/adls-passthrough#enable-azure-data-lake-storage-credential-passthrough-for-a-high-concurrency-cluster) where your user credentials would get passed through to the data lake and you'd have access to the data that you're permissioned for there.  (Unity Catalog uses [storage credentials](https://learn.microsoft.com/en-us/azure/databricks/connect/unity-catalog/cloud-storage/storage-credentials) instead, which work a bit differently.)  So you might expect your user credentials would get "passed through" to the REST API the same way that they would for a data lake under passthrough authentication. However, if you run the code below, you'll get an authorization error:

``` python
from azure.identity import *
import requests
subscriptionId = "XXXX-XXXX-XXXX-XXXX-XXXX"
url = f"https://management.azure.com/subscriptions/{subscriptionId}/locations?api-version=2022-12-01"
credential = DefaultAzureCredential()
# Set the authorization header
headers = {
    "Authorization": f"Bearer {credential.get_token('https://management.azure.com/.default').token}",
    "Content-Type": "application/json"
}
response = requests.get(url, headers = headers)
data = response.json()
```
![errorMsg](./Databricks/errorMsg.png)

Unfortunately, passthrough authentication only works for storage accounts, not REST APIs and databases.  If you go into Entra Id and look up the client id, you will see that the user assigned managed identity "dbmanagedidentity" that is associated with your workspace is being used instead.  
![EntraClientId](./Databricks/dbmanagedidentity.png)

As mentioned in the error message, dbmanagedidentity is missing the Reader RBAC role for the subscription:
1. Open the access control blade for your subscription
![subIAM](./Databricks/subIAM.png)

2. Select the Reader role 
![subReader](./Databricks/ReaderRole.png)

3. Select managed identities and find dbmanagedidentity for your workspace under user assigned managed identities
![roleMember](./Databricks/RoleMember.png)
![selectManagedId](./Databricks/selectManagedIdentity.png)

4. Review + Assign
![reviewAndAssign](./Databricks/ReviewAndAssign.png)

Now when we run the code again it executes successfully!
![works](./Databricks/worksNow.png)

Alternatively, you can replace the call to ```DefaultAzureCredential()``` with ```DeviceCodeCredential()``` to use your authenticated local user instead:
![works](./Databricks/DeviceCodeCredential.png)

Let's modify the code to automatically retrieve the subscription id for our workspace

``` python
from azure.mgmt.resource import SubscriptionClient
from azure.identity import *
credential = DefaultAzureCredential()
subscription_client = SubscriptionClient(credential)
subs = list(subscription_client.subscriptions.list())

if subs:
    subscriptionId = subs[0].subscription_id
else:
    print("No subscriptions found.")

import requests
url = f"https://management.azure.com/subscriptions/{subscriptionId}/locations?api-version=2022-12-01"

# Set the authorization header
headers = {
    "Authorization": f"Bearer {credential.get_token('https://management.azure.com/.default').token}",
    "Content-Type": "application/json"
}

response = requests.get(url, headers = headers)
data = response.json()
```

Next we will load the data into a spark dataframe and convert the json to columns
``` python
df = spark.read.json(spark.sparkContext.parallelize([data]))
df_flattened = df.selectExpr("explode(value) as location").select("location.*").where("metadata.regionType == 'Physical'").selectExpr("name", "metadata.regionCategory as regionCategory", "metadata.physicalLocation as dataCenterLocation", "size(availabilityZoneMappings) as numZones","metadata.longitude as longitude", "metadata.latitude as latitude", "metadata.pairedRegion.name[0] as pairedRegion")

display(df_flattened)
```
![jsonToColumns](./Databricks/df_flattened.png)

Now that we have the data in table format we can join it to itself on the paired region column to get longitude and latitude for the paired region
``` python
from pyspark.sql.functions import *
# Create a lookup DataFrame for paired regions
paired_df = df_flattened.selectExpr("name as pairedRegionName", "longitude as pairedLongitude", "latitude as pairedLatitude"
)

# Perform a self join to add the pairedLongitude and pairedLatitude columns
df_with_paired_location = df_flattened.join(
    paired_df,
    df_flattened.pairedRegion == paired_df.pairedRegionName,
    "left"
).drop("pairedRegionName")

# Display the DataFrame
display(df_with_paired_location)
```
![pairedLatLong](./Databricks/pairedLatLong.png)

Finally, we add the distance calculation
``` python
df_with_distance = df_with_paired_location.withColumn("distance", round(6371 * acos(cos(radians(df_with_paired_location.latitude)) * cos(radians(df_with_paired_location.pairedLatitude)) * cos(radians(df_with_paired_location.longitude) - radians(df_with_paired_location.pairedLongitude)) + sin(radians(df_with_paired_location.latitude)) * sin(radians(df_with_paired_location.pairedLatitude))), 2))

display(df_with_distance.orderBy("regionCategory", "distance", ascending=False))
```
![withDistance](./Databricks/withDistance.png)

### Code
You can download the complete notebooks here:
- Authentication with [workspace user-assigned managed identity](./Databricks/CallRESTApi.ipynb)
- Authentication with local user using a [device code](./Databricks/CallRESTAPIDeviceCode.ipynb)
