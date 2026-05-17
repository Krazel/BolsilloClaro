param(
  [string]$Repo = "Krazel/BolsilloClaro",
  [string]$WorkflowName = "Build unsigned iOS IPA",
  [string]$ArtifactName = "BolsilloClaro-unsigned-ipa",
  [string]$AppVersion = "1.0",
  [string]$Commit = "",
  [int]$IntervalSeconds = 60,
  [int]$MaxAttempts = 30
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$artifactDir = Join-Path $root "artifact"
$oldDir = Join-Path $artifactDir "old"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
New-Item -ItemType Directory -Force -Path $oldDir | Out-Null

if ([string]::IsNullOrWhiteSpace($Commit)) {
  $Commit = (git -C $root rev-parse HEAD).Trim()
}

$headers = @{
  "User-Agent" = "BolsilloClaro-Artifact-Watcher"
  "Accept" = "application/vnd.github+json"
}

if ($env:GITHUB_TOKEN) {
  $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
}

function Get-LatestRun {
  $runsUrl = "https://api.github.com/repos/$Repo/actions/runs?per_page=20"
  $runs = Invoke-RestMethod -Uri $runsUrl -Headers $headers
  return $runs.workflow_runs |
    Where-Object { $_.name -eq $WorkflowName -and ($_.head_sha -eq $Commit -or $_.head_sha.StartsWith($Commit)) } |
    Sort-Object created_at -Descending |
    Select-Object -First 1
}

function Move-CurrentArtifacts {
  Get-ChildItem -LiteralPath $artifactDir |
    Where-Object { $_.Name -ne "old" -and $_.Name -ne ".gitkeep" -and $_.Name -like "*iPhone*.ipa" } |
    ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $oldDir -Force }
}

function Keep-OnlyCurrentArtifact {
  param([string]$CurrentPath)

  Get-ChildItem -LiteralPath $artifactDir |
    Where-Object { $_.Name -ne "old" -and $_.Name -ne ".gitkeep" -and $_.Name -like "*iPhone*.ipa" -and $_.FullName -ne $CurrentPath } |
    ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination $oldDir -Force }
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt += 1) {
  $run = Get-LatestRun

  if ($null -eq $run) {
    Write-Host "[$attempt/$MaxAttempts] Aun no hay run para $Commit."
  } elseif ($run.status -ne "completed") {
    Write-Host "[$attempt/$MaxAttempts] Build en curso: $($run.status)."
  } elseif ($run.conclusion -eq "success") {
    Write-Host "Build correcta: $($run.html_url)"
    $runDir = Join-Path $oldDir "BolsilloClaro-native-ipa-run-$($run.id)"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $latestPath = Join-Path $artifactDir "BolsilloClaro-iPhone-latest.ipa"
    $versionedPath = Join-Path $artifactDir "BolsilloClaro-iPhone-v$AppVersion-build-$($run.run_number).ipa"
    $latestVersionedPath = Join-Path $artifactDir "BolsilloClaro-iPhone-latest-v$AppVersion-build-$($run.run_number).ipa"
    $releaseUrl = "https://github.com/$Repo/releases/download/latest-ipa/BolsilloClaro-iPhone-latest.ipa"

    Move-CurrentArtifacts
    try {
      Invoke-WebRequest -Uri $releaseUrl -Headers @{ "User-Agent" = "BolsilloClaro-Artifact-Watcher" } -OutFile $latestPath
      Copy-Item -LiteralPath $latestPath -Destination $versionedPath -Force
      Copy-Item -LiteralPath $latestPath -Destination $latestVersionedPath -Force
      Keep-OnlyCurrentArtifact -CurrentPath $latestVersionedPath
    } catch {
      if (-not $env:GITHUB_TOKEN) {
        throw "La build termino, pero la release latest-ipa aun no esta disponible o requiere token. Reintenta en un minuto."
      }

      $artifactsUrl = "https://api.github.com/repos/$Repo/actions/runs/$($run.id)/artifacts"
      $artifacts = Invoke-RestMethod -Uri $artifactsUrl -Headers $headers
      $artifact = $artifacts.artifacts | Where-Object { $_.name -eq $ArtifactName -and -not $_.expired } | Select-Object -First 1
      if ($null -eq $artifact) {
        throw "Build correcta, pero no se encontro el artifact $ArtifactName."
      }
      $zipPath = Join-Path $runDir "BolsilloClaro-unsigned-ipa-run-$($run.id).zip"
      $ipaPath = Join-Path $runDir "BolsilloClaro-unsigned.ipa"
      Invoke-WebRequest -Uri $artifact.archive_download_url -Headers $headers -OutFile $zipPath
      Expand-Archive -Path $zipPath -DestinationPath $runDir -Force
      if (!(Test-Path -LiteralPath $ipaPath)) {
        throw "No se encontro BolsilloClaro-unsigned.ipa dentro del artifact."
      }
      Copy-Item -LiteralPath $ipaPath -Destination $latestPath -Force
      Copy-Item -LiteralPath $ipaPath -Destination $versionedPath -Force
      Copy-Item -LiteralPath $ipaPath -Destination $latestVersionedPath -Force
      Keep-OnlyCurrentArtifact -CurrentPath $latestVersionedPath
    }

    Write-Host "IPA actual: $latestVersionedPath"
    Write-Host "Copias anteriores movidas a: $oldDir"
    exit 0
  } else {
    Write-Error "Build fallida: $($run.conclusion) $($run.html_url)"
    exit 1
  }

  Start-Sleep -Seconds $IntervalSeconds
}

Write-Error "No se completo la build tras $MaxAttempts intentos."
exit 2
