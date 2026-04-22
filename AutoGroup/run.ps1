param($Timer)

Import-Module Az

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
    Connect-AzAccount -Identity
    Write-Host "Connected to Azure"
} catch {
    Write-Error "Failed to connect to Azure: $_"
    exit 1
}

$group = Get-AzADGroup -ObjectId $targetGroupId -ErrorAction SilentlyContinue

if (-not $group) {
    Write-Error "Target group not found"
    exit 1
}

Write-Host "Target group: $($group.DisplayName) ($targetGroupId)"

$allUsers = Get-AzADUser -All -ErrorAction SilentlyContinue
$users = @()
foreach ($user in $allUsers) {
    if ($user.AccountEnabled -and $user.SignInActivity -and $user.SignInActivity.LastSignInDateTime) {
        $lastSignIn = [DateTime]::Parse($user.SignInActivity.LastSignInDateTime)
        if ($lastSignIn -lt $cutoffDate) {
            $users += $user
        }
    }
}

Write-Host "Found $($users.Count) users inactive for $inactivityDays days"

$processed = 0
foreach ($user in $users) {
    if ($user.AccountEnabled) {
        try {
            $userId = $user.Id
            
            Update-AzADUser -ObjectId $userId -AccountEnabled:$false -ErrorAction Stop
            Write-Host "Disabled account: $($user.DisplayName) ($($user.UserPrincipalName))"
            
            Add-AzADGroupMember -GroupObjectId $targetGroupId -MemberObjectId $userId -ErrorAction Stop
            Write-Host "Added to group: $($user.DisplayName)"
            
            $processed++
        } catch {
            Write-Warning "Failed to process user $($user.DisplayName): $_"
        }
    }
}

Write-Host "Processed $processed users"
Write-Host "PowerShell timer trigger function completed!"