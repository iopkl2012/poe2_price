param(
    [string]$Poe2Dir = "",
    [string]$RestoreZip = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot "poe2_patch_common.ps1")

$CodeToolsRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($env:POE2_PATCH_ROOT)) {
    $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}
else {
    $RepoRoot = (Resolve-Path -LiteralPath $env:POE2_PATCH_ROOT).Path
}
Set-Location -LiteralPath $RepoRoot

if ([string]::IsNullOrWhiteSpace($Poe2Dir)) {
    $Poe2Dir = (Split-Path -Parent $RepoRoot)
}
$Poe2Dir = (Resolve-Path -LiteralPath $Poe2Dir).Path

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Assert-File {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Name`: $Path"
    }
}

function Test-BaseItemsLookPatched {
    param([string]$SourceDat)

    $TempCsv = Join-Path $env:TEMP ([string]::Concat("poe2_price_restore_", [Guid]::NewGuid().ToString("N"), ".csv"))
    try {
        $Python = Ensure-PythonRequests -RepoRoot $RepoRoot
        $ExportScript = Join-Path $CodeToolsRoot "poe2_name_price_patch.py"
        & $Python $ExportScript export --source $SourceDat --output $TempCsv *> $null
        if ($LASTEXITCODE -ne 0) {
            return $true
        }
        $Rows = Import-Csv -LiteralPath $TempCsv -Encoding UTF8
        return [bool]($Rows | Where-Object { $_.name -match '=[0-9]+(?:\.[0-9]+)?[DE]$' } | Select-Object -First 1)
    }
    finally {
        if (Test-Path -LiteralPath $TempCsv -PathType Leaf) {
            Remove-Item -LiteralPath $TempCsv -Force
        }
    }
}

function New-BaseItemRestoreZip {
    param(
        [string]$SourceDat,
        [string]$OutputZip
    )

    Assert-File $SourceDat "clean BaseItemTypes.datc64"
    if (Test-BaseItemsLookPatched $SourceDat) {
        throw "Cached BaseItemTypes looks patched. Refusing to build a restore zip from it."
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $OutputDir = Split-Path -Parent $OutputZip
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    if (Test-Path -LiteralPath $OutputZip -PathType Leaf) {
        Remove-Item -LiteralPath $OutputZip -Force
    }

    $Archive = [System.IO.Compression.ZipFile]::Open($OutputZip, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $Archive,
            $SourceDat,
            "data/balance/traditional chinese/baseitemtypes.datc64",
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
    finally {
        $Archive.Dispose()
    }
}

function Assert-RestoreZip {
    param([string]$Path)

    Assert-File $Path "restore zip"
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $Entry = $Archive.GetEntry("data/balance/traditional chinese/baseitemtypes.datc64")
        if ($null -eq $Entry) {
            throw "Restore zip does not contain data/balance/traditional chinese/baseitemtypes.datc64"
        }
    }
    finally {
        $Archive.Dispose()
    }
}

$GameMode = Get-Poe2GameMode -Poe2Dir $Poe2Dir
$ContentGgpk = Join-Path $Poe2Dir "Content.ggpk"
$Bundles2Paths = Get-Bundles2Paths -Poe2Dir $Poe2Dir
$BundledInstallerDir = Join-Path $RepoRoot (Get-Poe2PatchName "InstallerDir")
$BundledPatchDll = Join-Path $BundledInstallerDir "PatchBundledGGPK3.dll"
$BundledPatchRuntimeConfig = Join-Path $BundledInstallerDir "PatchBundledGGPK3.runtimeconfig.json"
$BundledBundlePatchExe = Join-Path $BundledInstallerDir "PatchBundle3.exe"
$BundledBundleExtractorExe = Join-Path $BundledInstallerDir "BundleExtractor\BundleExtractor.exe"
$BundledOodleDll = Join-Path $BundledInstallerDir "BundleExtractor\oo2core.dll"
$RestoreZipName = Get-Poe2PatchName "RestorePatchZip"
$RestoreOutDir = Join-Path $RepoRoot "output\restore"
$RestoreOutZip = Join-Path $RestoreOutDir $RestoreZipName
$PatchFolderRestoreZip = Join-Path $RepoRoot $RestoreZipName
$GameRootRestoreZip = Join-Path $Poe2Dir $RestoreZipName
$CleanDat = Join-Path $RepoRoot "output\dat_files_latest\data\data_balance_traditional chinese_baseitemtypes.datc64"

Write-Host "POE2 price patch restore" -ForegroundColor Green
Write-Host "Game dir : $Poe2Dir"
Write-Host "Patch dir: $RepoRoot"
Write-Host "Mode     : $GameMode" -ForegroundColor Cyan

if ($GameMode -eq "GGPK") {
    Assert-File $ContentGgpk "Content.ggpk"
    Assert-File $BundledPatchDll "PatchBundledGGPK3.dll"
    Assert-File $BundledPatchRuntimeConfig "PatchBundledGGPK3.runtimeconfig.json"
}
else {
    # Bundles2 (Steam/Epic) 模式
    Assert-File $Bundles2Paths.IndexBin "Bundles2 _.index.bin"
    # 检查工具
    if (-not (Test-Path -LiteralPath $BundledBundleExtractorExe -PathType Leaf)) {
        $BundledBundleExtractorExe = Join-Path $CodeToolsRoot "BundleExtractor\BundleExtractor.exe"
    }
    if (-not (Test-Path -LiteralPath $BundledBundleExtractorExe -PathType Leaf)) {
        throw "Missing BundleExtractor.exe: $BundledBundleExtractorExe"
    }
    if (-not (Test-Path -LiteralPath $BundledOodleDll -PathType Leaf)) {
        $BundledOodleDll = Join-Path $CodeToolsRoot "BundleExtractor\oo2core.dll"
    }
    if (-not (Test-Path -LiteralPath $BundledOodleDll -PathType Leaf)) {
        throw "Missing oo2core.dll: $BundledOodleDll"
    }
}
$Dotnet = Ensure-DotNet8Runtime -RepoRoot $RepoRoot

function Ensure-CleanBaseItemForRestore {
    # 在 Bundles2 模式下，如果缓存的 clean 文件不存在或看起来已修补，需要重新提取
    
    if (Test-Path -LiteralPath $CleanDat -PathType Leaf) {
        if (-not (Test-BaseItemsLookPatched $CleanDat)) {
            return $CleanDat
        }
        Write-Host "Cached BaseItemTypes looks patched. Re-extracting from bundle..." -ForegroundColor Yellow
    }
    
    # 需要从 bundle 重新提取
    Write-Step "Extract clean BaseItemTypes from Bundles2"
    
    $ExtractDir = Split-Path -Parent $CleanDat
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    
    # 确保 oo2core.dll 在 BundleExtractor 旁边
    $ExtractorDir = Split-Path -Parent $BundledBundleExtractorExe
    $ExtractorOodle = Join-Path $ExtractorDir "oo2core.dll"
    if (-not (Test-Path -LiteralPath $ExtractorOodle -PathType Leaf) -and (Test-Path -LiteralPath $BundledOodleDll -PathType Leaf)) {
        Copy-Item -LiteralPath $BundledOodleDll -Destination $ExtractorOodle -Force
    }
    
    Write-Host "Extracting from: $($Bundles2Paths.IndexBin)"
    Write-Host "File: $($Bundles2Paths.TcBaseItems)"
    Write-Host "Output: $CleanDat"
    
    & $BundledBundleExtractorExe $Bundles2Paths.IndexBin $Bundles2Paths.TcBaseItems $CleanDat
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract clean BaseItemTypes. Exit code: $LASTEXITCODE"
    }
    
    # 验证提取的文件
    if (Test-BaseItemsLookPatched $CleanDat) {
        throw "Extracted BaseItemTypes still looks patched. Something is wrong."
    }
    
    return $CleanDat
}

if ([string]::IsNullOrWhiteSpace($RestoreZip)) {
    # 尝试查找现有的还原补丁
    $Candidates = @($PatchFolderRestoreZip, $RestoreOutZip, $GameRootRestoreZip)
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $RestoreZip = (Resolve-Path -LiteralPath $Candidate).Path
            break
        }
    }
    
    # 如果没有找到还原补丁，创建一个
    if ([string]::IsNullOrWhiteSpace($RestoreZip)) {
        Write-Step "Build restore zip from clean BaseItemTypes"
        
        if ($GameMode -eq "GGPK") {
            New-BaseItemRestoreZip $CleanDat $RestoreOutZip
        }
        else {
            # Bundles2 模式：先确保有 clean 的文件
            $CleanSource = Ensure-CleanBaseItemForRestore
            New-BaseItemRestoreZip $CleanSource $RestoreOutZip
        }
        $RestoreZip = $RestoreOutZip
    }
}
else {
    $RestoreZip = (Resolve-Path -LiteralPath $RestoreZip).Path
}

Assert-RestoreZip $RestoreZip

if ($RestoreZip -ne $PatchFolderRestoreZip) {
    Copy-Item -LiteralPath $RestoreZip -Destination $PatchFolderRestoreZip -Force
}
Copy-Item -LiteralPath $RestoreZip -Destination $GameRootRestoreZip -Force

if ($GameMode -eq "GGPK") {
    Write-Step "Install restore patch into Content.ggpk"
    Write-Host "Installer: $BundledPatchDll"
    Write-Host "GGPK     : $ContentGgpk"
    Write-Host "Patch    : $GameRootRestoreZip"

    Push-Location -LiteralPath $BundledInstallerDir
    try {
        $InstallerOutput = "" | & $Dotnet $BundledPatchDll $ContentGgpk $GameRootRestoreZip 2>&1
        $InstallerOutput | ForEach-Object { Write-Host $_ }
        $InstallerText = ($InstallerOutput | Out-String)
        if ($LASTEXITCODE -ne 0 -or $InstallerText -match 'Exception|Unhandled|錯誤|错误|失敗|失败') {
            throw "Restore installer failed. Exit code: $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ""
    Write-Host "Restore installed into Content.ggpk." -ForegroundColor Green
}
else {
    Write-Step "Install restore patch into Bundles2 using PatchBundle3"
    
    # 检查 PatchBundle3.exe
    if (-not (Test-Path -LiteralPath $BundledBundlePatchExe -PathType Leaf)) {
        $BundledBundlePatchExe = Join-Path $CodeToolsRoot "PatchBundle3.exe"
    }
    if (-not (Test-Path -LiteralPath $BundledBundlePatchExe -PathType Leaf)) {
        throw "Missing PatchBundle3.exe: $BundledBundlePatchExe"
    }
    
    Write-Host "Bundle3: $($BundledBundlePatchExe)"
    Write-Host "Index  : $($Bundles2Paths.IndexBin)"
    Write-Host "Patch  : $GameRootRestoreZip"
    
    & $BundledBundlePatchExe $Bundles2Paths.IndexBin $GameRootRestoreZip
    if ($LASTEXITCODE -ne 0) {
        throw "PatchBundle3 restore failed. Exit code: $LASTEXITCODE"
    }
    
    Write-Host "Restore installed into Bundles2." -ForegroundColor Green
}
