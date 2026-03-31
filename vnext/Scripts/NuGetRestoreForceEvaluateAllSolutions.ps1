param(
    [switch] $SkipLockDeletion
)

[string] $RepoRoot = Resolve-Path "$PSScriptRoot\..\.."

$StartingLocation = Get-Location
Set-Location -Path $RepoRoot

try
{
    if (-not $SkipLockDeletion) {
        # Delete existing lock files
        $existingLockFiles = (Get-ChildItem -File -Recurse -Path $RepoRoot -Filter *.lock.json)
        $existingLockFiles | Foreach-Object {
            Write-Host Deleting $_.FullName
            Remove-Item $_.FullName
        }
    }

    # Solutions that fail NuGet restore due to project type incompatibilities (e.g., WAP + native)
    $excludedSolutions = @("playground-win32-packaged.sln")

    $packagesSolutions = @(Get-ChildItem -File -Recurse -Path $RepoRoot\packages -Include *.sln,*.slnf) | Where-Object { !$_.FullName.Contains('node_modules') -and !$_.FullName.Contains('e2etest') -and ($excludedSolutions -notcontains $_.Name) }
    $vnextSolutions = @(Get-ChildItem -File -Path $RepoRoot\vnext\* -Include *.sln,*.slnf)

    # Run all solutions with their defaults
    $($packagesSolutions; $vnextSolutions) | Foreach-Object {
        Write-Host Restoring $_.FullName with defaults
        & msbuild /t:Restore /p:RestoreForceEvaluate=true $_.FullName
    }

    # Re-run solutions that build with UseExperimentalWinUI3
    # Note: ReactWindows-Desktop.sln is NOT included here because ExperimentalFeatures.props
    # already sets UseExperimentalWinUI3=false for SolutionName=ReactWindows-Desktop.
    $experimentalSolutions = @("playground-composition.sln", "Microsoft.ReactNative.sln", "Microsoft.ReactNative.CppOnly.slnf");
    $($packagesSolutions; $vnextSolutions) | Where-Object { $experimentalSolutions -contains $_.Name } | Foreach-Object {
        Write-Host Restoring $_.FullName with UseExperimentalWinUI3=true
        & msbuild /t:Restore /p:RestoreForceEvaluate=true /p:UseExperimentalWinUI3=true $_.FullName
    }

    # Re-run solutions that build with Chakra
    $chakraSolutions = @("ReactUWPTestApp.sln", "integrationtest.sln");
    $($packagesSolutions; $vnextSolutions) | Where-Object { $chakraSolutions -contains $_.Name } | Foreach-Object {
        Write-Host Restoring $_.FullName with UseHermes=false
        & msbuild /t:Restore /p:RestoreForceEvaluate=true /p:UseHermes=false $_.FullName
    }
}
finally
{
    Set-Location -Path "$StartingLocation"
}
