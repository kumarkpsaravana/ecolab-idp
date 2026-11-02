[Cmdletbinding()]
Param(
    [Parameter(Mandatory = $true)][string]$PathToFolder,
    [Parameter(Mandatory = $true)][string]$ClientId,
    [Parameter(Mandatory = $true)][string]$ClientSecret,
    [Parameter(Mandatory = $true)][string]$TenantId,
    [Parameter(Mandatory = $false)][string]$ConfigFile,
    [Parameter(Mandatory = $false)][string]$BackupPath
)

try{
    # --- Load config (exclusion list) ---
    $ExcludeList = @()
    if($ConfigFile -and (Test-Path $ConfigFile)){
        Write-Host "Loading config from $ConfigFile"
        $Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        if($Config.exclude){
            $ExcludeList = $Config.exclude
            Write-Host "Excluding policies: $($ExcludeList -join ', ')"
        }
    }

    # --- Get access token via client credentials ---
    Write-Host "Acquiring Access Token via client credentials"
    $TokenBody = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }
    $TokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method Post -Body $TokenBody -ContentType "application/x-www-form-urlencoded"
    $AccessToken = $TokenResponse.access_token

    $GraphHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $GraphHeaders.Add("Content-Type", 'application/xml; charset=utf-8')
    $GraphHeaders.Add("Authorization", 'Bearer ' + $AccessToken)

    # --- Load and parse policy files ---
    $PolicyFiles = Get-ChildItem -Path $PathToFolder -Filter "*.xml"
    $Policies = [collections.arraylist]@()

    foreach($PolicyFile in $PolicyFiles){
        Write-Host "Getting Content From $($PolicyFile.name)"
        $PolicyContent = Get-Content $PolicyFile.FullName -Encoding UTF8
        $PolicyXML = [xml]$PolicyContent

        if(!$PolicyXML.TrustFrameworkPolicy.PolicyId){
            throw "Policy XML is missing a PolicyId and is malformed: $($PolicyFile.name)"
        }

        $PolicyId = $PolicyXML.TrustFrameworkPolicy.PolicyId

        # Skip excluded policies
        if($PolicyId -in $ExcludeList){
            Write-Host "  Skipping excluded policy: $PolicyId" -ForegroundColor Yellow
            continue
        }

        [void]$Policies.Add($PolicyXML)
    }

    # --- Validate exclusions don't break dependencies ---
    foreach($Policy in $Policies){
        $BasePolicyId = $Policy.TrustFrameworkPolicy.BasePolicy.PolicyId
        if($BasePolicyId -and $BasePolicyId -in $ExcludeList){
            $PolicyId = $Policy.TrustFrameworkPolicy.PolicyId
            throw "Policy $PolicyId depends on excluded policy $BasePolicyId. Cannot proceed."
        }
    }

    # --- Sort by dependency order (parents first) ---
    Write-Host "Sorting Policy List For Upload"
    $SortedPolicies = [collections.arraylist]@()
    $UnsortedPolicies = $Policies.Clone()

    $MaxIterations = $UnsortedPolicies.Count * $UnsortedPolicies.Count
    $Iteration = 0

    while($UnsortedPolicies){
        $Iteration++
        if($Iteration -gt $MaxIterations){
            $Remaining = ($UnsortedPolicies | ForEach-Object { $_.TrustFrameworkPolicy.PolicyId }) -join ', '
            throw "Could not resolve dependency order. Remaining policies: $Remaining"
        }

        foreach($Policy in $UnsortedPolicies.clone()){
            $PolicyId = $Policy.TrustFrameworkPolicy.PolicyId
            $BasePolicyId = $Policy.TrustFrameworkPolicy.BasePolicy.PolicyId

            if($BasePolicyId){
                if($BasePolicyId -in $SortedPolicies.TrustFrameworkPolicy.PolicyId){
                    [void]$SortedPolicies.Add($Policy)
                    $UnsortedPolicies.Remove($Policy)
                } else {
                    if($BasePolicyId -notin $Policies.TrustFrameworkPolicy.PolicyId){
                        # Base policy is external (not in this folder) — safe to proceed
                        [void]$SortedPolicies.Add($Policy)
                        $UnsortedPolicies.Remove($Policy)
                    }
                }
            } else {
                [void]$SortedPolicies.Add($Policy)
                $UnsortedPolicies.Remove($Policy)
            }
        }
    }

    Write-Host "Upload order:"
    for($i = 0; $i -lt $SortedPolicies.Count; $i++){
        Write-Host "  $($i + 1). $($SortedPolicies[$i].TrustFrameworkPolicy.PolicyId)"
    }

    # --- Download backups of current policies ---
    $BackedUpPolicies = [collections.arraylist]@()

    if($BackupPath){
        if(!(Test-Path $BackupPath)){
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        }

        Write-Host "`nDownloading backups of current policies"
        $DownloadHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $DownloadHeaders.Add("Accept", 'application/xml')
        $DownloadHeaders.Add("Authorization", 'Bearer ' + $AccessToken)

        foreach($Policy in $SortedPolicies){
            $PolicyId = $Policy.TrustFrameworkPolicy.PolicyId
            $BackupFile = Join-Path $BackupPath "$PolicyId.xml"
            $GraphURI = "https://graph.microsoft.com/beta/trustframework/policies/$PolicyId/`$value"

            try{
                $ExistingPolicy = Invoke-RestMethod -Uri $GraphURI -Method Get -Headers $DownloadHeaders

                if($ExistingPolicy -is [xml]){
                    $ExistingPolicy.OuterXml | Set-Content -Path $BackupFile -Encoding UTF8
                } else {
                    $ExistingPolicy | Set-Content -Path $BackupFile -Encoding UTF8
                }

                [void]$BackedUpPolicies.Add($PolicyId)
                Write-Host "  Backed up: $PolicyId"
            } catch {
                $StatusCode = $_.Exception.Response.StatusCode.value__
                if($StatusCode -eq 404){
                    Write-Host "  No existing policy to back up: $PolicyId (new policy)" -ForegroundColor Yellow
                } else {
                    Write-Host "  WARNING: Failed to back up $PolicyId (HTTP $StatusCode)" -ForegroundColor Red
                    throw "Cannot proceed without backup of $PolicyId. Aborting."
                }
            }
        }
    }

    # --- Upload policies in order ---
    Write-Host "`nUploading Policies"
    $UploadedPolicies = [collections.arraylist]@()

    foreach($Policy in $SortedPolicies){
        $PolicyId = $Policy.TrustFrameworkPolicy.PolicyId
        $PolicyContent = $Policy.OuterXml
        $PolicyBytes = [System.Text.Encoding]::UTF8.GetBytes($PolicyContent)
        $GraphURI = "https://graph.microsoft.com/beta/trustframework/policies/$PolicyId/`$value"

        try{
            Invoke-RestMethod -Uri $GraphURI -Method Put -Body $PolicyBytes -Headers $GraphHeaders | Out-Null
            [void]$UploadedPolicies.Add($PolicyId)
            Write-Host "  Uploaded: $PolicyId" -ForegroundColor Green
        } catch {
            Write-Host "  FAILED: $PolicyId" -ForegroundColor Red
            Write-Host "  Error: $_" -ForegroundColor Red

            if($_.Exception.Response){
                try{
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = [System.IO.StreamReader]::new($stream)
                    $reader.BaseStream.Position = 0
                    $reader.DiscardBufferedData()
                    $body = $reader.ReadToEnd()
                    $reader.Close()

                    $json = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if($json.error){
                        Write-Host "  Code: $($json.error.code)" -ForegroundColor Red
                        Write-Host "  Message: $($json.error.message)" -ForegroundColor Red
                    } else {
                        Write-Host "  Response: $body" -ForegroundColor Red
                    }
                } catch {}
            }

            # --- Rollback uploaded policies ---
            if($BackupPath -and $UploadedPolicies.Count -gt 0){
                Write-Host "`nRolling back $($UploadedPolicies.Count) uploaded policies..." -ForegroundColor Yellow

                foreach($RollbackPolicyId in $UploadedPolicies){
                    $BackupFile = Join-Path $BackupPath "$RollbackPolicyId.xml"

                    if(Test-Path $BackupFile){
                        $RollbackURI = "https://graph.microsoft.com/beta/trustframework/policies/$RollbackPolicyId/`$value"
                        try{
                            $RollbackContent = Get-Content $BackupFile -Raw -Encoding UTF8
                            $RollbackBytes = [System.Text.Encoding]::UTF8.GetBytes($RollbackContent)
                            Invoke-RestMethod -Uri $RollbackURI -Method Put -Body $RollbackBytes -Headers $GraphHeaders | Out-Null
                            Write-Host "  Rolled back: $RollbackPolicyId" -ForegroundColor Green
                        } catch {
                            Write-Host "  ROLLBACK FAILED: $RollbackPolicyId - $_" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "  No backup file for $RollbackPolicyId (was a new policy, skipping rollback)" -ForegroundColor Yellow
                    }
                }
            } elseif($UploadedPolicies.Count -gt 0) {
                Write-Host "`nWARNING: No backup path provided, cannot rollback $($UploadedPolicies.Count) uploaded policies" -ForegroundColor Red
            }

            throw "Deployment failed at $PolicyId. See above for rollback status."
        }
    }

    # --- Re-download and diff uploaded policies ---
    $AddedPolicies = [collections.arraylist]@()
    $ModifiedPolicies = [collections.arraylist]@()
    $UnchangedPolicies = [collections.arraylist]@()

    if($BackupPath -and $UploadedPolicies.Count -gt 0){
        $PostUploadPath = Join-Path $BackupPath "post-upload"
        if(!(Test-Path $PostUploadPath)){
            New-Item -ItemType Directory -Path $PostUploadPath -Force | Out-Null
        }

        Write-Host "`nDownloading policies after upload for comparison"
        foreach($PolicyId in $UploadedPolicies){
            $GraphURI = "https://graph.microsoft.com/beta/trustframework/policies/$PolicyId/`$value"
            $PostFile = Join-Path $PostUploadPath "$PolicyId.xml"

            try{
                $PostPolicy = Invoke-RestMethod -Uri $GraphURI -Method Get -Headers $DownloadHeaders
                if($PostPolicy -is [xml]){
                    $PostPolicy.OuterXml | Set-Content -Path $PostFile -Encoding UTF8
                } else {
                    $PostPolicy | Set-Content -Path $PostFile -Encoding UTF8
                }
            } catch {
                Write-Host "  WARNING: Could not download $PolicyId after upload" -ForegroundColor Yellow
                continue
            }

            $BackupFile = Join-Path $BackupPath "$PolicyId.xml"
            if(!(Test-Path $BackupFile)){
                [void]$AddedPolicies.Add($PolicyId)
            } else {
                $beforeLines = Get-Content $BackupFile
                $afterLines = Get-Content $PostFile
                $diff = Compare-Object $beforeLines $afterLines
                if($diff){
                    [void]$ModifiedPolicies.Add(@{ Id = $PolicyId; Diff = $diff })
                } else {
                    [void]$UnchangedPolicies.Add($PolicyId)
                }
            }
        }

        Write-Host "`n--- Change Summary ---" -ForegroundColor Cyan

        if($AddedPolicies.Count -gt 0){
            Write-Host "Added ($($AddedPolicies.Count)):" -ForegroundColor Green
            foreach($p in $AddedPolicies){ Write-Host "  + $p" -ForegroundColor Green }
        }

        if($ModifiedPolicies.Count -gt 0){
            Write-Host "Modified ($($ModifiedPolicies.Count)):" -ForegroundColor Yellow
            foreach($entry in $ModifiedPolicies){
                Write-Host "  ~ $($entry.Id)" -ForegroundColor Yellow
                foreach($change in $entry.Diff){
                    if($change.SideIndicator -eq "<="){
                        Write-Host "      - $($change.InputObject)" -ForegroundColor Red
                    } else {
                        Write-Host "      + $($change.InputObject)" -ForegroundColor Green
                    }
                }
            }
        }

        if($UnchangedPolicies.Count -gt 0){
            Write-Host "Unchanged ($($UnchangedPolicies.Count)):" -ForegroundColor DarkGray
            foreach($p in $UnchangedPolicies){ Write-Host "  = $p" -ForegroundColor DarkGray }
        }
    }

    # --- Summary ---
    Write-Host "`n--- Deployment Summary ---" -ForegroundColor Cyan
    Write-Host "Policies uploaded: $($UploadedPolicies.Count)" -ForegroundColor Green
    foreach($p in $UploadedPolicies){ Write-Host "  - $p" }

    if($ExcludeList.Count -gt 0){
        Write-Host "Policies excluded: $($ExcludeList.Count)" -ForegroundColor Yellow
        foreach($p in $ExcludeList){ Write-Host "  - $p" }
    }

    if($BackupPath){
        Write-Host "Backups saved to: $BackupPath"
        Write-Host "Post-upload saved to: $PostUploadPath"
    }

} catch {
    Write-Host "`nDeployment Error:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if($_.Exception.Response){
        try{
            $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $streamReader.BaseStream.Position = 0
            $streamReader.DiscardBufferedData()
            $errResp = $streamReader.ReadToEnd()
            $streamReader.Close()
            Write-Host $errResp -ForegroundColor Red
        } catch {}
    }

    exit 1
}

exit 0
