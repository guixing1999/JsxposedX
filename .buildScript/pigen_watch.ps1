# 修复控制台和脚本编码
param(
    [switch]$Once
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$PIGEON_DIR = "lib/pigeons"
$DART_OUT_DIR = "lib/generated"
$KOTLIN_SRC_ROOT = "android/app/src/main/kotlin"
$BASE_PACKAGE = "com.jsxposed.x"

# 大小写无关地查找已存在文件,保留开发者手工指定的大小写
# (Windows FS 不敏感,Linux 敏感;不做这层兜底会在 Linux 旁边生成第二个重复文件)
function Get-PreservedCaseName {
    param($dir, $expectedName)
    if (-not (Test-Path $dir -PathType Container)) { return $expectedName }
    $existing = Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq $expectedName } |
        Select-Object -First 1
    if ($existing) { return $existing.Name }
    return $expectedName
}

function Run-Pigeon {
    param($file)
    
    $baseFull = (Get-Item $PIGEON_DIR).FullName
    $fileFull = (Get-Item $file).FullName
    $relativePath = $fileFull.Replace($baseFull, "").TrimStart("\").TrimStart("/")
    $relativeDir = [System.IO.Path]::GetDirectoryName($relativePath)
    
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $dart_out = "$DART_OUT_DIR/$($fileName).g.dart"

    if ($relativeDir -eq "." -or [string]::IsNullOrEmpty($relativeDir)) {
        $kotlin_pkg = $BASE_PACKAGE
    } else {
        $subPkg = $relativeDir.Replace('\', '.').Replace('/', '.')
        $kotlin_pkg = "$BASE_PACKAGE.$subPkg"
    }
    $kotlin_out_dir = "$KOTLIN_SRC_ROOT/$($kotlin_pkg.Replace('.', '/'))"

    $className = ""
    $fileName.Split('_') | ForEach-Object {
        if ($_) { $className += "$([char]::ToUpper($_[0]))$($_.Substring(1))" }
    }

    $kotlinFileName = Get-PreservedCaseName $kotlin_out_dir "${className}Native.g.kt"
    $implFileName   = Get-PreservedCaseName $kotlin_out_dir "${className}NativeImpl.kt"
    $kotlin_file = "$kotlin_out_dir/$kotlinFileName"
    $impl_file = "$kotlin_out_dir/$implFileName"

    Write-Host "`n>>> [Generating] $fileName" -ForegroundColor Cyan

    if (!(Test-Path $kotlin_out_dir)) { New-Item -ItemType Directory -Path $kotlin_out_dir | Out-Null }

    # 生成 Impl 模板 (如果不存在)
    if (!(Test-Path $impl_file)) {
        $impl_content = @"
package $kotlin_pkg

import android.content.Context

class ${className}NativeImpl(val context: Context) : ${className}Native {
    // TODO: 实现 ${className}Native 接口的方法
}
"@
        Set-Content -Path $impl_file -Value $impl_content -Encoding UTF8
        Write-Host ">>> Created Impl template: $impl_file (需要手动实现)" -ForegroundColor Yellow
    }

    dart run pigeon `
        --input "$file" `
        --dart_out "$dart_out" `
        --kotlin_out "$kotlin_file" `
        --kotlin_package "$kotlin_pkg"
}

Get-ChildItem -Path $PIGEON_DIR -Filter *.dart -Recurse | ForEach-Object { Run-Pigeon $_.FullName }

if ($Once) {
    Write-Host "`n>>> [Once] Initial codegen complete, skipping watcher." -ForegroundColor Green
    return
}

Write-Host "`n>>> [Watcher] Watching $PIGEON_DIR for changes..." -ForegroundColor Yellow
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = (Get-Item $PIGEON_DIR).FullName
$watcher.Filter = "*.dart"
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$action = {
    $path = $Event.SourceEventArgs.FullPath
    $name = $Event.SourceEventArgs.Name
    Write-Host "`n变动: $name" -ForegroundColor Magenta
    Run-Pigeon $path
}

Register-ObjectEvent $watcher "Changed" -Action $action | Out-Null
Register-ObjectEvent $watcher "Created" -Action $action | Out-Null

while ($true) { Start-Sleep -Seconds 5 }
