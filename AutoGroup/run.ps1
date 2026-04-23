param($Timer)

Import-Module Microsoft.Entra.Users
Import-Module Microsoft.Entra.Groups

$currentUTCtime = (Get-Date).ToUniversalTime()

if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

Write-Host "PowerShell timer trigger function started! TIME: $currentUTCtime"

$inactivityDays = [int]$env:INACTIVITY_DAYS
$targetGroupId = $env:TARGET_GROUP_ID

if (-not $inactivityDays) {
    $inactivityDays = 90
}

if (-not $targetGroupId) {
    Write-Error "TARGET_GROUP_ID must be configured"
    exit 1
}

Write-Host "Looking for users inactive for $inactivityDays days"

$cutoffDate = (Get-Date).AddDays(-$inactivityDays).ToUniversalTime()

try {
    #Connect-Entra -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "AuditLog.Read.All" -NoWelcome -Identity
    Connect-Entra -Identity -NoWelcome
    Write-Host "Connected to Microsoft Entra"
} catch {
    Write-Error "Failed to connect to Microsoft Entra: $_"
    exit 1
}

$group = Get-EntraGroup -GroupId $targetGroupId

if (-not $group) {
    Write-Error "Target group not found"
    exit 1
}

Write-Host "Target group: $($group.DisplayName) ($targetGroupId)"

$allUsers = Get-EntraUser -All -Filter "accountEnabled eq true and userType eq 'Member'" -Property "id,displayName,userPrincipalName,signInActivity"

$users = $allUsers | Where-Object {
    $_.SignInActivity -and
    $_.SignInActivity.LastSignInDateTime -and
    $_.SignInActivity.LastSignInDateTime -lt $cutoffDate
}

Write-Host "Found $($users.Count) users inactive for $inactivityDays days"

$processed = 0
foreach ($user in $users) {
    try {
        $userId = $user.Id
        
        Set-EntraUser -UserId $userId -AccountEnabled:$false -ErrorAction Stop
        Write-Host "Disabled account: $($user.DisplayName) ($($user.UserPrincipalName))"
        
        Add-EntraGroupMember -GroupId $targetGroupId -RefObjectId $userId -ErrorAction Stop
        Write-Host "Added to group: $($user.DisplayName)"
        
        $processed++
    } catch {
        Write-Warning "Failed to process user $($user.DisplayName): $_"
    }
}

Write-Host "Processed $processed users"
Write-Host "PowerShell timer trigger function completed!"