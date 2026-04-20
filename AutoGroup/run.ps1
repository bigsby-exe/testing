param($Timer)

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

$cutoffDate = (Get-Date).AddDays(-$inactivityDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
    Connect-MgGraph -Scopes "User.Read.All", "Group.ReadWrite.All" -NoWelcome
    Write-Host "Connected to Microsoft Graph"
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

$group = Get-MgGroup -GroupId $targetGroupId -ErrorAction SilentlyContinue

if (-not $group) {
    Write-Error "Target group not found"
    exit 1
}

Write-Host "Target group: $($group.DisplayName) ($targetGroupId)"

$users = Get-MgUser -All -Property "id,displayName,userPrincipalName,signInActivity,accountEnabled" -Filter "signInActivity/lastSignInDateTime le $cutoffDate" -ErrorAction SilentlyContinue

if (-not $users) {
    $users = @()
    $allUsers = Get-MgUser -All -Property "id,displayName,userPrincipalName,signInActivity,accountEnabled" -ErrorAction SilentlyContinue
    foreach ($user in $allUsers) {
        if ($user.SignInActivity -and $user.SignInActivity.LastSignInDateTime) {
            $lastSignIn = [DateTime]::Parse($user.SignInActivity.LastSignInDateTime)
            if ($lastSignIn -lt (Get-Date).AddDays(-$inactivityDays)) {
                $users += $user
            }
        }
    }
}

Write-Host "Found $($users.Count) users inactive for $inactivityDays days"

$processed = 0
foreach ($user in $users) {
    if ($user.AccountEnabled) {
        try {
            $userId = $user.Id
            
            Update-MgUser -UserId $userId -AccountEnabled:$false -ErrorAction Stop
            Write-Host "Disabled account: $($user.DisplayName) ($($user.UserPrincipalName))"
            
            $memberParams = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
            }
            New-MgGroupMember -GroupId $targetGroupId -BodyParameter $memberParams -ErrorAction Stop
            Write-Host "Added to group: $($user.DisplayName)"
            
            $processed++
        } catch {
            Write-Warning "Failed to process user $($user.DisplayName): $_"
        }
    }
}

Write-Host "Processed $processed users"
Write-Host "PowerShell timer trigger function completed!"